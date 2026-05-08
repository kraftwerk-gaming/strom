{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # The Legend of Zelda: Oracle of Seasons (USA/Australia, 2001 Capcom/
  # Nintendo). Game Boy Color ROM (CGB, MBC5+RAM+BATT), 1 MiB; internal
  # title "ZELDA DIN" (Din is the Oracle in this entry). mGBA handles
  # the CGB extensions and the cart-link "secrets" mechanic for save
  # data shared with Oracle of Ages.
  rom = fetchIpfs {
    cid = "QmPBLaThsf3G8UbY1wQb97N2473TA2v7cT9s5fg8HeYyJc";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-oracle-of-seasons-usa-australia/Legend%20of%20Zelda%2C%20The%20-%20Oracle%20of%20Seasons%20%28USA%2C%20Australia%29.gbc";
    hash = "sha256-hipRNo+zBTknnTNrP+GTtDh20ssVyHo29dpReASrOXE=";
    name = "the-legend-of-zelda-oracle-of-seasons.gbc";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.mgba ];
  preHook = ''
    mkdir -p ~/.strom/the-legend-of-zelda-oracle-of-seasons/saves \
             ~/.strom/the-legend-of-zelda-oracle-of-seasons/states
  '';
  settings.savefile_directory = "~/.strom/the-legend-of-zelda-oracle-of-seasons/saves";
  settings.savestate_directory = "~/.strom/the-legend-of-zelda-oracle-of-seasons/states";

  # Keyboard layout for solo play (mirrors Oracle of Ages).
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
      description = "The Legend of Zelda: Oracle of Seasons (via RetroArch / mGBA)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
