{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  src = fetchIpfs {
    cid = "QmX5FPJjRbZ4qcpNYJ1FkVbkbi23cbttVzctuynEieEofz";
    fallbackUrl = "https://archive.org/download/lorns.-lure/Lorns.Lure.rar";
    hash = "sha256-uZ3xftxoqo782rSCLsk8IRBqp5Ite14+MRvy+Khu9VM=";
    name = "lorns-lure.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lorns-lure";

  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -q -o /tmp/ll "$src"
    # rar layout: Lorns.Lure/Lorn's Lure/LornsLure.exe + data
    cp -r "/tmp/ll/Lorns.Lure/Lorn's Lure"/* "$out"/
  '';

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/Rubeki Games/LornsLure" ];
  executable = "LornsLure.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      "--adaptive-sync" = true;
    };
  };

  env = {
    RADV_PERFTEST = "gpl";
    mesa_glthread = "true";
    PULSE_LATENCY_MSEC = "60";
  };

  meta = {
    description = "Lorn's Lure (Unity, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lorns-lure";
  };
}
