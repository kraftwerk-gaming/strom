{
  lib,
  runCommand,
  writeShellApplication,
  python3,
  xdg-utils,
}:

# `strom-gui` serves the static web catalog (web/gui + a catalog.json assembled
# at build) over a localhost HTTP server and opens it in the
# browser. It is deliberately a dumb static file server, not an application
# daemon: launching a game is handed off to the `strom://` URI scheme (see
# pkgs/strom-launch), so the GUI itself needs no privileges and no game closure.

let
  webSrc = ../../web;

  # Assemble the served document root. catalog.json is built here from each
  # game's games/<slug>/steam.json + metadata.json by scripts/assemble-catalog.py
  # (the same merge the launcher uses), so it is not a committed file.
  bundle = runCommand "strom-gui-web" { nativeBuildInputs = [ python3 ]; } ''
    mkdir -p "$out/gui"
    cp ${webSrc}/gui/index.html ${webSrc}/gui/app.js ${webSrc}/gui/style.css "$out/gui/"
    python3 ${../../scripts/assemble-catalog.py} ${../../games} > "$out/catalog.json"
  '';
in
writeShellApplication {
  name = "strom-gui";
  runtimeInputs = [
    python3
    xdg-utils
  ];
  text = ''
    root=${bundle}
    port="''${STROM_GUI_PORT:-8731}"
    url="http://127.0.0.1:''${port}/gui/index.html"

    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root" &
    server=$!
    trap 'kill "$server" 2>/dev/null || true' EXIT

    # Give the server a beat to bind before pointing the browser at it.
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
