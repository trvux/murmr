package main

import (
	"encoding/json"
	"testing"
)

func TestHintsJSON(t *testing.T) {
	boot := Entry{Raw: "chưa boot lên", Final: "chưa push lên"}
	bad := Entry{Raw: "chưa bad nên", Final: "chưa pass nên"}
	hist := []Entry{boot, boot, boot, bad, bad}

	b, err := hintsJSON(hist, nil)
	if err != nil {
		t.Fatal(err)
	}
	var got []hintJSON
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0] != (hintJSON{"boot", "push", 3, true}) || got[1] != (hintJSON{"bad", "pass", 2, false}) {
		t.Fatalf("got %+v", got)
	}

	b, _ = hintsJSON(hist, map[string]bool{"boot": true})
	_ = json.Unmarshal(b, &got)
	if len(got) != 1 || got[0].From != "bad" {
		t.Fatalf("an ignored pair must disappear, got %+v", got)
	}
}

func TestHintsJSONEmptyIsAnArray(t *testing.T) {
	b, err := hintsJSON(nil, nil)
	if err != nil || string(b) != "[]" {
		t.Fatalf("got %q, %v", b, err)
	}
}
