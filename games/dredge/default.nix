{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # DREDGE (Black Salt Games / Team17, 2023). Unity fishing-adventure.
  # Windows-only on GOG -- Black Salt ships no native Linux build and
  # points Linux players at Proton (confirmed ProtonDB/Steam Deck), so
  # runtime = "proton".
  #
  # SOURCE: GOG offline base installer, build "2879 - PROD.1_dlcfix"
  # (GOG build id 85593). This PROD.1_dlcfix base already bundles every
  # DLC (The Pale Reach, The Iron Rig, Blackstone Key, Custom Rod) inside
  # DREDGE_Data/ -- the standalone DLC installers carry only GOG ownership
  # metadata (goggame-*.ico + webcache.zip), no game assets -- so the base
  # alone is the complete game. innoextract --gog drops DREDGE.exe +
  # DREDGE_Data/ + UnityPlayer.dll at the install root.
  src = fetchIpfs {
    cid = "QmfM2FyB21ujQ1RHNMFSFvKoC9qhd6EZFn6JtTmWk15z15";
    fallbackUrl = "https://gog-games.to/game/dredge"; # torrent build 85593
    hash = "sha256-dFxjEzrRn6Nwi9Jns2LwvVk3OS/0gKmJ2jHDsErq1jA=";
    name = "setup_dredge_2879.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dredge";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    # Base --gog extract drops the install payload at the root (DREDGE.exe,
    # DREDGE_Data/, UnityPlayer.dll) -- no app/ wrapper for this installer.
    innoextract --gog -d "$out" "$src"
    if [ -d "$out/app" ]; then
      cp -a "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi
    rm -rf "$out/tmp" "$out/commonappdata" "$out/__redist" "$out/__support"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico "$out/webcache.zip"

    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. atomicrops).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "DREDGE.exe";

  # Unity LocalLow tree (PCGamingWiki): AppData/LocalLow/Black Salt Games/
  # DREDGE holds saves/ + dredge-settings.bin.
  saveLocations = [ "AppData/LocalLow/Black Salt Games/DREDGE" ];

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

  meta = {
    description = "DREDGE (Black Salt Games 2023, Unity fishing-adventure incl. all DLC, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dredge";
  };
}
