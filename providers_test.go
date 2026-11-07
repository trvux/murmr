package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func env(kv map[string]string) func(string) string { return func(k string) string { return kv[k] } }

func TestProviderTableIsConsistent(t *testing.T) {
	ids, keys := map[string]bool{}, map[string]bool{}
	for _, p := range providers {
		if p.ID == "" || p.Title == "" || p.Protocol == "" {
			t.Errorf("incomplete entry %+v", p)
		}
		if ids[p.ID] {
			t.Errorf("duplicate id %s", p.ID)
		}
		ids[p.ID] = true
		if p.KeyEnv != "" {
			if keys[p.KeyEnv] {
				t.Errorf("two providers share %s", p.KeyEnv)
			}
			keys[p.KeyEnv] = true
		}
		if p.NeedsKey && p.KeyEnv == "" {
			t.Errorf("%s needs a key but names no variable", p.ID)
		}
		if p.BaseURL == "" && p.BaseURLEnv == "" {
			t.Errorf("%s has no address and none can be given", p.ID)
		}
		if p.BaseURL != "" {
			if err := validateBaseURL(p.BaseURL); err != nil {
				t.Errorf("%s: built-in address rejected: %v", p.ID, err)
			}
		}
		if p.Tested && p.DefaultModel == "" {
			t.Errorf("%s is marked tested but has no default model", p.ID)
		}
	}
	if _, err := json.Marshal(providers); err != nil {
		t.Errorf("table must encode for the app: %v", err)
	}
}

func TestPickCleaner(t *testing.T) {
	name := func(c Cleaner) string {
		if c == nil {
			return "<nil>"
		}
		return c.Name()
	}
	both := env(map[string]string{"DEEPSEEK_API_KEY": "d", "ANTHROPIC_API_KEY": "a"})
	for _, tc := range []struct {
		mode string
		env  func(string) string
		want string
	}{
		{"", both, "deepseek"}, // automatic: first with a key
		{"", env(map[string]string{"ANTHROPIC_API_KEY": "a"}), "claude"},
		{"", env(map[string]string{"OPENAI_API_KEY": "o"}), "openai"},
		{"", env(nil), "<nil>"},
		{"claude", both, "claude"}, // explicit beats order
		{"claude", env(map[string]string{"DEEPSEEK_API_KEY": "d"}), "<nil>"}, // chosen but no key: off, not a silent switch
		{"none", both, "<nil>"},
		{"nonsense", both, "<nil>"},
		{"ollama", env(nil), "ollama"}, // no key needed, but only when asked for
		{"custom", env(nil), "<nil>"},  // no address yet
		{"custom", env(map[string]string{"CUSTOM_BASE_URL": "https://example.com/v1"}), "custom"},
		{"custom", env(map[string]string{"CUSTOM_BASE_URL": "http://example.com/v1"}), "<nil>"}, // plain http to another host
	} {
		if got := name(pickCleaner(tc.mode, tc.env, "sys")); got != tc.want {
			t.Errorf("mode %q: got %s, want %s", tc.mode, got, tc.want)
		}
	}
	if got := name(pickCleaner("", env(map[string]string{}), "s")); got != "<nil>" {
		t.Errorf("auto must never pick a keyless service, got %s", got)
	}
}

func TestConfigPrecedence(t *testing.T) {
	p, _ := lookupProvider("deepseek")
	if c := p.config(env(nil), nil); c.Model != "deepseek-flash" {
		t.Errorf("default model, got %q", c.Model)
	}
	if c := p.config(env(map[string]string{"DEEPSEEK_MODEL": "from-env"}), nil); c.Model != "from-env" {
		t.Errorf("env beats default, got %q", c.Model)
	}
	ov := parseOverrides(`{"deepseek":{"model":"from-app","baseURL":"https://evil.example"}}`)
	c := p.config(env(map[string]string{"DEEPSEEK_MODEL": "from-env"}), ov)
	if c.Model != "from-app" {
		t.Errorf("the app's choice beats the env, got %q", c.Model)
	}
	if c.BaseURL != "https://api.deepseek.com" {
		t.Errorf("a provider with a fixed address must ignore an override, got %q", c.BaseURL)
	}
	o, _ := lookupProvider("ollama")
	if c := o.config(env(nil), parseOverrides(`{"ollama":{"baseURL":"http://127.0.0.1:9999/v1"}}`)); c.BaseURL != "http://127.0.0.1:9999/v1" {
		t.Errorf("ollama's address can be changed, got %q", c.BaseURL)
	}
	if parseOverrides("not json") != nil {
		t.Error("bad override JSON should be ignored")
	}
}

