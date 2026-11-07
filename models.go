package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ModelInfo is one model a provider says it serves, as the Settings window lists it.
type ModelInfo struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Created    string `json:"created,omitempty"` // RFC 3339, when the provider says
	Deprecated bool   `json:"deprecated"`        // still callable, but on its way out
}

// listModels asks a service which models it serves right now, newest first, so the app never needs a list that
// goes stale. A retired model is gone from the lists, so "old" here means deprecated-but-callable.
func listModels(ctx context.Context, p ProviderSpec, cfg ProviderConfig) ([]ModelInfo, error) {
	base := strings.TrimRight(cfg.BaseURL, "/")
	var url string
	if p.Protocol == protoAnthropic {
		url = base + "/models?limit=1000"
	} else {
		url = base + "/models"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	switch {
	case p.Protocol == protoAnthropic:
		req.Header.Set("x-api-key", cfg.Key)
		req.Header.Set("anthropic-version", "2023-06-01")
	case cfg.Key != "":
		req.Header.Set("Authorization", "Bearer "+cfg.Key)
	}

	var out struct {
		Data []struct {
			ID          string          `json:"id"`
			Name        string          `json:"name"`         // DeepSeek, OpenRouter
			DisplayName string          `json:"display_name"` // Anthropic
			Created     json.RawMessage `json:"created"`      // unix seconds (OpenAI style)
			CreatedAt   string          `json:"created_at"`   // RFC 3339 (Anthropic)
			Lifecycle   string          `json:"lifecycle"`
		} `json:"data"`
	}
	if err := doJSON(req, &out); err != nil {
		return nil, err
	}
	models := make([]ModelInfo, 0, len(out.Data))
	for _, m := range out.Data {
		id := strings.TrimPrefix(m.ID, "models/") // Gemini lists "models/<id>" but is called with "<id>"
		if id == "" || (p.chatModels && !isChatModel(id)) {
			continue
		}
		name := m.DisplayName
		if name == "" {
			name = m.Name
		}
		if name == "" || strings.HasPrefix(name, "models/") {
			name = id
		}
		created := m.CreatedAt
		if created == "" {
			if secs, err := strconv.ParseInt(strings.Trim(string(m.Created), `"`), 10, 64); err == nil && secs > 0 {
				created = time.Unix(secs, 0).UTC().Format(time.RFC3339)
			}
		}
		models = append(models, ModelInfo{ID: id, Name: name, Created: created, Deprecated: m.Lifecycle == "deprecated"})
	}
	// Newest first when dates are known; the sort is stable so a provider's own order survives otherwise.
	sort.SliceStable(models, func(i, j int) bool { return models[i].Created > models[j].Created })
	return models, nil
}

// isChatModel drops the models that cannot answer a chat request (embeddings, speech, images...). A heuristic on
// the id, used only for services whose list mixes kinds; "Dùng tên model khác" covers anything it hides.
func isChatModel(id string) bool {
	id = strings.ToLower(id)
	for _, word := range []string{"embed", "whisper", "tts", "dall-e", "moderation", "transcribe", "realtime", "audio", "imagen", "veo", "aqa", "image"} {
		if strings.Contains(id, word) {
			return false
		}
	}
	return true
}

// cmdModels prints a service's models as JSON, using the key from the environment (what the Settings window
// runs after a key is saved).
func cmdModels(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: murmr models <provider id> (see: murmr providers)")
	}
	p, ok := lookupProvider(args[0])
	if !ok {
		return fmt.Errorf("unknown provider %q (see: murmr providers)", args[0])
	}
	cfg := p.config(os.Getenv, parseOverrides(os.Getenv("MURMR_PROVIDER_CONFIG")))
	if !p.ready(cfg) {
		if p.NeedsKey && cfg.Key == "" {
			return fmt.Errorf("%s is not set", p.KeyEnv)
		}
		return fmt.Errorf("%s: no address set", p.ID)
	}
	if err := validateBaseURL(cfg.BaseURL); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	models, err := listModels(ctx, p, cfg)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(models)
}
