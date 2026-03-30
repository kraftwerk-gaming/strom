{
  callPackage,
  lib,
  pkgs,
  fetchurl,
  unzip,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
  proton = callPackage ../../lib/patched-proton.nix { };
in
mkGame {
  name = "starcraft";

  src = fetchurl {
    url = "https://archive.org/download/sc-classic-installer_202311/StarCraft%20Portable.zip";
    hash = "sha256-LotKRHxNGrDSO2afcqwkwxdwzkjS7saSZcF6a/By9zU=";
    name = "starcraft-portable.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -o $src -d /tmp/sc
    mv /tmp/sc/Starcraft\ Brood\ War/* "$out"/

    mv "$out/StarCraft ( Click here ).exe" "$out/StarCraft.exe"

    rm -rf "$out/Backup" "$out/APM_check" "$out/Record"
    rm -f "$out/unins000.exe" "$out/unins000.dat"
    rm -f "$out/Chaoslauncher.exe" "$out/Chaosupdater.exe" "$out/InsectLoader.exe"
    rm -f "$out/Launcher.exe" "$out/Res.exe" "$out/StarcraftResolutionHack.exe"
    rm -f "$out"/*.bwl "$out"/*.icc
    rm -f "$out/RepAnalyser.dll" "$out/ResolutionHackDemo.dll"
    rm -f "$out/EditLocal.dll" "$out/psapi.dll" "$out/w3lh.dll"
    rm -f "$out/alert.wav" "$out/Attack.ani" "$out/StarCraft.ani"
    rm -f "$out/scfix.vbs" "$out/SafeMode.bat" "$out/SETUP.EXE"
    rm -f "$out"/*.url "$out"/*.log "$out"/*.ini
    rm -f "$out/install.ex_" "$out/patch_rt.mp_"
  '';

  copyGlobs = [ ];

  runtime = "proton";

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  executable = "StarCraft.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 640 -h 480 -r 60 --immediate-flips --expose-wayland";

  preRun = "";

  meta = {
    description = "StarCraft + Brood War (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "starcraft";
  };
}
