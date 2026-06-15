{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Scritchy Scratchy (Lunch Money Games, 2026) — a scratch-card
  # incremental game. 64-bit Unity IL2CPP build, Windows-only on Steam
  # (store lists only Windows + macOS), so runtime = "proton".
  #
  # Source: AnkerGames pre-installed repack (Scritchy-Scratchy-AnkerGames.zip,
  # 338,491,985 bytes), Steam app 3948120, V 1.1.19d (build 23142522). The
  # repack ships a RUNE-emulated steam_api64.dll plus SmokeAPI for the
  # Supporter Pack DLC, so it runs fully offline without a Goldberg/gbe_fork
  # swap. RUNE keeps its own state under
  # drive_c/users/Public/Documents/Steam/RUNE/3948120.
  src = fetchIpfs {
    cid = "QmaJ3vHdT8Pi7LkWVi5YD88Mej7ynYSbfHKyLHcygjSt3G";
    hash = "sha256-w8fXVU2Z25jyq+lKW1oPXs8kJe8KF3UdCxU+ET4dfd0=";
    name = "scritchy-scratchy-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "scritchy-scratchy";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" "Scritchy Scratchy/*" -d "$TMPDIR/extract"
    cp -a "$TMPDIR/extract/Scritchy Scratchy/." "$out"/
    # UnityCrashHandler64.exe lingers after a clean quit; proton's
    # waitforexitandrun then waits on it forever and the wrapper /
    # gamescope never tear down. Unity runs fine without the reporter.
    rm -f "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "ScritchyScratchy.exe";

  # Unity IL2CPP persistentDataPath: AppData/LocalLow/<company>/<product>.
  saveLocations = [ "AppData/LocalLow/Lunch Money Games/Scritchy Scratchy" ];

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
    description = "Scritchy Scratchy (Lunch Money Games 2026, Unity scratch-card incremental, Steam via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "scritchy-scratchy";
  };
}
