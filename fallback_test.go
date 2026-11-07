package main

import (
	"context"
	"errors"
	"testing"
)

type fakeCleaner struct {
	name, out string
	err       error
	calls     int
}

func (f *fakeCleaner) Name() string { return f.name }
func (f *fakeCleaner) Clean(ctx context.Context, raw, extra string) (string, error) {
	f.calls++
	return f.out, f.err
}

func TestFallbackCleaner(t *testing.T) {
	ctx := context.Background()

	// the chosen service works: backup untouched, no note
	p, b := &fakeCleaner{name: "deepseek", out: "A"}, &fakeCleaner{name: "claude", out: "B"}
	text, note, err := (&fallbackCleaner{p, b}).CleanNote(ctx, "x", "")
	if text != "A" || note != "" || err != nil || b.calls != 0 {
		t.Errorf("primary ok: %q %q %v backup calls %d", text, note, err, b.calls)
	}

	// the chosen service fails: backup answers and the user is told
	p, b = &fakeCleaner{name: "deepseek", err: errors.New("503")}, &fakeCleaner{name: "claude", out: "B"}
	text, note, err = (&fallbackCleaner{p, b}).CleanNote(ctx, "x", "")
	if text != "B" || err != nil || note != "DeepSeek không trả lời, đã dùng Claude" {
		t.Errorf("fallback: %q %q %v", text, note, err)
	}

	// an empty answer counts as a failure too
	p, b = &fakeCleaner{name: "claude", out: ""}, &fakeCleaner{name: "deepseek", out: "B"}
	if text, _, _ = (&fallbackCleaner{p, b}).CleanNote(ctx, "x", ""); text != "B" {
		t.Errorf("empty primary should fall back, got %q", text)
	}

	// both fail: an error, so the raw transcript is pasted, and the user is told
	p, b = &fakeCleaner{name: "deepseek", err: errors.New("a")}, &fakeCleaner{name: "claude", err: errors.New("b")}
	text, note, err = (&fallbackCleaner{p, b}).CleanNote(ctx, "x", "")
	if text != "" || err == nil || note == "" {
		t.Errorf("both fail: %q %q %v", text, note, err)
	}
}
