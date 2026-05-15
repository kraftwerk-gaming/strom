#!/usr/bin/env python3
"""Clear PF_X on PT_GNU_STACK program headers (ELF64 little-endian only).

The bundled FMOD libs in Celeste's lib64/ ship with an executable-stack
request that modern Linux kernels refuse, breaking the Mono FMOD
P/Invoke. patchelf < 0.18 has no --clear-execstack, so we strip the
bit by hand: walk the program header table, locate each PT_GNU_STACK
entry (p_type = 0x6474E551), and clear bit 0 (PF_X) in p_flags.
"""

import struct
import sys

PT_GNU_STACK = 0x6474E551
PF_X = 0x1


def clear(path: str) -> None:
    with open(path, "r+b") as f:
        data = bytearray(f.read())

    if data[:4] != b"\x7fELF" or data[4] != 2:
        sys.exit(f"{path}: not an ELF64 file")
    if data[5] != 1:
        sys.exit(f"{path}: not little-endian")

    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
    e_phnum = struct.unpack_from("<H", data, 0x38)[0]

    if e_phentsize != 56:
        sys.exit(f"{path}: unexpected phentsize {e_phentsize}")

    patched = 0
    for i in range(e_phnum):
        ph = e_phoff + i * 56
        p_type, p_flags = struct.unpack_from("<II", data, ph)
        if p_type == PT_GNU_STACK and p_flags & PF_X:
            struct.pack_into("<I", data, ph + 4, p_flags & ~PF_X)
            patched += 1

    if not patched:
        print(f"{path}: no PT_GNU_STACK with PF_X (already clear)",
              file=sys.stderr)
        return

    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: cleared PF_X on {patched} PT_GNU_STACK entries",
          file=sys.stderr)


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        clear(arg)
