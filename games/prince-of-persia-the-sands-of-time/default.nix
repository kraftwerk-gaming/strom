{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  # GOG DRM-free release of Prince of Persia: The Sands of Time
  # (v181 / installer v2.0.0.4). We package the GOG edition rather than
  # the retail SafeDisc CD rip because every working ProtonDB report
  # (app 13600, 59 reports, Platinum, across Proton 7 -> 10) runs the
  # Steam/GOG DRM-free build; the retail CD edition's launcher +
  # SafeDisc/CD-check architecture is the one that wedges before the
  # menu under Proton. The GOG installer is a plain Inno Setup exe
  # (innoextract-clean); its `app/` tree is the complete install:
  # POP.EXE (GOG's DRM-free binary), PrinceOfPersia.EXE (the launcher
  # that runs hardware detection, writes Hardware.ini, CreateProcess's
  # POP.EXE and WaitForSingleObject's it), plus prince.bf, POPData.BF,
  # Sound/, Video/ and the engine DLLs. Unlike the retail launcher,
  # GOG's launcher WAITS for POP.EXE, so Proton's `waitforexitandrun`
  # follows the game correctly and no byte-patching is needed.
  src = fetchIpfs {
    cid = "QmbpUvgkJcw9QfyKjxvP3msV7ktH33VtpBsJftkL2wKMXB";
    fallbackUrl = "";
    hash = "sha256-BEzl9aH7mnJ9G8YhRgo5FqXatODFRMpY0wRcngt/ggM=";
    name = "pop-sot-gog-setup.exe";
  };

  # Sands of Time Fix Compilation (vini1264, ModDB), the community
  # all-in-one that makes SoT work on modern systems. We consume its
  # English payload at build time:
  #   - DxWrapper (elishacloud) as d3d9.dll: converts the engine's
  #     D3D9 device to D3D9Ex and forces FullscreenWindowMode, so the
  #     engine never issues the exclusive-fullscreen modeswitch that
  #     wedges forever under gamescope's nested Xwayland (DXVK builds
  #     the swapchain but the engine's exclusive-FS present never
  #     lands). 9Ex flip-model windowed present composites cleanly.
  #   - Ultimate ASI Loader (ThirteenAG) shipped AS BinkW32.DLL (the
  #     engine's own Bink import, so it loads at startup); GOG's real
  #     Bink is preserved as BinkW32Hooked.DLL. UAL loads
  #     scripts/pop1w.asi (Nemesis2000 widescreen fix).
  #   - DSOAL (dsound.dll + dsoal-aldrv.dll + hrtf/) restores EAX.
  #   - Xidi (dinput8.dll + Xidi.32.dll + SDL plugin) for controllers.
  fixSrc = fetchIpfs {
    cid = "QmUceUiz7bM8dsquB2fL2uvzTLK5tSWgP4NTmbjg2vp93U";
    fallbackUrl = "https://www.moddb.com/games/prince-of-persia-the-sands-of-time/downloads/sands-of-time-fix-compilation";
    hash = "sha256-sxibiezIIcAGSusVZh1rWxfEDZp91GLEWqOG0Lkw99Y=";
    name = "PoP_FixCompilation.22.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prince-of-persia-the-sands-of-time";

  inherit src;

  # Pin both the GOG installer and the Fix Compilation zip (default is
  # just [ src ]; fixSrc is a separate fetchIpfs the build consumes).
  ipfsSources = [
    src
    fixSrc
  ];

  nativeBuildInputs = [
    unzip
    innoextract
    pkgs.python3
  ];

  buildScript = ''
        mkdir -p "$out"
        # The GOG installer is a single Inno Setup exe; innoextract pulls
        # the complete game tree out of its `app/` directory. No CD image,
        # no InstallShield cabs, no byte-patching: GOG's POP.EXE is
        # already DRM-free and is launched by its own PrinceOfPersia.EXE.
        innoextract -e -s -d "$TMPDIR/gog" "$src"
        cp -r "$TMPDIR/gog/app/." "$out/"
        chmod -R u+rwX "$out"

        # Large Address Aware on POP.EXE (PE Characteristics bit 0x0020):
        # gives the 32-bit engine a 4 GiB address space so the engine +
        # DxWrapper (8 MiB) + DXVK don't crowd the default 2 GiB user VA.
        # The GOG/Steam ecosystem applies this via the launcher; we bake
        # it. This is the ONLY modification to POP.EXE (no DRM patching:
        # GOG's binary is already clean, and PrinceOfPersia.EXE creates
        # the POP_Launcher mutex the engine's anti-direct-launch check
        # looks for).
        ${pkgs.python3}/bin/python3 -c "$(cat <<'PYEOF'
    import struct, sys
    p = sys.argv[1]
    with open(p, "rb") as f:
        data = bytearray(f.read())
    e_lfanew = struct.unpack_from("<I", data, 0x3c)[0]
    assert data[e_lfanew : e_lfanew + 4] == b"PE\x00\x00", "bad PE sig"
    ch_off = e_lfanew + 4 + 18
    ch = struct.unpack_from("<H", data, ch_off)[0]
    struct.pack_into("<H", data, ch_off, ch | 0x0020)
    with open(p, "wb") as f:
        f.write(data)
    PYEOF
        )" "$out/POP.EXE"

        # ---- Sands of Time Fix Compilation (English payload) ----
        # See the fixSrc let-binding above for the rationale behind each
        # component. Baked into the read-only store output so wine's DLL
        # resolution is deterministic (dropping these into the writable
        # fuse-overlay upper alone made load order race).
        unzip -q -o "${fixSrc}" 'English/*' -d "$TMPDIR/fix"
        fix="$TMPDIR/fix/English"
        # DxWrapper as d3d9.dll: D3D9 -> D3D9Ex + FullscreenWindowMode.
        # Its ini must be named after the dll (d3d9.ini).
        cp "$fix/scripts/dxwrapper.asi" "$out/d3d9.dll"
        # Ultimate ASI Loader shipped AS BinkW32.DLL (loads at startup via
        # the engine's own Bink import). Preserve GOG's real Bink as
        # BinkW32Hooked.DLL (UAL forwards to it). We do NOT place
        # dxwrapper.asi in scripts/ - d3d9.dll already wraps d3d9.
        mv "$out/BinkW32.DLL" "$out/BinkW32Hooked.DLL"
        install -Dm644 "$fix/BinkW32.DLL"        "$out/BinkW32.DLL"
        install -Dm644 "$fix/scripts/pop1w.asi"  "$out/scripts/pop1w.asi"
        # Nemesis2000 widescreen fix (pop1w.asi) reads scripts/pop.ini for
        # the render resolution + HUD placement. It MUST match the actual
        # display (gamescope nested = 1920x1080 below); the fix's stock
        # pop.ini is 1280x720, which mispositions the 16:9 HUD/menu inside
        # a differently-sized framebuffer and clips text off the right
        # edge. Generate a 1920x1080 pop.ini so render res, HUD placement
        # and the gamescope surface all agree (Hor+ widescreen, no
        # pillarbox). HUD_posX_auto=1 lets the fix compute HUD offset for
        # the 16:9 aspect.
        printf '%s\n' \
          '[MAIN]' \
          'Width = 1920' \
          'Height = 1080' \
          '[HUD]' \
          'HUD_posX_auto = 1' \
          'HUD_posX = -0.148958' \
          '[MISC]' \
          'cutscenes_black_borders = 0' \
          'Xbox_fov = 0' \
          'fov_multiplier = 1.0' \
          > "$out/scripts/pop.ini"
        # DSOAL (EAX/HRTF audio restore) + Xidi (controller support).
        install -Dm644 "$fix/dsound.dll"             "$out/dsound.dll"
        install -Dm644 "$fix/dsoal-aldrv.dll"        "$out/dsoal-aldrv.dll"
        install -Dm644 "$fix/alsoft.ini"             "$out/alsoft.ini"
        cp -r "$fix/hrtf" "$out/hrtf"
        install -Dm644 "$fix/dinput8.dll"            "$out/dinput8.dll"
        install -Dm644 "$fix/Xidi.32.dll"            "$out/Xidi.32.dll"
        install -Dm644 "$fix/Xidi.ini"               "$out/Xidi.ini"
        install -Dm644 "$fix/SDL.XidiPlugin.32.dll"  "$out/SDL.XidiPlugin.32.dll"
        # Profiles: GOG ships only SafeProfile.DAT and no default profile,
        # so on first run POP.EXE tries to CREATE a profile
        # (Profiles\<name>\Profile.DAT). Creating that new file/subdir
        # over the fuse-overlayfs merged mount fails (wine resolves the
        # engine's "Profiles\.\Profile.DAT" path with a `.` component to
        # c0000034), and the engine shows "Unable to create profile" and
        # never leaves the profile prompt. The Fix Compilation ships a
        # ready DefaultProfile.DAT (a proper default-profile pointer, NOT
        # a SafeProfile clone) plus a pre-made "Prince" profile subdir;
        # dropping those in means POP.EXE loads an existing profile and
        # boots straight into the main menu without creating one. Profiles
        # is also in copyGlobs so the dir stays writable in the overlay
        # upper for in-game saves.
        cp -r "$fix/Profiles/." "$out/Profiles/"
        # DxWrapper config (named d3d9.ini to match the dll). The
        # load-bearing lines are D3d9to9Ex + FullscreenWindowMode: they
        # make the engine present a D3D9Ex flip-model WINDOWED swapchain
        # instead of the exclusive-fullscreen device that wedges under
        # gamescope's nested Xwayland. HandleExceptions +
        # FixPerfCounterUptime harden fast-CPU startup timing. We do NOT
        # set SingleProcAffinity: pinning one core deadlocks the engine's
        # own post-init spin-wait. printf, not a heredoc: the buildScript
        # runs inside a doubly quoted nix string that strips leading
        # whitespace.
        printf '%s\n' \
          '[General]' \
          'DisableLogging       = 1' \
          '[Compatibility]' \
          'D3d9to9Ex            = 1' \
          'EnableD3d9Wrapper    = 1' \
          'FixPerfCounterUptime = 1' \
          'HandleExceptions     = 1' \
          'SingleProcAffinity   = 0' \
          '[d3d9]' \
          'AnisotropicFiltering = 16' \
          'EnableVSync          = 0' \
          'ForceVsyncMode       = 0' \
          'LimitPerFrameFPS     = 60' \
          'EnableWindowMode     = 0' \
          'FullscreenWindowMode = 1' \
          'GraphicsHybridAdapter = 1' \
          > "$out/d3d9.ini"
        chmod -R u+rwX "$out"
  '';

  runtime = "proton";
  # GOG's PrinceOfPersia.EXE is the entry point: it runs hardware
  # detection (directx9tests.dll), writes Hardware.ini, creates the
  # POP_Launcher mutex, CreateProcess's POP.EXE and WaitForSingleObject's
  # it. Because it WAITS for POP.EXE (unlike the old retail launcher),
  # Proton's `waitforexitandrun` tracks the launcher and stays up for the
  # whole session. POP.EXE's anti-direct-launch mutex check is satisfied
  # by the launcher, so no byte-patching is required.
  executable = "PrinceOfPersia.EXE";

  # POP.EXE writes all user state (Profiles/*.DAT save profiles,
  # POP.LOG, POPError.DAT, PrinceSM sentinel) into its own CWD, the
  # install dir, which persists via the per-game fuse-overlayfs
  # upper, not the wineprefix. Nothing lands under
  # drive_c/users/steamuser/, so a prefix wipe can't lose progress.
  saveLocations = [ ];

  # Materialize the fix DLLs into the fuse-overlayfs upper before the
  # merge mount. Wine's module loader resolves an app-local d3d9.dll
  # (DxWrapper) over proton's builtin DXVK only when the file is
  # actually present in the upper; a lower-only file surfaced through
  # the merged view is resolved inconsistently (documented in
  # games/company-of-heroes: "merged view of lower-only files behaves
  # oddly"). The engine's BinkW32.DLL/dinput8/dsound imports resolve
  # the same way, so surface every injected DLL + its config.
  copyGlobs = [
    "d3d9.dll"
    "d3d9.ini"
    "BinkW32.DLL"
    "BinkW32Hooked.DLL"
    "dsound.dll"
    "dsoal-aldrv.dll"
    "dinput8.dll"
    "Xidi.32.dll"
    "SDL.XidiPlugin.32.dll"
    "scripts"
    "Profiles"
  ];

  # Remove the PrinceSM crash sentinel before each launch. POP.EXE
  # touches this empty file at startup and unlinks it on clean
  # shutdown; any non-clean termination (SIGKILL from the wrapper's
  # gamescope tear-down, alt-F4 mid-cutscene, OOM, ...) leaves it
  # behind, and the next launch then shows a "Last execution
  # crashed: do you want to load the safe mode profile?" MessageBoxA.
  # Runs in bwrap.extraPreHook (host-side, real upper $STROM_GAMEDIR):
  # a preRun unlink through the fuse-overlayfs merged mount returns
  # EXDEV and aborts the launch under set -euo pipefail.
  bwrap.extraPreHook = ''
    rm -f "$STROM_GAMEDIR/PrinceSM"
  '';

  # With the Nemesis2000 widescreen fix (scripts/pop1w.asi + pop.ini)
  # the engine renders true 16:9, so run the nested area at the full
  # 1920x1080 output (1:1, no pillarbox, no upscale). This MUST match
  # pop.ini's Width/Height (1920x1080) or the widescreen fix mispositions
  # the HUD/menu and clips text off the right edge.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # NOTE: do NOT add `-f` / `--fullscreen` / `-b` / `--borderless`
      # here - those flags reach the OUTER gamescope and would grab the
      # host display. Adjust nested-width/nested-height instead.
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Load the Fix Compilation's native DLLs (baked into the store
    # output) instead of proton's builtins:
    #   d3d9    -> DxWrapper (D3D9->D3D9Ex + FullscreenWindowMode)
    #   binkw32 -> Ultimate ASI Loader (loads scripts/pop1w.asi)
    #   dsound  -> DSOAL (EAX/HRTF audio)
    #   dinput8 -> Xidi (controller support)
    # "n,b" = native first, builtin fallback.
    WINEDLLOVERRIDES = "d3d9,binkw32,dsound,dinput8=n,b";
  };

  meta = {
    description = "Prince of Persia: The Sands of Time (Ubisoft Montreal, 2003; GOG DRM-free, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prince-of-persia-the-sands-of-time";
  };
}
