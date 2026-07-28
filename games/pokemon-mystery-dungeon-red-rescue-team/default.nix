{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Mystery Dungeon - Red Rescue Team (USA, Australia), 2005
  # Chunsoft/Nintendo. Game Boy Advance roguelike, 32 MiB ROM. Verified
  # No-Intro USA dump from the archive.org "gba_bt" GBA collection (same
  # item the other GBA games here use). Archive ships the ROM zipped;
  # extract to a raw .gba so mGBA can load it directly.
  romArchive = fetchIpfs {
    cid = "QmdmsKuPhqLzLUibcnyQFC91RwVUdDjZpqjtGbeayKDmy2";
    fallbackUrl = "https://archive.org/download/gba_bt/RA%20-%20Nintendo%20Game%20Boy%20Advance%2FPokemon%20Mystery%20Dungeon%20-%20Red%20Rescue%20Team%20%28USA%2C%20Australia%29.zip";
    hash = "sha256-Il7OP2gr+945wfLETjxe5Fg2PuoxDDWrGeND+lUbAWc=";
    name = "pokemon-mystery-dungeon-red-rescue-team.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-mystery-dungeon-red-rescue-team";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-mystery-dungeon-red-rescue-team.gba";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon Mystery Dungeon - Red Rescue Team (USA, Australia).gba' \
      > $out/pokemon-mystery-dungeon-red-rescue-team.gba
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
    description = "Pokemon Mystery Dungeon: Red Rescue Team (Chunsoft/Nintendo, 2005 Game Boy Advance, via RetroArch / mGBA)";
    mainProgram = "pokemon-mystery-dungeon-red-rescue-team";
    platforms = [ "x86_64-linux" ];
  };
}
