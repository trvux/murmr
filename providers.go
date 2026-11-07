package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
)

// Everything the engine knows about cleanup services lives in this one table. The Settings window does not
// hard-code a list: it asks `murmr providers` and draws what comes back, so adding a service is one entry here.
//
// There are only two wire protocols, so a provider is data plus (rarely) a small quirk:
//
//	protoOpenAI     POST {base}/chat/completions, Bearer key   (OpenAI, DeepSeek, Gemini, Kimi, OpenRouter, Ollama...)
//	protoAnthropic  POST {base}/messages, x-api-key            (Claude)
type Protocol string

const (
	protoOpenAI    Protocol = "openai"
	protoAnthropic Protocol = "anthropic"
)

// ProviderSpec describes one service. The exported fields are what the app receives as JSON.
type ProviderSpec struct {
	ID           string   `json:"id"` // what MURMR_CLEANUP and MURMR_FALLBACK take
	Title        string   `json:"title"`
	Blurb        string   `json:"blurb"`
	Protocol     Protocol `json:"protocol"`
	BaseURL      string   `json:"baseURL"` // default; "" when the user must supply one
	KeyEnv       string   `json:"keyEnv"`  // "" when the service takes no key
	ModelEnv     string   `json:"modelEnv"`
	BaseURLEnv   string   `json:"baseURLEnv"`   // set when the user may change the address
	DefaultModel string   `json:"defaultModel"` // "" until verified: the user then picks from the provider's list
	KeyURL       string   `json:"keyURL"`
	NeedsKey     bool     `json:"needsKey"`
	Local        bool     `json:"local"`  // runs on this machine: the text never leaves it
	Tested       bool     `json:"tested"` // checked by the author with a real key

	// quirks, not sent to the app
	tweak      func(body map[string]any) // adjusts the request body for this service
	chatModels bool                      // the model list mixes in embeddings, speech and image models: keep chat ones
}

// providers is ordered by preference for the automatic choice (see pickCleaner): the first one with a key wins.
var providers = []ProviderSpec{
	{
		ID: "deepseek", Title: "DeepSeek", Protocol: protoOpenAI, BaseURL: "https://api.deepseek.com",
		Blurb:  "Rẻ và nhanh. Tắt chế độ suy luận để trả lời trong vài giây.",
		KeyEnv: "DEEPSEEK_API_KEY", ModelEnv: "DEEPSEEK_MODEL", DefaultModel: "deepseek-flash",
		KeyURL: "https://platform.deepseek.com", NeedsKey: true, Tested: true,
		// Flash thinks by default; cleanup doesn't need it and it adds latency.
		tweak: func(b map[string]any) { b["thinking"] = map[string]string{"type": "disabled"} },
	},
	{
		ID: "claude", Title: "Claude (Anthropic)", Protocol: protoAnthropic, BaseURL: "https://api.anthropic.com/v1",
		Blurb:  "Dọn văn cần trả lời nhanh, nên model nhỏ (Haiku) thường hợp nhất.",
		KeyEnv: "ANTHROPIC_API_KEY", ModelEnv: "ANTHROPIC_MODEL", DefaultModel: "claude-haiku-4-5-20251001",
		KeyURL: "https://console.anthropic.com", NeedsKey: true, Tested: true,
	},
	{
		ID: "openai", Title: "OpenAI", Protocol: protoOpenAI, BaseURL: "https://api.openai.com/v1",
		Blurb:  "Chọn model nhỏ, không phải loại suy luận, để trả lời nhanh.",
		KeyEnv: "OPENAI_API_KEY", ModelEnv: "OPENAI_MODEL",
		KeyURL: "https://platform.openai.com/api-keys", NeedsKey: true, chatModels: true,
		// Newer models accept only the default temperature, so send none.
		tweak: func(b map[string]any) { delete(b, "temperature") },
	},
	{
		ID: "gemini", Title: "Gemini (Google)", Protocol: protoOpenAI, BaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
		Blurb:  "Dùng lớp tương thích OpenAI của Google. Chọn model Flash cho nhanh.",
		KeyEnv: "GEMINI_API_KEY", ModelEnv: "GEMINI_MODEL",
		KeyURL: "https://aistudio.google.com/apikey", NeedsKey: true, chatModels: true,
	},
	{
		ID: "kimi", Title: "Kimi (Moonshot)", Protocol: protoOpenAI, BaseURL: "https://api.moonshot.ai/v1",
		Blurb:  "Máy chủ quốc tế. Dùng bản Trung Quốc thì chọn Tuỳ chỉnh với https://api.moonshot.cn/v1.",
		KeyEnv: "MOONSHOT_API_KEY", ModelEnv: "MOONSHOT_MODEL",
		KeyURL: "https://platform.moonshot.ai", NeedsKey: true,
	},
	{
		ID: "openrouter", Title: "OpenRouter", Protocol: protoOpenAI, BaseURL: "https://openrouter.ai/api/v1",
		Blurb:  "Một khoá dùng được nhiều hãng (Claude, GPT, Gemini, Kimi...). Có thêm một bên trung gian nhìn thấy chữ.",
		KeyEnv: "OPENROUTER_API_KEY", ModelEnv: "OPENROUTER_MODEL",
		KeyURL: "https://openrouter.ai/keys", NeedsKey: true,
	},
	{
		ID: "ollama", Title: "Ollama (trên máy bạn)", Protocol: protoOpenAI, BaseURL: "http://localhost:11434/v1",
		Blurb:    "Chạy model ngay trên máy: chữ không rời máy, không cần khoá, không tốn tiền.",
		ModelEnv: "OLLAMA_MODEL", BaseURLEnv: "OLLAMA_BASE_URL",
		KeyURL: "https://ollama.com", Local: true,
	},
	{
		ID: "custom", Title: "Tuỳ chỉnh", Protocol: protoOpenAI,
		Blurb:  "Bất kỳ dịch vụ nào nói giao thức OpenAI. Dán địa chỉ gốc, ví dụ LM Studio: http://localhost:1234/v1.",
		KeyEnv: "CUSTOM_API_KEY", ModelEnv: "CUSTOM_MODEL", BaseURLEnv: "CUSTOM_BASE_URL",
	},
}

