{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # The Legend of Zelda: Majora's Mask 3D (USA) (En,Fr,Es) (Rev 1), the
  # 2015 3DS remake. A DECRYPTED cart dump, 696496128 bytes / 664 MiB,
  # which is what makes it usable: Azahar refuses any NCCH whose
  # `no_crypto` flag is clear and returns ErrorEncrypted
  # (src/core/file_sys/ncch_container.cpp), with no key-based path, so an
  # ordinary encrypted No-Intro .cci of this title will not boot. Checked
  # on these bytes rather than taken from the filename: NCSD at 0x0,
  # partition 0 at 0x4000, NCCH there, flags[7] = 0x04, i.e. no_crypto
  # set.
  rom = fetchIpfs {
    cid = "QmZ91XHc33Kx3pUhUHvLbZk5g9TKuUhPpevN1K259Ce5ee";
    fallbackUrl = "https://archive.org/download/legend-of-zelda-the-majoras-mask-3-d-usa-en-fr-es-rev-1-decrypted.-3ds/Legend%20of%20Zelda%2C%20The%20-%20Majora%27s%20Mask%203D%20%28USA%29%20%28En%2CFr%2CEs%29%20%28Rev%201%29-decrypted.3ds";
    hash = "sha256-oLChP+i95PescZXGPFL2+DNmlj7jUSPj5bx9m0BSwN4=";
    name = "majoras-mask-3d.3ds";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-legend-of-zelda-majoras-mask-3d";

  ipfsSources = [ rom ];
  src = rom;

  # No buildScript on purpose: mkGame copies the single fetched file to
  # $out/<src.name>, which is already the name `executable` wants, and
  # that is also what lets the Android payload be these exact bytes
  # instead of a second CID for a rebuilt copy of them (see
  # lib/android/default.nix).
  runtime = "azahar";
  executable = "majoras-mask-3d.3ds";

  # Saves live in the emulated NAND under $STROM_GAMEDIR/azahar (see
  # lib/azahar.nix), which is per-game and outside any wineprefix, so
  # there is nothing for saveLocations to relocate.

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "The Legend of Zelda: Majora's Mask 3D (via Azahar)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-legend-of-zelda-majoras-mask-3d";
  };
}
