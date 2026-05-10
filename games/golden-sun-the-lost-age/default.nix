{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Golden Sun: The Lost Age (USA, Europe), 2003 Camelot/Nintendo. Game Boy
  # Advance RPG sequel, 16 MiB ROM. Archive ships the ROM zipped; extract
  # to a raw .gba so mGBA can load it directly.
  romArchive = fetchIpfs {
    cid = "QmWMtnoKV4BviYwgLJWJ2TGWz7fj3r3X5cGK6i1ymo6KFU";
    fallbackUrl = "https://archive.org/download/Games-for-the-Gameboy-202501/Golden%20Sun%20-%20The%20Lost%20Age%20%28USA%2C%20Europe%29.zip";
    hash = "sha256-IGJKXJ4WOXyDOcBqDAsHc8ZeEqYUTLM3cRcZdSWK9GQ=";
    name = "golden-sun-the-lost-age.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "golden-sun-the-lost-age";
  src = romArchive;
  runtime = "retroarch";
  executable = "golden-sun-the-lost-age.gba";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Golden Sun - The Lost Age (UE) \[!\].gba' > $out/golden-sun-the-lost-age.gba
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
    description = "Golden Sun: The Lost Age (Camelot/Nintendo, 2003 GBA, via RetroArch / mGBA)";
    mainProgram = "golden-sun-the-lost-age";
    platforms = [ "x86_64-linux" ];
  };
}
