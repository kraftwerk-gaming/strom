{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Chrono Trigger (Square, 1995). 4 MiB headerless SFC ROM, the
  # USA release (internal title "CHRONO TRIGGER", region $7FD9 = 0x01).
  # Time-travel JRPG with the Akira Toriyama character art and the
  # Mitsuda/Uematsu score; bsnes handles the SPC700 audio and the
  # cart's straightforward LoROM mapping cleanly.
  rom = fetchIpfs {
    cid = "Qmdwp6PEMUghQXoQgRkunAzvkRaXDTQdW8f84QcQ3fqvpN";
    fallbackUrl = "https://archive.org/download/chrono-trigger-usa_202106/Chrono%20Trigger%20%28USA%29.sfc";
    hash = "sha256-BtHCsGtxYFLFWWqqDC5WMqAn/uGpooQ55Qn4E8MIKak=";
    name = "chrono-trigger.sfc";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "chrono-trigger";
  src = rom;
  runtime = "retroarch";
  executable = "chrono-trigger.sfc";

  retroarch = {
    cores = [ pkgs.libretro.bsnes ];

    # Keyboard layout for solo play (mirrors the SNES standard mapping
    # used by super-metroid; Chrono Trigger only needs the face buttons,
    # Start for menu, and Select for the in-battle item shortcut).
    #   arrows     D-pad
    #   z          B (confirm / talk)
    #   x          A (cancel / dash)
    #   a          Y (menu shortcut)
    #   s          X (open menu in field)
    #   q / e      L / R (page menus, target cycle)
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
  };

  meta = {
    description = "Chrono Trigger (Square 1995 SNES, via RetroArch / bsnes)";
    mainProgram = "chrono-trigger";
    platforms = [ "x86_64-linux" ];
  };
}
