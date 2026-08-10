{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Blue Version (USA, Europe) (SGB Enhanced), 1996 Game Freak /
  # Nintendo. Game Boy RPG, 1 MiB ROM. Archive ships the raw .gb; copy it
  # to a stable name so gambatte can load it directly.
  rom = fetchIpfs {
    cid = "QmcYT8mZSfYRHz1D1QJRLiahgZP1GMLJAz43pVUouU6jq9";
    fallbackUrl = "https://archive.org/download/pokemon-blue-version-usa-europe-sgb-enhanced/Pokemon%20-%20Blue%20Version%20%28USA%2C%20Europe%29%20%28SGB%20Enhanced%29.gb";
    hash = "sha256-KpUTE8JkDowssh8l0dsBmuYkXZxxIfdU+mGv177mRS0=";
    name = "pokemon-blue.gb";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-blue";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-blue.gb";

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
    description = "Pokemon Blue Version (Game Freak/Nintendo, 1996 Game Boy, via RetroArch / gambatte)";
    mainProgram = "pokemon-blue";
    platforms = [ "x86_64-linux" ];
  };
}
