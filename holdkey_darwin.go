package main

/*
#cgo LDFLAGS: -framework ApplicationServices -framework CoreFoundation
#include "holdkey_darwin.h"
*/
import "C"

import (
	"fmt"
	"log"
	"runtime"
)

//export goHoldEvent
func goHoldEvent(kind C.int, keycode C.int, flags C.ulonglong, repeat C.int) C.int {
	if hold.Handle(rawEvent{kind: rawKind(kind), keycode: int(keycode), flags: uint64(flags), repeat: repeat != 0}) {
		return 1
	}
	return 0
}

// StartHoldKey starts the event tap that watches for the dictation key (see holdkey.go) and returns the channel of
// "down" and "up" events.
func StartHoldKey() (<-chan bool, error) {
	errc := make(chan error, 1)
	go func() {
		runtime.LockOSThread() // the run loop is bound to this thread
		mode := C.tapCreate()
		if mode < 0 {
			errc <- fmt.Errorf("event tap refused: grant Input Monitoring to your terminal " +
				"(System Settings > Privacy & Security > Input Monitoring), then restart it")
			return
		}
		if mode == 0 {
			log.Printf("key tap: listen-only (grant Accessibility so a key combination can be kept from typing its letter)")
		}
		errc <- nil
		C.tapRun()
	}()
	if err := <-errc; err != nil {
		return nil, err
	}
	return holdEvents, nil
}
