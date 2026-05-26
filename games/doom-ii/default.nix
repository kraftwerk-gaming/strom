{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # DOOM II: Hell on Earth (id Software 1994). The asset is the
  # commercial DOOM2.WAD IWAD only (15 MiB); we drive it with the
  # open-source GZDoom engine from nixpkgs. No DOS binaries shipped --
  # gzdoom reads the IWAD directly and provides modern OpenGL/Vulkan
  # rendering plus modern input.
  wad = fetchIpfs {
    cid = "QmbvTqMatBt2tRcuM461BbCUdrf2kzL6hMSNUtGP4amkJc";
    fallbackUrl = "https://archive.org/download/DOOM2IWADFILE/DOOM2.WAD";
    hash = "sha256-XnAcgGqNOgNwD3/vl7etYtCu1Q/SQN+sJs3zmsPQqNU=";
    name = "DOOM2.WAD";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "doom-ii";

  ipfsSources = [ wad ];

  src = pkgs.runCommandLocal "doom-ii-data" { } ''
    mkdir -p "$out"
    cp ${wad} "$out/DOOM2.WAD"
  '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "custom";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      # Intentionally NO --expose-wayland: with it, gzdoom's SDL2 backend
      # picks up gamescope's nested Wayland socket and uses the relative-
      # pointer protocol, which under gamescope-nested delivers sustained
      # Y deltas — the player view pitches up the moment you touch the
      # mouse. Without it, SDL falls back to XWayland inside gamescope,
      # where the legacy X11 input path works correctly.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our
  # bwrap sandbox that resolves to ~/.strom/doom-ii/.config/gzdoom
  # via the bind setup in mk-game. Saves and config persist there.
  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/DOOM2.WAD" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "DOOM II: Hell on Earth (id Software 1994, DOOM2.WAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "doom-ii";
  };
}
