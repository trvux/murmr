package main

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The dictation key is the user's choice: one modifier key held alone ("mod:61" is the right Option), or a key with
// modifiers ("combo:49:c0000" is Control+Option+Space), or a function key. This file decides, from raw keyboard
// events, when the key goes down and up. It has no operating-system code, so it is tested with made-up events; the
// event tap in holdkey_darwin.c only forwards what it sees.

type holdKind int

const (
	holdMod   holdKind = iota // a modifier key on its own
	holdCombo                 // a key, with exactly these modifiers held
)

// CGEventFlags bits.
const (
	flagShift   = 0x20000
	flagControl = 0x40000
	flagOption  = 0x80000
	flagCommand = 0x100000
	flagFn      = 0x800000 // NX_SECONDARYFNMASK
	allModFlags = flagShift | flagControl | flagOption | flagCommand
)

type holdConfig struct {
	kind    holdKind
	keycode int
	devMask uint64        // mod: the device-specific flag set only while this exact key is down (tells left from right)
	mods    uint64        // combo: the modifiers that must be held
	delay   time.Duration // mod: how long it must be held before recording starts
}

// modifierKeys: key code -> the device flag for that physical key. Keys that often take part in shortcuts (Command,
// Control, Shift, the left Option) wait a moment and give up if another key arrives, so Command+C does not start a
// recording; the right Option and fn, which hardly ever do, start at once, as the right Option always has.
var modifierKeys = map[int]struct {
	mask  uint64
	delay time.Duration
}{
	59: {0x1, 150 * time.Millisecond},    // left Control
	56: {0x2, 150 * time.Millisecond},    // left Shift
	60: {0x4, 150 * time.Millisecond},    // right Shift
	55: {0x8, 150 * time.Millisecond},    // left Command
	54: {0x10, 150 * time.Millisecond},   // right Command
	58: {0x20, 150 * time.Millisecond},   // left Option
	61: {0x40, 0},                        // right Option
	62: {0x2000, 150 * time.Millisecond}, // right Control
	63: {flagFn, 0},                      // fn
}

const defaultHoldSpec = "mod:61"

// ParseHoldKey reads a spec: "mod:<key code>[:<delay ms>]" or "combo:<key code>:<modifier flags in hex>".
func ParseHoldKey(spec string) (holdConfig, error) {
	f := strings.Split(strings.TrimSpace(spec), ":")
	bad := func() (holdConfig, error) { return holdConfig{}, fmt.Errorf("not a dictation key: %q", spec) }
	if len(f) < 2 {
		return bad()
	}
	code, err := strconv.Atoi(f[1])
	if err != nil || code < 0 || code > 127 {
		return bad()
	}
	switch f[0] {
	case "mod":
		k, ok := modifierKeys[code]
		if !ok {
			return bad()
		}
		cfg := holdConfig{kind: holdMod, keycode: code, devMask: k.mask, delay: k.delay}
		if len(f) > 2 {
			ms, err := strconv.Atoi(f[2])
			if err != nil || ms < 0 || ms > 2000 {
				return bad()
			}
			cfg.delay = time.Duration(ms) * time.Millisecond
		}
		return cfg, nil
	case "combo":
		if _, isModifier := modifierKeys[code]; isModifier || code == 57 || len(f) != 3 { // 57 is Caps Lock
			return bad()
		}
		mods, err := strconv.ParseUint(f[2], 16, 64)
		if err != nil {
			return bad()
		}
		return holdConfig{kind: holdCombo, keycode: code, mods: mods & allModFlags}, nil
	}
	return bad()
}

type rawKind int

const (
	evFlags rawKind = iota // a modifier key changed
	evDown
	evUp
)

type rawEvent struct {
	kind    rawKind
	keycode int
	flags   uint64
	repeat  bool // auto-repeat of a held key
}

// holdMachine turns raw events into "dictation key down" and "dictation key up".
type holdMachine struct {
	mu      sync.Mutex
	cfg     holdConfig
	held    bool // the key is physically down
	active  bool // we reported "down" and owe a "up"
	tainted bool // another key arrived while a modifier was held: it is a shortcut, not a dictation
	timer   *time.Timer
	emit    func(down bool)
}

func newHoldMachine(cfg holdConfig, emit func(bool)) *holdMachine {
	return &holdMachine{cfg: cfg, emit: emit}
}

// Configure switches to another key at once, without a restart. If the old key is down it is released first.
func (m *holdMachine) Configure(cfg holdConfig) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.release()
	m.cfg = cfg
}

func (m *holdMachine) release() {
	if m.timer != nil {
		m.timer.Stop()
		m.timer = nil
	}
	if m.active {
		m.emit(false)
	}
	m.held, m.active, m.tainted = false, false, false
}

// Handle takes one event and says whether it must be swallowed (kept from the app in front): only the dictation key
// itself, and only when it is a combo, since a modifier on its own is harmless to let through.
func (m *holdMachine) Handle(e rawEvent) (swallow bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cfg.kind == holdMod {
		m.handleMod(e)
		return false
	}
	return m.handleCombo(e)
}

func (m *holdMachine) handleMod(e rawEvent) {
	if e.kind == evDown && m.held && !m.active {
		m.tainted = true // Command+C and friends: this was a shortcut
	}
	if e.kind != evFlags || e.keycode != m.cfg.keycode {
		return
	}
	down := e.flags&m.cfg.devMask != 0
	switch {
	case down && !m.held:
		m.held, m.tainted = true, false
		if m.cfg.delay <= 0 {
			m.active = true
			m.emit(true)
		} else {
			m.timer = time.AfterFunc(m.cfg.delay, m.delayElapsed)
		}
	case !down && m.held:
		m.release()
	}
}

func (m *holdMachine) delayElapsed() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.held && !m.tainted && !m.active {
		m.active = true
		m.emit(true)
	}
}

func (m *holdMachine) handleCombo(e rawEvent) bool {
	mods := e.flags & allModFlags
	switch e.kind {
	case evDown:
		if e.keycode != m.cfg.keycode || mods != m.cfg.mods {
			return false
		}
		if e.repeat {
			return m.held // while we hold it, the repeats must not type either
		}
		if !m.held {
			m.held, m.active = true, true
			m.emit(true)
		}
		return true
	case evUp:
		if e.keycode != m.cfg.keycode || !m.held {
			return false
		}
		m.release()
		return true
	case evFlags:
		if m.held && mods != m.cfg.mods { // a required modifier was let go first
			m.release()
		}
	}
	return false
}

// holdEvents carries "down" and "up" to the dictation loop; it never blocks the event tap.
var holdEvents = make(chan bool, 8)

var hold = newHoldMachine(mustHoldConfig(defaultHoldSpec), func(down bool) {
	select {
	case holdEvents <- down:
	default:
	}
})

func mustHoldConfig(spec string) holdConfig {
	cfg, err := ParseHoldKey(spec)
	if err != nil {
		panic(err)
	}
	return cfg
}

// SetHoldKey changes the dictation key, now.
func SetHoldKey(spec string) error {
	cfg, err := ParseHoldKey(spec)
	if err != nil {
		return err
	}
	hold.Configure(cfg)
	return nil
}
