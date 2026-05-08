{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Hyper Metroid (RealRed, 2015) — a popular fan-made Super Metroid
  # ROM hack with rebuilt map, items, and graphics. The upstream
  # archive item is mislabeled "Super Metroid (JU) [!]", but the
  # SNES internal header at $7FC0 reads "Hyper Metroid", so we
  # package it under its actual title.
  rom = fetchIpfs {
    cid = "QmW79tNQukhmDQJjbK8ymC9Sm4bbNmUiicWHvKTvd97Tw6";
    fallbackUrl = "https://archive.org/download/super-metroid-ju_202402/Super%20Metroid%20%28JU%29%20%5B%21%5D.smc";
    hash = "sha256-kLIucCBmoiuubULOyWTjgzjZQCqUFN2stvHO5I1d3IM=";
    name = "hyper-metroid.smc";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.bsnes ];
  preHook = ''
    mkdir -p ~/.strom/hyper-metroid/saves \
             ~/.strom/hyper-metroid/states
  '';
  settings.savefile_directory = "~/.strom/hyper-metroid/saves";
  settings.savestate_directory = "~/.strom/hyper-metroid/states";

  # Keyboard layout for solo play.
  #   arrows     D-pad
  #   z          B (jump)
  #   x          A (shoot)
  #   a          Y (run/dash)
  #   s          X (cancel)
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
      description = "Hyper Metroid (RealRed 2015 SM ROM hack, via RetroArch / bsnes)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
