{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  disc = fetchIpfs {
    cid = "QmPFJ4r73mxWoBk2wtJWBgYbNJT8PeaCXMkruCaF7A6svY";
    fallbackUrl = "https://archive.org/download/psx_spyro/playstationdisc.chd";
    hash = "sha256-yKAB1gJ2ixIQNhr9uilc2/iRS6OYWNk3jrudDrryHw4=";
    name = "Spyro the Dragon (USA).chd";
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
  name = "spyro-the-dragon";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Spyro the Dragon (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Spyro the Dragon (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Spyro the Dragon (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "spyro-the-dragon";
    platforms = [ "x86_64-linux" ];
  };
}
