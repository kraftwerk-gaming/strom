{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pocket Monsters Midori ("Pokemon Green"), 1996 Game Boy RPG by Game
  # Freak/Nintendo. Japan-only Gen 1 release; never localised. 512 KiB
  # ROM. Archive ships the ROM zipped; extract to a raw .gb so gambatte
  # can load it directly.
  romArchive = fetchIpfs {
    cid = "QmQNH7dKdEwNATtKNjNiP6H8Gk876rCy1yXrd34iT31kQ6";
    fallbackUrl = "https://archive.org/download/pocket-monsters-ao-japan-sgb-enhanced/Pocket%20Monsters%20-%20Midori%20%28Japan%29%20%28SGB%20Enhanced%29.zip";
    hash = "sha256-2xUHqF8ucvU5rWIIqyPt90nq8T7abPeWlMv1Sx4mfts=";
    name = "pokemon-green.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-green";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-green.gb";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pocket Monsters - Midori (Japan) (SGB Enhanced).gb' > $out/pokemon-green.gb
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
    description = "Pocket Monsters Midori / Pokemon Green (Game Freak/Nintendo, 1996 Game Boy, Japan-only release, via RetroArch / gambatte)";
    mainProgram = "pokemon-green";
    platforms = [ "x86_64-linux" ];
  };
}
