/* LD_PRELOAD evdev enumeration filter for luftrausers.
 *
 * luftrausers scans /dev/input/event* directly (it uses no SDL, which would
 * filter by udev's ID_INPUT_JOYSTICK) and treats any device with absolute
 * axes as a joystick -- including the laptop touchpad, whose 0..max axes read
 * as a stick jammed into a corner and whose axes hijack the game's steering
 * away from the real gamepad.
 *
 * This shim makes the game's open() of an event node succeed only for genuine
 * game controllers (devices advertising BTN_GAMEPAD or BTN_JOYSTICK key bits,
 * exactly SDL's own test); every other event device returns ENODEV so the
 * game skips it. Nothing outside this process is affected.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define NLONGS(x) (((x) + 8 * sizeof(long) - 1) / (8 * sizeof(long)))
#define TEST_BIT(nr, addr) \
    (((const unsigned long *)(addr))[(nr) / (8 * sizeof(long))] >> \
         ((nr) % (8 * sizeof(long))) & \
     1UL)

static int is_event_node(const char *path) {
    return path && strncmp(path, "/dev/input/event", 16) == 0;
}

static int is_game_controller(int fd) {
    unsigned long keys[NLONGS(KEY_MAX + 1)];
    memset(keys, 0, sizeof(keys));
    if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0)
        return 0;
    return TEST_BIT(BTN_GAMEPAD, keys) || TEST_BIT(BTN_JOYSTICK, keys);
}

static int vet(const char *path, int fd) {
    if (fd >= 0 && is_event_node(path) && !is_game_controller(fd)) {
        close(fd);
        errno = ENODEV;
        return -1;
    }
    return fd;
}

int open(const char *path, int flags, ...) {
    static int (*real)(const char *, int, ...);
    if (!real)
        real = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return vet(path, real(path, flags, mode));
}

int open64(const char *path, int flags, ...) {
    static int (*real)(const char *, int, ...);
    if (!real)
        real = dlsym(RTLD_NEXT, "open64");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return vet(path, real(path, flags, mode));
}

int openat(int dirfd, const char *path, int flags, ...) {
    static int (*real)(int, const char *, int, ...);
    if (!real)
        real = dlsym(RTLD_NEXT, "openat");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return vet(path, real(dirfd, path, flags, mode));
}

int openat64(int dirfd, const char *path, int flags, ...) {
    static int (*real)(int, const char *, int, ...);
    if (!real)
        real = dlsym(RTLD_NEXT, "openat64");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return vet(path, real(dirfd, path, flags, mode));
}
