{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # GOG DRM-free release of Prince of Persia: Warrior Within
  # (v1.00.999 / installer v2.0.0.9). We package the GOG edition, not
  # the retail SafeDisc 4 / StarForce 3 CD, for the same reason as The
  # Sands of Time: the retail DRM does not work on modern Windows or
  # under Proton, whereas GOG's DRM-free build is what actually runs.
  # The GOG installer is a 3-part Inno Setup (a small .exe stub plus two
  # .bin slices); innoextract reassembles them into the `app/` tree.
  # GOG's game binary is a UPX-packed `pop2.exe` launched by
  # PrinceOfPersia.exe (hardware detection + config). Warrior Within's
  # engine issues the same exclusive-fullscreen modeswitch that wedges
  # forever under gamescope's nested Xwayland, so we layer the community
  # Fix Compilation on top (see fixSrc).
  srcExe = fetchIpfs {
    cid = "QmZANN4qAVVzpis3dQnc6x4ci4Fs6pCXHRddjT3VGbamWb";
    fallbackUrl = "";
    hash = "sha256-xgLheDQeoJ/a+9QLZ8J2Ed/QI5TeNwP9SfJ8EV3F9I8=";
    name = "pop-ww-gog-setup.exe";
  };
  srcBin1 = fetchIpfs {
    cid = "QmPi2XYSUHGqFPMH2EvriwtdDXoKF9k2YB8vZo3gocMNxN";
    fallbackUrl = "";
    hash = "sha256-DzGFdW+PqtC0QahP3uv28RLO+HudTpEn49yefPJjnc4=";
    name = "pop-ww-gog-1.bin";
  };
  srcBin2 = fetchIpfs {
    cid = "QmesDtByHsXKHsyVsy7D9AjLQEKT9c8wqZf8PcY1Ufued7";
    fallbackUrl = "";
    hash = "sha256-FwBZvV+vBfd0sHOmcmwP1XQTk13dVQM5W/rQWI+lWIk=";
    name = "pop-ww-gog-2.bin";
  };

  # Warrior Within - Fix Compilation (vini1264, ModDB), the community
  # all-in-one that makes WW run on modern systems. Its `Main Patch/`
  # folder is a drop-in overlay that we lay on top of the GOG install:
  #   - POP2.EXE: the UPX-DECOMPRESSED game binary (5,533,696 bytes),
  #     the size Nemesis2000's widescreen fix expects. Replaces GOG's
  #     packed pop2.exe.
  #   - scripts/dxwrapper.asi (elishacloud DxWrapper), loaded as an ASI
  #     plugin by the Ultimate ASI Loader (shipped AS BinkW32.DLL). It
  #     wraps the D3D9 device to D3D9Ex (D3d9to9Ex) so the engine's
  #     exclusive-fullscreen present never lands (which wedges under
  #     gamescope's nested Xwayland), AND applies a WriteMemory patch
  #     that rewrites the "_Launcher" mutex check to "_Game" so POP2.EXE
  #     runs standalone without PrinceOfPersia.exe creating the mutex.
  #   - scripts/pop2w.asi (Nemesis2000 widescreen fix) + scripts/pop2.ini
  #     (render resolution + HUD placement).
  #   - Ultimate ASI Loader as BinkW32.DLL; GOG's real Bink preserved as
  #     BinkW32Hooked.DLL (UAL forwards to it).
  #   - DSOAL (dsound.dll + dsoal-aldrv.dll + hrtf/) restores EAX audio.
  #   - Xidi (dinput8.dll + Xidi.32.dll + SDL plugin) for controllers.
  #   - Prewritten Hardware.ini (skips the launcher's HW detection) and
  #     ready GameProfiles/POPWWProfiles (a default + "Prince" profile).
  #   - update/prince.bf (Prince Missing Teeth patch) + a fixed cutscene.
  fixSrc = fetchIpfs {
    cid = "QmQh29TnXovnBqDYrQfeDvpqvSSBqZnTS5w6cWMJ1aZvLA";
    fallbackUrl = "https://www.moddb.com/games/prince-of-persia-warrior-within/downloads/warrior-within-fix-compilation";
    hash = "sha256-fLFBqG2KUwodTloFwOSg2wbXU4nHXidJ2nUybeKGgeE=";
    name = "PoP2_FixCompilation.10.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prince-of-persia-warrior-within";

  # `src` is the Inno setup stub; the two .bin slices and the fix zip are
  # consumed by the buildScript via their store paths.
  src = srcExe;

  # Pin all three GOG installer parts plus the Fix Compilation zip.
  ipfsSources = [
    srcExe
    srcBin1
    srcBin2
    fixSrc
  ];

  nativeBuildInputs = [
    innoextract
    unzip
    pkgs.python3
  ];

  buildScript = ''
    mkdir -p "$out"
    # Reassemble the 3-part GOG Inno installer (stub .exe + two .bin
    # slices) under their original names so innoextract can slice them,
    # then pull the complete game tree out of its `app/` directory.
    mkdir -p "$TMPDIR/inst"
    cp "$src"        "$TMPDIR/inst/setup_pop_warior_within_2.0.0.9.exe"
    cp "${srcBin1}"  "$TMPDIR/inst/setup_pop_warior_within_2.0.0.9-1.bin"
    cp "${srcBin2}"  "$TMPDIR/inst/setup_pop_warior_within_2.0.0.9-2.bin"
    innoextract -e -s -d "$TMPDIR/gog" "$TMPDIR/inst/setup_pop_warior_within_2.0.0.9.exe"
    cp -r "$TMPDIR/gog/app/." "$out/"
    chmod -R u+rwX "$out"

    # Overlay the Fix Compilation's "Main Patch" (decompressed POP2.EXE,
    # UAL-as-BinkW32, DxWrapper.asi, Nemesis widescreen, DSOAL, Xidi,
    # Hardware.ini, profiles, update/prince.bf). It overwrites GOG's
    # BinkW32.DLL and PrinceOfPersia.exe in place.
    unzip -q -o "${fixSrc}" 'Main Patch/*' -d "$TMPDIR/fix"
    cp -rf "$TMPDIR/fix/Main Patch/." "$out/"
    chmod -R u+rwX "$out"

    # GOG ships a lowercase, UPX-packed `pop2.exe`; the fix ships the
    # decompressed `POP2.EXE`. On the case-sensitive store fs both now
    # coexist - drop GOG's packed one so wine's case-insensitive lookup
    # resolves unambiguously to the fix's POP2.EXE.
    rm -f "$out/pop2.exe"

    # Large Address Aware on POP2.EXE (PE Characteristics bit 0x0020):
    # the fix's Mini-Launcher applies this at runtime, but we run the
    # game binary directly (DxWrapper's WriteMemory patch bypasses the
    # launcher mutex), so bake it in. Only modification to POP2.EXE.
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
    )" "$out/POP2.EXE"

    # Nemesis widescreen fix (pop2w.asi) reads scripts/pop2.ini for the
    # render resolution + HUD placement. The fix's stock pop2.ini is
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
      'HUD_glitch_fix = 0' \
      '[MISC]' \
      'Xbox_fov = 0' \
      'fov_multiplier = 1.0' \
      > "$out/scripts/pop2.ini"
    chmod -R u+rwX "$out"
  '';

  runtime = "proton";
  # Run the game binary directly. DxWrapper's WriteMemory patch rewrites
  # POP2.EXE's "_Launcher" mutex check to "_Game" (loaded via UAL-as-Bink
  # before main()), so the original PrinceOfPersia.exe launcher is not
  # required; Proton's `waitforexitandrun` tracks the game itself.
  executable = "POP2.EXE";

  # POP2.EXE writes all user state (GameProfiles/ + POPWWProfiles/ save
  # profiles, logs) into its own CWD, the install dir, which persists via
  # the per-game fuse-overlayfs upper, not the wineprefix. Nothing lands
  # under drive_c/users/steamuser/, so a prefix wipe can't lose progress.
  saveLocations = [ ];

  # Materialize the fix's app-local DLLs + writable configs into the
  # fuse-overlayfs upper before the merge mount. Wine's module loader
  # resolves an app-local native DLL over proton's builtin only when the
  # file is actually present in the upper; a lower-only file surfaced
  # through the merged view is resolved inconsistently (documented in
  # games/company-of-heroes). scripts/ holds dxwrapper.asi + pop2w.asi
  # (loaded by UAL) and their inis; Hardware.ini and the profile dirs
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
    "GameProfiles"
    "POPWWProfiles"
  ];

  # With Nemesis2000's widescreen fix the engine renders true 16:9, so
  # run the nested area at the full 1920x1080 output (1:1, no pillarbox,
  # no upscale). This MUST match pop2.ini's Width/Height above.
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
    #              scripts/pop2w.asi)
    #   dsound  -> DSOAL (EAX/HRTF audio)
    #   dinput8 -> Xidi (controller support)
    # d3d9 stays builtin (DXVK): DxWrapper wraps it in-process as an ASI.
    WINEDLLOVERRIDES = "binkw32,dsound,dinput8=n,b";
  };

  meta = {
    description = "Prince of Persia: Warrior Within (Ubisoft Montreal, 2004; GOG DRM-free, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prince-of-persia-warrior-within";
  };
}
