package main

import (
	"testing"
	"time"
)

// events a test machine reports, in order: true is "down", false is "up"
type recorder struct{ got []bool }

func (r *recorder) emit(down bool) { r.got = append(r.got, down) }

func machine(t *testing.T, spec string) (*holdMachine, *recorder) {
	t.Helper()
	cfg, err := ParseHoldKey(spec)
	if err != nil {
		t.Fatal(err)
	}
	r := &recorder{}
	return newHoldMachine(cfg, r.emit), r
}

func flags(keycode int, flags uint64) rawEvent {
	return rawEvent{kind: evFlags, keycode: keycode, flags: flags}
}
func down(keycode int, flags uint64) rawEvent {
	return rawEvent{kind: evDown, keycode: keycode, flags: flags}
}
func up(keycode int, flags uint64) rawEvent {
	return rawEvent{kind: evUp, keycode: keycode, flags: flags}
}
func repeat(keycode int, flags uint64) rawEvent {
	return rawEvent{kind: evDown, keycode: keycode, flags: flags, repeat: true}
}

func TestParseHoldKey(t *testing.T) {
	for spec, ok := range map[string]bool{
		"mod:61": true, "mod:58": true, "mod:63": true, "mod:61:0": true, "mod:58:300": true,
		"combo:49:c0000": true, "combo:105:0": true, "combo:0:100000": true,
		"": false, "mod": false, "mod:abc": false, "mod:12": false, // 12 is Q, not a modifier
		"mod:57": false, "combo:61:0": false, "combo:49": false, "mod:61:99999": false, "key:1": false, "combo:200:0": false,
	} {
		if _, err := ParseHoldKey(spec); (err == nil) != ok {
			t.Errorf("%q: err %v, want ok=%v", spec, err, ok)
		}
	}
	cfg, _ := ParseHoldKey("combo:49:ffffffff")
	if cfg.mods != allModFlags {
		t.Errorf("only the four modifier bits are kept, got %x", cfg.mods)
	}
	if def, _ := ParseHoldKey(defaultHoldSpec); def.keycode != 61 || def.delay != 0 {
		t.Errorf("the default is the right Option, at once: %+v", def)
	}
}

func TestRightOptionAsAlwaysAtOnce(t *testing.T) {
	m, r := machine(t, "mod:61")
	if m.Handle(flags(61, 0x40)) {
		t.Error("a modifier is never swallowed")
	}
	m.Handle(flags(61, 0))
	if len(r.got) != 2 || !r.got[0] || r.got[1] {
		t.Errorf("down then up, got %v", r.got)
	}
	// the other Option key does nothing
	m.Handle(flags(58, 0x20))
	m.Handle(flags(58, 0))
	if len(r.got) != 2 {
		t.Errorf("left Option must not count: %v", r.got)
	}
}

func TestModifierWaitsAndGivesUpOnShortcuts(t *testing.T) {
	m, r := machine(t, "mod:55:40") // left Command, 40 ms for the test
	// Command+C: a key arrives while Command is held, before the delay
	m.Handle(flags(55, 0x8))
	m.Handle(down(8, flagCommand))
	time.Sleep(120 * time.Millisecond)
	m.Handle(flags(55, 0))
	if len(r.got) != 0 {
		t.Errorf("a shortcut must not start a recording: %v", r.got)
	}
	// a plain hold longer than the delay
	m.Handle(flags(55, 0x8))
	time.Sleep(120 * time.Millisecond)
	m.Handle(flags(55, 0))
	if len(r.got) != 2 || !r.got[0] || r.got[1] {
		t.Errorf("a real hold starts after the delay and ends on release: %v", r.got)
	}
	// a tap shorter than the delay does nothing
	r.got = nil
	m.Handle(flags(55, 0x8))
	m.Handle(flags(55, 0))
	time.Sleep(120 * time.Millisecond)
	if len(r.got) != 0 {
		t.Errorf("a quick tap does nothing: %v", r.got)
	}
}

func TestKeysPressedDuringRecordingDoNotCancelIt(t *testing.T) {
	m, r := machine(t, "mod:61")
	m.Handle(flags(61, 0x40))
	m.Handle(down(0, flagOption)) // the user presses a key while dictating
	m.Handle(flags(61, 0))
	if len(r.got) != 2 || r.got[1] {
		t.Errorf("recording goes on and ends at release: %v", r.got)
	}
}

