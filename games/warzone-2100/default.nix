{
  self,
  lib,
  pkgs,
  warzone2100,
}:

# Warzone 2100 (1999 Pumpkin Studios). Released as GPL free software in
# 2004; the modern community engine plus all data (base.wz, mp.wz,
# sequences.wz FMV cutscenes, music) ships in nixpkgs as warzone2100, so
# there is no proprietary data to fetch and no IPFS pin is needed.
#
# native runtime binds $HOME -> $STROM_GAMEDIR, so the engine's XDG
# config/save dir (~/.local/share/warzone2100-*) lands under
# ~/.strom/warzone-2100/ and persists across runs.

self.lib.mkGame { inherit lib pkgs; } {
  name = "warzone-2100";

  # FOSS engine + data straight from nixpkgs; the overlay lower is the
  # package tree itself, the runScript execs its binary directly.
  src = warzone2100;

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  runScript = ''
    exec ${warzone2100}/bin/warzone2100 \
      --configdir="$HOME" \
      --fullscreen
  '';

  meta = {
    description = "Warzone 2100 (1999 Pumpkin Studios, GPL free software, native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warzone-2100";
  };
}
