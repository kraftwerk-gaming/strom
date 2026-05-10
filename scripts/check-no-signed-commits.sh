#!/usr/bin/env bash
# Pre-push hook: refuse to push commits that carry a digital signature.
# pre-commit (and prek) export PRE_COMMIT_FROM_REF / PRE_COMMIT_TO_REF for the
# pre-push stage; we mirror git's own pre-push.sample semantics for new
# branches (no remote ref yet).
set -euo pipefail

zero=0000000000000000000000000000000000000000
from="${PRE_COMMIT_FROM_REF:-$zero}"
to="${PRE_COMMIT_TO_REF:-HEAD}"

if [ "$from" = "$zero" ]; then
    # New branch: inspect commits unique to it (not reachable from any remote).
    mapfile -t commits < <(git rev-list "$to" --not --remotes)
else
    mapfile -t commits < <(git rev-list "${from}..${to}")
fi

bad=0
for c in ${commits[@]+"${commits[@]}"}; do
    sig=$(git log -1 --format='%G?' "$c")
    # %G? returns 'N' for unsigned commits; anything else means a signature is
    # attached (G/U/B/X/Y/R/E).
    if [ "$sig" != "N" ]; then
        if [ "$bad" -eq 0 ]; then
            echo "Refusing push: signed commits detected." >&2
            echo "Recreate them without -S / --gpg-sign before pushing." >&2
            bad=1
        fi
        subject=$(git log -1 --format='%s' "$c")
        echo "  $c [$sig] $subject" >&2
    fi
done

exit "$bad"
