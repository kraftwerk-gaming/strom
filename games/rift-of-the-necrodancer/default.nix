{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Rift of the NecroDancer (Brace Yourself Games, 2025). Unity rhythm
  # spinoff of Crypt of the NecroDancer. Windows-only; Brace Yourself
  # ships no native Linux build, but the game runs out of the box under
  # Proton / Steam Deck (community-confirmed), so runtime = "proton".
  #
  # SOURCE: archive.org item "rift-of-the-necro-dancer-1.5.0", a TENOKE
  # pre-installed v1.5.0 repack (Steam appid 2073250) bundling every DLC.
  # The repack ships the TENOKE Steam emulator as the DRM bypass:
  # RiftOfTheNecroDancer_Data/Plugins/x86_64/steam_api64.dll alongside a
  # tenoke.ini that pins the appid, language=english and overlay=false.
  # It is a self-contained emu (no real Steam client needed), so no
  # steam_api swap is required. The game tree sits under a single
  # top-level "RiftOfTheNecroDancerOSTVolume1/" folder.
  src = fetchIpfs {
    cid = "QmXYVe3vFfKvpMTzGP45BjMxrXwUmHDEMih8LZS5rRaqUb";
    fallbackUrl = "https://archive.org/download/rift-of-the-necro-dancer-1.5.0/Rift-Of-The-Necro-Dancer-1.5.0.rar";
    hash = "sha256-DBUOHad954mfuAF+Waknp4gEI5Q6tnt7xD4qcwNJQUE=";
    name = "rift-of-the-necrodancer-1.5.0.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rift-of-the-necrodancer";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    # unar nests its output under a folder named after the archive stem,
    # so the game tree lands at <stem>/RiftOfTheNecroDancerOSTVolume1/.
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/"RiftOfTheNecroDancerOSTVolume1/." "$out"/

    # Strip the bundled soundtrack (FLAC+MP3, ~3.5 GB of non-game audio),
    # the redist installers, the Unity burst-debug dir, the AnkerGames-
    # style URL/license droppings and the crash reporter. proton
    # waitforexitandrun waits for every wine process to exit, so a
    # lingering UnityCrashHandler wedges proton/gamescope open after a
    # clean quit (cf. dredge/atomicrops).
    rm -rf "$out/RiftOfTheNecroDancerSoundtrack" \
           "$out/Rift of the NecroDancer_BurstDebugInformation_DoNotShip"
    rm -f "$out/UnityCrashHandler64.exe" "$out/License.txt"

    test -f "$out/RiftOfTheNecroDancer.exe" \
      || { echo "RiftOfTheNecroDancer.exe missing from extracted tree" >&2; ls -la "$out" >&2; exit 1; }
    test -f "$out/RiftOfTheNecroDancer_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "TENOKE steam_api64.dll missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "RiftOfTheNecroDancer.exe";

  # Unity LocalLow tree (PCGamingWiki / SteamDB UFS): saves are
  # User<steamid>.riftsave under .../Saves, per-device settings under
  # .../Settings. Relocate the whole product folder so progress survives
  # wineprefix wipes.
  saveLocations = [ "AppData/LocalLow/Brace Yourself Games/Rift of the NecroDancer" ];

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
    # Match the appid the TENOKE emu (tenoke.ini) expects.
    SteamAppId = "2073250";
    SteamGameId = "2073250";
  };

  meta = {
    description = "Rift of the NecroDancer (Brace Yourself Games 2025, Unity rhythm game incl. all DLC, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rift-of-the-necrodancer";
  };
}
