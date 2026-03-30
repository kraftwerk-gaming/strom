#!/usr/bin/env python3
"""Patch Proton's pfx_copy to use symlinks for DLLs/EXEs instead of copies.
Non-binary files (configs, .reg, .nls, etc) are still copied since Wine writes to them.
Saves ~600MB per game prefix."""
import sys

data = open(sys.argv[1]).read()

old = """            if dll_copy:
                try_copyfile(src, dst)
            else:
                os.symlink(contents, dst)
        else:
            try_copyfile(src, dst)"""

new = """            os.symlink(contents, dst)
        else:
            # Symlink binaries, copy everything else (configs, .reg, .nls need to be writable)
            if src.endswith(('.dll', '.exe', '.DLL', '.EXE', '.drv', '.ds', '.acm', '.ocx', '.ax', '.sys', '.cpl')):
                os.symlink(src, dst)
            else:
                try_copyfile(src, dst)"""

if old not in data:
    print("ERROR: Could not find pfx_copy patch target", file=sys.stderr)
    sys.exit(1)

data = data.replace(old, new)
open(sys.argv[1], 'w').write(data)
print("Patched pfx_copy to symlink binaries")
