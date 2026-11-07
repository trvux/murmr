package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestListModelsDeepseekAndClaude(t *testing.T) {
	var gotAuth, gotKey, gotVersion string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth, gotKey, gotVersion = r.Header.Get("Authorization"), r.Header.Get("x-api-key"), r.Header.Get("anthropic-version")
		switch r.URL.Path {
		case "/ds":
			w.Write([]byte(`{"data":[{"id":"deepseek-flash","name":"DeepSeek-V4.1-Flash"},{"id":"deepseek-v4-pro"}]}`))
		case "/claude":
			w.Write([]byte(`{"data":[
				{"id":"claude-old","display_name":"Claude Old","created_at":"2025-01-01T00:00:00Z","lifecycle":"deprecated"},
				{"id":"claude-new","display_name":"Claude New","created_at":"2026-09-01T00:00:00Z","lifecycle":"active"}],"has_more":false}`))
		default:
			http.Error(w, "nope", 404)
		}
	}))
	defer srv.Close()
	deepseekModelsURL, anthropicModelsURL = srv.URL+"/ds", srv.URL+"/claude"

	ds, err := listModels(context.Background(), "deepseek", "k1")
	if err != nil || len(ds) != 2 {
		t.Fatalf("deepseek: %v %v", ds, err)
	}
	if gotAuth != "Bearer k1" || ds[0].Name != "DeepSeek-V4.1-Flash" || ds[1].Name != "deepseek-v4-pro" {
		t.Errorf("deepseek auth %q models %+v (name falls back to id)", gotAuth, ds)
	}

	cl, err := listModels(context.Background(), "claude", "k2")
	if err != nil || len(cl) != 2 {
		t.Fatalf("claude: %v %v", cl, err)
	}
	if gotKey != "k2" || gotVersion == "" {
		t.Errorf("claude headers: key %q version %q", gotKey, gotVersion)
	}
	if cl[0].ID != "claude-new" || cl[1].ID != "claude-old" || !cl[1].Deprecated || cl[0].Deprecated {
		t.Errorf("claude should be newest first with the old one marked deprecated: %+v", cl)
	}

	anthropicModelsURL = srv.URL + "/missing"
	if _, err := listModels(context.Background(), "claude", "k2"); err == nil {
		t.Error("a 404 should be an error")
	}
	if _, err := listModels(context.Background(), "openai", "k"); err == nil {
		t.Error("unknown provider should be an error")
	}
}
