# strom-ip: print the n2n overlay ("LAN") IP address of a running strom
# game's sandbox.
#
# Usage:
#   strom-ip <slug>
#       Prints the game's edge0 overlay address (e.g. 10.x.x.x) on stdout.
#       Exits non-zero if the game isn't running, or if it is running but
#       has NO n2n networking — i.e. it was launched without $N2N_SUPERNODE,
#       so no edge/edge0 exists and there is no overlay IP.
#
# Mechanism (mirrors strom-screenshot): the in-sandbox n2n edge launcher
# writes edge0's address to `$STROM_GAMEDIR/.strom-n2n-ip` once the
# supernode assigns it (see lib/n2n-edge-launcher.sh); the host clears that
# marker at the start of every launch (lib/mk-game.nix), so its presence
# means n2n is up for the current session. Liveness is confirmed via the
# same nested gamescope wayland socket strom-screenshot uses, so a stale
# marker left by a hard-killed session is not mistaken for a live IP.
{ writeShellApplication }:

writeShellApplication {
  name = "strom-ip";
  text = ''
    if [ $# -lt 1 ]; then
      echo "usage: strom-ip <slug>" >&2
      exit 2
    fi
    slug=$1
    gamedir="''${HOME:-.}/.strom/$slug"

    # Liveness: is the game actually running? The gamescope wrapper records
    # its nested wayland socket name on launch; if the socket is gone the
    # game has exited (and any IP marker is stale).
    marker_wl="$gamedir/.strom-wayland-display"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    socket=""
    [ -r "$marker_wl" ] && socket=$(head -n1 "$marker_wl")
    if [ -z "$socket" ] || [ ! -S "$runtime_dir/$socket" ]; then
      echo "strom-ip: '$slug' does not appear to be running" >&2
      exit 1
    fi

    # n2n IP marker: present only when this launch brought n2n up.
    marker_ip="$gamedir/.strom-n2n-ip"
    if [ ! -r "$marker_ip" ]; then
      echo "strom-ip: '$slug' is running without n2n networking" >&2
      echo "strom-ip: it was launched without N2N_SUPERNODE, so it has no overlay IP" >&2
      exit 1
    fi

    ip=$(head -n1 "$marker_ip")
    if [ -z "$ip" ]; then
      echo "strom-ip: edge0 has no address yet (n2n still registering?)" >&2
      exit 1
    fi

    printf '%s\n' "$ip"
  '';
}
