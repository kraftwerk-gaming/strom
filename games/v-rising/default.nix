{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmNxWYo1ymaGAtdQhASRgNNxsL7Wtf7zt3QUUWbpi3ANX4";
    fallbackUrl = "";
    hash = "sha256-xoLmimy+ofsIYr/xnrXagJjnSvTt7mbNtthMLcPsR/k=";
    name = "v-rising-ankergames.rar";
  };

  # Goldberg / gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init etc. The repack ships an OnlineFix Mono-injection emu
  # (winmm.dll proxy + OnlineFix64.dll) which doesn't get hooked under
  # GE-Proton, so PlatformSystemBase.TryInitClient sees the unpatched
  # steam_api64.dll and Steamworks.NET fails with
  # "Steamworks API initialization Failed!". Goldberg is a static DLL
  # replacement and works under proton (same approach as outer-wilds).
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "v-rising";

  inherit src;

  nativeBuildInputs = [
    unar
    p7zip
  ];

  # AnkerGames RAR5 layout: archive root contains VRising/ and an
  # "AnkerGames - Free Pre-installed PC Games.url" advert at top level.
  # VRising/ holds the playable Unity build (VRising.exe, VRising_Data/,
  # GameAssembly.dll, UnityPlayer.dll) plus the OnlineFix bundle
  # (OnlineFix64.dll, winmm.dll, SteamOverlay64.dll, OnlineFix.ini) that
  # lets the game launch without a Steam client. A sibling VRising/v3/
  # subtree ships an alternate build variant; we use the top-level
  # build, which is the one the repack's launcher entry points at.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/VRising/* "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
    chmod -R u+w "$out"

    # Drop the repack's OnlineFix winmm proxy from BOTH the client and
    # the bundled dedicated server (VRising_Server/). OnlineFix relies
    # on a DllMain hook that GE-Proton's loader doesn't run for the
    # loader-injected winmm.dll, so steam_api64.dll stays unpatched.
    # Without this, the client logs "Steamworks API initialization
    # Failed!" and the server (spawned by "Play (LAN/Offline)") logs
    # "Unable to Initialize Steam GameServer!", leaving the client
    # stuck at "Connecting to SteamIPv4://127.0.0.1:9876".
    rm -f "$out/winmm.dll" "$out/OnlineFix64.dll" "$out/OnlineFix.ini" \
      "$out/SteamOverlay64.dll"
    rm -rf "$out/[Steam]"
    rm -f "$out/VRising_Server/winmm.dll" \
      "$out/VRising_Server/OnlineFix64.dll" \
      "$out/VRising_Server/OnlineFix.ini" \
      "$out/VRising_Server/SteamOverlay64.dll"
    rm -rf "$out/VRising_Server/[Steam]"

    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    goldberg_dll="$TMPDIR/goldberg/release/regular/x64/steam_api64.dll"

    # DLC list shared between client and server Goldberg configs
    # (from OnlineFix.ini's [DLC] section).
    dlc_block=$(cat <<'EOF'
    [app::dlcs]
    unlock_all=0
    3604340=V Rising - Eternal Dominance Pack
    2833600=V Rising - Legacy of Castlevania Premium Pack
    2358430=V Rising - Sinister Evolution Pack
    2169180=V Rising - Haunted Nights Castle Pack
    1997210=V Rising - Razer Night Serpent Pack
    1983901=V Rising - Founder's Pack: Eldest Bloodline
    1983900=V Rising - Dracula's Relics Pack
    EOF
    )

    # Patch client + dedicated-server plugin dirs. Goldberg looks for
    # steam_settings/ next to its steam_api64.dll; the same DLL handles
    # both SteamAPI_Init() (client) and SteamGameServer_Init() (server).
    for plugins in \
      "$out/VRising_Data/Plugins/x86_64" \
      "$out/VRising_Server/VRisingServer_Data/Plugins/x86_64"; do
      cp "$goldberg_dll" "$plugins/steam_api64.dll"
      settings="$plugins/steam_settings"
      mkdir -p "$settings"
      echo -n 1604030 > "$settings/steam_appid.txt"
      printf '%s\n' "$dlc_block" > "$settings/configs.app.ini"
    done

    # Some games look for steam_appid.txt next to the exe too.
    echo -n 1604030 > "$out/steam_appid.txt"
    echo -n 1604030 > "$out/VRising_Server/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "VRising.exe";

  # V Rising writes saves, settings, and Player.log under
  # AppData/LocalLow/Stunlock Studios/VRising — pull them out of the
  # wineprefix so they survive proton-bump auto-wipes.
  saveLocations = [
    "AppData/LocalLow/Stunlock Studios"
  ];

  env = {
    SteamAppId = "1604030";
    SteamGameId = "1604030";
  };

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
    description = "V Rising (Stunlock Studios 2024, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "v-rising";
  };
}
