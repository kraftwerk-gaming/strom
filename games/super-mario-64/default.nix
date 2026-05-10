{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Super Mario 64 (USA, 1996 Nintendo). 8 MiB Nintendo 64 ROM in the
  # native big-endian z64 format (magic 0x80371240). NSME header
  # confirms the USA region. mupen64plus-next is the modern fork of
  # the libretro mupen64plus core; nixpkgs ships it as
  # `libretro.mupen64plus` (the upstream repo is mupen64plus-libretro-nx).
  rom = fetchIpfs {
    cid = "QmQLxpguCe1cWs6SR3sDkcyb7oG5exVxbZ6GWiihGyWDvU";
    fallbackUrl = "https://archive.org/download/super-mario-64-usa_202401/Super%20Mario%2064%20%28USA%29.z64";
    hash = "sha256-F84Hc0PGEz+Mny1tbZpKtiyM0qpXxArqH0kLTIuyHZE=";
    name = "super-mario-64.z64";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-mario-64";
  src = rom;
  runtime = "retroarch";
  executable = "super-mario-64.z64";

  retroarch = {
    cores = [ pkgs.libretro.mupen64plus ];

    # Keyboard layout for solo play.
    #   arrows     analog stick (movement)
    #   wasd       C-buttons (camera)
    #   ijkl       D-pad
    #   z          N64 A (jump)
    #   x          N64 B (punch / dive / grab)
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    #   rshift     Select
    #
    # mupen64plus-next with the default `alt-map = False` core option
    # maps libretro **B** (bottom face) → N64 A (jump) and libretro **Y**
    # (left face) → N64 B (kick); libretro A and X are unused. So:
    #   input_player1_b = "z"   keyboard z → N64 A (jump)
    #   input_player1_y = "x"   keyboard x → N64 B (kick)
    #   input_player1_a / _x = "nul"   inert; we explicitly null them so
    #     RetroArch's hardcoded keyboard defaults (a → "x", x → "s")
    #     don't shadow our `_y = "x"` and our wasd C-button mapping below.
    settings = {
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
      # Right analog stick = N64 C-buttons (camera).
      input_player1_r_x_plus = "d";
      input_player1_r_x_minus = "a";
      input_player1_r_y_plus = "s";
      input_player1_r_y_minus = "w";
    };
  };

  meta = {
    description = "Super Mario 64 (via RetroArch / mupen64plus-next)";
    mainProgram = "super-mario-64";
    platforms = [ "x86_64-linux" ];
  };
}
