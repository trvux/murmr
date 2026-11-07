package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestListModelsAcrossProtocols(t *testing.T) {
	var auth, key, version, path string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth, key, version, path = r.Header.Get("Authorization"), r.Header.Get("x-api-key"), r.Header.Get("anthropic-version"), r.URL.Path
		switch r.URL.Path {
		case "/ds/models": // DeepSeek style: a name, no dates
			w.Write([]byte(`{"data":[{"id":"deepseek-flash","name":"DeepSeek-V4.1-Flash"},{"id":"deepseek-v4-pro"}]}`))
		case "/oa/models": // OpenAI style: unix dates, and models that cannot chat
			w.Write([]byte(`{"data":[
				{"id":"text-embedding-3-small","created":1700000000},
				{"id":"gpt-old","created":1600000000},
				{"id":"gpt-new","created":1800000000},
				{"id":"whisper-1","created":1500000000}]}`))
		case "/gem/models": // Gemini lists "models/<id>"
			w.Write([]byte(`{"data":[{"id":"models/gemini-flash"},{"id":"models/text-embedding-004"}]}`))
		case "/cl/models":
			w.Write([]byte(`{"data":[
				{"id":"claude-old","display_name":"Claude Old","created_at":"2025-01-01T00:00:00Z","lifecycle":"deprecated"},
				{"id":"claude-new","display_name":"Claude New","created_at":"2026-09-01T00:00:00Z","lifecycle":"active"}]}`))
		default:
			http.Error(w, "nope", 404)
		}
	}))
	defer srv.Close()
	ctx := context.Background()

	ds, err := listModels(ctx, ProviderSpec{ID: "deepseek", Protocol: protoOpenAI}, ProviderConfig{Key: "k1", BaseURL: srv.URL + "/ds"})
	if err != nil || len(ds) != 2 || auth != "Bearer k1" || ds[0].Name != "DeepSeek-V4.1-Flash" || ds[1].Name != "deepseek-v4-pro" {
		t.Errorf("deepseek: %+v %v auth %q (name falls back to id)", ds, err, auth)
	}

	oa, err := listModels(ctx, ProviderSpec{ID: "openai", Protocol: protoOpenAI, chatModels: true}, ProviderConfig{Key: "k", BaseURL: srv.URL + "/oa"})
	if err != nil || len(oa) != 2 || oa[0].ID != "gpt-new" || oa[1].ID != "gpt-old" {
		t.Errorf("openai should keep chat models, newest first: %+v %v", oa, err)
	}

	gem, _ := listModels(ctx, ProviderSpec{ID: "gemini", Protocol: protoOpenAI, chatModels: true}, ProviderConfig{Key: "k", BaseURL: srv.URL + "/gem"})
	if len(gem) != 1 || gem[0].ID != "gemini-flash" {
		t.Errorf("gemini should drop the models/ prefix and the embedding model: %+v", gem)
	}

	cl, err := listModels(ctx, ProviderSpec{ID: "claude", Protocol: protoAnthropic}, ProviderConfig{Key: "k2", BaseURL: srv.URL + "/cl"})
	if err != nil || len(cl) != 2 || key != "k2" || version == "" || path != "/cl/models" {
		t.Fatalf("claude: %+v %v key %q version %q path %q", cl, err, key, version, path)
	}
	if cl[0].ID != "claude-new" || !cl[1].Deprecated || cl[0].Deprecated {
		t.Errorf("claude should be newest first with the old one deprecated: %+v", cl)
	}

	// a local service with no key sends no Authorization header
	auth = "unset"
	if _, err := listModels(ctx, ProviderSpec{ID: "ollama", Protocol: protoOpenAI}, ProviderConfig{BaseURL: srv.URL + "/ds"}); err != nil || auth != "" {
		t.Errorf("keyless: err %v auth %q", err, auth)
	}

	if _, err := listModels(ctx, ProviderSpec{Protocol: protoOpenAI}, ProviderConfig{BaseURL: srv.URL + "/missing"}); err == nil {
		t.Error("a 404 should be an error")
	}
}
