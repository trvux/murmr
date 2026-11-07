package main

import (
	"encoding/json"
	"testing"
)

func TestStylesJSON(t *testing.T) {
	b, err := stylesJSON()
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Casual     []string            `json:"casual"`
		TitleRules []map[string]string `json:"titleRules"`
	}
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	has := func(bundle string) bool {
		for _, c := range got.Casual {
			if c == bundle {
				return true
			}
		}
		return false
	}
	if !has("com.mitchellh.ghostty") || !has("com.google.Chrome") || has("com.vng.zalo") {
		t.Fatalf("unexpected default casual apps: %v", got.Casual)
	}
	if len(got.TitleRules) == 0 || got.TitleRules[0]["style"] != styleNeutral {
		t.Fatalf("expected a neutral default title rule, got %v", got.TitleRules)
	}
}
