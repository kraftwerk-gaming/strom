{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Crystal Version (USA, Europe) (Rev 1), 2000 Game Freak/Nintendo.
  # Game Boy Color RPG, 2 MiB ROM. Archive ships a bare .gbc that gambatte
  # loads directly.
  rom = fetchIpfs {
    cid = "QmNvytPvKYLQ9EzLTU8uoM89gbWQwpEbCG2MEfkt3zpdEL";
    fallbackUrl = "https://archive.org/download/pokemon-crystal-version-usa-europe-rev-1_202310/Pokemon%20-%20Crystal%20Version%20%28USA%2C%20Europe%29%20%28Rev%201%29.gbc";
    hash = "sha256-Q5zV09bO5iwE1bRCTDyaNMHlzDhejoNeRxULKxJWAbA=";
    name = "pokemon-crystal.gbc";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-crystal";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-crystal.gbc";

  buildScript = ''
    mkdir -p $out
    cp "$src" $out/pokemon-crystal.gbc
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
    description = "Pokemon Crystal Version (Game Freak/Nintendo, 2000 Game Boy Color, via RetroArch / gambatte)";
    mainProgram = "pokemon-crystal";
    platforms = [ "x86_64-linux" ];
  };
}
