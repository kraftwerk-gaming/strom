#!/usr/bin/env python3
"""Assemble the merged display catalog from per-game metadata.

Usage: assemble-catalog.py GAMES_DIR [> catalog.json]

Each game contributes up to two files under games/<slug>/:
  - steam.json     Steam-fetched fields (name, genres, tags, screenshots, ...)
  - metadata.json  hand-maintained data plus flake-projected build keys
                   (cids, description, runtime) written by generate-readme.py.
                   Keys starting with "_", plus "appid", "cids" and the flake
                   "description", are not display fields; "appid" is a directive
                   for scripts/fetch-steam-metadata.py.

The merged entry is steam.json overlaid by metadata.json's display fields, plus
`runtime` taken from metadata.json. Only games with at least one of the two
files are included. This is the single source of merge truth, shared by
pkgs/launcher and pkgs/gui.
"""

import json
import os
import sys

# metadata.json keys that are not display fields (never copied into the catalog
# as-is). "runtime" is handled explicitly below.
NON_DISPLAY = {"appid", "cids", "description", "runtime"}


def load(path: str) -> dict | None:
    return json.loads(open(path).read()) if os.path.exists(path) else None


def main() -> int:
    games_dir = sys.argv[1]
    slugs = sorted(
        d for d in os.listdir(games_dir) if os.path.isdir(os.path.join(games_dir, d))
    )
    catalog: dict = {}
    for slug in slugs:
        d = os.path.join(games_dir, slug)
        steam = load(os.path.join(d, "steam.json"))
        md = load(os.path.join(d, "metadata.json")) or {}
        display = {
            k: v
            for k, v in md.items()
            if not k.startswith("_") and k not in NON_DISPLAY
        }
        # A game with no steam.json and no hand-authored display fields (only the
        # flake-projected build keys) is not a catalog tile, just as before.
        if steam is None and not display:
            continue
        entry = dict(steam or {})
        entry.update(display)
        entry["runtime"] = md.get("runtime", "unknown")
        catalog[slug] = entry
    json.dump(catalog, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
