{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  disc = fetchIpfs {
    cid = "QmNdTd9Avt4fJVSQgAocBrGS2fq8h2cmZ6LDpopcY5gyai";
    fallbackUrl = "https://archive.org/download/crash-bandicoot-warped-usa_202605/Crash%20Bandicoot%20-%20Warped%20%28USA%29.bin";
    hash = "sha256-Kw0rIpwGw6Id/EXUW6DffPcpletJrwrUI05n8rbOilo=";
    name = "crash-bandicoot-3-warped-usa.bin";
  };

  # Same redump cue as the .bin's, regenerated to keep .cue out of fetchIpfs.
  discCue = writeText "crash-warped.cue" ''
    FILE "Crash Bandicoot - Warped (USA).bin" BINARY
      TRACK 01 MODE2/2352
        INDEX 01 00:00:00
  '';

  psxBios7z = fetchIpfs {
    cid = "bafkreibalsxl4jo23j4lgxoubseqbquwudj5nieni3jsoxszkc3aza6g7u";
    fallbackUrl = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  # SwanStation expects scph5501.bin; the upstream blob is named
  # scph1001.bin so rename after extract.
  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ pkgs.p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "crash-bandicoot-3-warped";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Crash Bandicoot - Warped (USA).bin"
    cp ${discCue} "$out/Crash Bandicoot - Warped (USA).cue"
  '';

  runtime = "retroarch";
  executable = "Crash Bandicoot - Warped (USA).cue";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Crash Bandicoot 3: Warped (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "crash-bandicoot-3-warped";
    platforms = [ "x86_64-linux" ];
  };
}
