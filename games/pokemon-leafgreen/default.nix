{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon LeafGreen Version (USA, Europe), 2004 Game Freak/Nintendo. Game Boy
  # Advance RPG, 16 MiB ROM. No-Intro archive ships the ROM zipped; extract to a
  # raw .gba so mGBA can load it directly.
  romArchive = fetchIpfs {
    cid = "QmerCkFKAqMBkML3i5D51FWfew7jnMHoeqWYtPUVUBZXVT";
    fallbackUrl = "https://archive.org/download/ef_gba_no-intro_2024-02-21/Pokemon%20-%20LeafGreen%20Version%20%28USA%2C%20Europe%29.zip";
    hash = "sha256-WqRnapboWsiqmNLDoPPNcqLjk+V2WGtHGkDGSZHjX2Q=";
    name = "pokemon-leafgreen.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-leafgreen";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-leafgreen.gba";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - LeafGreen Version (USA, Europe).gba' > $out/pokemon-leafgreen.gba
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
    description = "Pokemon LeafGreen Version (Game Freak/Nintendo, 2004 GBA, via RetroArch / mGBA)";
    mainProgram = "pokemon-leafgreen";
    platforms = [ "x86_64-linux" ];
  };
}
