{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # GOG DRM-free release of Prince of Persia: The Two Thrones
  # (v1.1 / installer v2.0.0.5, single-file Inno Setup). We package the
  # GOG edition, not the retail StarForce 3 CD, for the same reason as
  # the other two trilogy entries: the retail DRM does not work on
  # modern Windows or under Proton, whereas GOG's DRM-free build runs.
  # GOG's game binary is a UPX-packed `pop3.exe` launched by
  # PrinceOfPersia.exe (hardware detection + config). The engine issues
  # the same exclusive-fullscreen modeswitch that wedges forever under
  # gamescope's nested Xwayland, so we layer the community Fix
  # Compilation on top (see fixSrc).
  src = fetchIpfs {
    cid = "QmaoRhfy7NH2AKQshQCFmEkZJsdvrxuPwhhK8X7WttwudT";
    fallbackUrl = "";
    hash = "sha256-DNPGArFiy2e8OpMY8pebDBH4wesR6+J7do92c1Mo/8E=";
    name = "pop-ttt-gog-setup.exe";
  };

  # Two Thrones - Ultimate Fix Compilation (vini1264, ModDB), the
  # community all-in-one that makes TT run on modern systems. Its
  # `Main Patch/` folder is a drop-in overlay we lay on the GOG install:
  #   - POP3.EXE: the UPX-DECOMPRESSED game binary (6,336,512 bytes),
  #     the size Nemesis2000's widescreen fix expects. Replaces GOG's
  #     packed pop3.exe. A POP3_mousefix.EXE variant (Dawid Freeman's
  #     mouse fix + Middle Tower springboard fix) ships alongside;
  #     selectable via mousefix.json when using the Mini-Launcher, or by
  #     overriding `executable`.
  #   - scripts/dxwrapper.asi (elishacloud DxWrapper), loaded as an ASI
  #     plugin by the Ultimate ASI Loader (shipped AS BinkW32.DLL). It
  #     wraps the D3D9 device to D3D9Ex (D3d9to9Ex) so the engine's
  #     exclusive-fullscreen present never lands (which wedges under
  #     gamescope's nested Xwayland), AND applies a WriteMemory patch
  #     that rewrites the "Launcher" mutex check to "_Game" so POP3.EXE
  #     runs standalone without PrinceOfPersia.exe creating the mutex.
  #   - scripts/pop3w.asi (Nemesis2000 widescreen fix) + scripts/pop3.ini
  #     (render resolution + HUD placement).
  #   - Ultimate ASI Loader as BinkW32.DLL; GOG's real Bink preserved as
  #     BinkW32Hooked.DLL (UAL forwards to it).
  #   - DSOAL (dsound.dll + dsoal-aldrv.dll + hrtf/) restores EAX audio.
  #   - Xidi (dinput8.dll + Xidi.32.dll + SDL plugin) for controllers.
  #   - Prewritten Hardware.ini (skips the launcher's HW detection) and
  #     ready POP3Profiles (a default + "Prince" profile).
  #   - update/pop3.bf data fixes (from the Unofficial Patch).
  fixSrc = fetchIpfs {
    cid = "QmT2Qs7B2nDofqVSk2DDEkzq8jnyCLRx8DCsVvWF9iP1DF";
    fallbackUrl = "https://www.moddb.com/games/prince-of-persia-the-two-thrones/downloads/two-thrones-ultimate-fix-compilation";
    hash = "sha256-eZlzawdPY/eQRWEnp2oOg4i5F4XjVnREs5UuqT2w5Yk=";
    name = "PoP3_FixCompilation.13.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prince-of-persia-the-two-thrones";

  inherit src;

  # Pin the GOG installer and the Fix Compilation zip.
  ipfsSources = [
    src
    fixSrc
  ];

  nativeBuildInputs = [
    innoextract
    unzip
    pkgs.python3
  ];

  buildScript = ''
    mkdir -p "$out"
    # The GOG installer is a single Inno Setup exe; innoextract pulls
    # the complete game tree out of its `app/` directory.
    innoextract -e -s -d "$TMPDIR/gog" "$src"
    cp -r "$TMPDIR/gog/app/." "$out/"
    chmod -R u+rwX "$out"

    # Overlay the Fix Compilation's "Main Patch" (decompressed POP3.EXE,
    # UAL-as-BinkW32, DxWrapper.asi, Nemesis widescreen, DSOAL, Xidi,
    # Hardware.ini, profiles, update/pop3.bf). It overwrites GOG's
    # BinkW32.DLL and PrinceOfPersia.exe in place.
    unzip -q -o "${fixSrc}" 'Main Patch/*' -d "$TMPDIR/fix"
    cp -rf "$TMPDIR/fix/Main Patch/." "$out/"
    chmod -R u+rwX "$out"

    # GOG ships a lowercase, UPX-packed `pop3.exe`; the fix ships the
    # decompressed `POP3.EXE`. On the case-sensitive store fs both now
    # coexist - drop GOG's packed one so wine's case-insensitive lookup
    # resolves unambiguously to the fix's POP3.EXE.
    rm -f "$out/pop3.exe"

    # Large Address Aware on POP3.EXE (PE Characteristics bit 0x0020):
    # the fix's Mini-Launcher applies this at runtime, but we run the
    # game binary directly (DxWrapper's WriteMemory patch bypasses the
    # launcher mutex), so bake it in. Applied to the mousefix variant
    # too, so overriding `executable` keeps the same address space.
    ${pkgs.python3}/bin/python3 -c "$(cat <<'PYEOF'
    import struct, sys
    for p in sys.argv[1:]:
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
    )" "$out/POP3.EXE" "$out/POP3_mousefix.EXE"

    # Nemesis widescreen fix (pop3w.asi) reads scripts/pop3.ini for the
    # render resolution + HUD placement. The fix's stock pop3.ini is
    # 1280x720; set it to 1920x1080 to match the gamescope nested
    # surface below (Hor+ widescreen, no pillarbox). HUD_posX_auto=1 lets
    # the fix compute the 16:9 HUD offset. (The Mini-Launcher's res.lua
    # would auto-write this, but we bypass the launcher.)
    printf '%s\n' \
      '[MAIN]' \
      'Width = 1920' \
      'Height = 1080' \
      '[HUD]' \
      'HUD_posX_auto = 1' \
      'HUD_posX = -0.148958' \
      '[MISC]' \
      'Xbox_fov = 0' \
      'fov_multiplier = 1.0' \
      > "$out/scripts/pop3.ini"
    chmod -R u+rwX "$out"
  '';

  runtime = "proton";
  # Run the game binary directly. DxWrapper's WriteMemory patch rewrites
  # POP3.EXE's launcher-mutex check to "_Game" (loaded via UAL-as-Bink
  # before main()), so the original PrinceOfPersia.exe launcher is not
  # required; Proton's `waitforexitandrun` tracks the game itself.
  executable = "POP3.EXE";

  # POP3.EXE writes all user state (POP3Profiles/ save profiles, logs)
  # into its own CWD, the install dir, which persists via the per-game
  # fuse-overlayfs upper, not the wineprefix. Nothing lands under
  # drive_c/users/steamuser/, so a prefix wipe can't lose progress.
  saveLocations = [ ];

  # Materialize the fix's app-local DLLs + writable configs into the
  # fuse-overlayfs upper before the merge mount. Wine's module loader
  # resolves an app-local native DLL over proton's builtin only when the
  # file is actually present in the upper; a lower-only file surfaced
  # through the merged view is resolved inconsistently (documented in
  # games/company-of-heroes). scripts/ holds dxwrapper.asi + pop3w.asi
  # (loaded by UAL) and their inis; Hardware.ini and the profile dir
  # must be writable for the engine.
  copyGlobs = [
    "BinkW32.DLL"
    "BinkW32Hooked.DLL"
    "dsound.dll"
    "dsoal-aldrv.dll"
    "alsoft.ini"
    "hrtf"
    "dinput8.dll"
    "Xidi.32.dll"
    "Xidi.ini"
    "SDL.XidiPlugin.32.dll"
    "scripts"
    "Hardware.ini"
    "POP3Profiles"
  ];

  # With Nemesis2000's widescreen fix the engine renders true 16:9, so
  # run the nested area at the full 1920x1080 output (1:1, no pillarbox,
  # no upscale). This MUST match pop3.ini's Width/Height above.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # NOTE: do NOT add `-f` / `-b` here - those reach the OUTER
      # gamescope and would grab the host display.
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Load the fix's native DLLs instead of proton's builtins:
    #   binkw32 -> Ultimate ASI Loader (loads scripts/dxwrapper.asi +
    #              scripts/pop3w.asi)
    #   dsound  -> DSOAL (EAX/HRTF audio)
    #   dinput8 -> Xidi (controller support)
    # d3d9 stays builtin (DXVK): DxWrapper wraps it in-process as an ASI.
    WINEDLLOVERRIDES = "binkw32,dsound,dinput8=n,b";
  };

  meta = {
    description = "Prince of Persia: The Two Thrones (Ubisoft Montreal, 2005; GOG DRM-free, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prince-of-persia-the-two-thrones";
  };
}
