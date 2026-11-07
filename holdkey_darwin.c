#include "holdkey_darwin.h"
#include <ApplicationServices/ApplicationServices.h>

extern int goHoldEvent(int kind, int keycode, unsigned long long flags, int repeat);

static CFMachPortRef tap;
static int active; // 1 if the tap may swallow events, 0 if it can only listen

// Forwards every key event to Go, which decides. Only an event Go says to swallow is dropped, and only by an active tap.
static CGEventRef onEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef ev, void *ctx) {
	if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
		CGEventTapEnable(tap, true); // macOS disables slow taps; turn it back on
		return ev;
	}
	int kind;
	if (type == kCGEventFlagsChanged) {
		kind = 0;
	} else if (type == kCGEventKeyDown) {
		kind = 1;
	} else if (type == kCGEventKeyUp) {
		kind = 2;
	} else {
		return ev;
	}
	int keycode = (int)CGEventGetIntegerValueField(ev, kCGKeyboardEventKeycode);
	int repeat = (int)CGEventGetIntegerValueField(ev, kCGKeyboardEventAutorepeat);
	int swallow = goHoldEvent(kind, keycode, (unsigned long long)CGEventGetFlags(ev), repeat);
	return (swallow && active) ? NULL : ev;
}

// Returns 1 for an active tap, 0 for a listen-only one (no Accessibility permission: combos would also type their
// key), -1 if no tap could be made (no Input Monitoring permission).
int tapCreate(void) {
	if (!CGPreflightListenEventAccess()) {
		CGRequestListenEventAccess(); // shows the system prompt once
	}
	CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
	tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, onEvent, NULL);
	active = tap != NULL;
	if (!tap) {
		tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, onEvent, NULL);
	}
	if (!tap) {
		return -1;
	}
	CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
	CGEventTapEnable(tap, true);
	return active;
}

void tapRun(void) {
	CFRunLoopRun();
}