func lookupProvider(id string) (ProviderSpec, bool) {
	for _, p := range providers {
		if p.ID == id {
			return p, true
		}
	}
	return ProviderSpec{}, false
}

// providerTitle is a short name for notices: the title without its parenthesis ("Claude (Anthropic)" -> "Claude").
// Unknown ids come back as they are.
func providerTitle(id string) string {
	p, ok := lookupProvider(id)
	if !ok {
		return id
	}
	title, _, _ := strings.Cut(p.Title, " (")
	return title
}

// ProviderConfig is a provider's settings after the environment and the app's overrides are applied.
type ProviderConfig struct{ Key, Model, BaseURL string }

// overrides is what the app sends in MURMR_PROVIDER_CONFIG, e.g. {"openai":{"model":"...","baseURL":""}}.
// It beats the plain environment variables, which stay supported for people who run the engine from a terminal.
type overrides map[string]struct {
	Model   string `json:"model"`
	BaseURL string `json:"baseURL"`
}

func parseOverrides(raw string) overrides {
	var o overrides
	if raw != "" {
		_ = json.Unmarshal([]byte(raw), &o)
	}
	return o
}

func (p ProviderSpec) config(getenv func(string) string, ov overrides) ProviderConfig {
	cfg := ProviderConfig{Model: p.DefaultModel, BaseURL: p.BaseURL}
	if p.KeyEnv != "" {
		cfg.Key = getenv(p.KeyEnv)
	}
	if p.ModelEnv != "" && getenv(p.ModelEnv) != "" {
		cfg.Model = getenv(p.ModelEnv)
	}
	if p.BaseURLEnv != "" && getenv(p.BaseURLEnv) != "" {
		cfg.BaseURL = getenv(p.BaseURLEnv)
	}
	if o, ok := ov[p.ID]; ok {
		if o.Model != "" {
			cfg.Model = o.Model
		}
		if o.BaseURL != "" && p.BaseURLEnv != "" {
			cfg.BaseURL = o.BaseURL
		}
	}
	return cfg
}

// ready reports whether the service can be called at all: it has a key if it needs one, and an address.
func (p ProviderSpec) ready(cfg ProviderConfig) bool {
	return (!p.NeedsKey || cfg.Key != "") && cfg.BaseURL != ""
}

// validateBaseURL refuses an address that would send a key over plain http to another machine.
func validateBaseURL(raw string) error {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.Host == "" {
		return fmt.Errorf("%q is not a web address", raw)
	}
	switch u.Scheme {
	case "https":
		return nil
	case "http":
		switch u.Hostname() {
		case "localhost", "127.0.0.1", "::1":
			return nil
		}
		return fmt.Errorf("%s: plain http is only allowed for this machine (localhost); use https", u.Host)
	}
	return fmt.Errorf("%q: only http(s) addresses are supported", raw)
}

// cmdProviders prints the table as JSON: the app's source of truth for what services exist.
func cmdProviders() error {
	return json.NewEncoder(os.Stdout).Encode(providers)
}
