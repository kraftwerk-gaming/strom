{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Sapphire Version (USA, Europe) (Rev 2), 2002 Game Freak/Nintendo.
  # Game Boy Advance RPG, 16 MiB ROM. Archive serves the raw .gba so mGBA can
  # load it directly.
  rom = fetchIpfs {
    cid = "QmNo9qmfDF57kN9rWduMdYgdHzXf1r2UvTcFHhMNz4p5yr";
    fallbackUrl = "https://archive.org/download/nintendo-game-boy-advance_20250310/Pokemon%20-%20Sapphire%20Version%20%28USA%2C%20Europe%29%20%28Rev%202%29.gba";
    hash = "sha256-AspBUTWAqLeAmJ3uQo33R7UqCxpVvsYXiGtAWesRUvs=";
    name = "pokemon-sapphire.gba";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-sapphire";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-sapphire.gba";

  retroarch = {
    cores = [ pkgs.libretro.mgba ];

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
    description = "Pokemon Sapphire Version (Game Freak/Nintendo, 2002 GBA, via RetroArch / mGBA)";
    mainProgram = "pokemon-sapphire";
    platforms = [ "x86_64-linux" ];
  };
}
