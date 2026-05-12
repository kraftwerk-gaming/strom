#!/usr/bin/env python3
"""Patch GOG Interstate '76 Arsenal i76.exe in place.

Three independent fixes, applied to the same exe:

1. CD-2 check bypass. i76.exe scans A..Z via GetVolumeInformationA looking
   for a CDROM drive labeled "I76_CD2" (or "I76_CD") and refuses to start
   when none matches. There are four scan functions; each is rewritten to
   short-circuit to "found at drive E:".

2. CPU-speed measurement crash. The routine at 0x499950 issues `cli`/`sti`
   and PIT I/O, which fault under a non-root user wineprefix. The call to
   it at 0x499b25 is replaced with `mov eax, 200` (same as i76fix patch 1).

3. 25-fps frame loop cap (i76fix patches 2/4/5/6). I'76 ties physics to
   frame rate — uncapped, the sky and AI run at 10-20x speed. Patch 2
   shortens an error string in .data to free 8 bytes for two DWORD globals
   (pSleep, LastTick). Patch 4 appends a draw_delay() thunk to .text slack
   space (Sleep-based 42ms gate per frame). Patch 5 redirects the call at
   VA 0x4039B8 through draw_delay; patch 6 chains draw_delay back to the
   original target.

Reference: https://github.com/immi101/i76fix (patch.s / patcher.c).
"""

from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

IMAGE_BASE = 0x400000


# ---------- CD-2 + CPU patches ----------

# Stub:  mov [0x58d92c],'E' ; mov [0x58d930],1 ; mov eax,1 ; ret  (23 bytes)
_STUB_RET = bytes.fromhex("c6052cd9580045c70530d9580001000000b801000000c3")
# Same stub but ending in a relative jmp instead of ret. Used for the
# fourth scan-site which lives inside a function whose post-scan tail
# (function-pointer init, install.dat open) still has to run.
_STUB_JMP = bytes.fromhex("c6052cd9580045c70530d9580001000000e9a3000000")

# (file_offset, bytes) — see module docstring for what each one does.
SIMPLE_PATCHES: list[tuple[int, bytes]] = [
    (0x70190, _STUB_RET),  # VA 0x470d90  generic "Please insert CD" loop
    (0x702d0, _STUB_RET),  # VA 0x470ed0  silent "I76_CD2" presence check
    (0x70390, _STUB_RET),  # VA 0x470f90  auth-path "I76_CD2" scan
    (0x706b6, _STUB_JMP),  # VA 0x4712b6  startup init, jmp to post-scan
    (0x98f25, bytes.fromhex("b8c8000000")),  # VA 0x499b25  mov eax,200
]


# ---------- i76fix patches 2 / 4 / 5 / 6 ----------

PATCH2_OFS = 0x4C25C0
PATCH5_OFS = 0x4039B8

PATCH2_STRING = b"Unable Allocate Virtual Memory, aborting...\x00"
PATCH2_PAYLOAD = PATCH2_STRING + b"\x00" * 8
assert len(PATCH2_STRING) == 0x2C
assert len(PATCH2_PAYLOAD) == 0x34

# 120 bytes (0x78) extracted from `i686-w64-mingw32-as patch.s
# --defsym TARGET=1` between symbols p4_code and p4_end. Absolute IAT
# references (call *0x4bc100, mov $0x4c25f0, etc.) are pre-resolved for
# TARGET=1. Self-relative jumps inside the body stay valid wherever we
# drop it into .text slack. The only spot patch 6 needs to fix is the
# 5-byte `jmp 0x444444` placeholder at offset 0x3c.
PATCH4_BODY = bytes.fromhex(
    "53"
    "ff1500c14b00"  # call *0x4bc100  (GetTickCount)
    "baf0254c00"  # mov $0x4c25f0,%edx (LastTick)
    "8b0a"  # mov (%edx),%ecx
    "85c9"
    "7427"  # je out
    "89c3"
    "29cb"
    "83fb27"  # cmp $0x27,%ebx (TargetDelay-3 = 39)
    "7f1e"  # jg out
    "a1ec254c00"  # mov 0x4c25ec,%eax (pSleep)
    "85c0"
    "742c"  # je fetch_func
    "ba2a000000"  # mov $0x2a,%edx (TargetDelay = 42)
    "29da"
    "52"
    "ffd0"
    "ff1500c14b00"  # call *0x4bc100
    "baf0254c00"  # mov $0x4c25f0,%edx
    "8902"
    "5b"
    "e9f6454400"  # jmp 0x444444  (placeholder — patch 6 fixes the rel32)
    "6b65726e656c333200"  # "kernel32\0"
    "536c65657000"  # "Sleep\0"
    "56"
    "e800000000"  # call ss
    "5e"
    "83ee15"
    "56"
    "ff15ecc04b00"  # call *0x4bc0ec (GetModuleHandleA)
    "83c609"
    "56"
    "50"
    "ff15a0c04b00"  # call *0x4bc0a0 (GetProcAddress)
    "5e"
    "85c0"
    "74c8"
    "a3ec254c00"  # mov %eax,0x4c25ec (pSleep)
    "ebac"  # jmp do_sleep
)
assert len(PATCH4_BODY) == 0x78

