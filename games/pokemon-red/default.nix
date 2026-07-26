{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Red Version (USA, Europe), 1996 Game Freak/Nintendo. Original
  # Game Boy RPG, 1 MiB ROM. Archive ships the ROM zipped; extract to a raw
  # .gb so gambatte can load it directly.
  romArchive = fetchIpfs {
    cid = "QmPFNcdvYc6uGjhtN1jnWgx7Cm95vfSRyWzKSdqiYGTj21";
    fallbackUrl = "https://archive.org/download/Game-Boy_BT/RA%20-%20Nintendo%20Game%20Boy%2FPokemon%20-%20Red%20Version%20%28USA%2C%20Europe%29%20%28SGB%20Enhanced%29.zip";
    hash = "sha256-P7T8+JfXrHJFKsgAs8Q1OcNdzsR9N5PyL4Ov5PBcvxw=";
    name = "pokemon-red.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-red";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-red.gb";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Red Version (USA, Europe) (SGB Enhanced).gb' > $out/pokemon-red.gb
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
    description = "Pokemon Red Version (Game Freak/Nintendo, 1996 Game Boy, via RetroArch / gambatte)";
    mainProgram = "pokemon-red";
    platforms = [ "x86_64-linux" ];
  };
}
