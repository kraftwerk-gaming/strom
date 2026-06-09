{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  src = fetchIpfs {
    cid = "QmXqGFXAh7Y9vzBRXj5cGyjnLFPPsYnMJPZVAoMAbdWmtj";
    hash = "sha256-hi9tn6HC6pgLIAkAoZtnhus7BcYq8B241xBVWqvupoM=";
    name = "balatro-ankergames.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "balatro";

  ipfsSources = [ src ];

  src =
    pkgs.runCommandLocal "balatro-data"
      {
        nativeBuildInputs = [ pkgs.unar ];
      }
      ''
        mkdir -p "$out"
        unar -o "$out" ${src}
        extracted=$(echo "$out/"*/)
        mv "$extracted/Balatro/"* "$out/"
      '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";
  executable = "Balatro.exe";

  saveLocations = [ "AppData/Roaming/Balatro" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      # Balatro's startup churns its toplevel (the Proton start.exe ->
      # game.exe handoff destroys+recreates the window) fast enough to
      # trip gamescope#1456: the wayland-backend CWaylandInputThread
      # abort()s (confirmed via coredump: SIGABRT in
      # CWaylandInputThread::ThreadFunc), killing the compositor on ~50%
      # of launches ("Parent of gamescopereaper was killed"). PerWindow
      # holds back the outer toplevel mapping until the inner client maps
      # its own, removing the rapid map/unmap that aborts the input
      # thread. Set per-game (not globally) because PerWindow delays
      # window-mapping for slow-intro games (lib/gamescope.nix); Balatro
      # has no intro so the trade-off is free here.
      # (--immediate-flips + --expose-wayland were also dropped: the
      # former is a DRM/embedded-only no-op when nested, the latter forces
      # a wayland session type that misroutes a Proton/Xwayland game.)
      "--virtual-connector-strategy" = "PerWindow";
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Balatro (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "balatro";
  };
}
