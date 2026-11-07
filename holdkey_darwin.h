#ifndef HOLDKEY_DARWIN_H
#define HOLDKEY_DARWIN_H

// tapCreate installs an event tap for key events on the calling thread's run loop and forwards each to Go
// (goHoldEvent), which decides what the dictation key is doing. Returns 1 for an active tap (it can swallow the
// events Go says to), 0 for a listen-only one, -1 if macOS refused (missing Input Monitoring permission).
int tapCreate(void);

// tapRun blocks, pumping the run loop that tapCreate attached to.
void tapRun(void);

#endif
