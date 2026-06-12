{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  p7zip,
}:

let
  # Risk of Rain Returns (Hopoo Games / Gearbox 2023, GameMaker Studio 2).
  # Windows-only Steam release; no native Linux build exists. Source is a
  # pre-installed v1.0.4 SteamUnlocked/TENOKE zip (tenoke.ini present)
  # uploaded to archive.org on 2024-01-02 (archive.org malware-checked).
  # Ships TENOKE's own steam_api64.dll Steam-emulator stub so the game runs
  # without a Steam client. Runs under Proton (GE-Proton).
  #
  # Zip double-nests the game: outer wrapper dir contains a _Redist folder
  # (Windows redistributables, not needed) and the inner game dir which holds
  # Risk of Rain Returns.exe, data.win, and all .ogg music files.
  src = fetchIpfs {
    cid = "QmNiTVVP7VDELisTdURfps3UitHddSLPQ45RLj63whApd7";
    fallbackUrl = "https://archive.org/download/risk.of.-rain.-returns.v-1.0.4/Risk.of.Rain.Returns.v1.0.4.zip";
    hash = "sha256-W/74h6eey84pL6F6L0xvhA22lKFfdQZPr4vd9GV11gg=";
    name = "Risk.of.Rain.Returns.v1.0.4.zip";
  };

  # gbe_fork (the maintained Goldberg fork): drop-in steam_api64.dll that
  # implements real Steam LAN networking -- broadcast peer discovery,
  # emulated lobbies, and P2P -- the same emu family Magicka uses for co-op.
  # The TENOKE stub it replaces has ZERO networking (no ws2_32 import, no
  # SteamNetworking/SteamMatchMaking interface implementation): it is an
  # offline single-player stub, so RoR's online co-op is dead with it. Same
  # pinned release the other strom gbe_fork games use (endless-legend,
  # slay-the-spire-2, outer-wilds, ...).
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "risk-of-rain-returns";

  inherit src;

  nativeBuildInputs = [
    unzip
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    # The zip double-nests the game data:
    #   Risk.of.Rain.Returns.v1.0.4/               ← outer wrapper
    #     _Redist/                                  ← Windows redistributables (skip)
    #     HOW TO RUN GAME!!.txt                     ← skip
    #     STEAMUNLOCKED...url                       ← skip
    #     Risk.of.Rain.Returns.v1.0.4/              ← inner game dir
    #       Risk of Rain Returns.exe
    #       data.win, steam_api64.dll, ...
    # Flatten the inner game dir directly into $out.
    inner="$TMPDIR/extract/Risk.of.Rain.Returns.v1.0.4/Risk.of.Rain.Returns.v1.0.4"
    cp -r "$inner"/. "$out"/
    chmod -R u+w "$out"

    # Replace the networking-less TENOKE steam_api64.dll with gbe_fork's
    # 64-bit drop-in (next to the .exe, where GameMaker's Steamworks_x64.dll
    # bridge loads it). gbe_fork's dll imports WS2_32.dll / IPHLPAPI.DLL and
    # implements SteamNetworking + SteamMatchMaking, which is what makes LAN
    # co-op work; TENOKE's stub imports neither.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$out/steam_api64.dll"

    # gbe_fork dispatches CreateInterface() by looking up the requested
    # version string in steam_settings/steam_interfaces.txt; without it the
    # game's Steam init hits the wrong vtable slots and crashes/hangs at boot.
    # These are the EXACT versions RoR requests, extracted from the game's own
    # GameMaker<->Steamworks bridge (Steamworks_x64.dll) -- the dll that calls
    # CreateInterface -- via `strings | grep '^Steam...NNN$'`. gbe_fork's
    # release-2026_04_25 x64 dll implements every one of these (verified by
    # exact-match grep of the dll's interface strings). This is Steamworks SDK
    # ~1.51-era and is the authoritative request set, not a guess.
    mkdir -p "$out/steam_settings"
    cat > "$out/steam_settings/steam_interfaces.txt" <<'EOF'
    SteamClient020
    SteamUser021
    SteamFriends017
    SteamUtils010
    SteamMatchMaking009
    SteamController008
    SteamInput006
    SteamNetworking006
    STEAMAPPS_INTERFACE_VERSION008
    STEAMAPPTICKET_INTERFACE_VERSION001
    STEAMREMOTESTORAGE_INTERFACE_VERSION016
    STEAMSCREENSHOTS_INTERFACE_VERSION003
    STEAMUGC_INTERFACE_VERSION016
    STEAMUSERSTATS_INTERFACE_VERSION012
    EOF

    # RoR appid 1337520. gbe_fork reads ownership appid from steam_appid.txt;
    # provide it both next to its dll (steam_settings/) and next to the exe.
    echo -n 1337520 > "$out/steam_settings/steam_appid.txt"
    echo -n 1337520 > "$out/steam_appid.txt"
  '';

  runtime = "proton";

  executable = "Risk of Rain Returns.exe";

  # GMS2 writes local save data to %LOCALAPPDATA%\Risk_of_Rain_Returns
  # (PCGamingWiki). The Steam-cloud path (userdata/1337520/remote/save.json)
  # is not used with the bundled TENOKE emu; the engine falls back to the
  # local AppData path. Preserving this across prefix wipes keeps unlocks and
  # run history.
  saveLocations = [ "AppData/Local/Risk_of_Rain_Returns" ];

  # gbe_fork mints a RANDOM per-machine SteamID on first run (parse_user_steam_id
  # falls through to generate_steam_id_user() when no id is configured) and
  # persists it to %APPDATA%\GSE Saves\settings\configs.user.ini
  # (account_steamid). Verified both in gbe_fork's source and empirically: two
  # fresh prefixes got distinct IDs (76561199280103826 vs 76561199534996918).
  # So two players already look like distinct Steam users and can see+join each
  # other's lobby -- NO manual id seed is needed (unlike Magicka, whose repack
  # baked a FIXED id; the original TENOKE stub here baked one too, which is why
  # discovery was dead). LAN is on by default; we set no disable_lan, so co-op
  # discovery works out of the box. Replaces the old tenoke.ini id-rewrite preRun.
  #
  # No n2n.defaultRoute: co-op was EMPIRICALLY PROVEN to work with the default
  # route left on slirp's tap0 (two-instance LAN host+join connected). gbe_fork
  # learns peers from the SOURCE IP of the overlay broadcast (which arrives on
  # edge0 via the launcher's unconditional 255.255.255.255 -> edge0 route), so
  # it dials the right overlay address without pinning the default route to
  # edge0 -- same source-IP mechanism as Magicka.

  # Force the loader to bind the native (gbe_fork) steam_api64.dll instead of
  # Proton's builtin lsteamclient proxy, which would re-route SteamAPI_Init
  # through a real Steam process that doesn't exist in the sandbox.
  env = {
    SteamAppId = "1337520";
    SteamGameId = "1337520";
    WINEDLLOVERRIDES = "steam_api64=n,b;lsteamclient=";
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
    description = "Risk of Rain Returns (Hopoo Games / Gearbox 2023, GameMaker Studio 2 Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risk-of-rain-returns";
  };
}
