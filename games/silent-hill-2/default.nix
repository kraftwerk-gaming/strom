{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # NTSC-U PS2 release of Silent Hill 2 (the standard US retail disc,
  # NOT the 2024 Bloober remake). The PC port (2002 Konami) is
  # technically playable on modern systems via the SH2EE community
  # patch, but the patch is a Windows installer that wraps over a
  # full PC retail install, and chaining "extract 3 CD ISOs ->
  # install via .exe -> apply SH2EE installer" inside a nix build
  # is not worth the fragility. PS2 NTSC-U + PCSX2 is the simpler
  # path and the canonical reference version of the game.
  gameSrc = fetchIpfs {
    cid = "QmdQoRYZSXwER8akwbZuxZ28HTUWEEo4YWHxEg78rv3AoR";
    fallbackUrl = "https://archive.org/download/silent-hill-2-vw-047-u-1-v-1.20/SILENT%20HILL%202%20%28VW047-U1%29%20V1.20.ISO";
    hash = "sha256-wjBvG/1XZGml5ev5mHf2/yYEBKt4pte3H5s/4mrv3vU=";
    name = "silent-hill-2-usa.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "silent-hill-2";
  src = gameSrc;

  runtime = "pcsx2";
  executable = "silent-hill-2-usa.iso";

  meta = {
    description = "Silent Hill 2 (PS2 NTSC-U, via PCSX2)";
    mainProgram = "silent-hill-2";
    platforms = [ "x86_64-linux" ];
  };
}
