{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  gameSrc = fetchIpfs {
    cid = "QmefADojRgYj81RXePWmpEVGNBCR7RCyGQrgFZLqmmPFUe";
    hash = "sha256-D07L8eThA/Pb+8Fmou2a/Xe3H+rpj0eLb+/zXanTi5Q=";
    name = "return-of-the-obra-dinn.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "return-of-the-obra-dinn";

  ipfsSources = [ gameSrc ];
  src = gameSrc;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    unar -o /tmp/obra "$src"
    mkdir -p "$out"
    cp -r /tmp/obra/*/ObraDinn/. "$out"/
  '';

  runtime = "proton";
  executable = "ObraDinn.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  env = {
    SteamAppId = "653530";
    SteamGameId = "653530";
    PULSE_LATENCY_MSEC = "60";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Return of the Obra Dinn (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "return-of-the-obra-dinn";
  };
}
