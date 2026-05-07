{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # The Legend of Zelda: Oracle of Ages (USA, 2001 Capcom/Nintendo).
  # Game Boy Color ROM (CGB, MBC5+RAM+BATT), 1 MiB. mGBA handles the
  # CGB extensions and the cart-link "secrets" mechanic for save data.
  rom = fetchIpfs {
    cid = "QmUPd38byri7dZauzebF5Yzc18GAH3Dv6uL2ar2QDgyC6w";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-the-oracle-of-ages-usa_202412/Legend%20of%20Zelda%2C%20The%20-%20Oracle%20of%20Ages%20%28USA%29.gbc";
    hash = "sha256-C1a3ip5FRS6Ywz7dERI0kx8eA03Al/byMILrjbYFVHQ=";
    name = "the-legend-of-zelda-oracle-of-ages.gbc";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.mgba ];
  preHook = ''
    mkdir -p ~/.strom/the-legend-of-zelda-oracle-of-ages/saves \
             ~/.strom/the-legend-of-zelda-oracle-of-ages/states
  '';
  settings.savefile_directory = "~/.strom/the-legend-of-zelda-oracle-of-ages/saves";
  settings.savestate_directory = "~/.strom/the-legend-of-zelda-oracle-of-ages/states";

  # Keyboard layout for solo play.
  #   arrows     D-pad
  #   z          B
  #   x          A
  #   q / e      L / R (unused on GBC, kept for parity)
  #   enter      Start
  #   rshift     Select
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
      description = "The Legend of Zelda: Oracle of Ages (via RetroArch / mGBA)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