JMP_CONT_OPCODE_OFS = 0x3C  # `e9 xx xx xx xx` inside PATCH4_BODY


# ---------- PE helpers ----------


def _parse_pe(buf: bytes) -> list[dict]:
    e_lfanew = struct.unpack_from("<I", buf, 0x3C)[0]
    if buf[e_lfanew : e_lfanew + 4] != b"PE\x00\x00":
        raise ValueError("not a PE file")
    num_sec = struct.unpack_from("<H", buf, e_lfanew + 4 + 2)[0]
    size_opt = struct.unpack_from("<H", buf, e_lfanew + 4 + 16)[0]
    sec_off = e_lfanew + 24 + size_opt

    sections = []
    for i in range(num_sec):
        o = sec_off + i * 40
        name = buf[o : o + 8].rstrip(b"\x00").decode("ascii", "replace")
        vs, va, rs, rp = struct.unpack_from("<IIII", buf, o + 8)
        sections.append(
            {
                "name": name,
                "va": va,
                "vs": vs,
                "raw_size": rs,
                "raw_ptr": rp,
                "header_off": o,
            }
        )
    return sections


def _section_by_name(sections: list[dict], name: str) -> dict:
    for s in sections:
        if s["name"] == name:
            return s
    raise KeyError(name)


def _va_to_file(sections: list[dict], va: int) -> int:
    rva = va - IMAGE_BASE
    for s in sections:
        if s["va"] <= rva < s["va"] + s["raw_size"]:
            return s["raw_ptr"] + (rva - s["va"])
    raise ValueError(f"no section covers VA {va:#x}")


def _rewrite_rel32(
    buf: bytearray, file_off: int, instr_va: int, new_target_va: int
) -> int:
    opcode = buf[file_off]
    if opcode not in (0xE8, 0xE9):
        raise ValueError(f"expected E8/E9 at VA {instr_va:#x}, got {opcode:#04x}")
    rel = struct.unpack_from("<i", buf, file_off + 1)[0]
    orig_target = (instr_va + 5 + rel) & 0xFFFFFFFF
    new_rel = new_target_va - instr_va - 5
    struct.pack_into("<i", buf, file_off + 1, new_rel)
    return orig_target


# ---------- driver ----------


def apply(path: Path) -> None:
    buf = bytearray(path.read_bytes())
    orig_size = len(buf)

    for off, data in SIMPLE_PATCHES:
        buf[off : off + len(data)] = data

    sections = _parse_pe(buf)
    text = _section_by_name(sections, ".text")

    p2_file = _va_to_file(sections, PATCH2_OFS)
    buf[p2_file : p2_file + len(PATCH2_PAYLOAD)] = PATCH2_PAYLOAD

    slack = text["raw_size"] - text["vs"]
    if slack < len(PATCH4_BODY):
        raise RuntimeError(
            f".text slack {slack:#x} < patch4 {len(PATCH4_BODY):#x}"
        )
    patch4_va = IMAGE_BASE + text["va"] + text["vs"]
    patch4_file = text["raw_ptr"] + text["vs"]
    buf[patch4_file : patch4_file + len(PATCH4_BODY)] = PATCH4_BODY
    struct.pack_into(
        "<I", buf, text["header_off"] + 8, text["vs"] + len(PATCH4_BODY)
    )

    p5_file = _va_to_file(sections, PATCH5_OFS)
    orig_target = _rewrite_rel32(buf, p5_file, PATCH5_OFS, patch4_va)

    jmp_va = patch4_va + JMP_CONT_OPCODE_OFS
    jmp_file = patch4_file + JMP_CONT_OPCODE_OFS
    _rewrite_rel32(buf, jmp_file, jmp_va, orig_target)

    if len(buf) != orig_size:
        raise RuntimeError("file size changed unexpectedly")

    path.write_bytes(bytes(buf))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <i76.exe>", file=sys.stderr)
        return 2
    apply(Path(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
