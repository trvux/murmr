package main

/*
#cgo LDFLAGS: -framework ApplicationServices -framework CoreFoundation
#include "holdkey_darwin.h"
*/
import "C"

import (
	"fmt"
	"runtime"
)

var holdEvents = make(chan bool, 8)

//export goKeyEvent
func goKeyEvent(down C.int) {
	select {
	case holdEvents <- down != 0:
	default: // never block the event tap thread
	}
}

// StartHoldKey listens for the right Option key and reports true on press,
// false on release.
func StartHoldKey() (<-chan bool, error) {
	errc := make(chan error, 1)
	go func() {
		runtime.LockOSThread() // the run loop is bound to this thread
		if C.tapCreate() != 0 {
			errc <- fmt.Errorf("event tap refused: grant Input Monitoring to your terminal " +
				"(System Settings > Privacy & Security > Input Monitoring), then restart it")
			return
		}
		errc <- nil
		C.tapRun()
	}()
	if err := <-errc; err != nil {
		return nil, err
	}
	return holdEvents, nil
}
