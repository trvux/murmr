package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestEmitWritesOneJSONObjectPerLine(t *testing.T) {
	var buf bytes.Buffer
	s := newEventSink(&buf)
	s.emit("ready")
	s.emit("done", "text", "xin chào <b>", "ms", int64(2400))

	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 2 {
		t.Fatalf("want 2 lines, got %d: %q", len(lines), buf.String())
	}
	var got map[string]any
	if err := json.Unmarshal([]byte(lines[1]), &got); err != nil {
		t.Fatal(err)
	}
	if got["e"] != "done" || got["text"] != "xin chào <b>" || got["ms"] != float64(2400) {
		t.Fatalf("round trip lost data: %v", got)
	}
}

func TestNilSinkIsSilent(t *testing.T) {
	var s *eventSink
	s.emit("ready") // must not panic
}
