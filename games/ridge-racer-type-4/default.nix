{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  disc = fetchIpfs {
    cid = "QmViMV19CRpDL9aKYh9Lp23KR59iCdmyKvH6SvrecLTsKk";
    fallbackUrl = "https://archive.org/download/r-4-ridge-racer-type-4-usa/R4%20-%20Ridge%20Racer%20Type%204%20%28USA%29.chd";
    hash = "sha256-JDxIEKBFfKhjgfDF7qx2yI3MxbZnOhLCLjhlhXVX7Ko=";
    name = "ridge-racer-type-4.chd";
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
  name = "ridge-racer-type-4";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Ridge Racer Type 4 (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Ridge Racer Type 4 (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Ridge Racer Type 4 (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "ridge-racer-type-4";
    platforms = [ "x86_64-linux" ];
  };
}
