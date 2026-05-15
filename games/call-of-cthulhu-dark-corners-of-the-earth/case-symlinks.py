#!/usr/bin/env python3
"""Round-13 case-insensitive view over the DCoTE install.

The engine's IO subsystem opens game data via case-sensitive paths
whose spellings come straight from the .rdata strings table of
CoCMainWin32.exe — e.g. ``MainMenu\\EngagingScreens\\%s`` or
``Resources\\Pc\\Shaders\\``. The GOG install lays directories down
with inconsistent case (``ENGAGINGSCREENS`` next to ``08_boat`` next
to ``misc03_asylum_cutscene``), so any open whose engine-string
spelling differs from the on-disk spelling fails silently and the
asset never loads.

Round-12 papered over one such miss (``courier new_23.abc``) with a
single lowercase symlink. Round-13 takes the systematic approach:

1. Walk the install tree depth-first. For each path component whose
   lowercase form differs from the on-disk form, add a sibling
   symlink under the lowercase name. (Engine strings sometimes use
   all-lower paths like ``courier new_23.abc``.)
2. Pull every path-like spelling out of the engine binary's strings
   and, for each component whose lowercase matches a disk entry but
   whose exact case does not exist on disk, add a sibling symlink
   under the engine's spelling.

Both passes never overwrite an existing entry, so a disk file that
already happens to match an engine spelling is left untouched.

Usage:
    case-symlinks.py <install-root> <CoCMainWin32.exe>
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


# A path-like component is ASCII alphanum + `_`, `.`, space.  Engine
# strings use `\\` separators almost everywhere but ``..\\MainMenu\\
# EngagingScreens\\%s`` also uses ``/`` in a couple of places.
_COMPONENT = re.compile(r"[A-Za-z0-9_. ][A-Za-z0-9_. ]*")
_PATH_LIKE = re.compile(rb"[A-Za-z0-9_. ][A-Za-z0-9_. \\/]+")


def extract_engine_spellings(exe: Path) -> set[str]:
    """Pull every path-component spelling out of the exe's strings.

    We don't try to parse full paths — instead split each path-like
    blob on ``\\`` / ``/`` and harvest every individual component.
    Components that match a `.cpp` debug-info path are skipped (those
    are filename pairs from the build's source tree, not game data).
    """
    out = subprocess.run(
        ["strings", "-n", "4", str(exe)],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.decode("latin-1", errors="replace")

    spellings: set[str] = set()
    for line in out.splitlines():
        # Skip C++ source debug-info paths (e.g. `.\CoCFoo.cpp`).
        if line.endswith(".cpp") or line.endswith(".h") or line.endswith(".hpp"):
            continue
        for component in re.split(r"[\\/]+", line):
            component = component.strip()
            if not component or component in (".", ".."):
                continue
            if not _COMPONENT.fullmatch(component):
                continue
            spellings.add(component)
    return spellings


def lowercase_pass(root: Path) -> int:
    """Pass 1: depth-first lowercase-symlink everything.

    Bottom-up so we never traverse into a freshly-created symlink.
    """
    n = 0
    # Sort by depth so deeper paths come first.
    paths = sorted(
        (p for p in root.rglob("*")),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for path in paths:
        name = path.name
        lower = name.lower()
        if name == lower:
            continue
        target = path.parent / lower
        if target.exists() or target.is_symlink():
            continue
        target.symlink_to(name)
        n += 1
    return n


def engine_spelling_pass(root: Path, spellings: set[str]) -> int:
    """Pass 2: add symlinks for every engine-string spelling.

    Build an index of each directory's children by lowercase name,
    then for each engine spelling whose lowercase form matches an
    on-disk child but whose exact spelling does not, add a symlink.
    """
    # Group engine spellings by their lowercase form.
    by_lower: dict[str, set[str]] = {}
    for s in spellings:
        by_lower.setdefault(s.lower(), set()).add(s)

    n = 0
    for dirpath, dirnames, filenames in os.walk(root):
        d = Path(dirpath)
        # Build a set of on-disk lowercase names in this directory.
        on_disk = {name.lower(): name for name in (dirnames + filenames)}
        for lower, variants in by_lower.items():
            if lower not in on_disk:
                continue
            actual = on_disk[lower]
            for variant in variants:
                if variant == actual:
                    continue
                target = d / variant
                if target.exists() or target.is_symlink():
                    continue
                target.symlink_to(actual)
                n += 1
    return n


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    exe = Path(sys.argv[2])

    spellings = extract_engine_spellings(exe)
    print(f"engine spellings extracted: {len(spellings)}", file=sys.stderr)

    n1 = lowercase_pass(root)
    print(f"lowercase symlinks added: {n1}", file=sys.stderr)

    n2 = engine_spelling_pass(root, spellings)
    print(f"engine-spelling symlinks added: {n2}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
