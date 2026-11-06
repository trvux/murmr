package main

import (
	"bytes"
	"os"
	"os/exec"
	"time"
)

// utf8Env makes pbcopy/pbpaste treat bytes as UTF-8 (needed for Vietnamese
// when launched from a context without a UTF-8 locale).
func utf8Env() []string {
	return append(os.Environ(), "LC_ALL=en_US.UTF-8")
}

func pbpaste() []byte {
	cmd := exec.Command("pbpaste")
	cmd.Env = utf8Env()
	out, _ := cmd.Output()
	return out
}

func pbcopy(b []byte) error {
	cmd := exec.Command("pbcopy")
	cmd.Env = utf8Env()
	cmd.Stdin = bytes.NewReader(b)
	return cmd.Run()
}

// pasteText puts text on the clipboard, sends Cmd+V to the focused app,
// then restores the previous clipboard text. Needs Accessibility permission.
func pasteText(text string) error {
	prev := pbpaste()
	if err := pbcopy([]byte(text)); err != nil {
		return err
	}
	err := exec.Command("osascript", "-e",
		`tell application "System Events" to keystroke "v" using command down`).Run()
	time.Sleep(200 * time.Millisecond) // let the target app read the clipboard
	_ = pbcopy(prev)
	return err
}

// playSound plays a macOS system sound by name (see /System/Library/Sounds); "off" is silent.
func playSound(name string) {
	if name == "off" {
		return
	}
	go exec.Command("afplay", "/System/Library/Sounds/"+name+".aiff").Run()
}
