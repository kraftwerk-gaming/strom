{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # The Legend of Zelda: Majora's Mask (USA) v1.0, big-endian .z64 ROM.
  # SHA1 d6133ace5afaa0882cf214cf88daba39e266c078. The archive item ships
  # the bare 32MiB ROM directly (no zip).
  rom = fetchIpfs {
    cid = "QmVDFMYSFWEKNb6SgpuG51sLYnTQavAa723tLSU22LKy7u";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-the-majoras-mask-usa_20260316/Legend%20of%20Zelda%2C%20The%20-%20Majora%27s%20Mask%20%28USA%29.z64";
    hash = "sha256-77E2WzrjYmBFFMD5oaLRH13IaIulvmYKN96/XjvkPys=";
    name = "majoras-mask.z64";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.mupen64plus ];
  preHook = ''
    mkdir -p ~/.strom/the-legend-of-zelda-majoras-mask/saves \
             ~/.strom/the-legend-of-zelda-majoras-mask/states
  '';

  # Keyboard layout for solo play. The libretro N64 controller exposes
  # the analog stick and C-buttons as separate "axes", which we bind to
  # keys here (analog/digital input, full deflection).
  #   arrows     left analog stick (movement)
  #   WASD       C-buttons (right analog, camera/items)
  #   IJKL       D-pad (rarely used)
  #   z          A
  #   x          B
  #   f          Z trigger
  #   q / e      L / R shoulder
  #   enter      Start
  settings = {
    savefile_directory = "~/.strom/the-legend-of-zelda-majoras-mask/saves";
    savestate_directory = "~/.strom/the-legend-of-zelda-majoras-mask/states";
    # Digital buttons.
    input_player1_a = "z";
    input_player1_b = "x";
    input_player1_start = "enter";
    input_player1_select = "rshift";
    input_player1_l = "q";
    input_player1_r = "e";
    input_player1_l2 = "f"; # N64 Z trigger
    # f is RetroArch's default fullscreen toggle; clear it so the Z
    # trigger bind wins.
    input_toggle_fullscreen = "nul";
    input_player1_up = "i";
    input_player1_down = "k";
    input_player1_left = "j";
    input_player1_right = "l";
    # Left analog stick (movement).
    input_player1_l_x_plus = "right";
    input_player1_l_x_minus = "left";
    input_player1_l_y_plus = "down";
    input_player1_l_y_minus = "up";
    # Right analog stick = N64 C-buttons.
    input_player1_r_x_plus = "d";
    input_player1_r_x_minus = "a";
    input_player1_r_y_plus = "s";
    input_player1_r_y_minus = "w";
  };
  args = [ (toString rom) ];
}).wrapper.overrideAttrs
  (_: {
    meta = {
      description = "The Legend of Zelda: Majora's Mask (via RetroArch / mupen64plus-next)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
