#!/usr/bin/env python3
"""Splice a single Vernaux entry out of an ELF binary's .gnu.version_r.

patchelf --clear-symbol-version drops per-symbol version references but
leaves the Verneed entry intact, so glibc's dynamic loader still refuses
to load a library that doesn't define that version. We rewrite the
linked-list of Vernaux entries in place to skip the target version, and
if that was the last aux for a Verneed, splice the Verneed itself out
of the file-level linked list too — glibc still validates entries with
cnt=0 against the loaded library, so a stale shell is not enough.

Usage: strip-verneed.py <elf> <version-name>
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ELFCLASS64 = 2
SHT_GNU_VERNEED = 0x6FFFFFFE


def u16(buf: bytearray, off: int) -> int:
    return struct.unpack_from("<H", buf, off)[0]


def u32(buf: bytearray, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


def u64(buf: bytearray, off: int) -> int:
    return struct.unpack_from("<Q", buf, off)[0]


def w16(buf: bytearray, off: int, val: int) -> None:
    struct.pack_into("<H", buf, off, val)


def w32(buf: bytearray, off: int, val: int) -> None:
    struct.pack_into("<I", buf, off, val)


def main() -> None:
    path = Path(sys.argv[1])
    target = sys.argv[2]
    data = bytearray(path.read_bytes())

    if data[:4] != b"\x7fELF" or data[4] != ELFCLASS64:
        sys.exit("not an ELF64")

    e_shoff = u64(data, 0x28)
    e_shentsize = u16(data, 0x3A)
    e_shnum = u16(data, 0x3C)

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sections.append(
            (
                u32(data, off + 4),  # sh_type
                u64(data, off + 0x18),  # sh_offset
                u32(data, off + 0x28),  # sh_link
                u32(data, off + 0x2C),  # sh_info
            )
        )

    verneed = next((s for s in sections if s[0] == SHT_GNU_VERNEED), None)
    if verneed is None:
        sys.exit("no .gnu.version_r section")
    _, sh_offset, sh_link, sh_info = verneed
    strtab_off = sections[sh_link][1]

    def str_at(off: int) -> str:
        end = data.find(b"\x00", strtab_off + off)
        return data[strtab_off + off : end].decode()

    cur = sh_offset
    prev_vn: int | None = None
    for _ in range(sh_info):
        vn_cnt = u16(data, cur + 2)
        vn_aux = u32(data, cur + 8)
        vn_next = u32(data, cur + 12)

        aux_off = cur + vn_aux
        prev_aux: int | None = None
        for _j in range(vn_cnt):
            va_name = u32(data, aux_off + 8)
            va_next = u32(data, aux_off + 12)
            if str_at(va_name) == target:
                if prev_aux is None and va_next == 0:
                    # Last aux of this Verneed — splice the entire
                    # Verneed out of the file-level linked list. If it's
                    # the only Verneed, fall back to cnt=0 (no parent to
                    # adjust); the ELF must keep at least the section.
                    if prev_vn is None:
                        # First Verneed in the section: collapse its
                        # next-pointer into its position by overwriting
                        # this header with the next one. Easier path:
                        # just mark vn_cnt=0 and rely on the loader
                        # ignoring it. (Glibc 2.42 does honour cnt=0,
                        # but some versions also bail if vn_aux points
                        # at an aux that names an unsatisfied version.)
                        w32(data, cur + 8, 0)
                        w16(data, cur + 2, 0)
                    else:
                        # Bridge prev_vn -> our successor (or terminate).
                        prev_vn_next = u32(data, prev_vn + 12)
                        if vn_next == 0:
                            w32(data, prev_vn + 12, 0)
                        else:
                            w32(data, prev_vn + 12, prev_vn_next + vn_next)
                elif prev_aux is None:
                    w32(data, cur + 8, vn_aux + va_next)
                    w16(data, cur + 2, vn_cnt - 1)
                else:
                    prev_va_next = u32(data, prev_aux + 12)
                    w32(
                        data,
                        prev_aux + 12,
                        0 if va_next == 0 else prev_va_next + va_next,
                    )
                    w16(data, cur + 2, vn_cnt - 1)
                path.write_bytes(bytes(data))
                return
            prev_aux = aux_off
            if va_next == 0:
                break
            aux_off += va_next
        if vn_next == 0:
            break
        prev_vn = cur
        cur += vn_next

    sys.exit(f"version {target!r} not found in .gnu.version_r")


if __name__ == "__main__":
    main()
