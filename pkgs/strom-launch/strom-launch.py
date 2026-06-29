#!/usr/bin/env python3
"""XDG handler for the ``strom://<slug>`` URI scheme.

Invoked by the desktop when the web GUI's Play button navigates to
``strom://<slug>``. It validates the slug against the baked manifest (so a
crafted URL can never run an arbitrary ``nix`` target), then:

1. realizes the game with ``nix build`` while showing a real progress bar
   (driven by parsing ``--log-format internal-json`` activity events, which
   include the IPFS asset download emitted by lib/fetch-ipfs.nix), then
2. launches it with ``nix run`` (instant, everything is already in the store).

Progress UI degrades gracefully: zenity window -> notify-send phases ->
plain stderr.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

MANIFEST = Path(os.environ["STROM_MANIFEST"])
FLAKE_REF = os.environ.get("STROM_FLAKE", "github:kraftwerk-gaming/strom")

# Nix internal-json result type for incremental progress: fields are
# [done, expected, running, failed]. See nix's logging/JSON sink.
RESULT_PROGRESS = 105


def parse_slug(arg: str) -> str:
    """Extract the slug from ``strom://<slug>`` (or a bare slug)."""
    text = arg.strip()
    if "://" in text:
        text = urllib.parse.urlsplit(text).netloc or urllib.parse.urlsplit(
            text
        ).path.lstrip("/")
    text = text.rstrip("/")
    return urllib.parse.unquote(text)


class Progress:
    """Drives whatever progress UI is available."""

    def __init__(self, title: str) -> None:
        self.title = title
        self.proc: subprocess.Popen[str] | None = None
        self.notify = shutil.which("notify-send")
        zenity = shutil.which("zenity")
        if zenity:
            self.proc = subprocess.Popen(
                [
                    zenity,
                    "--progress",
                    "--auto-close",
                    "--no-cancel",
                    "--width=420",
                    f"--title={title}",
                    "--text=Preparing…",
                ],
                stdin=subprocess.PIPE,
                text=True,
            )

    def update(self, pct: int, msg: str) -> None:
        if self.proc and self.proc.stdin:
            try:
                self.proc.stdin.write(f"{pct}\n# {msg}\n")
                self.proc.stdin.flush()
            except BrokenPipeError:
                self.proc = None
        else:
            print(f"[{pct:3d}%] {msg}", file=sys.stderr)

    def phase(self, msg: str) -> None:
        if not self.proc and self.notify:
            subprocess.run([self.notify, "-a", "strom", self.title, msg], check=False)

    def close(self, pct: int = 100) -> None:
        if self.proc and self.proc.stdin:
            try:
                self.proc.stdin.write(f"{pct}\n")
                self.proc.stdin.close()
            except BrokenPipeError:
                pass
            self.proc.wait()
            self.proc = None


def build_with_progress(slug: str, prog: Progress) -> bool:
    """Run ``nix build`` for the game, feeding progress events to the UI.
    Returns True on success."""
    cmd = [
        "nix",
        "build",
        "--no-link",
        "--print-build-logs",
        "--log-format",
        "internal-json",
        f"{FLAKE_REF}#{slug}",
    ]
    proc = subprocess.Popen(cmd, stderr=subprocess.PIPE, text=True)
    assert proc.stderr is not None

    progress: dict[int, tuple[int, int]] = {}
    current = "Preparing…"
    for line in proc.stderr:
        line = line.rstrip("\n")
        if not line.startswith("@nix "):
            continue
        try:
            evt = json.loads(line[5:])
        except json.JSONDecodeError:
            continue
        action = evt.get("action")
        if action == "start":
            text = evt.get("text")
            if text:
                current = text
                prog.phase(text)
        elif action == "stop":
            progress.pop(evt.get("id", -1), None)
        elif action == "result" and evt.get("type") == RESULT_PROGRESS:
            fields = evt.get("fields") or []
            if len(fields) >= 2:
                progress[evt.get("id", -1)] = (int(fields[0]), int(fields[1]))

        done = sum(d for d, _ in progress.values())
        expected = sum(e for _, e in progress.values())
        pct = int(100 * done / expected) if expected else 0
        prog.update(min(pct, 99), current)

    proc.wait()
    return proc.returncode == 0


def notify_error(slug: str, msg: str) -> None:
    notify = shutil.which("notify-send")
    if notify:
        subprocess.run(
            [notify, "-u", "critical", "-a", "strom", f"strom: {slug}", msg],
            check=False,
        )
    print(f"strom: {slug}: {msg}", file=sys.stderr)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: strom-launch strom://<slug>", file=sys.stderr)
        return 2

    slug = parse_slug(argv[1])
    manifest = json.loads(MANIFEST.read_text())
    if slug not in manifest:
        notify_error(slug, "unknown game (not in strom manifest)")
        return 1

    name = (manifest[slug].get("description") or slug).split("(", 1)[0].strip()

    prog = Progress(f"Launching {name}")
    ok = build_with_progress(slug, prog)
    prog.close()
    if not ok:
        notify_error(slug, "build/download failed")
        return 1

    # Everything is in the store now; this returns when the game exits.
    result = subprocess.run(["nix", "run", f"{FLAKE_REF}#{slug}"], check=False)
    if result.returncode != 0:
        notify_error(slug, f"game exited with status {result.returncode}")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
