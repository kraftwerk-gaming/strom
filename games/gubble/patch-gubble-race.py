#!/usr/bin/env python3
"""Startup-state-machine fix for Gubble (Actual Entertainment 1996).

The retail GUBBLECD.EXE crashes within a few seconds of launch:

  EXCEPTION_ACCESS_VIOLATION at VA 0x00410713 inside the per-frame
  render loop fcn.00410690, on `movsx eax, word [esi + 6]` with esi
  derived from an uninitialized per-entry pointer (dword [edi + 0x14]).

Root cause: the window-class / main-init function fcn.0040cb70 seeds
the screen-state machine selector with

    0x0040cb73  c6 05 b8 f3 4d 00 0a   mov byte [0x004df3b8], 0xa

so the very first dispatch through fcn.0040d410's switch table jumps
straight to case 10 (the gameplay render path: fcn.00410690), skipping
cases 0..6 (intro / loaders) and case 7 (fcn.0040e8a0, which is the
function that actually promotes the gameplay state byte 0x004d8460 to
0x14 and wires up the per-screw struct array at 0x004d5928). With no
level data wired up yet, the per-entry pointers at [edi + 0x14] are
zero, and the indexed read off them faults.

Fix: change the immediate from 0x0a to 0x00 so the dispatcher starts
at case 0 (fcn.00417d20, the bootstrap step). The intro/menu state
machine then progresses cases 0->1->2->...->7 (gameplay init,
including 0x004d8460=0x14 and the per-screw setup) ->8->9->10
(render), so by the time fcn.00410690 fires the per-entry pointers
are valid.

The selector byte itself is incremented elsewhere as the intro
progresses; we are only changing its initial value.

Patches a single byte. Independent of patch-gubble-nocd.py; order is
not significant.
"""

from __future__ import annotations

import sys
from pathlib import Path

# `mov byte [0x004df3b8], 0xa` at VA 0x0040cb73 -> file 0x0000BF73.
# The 7-byte instruction's immediate is the 7th byte.
INSTR_OFFSET = 0x0000BF73
INSTR_ORIGINAL = bytes.fromhex("c605b8f34d000a")
# Same instruction, immediate 0x00 instead of 0x0a.
INSTR_PATCH = bytes.fromhex("c605b8f34d0000")


def apply(path: Path) -> None:
    buf = bytearray(path.read_bytes())
    cur = bytes(buf[INSTR_OFFSET : INSTR_OFFSET + len(INSTR_ORIGINAL)])
    if cur != INSTR_ORIGINAL:
        raise SystemExit(
            f"GubbleCD.exe race fix: bytes at {INSTR_OFFSET:#x} are "
            f"{cur.hex()}, expected {INSTR_ORIGINAL.hex()}"
        )
    buf[INSTR_OFFSET : INSTR_OFFSET + len(INSTR_PATCH)] = INSTR_PATCH
    path.write_bytes(bytes(buf))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <GubbleCD.exe>", file=sys.stderr)
        return 2
    apply(Path(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
