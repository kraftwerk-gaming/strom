{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Ruby Version (USA, Europe) (Rev 2), 2002 Game Freak/Nintendo. Game
  # Boy Advance RPG, 16 MiB ROM. Archive serves the raw .gba directly, which
  # mGBA can load without extraction.
  rom = fetchIpfs {
    cid = "QmZUGgWuzrNTe6sKaNnYUhH4jgKzho7ZWVwboHtcptF2AV";
    fallbackUrl = "https://archive.org/download/pokemon-ruby-version-usa-europe-rev-2/Pokemon%20-%20Ruby%20Version%20%28USA%2C%20Europe%29%20%28Rev%202%29.gba";
    hash = "sha256-D9026St1vtZdCd9GNasLcHsojCvx3ExuekpPDuvp1kw=";
    name = "pokemon-ruby.gba";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-ruby";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-ruby.gba";

  buildScript = ''
    mkdir -p $out
    cp "$src" $out/pokemon-ruby.gba
  '';

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
    description = "Pokemon Ruby Version (Game Freak/Nintendo, 2002 GBA, via RetroArch / mGBA)";
    mainProgram = "pokemon-ruby";
    platforms = [ "x86_64-linux" ];
  };
}
