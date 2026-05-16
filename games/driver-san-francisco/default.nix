{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Driver: San Francisco (2011, Ubisoft Reflections). The retail PC build
  # ships with Ubisoft's uPlay (now Ubisoft Connect) DRM via
  # ubiorbitapi_r2_loader.dll + uplay_r1_loader.dll. The zip is the
  # "no_install" pre-extracted game tree from archive.org; its
  # uplay_r1_loader.dll is a 3.5 KiB RELOADED stub that fakes the
  # UPLAY_Init / UPLAY_USER_IsConnected / UPLAY_ACH_* entry points so the
  # game launches without contacting Ubisoft's servers (single-player
  # only; no online multiplayer / friends / overlay). The orbit_api.ini
  # shipped next to the loader pins Orbit GameId = 55, which the stub
  # consumes to satisfy the orbit handshake.
  src = fetchIpfs {
    cid = "QmY6JgHkrRdbUu3eFLynuUKqfnrPZ6FgFxCzvMWAgpLKYE";
    fallbackUrl = "https://archive.org/download/driver-san-francisco_no_install_version/Driver%20-%20San%20Francisco.zip";
    hash = "sha256-+W8KdMugc0Mgme4iCBCxUsEWUNAMK8RdsRy6RCYvuYc=";
    name = "driver-san-francisco.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "driver-san-francisco";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Archive layout: top-level "Driver - San Francisco/" directory with
  # Driver.exe and the game data tree. Flatten that one level so
  # Driver.exe lands at the overlay root.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Driver - San Francisco/." "$out"/
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  executable = "Driver.exe";

  # Driver: SF writes settings + savegames under the user profile. The
  # retail engine stores them in Documents\Ubisoft\Driver San Francisco
  # (online profile cache) and AppData\Local\Ubisoft\Driver San Francisco
  # (binary save slots + render config). Relocate both so a wineprefix
  # wipe doesn't take progress with it.
  saveLocations = [
    "Documents/Ubisoft/Driver San Francisco"
    "AppData/Local/Ubisoft/Driver San Francisco"
  ];

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

  env = {
    # uplay_r1_loader / ubiorbitapi_r2_loader are the RELOADED stubs that
    # impersonate Ubisoft's DRM DLLs. Force native-first so Wine's loader
    # binds the bundled stubs rather than searching for the real Ubisoft
    # libraries (which aren't installed under Proton).
    WINEDLLOVERRIDES = "uplay_r1_loader=n,b;ubiorbitapi_r2_loader=n,b";
  };

  meta = {
    description = "Driver: San Francisco (Ubisoft Reflections 2011, single-player via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "driver-san-francisco";
  };
}
