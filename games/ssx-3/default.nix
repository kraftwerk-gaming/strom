# SSX 3 (EA Sports BIG, 2003) - PlayStation 2 snowboarder, run under PCSX2.
#
# Asset: archive.org item "ssx-3_202601", a single RAR holding SSX3.iso
# (3,320,938,496 B). The disc is the PAL/Europe release - SYSTEM.CNF reads
# `BOOT2=cdrom0:\SLES_516.97;1`, `VER=1.00`, `VMODE=PAL`. No NTSC-U dump is
# reachable: the Redump USA set on archive.org
# (ps2-redump-usa-chd-part-S, "SSX 3 (USA).chd") sits in the `loggedin`
# collection and answers 401 without archive.org credentials, and the only
# other SSX 3 items are a Korean demo and a Sep-2003 prototype.
#
# Build step: the source is a RAR, so it is unpacked with `unar` (nixpkgs'
# `unrar` is unfree) and the ISO inside is handed to PCSX2 via `executable`.
# The PS2 BIOS and PCSX2.ini come from lib/pcsx2.nix; nothing game-specific
# is needed here - the shared ini's widescreen patches and recompiler
# settings boot this disc as-is.
{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "ssx-3";
  src = fetchIpfs {
    cid = "QmUqcjszxZ9JNY5BcwqPZ6BZa6J4HqYroJcUSX2pHV7J32";
    fallbackUrl = "https://archive.org/download/ssx-3_202601/SSX3.rar";
    hash = "sha256-aR8Tdr8AdDbrJjUhqY9WZIibXV4ZgBVZ9J7fKmg0/w8=";
    name = "ssx-3-europe.rar";
  };

  nativeBuildInputs = [ pkgs.unar ];
  buildScript = ''
    mkdir -p $out
    unar -o $out -D "$src"
  '';

  runtime = "pcsx2";
  executable = "SSX3.iso";

  meta = {
    description = "SSX 3 (via PCSX2)";
    mainProgram = "ssx-3";
    platforms = [ "x86_64-linux" ];
  };
}
