{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
  python3,
  binutils,
}:

let
  # archive.org "call-of-cthulhu-dark-corners-of-the-earth_202604" ships
  # the GOG v1.0(a) build (33564): a single RAR5 wrapping the InnoSetup
  # installer. The 2005/2006 Headfirst Productions horror title runs on
  # a modified Halo Blam! engine. Engine/ already ships d3dx9_28.dll +
  # fmodex.dll + gdiplus.dll so no DirectX redist is required.
  src = fetchIpfs {
    cid = "QmXshetsRsiSbvd42xRZfb26ojv7kkkKKxP11o84Rd3cm1";
    fallbackUrl = "https://archive.org/download/call-of-cthulhu-dark-corners-of-the-earth_202604/Call%20of%20Cthulhu%20-%20Dark%20Corners%20of%20the%20Earth.rar";
    hash = "sha256-lZc+/3JoC/nKCq52ryWSqnt0a9Cfm9lePApdI6quKog=";
    name = "call-of-cthulhu-dark-corners-of-the-earth.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "call-of-cthulhu-dark-corners-of-the-earth";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
    python3
    binutils
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rar/setup_call_of_cthulhu_dark_corners_of_the_earth_1.0(a)_(33564).exe"
    cp -r "$TMPDIR/iss"/* "$out/"
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata" "$out/app" \
      "$out/Installers" "$out/_nvi"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
      "$out/goggame-"*.script "$out/goggame-"*.ico

    # HfeDirect3DDevice opens `cards.dat` relative to the runtime cwd,
    # which under our fuse-overlay setup is the overlay root, not the
    # `Engine/` subdir where the GOG bundle ships it. Without a
    # top-level copy the per-vendor caps table stays NULL and the
    # caller at VA 0x00425053 null-derefs. Drop a patched copy at the
    # data root with an ATI catch-all so any RADV-reported device id
    # (incl. modern RDNA 0x1114) resolves to the RADEON X-series
    # profile rather than the unsupported Mach/Rage 0x4xxx entries
    # that dominate the 0x1002 block. cards.dat is CRLF.
    install -m644 "$out/Engine/cards.dat" "$out/cards.dat"
    chmod u+w "$out/cards.dat"
    {
      printf '\r\n'
      printf '///////////////////////////////////////////////////\r\n'
      printf '//\r\n'
      printf '// Modern AMD (post-2010 RDNA / GCN) — catch-all\r\n'
      printf '//\r\n'
      printf '//////////////////////////////////////////////////\r\n'
      printf '\r\n'
      printf 'DisplayVendor = 0x1002  "ATI"\r\n'
      printf '0x1114 = "RADEON RDNA (RADV)"\r\n'
      printf 'Unknown = "Unknown"\r\n'
      printf '    //UseAnisotropicFilter\r\n'
      printf '    break\r\n'
    } >> "$out/cards.dat"

    # Blanket case-insensitive view over the install. The engine
    # opens files through wine's CreateFileW under CWD-relative paths,
    # and wine's case-insensitive name search is disabled on Z: drives
    # (``warn:file:lookup_unix_name Disabling case insensitive
    # search``). Engine strings reference path components in mixed
    # case (``MainMenu\\EngagingScreens\\%s`` vs disk
    # ``MainMenu/ENGAGINGSCREENS``, ``Resources\\Pc\\Shaders\\`` vs
    # disk ``Resources/PC/SHADERS``, ``..\\Pc Sound\\xact\\`` vs disk
    # ``"Pc Sound"/XACT``). The disk has UPPER-, lower-, and Mixed-case
    # dirs side-by-side. One blanket lowercase-symlink walk at every
    # path level handles the open-side; the helper also harvests every
    # path-component spelling from the exe .rdata strings table and
    # drops symlinks for each on-disk-mismatched variant.
    python3 ${./case-symlinks.py} "$out" "$out/Engine/CoCMainWin32.exe"

    # One RE byte-patch in patch-handle-table-null.py:
    #
    #   round-14: DirectShow filter-graph wrapper destructor at
    #     VA 0x0056c3c9 — NULL-guard the inner-ptr vtable load. The
    #     engine tries to build a DirectShow graph for the intro FMV
    #     and Wine's quartz cannot find ir50_32.dll / msrle32.dll /
    #     msvidc32.dll / iccvid.dll. The half-built wrapper's
    #     destructor then loads [edi+0] (=NULL) and faults at
    #     mov ecx, [eax]. Patch skips the Release call when the inner
    #     ptr is NULL and falls into the existing free path.
    #
    # The trampoline lives in the .text trailing zero pad at
    # VA 0x6274e9 (no new sections, no relocation).
    #
    # Confirmed load-bearing by round-15 ablation: dropping this patch
    # while keeping the case+cwd fix reproduces the original crash
    # (``wine: Unhandled page fault on read access to 00000000 at
    # address 0056C3C9``) within 75s of smoke test.
    chmod u+w "$out/Engine/CoCMainWin32.exe"
    python3 ${./patch-handle-table-null.py} \
      "$out/Engine/CoCMainWin32.exe" \
      "$out/Engine/CoCMainWin32.exe.patched"
    mv "$out/Engine/CoCMainWin32.exe.patched" "$out/Engine/CoCMainWin32.exe"
  '';

  runtime = "proton";
  # Primary FileTask per goggame-1189711155.info. Wine sets cwd to the
  # exe's directory, which matches GOG's workingDir = "Engine".
  executable = "Engine/CoCMainWin32.exe";

  # DCotE writes config + saves under My Documents in the wineprefix.
  saveLocations = [ "Documents/Cthulhu" ];

  # CoCMainWin32.exe checks
  # HKCU\Software\Bethesda Softworks\Call Of Cthulhu DCoTE\Settings\
  # on startup. When missing it spawns CoCDCoTELauncher.exe (settings-
  # only dialog that writes those keys then exits without starting
  # the game). Under Proton's waitforexitandrun the wineprefix tears
  # down after that exit, which the user sees as "press Launch, game
  # quits". Seed 1920x1080 fullscreen defaults so the game bypasses
  # the launcher; the in-game options menu rewrites these keys for
  # subsequent runs.
  preRun = ''
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    if [ -f "$USERREG" ]; then
      sh ${./seed-settings.sh} "$USERREG"
    fi

    # The engine chdir's to the game root (``Z:\\…\\overlay\\``) early
    # in init and then calls ``CreateFileW(L"..\\Fonts\\Subtitles.abc")``
    # — wine resolves that one level UP from cwd, i.e. into
    # ``$STROM_CACHEDIR\\Fonts\\…`` instead of
    # ``$STROM_CACHEDIR\\overlay\\Fonts\\…``. Plant per-top-level-dir
    # symlinks in ``$STROM_CACHEDIR`` (parent of ``overlay/``) pointing
    # back into the overlay so ``..\\Foo`` resolves to ``overlay\\Foo``.
    for d in "$STROM_OVERLAY"/*/; do
      base=$(basename "$d")
      ln -sfn "$STROM_OVERLAY/$base" "$STROM_CACHEDIR/$base"
    done
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

  env = {
    # The Halo Blam! engine couples gameplay timers to the present
    # rate. The GOG build ships sucklead's "Fix FPS to 60" exe patch
    # baked in (mov [0x6c7fe0],edi at file_off 0x638D), so the
    # internal frame counter is capped — but DXVK's
    # vkQueuePresentKHR clock is independent and runs uncapped,
    # which the community converged on as the canonical cause of
    # the immediate-after-splash crash (ValveSoftware/Proton#3303).
    DXVK_FRAME_RATE = "60";
  };

  meta = {
    description = "Call of Cthulhu: Dark Corners of the Earth (Headfirst Productions / Bethesda 2005, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "call-of-cthulhu-dark-corners-of-the-earth";
  };
}
