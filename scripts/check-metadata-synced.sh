#!/usr/bin/env bash
# Pre-commit hook: re-run scripts/sync-metadata.py and fail if any game's
# metadata.json build keys (cids/description/runtime) are stale relative to the
# flake. These are per-game files, so this never causes cross-branch conflicts.
# Regenerated files are left in the working tree so they can be staged before
# re-committing.
set -euo pipefail

# `nix eval` is required by the sync script; in sandboxed contexts (e.g.
# `nix flake check`) it isn't available, so skip rather than failing.
if ! command -v nix >/dev/null 2>&1; then
    echo "nix not on PATH; skipping metadata sync check." >&2
    exit 0
fi

python3 scripts/sync-metadata.py

if ! git diff --quiet -- 'games/*/metadata.json'; then
    echo "scripts/sync-metadata.py updated metadata.json build keys:" >&2
    git diff --name-only -- 'games/*/metadata.json' | sed 's/^/  - /' >&2
    echo "Stage the updated files and commit again." >&2
    exit 1
fi
