{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
  zstd,
  gnutar,
  binutils-unwrapped,
}:

let
  # Antichamber (Alexander Bruce / Demruth, 2013) is a first-person
  # non-euclidean puzzle game built on UDK (Unreal Engine 3, engine
  # build 7977). It only ever shipped on Steam -- there is no GOG
  # release.
  # runtime = "proton": no native Linux build is carried here, UDK.exe is
  # the Win32 engine binary.
  #
  # SOURCE: the official ENGLISH Steam build v2014.06.12, repacked locally
  # to a deterministic tar.zst of the install tree (Binaries/Win32/UDK.exe
  # + UDKGame/ + Engine/).
  #
  # WHY NOT the archive.org "antichamber-2013" ISO: that item's Inno
  # installer header claims `english`, but it is in fact the RUSSIAN build
  # -- in-game wall-sign text renders in Cyrillic. Antichamber bakes its
  # sign/puzzle text into the cooked, LZO-compressed Maps/Hazard/ map (it
  # is NOT in the .int loc files or the *_LOC_INT.upk packages), so the
  # text is not switchable via `-LANGUAGE=INT`; the only fix is an English
  # Hazard map, i.e. a genuinely English source. The English build's
  # localized packages are also smaller (Startup_LOC_INT.upk 2.23 MB vs the
  # Russian 6.13 MB) and the tree carries no RUS localization dir
  # (UDKGame/Localization/ = INT; Engine/Localization/ = INT/CHN/JPN/KOR).
  #
  # Rebuild the tar: fetch the v2014.06.12 ZIP (steamunlocked), extract the
  # inner `Antichamber/` game root, and
  #   tar --sort=name --owner=0 --group=0 --numeric-owner \
  #       --mtime='2014-06-12 00:00:00 UTC' -cf - . | zstd -19 -T0
  src = fetchIpfs {
    cid = "QmNqHYfVSpdkBLCpYSFQUC7dii1uorK9oJGP42dpUW4QLn";
    fallbackUrl = "";
    hash = "sha256-Gyf7FPk0qCTE0js9FlxoM52oV+1VIv4/9R7PujpCIn4=";
    name = "antichamber-en-2014.06.12.tar.zst";
  };

  # gbe_fork (Goldberg fork): drop-in steam_api.dll that fakes
  # SteamAPI_Init without contacting any Steam process. The repack ships a
  # SmartSteamEmu loader (smoke_api.dll), but the cooked
  # OnlineSubsystemSteamworks separately does LoadLibrary("steam_api.dll")
  # at startup; with no steam_api.dll present that returns
  # ERROR_MOD_NOT_FOUND (126). Dropping a real 32-bit gbe_fork
  # steam_api.dll next to UDK.exe lets Steamworks init resolve cleanly
  # offline. (The startup hang itself is the UnSetup/EULA gate handled in
  # preRun, not this; the steam DLL is here so the OnlineSubsystem path is
  # clean rather than erroring through a missing module.)
  gbeFork = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "antichamber";

  inherit src;

  nativeBuildInputs = [
    p7zip
    zstd
    gnutar
    binutils-unwrapped
  ];

  buildScript = ''
    mkdir -p "$out"
    # tar.zst of the English install tree -> $out
    zstd -d -c "$src" | tar -x -C "$out"
    chmod -R u+w "$out"
    # Keep Binaries/UnSetup.exe + Binaries/UDK.exe: on startup the Win32
    # UDK.exe shells out to ..\UnSetup.exe for its first-run/update check
    # (and that path expects the UDK editor stub alongside). Remove either
    # and UDK.exe pops a modal "File not found." MessageBox over the splash
    # ("Failed to launch UnSetup.exe. Please reinstall."), then asserts and
    # crashes before the GFx main menu loads. Only the standalone memory
    # debugger (never invoked under Proton) is dropped.
    rm -f "$out/Binaries/MemLeakCheckDiffer.exe" \
          "$out/Binaries/MemLeakCheckDiffer.exe.config"

    # Steam: drop a real 32-bit gbe_fork steam_api.dll next to UDK.exe so
    # OnlineSubsystemSteamworks resolves Steamworks offline (the repack's
    # smoke_api.dll loader is left in place; gbe_fork is what the cooked
    # OnlineSubsystem actually binds by name).
    mkdir -p "$TMPDIR/gbe"
    7z x -y ${gbeFork} -o"$TMPDIR/gbe" release/regular/x32/steam_api.dll >/dev/null
    install -m0644 "$TMPDIR/gbe/release/regular/x32/steam_api.dll" \
      "$out/Binaries/Win32/steam_api.dll"

    # gbe_fork resolves CreateInterface() version strings from
    # steam_settings/steam_interfaces.txt (next to the DLL); without it
    # every interface dispatch returns NULL. Emit only the versioned
    # interface strings the DLL itself exports (matches gbe_fork's own
    # steam_interfaces.EXAMPLE.txt layout).
    mkdir -p "$out/Binaries/Win32/steam_settings"
    strings "$out/Binaries/Win32/steam_api.dll" \
      | grep -E '^(SteamClient[0-9]+|SteamUser[0-9]+|SteamFriends[0-9]+|SteamUtils[0-9]+|SteamMatchMaking[0-9]+|SteamMatchMakingServers[0-9]+|SteamGameServer[0-9]+|SteamGameServerStats[0-9]+|SteamNetworking[0-9]+|SteamController[0-9]+|SteamUserStats[0-9]+|SteamApps[0-9]+|SteamRemoteStorage[0-9]+|STEAM[A-Z_]+_INTERFACE_VERSION[0-9]*)$' \
      | sort -u > "$out/Binaries/Win32/steam_settings/steam_interfaces.txt"
    test -s "$out/Binaries/Win32/steam_settings/steam_interfaces.txt"

    # AppId 219890 = Antichamber on Steam. gbe_fork reads steam_appid.txt
    # both next to the DLL and under steam_settings/.
    echo -n 219890 > "$out/Binaries/Win32/steam_appid.txt"
    echo -n 219890 > "$out/Binaries/Win32/steam_settings/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "Binaries/Win32/UDK.exe";

  # Pin English. The source is the official multi-language Steam build
  # (Engine/Localization/ ships INT/CHN/JPN/KOR), so on a fresh prefix UDK
  # would otherwise pick the localization from the system locale. UE3/UDK
  # honours `-LANGUAGE=<code>` on the engine command line, which
  # short-circuits the generated UDKEngine.ini Language= and the
  # system-locale fallback, pinning the localization mount to INT
  # (English). Same mechanism used for spec-ops-the-line.
  executableArgs = [ "-LANGUAGE=INT" ];

  # Antichamber persists progress to a single SavedGame.bin written next
  # to the engine binary (Binaries/Win32/), and UDK writes its generated
  # config (UDKEngine.ini, UDKInput.ini, ...) into UDKGame/Config/. None
  # of that lives under drive_c/users/steamuser, so the generic
  # saveLocations relocation can't reach it; it persists instead via the
  # fuse-overlayfs writable upper. The save redirect that matters is done
  # in preRun: SavedGame.bin is symlinked onto plain btrfs so it survives
  # prefix wipes (and dodges the FUSE case-insensitive-lookup trap).
  saveLocations = [ ];

  # Take the savegame OFF the fuse-overlayfs merged mount and onto plain
  # btrfs ($STROM_GAMEDIR, the overlay's writable upper, is also bind-
  # mounted as itself). The engine opens Binaries\Win32\SavedGame.bin
  # relative to its cwd; following a symlink to the btrfs target keeps the
  # file off FUSE (so a mixed-case fopen still resolves) and makes the
  # single save persist across prefix wipes, exactly like saveLocations
  # does for drive_c saves.
  #
  # preRun also pre-accepts the UDK EULA in the registry. At startup
  # Binaries/Win32/UDK.exe reads
  #   HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\UDK-<GUID>
  #   value "EULAAccepted"
  # where <GUID> is the <InstallGuidString> from Binaries/InstallInfo.xml
  # (NOT the UnSetup.Game.xml GUIDs). When it is not 1, UDK shells out to
  # ..\UnSetup.exe /EULA, which on a fresh prefix pops a blocking .NET
  # "Unreal Engine 3 UDK license terms" window with an "I ACCEPT" button --
  # with no human to click it the launch wedges on the splash. Seeding
  # EULAAccepted=1 for that GUID makes UDK skip UnSetup entirely and load
  # straight into the GFx menu. The 32-bit UDK.exe's HKLM\SOFTWARE read is
  # WOW64-redirected to Wow6432Node, which is where wine's regedit lands a
  # SOFTWARE write, so the key is visible to the engine.
  preRun = ''
    STROM_SAVE_REAL="$STROM_GAMEDIR/.savegame-real"
    # Write the SavedGame.bin symlink directly into the overlay's writable
    # UPPER ($STROM_GAMEDIR), not into the merged mount ($GAMEDIR). Creating
    # the symlink under the merged mount's lower-only Binaries/Win32/ forces
    # fuse-overlayfs to copy-up that whole directory, and the patched
    # in-userns fuse-overlayfs (squash_to_uid) returns ENOMEM during that
    # copy-up ("ln: ... Cannot allocate memory"). The upper is bind-mounted
    # as itself, so $STROM_GAMEDIR/Binaries/Win32/ resolves to the same path
    # the engine reaches via cwd. A plain mkdir in the upper does NOT set the
    # overlay opaque xattr, so fuse-overlayfs still MERGES the lower
    # Binaries/Win32/ (UDK.exe + DLLs) with this upper dir -- the engine sees
    # both the binaries and the save symlink. The save stays off FUSE on
    # plain btrfs ($STROM_SAVE_REAL) so it survives prefix wipes and dodges
    # the FUSE case-insensitive-lookup trap.
    SAVE_LINK="$STROM_GAMEDIR/Binaries/Win32/SavedGame.bin"
    mkdir -p "$STROM_GAMEDIR/Binaries/Win32"
    if [ -e "$SAVE_LINK" ] && [ ! -L "$SAVE_LINK" ]; then
      cp -an "$SAVE_LINK" "$STROM_SAVE_REAL" 2>/dev/null || true
      rm -f "$SAVE_LINK"
    fi
    [ -e "$STROM_SAVE_REAL" ] || : > "$STROM_SAVE_REAL"
    ln -snf "$STROM_SAVE_REAL" "$SAVE_LINK"

    PFX="$STROM_COMPATDATA/0/pfx"
    # GUID from InstallInfo.xml's <InstallGuidString> -- the one UDK.exe
    # uses to build the UDK-<GUID> uninstall key. xmllint isn't on the
    # path, so pull the bare GUID out with grep.
    GUID=$(grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' \
      "$GAMEDIR/Binaries/InstallInfo.xml" 2>/dev/null | head -1)
    # Seed only when the prefix exists and the accepted key isn't already
    # present (regedit is idempotent but ~1-2s, so skip on warm prefixes).
    if [ -f "$PFX/system.reg" ] && [ -n "$GUID" ] \
        && ! grep -q "UDK-$GUID" "$PFX/system.reg" 2>/dev/null; then
      WINE="${pkgs.callPackage ../../pkgs/proton.nix { }}/files/bin/wine"
      {
        echo 'Windows Registry Editor Version 5.00'
        echo
        echo "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\UDK-$GUID]"
        echo '"EULAAccepted"=dword:00000001'
        echo
      } > "$GAMEDIR/udk-eula.reg"
      export WINEPREFIX="$PFX"
      export WINEDEBUG=-all
      timeout 60 "$WINE" regedit /S "$GAMEDIR/udk-eula.reg" >/dev/null 2>&1 || true
      "$WINE"server -w 2>/dev/null || true
    fi
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Antichamber is a first-person mouse-look game. Without a relative
      # cursor grab gamescope feeds the engine absolute pointer positions
      # and synthesises motion from successive warps; on a HiDPI seat
      # (e.g. 2880x1920) scaled into the 1920x1080 nest those warp deltas
      # are inflated, so in-game look speed comes out wildly too fast.
      # `--force-grab-cursor` puts gamescope into relative-mouse mode and
      # hands UDK.exe raw 1:1 motion deltas (seat-resolution independent),
      # which is the canonical strom fix for mouse-look games under the
      # nest (cf. dark-souls, arx-fatalis). It also keeps the system
      # cursor locked to the surface so it can't drift off the window.
      # NB: the baked input config is stock (UDKGame/Config DefaultInput.ini
      # MouseSensitivity=30.0, the UE3 default), and the engine already
      # self-caps to ~60fps (BaseEngine.ini [Engine.Engine]
      # bSmoothFrameRate=TRUE/MaxSmoothedFrameRate=62), so neither an
      # inflated sensitivity nor the famous UDK FPS-linked-mouse-speed
      # quirk is in play here -- the inflation is purely the gamescope
      # absolute-warp path, which this flag removes. If look speed still
      # needs trimming the in-game Options sensitivity slider (or console
      # `setsensitivity <n>` / DefaultInput.ini MouseSensitivity) tunes it.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Antichamber (Alexander Bruce 2013, UDK/UE3 puzzle, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "antichamber";
  };
}
