/* inotify_add_watch graceful-degradation shim for Project Zomboid.
 *
 * PZ's zombie.DebugFileWatcher.init() (a dev-only live-reload helper) runs
 * unconditionally at startup and registers a recursive inotify watch over the
 * game's media/ tree. It treats a failed inotify_add_watch as fatal: the
 * IOException leaves the WatchService half-initialized and the next
 * Path.register throws an unhandled NullPointerException that kills MainThread
 * before the main menu ever appears.
 *
 * When the per-user inotify watch pool is exhausted (a common condition - e.g.
 * a leaked editor/terminal config-watcher holding hundreds of thousands of
 * watches), inotify_add_watch returns ENOSPC and PZ crashes at launch through
 * no fault of its own. Degrade that failure: on ENOSPC/EMFILE return a
 * harmless, non-negative fake watch descriptor so the recursive walk completes
 * and the NPE never fires. The watcher then simply delivers no events, which is
 * exactly the desired behavior for a player who is not live-editing scripts.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/inotify.h>

int inotify_add_watch(int fd, const char *pathname, uint32_t mask) {
    static int (*real)(int, const char *, uint32_t) = NULL;
    if (!real)
        real = dlsym(RTLD_NEXT, "inotify_add_watch");
    int wd = real(fd, pathname, mask);
    if (wd < 0 && (errno == ENOSPC || errno == EMFILE)) {
        errno = 0;
        return 0x40000000; /* non-negative fake wd; never reused by the kernel */
    }
    return wd;
}
