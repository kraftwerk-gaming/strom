#!/usr/bin/env python3
"""Assemble the merged display catalog from per-game metadata.

Usage: assemble-catalog.py GAMES_DIR GAMES_JSON [> catalog.json]

Each game contributes up to two files under games/<slug>/:
  - steam.json     Steam-fetched fields (name, genres, tags, screenshots, ...)
  - metadata.json  hand-maintained data: corrections overlaid on steam.json for
                   Steam games, or the whole entry for off-Steam games. Keys
                   starting with "_" are comments; "appid" is a directive for
                   scripts/fetch-steam-metadata.py, not a display field.

The merged entry is steam.json overlaid by metadata.json (minus _*/appid), plus
runtime from games.json. Only games with at least one of the two files are
included, so the output matches what the old committed catalog.json held. This
is the single source of merge truth, shared by pkgs/launcher and pkgs/gui.
"""

import json
import os
import sys


def main() -> int:
    games_dir, games_json = sys.argv[1], sys.argv[2]
    games = json.loads(open(games_json).read())
    catalog: dict = {}
    for slug in sorted(games):
        d = os.path.join(games_dir, slug)
        sp, mp = os.path.join(d, "steam.json"), os.path.join(d, "metadata.json")
        steam = json.loads(open(sp).read()) if os.path.exists(sp) else None
        md = json.loads(open(mp).read()) if os.path.exists(mp) else None
        if steam is None and md is None:
            continue
        entry = dict(steam or {})
        for k, v in (md or {}).items():
            if k.startswith("_") or k == "appid":
                continue
            entry[k] = v
        entry["runtime"] = games[slug].get("runtime", "unknown")
        catalog[slug] = entry
    json.dump(catalog, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
