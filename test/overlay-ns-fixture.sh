#!/usr/bin/env bash
# Fixture for the "Option B" in-namespace game overlay (no real game).
#
# Exercises the SAME mechanism lib/mk-game.nix now uses: the real built
# strom-run wraps a real bwrap whose inner shim mounts the patched
# fuse-overlayfs INSIDE bwrap's user+mount+pid namespace (CAP_SYS_ADMIN +
# plain store fusermount3 on PATH), then execs `sleep` instead of a game.
#
# Asserts:
#   A  inside the ns the overlay is mounted + WRITABLE: a file written at
#      the dest lands in the upper dir, and the lower's known file is
#      visible.
#   B  NO host-side mount leaked (the whole reason for Option B).
#   C  kill -9 of strom-run -> after a moment NO fuse-overlayfs daemon for
#      the fixture survives AND no host mount leaked (cgroup.kill tears the
#      ns down atomically). Contrast: the OLD host-side mount would have
#      survived a strom-run SIGKILL.
#
# Headless, no gamescope. Run from a delegated cgroup-v2 session (logind/
# elogind seat) so strom-run can create its child cgroup.
set -euo pipefail

say() { printf '\n=== %s ===\n' "$*"; }
fail() {
	printf 'FIXTURE FAIL: %s\n' "$*" >&2
	exit 1
}

# --- resolve the real binaries (built from THIS worktree) -----------------
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

