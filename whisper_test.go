package main

import "testing"

func TestHasWord(t *testing.T) {
	for s, want := range map[string]bool{"": false, ".": false, " . ": false, "...": false, "Hello.": true, "9m": true, "ừm": true} {
		if got := hasWord(s); got != want {
			t.Errorf("hasWord(%q) = %v, want %v", s, got, want)
		}
	}
}

func TestIsOrphanedWhisper(t *testing.T) {
	for line, want := range map[string]bool{
		"    1 /opt/homebrew/Cellar/whisper.cpp/1.9.5/bin/whisper-server":        true,
		"    1 /Applications/Murmr Stream.app/Contents/Resources/whisper-server": true,
		" 4242 /opt/homebrew/bin/whisper-server":                                 false, // still has a parent
		"    1 /usr/bin/python3":                                                 false, // not ours
		"    1 /tmp/not-whisper-server-2":                                        false,
		"":                                                                       false,
	} {
		if got := isOrphanedWhisper(line); got != want {
			t.Errorf("%q: got %v, want %v", line, got, want)
		}
	}
}

func TestWhisperBinaryPrefersOverride(t *testing.T) {
	t.Setenv("MURMR_WHISPER", "/custom/whisper-server")
	if p, err := whisperBinary(); err != nil || p != "/custom/whisper-server" {
		t.Errorf("override ignored: %q %v", p, err)
	}
}
