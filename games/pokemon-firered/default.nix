{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon FireRed Version (USA), 2004 Game Freak/Nintendo. Game Boy Advance
  # RPG. Archive ships a bare .gba ROM; mGBA loads it directly.
  rom = fetchIpfs {
    cid = "QmW3XjWfFpvP4cck7DXQAGVqVmZMN8vFQXKoysjRYFu6Zp";
    fallbackUrl = "https://archive.org/download/pokemon-fire-red-version-usa/Pokemon%20-%20FireRed%20Version%20%28USA%29.gba";
    hash = "sha256-PQx58WJwIuGHZXZvbLXqBn9rW/fcoRVVIYmtZaXDqKw=";
    name = "pokemon-firered.gba";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-firered";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-firered.gba";

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
    description = "Pokemon FireRed Version (Game Freak/Nintendo, 2004 GBA, via RetroArch / mGBA)";
    mainProgram = "pokemon-firered";
    platforms = [ "x86_64-linux" ];
  };
}
