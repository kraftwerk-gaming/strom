"""
Force sxlrt233.dll to be relocated by Wine's loader so that its .reloc
table is applied and all internal absolute references are fixed up.

Background
----------
Both sxlrt233.dll and Low-Level Engine.dll (LLE) ship from GOG with PE
ImageBase 0x10000000.  sxlrt233 loads first, claims 0x10000000, and LLE is
forced to relocate.  LLE's packer stub has hardcoded absolute refs that
assume its own base is 0x10000000; when relocated those refs corrupt the
global array-pointer table and the first worker-thread read faults.

Round-1 fix attempted to move sxlrt233 by changing its ImageBase header to
0x11000000.  When ImageBase == load address Wine considers the DLL "already
at preferred base" and skips the relocation pass entirely.  sxlrt233's 9655
HIGHLOW .reloc entries were therefore never applied, leaving all internal
absolute refs still pointing into 0x10XXXXXX (now LLE's memory).  DllMain
then jumped through a stale IAT pointer to garbage (0x4E65636E) and
access-violated.

Round-2 fix (this script)
--------------------------
Set the DYNAMIC_BASE (ASLR) bit (0x0040) in the PE Optional Header's
DllCharacteristics field.  With DYNAMIC_BASE set, Wine's loader selects a
random base for the DLL regardless of its declared ImageBase, applies the
full .reloc section, and leaves 0x10000000 free for LLE.  The ImageBase
field is reset to 0x10000000 (original value) so the .reloc delta is
correctly calculated; only the 2-byte DllCharacteristics word changes on
disk.  The PE checksum is zeroed (Wine does not verify it).
"""

import struct
import sys


DYNAMIC_BASE = 0x0040  # IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE


def patch(path: str) -> None:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if data[:2] != b"MZ":
        raise ValueError(f"{path}: not an MZ binary")

    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off : pe_off + 4] != b"PE\x00\x00":
        raise ValueError(f"{path}: PE signature not found at 0x{pe_off:x}")

    opt_off = pe_off + 4 + 20
    magic = struct.unpack_from("<H", data, opt_off)[0]
    if magic != 0x010B:
        raise ValueError(
            f"{path}: expected PE32 optional header (0x010b), got 0x{magic:x}"
        )

    # --- Ensure ImageBase is the original 0x10000000 ---
    # (Round-1 changed it to 0x11000000; revert so the .reloc delta is computed
    # correctly when DYNAMIC_BASE forces the loader to pick a different address.)
    imagebase_off = opt_off + 28
    current_base = struct.unpack_from("<I", data, imagebase_off)[0]
    if current_base == 0x11000000:
        struct.pack_into("<I", data, imagebase_off, 0x10000000)
        print(f"{path}: ImageBase reverted 0x11000000 -> 0x10000000")
    elif current_base == 0x10000000:
        print(f"{path}: ImageBase already 0x10000000, no revert needed")
    else:
        print(f"{path}: ImageBase is 0x{current_base:08x} (unexpected, leaving as-is)")

    # --- Set DYNAMIC_BASE in DllCharacteristics ---
    dllchar_off = opt_off + 70
    current_flags = struct.unpack_from("<H", data, dllchar_off)[0]
    if current_flags & DYNAMIC_BASE:
        print(
            f"{path}: DYNAMIC_BASE already set (flags=0x{current_flags:04x}), nothing to do"
        )
        return
    new_flags = current_flags | DYNAMIC_BASE
    struct.pack_into("<H", data, dllchar_off, new_flags)
    print(
        f"{path}: DllCharacteristics 0x{current_flags:04x} -> 0x{new_flags:04x} "
        f"(DYNAMIC_BASE set)"
    )

    # Zero the PE checksum; Wine does not verify it and will recompute lazily.
    struct.pack_into("<I", data, opt_off + 64, 0)

    with open(path, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <sxlrt233.dll> [...]")
        sys.exit(1)
    for p in sys.argv[1:]:
        patch(p)
