{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Driver - You Are the Wheelman, original PlayStation release (Reflections
  # Interactive / GT Interactive 1999, USA, SLUS-00842), run via RetroArch +
  # SwanStation. Single-disc. Sourced from the non-restricted "PSX CHD ROMS D"
  # archive.org item; re-exposed on-disk under the canonical Redump name.
  disc = fetchIpfs {
    cid = "QmXJtuT3obuzCNPGhDdMbtnLAFNEZgTu2swxQEtn8Mw9qD";
    fallbackUrl = "https://archive.org/download/psx-chd-roms-d/Driver%20-%20You%20Are%20the%20Wheelman%20%28USA%29.chd";
    hash = "sha256-WMXuuMN+RbnMMeKnnS33cxNHnkbTuQEh+fVFX9q/fFU=";
    name = "driver.chd";
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
  name = "driver";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Driver (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Driver (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Driver - You Are the Wheelman (PSX 1999 USA, via RetroArch / SwanStation)";
    mainProgram = "driver";
    platforms = [ "x86_64-linux" ];
  };
}
