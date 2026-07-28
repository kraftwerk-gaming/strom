{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Final Fantasy X, PS2 NTSC-U retail disc: serial SLUS-20312, VER 1.00,
  # VMODE NTSC (read out of the image's SYSTEM.CNF), DVD-ROM-5, 4508221440
  # bytes. Redump-verified dump - md5 57998b60010b7583c423d5b2142ad1a3 /
  # sha1 42ab110b759e600365b99612e76cf51ef3e95901 match the Redump entry
  # for "Final Fantasy X (USA)" exactly.
  #
  # Deliberately NOT the FFX/X-2 HD Remaster (a 2013/2016 re-release, a
  # different product with different assets), NOT the PAL disc and NOT the
  # NTSC-J "International" edition. The archive item ships a plain .iso, so
  # no unpack step is needed - PCSX2 boots the DVD image directly.
  gameSrc = fetchIpfs {
    cid = "QmUUoujHXde2wgwU5pKETzry7spmHu5ocevSK8mYYrqJyb";
    fallbackUrl = "https://archive.org/download/ffx-usa/Final%20Fantasy%20X%20%28USA%29.iso";
    hash = "sha256-MdWZd+8Z8P9wGNJ4fRi+qlaTMROMDl81Hgvaw4eioDE=";
    name = "final-fantasy-x-usa.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-fantasy-x";
  src = gameSrc;

  runtime = "pcsx2";
  executable = "final-fantasy-x-usa.iso";

  meta = {
    description = "Final Fantasy X (PS2 2001 USA, via PCSX2)";
    mainProgram = "final-fantasy-x";
    platforms = [ "x86_64-linux" ];
  };
}
