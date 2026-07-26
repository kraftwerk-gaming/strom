{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Single-disc PS1 redump packed as a MAME CHD (SwanStation loads .chd
  # directly, no cue/bin split). Source: archive.org psxgames item
  # psx_spidermn ("Spider-Man (USA)", SLUS-00875, NTSC-U).
  disc = fetchIpfs {
    cid = "QmY3oA5VedKngCtfXB2aguEsg2uHNp8T2rBtvujES9Hvcz";
    fallbackUrl = "https://archive.org/download/psx_spidermn/playstationdisc.chd";
    hash = "sha256-C5FVweiT4MkbQcbtVuGx3rdYbANlP4xfRCJLv9+/Ick=";
    name = "spider-man-playstation.chd";
  };

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
  name = "spider-man-playstation";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Spider-Man (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Spider-Man (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Spider-Man (PSX 2000 USA, via RetroArch / SwanStation)";
    mainProgram = "spider-man-playstation";
    platforms = [ "x86_64-linux" ];
  };
}
