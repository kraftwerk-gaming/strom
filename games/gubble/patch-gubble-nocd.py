#!/usr/bin/env python3
"""NoCD patch for Gubble (Actual Entertainment 1996) GubbleCD.exe.

The retail binary calls a routine at VA 0x0040c2e0 before the title
screen. That routine scans A..Z via GetDriveTypeA, looks for any
DRIVE_CDROM, then fopen()s "%c:\\setup\\gubblecd.exe" off the matched
drive; only if that succeeds does it return 1 (CD present). On failure
it pops a "Please insert the Gubble CD." MessageBox and re-scans.

BUT it does one more critically important thing as a side effect: when
it finds the CD, it sprintf's `"%c:\\setup\\data\\"` into the BSS
buffer at 0x004444be0. Every BMP / introlev / movies loader in the
game (fcn.0040bc90, fcn.0040bd60, fcn.004033e0, ...) pushes 0x004444be0
as the first %s in format strings like "%smovies\\%s.bmp" or
"%sintrolev\\%s". With 0x004444be0 unset (BSS = empty string), every
constructed path becomes a bare "movies\\a_logo.bmp" / "introlev\\..."
relative to CWD, and since CWD is `<install>\\setup\\`, the actual
assets at `<install>\\setup\\data\\movies\\...` are never found.

Result of "just make CD-check return 1" (the obvious naive bypass):
the title screen never paints (every bitmap load fails), the per-screw
struct array at 0x004d5928 stays zeroed because fcn.00410400 bails
when fcn.0040bc90 returns 0, and the render loop fcn.00410690 faults
at VA 0x00410713 on a NULL [esi + 6] derived from
dword [edi + 0x14] = 0. Black-screen-then-EXCEPTION_ACCESS_VIOLATION.

Fix: replace the function entry with a stub that (a) writes the
literal string "data\\" + NUL into 0x004444be0 (so every later loader
constructs `data\\introlev\\...` etc., which resolves relative to the
running CWD of `<install>\\setup\\` and matches the on-disk layout
`<install>\\setup\\data\\introlev\\...`), and (b) returns 1
unconditionally. The stub uses only immediate-store instructions, so
no imports / relocations are needed.

Replacement assembly (25 bytes, fits inside the original 190-byte
function so the tail becomes dead code after `ret`):

    c7 05 e0 4b 44 00 64 61 74 61   mov dword [0x444be0], 'atad'
    66 c7 05 e4 4b 44 00 5c 00      mov word  [0x444be4], 0x005c
    b8 01 00 00 00                  mov eax, 1
    c3                              ret

The original 7-byte preamble `53 8B 1D E4 42 4E 00` (push ebx; mov
ebx,[GetDriveTypeA]) is the assertion anchor; we overwrite 25 bytes.

GameCopyWorld, GameBurnWorld, MegaGames and the Internet Archive have
no community NoCD listed for this title, so we apply this in-tree.
"""

from __future__ import annotations

import sys
from pathlib import Path

# File offset of the CD-scan function (VA 0x0040c2e0 in .text; the
# VA-to-file delta is 0x00400c00, cross-checked against other in-tree
# patches at this binary's text section).
PATCH_OFFSET = 0x0000B6E0
# First 7 bytes of the original CD-scan function. We only need to
# match these as a sanity-check anchor; the actual rewrite is 25 bytes.
ORIGINAL_BYTES = bytes.fromhex("538b1de4424e00")
# Stub:
#   mov dword [0x004444be0], 'atad'   ; "data" little-endian
#   mov word  [0x004444be4], 0x005c   ; "\\\0"
#   mov eax, 1
#   ret
PATCH_BYTES = bytes.fromhex(
    "c705e04b440064617461"  # mov dword [0x444be0], 0x61746164
    "66c705e44b44005c00"  # mov word  [0x444be4], 0x005c
    "b801000000"  # mov eax, 1
    "c3"  # ret
)
assert len(PATCH_BYTES) == 25


def apply(path: Path) -> None:
    buf = bytearray(path.read_bytes())
    cur = bytes(buf[PATCH_OFFSET : PATCH_OFFSET + len(ORIGINAL_BYTES)])
    if cur != ORIGINAL_BYTES:
        raise SystemExit(
            f"GubbleCD.exe NoCD patch: bytes at {PATCH_OFFSET:#x} are "
            f"{cur.hex()}, expected {ORIGINAL_BYTES.hex()}"
        )
    buf[PATCH_OFFSET : PATCH_OFFSET + len(PATCH_BYTES)] = PATCH_BYTES
    path.write_bytes(bytes(buf))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <GubbleCD.exe>", file=sys.stderr)
        return 2
    apply(Path(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
