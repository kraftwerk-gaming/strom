{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Emerald Version (USA, Europe), 2004 Game Freak/Nintendo. Game Boy
  # Advance RPG, 16 MiB ROM. Archive ships the ROM zipped; extract to a raw
  # .gba so mGBA can load it directly.
  romArchive = fetchIpfs {
    cid = "QmbA32fn51A8StLtJ8bmJBGMvCyFgEc85bNJtZBZNGDBGn";
    fallbackUrl = "https://archive.org/download/gba_bt/RA%20-%20Nintendo%20Game%20Boy%20Advance%2FPokemon%20-%20Emerald%20Version%20%28USA%2C%20Europe%29.zip";
    hash = "sha256-K4zgkGPBvEX5G7sAFFn06qY32Pko76QsgtGpdpX27O4=";
    name = "pokemon-emerald.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-emerald";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-emerald.gba";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Emerald Version (USA, Europe).gba' > $out/pokemon-emerald.gba
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
    description = "Pokemon Emerald Version (Game Freak/Nintendo, 2004 Game Boy Advance, via RetroArch / mGBA)";
    mainProgram = "pokemon-emerald";
    platforms = [ "x86_64-linux" ];
  };
}
