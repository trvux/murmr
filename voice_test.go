package main

import "testing"

// The stub is a shell loop standing in for voice/speak_server.py, to test the
// JSON-lines protocol without running any third-party code.
func stub(t *testing.T, reply string) *Voice {
	t.Helper()
	v, err := startVoiceProc("sh", "-c", `echo '{"ready": true}'; while read l; do echo '`+reply+`'; done`)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(v.Close)
	return v
}

func TestVoiceSpeakOK(t *testing.T) {
	if err := stub(t, `{"ok": true}`).Speak("push", "/tmp/x.wav"); err != nil {
		t.Fatalf("Speak: %v", err)
	}
}

func TestVoiceSpeakError(t *testing.T) {
	err := stub(t, `{"error": "boom"}`).Speak("push", "/tmp/x.wav")
	if err == nil || err.Error() != "voice: boom" {
		t.Fatalf("got %v, want voice: boom", err)
	}
}

func TestVoiceNotReady(t *testing.T) {
	if _, err := startVoiceProc("sh", "-c", `echo '{"ready": false}'`); err == nil {
		t.Fatal("a server that is not ready must be an error")
	}
}
