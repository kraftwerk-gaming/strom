{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Silver Version (USA, Europe) (SGB Enhanced), 1999 Game Freak /
  # Nintendo. Game Boy Color RPG, 2 MiB ROM. Archive ships a zip; extract the
  # .gbc to a stable name so gambatte can load it directly.
  romArchive = fetchIpfs {
    cid = "QmaqfZkZdK644P2gb1c6uHsg4AVAgK4XQ6tdtjQn9qviaW";
    fallbackUrl = "https://archive.org/download/pokemon-gold-version-usa-europe-sgb-enhanced/Pokemon%20-%20Silver%20Version%20%28USA%2C%20Europe%29%20%28SGB%20Enhanced%29.zip";
    hash = "sha256-tjhbzoCB4z+QjQ5yh6NLk+qt6mE7UQOdrfwYhDAMiyw=";
    name = "pokemon-silver.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-silver";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-silver.gbc";

  nativeBuildInputs = [ pkgs.unzip ];

  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Silver Version (USA, Europe) (SGB Enhanced).gbc' > $out/pokemon-silver.gbc
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
    description = "Pokemon Silver Version (Game Freak/Nintendo, 1999 Game Boy Color, via RetroArch / gambatte)";
    mainProgram = "pokemon-silver";
    platforms = [ "x86_64-linux" ];
  };
}
