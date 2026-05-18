#!/usr/bin/env python3
"""Seed the wine user.reg with Rohankar's Steam-Deck registry fix.

The Rohankar repack ships `Registry_Fix_For_Steam_Deck.reg`, a UTF-16 LE
.reg file with `[HKEY_CURRENT_USER\\Software\\Lionhead Studios Ltd\\
Black & White\\...]` sections.  wine's on-disk `user.reg` format is
different:

  * one Header per section: `[Software\\\\Lionhead ...\\\\Black & White] <ts>`
    (HKEY_CURRENT_USER stripped, every backslash doubled, a unix
    timestamp appended).
  * value lines copied verbatim.

The previous sed-based converter mangled this because it tried to double
backslashes via repeated regex passes; deeper subkeys lost their leading
sections and the critical `[Software\\\\Lionhead Studios Ltd\\\\Black & White]`
header (with GameDir) never made it into user.reg.  Without GameDir the
engine has nowhere to find its install dir and exits silently.

Usage: seed-registry.py <reg-file> <user.reg> [--marker <key-fragment>]
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

# The Rohankar repack's Steam-Deck .reg hard-codes ScreenW=0x500 (1280) and
# ScreenH=0x320 (800), i.e. 1280x800.  Our gamescope nests at 1024x768 to
# match Black & White's native 4:3 aspect; if the registry tells the
# engine 1280x800 but xwayland only offers 1024x768, IDirectDraw7::
# SetDisplayMode silently falls back to a smaller mode and the result is
# letterboxed/stretched garbage.  Rewrite the screen dwords in-flight so
# they match the gamescope nested resolution.
SCREEN_W = 0x400  # 1024
SCREEN_H = 0x300  # 768
SCREEN_W_RE = re.compile(r'^("ScreenW"=dword:)[0-9a-fA-F]{8}\s*$')
SCREEN_H_RE = re.compile(r'^("ScreenH"=dword:)[0-9a-fA-F]{8}\s*$')


def read_reg(path: Path) -> str:
    raw = path.read_bytes()
    # UTF-16 LE with BOM is the standard Windows regedit export; some
    # editors save without BOM, so try both.
    if raw.startswith(b"\xff\xfe"):
        return raw.decode("utf-16-le")[1:]
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8")[1:]
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        return raw.decode("utf-8", errors="replace")


def convert(reg_text: str, ts: int) -> str:
    """Convert a regedit-format .reg into a user.reg fragment.

    Strips the HKEY_CURRENT_USER\\ prefix, doubles every backslash in
    section headers, and stamps each section with `ts` so wine accepts
    it on next load.  Values are passed through unchanged.
    """
    out: list[str] = []
    for line in reg_text.splitlines():
        line = line.strip("\r")
        if line.startswith("Windows Registry Editor"):
            continue
        # ignore HKLM exports (we only get HKCU here, but be defensive)
        if line.startswith("[HKEY_LOCAL_MACHINE\\"):
            continue
        if line.startswith("[HKEY_CURRENT_USER\\"):
            # Strip prefix; double remaining backslashes.
            inner = line[len("[HKEY_CURRENT_USER\\") : -1]
            doubled = inner.replace("\\", "\\\\")
            out.append("")
            out.append(f"[{doubled}] {ts}")
            continue
        # Force ScreenW/ScreenH to match gamescope's nested resolution
        # so DirectDraw7::SetDisplayMode lands on a mode xwayland can
        # actually serve.  Without this the seed re-introduces the
        # repack's 1280x800 values on every prefix wipe.
        m = SCREEN_W_RE.match(line)
        if m:
            out.append(f"{m.group(1)}{SCREEN_W:08x}")
            continue
        m = SCREEN_H_RE.match(line)
        if m:
            out.append(f"{m.group(1)}{SCREEN_H:08x}")
            continue
        out.append(line)
    # ensure a trailing newline
    out.append("")
    return "\n".join(out)


def patch_screen_resolution(user_reg: Path) -> None:
    """Rewrite ScreenW/ScreenH dwords in an existing user.reg.

    Runs unconditionally on every preRun so an earlier seed (which may
    have planted 1280x800 from the pre-rewrite source .reg) is brought
    in line with gamescope's nested resolution.  Idempotent and a no-op
    on prefixes where user.reg doesn't yet exist or doesn't contain the
    Black & White section.
    """
    if not user_reg.exists():
        return
    try:
        text = user_reg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    lines = text.splitlines(keepends=True)
    changed = False
    in_bw_setup = False
    for i, raw in enumerate(lines):
        stripped = raw.lstrip()
        if stripped.startswith("["):
            in_bw_setup = stripped.startswith(
                "[Software\\\\Lionhead Studios Ltd\\\\Black & White\\\\BWSetup]"
            )
            continue
        if not in_bw_setup:
            continue
        # raw may carry a trailing newline; preserve it.
        eol = ""
        body = raw
        if body.endswith("\r\n"):
            eol = "\r\n"
            body = body[:-2]
        elif body.endswith("\n"):
            eol = "\n"
            body = body[:-1]
        m = SCREEN_W_RE.match(body)
        if m:
            new = f"{m.group(1)}{SCREEN_W:08x}"
            if new != body:
                lines[i] = new + eol
                changed = True
            continue
        m = SCREEN_H_RE.match(body)
        if m:
            new = f"{m.group(1)}{SCREEN_H:08x}"
            if new != body:
                lines[i] = new + eol
                changed = True
    if changed:
        user_reg.write_text("".join(lines), encoding="utf-8")


def already_seeded(user_reg: Path, marker: str) -> bool:
    if not user_reg.exists():
        return False
    try:
        text = user_reg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return marker in text


def ensure_user_reg(user_reg: Path) -> None:
    """Create a minimal user.reg header if proton hasn't yet."""
    if user_reg.exists():
        return
    user_reg.parent.mkdir(parents=True, exist_ok=True)
    user_reg.write_text(
        "WINE REGISTRY Version 2\n"
        ";; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n",
        encoding="utf-8",
    )


