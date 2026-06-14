{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  libarchive,
  p7zip,
}:

let
  # Superliminal (Pillow Castle, 2019; Unity Mono x86_64). First-person
  # forced-perspective puzzle game, Steam AppId 1049410. No native Linux
  # build (the GOG release ships a Linux binary, but that build matchmakes
  # co-op through GOG Galaxy, which the sandbox does not emulate). We
  # deliberately package the WINDOWS STEAM build under Proton instead,
  # because Superliminal's online co-op (added in the Dec-2021 "Co-Op
  # launch" update) matchmakes through Steamworks lobbies, and gbe_fork
  # emulates those lobbies over LAN broadcast -- which is exactly what
  # strom's in-sandbox n2n virtual LAN carries. So Proton + gbe_fork keeps
  # multiplayer working; the native GOG/Galaxy path would break it.
  #
  # SOURCE: the AnkerGames pre-installed Windows Steam repack (Build
  # 10651429, post Co-Op update so multiplayer is present), a plain RAR5
  # with no installer. Layout is the standard Unity tree:
  #   SuperliminalSteam.exe + SuperliminalSteam_Data/ + UnityPlayer.dll +
  #   MonoBleedingEdge/. The repack already swaps the retail steam_api64.dll
  #   (kept as steam_api64.dll.bak) for a gbe_fork Goldberg build and ships
  #   a steam_settings/ tree under SuperliminalSteam_Data/Plugins/x86_64/.
  # The AnkerGames download URL is a per-IP, time-signed dlproxy link that
  # expires, so it is not a stable fallbackUrl -- IPFS-only once pinned.
  src = fetchIpfs {
    cid = "QmTHZZB5YwxEMurv341kd7W8X9JgjE3MtADdbLXahxRwrM";
    fallbackUrl = "";
    hash = "sha256-BhEnt6Rh7MFzuyJkPorbLR4Qiqs+2zLWVjM1RsiNMwQ=";
    name = "Superliminal-AnkerGames.rar";
  };

  # gbe_fork (the maintained Goldberg fork): drop-in steam_api64.dll that
  # implements real Steam LAN networking -- broadcast peer discovery,
  # emulated lobbies, and P2P -- which is what lets Superliminal's online
  # co-op find peers across strom's n2n LAN. We re-swap the repack's
  # (unknown-vintage) bundled gbe_fork dll for the same pinned release the
  # other strom gbe_fork games use (moving-out, ...), so every package
  # tracks one audited emu binary. The dll imports WS2_32.dll / IPHLPAPI.DLL
  # and exposes SteamNetworking + SteamMatchMaking; networking is left ON.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_30/emu-win-release.7z";
    hash = "sha256-ONDOgi949bIt0o2Uj0scmLxl9fw6hQt3dShnQ6YONRY=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "superliminal";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    libarchive
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/extract"
    # RAR5; p7zip 17.x can't read it but libarchive's bsdtar can. The archive
    # nests everything under a top-level Superliminal/ dir; strip it.
    bsdtar -xf "$src" -C "$TMPDIR/extract" --strip-components=1
    cp -a "$TMPDIR/extract"/. "$out"/
    chmod -R u+w "$out"

    # AnkerGames clutter.
    rm -f "$out"/*.url "$out/Read Me.txt"

    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit.
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"

    plugins="$out/SuperliminalSteam_Data/Plugins/x86_64"

    # Re-swap the repack's bundled gbe_fork dll for the pinned strom build,
    # both in the Unity plugin dir (where Steamworks.NET loads it) and at the
    # game root (gbe_fork also reads steam_appid.txt next to the exe).
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$plugins/steam_api64.dll"
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$out/steam_api64.dll"
    # Drop the retail backup the repack left behind.
    rm -f "$plugins/steam_api64.dll.bak"

    # Keep the repack's gbe_fork steam_settings/ tree (it already has
    # networking ON -- a listen_port is set and there is no
    # disable_networking.txt / disable_lan_only.txt -- so co-op LAN discovery
    # works out of the box). Pin the AppId next to both dll copies.
    settings="$plugins/steam_settings"
    echo -n 1049410 > "$settings/steam_appid.txt"
    echo -n 1049410 > "$out/steam_appid.txt"

    # The repack baked a FIXED user_steam_id.txt (76561197960287930). With a
    # constant id every player looks like the same Steam user, so lobby/peer
    # discovery collapses. Removing it makes gbe_fork mint a random per-machine
    # SteamID on first run (persisted to GSE Saves), so two players show up as
    # distinct users and can see+join each other's co-op lobby -- same
    # mechanism risk-of-rain-returns relies on.
    rm -f "$settings/settings/user_steam_id.txt"
  '';

  runtime = "proton";
  executable = "SuperliminalSteam.exe";

  # Unity LocalLow tree (company / product from SuperliminalSteam_Data/app.info:
  # "PillowCastle" / "SuperliminalSteam"). gbe_fork's emulated Steam state
  # (configs.user.ini holding the minted SteamID, plus any remote storage)
  # lands under AppData/Roaming/GSE Saves; preserve both across prefix wipes.
  saveLocations = [
    "AppData/LocalLow/PillowCastle/SuperliminalSteam"
    "AppData/Roaming/GSE Saves"
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

  # Bind the native gbe_fork steam_api64.dll instead of Proton's builtin
  # lsteamclient proxy, which would route SteamAPI_Init through a real Steam
  # process that does not exist in the sandbox.
  env = {
    SteamAppId = "1049410";
    SteamGameId = "1049410";
    WINEDLLOVERRIDES = "steam_api64=n,b;lsteamclient=";
  };

  meta = {
    description = "Superliminal (Pillow Castle 2019, Unity forced-perspective puzzle game, Windows Steam build + gbe_fork co-op via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "superliminal";
  };
}
