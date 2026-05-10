{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # The Legend of Zelda: Ocarina of Time (USA) v1.0, big-endian .n64
  # ROM. SHA1 ad69c91157f6705e8ab06c79fe08aad47bb57ba7. The archive
  # item ships the bare 32MiB ROM directly (no zip).
  rom = fetchIpfs {
    cid = "QmPbeK1K79B4HpbfJ2GqHebFxWvhyaUf5U5GqYnn95aHPn";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-the-ocarina-of-time-usa_202508/ocarina.n64";
    hash = "sha256-yRarMV++gqIhab/xPWuGbp/dyQdGHrawoie4Ks31tQY=";
    name = "ocarina-of-time.n64";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-legend-of-zelda-ocarina-of-time";
  src = rom;
  runtime = "retroarch";
  executable = "ocarina-of-time.n64";

  retroarch = {
    cores = [ pkgs.libretro.mupen64plus ];

    # Keyboard layout for solo play. The libretro N64 controller exposes
    # the analog stick and C-buttons as separate "axes", which we bind to
    # keys here (analog/digital input, full deflection).
    #   arrows     left analog stick
    #   WASD       C-buttons (right analog, camera/items)
    #   IJKL       D-pad (rarely used in OoT)
    #   z          A
    #   x          B
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    settings = {
      # Digital buttons. mupen64plus-next default (alt-map = False) maps
      # libretro B → N64 A and libretro Y → N64 B; libretro A and X are
      # unused, so keyboard A/X must be cleared or RetroArch's hardcoded
      # defaults ("x"/"s") would shadow our wasd C-button mapping.
      input_player1_a = "nul";
      input_player1_b = "z";
      input_player1_x = "nul";
      input_player1_y = "x";
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
  };

  meta = {
    description = "The Legend of Zelda: Ocarina of Time (via RetroArch / mupen64plus-next)";
    mainProgram = "the-legend-of-zelda-ocarina-of-time";
    platforms = [ "x86_64-linux" ];
  };
}