def strip_sections(user_reg: Path, prefix: str) -> None:
    """Remove any existing top-level sections whose header starts with prefix.

    A section runs from its `[...]` header up to (but excluding) the next
    `[`-prefixed header or EOF.  Used to evict garbage left by previous
    failed seed attempts so the fresh seed isn't shadowed by partial
    dupes.
    """
    if not user_reg.exists():
        return
    text = user_reg.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines(keepends=True)
    kept: list[str] = []
    drop = False
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("["):
            drop = stripped.startswith(prefix)
        if not drop:
            kept.append(line)
    user_reg.write_text("".join(kept), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("reg_file", type=Path)
    ap.add_argument("user_reg", type=Path)
    ap.add_argument(
        "--marker",
        default="Software\\\\Lionhead Studios Ltd\\\\Black & White]",
        help="Substring that, if present in user.reg, signals the seed already ran.",
    )
    ap.add_argument(
        "--strip-prefix",
        default="[Software\\\\Lionhead Studios Ltd\\\\Black & White",
        help=(
            "Strip pre-existing sections whose header starts with this prefix "
            "before seeding.  Removes the partial/garbage subkeys an earlier "
            "broken seed (the sed pipeline shipped in stage commit 21eb973) "
            "may have left in user.reg."
        ),
    )
    args = ap.parse_args()

    if not args.reg_file.is_file():
        print(f"seed-registry: {args.reg_file}: not found", file=sys.stderr)
        return 1

    if already_seeded(args.user_reg, args.marker):
        # Always reconcile screen dwords even if the seed already ran,
        # so prefixes created by earlier stage builds (which seeded
        # 1280x800) get fixed without a wipe.
        patch_screen_resolution(args.user_reg)
        return 0

    ensure_user_reg(args.user_reg)
    if args.strip_prefix:
        strip_sections(args.user_reg, args.strip_prefix)
    reg_text = read_reg(args.reg_file)
    fragment = convert(reg_text, int(time.time()))

    with args.user_reg.open("a", encoding="utf-8") as fh:
        fh.write("\n")
        fh.write(fragment)
    return 0


if __name__ == "__main__":
    sys.exit(main())
