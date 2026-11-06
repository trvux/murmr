#include "holdkey_darwin.h"
#include <ApplicationServices/ApplicationServices.h>

extern void goKeyEvent(int down);

#define KEY_RIGHT_OPTION 61
#define DEVICE_RIGHT_ALT_MASK 0x40 // NX_DEVICERALTKEYMASK: set only while right Option is down

static CFMachPortRef tap;
static int held;

static CGEventRef onEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef ev, void *ctx) {
	if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
		CGEventTapEnable(tap, true); // macOS disables slow taps; turn it back on
		return ev;
	}
	if (type != kCGEventFlagsChanged) {
		return ev;
	}
	if (CGEventGetIntegerValueField(ev, kCGKeyboardEventKeycode) != KEY_RIGHT_OPTION) {
		return ev;
	}
	int down = (CGEventGetFlags(ev) & DEVICE_RIGHT_ALT_MASK) != 0;
	if (down != held) {
		held = down;
		goKeyEvent(down);
	}
	return ev;
}

int tapCreate(void) {
	if (!CGPreflightListenEventAccess()) {
		CGRequestListenEventAccess(); // shows the system prompt once
	}
	tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
		kCGEventTapOptionListenOnly, CGEventMaskBit(kCGEventFlagsChanged), onEvent, NULL);
	if (!tap) {
		return -1;
	}
	CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
	CGEventTapEnable(tap, true);
	return 0;
}

void tapRun(void) {
	CFRunLoopRun();
}
