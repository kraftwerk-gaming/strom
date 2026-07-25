{
  lib,
  runCommand,
  writeShellApplication,
  python3,
  xdg-utils,
}:

# `strom-gui` serves the Steam-like catalog SPA on a localhost HTTP server and
# opens it. The browser assembles the catalog by reading each game's steam.json
# + metadata.json from the games/ directory served here (the stock http.server
# lists it), so there is no catalog.json. Launching a game is handed off to the
# `strom://` URI scheme (pkgs/strom-launch), so the GUI needs no privileges.

let
  # Served document root: the SPA under /gui and the per-game files under
  # /games. Symlinked (not copied) so the games/ source isn't duplicated.
  root = runCommand "strom-gui-web" { } ''
    mkdir -p "$out"
    ln -s ${../../web/gui} "$out/gui"
    ln -s ${../../games} "$out/games"
  '';
in
writeShellApplication {
  name = "strom-gui";
  runtimeInputs = [
    python3
    xdg-utils
  ];
  text = ''
    port="''${STROM_GUI_PORT:-8731}"
    url="http://127.0.0.1:''${port}/gui/index.html"

    python3 -m http.server "$port" --bind 127.0.0.1 --directory ${root} &
    server=$!
    trap 'kill "$server" 2>/dev/null || true' EXIT

    sleep 0.5
    echo "strom-gui serving $url" >&2
    xdg-open "$url" >/dev/null 2>&1 || echo "open $url manually" >&2

    wait "$server"
  '';
  meta = {
    description = "Steam-like web catalog browser for strom games";
    mainProgram = "strom-gui";
    platforms = lib.platforms.linux;
  };
}
