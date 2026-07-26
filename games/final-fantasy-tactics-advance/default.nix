{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Final Fantasy Tactics Advance (USA), 2003 Square. Game Boy Advance
  # tactical RPG, 16 MiB ROM. Sourced from the No-Intro GBA collection,
  # which ships each ROM zipped; extract to a raw .gba so mGBA loads it
  # directly.
  romArchive = fetchIpfs {
    cid = "QmVkk3B4kGZ22wpUY5gZGAWu7Rpg5RNTyaKotLNAaJqbKL";
    fallbackUrl = "https://archive.org/download/No-Intro_GameBoy_Advance_Collection/mnt%2Fuser%2FROMS%2FNintendo%2FGBA_2%2FGBA.zip/GBA%2FFinal%20Fantasy%20Tactics%20Advance%20%28USA%29.zip";
    hash = "sha256-TWIVl8wLfJXUJlkzxkSzUEk/aitoUEQTpFGIP2lic8A=";
    name = "final-fantasy-tactics-advance.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-fantasy-tactics-advance";
  src = romArchive;
  runtime = "retroarch";
  executable = "final-fantasy-tactics-advance.gba";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Final Fantasy Tactics Advance (USA).gba' > $out/final-fantasy-tactics-advance.gba
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
    description = "Final Fantasy Tactics Advance (Square, 2003 GBA, via RetroArch / mGBA)";
    mainProgram = "final-fantasy-tactics-advance";
    platforms = [ "x86_64-linux" ];
  };
}
