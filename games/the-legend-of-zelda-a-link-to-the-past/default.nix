{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # The Legend of Zelda: A Link to the Past (USA) - "Legend of Zelda,
  # The - A Link to the Past (U) [!].smc". Headered copier dump
  # (1049088 bytes), SHA1 8288b4bc88052a3cf4effed3acd6a498847bfb95.
  # bsnes handles the 512-byte header transparently.
  rom = fetchIpfs {
    cid = "QmaQPt3nPrqoxhkB13HEwpynGkPpmHatBv9Arix4Jj7jBt";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-the-a-link-to-the-past-u_202407/Legend%20of%20Zelda%2C%20The%20-%20A%20Link%20to%20the%20Past%20%28U%29%20%5B%21%5D.smc";
    hash = "sha256-2cacUnCy9+rFTyVGiKQ8x2f9XLTyH8B5oPn74Jl46uw=";
    name = "a-link-to-the-past.smc";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.bsnes ];
  preHook = ''
    mkdir -p ~/.strom/the-legend-of-zelda-a-link-to-the-past/saves \
             ~/.strom/the-legend-of-zelda-a-link-to-the-past/states
  '';
  settings.savefile_directory = "~/.strom/the-legend-of-zelda-a-link-to-the-past/saves";
  settings.savestate_directory = "~/.strom/the-legend-of-zelda-a-link-to-the-past/states";

  # Keyboard layout for solo play.
  #   arrows     D-pad
  #   z          B (sword)
  #   x          A (action)
  #   a          Y (item)
  #   s          X (map)
  #   q / e      L / R shoulder
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
      description = "The Legend of Zelda: A Link to the Past (via RetroArch / bsnes)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
