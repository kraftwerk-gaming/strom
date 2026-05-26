{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
  p7zip,
}:

let
  # The Ultimate DOOM (id Software 1995): the four-episode "Ultimate"
  # re-release with Thy Flesh Consumed bundled. The 7z bundle ships the
  # DOOM.WAD IWAD (12 MiB) plus the DOS binary and a couple of configs;
  # we ignore the DOS exe and drive the IWAD with GZDoom from nixpkgs.
  bundle = fetchIpfs {
    cid = "QmRuNHP4mT38wHc8A1WL39cjbqvjKreSES8MMkkYvPDJN8";
    fallbackUrl = "https://archive.org/download/the-ultimate-doom_202301/UDOOM.7z";
    hash = "sha256-wAqKg3t+/9aEpJFS7T8sNvN/FTv8JV7hM1LFHZnpmlU=";
    name = "UDOOM.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "doom";

  ipfsSources = [ bundle ];

  src =
    pkgs.runCommandLocal "doom-data"
      {
        nativeBuildInputs = [ p7zip ];
      }
      ''
        mkdir -p "$out"
        7z x -o"$TMPDIR/u" ${bundle}
        cp "$TMPDIR/u/DOOM.WAD" "$out/DOOM.WAD"
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

  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/DOOM.WAD" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "The Ultimate DOOM (id Software 1995, DOOM.WAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "doom";
  };
}
