{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Crow Country (SFB Games, 2024). Retro-styled survival-horror built on
  # Unity. No native Linux build is shipped -- the developer points Linux
  # players at Steam Play / Proton (PCGamingWiki lists "Steam Play (Linux)"),
  # so runtime = "proton".
  #
  # SOURCE: GOG offline installer, Windows build 82810 (version 1.0.7),
  # single-part Inno setup (~457 MB). innoextract --gog yields the GOG
  # `app/` layout with "Crow Country.exe" + "Crow Country_Data/" +
  # UnityPlayer.dll at the install root.
  src = fetchIpfs {
    cid = "QmPaPLesWagh5s8ZpKNiCMWSYxhNypN8CAcvTydoxmGrsY";
    fallbackUrl = "https://gog-games.to/game/crow_country"; # GOG via gog-games.to mirror, build 82810
    hash = "sha256-sy9/sGUgvIM+W9m4jbPO5/Q/CdiLEAJKCPz23Z2RWvg=";
    name = "setup_crow_country_1.0.7_64bit_82810.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "crow-country";

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
    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. dredge, chants-of-sennaar).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "Crow Country.exe";

  # Unity LocalLow tree (PCGamingWiki): AppData/LocalLow/SFB Games/Crow Country
  # holds the save data; the in-game config lives in the wine registry under
  # SOFTWARE\SFB Games\Crow Country (user.reg), not a flat file.
  saveLocations = [ "AppData/LocalLow/SFB Games/Crow Country" ];

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
    description = "Crow Country (SFB Games 2024, Unity survival-horror, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "crow-country";
  };
}
