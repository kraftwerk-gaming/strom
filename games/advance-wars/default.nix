{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Advance Wars (USA) (Rev 1), 2001 Intelligent Systems/Nintendo. Game Boy
  # Advance turn-based strategy. Archive serves the bare 4 MiB ROM, loaded
  # directly by mGBA.
  rom = fetchIpfs {
    cid = "QmXZLR2PCr7UNB6pFKFwV3DajDVmAnqG1a1U8fj1EUvuNK";
    fallbackUrl = "https://archive.org/download/advance-wars-usa-rev-1_202604/Advance%20Wars%20%28USA%29%20%28Rev%201%29.gba";
    hash = "sha256-TdS9IkQfKbIspa9VTzC/DrfSsaXa/w4s0HGkPhE4MwU=";
    name = "advance-wars.gba";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "advance-wars";
  src = rom;
  runtime = "retroarch";
  executable = "advance-wars.gba";

  buildScript = ''
    mkdir -p $out
    cp "$src" $out/advance-wars.gba
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
    description = "Advance Wars (Intelligent Systems/Nintendo, 2001 GBA, via RetroArch / mGBA)";
    mainProgram = "advance-wars";
    platforms = [ "x86_64-linux" ];
  };
}
