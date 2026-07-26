{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  disc = fetchIpfs {
    cid = "Qmd91vzcFFrztYeqEDHvj2pteutsjNNd53AHWc9AtcC3Wv";
    fallbackUrl = "https://archive.org/download/psx_shadwtwr/playstationdisc.chd";
    hash = "sha256-Nal62BLyRXvpOhejaOcfu6NO0A/o/1fX2o3SGdXo5WA=";
    name = "shadow-tower-1999.chd";
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
  name = "shadow-tower-1999";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Shadow Tower (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Shadow Tower (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Shadow Tower (PSX 1999 USA, via RetroArch / SwanStation)";
    mainProgram = "shadow-tower-1999";
    platforms = [ "x86_64-linux" ];
  };
}
