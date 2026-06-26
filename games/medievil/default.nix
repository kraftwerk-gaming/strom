{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  disc = fetchIpfs {
    cid = "QmNWndhQEyzddjJfBoob9n2Nv9Yojzf9JywRvGUZxWqw8j";
    fallbackUrl = "https://archive.org/download/medi-evil-usa/MediEvil%20%28USA%29.chd";
    hash = "sha256-Az9GcSxDYn18bHun9VKecfOtPaUX96I5RRMoDZxpzhQ=";
    name = "medievil.chd";
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
  name = "medievil";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/MediEvil (USA).chd"
  '';

  runtime = "retroarch";
  executable = "MediEvil (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "MediEvil (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "medievil";
    platforms = [ "x86_64-linux" ];
  };
}
