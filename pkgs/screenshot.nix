# strom-screenshot: on-demand PNG capture of a running strom game's
# gamescope-nested wayland surface.
#
# Usage:
#   strom-screenshot <slug>
#       Writes ~/.strom/<slug>/screenshots/manual-<UTC>.png and prints
#       the absolute path on stdout. Exits non-zero if no nested
#       gamescope socket is recorded for the slug.
#
# The strom gamescope wrapper writes the active socket name to
# `$STROM_GAMEDIR/.strom-wayland-display` whenever it starts (see
# lib/screenshot-sidecar.sh). This command reads that file and invokes
# `gamescopectl screenshot <path>` against the socket.
#
# gamescopectl (not grim) is required because gamescope's nested
# compositor does NOT advertise the wlr-screencopy protocol; it has a
# native `gamescope_control` interface instead. gamescopectl drives
# that interface and asks gamescope itself to write the PNG.
{ writeShellApplication, gamescope }:

writeShellApplication {
  name = "strom-screenshot";
  runtimeInputs = [ gamescope ];
  text = ''
    if [ $# -lt 1 ]; then
      echo "usage: strom-screenshot <slug>" >&2
      exit 2
    fi
    slug=$1
    gamedir="''${HOME:-.}/.strom/$slug"
    marker="$gamedir/.strom-wayland-display"

    if [ ! -r "$marker" ]; then
      echo "strom-screenshot: no active gamescope socket recorded at $marker" >&2
      echo "strom-screenshot: is the game running? (the sidecar writes this on launch)" >&2
      exit 1
    fi

    socket=$(head -n1 "$marker")
    if [ -z "$socket" ]; then
      echo "strom-screenshot: $marker is empty" >&2
      exit 1
    fi

    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [ ! -S "$runtime_dir/$socket" ]; then
      echo "strom-screenshot: socket $runtime_dir/$socket missing (game exited?)" >&2
      exit 1
    fi

    mkdir -p "$gamedir/screenshots"
    out="$gamedir/screenshots/manual-$(date -u +%Y%m%dT%H%M%SZ).png"
    if WAYLAND_DISPLAY="$socket" gamescopectl screenshot "$out" >&2; then
      # gamescope writes the file asynchronously after gamescopectl's
      # control message lands; poll briefly so the printed path points
      # at a fully-written PNG.
      for _ in $(seq 1 50); do
        [ -s "$out" ] && break
        sleep 0.1
      done
      printf '%s\n' "$out"
    else
      rc=$?
      echo "strom-screenshot: gamescopectl screenshot failed (rc=$rc)" >&2
      exit "$rc"
    fi
  '';
}
