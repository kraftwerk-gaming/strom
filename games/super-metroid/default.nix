{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Super Metroid (Nintendo R&D1, 1994). 3 MiB headerless SFC ROM,
  # the Japan/USA "(En,Ja)" multi-region build (internal title
  # "Super Metroid", region $7FD9 = 0x00). bsnes handles the SA-1
  # MMC and SPC700 emulation cleanly.
  rom = fetchIpfs {
    cid = "QmRVRg1spGsV96NuKv7HH27kwhnPKwadNnBp3ZyarDPFwY";
    fallbackUrl = "https://archive.org/download/super-metroid-jue/Super%20Metroid%20%28Japan%2C%20USA%29%20%28En%2CJa%29.sfc";
    hash = "sha256-Erd8S8nBgyzuiIEkRlkGXuHYTHDD0p5ur5LmeYzCynI=";
    name = "super-metroid.sfc";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.bsnes ];
  preHook = ''
    mkdir -p ~/.strom/super-metroid/saves \
             ~/.strom/super-metroid/states
  '';
  settings.savefile_directory = "~/.strom/super-metroid/saves";
  settings.savestate_directory = "~/.strom/super-metroid/states";

  # Keyboard layout for solo play (mirrors the hyper-metroid hack
  # since the underlying control surface is identical SNES).
  #   arrows     D-pad
  #   z          B (jump)
  #   x          A (shoot)
  #   a          Y (run/dash)
  #   s          X (cancel / map)
  #   q / e      L / R (aim diagonals)
  #   enter      Start
  #   rshift     Select
  settings = {
    input_player1_up = "up";
    input_player1_down = "down";
    input_player1_left = "left";
    input_player1_right = "right";
    input_player1_b = "z";
    input_player1_a = "x";
    input_player1_y = "a";
    input_player1_x = "s";
    input_player1_l = "q";
    input_player1_r = "e";
    input_player1_start = "enter";
    input_player1_select = "rshift";
  };
  args = [ (toString rom) ];
}).wrapper.overrideAttrs
  (_: {
    meta = {
      description = "Super Metroid (Nintendo R&D1, 1994 SNES, via RetroArch / bsnes)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
