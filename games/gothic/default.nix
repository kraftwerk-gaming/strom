{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  innoextract,
  cabextract,
  p7zip,
}:

let
  # Microsoft DirectX End-User Runtime (February 2010 redistributable).
  # This is the exact package winetricks's `directmusic` verb pulls
  # (sha1 a97c820915dc20929e84b49646ec275760012a42); the original
  # microsoft.com download was retired, so this mirrors the MS Download
  # Center file via the Internet Archive Wayback Machine. The core
  # DirectMusic DLLs Gothic needs live in the nested `dxnt.cab` inside
  # the self-extracting outer cabinet -- cabextract reaches them in two
  # stages (SFX -> dxnt.cab -> the dm*.dll set). The June 2010 *SDK*
  # redist (used elsewhere for d3dx9_43) is a different package that
  # ships only the d3dx/xact/xinput extension DLLs and has NO
  # DirectMusic, so it cannot be reused here.
  directxFeb2010 = fetchurl {
    url = "https://web.archive.org/web/20100205120000id_/https://download.microsoft.com/download/E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe";
    hash = "sha256-9tGR6JqWPXzKNPFp0w9J6rmcHtO7ktpz7ENhfKqh6T8=";
    name = "directx_feb2010_redist.exe";
  };

  # The native DirectMusic DLL set winetricks's `directmusic` installs
  # and overrides to native. GE-Proton ships Wine's BUILTIN dmusic/
  # dmime/dmsynth, which are incomplete: Gothic's
  # zCMusicSys_DirectMusic::Play null-derefs through them and dies with
  # an access violation in the intro before the main menu. Replacing
  # them with these native Microsoft DLLs (set native via
  # WINEDLLOVERRIDES) is the community-proven fix.
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

  # The "report version" Gothic 1 engine binary. kirides GD3D11's loader
  # (Launcher/dllmain.cpp) does NOT gate on a DLL -- it fingerprints the
  # running GOTHIC.EXE by reading three DWORDs at fixed virtual addresses
  # (base 0x400000: @0x160==0x37A8D8, @0x37A960==0x7D01E4,
  # @0x37A98B==0x7D01E8). Only the community "report version" exe carries
  # those bytes; the GOG retail GOTHIC.EXE has entirely different ones, so
  # GD3D11 pops "GD3D11 Renderer doesn't work with your game version. It
  # requires report version of the game. Same as System Pack or Union."
  # and falls back to the standard renderer (which then access-violates at
  # world entry). Union/SystemPack patch the engine in memory via Shw32's
  # InitPatch, but that runs AFTER GD3D11's ddraw DllMain has already
  # fingerprinted -- too late -- and neither ships a replacement exe.
  #
  # Gratt's primary-patch .7z ships the actual report-version binary as
  # System/GothicMod.exe (it matches all three GD3D11 signatures exactly);
  # 7z unpacks it NON-INTERACTIVELY. It overwrites the GOG GOTHIC.EXE at
  # build time so the renderer recognises the engine on first load.
  primaryPatch = fetchurl {
    url = "https://raw.githubusercontent.com/Gratt-5r2/gothic-fix-archive/main/primary-patch/Primary%20patch%20Gothic%201.7z";
    hash = "sha256-zLg8UCw7miinaJWhCzXfUVqkYmezHfR4DzMT1rjpG7g=";
    name = "Primary-patch-Gothic-1.7z";
  };

  # Union 1.0m (Gratt's modern ZenGin engine-extension framework, paired
  # with the report-version exe + kirides GD3D11). Union supplies the
  # in-memory engine fixes (Union.patch) and the modern VDFS the renderer
  # expects. Sourced from Gratt's gothic-fix-archive as a plain .7z (NOT
  # an installer), so 7z unpacks it NON-INTERACTIVELY:
  #   System/Shw32.dll    -- the Union runtime (exports InitPatch; reads
  #                          Union.patch + the Autorun/ plugins at load).
  #   System/Union.patch  -- the engine binary-patch set Union applies in
  #                          memory.
  #   System/Vdfs32g.dll  -- Union's VDFS layer.
  #   System/msvcp100.dll, System/msvcr100.dll -- the VC++ 2010 runtime
  #                          Union's Shw32.dll links against.
  #   System/stdhost.exe  -- Union's launcher host.
  #   Data/Union.vdf      -- Union's script/asset bundle.
  union = fetchurl {
    url = "https://raw.githubusercontent.com/Gratt-5r2/gothic-fix-archive/main/union/Union%201.0m.7z";
    hash = "sha256-ml/f98Ho0zwOa5BRN18laaNSsarINQQLbvgct/ks8wg=";
    name = "Union-1.0m.7z";
  };

  # kirides GD3D11 v17.9.7 -- the modern, actively maintained Direct3D11
  # renderer for Gothic 1/2 (fork of ataulien's original). A drop-in
  # system/ddraw.dll loader that re-implements Gothic's zCRnd renderer on
  # D3D11 (-> DXVK). The zip unpacks AT the system/ level: the ddraw.dll
  # loader + support DLLs (AntTweakBar, assimp-vc143-mt, d3dcompiler_47,
  # GFSDK_SSAO) + a GD3D11/ data dir whose Bin/ holds the per-game
  # renderer cores (g1.dll + AVX/AVX2 variants the loader picks at
  # runtime) alongside Fonts/, Meshes/, shaders/. It compiles its HLSL on
  # first run via the bundled d3dcompiler_47 and writes GD3D11.ini + a
  # shader cache next to the binary, which land in the per-game
  # fuse-overlayfs writable upper.
  #
  # v17.x's loader gates on the engine being the Union/report version
  # (GetProcAddress(shw32.dll, "InitPatch")) and its hooks
  # (zCWorld/zCBspTree/zFILE/... at fixed virtual addresses) assume that
  # patched engine, which is why Union 1.0m is overlaid alongside it. The
  # 2015 ataulien X11 build that preceded this bound to the unpatched GOG
  # engine but crashed with a fixed-offset access violation the moment the
  # colony world loaded after New Game; Union + kirides v17.x is the
  # community-established pairing that fixes that world-entry crash.
  gd3d11 = fetchurl {
    url = "https://github.com/kirides/GD3D11/releases/download/v17.9.7/GD3D11-v17.9.7.zip";
    hash = "sha256-RMqOpZZs9eeTUlzKY4URTWcBb6+/ZrEOI8HxW4Efm9A=";
    name = "GD3D11-v17.9.7.zip";
  };

  # Gothic (Piranha Bytes 2001 action RPG). GOG offline installer,
  # build 1.08k + community hotfix (26654), the current GOG release.
  # Distributed as a single .zip wrapping the paired InnoSetup bundle
  # (setup_gothic_*.exe + setup_gothic_*-1.bin GOG-Galaxy data slob).
  # unzip unpacks the container; innoextract --gog then reassembles the
  # .exe header + .bin chunk into the install tree (binaries under
  # System/, assets under Data/, _work/).
  #
  # NOTE: hash + cid are PENDING. The archive.org `.7z` derivative item
  # (gothic-1.08k-hotfix-26654-win-gog.-7z) is corrupt -- it carries a
  # valid 7z start signature but a broken trailing end-header, so `7z l`
  # fails with "Headers Error" even at the full advertised byte count
  # (937914621 B), via both multi- and single-connection fetches. The
  # sibling `.zip` item below holds the same GOG build in a robust ZIP
  # container; seed from it, then fill hash + the real IPFS cid. The
  # exact inner exe name (System/Gothic.exe vs System/GothicStarter.exe)
  # must be confirmed against the extracted tree at seed time.
  src = fetchIpfs {
    cid = "QmPjRAE7pbQEqxSm7vtaK9ws9vQj7DWpbbEFuzRsoYjaEN";
    fallbackUrl = "https://archive.org/download/gothic-1.08k-hotfix-26654-win-gog/Gothic_1.08k_hotfix_%2826654%29_win_gog.zip";
    hash = "sha256-ZetSLW5inawyYW+LtKMplLEdV1SR4k85EV59QpRK/cA=";
    name = "gothic-1.08k-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gothic";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
    cabextract
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip" "$TMPDIR/iss"

    # Unpack the .zip container into the paired GOG installer parts
    # (setup_gothic_*.exe + setup_gothic_*-1.bin).
    unzip -q "$src" -d "$TMPDIR/zip"

    # The .zip nests the per-language GOG installers under
    # Gothic_*/{ENG,GER,POL,CZE}/; take the English pair
    # (setup_gothic_*.exe + paired -1.bin).
    eng_exe=$(find "$TMPDIR/zip" -path '*/ENG/setup_gothic_*.exe' | head -1)

    # innoextract --gog reads the .exe header + paired .bin chunk. The
    # game tree lands at the install ROOT (system/, Data/, Miles/,
    # _work/); the near-empty `app/` plus tmp/, __redist, __support,
    # commonappdata are installer-bootstrap junk.
    innoextract --gog -d "$TMPDIR/iss" "$eng_exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"
    rm -rf "$out/app" "$out/tmp" "$out/__redist" "$out/__support" \
           "$out/commonappdata"

    # Strip GOG-launcher / installer side files. The engine does not
    # query them at runtime; they only matter inside GOG Galaxy.
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.ico "$out"/*.url 2>/dev/null || true

    # Native DirectMusic DLL set for the zCMusicSys_DirectMusic::Play
    # crash fix. Two-stage cabextract: the redist is itself a cabinet
    # whose `dxnt.cab` member holds the actual dm*.dll files; -L folds
    # the names to lowercase (the cab stores mixed case). preRun drops
    # these into the wineprefix's syswow64 on first launch.
    mkdir -p "$TMPDIR/dx" "$out/_strom/directmusic"
    cabextract -q -L -d "$TMPDIR/dx" -F 'dxnt.cab' ${directxFeb2010}
    ${lib.concatMapStringsSep "\n" (d: ''
      cabextract -q -L -d "$out/_strom/directmusic" -F '${d}.dll' "$TMPDIR/dx/dxnt.cab"
    '') directMusicDlls}

    # innoextract emits the system + Data dirs lowercase ("system",
    # "data"); resolve them case-insensitively in case a future GOG build
    # differs.
    sysdir=$(find "$out" -maxdepth 1 -iname system -type d | head -1)
    datadir=$(find "$out" -maxdepth 1 -iname data -type d | head -1)

    # Replace the GOG retail GOTHIC.EXE with the report-version
    # GothicMod.exe from Gratt's primary-patch -- the only Gothic 1 binary
    # whose fixed-offset signature kirides GD3D11 recognises. Overwrite at
    # the GOG file's exact on-disk case (GOTHIC.EXE) so Wine loads it and
    # so the executable= path stays valid.
    mkdir -p "$TMPDIR/pp"
    7z x -y -o"$TMPDIR/pp" "${primaryPatch}" 'System/GothicMod.exe' \
      >/dev/null
    cp -f "$TMPDIR/pp/System/GothicMod.exe" "$sysdir/GOTHIC.EXE"
    chmod u+w "$sysdir/GOTHIC.EXE"

    # Overlay Union 1.0m -- the engine-extension framework that turns the
    # retail exe into the "report version" kirides GD3D11 binds to. 7z
    # unpacks the plain .7z non-interactively. Union's Shw32.dll (the
    # UnionCore runtime that exports InitPatch), Vdfs32g.dll, Union.patch
    # and the VC++ 2010 runtime it links against drop into system/;
    # Union.vdf drops into Data/.
    #
    # Shw32.dll and Vdfs32g.dll must overwrite the GOG files at their
    # EXACT on-disk case (SHW32.DLL uppercase, Vdfs32g.dll mixed) --
    # writing a differently-cased name alongside the original would leave
    # two files that collide on Wine's case-insensitive view, and Wine
    # could load the wrong (original) one, defeating the patch. The
    # remaining members (Union.patch, msvcp100/msvcr100.dll, stdhost.exe,
    # Union.vdf) are new files. Union's BinkMss/ DLLs are intentionally
    # left out -- the GOG-bundled Bink/MSS pair already works and the
    # native-DirectMusic audio path depends on it.
    mkdir -p "$TMPDIR/union"
    7z x -y -o"$TMPDIR/union" "${union}" 'System/*' 'Data/Union.vdf' \
      >/dev/null
    cp -f "$TMPDIR/union/System/Shw32.dll"    "$sysdir/SHW32.DLL"
    cp -f "$TMPDIR/union/System/Vdfs32g.dll"  "$sysdir/Vdfs32g.dll"
    cp -f "$TMPDIR/union/System/Union.patch"  "$sysdir/Union.patch"
    cp -f "$TMPDIR/union/System/msvcp100.dll" "$sysdir/msvcp100.dll"
    cp -f "$TMPDIR/union/System/msvcr100.dll" "$sysdir/msvcr100.dll"
    cp -f "$TMPDIR/union/System/stdhost.exe"  "$sysdir/stdhost.exe"
    cp -f "$TMPDIR/union/Data/Union.vdf"      "$datadir/Union.vdf"
    chmod u+w "$sysdir/SHW32.DLL" "$sysdir/Vdfs32g.dll" \
              "$sysdir/Union.patch" "$sysdir/msvcp100.dll" \
              "$sysdir/msvcr100.dll" "$sysdir/stdhost.exe" \
              "$datadir/Union.vdf"

    # Overlay the kirides GD3D11 v17.9.7 Direct3D11 renderer onto system/.
    # The zip's contents (ddraw.dll loader, support DLLs, GD3D11/ data
    # dir with Bin/g1*.dll renderer cores + shaders) unpack directly INTO
    # system/, so its ddraw.dll REPLACES the GOG ddraw->d3d9 wrapper while
    # the engine's ddraw=n,b override keeps loading "the" system/ddraw.dll
    # -- now GD3D11.
    unzip -q -o "${gd3d11}" -d "$sysdir"
    chmod -R u+w "$sysdir"
    # COPYING / license text are not runtime files.
    rm -f "$sysdir/COPYING" "$sysdir"/*.license.txt
  '';

  runtime = "proton";

  # The classic 2001 engine writes savegames into a Saves/ tree next to its
  # binary (Saves/current/, Saves/savegameN/) plus System/Gothic.ini, NOT
  # under drive_c/users/steamuser/... -- the modern AppData/LocalLow
  # "Gothic 1" path belongs to the 2023 remake, a different engine. So the
  # generic saveLocations relocation (which only ever pulls dirs out of
  # drive_c/users/steamuser/) does not apply; the redirect that actually
  # matters is done in preRun, where the game-root Saves/ is symlinked onto
  # plain btrfs (the bind-mounted $STROM_GAMEDIR) to escape the FUSE mount's
  # disabled case-insensitive lookup -- see the preRun "save redirect"
  # comment. That symlink also makes saves persist across prefix wipes.
  saveLocations = [ ];
  executable = "system/GOTHIC.EXE";

  # The engine's VDFS layer loads the compiled Daedalus scripts as loose
  # files (none are inside a .VDF). Read straight off the read-only
  # fuse-overlayfs lower, MUSIC.DAT intermittently fails Wine's
  # case-insensitive open ("B: VFILE: Err: -2: Can't find file:
  # _WORK\DATA\SCRIPTS\_COMPILED\MUSIC.DAT") even though it is present and
  # its siblings (GOTHIC.DAT, MENU.DAT) resolve. Materializing the
  # _compiled dir into the writable upper makes every script reliably
  # visible — the same copy-up workaround mkGame documents for files
  # Wine/Proton can't read cleanly from the overlay lower.
  copyGlobs = [ "_work/DATA/scripts/_compiled" ];

  # Force the native Microsoft DirectMusic/DirectShow DLLs (dropped into
  # syswow64 by preRun) to load instead of GE-Proton's incomplete Wine
  # builtins. Without `native`, Wine keeps its builtin dmusic/dmime/
  # dmsynth and Gothic null-derefs through zCMusicSys_DirectMusic::Play.
  env = {
    WINEDLLOVERRIDES = lib.concatStringsSep ";" (
      map (d: "${d}=n,b") (lib.filter (d: d != "dsound") directMusicDlls)
      # dsound stays builtin,native: Wine's builtin dsound is the
      # functional one (it bridges to the host audio stack); the native
      # XP dsound.dll exists only to satisfy DirectMusic's import.
      ++ [ "dsound=b,n" ]
      # ddraw native: load the kirides GD3D11 system/ddraw.dll loader
      # overlaid at build time -- the community Direct3D11 renderer that
      # replaces Gothic's DirectDraw7 path entirely. Wine's BUILTIN ddraw
      # routes the D3D7 calls through wined3d->OpenGL and faults the moment
      # world rendering starts; the GOG-bundled ddraw->d3d9 wrapper renders
      # the main menu but then access-violates at a fixed offset when the
      # colony world loads after New Game. GD3D11 v17.x (atop the
      # Union report-version engine, overlaid alongside) re-implements the
      # renderer on D3D11 (-> DXVK) and handles the full world; it compiles
      # its HLSL at runtime via the bundled d3dcompiler_47 and caches the
      # result in the overlay upper. `n,b` so a missing DLL still falls
      # back to builtin rather than failing to load ddraw at all.
      ++ [ "ddraw=n,b" ]
    );
  };

  # Drop the native DirectMusic DLLs into the wineprefix and register
  # their COM CLSIDs. dmusic/dmime/dmsynth/dmloader/dmscript/dmstyle/
  # dmband/dmcompos/dswave/devenum/quartz all export DllRegisterServer
  # and Gothic CoCreateInstance's them by CLSID at intro time; a bare
  # copy + native override is not enough -- the CLSID -> InprocServer32
  # registrations must exist or zCMusicSys_DirectMusic::Play hits a
  # null interface and access-violates.
  #
  # preRun runs inside the bwrap FHS (proton's 32-bit wine resolves its
  # /lib/ld-linux.so.2 via /usr/lib32 here), but BEFORE proton has
  # created the prefix on a clean install, so this is sentinel-gated and
  # only fires once $PFX/system.reg exists. On a first launch against an
  # uninitialised prefix the seed is skipped; the autoWipePrefix/normal
  # relaunch path lands it on the next run. regsvr32 is driven through
  # proton's own wine (PROTON's runtime), which is the only Wine that
  # works correctly against this prefix.
  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    SYSWOW64="$PFX/drive_c/windows/syswow64"
    DM_SENTINEL="$PFX/.strom-directmusic-registered"
    WINE="${pkgs.callPackage ../../pkgs/proton.nix { }}/files/bin/wine"

    if [ -d "$SYSWOW64" ] && [ -f "$PFX/system.reg" ] \
        && [ ! -e "$DM_SENTINEL" ]; then
      echo "[strom] gothic: installing native DirectMusic into wineprefix" >&2
      for f in ${lib.escapeShellArgs (map (d: "${d}.dll") directMusicDlls)}; do
        if [ -f "$GAMEDIR/_strom/directmusic/$f" ]; then
          # Move Wine's builtin aside (recoverable), then drop the native
          # Microsoft DLL in its place.
          if [ -e "$SYSWOW64/$f" ] || [ -L "$SYSWOW64/$f" ]; then
            mv -f "$SYSWOW64/$f" "$SYSWOW64/$f.builtin" 2>/dev/null || true
          fi
          cp "$GAMEDIR/_strom/directmusic/$f" "$SYSWOW64/$f"
        fi
      done

      # Register the COM servers via proton's wine. WINEPREFIX points at
      # the live prefix; the native override ensures regsvr32 calls the
      # native DllRegisterServer (not the builtin stub). dsound has no
      # DllRegisterServer export, so it is not registered (left builtin).
      export WINEPREFIX="$PFX"
      export WINEDEBUG=-all
      export WINEDLLOVERRIDES="${
        lib.concatStringsSep ";" (map (d: "${d}=n,b") (lib.filter (d: d != "dsound") directMusicDlls))
      }"
      for d in ${lib.escapeShellArgs (lib.filter (d: d != "dsound") directMusicDlls)}; do
        timeout 60 "$WINE" regsvr32 /s "$d.dll" >/dev/null 2>&1 \
          && echo "[strom] gothic: regsvr32 $d ok" >&2 \
          || echo "[strom] gothic: regsvr32 $d failed (continuing)" >&2
      done
      "$WINE"server -w 2>/dev/null || true
      touch "$DM_SENTINEL"
    fi

    # Save redirect: take the game-root Saves/ tree OFF the fuse-overlayfs
    # mount and onto plain btrfs so the engine can actually write savegames.
    #
    # Gothic writes savegames into the Saves/ tree next to its binary
    # (Saves/current/, Saves/savegameN/) and refers to those paths
    # uppercased -- it resolves the save dir as `SAVES\CURRENT\` and the
    # menu enumerates `SAVES\SAVEGAMEN\` while the names it creates on disk
    # are `Saves/current` / `Saves/savegameN`. On a normal Wine prefix this
    # is fine: Wine falls back to a case-insensitive directory scan. But
    # that fallback is GATED -- ntdll's get_dir_case_sensitivity(), for a
    # FUSE mount (FUSE_SUPER_MAGIC, which our fuse-overlayfs is), enables
    # the scan only when a `.ciopfs` marker exists in that dir; otherwise it
    # DISABLES the case-insensitive search. With the Saves/ tree on the
    # overlay the engine's `SAVES\CURRENT\` then misses, the save fopen
    # returns NULL, and zFILE_FILE::Write null-derefs (access violation in
    # Zdisk.cpp the instant you save). Even after the AV was suppressed by
    # seeding `.ciopfs`, the engine still wrote NOTHING into the slot dirs:
    # the ZenGin save path rmdir+mkdir's each slot, which fuse-overlayfs
    # realises as a fresh opaque upper dir, so any in-overlay state was
    # repeatedly wiped.
    #
    # The clean fix is to keep Saves/ off the overlay entirely. $STROM_GAMEDIR
    # (the overlay's writable upper) is ALSO bind-mounted into the sandbox at
    # its own path as plain btrfs, separate from the merged FUSE mount at
    # $GAMEDIR. We make a real save dir there ($STROM_GAMEDIR/.saves-real) and
    # symlink the game-root Saves/ to it. When the engine opens
    # `Saves\current\...` (cwd = the FUSE $GAMEDIR), Wine follows the symlink
    # to the btrfs target, which is NOT under the FUSE mount -- so
    # get_dir_case_sensitivity sees btrfs, keeps Wine's case-insensitive scan
    # on, the mixed-case fopen resolves, and the save completes. Because the
    # target lives in $STROM_GAMEDIR it also persists across prefix wipes,
    # exactly like saveLocations does for drive_c saves.
    STROM_SAVES_REAL="$STROM_GAMEDIR/.saves-real"
    mkdir -p "$STROM_SAVES_REAL"
    # Replace any stale on-overlay Saves/ (real dir from an older build, or a
    # symlink pointing elsewhere) with the symlink to btrfs. A pre-existing
    # real dir would otherwise keep the engine on the FUSE path.
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
    description = "Gothic (Piranha Bytes 2001, GOG 1.08k, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gothic";
  };
}
