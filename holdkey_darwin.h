#ifndef HOLDKEY_DARWIN_H
#define HOLDKEY_DARWIN_H

// tapCreate installs a listen-only event tap for the right Option key on the
// calling thread's run loop. Returns 0 on success, -1 if macOS refused
// (missing Input Monitoring permission).
int tapCreate(void);

// tapRun blocks, pumping the run loop that tapCreate attached to.
void tapRun(void);

#endif