say "building strom-run + helper binaries from $here"
STROM_RUN=$(nix build .#checks.x86_64-linux.strom-run --no-link --print-out-paths)/bin/strom-run
BWRAP=$(nix build nixpkgs#bubblewrap --no-link --print-out-paths | head -1)/bin/bwrap
# Patched fuse-overlayfs exactly as the game uses (pkgs/fuse-overlayfs.nix).
FOF=$(nix build --no-link --print-out-paths --impure --expr \
	'let p = import <nixpkgs> {}; in p.callPackage ./pkgs/fuse-overlayfs.nix { pkgs = p; }' \
	| grep -- '-fuse-overlayfs' | grep -v -- '-man' | head -1)/bin/fuse-overlayfs
FUSE3=$(nix build nixpkgs#fuse3 --no-link --print-out-paths | head -1)/bin
COREUTILS=$(nix build nixpkgs#coreutils --no-link --print-out-paths | head -1)/bin
UTILLINUX=$(nix build nixpkgs#util-linux --no-link --print-out-paths | grep -- '-bin' | head -1)/bin
BASH=$(nix build nixpkgs#bash --no-link --print-out-paths | grep -v man | head -1)/bin/bash
GNUGREP=$(nix build nixpkgs#gnugrep --no-link --print-out-paths | head -1)/bin

for f in "$STROM_RUN" "$BWRAP" "$FOF" "$FUSE3/fusermount3" "$COREUTILS/sleep" \
	"$UTILLINUX/mountpoint" "$BASH" "$GNUGREP/grep"; do
	[ -x "$f" ] || fail "missing helper: $f"
done

# --- toy overlay layout ---------------------------------------------------
WORK=$(mktemp -d -t strom-fixture.XXXXXX)
DEST="$WORK/merged"
LOWER="$WORK/lower"
UPPER="$WORK/upper"
OWORK="$WORK/work"
CTRL=$(mktemp -d -t strom-fixture-ctl.XXXXXX)
mkfifo -m 0600 "$CTRL/shutdown.fifo"
mkdir -p "$LOWER" "$UPPER" "$OWORK" "$DEST"
echo "hello-from-lower" >"$LOWER/known.txt"

cleanup() {
	# best-effort: kill any survivor + remove tmp
	for p in /proc/[0-9]*; do
		pid=${p#/proc/}
		[ "$(cat "$p/comm" 2>/dev/null)" = fuse-overlayfs ] || continue
		tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q "$DEST" && kill -9 "$pid" 2>/dev/null || true
	done
	rm -rf "$WORK" "$CTRL" 2>/dev/null || true
}
trap cleanup EXIT

# --- inner shim: the EXACT in-ns mount invocation from lib/mk-game.nix ----
INNER="$WORK/inner.sh"
cat >"$INNER" <<EOF
#!$BASH
set -euo pipefail
export PATH="$FUSE3:$COREUTILS:$UTILLINUX:$GNUGREP"
export FUSERMOUNT_PROG="$FUSE3/fusermount3"
$FOF \\
  -o "lowerdir=$LOWER,upperdir=$UPPER,workdir=$OWORK,squash_to_uid=\$(id -u),squash_to_gid=\$(id -g)" \\
  "$DEST"
if ! mountpoint -q "$DEST"; then
	echo "inner: mount FAILED" >&2
	exit 1
fi
# ASSERT A (from inside the ns): lower visible + dest writable -> upper.
grep -q hello-from-lower "$DEST/known.txt" || { echo "inner: lower not visible" >&2; exit 1; }
echo "written-in-ns" > "$DEST/from-ns.txt"
echo "INNER_A_OK"
exec sleep 600
EOF
chmod +x "$INNER"

# --- launch: strom-run -> bwrap (--cap-add CAP_SYS_ADMIN) -> inner --------
say "launching strom-run -> bwrap -> in-ns fuse-overlayfs mount -> sleep"
"$STROM_RUN" \
	--cgroup-name strom-fixture \
	--control-dir "$CTRL" \
	--control-fifo "$CTRL/shutdown.fifo" \
	--gs-dirs "$CTRL/strom-gs-dirs" \
	-- \
	"$BWRAP" \
	--die-with-parent \
	--unshare-pid \
	--cap-add CAP_SYS_ADMIN \
	--dev-bind /dev /dev \
	--bind "$WORK" "$WORK" \
	--ro-bind /nix /nix \
	--ro-bind /etc /etc \
	--proc /proc \
	-- \
	"$BASH" "$INNER" >"$WORK/inner.log" 2>&1 &
SR_PID=$!

# wait for the inner mount to come up (bounded)
for _ in $(seq 1 100); do
	grep -q INNER_A_OK "$WORK/inner.log" 2>/dev/null && break
	kill -0 "$SR_PID" 2>/dev/null || break
	sleep 0.1
done

say "ASSERT A: in-ns mount writable, lower visible, write lands in upper"
grep -q INNER_A_OK "$WORK/inner.log" || {
	cat "$WORK/inner.log" >&2
	fail "A: inner did not confirm mount/write (INNER_A_OK missing)"
}
[ -f "$UPPER/from-ns.txt" ] || fail "A: write did not land in upper dir"
grep -q written-in-ns "$UPPER/from-ns.txt" || fail "A: upper content mismatch"
echo "A PASS: lower visible in-ns, dest writable, content in upper ($UPPER/from-ns.txt)"

say "ASSERT B: no host-side mount leaked"
if grep -F "$DEST" /proc/mounts; then
	fail "B: a host mount for $DEST exists (LEAK)"
fi
echo "B PASS: no host mount for $DEST in /proc/mounts"

# helper: is any fuse-overlayfs daemon backing our DEST alive?
daemon_alive() {
	for p in /proc/[0-9]*; do
		pid=${p#/proc/}
		[ "$(cat "$p/comm" 2>/dev/null)" = fuse-overlayfs ] || continue
		if tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q "$DEST"; then
			echo "$pid"
			return 0
		fi
	done
	return 1
}

say "pre-C sanity: a fuse-overlayfs daemon for our DEST is currently alive"
if d=$(daemon_alive); then
	echo "daemon pid $d alive (expected before kill)"
else
	fail "no daemon found before kill -- mount mechanism broken"
fi

say "ASSERT C: kill -9 strom-run -> daemon + host mount both gone"
kill -9 "$SR_PID" 2>/dev/null || true
wait "$SR_PID" 2>/dev/null || true
# give cgroup.kill / ns teardown a moment to propagate
for _ in $(seq 1 50); do
	daemon_alive >/dev/null || break
	sleep 0.1
done
if d=$(daemon_alive); then
	fail "C: fuse-overlayfs daemon (pid $d) survived kill -9 of strom-run (LEAK)"
fi
echo "C PASS: no fuse-overlayfs daemon survives kill -9 of strom-run"
if grep -F "$DEST" /proc/mounts; then
	fail "C: host mount for $DEST present after kill (LEAK)"
fi
echo "C PASS: no host mount for $DEST after kill -9"

say "ALL ASSERTS PASS (A, B, C)"
