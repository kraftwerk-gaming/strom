#!/usr/bin/env python3
"""Clear the 32BITREQUIRED/32BITPREFERRED CorFlags on a .NET assembly.

UnrailedCrashDumper.exe is built AnyCPU-prefer-32 (machine=i386, CorFlags =
ILONLY | 32BITREQUIRED | 32BITPREFERRED = 0x20003). Real .NET Framework 4.5+
treats that combination as AnyCPU and happily loads it into the 64-bit
UnrailedGame.exe host process, but wine-mono 10.x mishandles 32BITPREFERRED and
rejects the assembly as 32-bit-only -- so the main exe's early reference to
UnrailedCrashDumper.CertManager throws a TypeLoadException before the menu.

Clearing both flags leaves a pure ILONLY (AnyCPU) image, which wine-mono loads
into the 64-bit process. The image is IL-only so the i386 machine field in the
COFF header is ignored by the CLR.
"""

import struct
import sys


def clear_flags(path: str) -> None:
    data = bytearray(open(path, "rb").read())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\x00\x00":
        raise SystemExit(f"{path}: not a PE file")

    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    ddir = opt + (96 if magic == 0x10B else 112)
    clr_rva = struct.unpack_from("<I", data, ddir + 14 * 8)[0]
    if clr_rva == 0:
        raise SystemExit(f"{path}: no CLR data directory (not a managed image)")

    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    sectab = opt + struct.unpack_from("<H", data, pe + 20)[0]

    def rva_to_off(rva: int) -> int:
        for i in range(nsec):
            base = sectab + i * 40
            vaddr = struct.unpack_from("<I", data, base + 12)[0]
            vsize = struct.unpack_from("<I", data, base + 8)[0]
            praw = struct.unpack_from("<I", data, base + 20)[0]
            if vaddr <= rva < vaddr + max(vsize, 1):
                return praw + (rva - vaddr)
        raise SystemExit(f"{path}: RVA {rva:#x} not in any section")

    clr_off = rva_to_off(clr_rva)
    flags_off = clr_off + 16
    old = struct.unpack_from("<I", data, flags_off)[0]
    new = old & ~0x2 & ~0x20000  # drop 32BITREQUIRED and 32BITPREFERRED
    struct.pack_into("<I", data, flags_off, new)
    open(path, "wb").write(data)
    print(f"{path}: CorFlags {old:#x} -> {new:#x}")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        clear_flags(arg)
