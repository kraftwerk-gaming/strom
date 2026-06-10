{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  innoextract,
  cabextract,
  p7zip,
  unzip,
}:

let
  # Microsoft DirectX End-User Runtime (February 2010 redistributable).
  # The native DirectMusic DLLs Gothic II needs live in the nested `dxnt.cab`
  # inside this self-extracting cabinet.  Same package as Gothic 1.
  directxFeb2010 = fetchurl {
    url = "https://web.archive.org/web/20100205120000id_/https://download.microsoft.com/download/E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe";
    hash = "sha256-9tGR6JqWPXzKNPFp0w9J6rmcHtO7ktpz7ENhfKqh6T8=";
    name = "directx_feb2010_redist.exe";
  };

  # The native DirectMusic DLL set winetricks's `directmusic` installs.
  # Gothic II's zCMusicSys_DirectMusic::Play crashes through GE-Proton's
  # incomplete builtin dmusic/dmime/dmsynth just as Gothic 1 does.  The
  # same native Microsoft set is the community-proven fix.
  directMusicDlls = [
    "devenum"
    "dmband"
    "dmcompos"
    "dmime"
    "dmloader"
    "dmscript"
    "dmstyle"
    "dmsynth"
    "dmusic"
    "dswave"
    "dsound"
    "quartz"
  ];

  # The "report version" Gothic II Night of the Raven engine binary.
  # kirides GD3D11's ddraw.dll loader hooks Gothic2.exe at fixed virtual
  # addresses (zCWorld/zCBspTree/zFILE/... VAs from GothicMemoryLocations
  # 2_6_fix.h); it also checks GetProcAddress(shw32.dll, "InitPatch") at
  # startup to confirm Union is present (HookedFunctions.cpp:InitHooks).
  # The GOG Gold Gothic2.exe has *different* fixed-offset layout than the
  # "2.6 fix" / report-version binary the renderer was compiled against, so
  # any hook that touches a GOG-only VA either corrupts memory or faults at
  # world entry -- reproducing the exact "video flicker + New Game crash"
  # symptoms.  The community-standard fix: replace the GOG exe with the
  # report-version binary from Gratt's gothic-fix-archive before launching.
  #
  # The GOG Gold Edition ships the Night-of-the-Raven (NoTR/addon) engine,
  # so the correct primary patch is "Primary patch Gothic 2 NoTR.7z"
  # (Gothic2.exe ~8.7 MB, datestamped 2016-05-27), not the plain G2 one.
  primaryPatch = fetchurl {
    url = "https://raw.githubusercontent.com/Gratt-5r2/gothic-fix-archive/main/primary-patch/Primary%20patch%20Gothic%202%20NoTR.7z";
    hash = "sha256-Men8gLJYsHcLcff9LQCSiYM0WMagoTp+/U7MOkO5pY8=";
    name = "Primary-patch-Gothic-2-NoTR.7z";
  };

  # Union 1.0m (Gratt's ZenGin engine-extension framework for both Gothic 1
  # and Gothic 2).  Union supplies the in-memory engine patches (Union.patch)
  # and the modern VDFS the renderer expects, and exports InitPatch from
  # Shw32.dll -- the signal GD3D11 checks to confirm it's running on the
  # patched engine.  Same archive as used by Gothic 1; Union.patch contains
  # patches for all supported engine versions and auto-selects at load time.
  #   System/Shw32.dll     -- Union runtime (exports InitPatch)
  #   System/Union.patch   -- engine binary-patch set
  #   System/Vdfs32g.dll   -- Union's VDFS layer
  #   System/msvcp100.dll, msvcr100.dll -- VC++ 2010 runtime Union needs
  #   System/stdhost.exe   -- Union launcher host
  #   Data/Union.vdf       -- Union script/asset bundle
  union = fetchurl {
    url = "https://raw.githubusercontent.com/Gratt-5r2/gothic-fix-archive/main/union/Union%201.0m.7z";
    hash = "sha256-ml/f98Ho0zwOa5BRN18laaNSsarINQQLbvgct/ks8wg=";
    name = "Union-1.0m.7z";
  };

  # kirides GD3D11 v17.9.7 -- the modern, actively-maintained Direct3D 11
  # renderer for both Gothic 1 and Gothic 2.  The same zip that Gothic 1 uses;
  # the ddraw.dll loader is universal: it auto-detects the running executable
  # (Gothic.exe vs Gothic2.exe) at DllMain time and loads the matching engine
  # core from GD3D11/Bin/:
  #   g1.dll / g1_avx / g1_avx2    -- Gothic 1 1.08k renderer cores
  #   g1a.dll                       -- Gothic 1 addon renderer
  #   g2a.dll / g2a_avx / g2a_avx2  -- Gothic 2 Night of the Raven cores
  #   g2_spacer.dll / g1_spacer.dll -- Spacer tool variants
  # For Gothic 2 Gold (= NoTR) the g2a* cores are selected automatically.
  # The ddraw.dll replaces Gothic's original DirectDraw7 path entirely via
  # D3D11 (-> DXVK), fixing the video flicker (DirectDraw->DXVK renders Bink
  # frames correctly) and the New-Game world-entry crash (hooks now bind to
  # the correct report-version VAs).
  gd3d11 = fetchurl {
    url = "https://github.com/kirides/GD3D11/releases/download/v17.9.7/GD3D11-v17.9.7.zip";
    hash = "sha256-RMqOpZZs9eeTUlzKY4URTWcBb6+/ZrEOI8HxW4Efm9A=";
    name = "GD3D11-v17.9.7.zip";
  };

  # Gothic II: Gold Edition (Piranha Bytes 2003, Night of the Raven expansion
  # bundled).  GOG offline installer v2.7 win10 build 55878, split format:
  #   setup_gothic_2_gold_2.7_win10_(55878).exe   -- 876 KiB Inno Setup stub
  #   setup_gothic_2_gold_2.7_win10_(55878)-1.bin -- 2.25 GiB game data slob
  # innoextract --gog reads the .exe stub and pulls data from the .bin slice.
  # The two files must reside in the same directory with matching base names.
  #
  # Stub exe (876 KiB): no stable public HTTP mirror; seed via IPFS after test.
  setupExe = fetchIpfs {
    cid = "QmRqRswjxcgiqBUZNwHphd7xC6AtarKnjubZxMwjzXirHH";
    hash = "sha256-CbZX3We6Fqg0kcwdZgAcRSF3oZqtN4BA5IkCT5Fn1Kg=";
    name = "setup_gothic_2_gold_2.7_win10_55878.exe";
  };

  # Data bin (2.25 GiB): archived at archive.org.
  src = fetchIpfs {
    cid = "QmeTtngpG3MdbSFyhpiZjF5tjBeoADwy1fJk9xPVv1kHcw";
    fallbackUrl = "https://archive.org/download/setup_gothic_2_gold_2.7_win10_55878-1/Gothic%20II%20Gold%20Edition%20%282005%29/setup_gothic_2_gold_2.7_win10_%2855878%29-1.bin";
    hash = "sha256-RzM6xUkeUNvxX7I9W1uSv9qaM7+IhhZCAgzJZVGkpXY=";
    name = "setup_gothic_2_gold_2.7_win10_55878-1.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gothic-ii";

  inherit src;
  ipfsSources = [
    src
    setupExe
  ];

  nativeBuildInputs = [
    innoextract
    cabextract
    p7zip
    unzip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iss" "$TMPDIR/inno"

    # The GOG win10 v2.7 installer uses plain Inno Setup 5 format (NOT the
    # older GOG Galaxy slob embedding): game files are packed directly in
    # the Inno archive, so innoextract --gog would only extract __redist
    # and miss the actual game tree.  Plain innoextract (no --gog flag)
    # extracts everything; --exclude-temp drops installer-side temp files.
    #
    # The stub .exe and data .bin must live in the same directory with
    # matching base names (stub base == bin base minus "-1").
    # Innoextract layout for this build:
    #   system/        -- Gothic2.exe + engine DLLs (Miles, Bink, ...)
    #   Data/          -- .VDF archives (textures, meshes, scripts)
    #   _work/         -- loose Daedalus scripts + compiled output
    #   Miles/         -- runtime audio-engine dir
    #   app/           -- GOG metadata junk (stripped below)
    #   commonappdata, __redist, __support -- installer debris
    ln -s "${setupExe}" "$TMPDIR/inno/setup_gothic_2_gold_2.7_win10_(55878).exe"
    ln -s "$src"        "$TMPDIR/inno/setup_gothic_2_gold_2.7_win10_(55878)-1.bin"
    innoextract --exclude-temp -d "$TMPDIR/iss" \
      "$TMPDIR/inno/setup_gothic_2_gold_2.7_win10_(55878).exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"
    rm -rf "$out/app" "$out/tmp" "$out/__redist" "$out/__support" \
           "$out/commonappdata"

    # Strip GOG-launcher / installer side files not needed at runtime.
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.ico "$out"/*.url 2>/dev/null || true

    # Native DirectMusic DLL set for the zCMusicSys_DirectMusic::Play
    # crash fix.  Two-stage cabextract: the redist is a cabinet whose
    # `dxnt.cab` member holds the actual dm*.dll files.
    mkdir -p "$TMPDIR/dx" "$out/_strom/directmusic"
    cabextract -q -L -d "$TMPDIR/dx" -F 'dxnt.cab' ${directxFeb2010}
    ${lib.concatMapStringsSep "\n" (d: ''
      cabextract -q -L -d "$out/_strom/directmusic" -F '${d}.dll' "$TMPDIR/dx/dxnt.cab"
    '') directMusicDlls}

    # innoextract emits the system dir as "system" (lowercase); resolve
    # case-insensitively in case a future GOG build differs.
    sysdir=$(find "$out" -maxdepth 1 -iname system -type d | head -1)
    datadir=$(find "$out" -maxdepth 1 -iname data -type d | head -1)

    # Replace the GOG retail Gothic2.exe with the "report version" binary
    # from Gratt's primary patch (NoTR variant).  kirides GD3D11 hooks
    # Gothic2.exe at the fixed virtual addresses from GothicMemoryLocations
    # 2_6_fix.h; the GOG exe has different offsets, so any hook binding
    # against the GOG binary corrupts memory or faults at world entry --
    # which is the root cause of the New-Game crash.  The report-version
    # exe carries the exact VA layout GD3D11 expects.
    mkdir -p "$TMPDIR/pp"
    7z x -y -o"$TMPDIR/pp" "${primaryPatch}" 'System/Gothic2.exe' \
      >/dev/null
    cp -f "$TMPDIR/pp/System/Gothic2.exe" "$sysdir/Gothic2.exe"
    chmod u+w "$sysdir/Gothic2.exe"

    # Overlay Union 1.0m -- the engine-extension framework.  Union's
    # Shw32.dll exports InitPatch, which is the signal GD3D11 checks
    # (HookedFunctions.cpp:InitHooks) to confirm it's running on the
    # patched engine.  Union.patch contains per-version engine patches
    # for all supported Gothic builds and auto-selects at load time.
    # Shw32.dll and Vdfs32g.dll overwrite the GOG-bundled versions at
    # their exact on-disk case to avoid Wine seeing two colliding names.
    mkdir -p "$TMPDIR/union"
    7z x -y -o"$TMPDIR/union" "${union}" 'System/*' 'Data/Union.vdf' \
      >/dev/null
    cp -f "$TMPDIR/union/System/Shw32.dll"    "$sysdir/Shw32.dll"
    cp -f "$TMPDIR/union/System/Vdfs32g.dll"  "$sysdir/Vdfs32g.dll"
    cp -f "$TMPDIR/union/System/Union.patch"  "$sysdir/Union.patch"
    cp -f "$TMPDIR/union/System/msvcp100.dll" "$sysdir/msvcp100.dll"
    cp -f "$TMPDIR/union/System/msvcr100.dll" "$sysdir/msvcr100.dll"
    cp -f "$TMPDIR/union/System/stdhost.exe"  "$sysdir/stdhost.exe"
    cp -f "$TMPDIR/union/Data/Union.vdf"      "$datadir/Union.vdf"
    chmod u+w "$sysdir/Shw32.dll" "$sysdir/Vdfs32g.dll" \
              "$sysdir/Union.patch" "$sysdir/msvcp100.dll" \
              "$sysdir/msvcr100.dll" "$sysdir/stdhost.exe" \
              "$datadir/Union.vdf"

    # Overlay kirides GD3D11 v17.9.7.  The same zip used by Gothic 1:
    # the ddraw.dll loader is universal and selects GD3D11/Bin/g2a*.dll
    # automatically for Gothic2.exe.  The ddraw.dll REPLACES the GOG
    # ddraw->d3d9 wrapper; with ddraw=n,b in WINEDLLOVERRIDES Wine
    # always loads this GD3D11 ddraw first.  GD3D11 routes all rendering
    # through D3D11 -> DXVK, which fixes:
    #   - Video flicker: DXVK renders Bink/overlay frames without the
    #     DirectDraw page-flip tearing that wined3d/the old d3d9 wrapper
    #     cause on modern drivers.
    #   - New-Game crash: hooks now bind to the correct report-version VAs
    #     (replaced above), so world entry no longer faults.
    unzip -q -o "${gd3d11}" -d "$sysdir"
    chmod -R u+w "$sysdir"
    rm -f "$sysdir/COPYING" "$sysdir"/*.license.txt

    # Output-Unit library extension fix (the "no dialog / silent NPCs" bug).
    # ZenGin's dialog system loads the cutscene/output-unit library from
    # _work\DATA\scripts\content\CUTSCENE\OU.BIN (binary, BIN_SAFE archive)
    # and OU.CSL (text/ASCII archive).  OU.BIN maps each AI_Output unit name
    # to its subtitle string AND to the speech .WAV name -- so if the engine
    # can't find it, dialog lines flash by instantly with no subtitle text
    # *and* no voice (the WAV name can't be resolved either), even with
    # subTitles=1 and the Speech*.vdf present.  This GOG v2.7 build ships the
    # files with the wrong extensions -- Ou.dat / Ou.lsc instead of the
    # OU.BIN / OU.CSL the engine requests -- so dialog is dead on arrival.
    # (Verified via header: Ou.dat = "zCArchiverBinSafe BIN_SAFE",
    # Ou.lsc = "zCArchiverGeneric ASCII".)  Community-standard fix is the
    # rename; we copy rather than move so both names coexist.
    cutscenedir=$(find "$out/_work" -type d -ipath '*scripts/content/cutscene' | head -1)
    if [ -n "$cutscenedir" ]; then
      oudat=$(find "$cutscenedir" -maxdepth 1 -iname 'ou.dat' | head -1)
      oulsc=$(find "$cutscenedir" -maxdepth 1 -iname 'ou.lsc' | head -1)
      [ -n "$oudat" ] && cp -f "$oudat" "$cutscenedir/OU.BIN"
      [ -n "$oulsc" ] && cp -f "$oulsc" "$cutscenedir/OU.CSL"
      chmod u+w "$cutscenedir/OU.BIN" "$cutscenedir/OU.CSL" 2>/dev/null || true
    fi
  '';

  runtime = "proton";

  # Gothic II (ZenGin 2) writes savegames into Saves/ next to its binary,
  # NOT under drive_c/users/steamuser -- same engine-family behaviour as
  # Gothic 1.  The same FUSE case-insensitivity problem applies: the engine
  # resolves SAVES\CURRENT\ via ntdll's case-insensitive scan, which is
  # disabled on FUSE mounts without a .ciopfs marker.  Redirect Saves/ onto
  # plain btrfs via a preRun symlink, same as Gothic 1.
  saveLocations = [ ];
  executable = "system/Gothic2.exe";

  # ZenGin 2 compiled scripts -- same pattern as Gothic 1: loose files under
  # _work/DATA/scripts/_compiled read directly off the fuse-overlayfs lower
  # can intermittently fail Wine's case-insensitive open; materialising them
  # into the writable upper makes every script reliably visible.
  # _compiled holds the Daedalus .DATs (GOTHIC.DAT/MENU.DAT/OUINFO.INF/...).
  # CUTSCENE holds the renamed OU.BIN/OU.CSL output-unit library (see the
  # extension-fix in buildScript): materialise it into the writable upper so
  # the engine's uppercase OU.BIN/OU.CSL request resolves reliably even with
  # FUSE case-insensitive lookup disabled -- same rationale as _compiled.
  copyGlobs = [
    "_work/Data/Scripts/_compiled"
    "_work/Data/Scripts/CONTENT/CUTSCENE"
  ];

  # Force the native Microsoft DirectMusic DLLs and the GD3D11 ddraw loader.
  # ddraw=n,b: load the kirides GD3D11 system/ddraw.dll (overlaid at build
  # time) instead of Wine's builtin or the GOG d3d9 wrapper.  This is the
  # same approach as Gothic 1.
  env = {
    WINEDLLOVERRIDES = lib.concatStringsSep ";" (
      map (d: "${d}=n,b") (lib.filter (d: d != "dsound") directMusicDlls)
      # dsound stays builtin,native: Wine's builtin dsound bridges to the
      # host audio stack; the native XP dsound.dll only satisfies DirectMusic's
      # import.
      ++ [ "dsound=b,n" ]
      # ddraw native: load the kirides GD3D11 system/ddraw.dll loader
      # overlaid at build time.  n,b so a missing DLL still falls back to
      # builtin rather than refusing to load ddraw at all.
      ++ [ "ddraw=n,b" ]
    );
  };

  # Drop the native DirectMusic DLLs into the wineprefix and register their
  # COM CLSIDs -- identical logic to Gothic 1.  Sentinel-gated so it only
  # fires once system.reg exists (prefix must be initialised first).
  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    SYSWOW64="$PFX/drive_c/windows/syswow64"
    DM_SENTINEL="$PFX/.strom-directmusic-registered"
    WINE="${pkgs.callPackage ../../pkgs/proton.nix { }}/files/bin/wine"

    if [ -d "$SYSWOW64" ] && [ -f "$PFX/system.reg" ] \
        && [ ! -e "$DM_SENTINEL" ]; then
      echo "[strom] gothic-ii: installing native DirectMusic into wineprefix" >&2
      for f in ${lib.escapeShellArgs (map (d: "${d}.dll") directMusicDlls)}; do
        if [ -f "$GAMEDIR/_strom/directmusic/$f" ]; then
          if [ -e "$SYSWOW64/$f" ] || [ -L "$SYSWOW64/$f" ]; then
            mv -f "$SYSWOW64/$f" "$SYSWOW64/$f.builtin" 2>/dev/null || true
          fi
          cp "$GAMEDIR/_strom/directmusic/$f" "$SYSWOW64/$f"
        fi
      done

      export WINEPREFIX="$PFX"
      export WINEDEBUG=-all
      export WINEDLLOVERRIDES="${
        lib.concatStringsSep ";" (map (d: "${d}=n,b") (lib.filter (d: d != "dsound") directMusicDlls))
      }"
      for d in ${lib.escapeShellArgs (lib.filter (d: d != "dsound") directMusicDlls)}; do
        timeout 60 "$WINE" regsvr32 /s "$d.dll" >/dev/null 2>&1 \
          && echo "[strom] gothic-ii: regsvr32 $d ok" >&2 \
          || echo "[strom] gothic-ii: regsvr32 $d failed (continuing)" >&2
      done
      "$WINE"server -w 2>/dev/null || true
      touch "$DM_SENTINEL"
    fi

    # Save redirect: Saves/ off the fuse-overlayfs onto plain btrfs.
    #
    # Gothic II's ZenGin 2 writes savegames into Saves/current/ and
    # Saves/savegameN/ relative to the binary; the engine refers to them as
    # SAVES\CURRENT\ and SAVES\SAVEGAMEN\ (uppercase).  On a normal Wine
    # prefix ntdll's case-insensitive scan resolves these fine.  On a FUSE
    # mount (fuse-overlayfs), ntdll's get_dir_case_sensitivity() disables
    # the scan unless a .ciopfs marker exists -- so SAVES\CURRENT\ misses,
    # fopen returns NULL, and the engine crashes with an access violation.
    #
    # The fix: symlink game-root Saves/ to $STROM_GAMEDIR/.saves-real which
    # lives on plain btrfs (not the FUSE mount).  The symlink target is also
    # outside the prefix so saves survive prefix wipes.
    STROM_SAVES_REAL="$STROM_GAMEDIR/.saves-real"
    mkdir -p "$STROM_SAVES_REAL"
    if [ -e "$GAMEDIR/Saves" ] && [ ! -L "$GAMEDIR/Saves" ]; then
      cp -an "$GAMEDIR/Saves/." "$STROM_SAVES_REAL/" 2>/dev/null || true
      rm -rf "$GAMEDIR/Saves"
    fi
    ln -snf "$STROM_SAVES_REAL" "$GAMEDIR/Saves"
  '';

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
    description = "Gothic II: Gold Edition (Piranha Bytes 2003, GOG v2.7 win10 build 55878, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gothic-ii";
  };
}
