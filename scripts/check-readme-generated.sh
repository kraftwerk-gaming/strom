#!/usr/bin/env bash
# Pre-commit hook: re-run scripts/generate-readme.py and fail if either
# README.md or web/games.json changed. The regenerated files are left in the
# working tree so they can be staged before re-committing.
set -euo pipefail

# `nix eval` is required by the generator; in sandboxed contexts (e.g.
# `nix flake check`) it isn't available, so skip rather than failing.
if ! command -v nix >/dev/null 2>&1; then
    echo "nix not on PATH; skipping README/games.json freshness check." >&2
    exit 0
fi

hash_file() {
    if [ -f "$1" ]; then
        sha256sum "$1" | cut -d' ' -f1
    else
        echo "missing"
    fi
}

before_readme=$(hash_file README.md)
before_games=$(hash_file web/games.json)

python3 scripts/generate-readme.py

after_readme=$(hash_file README.md)
after_games=$(hash_file web/games.json)

changed=()
[ "$before_readme" != "$after_readme" ] && changed+=("README.md")
[ "$before_games" != "$after_games" ] && changed+=("web/games.json")

if [ "${#changed[@]}" -gt 0 ]; then
    echo "scripts/generate-readme.py regenerated:" >&2
    for f in "${changed[@]}"; do
        echo "  - $f" >&2
    done
    echo "Stage the updated files and commit again." >&2
    exit 1
fi
