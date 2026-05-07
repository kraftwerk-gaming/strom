{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Golden Sun (USA, Europe), 2001 Camelot/Nintendo. Game Boy Advance RPG,
  # 8 MiB ROM. Archive ships the ROM zipped; extract to a raw .gba so
  # mGBA can load it directly.
  romArchive = fetchIpfs {
    cid = "QmaSeGWrzZ77vZQZ9RHsnyizfmXzizdkXaov1JiGgTMH58";
    fallbackUrl = "https://archive.org/download/Games-for-the-Gameboy-202501/Golden%20Sun%20%28USA%2C%20Europe%29.zip";
    hash = "sha256-aeaRf1jS7lF2eUQmGvrNVwlp3NjAzIP090X8wpUOJJY=";
    name = "golden-sun.zip";
  };

  rom =
    pkgs.runCommandLocal "golden-sun.gba"
      {
        nativeBuildInputs = [ pkgs.unzip ];
      }
      ''
        unzip -p ${romArchive} 'Golden Sun (UE) \[!\].gba' > $out
      '';
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.mgba ];
  preHook = ''
    mkdir -p ~/.strom/golden-sun/saves \
             ~/.strom/golden-sun/states
  '';
  settings.savefile_directory = "~/.strom/golden-sun/saves";
  settings.savestate_directory = "~/.strom/golden-sun/states";

  settings = {
    input_player1_up = "up";
    input_player1_down = "down";
    input_player1_left = "left";
    input_player1_right = "right";
    input_player1_b = "z";
    input_player1_a = "x";
    input_player1_l = "q";
    input_player1_r = "e";
    input_player1_start = "enter";
    input_player1_select = "rshift";
  };
  args = [ (toString rom) ];
}).wrapper.overrideAttrs
  (_: {
    meta = {
      description = "Golden Sun (Camelot/Nintendo, 2001 GBA, via RetroArch / mGBA)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ romArchive ];
    };
  })
