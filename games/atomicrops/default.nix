{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Atomicrops (Bird Bath Games / Raw Fury, 2020). Action-roguelite
  # farming shooter built on Unity. Windows-only on GOG (no native
  # Linux build), so runtime = "proton". GOG offline Inno setup
  # v1.1.9a build 41296; innoextract --gog yields Atomicrops.exe +
  # Atomicrops_Data/ + UnityPlayer.dll at the install root.
  src = fetchIpfs {
    cid = "QmYCBXRWtbgkSbRqsivK12M6MZi8GwnD5omJii2mkwxA97";
    fallbackUrl = "https://archive.org/download/atomicrops-gog/setup_atomicrops_1.1.9a_%2841296%29.exe";
    hash = "sha256-r2UV2j1m2jpTketz3lE+QOSpagsum8z6YqR95oJsxwE=";
    name = "setup_atomicrops_1.1.9a.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "atomicrops";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$out" "$src"
    if [ -d "$out/app" ]; then
      cp -a "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi
    rm -rf "$out/tmp" "$out/commonappdata" "$out/__redist"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico
    # Atomicrops.exe spawns UnityCrashHandler32.exe (--attach <pid>) to
    # monitor it. On a clean in-game quit the main process exits but the
    # crash handler lingers; `proton waitforexitandrun` waits for *every*
    # wine process (and wineserver) to exit before returning, so the
    # surviving handler wedges proton open forever and the strom wrapper /
    # gamescope never tear down. Unity runs fine without it (just no crash
    # reporter), so drop it to get a clean exit.
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "Atomicrops.exe";

  # Atomicrops writes profile_v1_0*.banana saves into the Unity
  # LocalLow tree (AppData/LocalLow/Bird Bath Games/Atomicrops on
  # Windows).
  saveLocations = [ "AppData/LocalLow/Bird Bath Games/Atomicrops" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Atomicrops (Bird Bath Games 2020, Unity action-roguelite farming shooter, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "atomicrops";
  };
}
