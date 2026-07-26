{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Mario Party 3 (USA, 2000 Hudson Soft/Nintendo). 32 MiB Nintendo 64
  # ROM in the native big-endian z64 format (magic 0x80371240). The last
  # Mario Party on the N64. mupen64plus-next runs it without extra config.
  rom = fetchIpfs {
    cid = "Qma3HU44wdAAirrChzU2FPA5qJ5aVh1enQP1hmiw3Lre6t";
    fallbackUrl = "https://archive.org/download/20240625_20240625_1518/Mario%20Party%203%20%28USA%29.z64";
    hash = "sha256-oIy9ak9A0Vy9i83uZE+AzfuEPgbVadEzS81J8jJihVo=";
    name = "mario-party-3.z64";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mario-party-3";
  src = rom;
  runtime = "retroarch";
  executable = "mario-party-3.z64";

  retroarch = {
    cores = [ pkgs.libretro.mupen64plus ];

    # Keyboard layout for solo play.
    #   arrows     analog stick (movement)
    #   wasd       C-buttons (camera)
    #   ijkl       D-pad
    #   z          N64 A
    #   x          N64 B
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    #   rshift     Select
    #
    # mupen64plus-next with the default `alt-map = False` core option
    # maps libretro B → N64 A and libretro Y → N64 B; libretro A and X
    # are unused, so we null them to stop RetroArch's hardcoded keyboard
    # defaults (a → "x", x → "s") shadowing our _y and wasd C-buttons.
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
    description = "Mario Party 3 (via RetroArch / mupen64plus-next)";
    mainProgram = "mario-party-3";
    platforms = [ "x86_64-linux" ];
  };
}
