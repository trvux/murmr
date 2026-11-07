package main

import (
	"encoding/json"
	"io"
	"math"
	"sync"
	"time"
)

// eventSink writes one JSON object per line. The macOS app shell reads these to
// draw the notch UI. Event kinds:
//
//	loading  stage                 startup step: "dictionary", "whisper" (the long one), "audio", "keys"
//	ready                          engine is up
//	recording                      key down, mic is capturing
//	app      bundle, style         where the text will be pasted (arrives a moment later); style is the pronoun
//	                               profile's label ("tao / mày"), or "" when pronouns are left as recognised
//	level    v                     0..1 loudness while recording, ~20 per second
//	partial  stable, tentative     live caption while recording (see streaming.go); stable words stopped
//	                               changing between two decodes, tentative ones may still be revised
//	processing stage               "transcribe" or "cleanup", after the key is released
//	done     text, ms, note        text was pasted; note says if a backup service was used ("" otherwise)
//	skipped  reason                nothing worth pasting ("silent" or "no_speech")
//	error    msg                   something failed
//
// A nil *eventSink is valid and silent, so call sites need no checks.
type eventSink struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func newEventSink(w io.Writer) *eventSink { return &eventSink{enc: json.NewEncoder(w)} }

// events is non-nil only when the shell asked for events (MURMR_EVENTS=1).
var events *eventSink

func (s *eventSink) emit(kind string, kv ...any) {
	if s == nil {
		return
	}
	m := map[string]any{"e": kind}
	for i := 0; i+1 < len(kv); i += 2 {
		if k, ok := kv[i].(string); ok {
			m[k] = kv[i+1]
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = s.enc.Encode(m)
}

// levelGain maps microphone RMS to a 0..1 meter. Speech on the built-in mic
// measured about 0.01-0.02 (see the "level" in the engine log), so x18 puts normal
// speech around 0.2-0.4 and loud speech near 1.
const levelGain = 18

// startLevels emits a "level" event every 50ms until the returned stop is called.
func startLevels(s *eventSink, rec *Recorder) (stop func()) {
	if s == nil {
		return func() {}
	}
	done := make(chan struct{})
	go func() {
		t := time.NewTicker(50 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				s.emit("level", "v", math.Min(1, rec.Level()*levelGain))
			}
		}
	}()
	return func() { close(done) }
}
