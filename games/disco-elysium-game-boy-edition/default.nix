{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Disco Elysium: Game Boy Edition - unofficial fan demake by Optriromontain.
  # Game Boy Color ROM (CGB, MBC5+RAM+BATT), 1 MiB.
  rom = fetchIpfs {
    cid = "Qme3jE9E7fCJTFiZrcBeWQ7swsQrzZucLxKoE1KdvbrmPX";
    hash = "sha256-JVaWvfmPpn+lkoKcDoY+dChIJJJwDw8Lq74mgyc1SpU=";
    name = "disco-elysium-gb-edition.gb";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "disco-elysium-game-boy-edition";
  src = rom;
  runtime = "retroarch";
  executable = "disco-elysium-gb-edition.gb";

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
    description = "Disco Elysium: Game Boy Edition (fan demake, via RetroArch / mGBA)";
    mainProgram = "disco-elysium-game-boy-edition";
    platforms = [ "x86_64-linux" ];
  };
}