func TestComboHoldsAndSwallowsItsKey(t *testing.T) {
	m, r := machine(t, "combo:49:c0000") // Control+Option+Space
	mods := uint64(flagControl | flagOption)
	if !m.Handle(down(49, mods)) {
		t.Error("the combo's key must be swallowed or it types a space")
	}
	if !m.Handle(repeat(49, mods)) || !m.Handle(repeat(49, mods)) {
		t.Error("auto-repeats are swallowed while held")
	}
	if len(r.got) != 1 || !r.got[0] {
		t.Errorf("repeats must not start again: %v", r.got)
	}
	if !m.Handle(up(49, mods)) {
		t.Error("the key-up is swallowed too")
	}
	if len(r.got) != 2 || r.got[1] {
		t.Errorf("released: %v", r.got)
	}
}

func TestComboIgnoresOtherKeysAndOtherModifiers(t *testing.T) {
	m, r := machine(t, "combo:49:c0000")
	for _, e := range []rawEvent{
		down(49, 0),           // Space alone
		down(49, flagControl), // only one of the two modifiers
		down(49, flagControl|flagOption|flagShift), // one too many
		down(50, flagControl|flagOption),           // another key
		repeat(49, flagControl|flagOption),         // a stray repeat while not held
		up(49, flagControl|flagOption),             // key-up of something we did not start
	} {
		if m.Handle(e) {
			t.Errorf("must pass through untouched: %+v", e)
		}
	}
	if len(r.got) != 0 {
		t.Errorf("nothing starts: %v", r.got)
	}
}

func TestComboEndsWhenAModifierIsLetGoFirst(t *testing.T) {
	m, r := machine(t, "combo:49:c0000")
	m.Handle(down(49, flagControl|flagOption))
	m.Handle(flags(58, flagControl)) // Option released while Space is still down
	if len(r.got) != 2 || r.got[1] {
		t.Errorf("ends when a required modifier goes: %v", r.got)
	}
	if m.Handle(up(49, flagControl)) {
		t.Error("the later key-up is not ours any more")
	}
}

func TestFunctionKeyWithoutModifiers(t *testing.T) {
	m, r := machine(t, "combo:105:0") // F13
	if !m.Handle(down(105, 0)) || !m.Handle(up(105, 0)) {
		t.Error("F13 is swallowed on both edges")
	}
	if len(r.got) != 2 {
		t.Errorf("down and up: %v", r.got)
	}
}

func TestChangingTheKeyWhileHeldReleasesIt(t *testing.T) {
	m, r := machine(t, "mod:61")
	m.Handle(flags(61, 0x40))
	m.Configure(mustHoldConfig("combo:49:c0000"))
	if len(r.got) != 2 || r.got[1] {
		t.Errorf("the old key is released first, so recording does not hang: %v", r.got)
	}
	m.Handle(flags(61, 0)) // the old key coming up now means nothing
	if len(r.got) != 2 {
		t.Errorf("%v", r.got)
	}
	if !m.Handle(down(49, flagControl|flagOption)) {
		t.Error("the new key works at once")
	}
}

func TestPausedKeyDoesNothingAndResumes(t *testing.T) {
	m, r := machine(t, "mod:61")
	m.SetPaused(true)
	// choosing a new key by pressing Option+Shift+M must not start a recording
	m.Handle(flags(61, 0x40))
	m.Handle(down(46, flagOption|flagShift))
	m.Handle(flags(61, 0))
	if len(r.got) != 0 {
		t.Errorf("a paused key does nothing: %v", r.got)
	}
	m.SetPaused(false)
	m.Handle(flags(61, 0x40))
	m.Handle(flags(61, 0))
	if len(r.got) != 2 || !r.got[0] || r.got[1] {
		t.Errorf("after resuming it works again: %v", r.got)
	}
}

func TestPausingWhileHeldReleasesTheRecording(t *testing.T) {
	m, r := machine(t, "mod:61")
	m.Handle(flags(61, 0x40))
	m.SetPaused(true)
	if len(r.got) != 2 || r.got[1] {
		t.Errorf("pausing mid-recording must not leave it hanging: %v", r.got)
	}
}

func TestPausedComboIsNotSwallowed(t *testing.T) {
	m, _ := machine(t, "combo:49:c0000")
	m.SetPaused(true)
	if m.Handle(down(49, flagControl|flagOption)) {
		t.Error("while choosing a key nothing may be swallowed")
	}
}
