package main

import "testing"

func TestHasWord(t *testing.T) {
	for s, want := range map[string]bool{"": false, ".": false, " . ": false, "...": false, "Hello.": true, "9m": true, "ừm": true} {
		if got := hasWord(s); got != want {
			t.Errorf("hasWord(%q) = %v, want %v", s, got, want)
		}
	}
}
