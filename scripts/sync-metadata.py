#!/usr/bin/env python3
"""Sync each game's flake-projected build keys into games/<slug>/metadata.json.

`cids`, `description` and `runtime` are pure projections of a game's
`default.nix` (flake eval via sync-metadata.nix). They are written into
`games/<slug>/metadata.json`, merged over any hand-authored keys (which are
left untouched), so the launcher and web GUI can read `runtime`, the Steam
fetch script can read `description`, and the web IPFS checker (web/index.html)
can pull them per-game from a Radicle node at runtime.

Only per-game files are touched: there is no shared games list to regenerate,
so concurrent game additions never conflict. Run after adding/removing a game.
"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
NIX_FILE = SCRIPT_DIR / "sync-metadata.nix"
ROOT = SCRIPT_DIR.parent
GAMES_DIR = ROOT / "games"


def get_metadata() -> dict[str, dict[str, str | list[str] | None]]:
    proc = subprocess.run(
        ["nix", "eval", "--json", "--file", str(NIX_FILE)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def filter_games(meta: dict) -> dict:
    return {slug: m for slug, m in meta.items() if (GAMES_DIR / slug).is_dir()}


def build_values(m: dict) -> dict:
    """The flake-projected build keys sync-metadata.py owns in metadata.json."""
    return {
        "cids": m.get("cids") or [],
        "description": m.get("description"),
        "runtime": m.get("runtime") or "unknown",
    }


def sync_metadata(games: dict) -> list[str]:
    """Merge each game's build keys into games/<slug>/metadata.json, preserving
    hand-authored keys. Returns the slugs whose file changed."""
    changed: list[str] = []
    for slug, m in games.items():
        path = GAMES_DIR / slug / "metadata.json"
        existing: dict = {}
        if path.exists():
            try:
                existing = json.loads(path.read_text())
            except json.JSONDecodeError:
                existing = {}
        merged = dict(existing)
        merged.update(build_values(m))
        payload = json.dumps(merged, indent=2, sort_keys=True) + "\n"
        if not path.exists() or path.read_text() != payload:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(payload)
            changed.append(slug)
    return changed


def main() -> None:
    games = filter_games(get_metadata())
    changed = sync_metadata(games)
    if changed:
        print(
            f"Updated {len(changed)} metadata.json file(s): {', '.join(sorted(changed))}"
        )
    else:
        print("All metadata.json build keys up to date")


if __name__ == "__main__":
    main()
