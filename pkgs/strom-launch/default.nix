{
  lib,
  writeShellApplication,
  writeText,
  makeDesktopItem,
  symlinkJoin,
  python3,
  nix,
  zenity,
  libnotify,
  gameMeta,
}:

# The `strom://` URI-scheme handler used by the web GUI's Play button. The set
# of valid games is baked in at build time (same manifest the couch launcher
# uses) so the handler can reject any slug that is not a real strom game before
# it ever reaches `nix`. Installing this package provides both the
# `strom-launch` binary and the .desktop file that registers the scheme.

let
  manifest = writeText "strom-manifest.json" (builtins.toJSON gameMeta);

  bin = writeShellApplication {
    name = "strom-launch";
    runtimeInputs = [
      python3
      nix
      zenity
      libnotify
    ];
    text = ''
      export STROM_MANIFEST=${manifest}
      : "''${STROM_FLAKE:=github:kraftwerk-gaming/strom}"
      export STROM_FLAKE
      exec ${python3.interpreter} ${./strom-launch.py} "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "strom-launch";
    desktopName = "strom launcher";
    comment = "Launch strom games from the web catalog";
    exec = "strom-launch %u";
    icon = "applications-games";
    noDisplay = true;
    categories = [ "Game" ];
    mimeTypes = [ "x-scheme-handler/strom" ];
  };
in
symlinkJoin {
  name = "strom-launch";
  paths = [
    bin
    desktopItem
  ];
  meta = {
    description = "XDG strom:// scheme handler that runs games via nix";
    mainProgram = "strom-launch";
    platforms = lib.platforms.linux;
  };
}
