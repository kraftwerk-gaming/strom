{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Yellow: Special Pikachu Edition (USA, Europe), 1998/1999 Game
  # Freak/Nintendo. A Game Boy game with Game Boy Color enhancements
  # (CGB+SGB Enhanced), 1 MiB ROM. Archive ships the ROM zipped; extract
  # to a raw .gb so gambatte can load it directly.
  romArchive = fetchIpfs {
    cid = "QmQ6r81GyqadmC3rMtuyYjYHFMVzeaR9SsZeCcNN11pKsT";
    fallbackUrl = "https://archive.org/download/Game-Boy_BT/RA%20-%20Nintendo%20Game%20Boy/Pokemon%20-%20Yellow%20Version%20-%20Special%20Pikachu%20Edition%20%28USA%2C%20Europe%29%20%28CGB%2BSGB%20Enhanced%29.zip";
    hash = "sha256-8AfopYMEJZcSaeegA0afTqTwG513WfORMW3exT+LMqM=";
    name = "pokemon-yellow.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-yellow";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-yellow.gb";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Yellow Version - Special Pikachu Edition (USA, Europe) (CGB+SGB Enhanced).gb' > $out/pokemon-yellow.gb
  '';

  retroarch = {
    cores = [ pkgs.libretro.gambatte ];

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
  };

  meta = {
    description = "Pokemon Yellow: Special Pikachu Edition (Game Freak/Nintendo, 1998 GB, via RetroArch / gambatte)";
    mainProgram = "pokemon-yellow";
    platforms = [ "x86_64-linux" ];
  };
}
