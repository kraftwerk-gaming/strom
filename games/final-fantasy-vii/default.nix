{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  # Final Fantasy VII, original PlayStation release (Squaresoft / Eidos
  # 1997, USA), run via RetroArch + SwanStation. Both PC ports are a poor
  # fit for strom's direct-launch model: the 1998 Eidos release needs a
  # custom GL driver + CD-install extraction, and the 2012 Steam re-release
  # ships a packed exe whose disc/ownership check only 7th Heaven's runtime
  # patch satisfies (no registry/drive/Steam-appid fix reaches the menu --
  # see the stage history). The PSX version emulates cleanly, plays every
  # FMV, and needs no DRM dance. It is a three-disc game; the .m3u drives
  # SwanStation's automatic disc-swapping across the story.
  #
  # The source applies community bugfix/proofread patches (documented on the
  # archive.org item): Final Proofread VII v1.1 (typo/grammar cleanup of the
  # original US script, not a retranslation) plus Ortew's Shop-menu and
  # W-Item bugfixes and Gemini's Spirit-stat bugfix -- all QoL/bugfix, no
  # gameplay or story changes.
  base = "https://archive.org/download/psx-final-fantasy-vii-usa-patched";

  disc1 = fetchIpfs {
    cid = "QmcxcNS7SR3vqpFgq4Bfo9xXywi6NJY8iRKXxmhqRryfKD";
    fallbackUrl = "${base}/Final%20Fantasy%20VII%20%28USA%29%20%28patched%29%20%28Disc%201%29.chd";
    hash = "sha256-dBVFTKdruKwSwy9wzaiNcUpRW2884D+7LG9KxYZthbk=";
    name = "final-fantasy-vii-disc1.chd";
  };

  disc2 = fetchIpfs {
    cid = "QmZNZn7EM2m9S5Q9aMrfWRiX4biV1juaX2QcjsqPCtnTi3";
    fallbackUrl = "${base}/Final%20Fantasy%20VII%20%28USA%29%20%28patched%29%20%28Disc%202%29.chd";
    hash = "sha256-jE28L5uYJzRzdkczBEaB29asJWPO2yC61Bi2CgdwP9M=";
    name = "final-fantasy-vii-disc2.chd";
  };

  disc3 = fetchIpfs {
    cid = "QmWupUVqTvwhQRzUmC7qpd3JGfFKyxxnDQH5Enpe8Jf8bt";
    fallbackUrl = "${base}/Final%20Fantasy%20VII%20%28USA%29%20%28patched%29%20%28Disc%203%29.chd";
    hash = "sha256-UPy5o2EGhxX8zPt6JpcY50svD5m/SIpV4rgvCs4WVm0=";
    name = "final-fantasy-vii-disc3.chd";
  };

  # SwanStation loads the .m3u and swaps discs from the entries below
  # (resolved relative to the playlist, i.e. alongside it in $out).
  m3u = writeText "final-fantasy-vii.m3u" ''
    Final Fantasy VII (USA) (patched) (Disc 1).chd
    Final Fantasy VII (USA) (patched) (Disc 2).chd
    Final Fantasy VII (USA) (patched) (Disc 3).chd
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
  name = "final-fantasy-vii";
  src = disc1;
  ipfsSources = [
    disc1
    disc2
    disc3
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc1} "$out/Final Fantasy VII (USA) (patched) (Disc 1).chd"
    ln -s ${disc2} "$out/Final Fantasy VII (USA) (patched) (Disc 2).chd"
    ln -s ${disc3} "$out/Final Fantasy VII (USA) (patched) (Disc 3).chd"
    cp ${m3u} "$out/Final Fantasy VII (USA).m3u"
  '';

  runtime = "retroarch";
  executable = "Final Fantasy VII (USA).m3u";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Final Fantasy VII (PSX 1997 USA, via RetroArch / SwanStation)";
    mainProgram = "final-fantasy-vii";
    platforms = [ "x86_64-linux" ];
  };
}
