{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  _7zz,
  binutils-unwrapped,
  cabextract,
}:

let
  # gbe_fork (Goldberg fork): drop-in steam_api.dll replacement that fakes
  # SteamAPI_Init / lsteamclient!CreateInterface. The repack ships Valve's
  # retail steam_api.dll, which under Proton with no real Steam install
  # hangs in CreateInterface waiting for steamclient.dll to handshake. The
  # 32-bit gbe_fork build returns success without contacting any Steam
  # process so DARKSOULS.exe finishes Steamworks init and reaches the
  # main menu.
  gbeFork = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # DSfix's d3d9.dll has d3dx9_43 in its IAT (the version supplied with
  # the DSfix build); Wine ships a d3dx9_43 builtin compiled out of
  # dlls/d3dx9_36/d3dx_helpers.c (same source, multiple version-specific
  # DLLs). The first DDS-format probe fires `_wassert L"0", L".../
  # d3dx9_36/d3dx_helpers.c",322` and DARKSOULS.exe aborts before any
  # window appears. Ship Microsoft's native d3dx9_43.dll out of the
  # standard MS redist (same package winetricks's `d3dx9_43` verb pulls)
  # and load it native first.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dark-souls-prepare-to-die-edition";

  src = fetchIpfs {
    cid = "Qme47DJC984rC7qCzMdQmoMYkcowVrdzfQhBDpQyq13FdF";
    fallbackUrl = "https://archive.org/download/dark-souls-prepare-to-die-edition.-7z/Dark%20Souls%20Prepare%20to%20Die%20Edition.7z";
    hash = "sha256-8BrawTa4bMVQXJeCAqoYyAcc30/HlyoNFwJhEASkQ3U=";
    name = "darksouls-ptde.zip";
  };

  nativeBuildInputs = [
    _7zz
    binutils-unwrapped
    cabextract
  ];

  # Layout inside the 7z:
  #   "Dark Souls Prepare to Die Edition/DATA/{DARKSOULS.exe, d3d9.dll,
  #     DSCM.exe, DSPWSteam.ini, fmodex.dll, fmod_event.dll,
  #     steam_api.dll, ...}"
  #
  # The repack actually only ships ONE d3d9 wrapper: it's *not* DSfix —
  # `strings d3d9.dll` shows "Dark Souls PVP Watchdog", "About Dark Souls
  # PVP Watchdog", "WinHttpConnect", etc. The d3d9.dll is DSPW/DSCM-Net
  # (the connectivity mod's render hook), not Durante's DSfix. Loading it
  # paints a "DSCM PVP Watchdog 1.17.2" overlay on every launch and
  # initiates outbound HTTP to bitbucket.org for update checks. We
  # ship single-player only, so we delete d3d9.dll, DSCM.exe, and
  # DSPWSteam.ini from $out/ and let Wine's builtin d3d9 render.
  #
  # The bundled steam_api.dll is Valve retail and hangs under Proton without
  # a live Steam process. We swap it for gbe_fork's x32 release build, which
  # is API-compatible and returns success synchronously.
  buildScript = ''
    mkdir -p "$out"
    # Unzip the DATA/ subtree only, stripping the top-level dir prefix
    # so files land directly in $out/. Avoids a 3 GB double-extraction
    # to $TMPDIR plus a copy into $out/.
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract" \
      'Dark Souls Prepare to Die Edition/DATA'
    cp -r "$TMPDIR/extract/Dark Souls Prepare to Die Edition/DATA/." "$out/"
    chmod -R u+w "$out"

    # Strip the DSCM/DSPW (Dark Souls PVP Watchdog) connectivity mod so the
    # game launches without the "DSCM PVP Watchdog 1.17.2" banner and the
    # outbound update-check HTTP request. d3d9.dll here is DSPW, not DSfix
    # (verified via `strings`, see comment block above).
    rm -f "$out/d3d9.dll" "$out/DSCM.exe" "$out/DSPWSteam.ini"

    mkdir -p "$out/steam_settings"

    # gbe_fork dispatches CreateInterface() requests by looking up the
    # requested version string in steam_settings/steam_interfaces.txt.
    # Without that file every Steamworks call returns NULL and the game
    # crashes on the first SteamAPI_ISteamUser_*() vtable dispatch
    # (observed: c0000005 access violation inside steam_api.dll text).
    #
    # gbe_fork's parser (settings_parser.cpp:try_parse_old_steam_interfaces_file)
    # uses substring std::string::find on each line and stores the WHOLE line
    # under the matched SettingsItf slot. Slot keys are tested in a fixed
    # order; the FIRST match wins per line. Critically, "SteamUser" is also
    # a prefix of "SteamUserStats", so a bare "SteamUserStats" line gets
    # stored as the USER slot's version string. Later, when DARKSOULS.exe
    # asks the steam_client to construct ISteamUser, gbe_fork passes
    # "SteamUserStats" to GetISteamUser(), which has no strcmp match and
    # pops up "INTERFACE=SteamUserStats CALLER FN=GetISteamUser()".
    #
    # Fix: emit ONLY versioned interface strings (no bare "SteamUser",
    # "SteamFriends", etc.) so each SettingsItf slot resolves to a numbered
    # variant gbe_fork's GetISteam*() dispatchers actually implement.
    # Matches the layout of release/steam_settings.EXAMPLE/
    # steam_interfaces.EXAMPLE.txt shipped with gbe_fork itself.
    strings "$out/steam_api.dll" \
      | grep -E '^(SteamClient[0-9]+|SteamUser[0-9]+|SteamFriends[0-9]+|SteamUtils[0-9]+|SteamMatchMaking[0-9]+|SteamMatchMakingServers[0-9]+|SteamGameServer[0-9]+|SteamGameServerStats[0-9]+|SteamNetworking[0-9]+|SteamController[0-9]+|STEAM[A-Z_]+_INTERFACE_VERSION[0-9]*)$' \
      | sort -u > "$out/steam_settings/steam_interfaces.txt"
    test -s "$out/steam_settings/steam_interfaces.txt"

    mkdir -p "$TMPDIR/gbe"
    7zz x -bso0 -bsp0 ${gbeFork} -o"$TMPDIR/gbe" release/regular/x32/steam_api.dll
    install -m0644 "$TMPDIR/gbe/release/regular/x32/steam_api.dll" "$out/steam_api.dll"

    # Two-stage cabextract of d3dx9_43.dll (32-bit) from the June 2010
    # DirectX redist. Outer SFX cabinet -> jun2010_d3dx9_43_x86.cab,
    # then that inner cab -> d3dx9_43.dll. DSfix's d3d9.dll IAT
    # imports `d3dx9_43.dll` (visible via `strings`), so Wine's builtin
    # d3dx9_43 (which shares src-wine/dlls/d3dx9_36/d3dx_helpers.c with
    # every other d3dx9_NN version) is what fires the assertion at
    # helpers.c:322. Drop Microsoft's native d3dx9_43.dll next to
    # DARKSOULS.exe and the WINEDLLOVERRIDES below force the loader
    # to bind it instead of Wine's builtin.
    mkdir -p "$TMPDIR/dx"
    cabextract -L -d "$TMPDIR/dx" -F 'jun2010_d3dx9_43_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx9_43.dll' \
      "$TMPDIR/dx/jun2010_d3dx9_43_x86.cab"
    install -m0644 "$TMPDIR/dx/d3dx9_43.dll" "$out/d3dx9_43.dll"

    # gbe_fork looks for steam_settings/ next to its DLL; some games also
    # check steam_appid.txt next to the exe. Cover both. AppId 211420 =
    # Dark Souls: Prepare to Die Edition on Steam.
    echo -n 211420 > "$out/steam_settings/steam_appid.txt"
    echo -n 211420 > "$out/steam_appid.txt"

    # Intro/title videos hang under Proton's wmvcore: DARKSOULS.exe runs
    # the WMV decoder synchronously on the main thread and blocks forever
    # on the FromSoftware/Bandai Namco logo + animated title playback.
    # Truncating the source files to 0 bytes makes the engine's "movie
    # decode failed" path fire and fall straight through to the main menu.
    # frpg_goodending.wmv is the END credits video — leave it intact.
    for f in movWW/frpg_opening.wmv movWW/frpg_title.wmv; do
      [ -f "$out/$f" ] && truncate -s 0 "$out/$f"
    done
  '';

  runtime = "proton";
  executable = "DARKSOULS.exe";

  saveLocations = [
    "AppData/Local/NBGI"
    "Documents/NBGI"
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Lock cursor + clicks to the game's nested Xwayland surface;
      # without this DARKSOULS.exe's GetCursorPos returns host-desktop
      # coordinates and the in-game pointer drifts off the window.
      "--force-grab-cursor" = true;
      # DARKSOULS uses the mouse for camera/character turn input, so
      # the system cursor would otherwise be visible at all times.
      # `--force-grab-cursor` puts gamescope into relative mouse mode
      # (so the engine gets motion deltas) and `-C 0` tells gamescope
      # to hide its pointer overlay with zero idle delay — combined
      # the cursor never appears.
      "-C" = "0";
      # Grab the keyboard so DARKSOULS receives Super/F-key combos
      # the host WM would otherwise eat. Disable with Super+G if needed.
      "--grab" = true;
    };
  };

  # Mask /dev/input/event* from the bwrap sandbox so the touchpad isn't
  # enumerated as a joystick by Xinput. DARKSOULS reads dinput devices
  # directly and an absolute-axis touchpad would jam the camera.
  extraBwrapArgs = [ "--tmpfs /dev/input" ];

  env = {
    SteamAppId = "211420";
    SteamGameId = "211420";
    # Real env knob honoured by protonfixes/__init__.py:check_conditions().
    # `PROTON_NO_GAME_FIXES` is a cargo-cult name that doesn't exist anywhere
    # in the protonfixes source — using it lets winetricks (vcrun/dotnet/etc)
    # fire on launch, which the user has explicitly forbidden.
    PROTONFIXES_DISABLE = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Wine DLL override map:
    #   steam_api -> gbe_fork stub (must load native, never builtin)
    #   d3dx9_43  -> Microsoft DX9 helper redist (Wine's builtin fails
    #                an assertion at d3dx9_36/d3dx_helpers.c:322 on the
    #                first DDS-format probe — same source compiled into
    #                every d3dx9_NN — so we ship the native one and load
    #                it first).
    # d3d9/dinput8 are not overridden: the rip's d3d9.dll was DSPW (PVP
    # Watchdog overlay), removed in buildScript above so the game now
    # uses Wine's builtin d3d9 / DXVK.
    WINEDLLOVERRIDES = "steam_api=n,b;d3dx9_43=n,b";
  };

  meta = {
    description = "Dark Souls: Prepare to Die Edition (single-player, DSCM stripped, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dark-souls-prepare-to-die-edition";
  };
}
