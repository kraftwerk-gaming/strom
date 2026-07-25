#!/usr/bin/env bash
# Pre-commit hook: re-run scripts/generate-readme.py and fail if it changes any
# generated file -- the README games table, each game's metadata.json build keys
# (cids/description/runtime), or the web/index.html checker dataset. Regenerated
# files are left in the working tree so they can be staged before re-committing.
set -euo pipefail

# `nix eval` is required by the generator; in sandboxed contexts (e.g.
# `nix flake check`) it isn't available, so skip rather than failing.
if ! command -v nix >/dev/null 2>&1; then
    echo "nix not on PATH; skipping generated-file freshness check." >&2
    exit 0
fi

python3 scripts/generate-readme.py

paths=(README.md web/index.html)
while IFS= read -r f; do
    paths+=("$f")
done < <(git ls-files 'games/*/metadata.json')

if ! git diff --quiet -- "${paths[@]}"; then
    echo "scripts/generate-readme.py regenerated:" >&2
    git diff --name-only -- "${paths[@]}" | sed 's/^/  - /' >&2
    echo "Stage the updated files and commit again." >&2
    exit 1
fi
