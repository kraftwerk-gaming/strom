{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Harvest Moon (Pack-In-Video / Natsume, 1996). 2 MiB headerless SFC
  # ROM, the USA release (internal title "HARVEST MOON", region $7FD9
  # = 0x01). Farming sim where you inherit a run-down ranch and have
  # two and a half in-game years to make it productive; bsnes handles
  # the LoROM mapping and SPC700 audio without quirks.
  rom = fetchIpfs {
    cid = "Qmb3XE2q79kVqrZ1iHfGwxKKj1byDCjwDwVUS27dPV1Rv9";
    fallbackUrl = "https://archive.org/download/No-Intro_Super_Nintendo_SNES/Harvest%20Moon%20%28USA%29.zip";
    hash = "sha256-c6Oqh93Vzl31ulEpIxb0K24SgoAXmwobEbTc3cF9QWM=";
    name = "harvest-moon.sfc";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "harvest-moon";
  src = rom;
  runtime = "retroarch";
  executable = "harvest-moon.sfc";

  retroarch = {
    cores = [ pkgs.libretro.bsnes ];

    # Keyboard layout for solo play (mirrors the SNES standard mapping
    # used by chrono-trigger; Harvest Moon uses B to confirm/pick up,
    # A to use the held tool, Y/X for the inventory and tool-swap, L/R
    # to cycle items, Start for the menu, Select for the map).
    #   arrows     D-pad
    #   z          B (confirm / pick up)
    #   x          A (use tool)
    #   a          Y (inventory)
    #   s          X (tool swap)
    #   q / e      L / R (cycle items)
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
    description = "Harvest Moon (Pack-In-Video / Natsume 1996 SNES, via RetroArch / bsnes)";
    mainProgram = "harvest-moon";
    platforms = [ "x86_64-linux" ];
  };
}
