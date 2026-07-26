{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible), 1999
  # Game Freak/Nintendo. Game Boy Color RPG, 2 MiB ROM. Archive ships the
  # ROM zipped; extract to a raw .gbc so gambatte can load it directly.
  romArchive = fetchIpfs {
    cid = "QmSpnR58zBEnQqWAPPSEAybbkJfFFRLXSjSkqiuDwhsA4z";
    fallbackUrl = "https://archive.org/download/theentireGAMEBOYCOLORcollection/Pokemon%20-%20Gold%20Version%20%28USA%2C%20Europe%29%20%28SGB%20Enhanced%29%20%28GB%20Compatible%29.zip";
    hash = "sha256-7VA6lJ5J5PsBMub4qXCcw0cfoLxuhikW+k/0vImMaGk=";
    name = "pokemon-gold.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-gold";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-gold.gbc";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc' > $out/pokemon-gold.gbc
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
    description = "Pokemon Gold Version (Game Freak/Nintendo, 1999 Game Boy Color, via RetroArch / gambatte)";
    mainProgram = "pokemon-gold";
    platforms = [ "x86_64-linux" ];
  };
}
