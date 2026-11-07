package main

import (
	"strings"
	"sync/atomic"
	"time"
	"unicode"
)

// Live preview ("streaming") while the key is held.
//
// Whisper is not a streaming model: it always encodes a 30 s window, so a normal
// decode costs ~1.6 s even for 2 s of audio. A second whisper-server started with
// `-ac 512` (a ~10 s encoder window) decodes in ~0.6 s, fast enough to re-decode the
// latest audio every ~0.4 s. Its text is only a preview (a bit less accurate); the
// text that is pasted still comes from the normal full-quality pass after release.
const (
	previewWindow    = 10 * sampleRate        // matches the ~10.2 s that -ac 512 can see
	previewInterval  = 400 * time.Millisecond // pause between decodes
	previewMinAudio  = sampleRate * 8 / 10    // do not decode less than 0.8 s
	previewSpeechRMS = 0.006                  // the last second must be louder than room noise (~0.004)
	previewACArg     = "512"
)

// previewSrv holds the preview whisper-server once it is up (it loads in the
// background so the engine does not wait for it).
var previewSrv atomic.Pointer[Whisper]

func normWord(w string) string {
	return strings.ToLower(strings.TrimFunc(w, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) }))
}

// agree is LocalAgreement-2: the words two consecutive hypotheses both start with are
// "stable" (they stopped changing), the rest is still "tentative". This is what keeps a
// live transcript from flickering every time Whisper revises its last few words.
func agree(prev, cur []string) (stable, tentative []string) {
	n := 0
	for n < len(prev) && n < len(cur) && normWord(prev[n]) == normWord(cur[n]) {
		n++
	}
	return cur[:n], cur[n:]
}

// startPreview emits "partial" events until the returned stop is called. It is a no-op
// when events are off or the preview server is not ready.
func startPreview(s *eventSink, rec *Recorder) (stop func()) {
	srv := previewSrv.Load()
	if s == nil || srv == nil {
		return func() {}
	}
	done := make(chan struct{})
	go func() {
		var prev []string
		t := time.NewTicker(previewInterval)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
			}
			pcm := rec.Snapshot(previewWindow)
			if len(pcm) < previewMinAudio {
				continue
			}
			tail := pcm
			if len(tail) > sampleRate {
				tail = tail[len(tail)-sampleRate:]
			}
			if rms(tail) < previewSpeechRMS { // silence: Whisper would invent text
				continue
			}
			tr, err := srv.Transcribe(encodeWAV(pcm))
			select {
			case <-done: // key released while decoding: the full pass takes over
				return
			default:
			}
			if err != nil || !hasWord(tr.Text) {
				continue
			}
			cur := strings.Fields(tr.Text)
			stable, tentative := agree(prev, cur)
			prev = cur
			s.emit("partial", "stable", strings.Join(stable, " "), "tentative", strings.Join(tentative, " "))
		}
	}()
	return func() { close(done) }
}
