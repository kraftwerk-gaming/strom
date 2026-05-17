{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  src = fetchIpfs {
    cid = "QmZzc2ffQdtsokSZ8CxBWdSdzohoKwJBfcRv1dnzd9Q5Fw";
    fallbackUrl = "https://ipfs.io/ipfs/QmZzc2ffQdtsokSZ8CxBWdSdzohoKwJBfcRv1dnzd9Q5Fw";
    hash = "sha256-7sAXNlth42jlwBgyKCKB/WKjKsd13MJAZ7MhFzNLzwk=";
    name = "baby-steps-ankergames.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "baby-steps";

  inherit src;

  nativeBuildInputs = [ unar ];

  # AnkerGames RAR5 layout: Baby Steps/{BabySteps.exe,BabySteps_Data/,
  # GameAssembly.dll,UnityPlayer.dll,...}. Plain Unity IL2CPP.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/"Baby Steps"/* "$out"/
  '';

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/DefaultCompany/BabySteps" ];
  executable = "BabySteps.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Baby Steps (Maxis Games / Devolver Digital 2025, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "baby-steps";
  };
}
