{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  disc = fetchIpfs {
    cid = "QmczfxxrqaZpp5DWsPMrKHmiwfRubd4czQGaohDTJ3Mu8W";
    fallbackUrl = "https://archive.org/download/psx_tenchu/playstationdisc.chd";
    hash = "sha256-DL5O5VM3JJbNxn9aK2h6YHP2E1YGjqNbzbFtni5X3j4=";
    name = "tenchu-stealth-assassins.chd";
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
  name = "tenchu-stealth-assassins";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Tenchu - Stealth Assassins (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Tenchu - Stealth Assassins (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Tenchu: Stealth Assassins (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "tenchu-stealth-assassins";
    platforms = [ "x86_64-linux" ];
  };
}
