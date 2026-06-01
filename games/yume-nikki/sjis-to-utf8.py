#!/usr/bin/env python3
"""Recursively re-encode CP932 (Shift-JIS) asset filenames to UTF-8.

Yume Nikki's RPG Maker 2003 data ships its asset filenames -- System
graphics, CharSets, Sounds, ... -- as raw Shift-JIS bytes (that's what the
.lzh stores and what lhasa writes to disk verbatim). RPG_RT.exe opens them
through the Win32 ANSI API.

Under Proton we run the prefix with LC_ALL=ja_JP.UTF-8 so Wine's ANSI
codepage is 932 and the engine's Shift-JIS *text* renders correctly. But
that same locale makes Wine's *unix* filesystem encoding UTF-8: when the
engine asks to open `マイシステムa.xyz`, Wine encodes that name as UTF-8
before hitting the host filesystem, while the file on disk still carries
the original Shift-JIS bytes. The two byte sequences differ, the open
fails, and RPG_RT pops `ファイル <name> は開けません` ("cannot open file").

Renaming every Shift-JIS filename to its UTF-8 form at build time makes the
on-disk bytes match what Wine looks up. Walk bottom-up so a renamed
directory never invalidates a not-yet-processed child path.
"""

from __future__ import annotations

import os
import sys


def main(root: str) -> int:
    converted = 0
    skipped = 0
    for dirpath, dirnames, filenames in os.walk(os.fsencode(root), topdown=False):
        for name in filenames + dirnames:
            try:
                name.decode("ascii")
                continue  # pure ASCII: nothing to do
            except UnicodeDecodeError:
                pass
            try:
                decoded = name.decode("shift_jis")
            except UnicodeDecodeError:
                # Not Shift-JIS (already UTF-8, or some other encoding);
                # leave it untouched rather than corrupt it.
                skipped += 1
                continue
            utf8 = decoded.encode("utf-8")
            if utf8 == name:
                continue  # bytes already coincide (rare, ASCII-ish)
            src = os.path.join(dirpath, name)
            dst = os.path.join(dirpath, utf8)
            os.rename(src, dst)
            converted += 1
    print(f"sjis-to-utf8: renamed {converted} entries, skipped {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
