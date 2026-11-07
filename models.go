package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"time"
)

// ModelInfo is one model a provider says it serves, as the Settings window lists it.
type ModelInfo struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Created    string `json:"created,omitempty"` // RFC 3339, when the provider says
	Deprecated bool   `json:"deprecated"`        // still callable, but on its way out
}

// Both providers publish a list of the models they serve right now, so the app never needs a hard-coded
// list that goes stale. Variables so tests can point them at a local server.
var (
	deepseekModelsURL  = "https://api.deepseek.com/models"
	anthropicModelsURL = "https://api.anthropic.com/v1/models?limit=1000"
)

// listModels asks a provider ("deepseek" or "claude") which models its key can use, newest first.
// A retired model is gone from the lists, so "old" here means deprecated-but-callable.
func listModels(ctx context.Context, provider, key string) ([]ModelInfo, error) {
	var req *http.Request
	switch provider {
	case "deepseek":
		req, _ = http.NewRequestWithContext(ctx, http.MethodGet, deepseekModelsURL, nil)
		req.Header.Set("Authorization", "Bearer "+key)
	case "claude":
		req, _ = http.NewRequestWithContext(ctx, http.MethodGet, anthropicModelsURL, nil)
		req.Header.Set("x-api-key", key)
		req.Header.Set("anthropic-version", "2023-06-01")
	default:
		return nil, fmt.Errorf("unknown provider %q (deepseek or claude)", provider)
	}

	var out struct {
		Data []struct {
			ID          string `json:"id"`
			Name        string `json:"name"`         // DeepSeek
			DisplayName string `json:"display_name"` // Anthropic
			CreatedAt   string `json:"created_at"`
			Lifecycle   string `json:"lifecycle"`
		} `json:"data"`
	}
	if err := doJSON(req, &out); err != nil {
		return nil, err
	}
	models := make([]ModelInfo, 0, len(out.Data))
	for _, m := range out.Data {
		if m.ID == "" {
			continue
		}
		name := m.DisplayName
		if name == "" {
			name = m.Name
		}
		if name == "" {
			name = m.ID
		}
		models = append(models, ModelInfo{ID: m.ID, Name: name, Created: m.CreatedAt, Deprecated: m.Lifecycle == "deprecated"})
	}
	// Newest first when dates are known; the sort is stable so a provider's own order survives otherwise.
	sort.SliceStable(models, func(i, j int) bool { return models[i].Created > models[j].Created })
	return models, nil
}

// cmdModels prints a provider's models as JSON, using the key from the environment (what the Settings
// window runs after a key is saved).
func cmdModels(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage: murmr models deepseek|claude")
	}
	keyName := map[string]string{"deepseek": "DEEPSEEK_API_KEY", "claude": "ANTHROPIC_API_KEY"}[args[0]]
	if keyName == "" {
		return fmt.Errorf("unknown provider %q (deepseek or claude)", args[0])
	}
	key := os.Getenv(keyName)
	if key == "" {
		return fmt.Errorf("%s is not set", keyName)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	models, err := listModels(ctx, args[0], key)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(models)
}
