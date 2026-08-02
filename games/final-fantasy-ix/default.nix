{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  # Final Fantasy IX, original PlayStation release (Squaresoft 2000, USA),
  # run via RetroArch + SwanStation. Same reasoning as the FF7 recipe next
  # door: the 2016 "remaster" is a separate product (Lutris slug
  # final-fantasy-ix--1, Steam appid 377840) with re-rendered character
  # models and a different launcher, not this game. The PSX version
  # emulates cleanly, plays every FMV, and needs no DRM dance. It is a
  # FOUR-disc game; the .m3u drives SwanStation's automatic disc-swapping
  # across the story.
  #
  # Provenance: archive.org item `psx-chd-roms-f`, the F slice of a
  # Redump-derived PSX CHD set. Unpatched, unmodified dumps -- this is the
  # plain "(USA)" set, not the "(Rev 1)" reprint that sits beside it in the
  # same item. Verified after download:
  #   * byte sizes match the item's file table exactly:
  #     disc1 431515736, disc2 350224213, disc3 375242368, disc4 396832711
  #   * MD5s match the item's published per-file MD5s
  #   * `chdman info`: single MODE2_RAW data track per disc, no audio
  #     tracks, cdlz/cdzl/cdfl compression (plain CHD v5, not zstd)
  #   * `chdman extractcd` + SYSTEM.CNF gives the four US disc serials in
  #     order: SLUS-01251 / SLUS-01295 / SLUS-01296 / SLUS-01297
  #   * the extracted .bin SHA-1s match redump.org
  #     "Final Fantasy IX (USA, Canada)" discs 1-4 (redump.org/disc/73..76)
  #     bit for bit:
  #       disc1 4bbd0132b25ee1cc436b45f2a665a21db0d6e9b4 (740715360 bytes)
  #       disc2 afdfe5f846909d7dfbee03cd09175ba76d31b070 (689004288 bytes)
  #       disc3 eb85348d88fce2c76bf6f3b616f54242878f5a46 (729755040 bytes)
  #       disc4 3392de8f304bc05ed7c845c1eb6d91b4021ecd2b (688413936 bytes)
  #     so the CHDs are lossless recompressions of the Redump images.
  base = "https://archive.org/download/psx-chd-roms-f";

  disc1 = fetchIpfs {
    cid = "QmXXNaYj4fPLenZRQY7upCBK2qDRT4i1H5aAuyiZz2meJM";
    fallbackUrl = "${base}/Final%20Fantasy%20IX%20%28USA%29%20%28Disc%201%29.chd";
    hash = "sha256-1iN47mwsRFQJ4o2h0Vfvib+VgGEvp21jhwbRn0zOryA=";
    name = "final-fantasy-ix-disc1.chd";
  };

  disc2 = fetchIpfs {
    cid = "QmRqPM25TbSNAPZMXMX6fwUq7DWnn6xnu7z129rpTbJzZE";
    fallbackUrl = "${base}/Final%20Fantasy%20IX%20%28USA%29%20%28Disc%202%29.chd";
    hash = "sha256-8Ap20wxQ9L2tc1pz0/4wGE68dnnWUxIsdJVUbTrGR7s=";
    name = "final-fantasy-ix-disc2.chd";
  };

  disc3 = fetchIpfs {
    cid = "QmTWXSxcjf5E5jmEejLSXh3PhnqakVwVgi7T4BcCu7hHmf";
    fallbackUrl = "${base}/Final%20Fantasy%20IX%20%28USA%29%20%28Disc%203%29.chd";
    hash = "sha256-2k8dzYk/uBJZ/tjkPbfs+pg64s8tzcog9YWFM1tIP+c=";
    name = "final-fantasy-ix-disc3.chd";
  };

  disc4 = fetchIpfs {
    cid = "QmUnwAaeksgJ7x8V3DWtBtbMJHA93rdP1Wspoxxv8ahaLr";
    fallbackUrl = "${base}/Final%20Fantasy%20IX%20%28USA%29%20%28Disc%204%29.chd";
    hash = "sha256-aEVaX9G9+8H7am3Vn/M5ZOGuwvB6ie1UNNhMZtp928I=";
    name = "final-fantasy-ix-disc4.chd";
  };

  # SwanStation loads the .m3u and swaps discs from the entries below
  # (resolved relative to the playlist, i.e. alongside it in $out).
  m3u = writeText "final-fantasy-ix.m3u" ''
    Final Fantasy IX (USA) (Disc 1).chd
    Final Fantasy IX (USA) (Disc 2).chd
    Final Fantasy IX (USA) (Disc 3).chd
    Final Fantasy IX (USA) (Disc 4).chd
  '';

  psxBios7z = fetchIpfs {
    cid = "bafkreibalsxl4jo23j4lgxoubseqbquwudj5nieni3jsoxszkc3aza6g7u";
    fallbackUrl = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  # SwanStation expects scph5501.bin; the upstream blob is named
  # scph1001.bin (both are the US v4.1 BIOS) so rename after extract.
  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ pkgs.p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-fantasy-ix";
  src = disc1;
  ipfsSources = [
    disc1
    disc2
    disc3
    disc4
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc1} "$out/Final Fantasy IX (USA) (Disc 1).chd"
    ln -s ${disc2} "$out/Final Fantasy IX (USA) (Disc 2).chd"
    ln -s ${disc3} "$out/Final Fantasy IX (USA) (Disc 3).chd"
    ln -s ${disc4} "$out/Final Fantasy IX (USA) (Disc 4).chd"
    cp ${m3u} "$out/Final Fantasy IX (USA).m3u"
  '';

  runtime = "retroarch";
  executable = "Final Fantasy IX (USA).m3u";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Final Fantasy IX (PSX 2000 USA, via RetroArch / SwanStation)";
    mainProgram = "final-fantasy-ix";
    platforms = [ "x86_64-linux" ];
  };
}
