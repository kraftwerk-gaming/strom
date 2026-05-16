#!/usr/bin/env bash
# Disk-budget gate for packaging agents.
#
# Print free space on the partitions a packaging agent will write to,
# refuse to proceed (exit 1) if any is below threshold.
#
# Defaults: refuse if /home or /nix has < 30G free (configurable via env).
#
# Usage:
#   scripts/check-disk-budget.sh               # gate with defaults
#   MIN_HOME_GB=10 MIN_NIX_GB=20 scripts/check-disk-budget.sh
#   scripts/check-disk-budget.sh --report      # just print, never fail
#
# Why: packaging a multi-GB game seeds the asset into /nix/store (one copy)
# and stages it in the worktree's tmp/ (another copy). Three or four
# concurrent agents can balloon peak disk by 30-60 GiB. ENOSPC during
# `nix store add-file` or `nix build` is a wedge case - the daemon dies,
# pueue dies, the agent goes into a self-poll loop.

set -euo pipefail

MIN_HOME_GB="${MIN_HOME_GB:-30}"
MIN_NIX_GB="${MIN_NIX_GB:-30}"

free_gb() {
    # Resolve mountpoint for a given path, return free GiB.
    local path=$1
    df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -d ' G'
}

home_free=$(free_gb /home)
nix_free=$(free_gb /nix)

report() {
    printf 'home(/): %s GiB free (threshold %s GiB)\n' "$home_free" "$MIN_HOME_GB"
    printf 'nix(/nix): %s GiB free (threshold %s GiB)\n' "$nix_free" "$MIN_NIX_GB"
}

case "${1:-}" in
--report)
    report
    exit 0
    ;;
"") ;;
*)
    echo "unknown arg: $1" >&2
    echo "usage: $0 [--report]" >&2
    exit 2
    ;;
esac

bad=0

if [ "$home_free" -lt "$MIN_HOME_GB" ]; then
    bad=1
    echo "REFUSE: home has $home_free GiB free, threshold is $MIN_HOME_GB GiB" >&2
fi

if [ "$nix_free" -lt "$MIN_NIX_GB" ]; then
    bad=1
    echo "REFUSE: nix has $nix_free GiB free, threshold is $MIN_NIX_GB GiB" >&2
fi

if [ "$bad" -ne 0 ]; then
    echo >&2
    echo "Free space before dispatching another packaging agent:" >&2
    echo "  - 'nix-store --gc' (reclaims unreferenced FOD seeds)" >&2
    echo "  - 'rm -rf <stale-worktree>/tmp/' (game assets already in nix store)" >&2
    echo "  - 'workmux remove <handle>' (drops worktree and branch entirely)" >&2
    echo >&2
    report >&2
    exit 1
fi

report
