# shellcheck shell=bash
# n2n edge launcher fragment — sourced into the inner command script
# (inside the bwrap sandbox) when n2n.enable = true. Starts an n2n edge
# in the BACKGROUND so the game's LAN/multiplayer rides the overlay,
# then returns so the game execs.
#
# Runs ONLY when $N2N_SUPERNODE is set. When unset this fragment is a
# no-op and the game keeps the shared-host-net behavior.
#
# EVENT-DRIVEN, no poll/sleep: the sandbox runs in its own net namespace
# (--unshare-net) with internet via a host-side slirp4netns. The host
# wrapper blocks until slirp signals its tap0 + default route are up,
# THEN writes one byte to the readiness FIFO bound at
# $STROM_N2N_READY_FIFO. We block-read that byte once; by the time the
# read returns the network is fully configured, so there is nothing to
# poll for. We then start edge (it creates edge0) and add the
# limited-broadcast route once n2n has assigned edge0 its address —
# waited for event-driven via `ip monitor`, since a route added before
# n2n finishes is flushed when it (re)creates the tap.
#
# Inputs (set in the surrounding scope before this fragment runs):
#   STROM_N2N_EDGE        - path to the n2n `edge` binary
#   STROM_N2N_COMMUNITY   - community + key (edge -c / -k)
#   STROM_N2N_EXTRA_ARGS  - bash array (declared in caller) of extra
#                           raw edge args
#   STROM_N2N_READY_FIFO  - readiness FIFO the host writes once slirp is up
#   N2N_SUPERNODE         - supernode `ip:port` (host-set, propagated
#                           into the sandbox via --setenv)
#
# A game with n2n.defaultRoute = true gets an extra build-time-templated
# block (in mk-game.nix) that, after edge0 is up, moves the default route
# onto it — emitted by Nix only for those games, not gated at runtime.
#
# No edge PID tracking: edge runs `-f` (foreground) as a child of this
# script, so the --unshare-pid teardown reaps it with the namespace.

if [ -n "${N2N_SUPERNODE:-}" ]; then
  # Block ONCE until the host signals slirp4netns has configured tap0 +
  # the default route in this netns. Open non-blocking (<>) so the open()
  # itself never deadlocks; the read returns the instant the host writes.
  exec {__strom_n2n_ready_fd}<>"$STROM_N2N_READY_FIFO"
  IFS= read -r _ <&"${__strom_n2n_ready_fd}" || true
  exec {__strom_n2n_ready_fd}<&-

  # -E accept multicast MAC, -r route/forward, -f foreground (so edge
  # stays a reaped child of the --unshare-pid ns), -u/-g map to our
  # uid/gid (edge would otherwise drop to an unmapped nobody and die).
  # No -a: match the host's supernode-assigned addressing. edge creates
  # edge0 and the supernode assigns its overlay address asynchronously.
  "$STROM_N2N_EDGE" \
    -c "$STROM_N2N_COMMUNITY" \
    -k "$STROM_N2N_COMMUNITY" \
    -l "$N2N_SUPERNODE" \
    -d edge0 \
    -r -E -f \
    -u "$(id -u)" -g "$(id -g)" \
    "${STROM_N2N_EXTRA_ARGS[@]}" >&2 &

  # Add the limited-broadcast route (255.255.255.255 -> edge0) so WC3-style
  # LAN discovery rides the overlay; directed subnet broadcast works
  # without it. It MUST go on AFTER n2n has brought edge0 up: n2n
  # (re)creates the tap and assigns its address as it registers, flushing
  # any route added earlier. Wait for the address EVENT-DRIVEN via
  # `ip monitor` (no poll/sleep) — re-checking state after each netlink
  # event, with the monitor started before the first check so the address
  # can't slip through unseen — then add the route. n2n does not touch
  # edge0 again, so it persists. Backgrounded so the game execs at once.
  (
    exec {__strom_mon_fd}< <(exec ip monitor link address 2>/dev/null)
    until ip -4 addr show edge0 2>/dev/null | grep -q 'inet '; do
      IFS= read -r _ <&"${__strom_mon_fd}" || break
    done
    ip route add table local broadcast 255.255.255.255 dev edge0 2>/dev/null || true
  ) &
fi