func TestValidateBaseURL(t *testing.T) {
	for url, ok := range map[string]bool{
		"https://api.example.com/v1": true, "http://localhost:11434/v1": true, "http://127.0.0.1:1234/v1": true,
		"http://example.com/v1": false, "ftp://x.com": false, "": false, "not a url": false,
	} {
		if err := validateBaseURL(url); (err == nil) != ok {
			t.Errorf("%q: err %v, want ok=%v", url, err, ok)
		}
	}
}

// Both protocols and the per-service quirks, against a local server.
func TestCleanersSpeakTheirProtocol(t *testing.T) {
	var got struct {
		path, auth, xkey string
		body             map[string]any
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.path, got.auth, got.xkey = r.URL.Path, r.Header.Get("Authorization"), r.Header.Get("x-api-key")
		b, _ := io.ReadAll(r.Body)
		got.body = nil
		_ = json.Unmarshal(b, &got.body)
		if strings.HasSuffix(r.URL.Path, "/messages") {
			w.Write([]byte(`{"content":[{"text":" hi from claude "}]}`))
			return
		}
		w.Write([]byte(`{"choices":[{"message":{"content":" hi "}}]}`))
	}))
	defer srv.Close()
	ctx := context.Background()

	// DeepSeek: bearer key, and its own "thinking disabled" quirk
	ds, _ := lookupProvider("deepseek")
	out, err := newCleaner(ds, ProviderConfig{Key: "k", Model: "m", BaseURL: srv.URL}, "sys").Clean(ctx, "raw", "+x")
	if err != nil || out != "hi" || got.path != "/chat/completions" || got.auth != "Bearer k" || got.body["thinking"] == nil || got.body["temperature"] == nil {
		t.Errorf("deepseek: %q %v %+v", out, err, got)
	}

	// OpenAI: same protocol, but the temperature quirk removes the parameter
	oa, _ := lookupProvider("openai")
	if _, err := newCleaner(oa, ProviderConfig{Key: "k", Model: "m", BaseURL: srv.URL}, "s").Clean(ctx, "raw", ""); err != nil {
		t.Fatal(err)
	}
	if _, has := got.body["temperature"]; has || got.body["thinking"] != nil {
		t.Errorf("openai body should carry no temperature and no thinking: %+v", got.body)
	}

	// a keyless local service sends no Authorization header
	ol, _ := lookupProvider("ollama")
	if _, err := newCleaner(ol, ProviderConfig{Model: "m", BaseURL: srv.URL}, "s").Clean(ctx, "raw", ""); err != nil || got.auth != "" {
		t.Errorf("ollama: err %v auth %q", err, got.auth)
	}

	// Claude: its own endpoint and header
	cl, _ := lookupProvider("claude")
	out, err = newCleaner(cl, ProviderConfig{Key: "ak", Model: "cm", BaseURL: srv.URL}, "s").Clean(ctx, "raw", "")
	if err != nil || out != "hi from claude" || got.path != "/messages" || got.xkey != "ak" || got.body["model"] != "cm" {
		t.Errorf("claude: %q %v %+v", out, err, got)
	}

	// no model chosen yet (a service not yet verified): a clear error, no request
	got.path = ""
	if _, err := newCleaner(oa, ProviderConfig{Key: "k", BaseURL: srv.URL}, "s").Clean(ctx, "raw", ""); err == nil || got.path != "" {
		t.Errorf("empty model should fail before any request: err %v path %q", err, got.path)
	}
}
