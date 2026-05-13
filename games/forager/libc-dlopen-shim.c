/* Steam's 2018-era libsteam_api.so binds against `__libc_dlopen_mode`,
 * a GLIBC_PRIVATE symbol that modern glibc (2.34+) hides at link
 * resolution time. We LD_PRELOAD this shim so the lookup succeeds —
 * the real implementation just forwards to dlopen(), which is the
 * documented public replacement. */
#define _GNU_SOURCE
#include <dlfcn.h>

void *__libc_dlopen_mode(const char *name, int mode) {
  return dlopen(name, mode);
}
