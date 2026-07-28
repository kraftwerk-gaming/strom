{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  msitools,
}:

let
  # Mass Effect 3 (BioWare 2012, Unreal Engine 3). Windows-only, so
  # runtime = "proton". This is the standalone 2012 release, NOT the
  # Legendary Edition.
  #
  # Verified headless (gamescope --backend headless + screenshot sidecar):
  # reaches the animated "MASS EFFECT 3 / Press any key to continue" title
  # screen, and past it (XTEST) the New Game / Multiplayer / Extras main
  # menu. Getting there needs the PhysX runtime the repack omits; see
  # "PHYSX" below, and engine audio needs the -log switch; see "AUDIO"
  # below. Menu audio measured at Pk -16.01 / RMS -29.30 dBFS.
  #
  # SOURCE: archive.org item `mass-effect-3-t1coon`,
  # "[PC] Mass Effect 3 [MULTi-ENG-RUS] [LAN]" - a three-volume RAR
  # repack. Only volumes 2 and 3 are fetched here:
  #
  #   Part 1 (0.57 GB, NOT fetched) holds no game data at all: just the
  #     repack's Inno Setup 5.5.7 installer stub ("Mass Effect 3.exe",
  #     carrying ISDone.dll + unarc.dll + facompress.dll + XDelta3.dll)
  #     and a Mods/ folder of optional ME3Tweaks .7z mods.
  #   Part 2 + Part 3 hold Data/Files1.bin .. Data/Files17.bin, which is
  #     the whole payload. Both RARs store those entries UNCOMPRESSED
  #     (RAR5 method 0), so `unar` just copies them out.
  #
  # Each Data/FilesN.bin is a self-contained FreeArc archive ("ArC\1"
  # magic, lzma-coded solid blocks) holding a slice of the PRE-INSTALLED
  # game tree (Binaries/Win32/..., BIOGame/...). nixpkgs' `unarc`
  # decompresses them and verifies their CRCs, so the whole extraction is
  # a headless build step - the Inno/ISDone installer GUI is never run.
  #
  # WHICH BLOCKS: the installer's tmp/records.inf lists all 17 blocks in
  # order with an optional-component index in its third column. That index
  # is 0 for blocks 1-13 (unconditionally installed = the base game) and
  # 1, 2, 3, 4 for blocks 14-17, i.e. the four component checkboxes the
  # repack offers (each verified by listing the block with `unarc v`):
  #   Files14  ME3Server_WV LAN server emulator + its client patcher
  #   Files15  binkw23.dll/binkw32.dll ASI-loader bink bypass
  #   Files16  ME3TweaksModManager.exe
  #   Files17  MassEffectTrilogy.FOVFix.asi (needs the Files15 bypass)
  # Only 1-13 are extracted, so what ships here is the stock game with no
  # mod loader and no server emulator, all official DLC included
  # (BIOGame/DLC: From Ashes, Extended Cut, Leviathan, Omega, Citadel,
  # the weapon/appearance packs and the MP packs) and patch 1.05 applied
  # (BIOGame/Patches/PCConsole/Patch_001.sfar). The repack's [LAN]
  # multiplayer needs Files14+Files15 plus a hosts-file redirect to a
  # locally run ME3Server_WV; that is out of scope for a single-player
  # package.
  #
  # DRM: the repack's Binaries/Win32/MassEffect3.exe is already
  # Origin-stripped - its import table is plain UE3 (d3d9, d3dx9_42,
  # binkw32, PhysXExtensions, XINPUT1_3, ...) with no EACore/activation
  # import, and it carries no SecuROM/Origin strings. Binaries/Win32/Core/
  # (EACore.dll, activation.exe, awc.dll + Qt4) is dead weight the engine
  # never loads; it is kept so the tree matches the source.
  #
  # AUDIO. Symptom before the fix: bink's intro/logo movie reaches the mixer,
  # the engine never opens an audio device at all. The engine side is Wwise,
  # not ISACT/OpenAL: nothing in the tree is an OpenAL router (no
  # OpenAL32.dll, no wrap_oal.dll anywhere) and the exe imports no audio DLL
  # at all. Wwise is statically linked and the exe EXPORTS the whole AK API
  # by name (198 named exports), which pins every address below -
  # AK::SoundEngine::Init is 0xE70160.
  #
  # Wwise's sink is DirectSound over COM. The exe carries a contiguous GUID
  # table CLSID_DirectSound8 / IID_IDirectSound8 / IID_IDirectSoundBuffer8
  # at VA 0x15AD2F4 / 0x15AD304 / 0x15AD314 and no XAudio2 or MMDevice GUID
  # at all; CAkSinkDirectSound::Init at 0xEAB2C0 is
  # CoCreateInstance(CLSID_DirectSound8) -> IDirectSound8::Initialize(NULL)
  # -> SetCooperativeLevel(hWnd, DSSCL_PRIORITY) -> CreateSoundBuffer.
  # Bink is a separate consumer: binkw32.dll imports only user32/gdi32/
  # kernel32/WINMM and LoadLibrary's dsound itself, and a +dsound trace
  # shows `DirectSoundCreate ((null),18031580,00000000)` - 0x18031580 lies
  # inside binkw32, loaded at base 0x18000000 - building a 48 kHz/2ch
  # primary plus a 115712-byte DSBCAPS_GLOBALFOCUS secondary that really
  # mixes (DSOUND_MixOne / mixieee32), then released at movie end. So the
  # movie path really does reach the mixer, and it says nothing about the
  # engine either way.
  #
  # The engine, before the fix, never opened a device. Through the title
  # screen AND the main menu there is not one further dsound call, no
  # DirectSoundEnumerate, and no CoCreateInstance for {3901CC3F-...}: every
  # distinct CLSID in a full run is {00000323} free marshaler, {BCDE0395}
  # MMDeviceEnumerator (4x, all from inside dsound on the bink path),
  # {25E609E4} DirectInput8, {079AA557}, {9A5EA990}, {E22AD333}. The stack
  # underneath is healthy:
  # `init_driver Loading driver list L"pulse,alsa,oss,coreaudio"`,
  # `Successfully loaded L"winepulse.drv" with priority Preferred`,
  # `Selecting driver L"pulse"`, real endpoints enumerated.
  #
  # Cause, from 0xB0BCA0 (the UE3 Wwise device init). It does MemoryMgr::
  # Init, StreamMgr::Create(0x40000) and the IO hook, then takes
  # AkPlatformInitSettings.hWnd from GetForegroundWindow() (0xE70330:
  # memset(plat,0,0x3c); plat->hWnd = GetForegroundWindow()). If that is
  # NULL it tries the game-window global 0x1AA1F2C - written at 0x496E9F,
  # immediately after the main window's CreateWindowExW - then polls
  # appSleep(0.05) + GetForegroundWindow() for a hard 1.0 s, then
  # EnumWindows(callback 0xB0BBB0) demanding wcscmp(title,L"SplashScreen")
  # == 0 AND wcsstr(class,L"SplashScreenClass"). If all four fail it
  # RETURNS FAILURE and AK::SoundEngine::Init is never called, so there is
  # no sink, no audio device and no pulse stream for the whole session.
  # That splash fallback is dead code in this build: ME3 draws its splash
  # with D3D (SplashScreenShader, FSplashVertexShader, FSplashPixelShader,
  # SplashTexture, L"PC\\Splash.bmp") and the only references to
  # L"SplashScreen" / L"SplashScreenClass" are those two comparisons - the
  # process creates exactly ONE window, CreateWindowExW(
  # L"LaunchUnrealUWindowsClient", L"Mass Effect 3") at ret=00496E9B.
  #
  # WINEDEBUG=+relay (RelayInclude on the user32 window calls; the value
  # must be inserted into the [Software\\Wine\\Debug] block Proton already
  # creates, appending a second block is ignored):
  #   20x `Call user32.GetForegroundWindow() ret=00e7034a`, every one
  #       `retval=00000000`  (ret=00e7034a is the instruction after
  #       `call ds:0x12546c8` in 0xE70330, i.e. the hWnd fetch)
  #   `Call user32.EnumWindows(00b0bbb0,0358fb00) ret=00b0be06` sweeping 14
  #       windows (28 GetWindowTextW Call/Ret at ret=00b0bc10; title
  #       lengths 0,0,11,5,11,14,5,11,0,0,0,0,0,11 - none is 12 =
  #       len("SplashScreen"))
  #   bink's DirectSoundCreate 60 lines later, the main window 450 lines
  #       later, i.e. the game has no window of its own yet.
  #
  # Not a headless artifact: in the SAME run and with no helper of any kind,
  # gamescope does give the game X input focus, and the game's own per-frame
  # checks then return its own window 86803 times (46076x `retval=00090098
  # ret=00bd6214` + 40727x at ret=00bf5bbd) from the moment that window
  # exists. The only NULL interval is ME3's first second, when the only wine
  # windows alive are Proton's own (`Steam` 400x300, `SteamVR Status` 1x1,
  # `Input` 119x34) and nothing ever makes one of them foreground. No
  # compositor can focus a window that does not exist yet. On Windows the
  # check passes only incidentally, because GetForegroundWindow() returns
  # whatever the user had focused, which is never NULL on a real desktop.
  #
  # THE FIX is `executableArgs = [ "-log" ]` below, and it is NOT about
  # logging: UE3's -log makes the engine allocate a console, proton spawns
  # conhost.exe, and conhost's top-level window becomes wine's desktop
  # foreground window before UEngine::Init runs. Note that wine's per-desktop
  # FOREGROUND window and the X server's INPUT FOCUS are different things -
  # conhost supplies the former while gamescope keeps the latter on the game
  # (verified: with no injection at all, `xdotool getwindowfocus` and
  # `getactivewindow` inside the wine namespace both return the "Mass Effect
  # 3" window), so input and compositing are unaffected. This is a
  # FINAL_RELEASE UE3 build with GLog compiled out, so -log writes nothing:
  # BIOGame/Logs stays empty. The same predicate was traced independently in
  # games/mass-effect-2 (its Wwise device init is 0x00973BA4 and has no
  # splash fallback at all, so GetForegroundWindow() is its only HWND
  # source). DO NOT remove this flag as debug leftovers.
  #
  # Measured, isolated - a dedicated `module-null-sink` (the game routed to it
  # from launch with PULSE_SINK, so nothing reaches the real output), captured
  # off its monitor with parec s16le/48k/stereo and piped through
  # `sox -t raw ... -n stats`, always at the screenshot-confirmed main menu:
  #   before, no -log:  Pk lev dB -inf, RMS lev dB -inf, and `pactl list
  #                     sink-inputs` shows NO sink-input for the game at all
  #   after, 3 cold runs: Pk -14.97 / RMS -29.03, Pk -16.11 / RMS -29.26,
  #                     Pk -16.01 / RMS -29.30 dBFS, with exactly one
  #                     uncorked sink-input, application.name
  #                     "Mass Effect(TM) 3", float32le 2ch 48000Hz
  # Capturing the default sink's monitor is worthless here - it carries the
  # host's own playback - hence the dedicated sink.
  #
  # The state change is visible in the process too. With -log the dsound
  # class factory is finally reached (`dsound:DllGetClassObject
  # ({3901cc3f-...}, {00000001-...} IClassFactory)` then
  # `DSCF_CreateInstance (..., {c50a7e93-...} = IID_IDirectSound8)` then three
  # IDirectSound8Impl_CreateSoundBuffer), and reading the live 32-bit process
  # (exe base 0x400000) gives g_pDirectSound @0x19222F4 non-NULL (0x02257854,
  # 0x02257854, 0x0225FD4C over the three runs - it is a heap pointer),
  # g_pSink @0x19219E0 = 0x0ECF0C80 in all three (the first
  # CreateSoundBuffer's ppDSBuffer is 0x0ECF0C8C, i.e. sink+0xC, which is
  # what identifies it), g_pStreamMgr @0x1922310 = 0x046E0C68 and
  # AK::SoundEngine state @0x18ED3CC = 2. Without -log that class factory is
  # never reached at all - {3901CC3F-...} does not appear once in any trace -
  # so there is no sink and no device. Regression tell: no pulse sink-input
  # for the game once the intro movies end.
  #
  # Ruled out along the way: the OpenAL-router/HKLM\Software\Khronos\OpenAL
  # story (there is no OpenAL in this title at all, so openal32=b is a
  # no-op); a broken dsound or mmdevapi (bink's path works end to end);
  # winmm - the exe does carry a full waveOut/waveIn set (0xF77000-0xF79000,
  # waveOutGetNumDevs/waveOutOpen/waveOutWrite/waveInOpen/...) but a
  # +winmm,+driver,+msacm trace records not one wave call; GamerSettings.ini
  # (it holds only AppCompat + accessibility keys, no audio); registry.
  #
  # Two alternatives were considered and are deliberately NOT shipped, in
  # case -log ever stops working. (1) A behavioural patch of game code: NOP
  # the 6-byte `je 0xb0bd28` at 0xB0BE0B (`0f 84 17 ff ff ff` -> six 0x90)
  # so the init proceeds with hWnd = NULL; wine's dsound ignores the hwnd in
  # SetCooperativeLevel entirely (it only warns "level=DSSCL_PRIORITY not
  # fully supported") and Wwise does nothing else with it on this sink path,
  # so it would work - but it edits shipped game logic, which -log makes
  # unnecessary. (2) A pkgsCross.mingw32 stub launched as the game's parent
  # that registers an unmapped 1x1 window, SetForegroundWindow()s it, execs
  # the real exe and drops the window once FindWindowW(
  # L"LaunchUnrealUWindowsClient") succeeds. Both were dropped as strictly
  # more machinery than one documented engine switch.
  #
  # Extracting this needs roughly 45 GB of build scratch (19 GB of .bin
  # blocks in $TMPDIR, freed block by block, plus the ~19 GB output tree).
  part2 = fetchIpfs {
    cid = "QmNMk3TjnazNq6ihymGto41H29vxX6PyTBgeis5ez49tfB";
    fallbackUrl = "https://archive.org/download/mass-effect-3-t1coon/Mass%20Effect%203%20%5BMULTi-ENG-RUS%5D%20%5BR%5D%20%5BTN%5D%20-%20Part%202.rar";
    hash = "sha256-z97BsB37rRotBjbwj2VL3HtTrnlpIYVlqeCTlcwGTNA=";
    name = "mass-effect-3-multi-eng-rus-part2.rar";
  };
  part3 = fetchIpfs {
    cid = "Qma3cEPFgMPzJ7yFRLeJNEPTPxLQFosFtEpWM18Vv1zgf5";
    fallbackUrl = "https://archive.org/download/mass-effect-3-t1coon/Mass%20Effect%203%20%5BMULTi-ENG-RUS%5D%20%5BR%5D%20%5BTN%5D%20-%20Part%203.rar";
    hash = "sha256-4HzPL/X4rVK5Ych4VwkZ94GXRgJs7u6LXq2sgs5xcUI=";
    name = "mass-effect-3-multi-eng-rus-part3.rar";
  };

  # PHYSX. ME3 dynamically LoadLibrary()s PhysXLoader.dll (the string is in
  # MassEffect3.exe; it is not a static import) and the repack's tree does
  # NOT ship any PhysX runtime - only UE3's own PhysXExtensions.dll, which
  # itself imports nothing but kernel32/user32. On Windows the repack's
  # installer runs the NVIDIA PhysX System Software MSI to supply the rest;
  # that MSI is a plain OLE container, so msiextract pulls the DLLs out at
  # build time with no installer run.
  #
  # 9.14.0702 is the last System Software shipped as an .msi (later ones are
  # self-extracting .exe). Its Engine/ dir carries v2.7.1..v2.8.3 under
  # version names plus per-title dirs with obfuscated names; the MSI's File
  # table gives their real versions, and Engine/5182B3C9EFEC (the
  # "Alice2" entry, i.e. Alice: Madness Returns, also a 2011 UE3 title) is
  # PhysXCore 2.8.4.10 - the 2.8.4 line ME3 was built against. Common/
  # holds PhysXLoader.dll 2.8.4.9.
  #
  # BOTH halves are required, and each on its own is not enough. Failure
  # modes seen while narrowing this down, all on the same prefix:
  #   - no PhysX runtime at all: LoadLibrary("PhysXLoader.dll") fails and
  #     UE3 pops "Failed to initialize the physics system. Please ensure you
  #     have an updated version of the PhysX System Software installed."
  #   - PhysXLoader.dll present but no AGEIA registry keys: UE3 gets to its
  #     hardware check and dies on "Using hardware accelerated PhysX has
  #     been requested, but the drivers were out of date. FATAL ERROR -
  #     EXITING", i.e. NxGetHWVersion() returns neither NX_HW_VERSION_NONE
  #     nor NX_HW_VERSION_ATHENA_1_0. A WINEDEBUG=+reg,+file trace shows
  #     PhysXLoader probing exactly three keys before that dialog:
  #     HKLM\Software\AGEIA Technologies\, HKLM\Software\NVIDIA Corporation\
  #     PhysX\Runtimes and HKLM\Software\Ageia Technologies, reading
  #     "enableLocalPhysXCore" (as a string) from the first and
  #     "PhysXCore Path" from the last.
  #   - registry keys present but no v2.8.4 dir under "PhysXCore Path":
  #     back to "Failed to initialize the physics system", because with the
  #     registry in place the loader resolves the core through it and stops
  #     falling back to the DLL next to the exe.
  # Hence: the version-named Engine/ tree AND the keys AND a local loader.
  # PhysXDevice.dll + cudart32_60.dll are shipped too so the loader can see
  # for itself that there is no CUDA PhysX device (HwSelection is "CPU"), and
  # PhysXCooking.dll 2.8.3 is in the Engine tree because the loader asks for
  # it by name from there.
  physxMsi = fetchurl {
    url = "https://us.download.nvidia.com/Windows/9.14.0702/PhysX-9.14.0702-SystemSoftware.msi";
    hash = "sha256-CgIuKKzPWFG+nWV3SHzc09Oj4qiiGmRFa3K0FcIX8Dw=";
    name = "PhysX-9.14.0702-SystemSoftware.msi";
  };

  # nixpkgs marks `unarc` (xredor/unarc, the FreeArc decompressor) unfree
  # with a bare `# unknown` license comment, and this flake instantiates
  # nixpkgs with the default allowUnfree = false - so touching
  # pkgs.unarc.drvPath throws at eval. Clear the placeholder license: it
  # is a build-time-only decompressor and none of it lands in the game
  # output.
  unarc = pkgs.unarc.overrideAttrs (old: {
    meta = old.meta // {
      license = lib.licenses.free;
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mass-effect-3";

  src = part2;
  ipfsSources = [
    part2
    part3
  ];

  nativeBuildInputs = [
    unar
    unarc
    msitools
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/data"

    # Both volumes carry the Data/FilesN.bin entries STORED, so this is a
    # straight copy out of the RAR container. -D keeps unar from wrapping
    # the result in an archive-named directory; -f overwrites instead of
    # prompting (unar prompts on stdin, which would hang the build).
    unar -q -f -D -o "$TMPDIR/data" ${part2}
    unar -q -f -D -o "$TMPDIR/data" ${part3}

    # Extract the 13 base-game FreeArc blocks in the order the installer
    # would, so that a later block overriding an earlier block's file wins
    # exactly as it does on Windows. Volume 2 carries 1-6 and 8, volume 3
    # carries 7 and 9-17, hence the interleave - the numeric loop makes it
    # irrelevant which volume a block came from. Each block is dropped as
    # soon as it is unpacked to keep the scratch footprint bounded.
    for i in $(seq 1 13); do
      blk="$TMPDIR/data/Data/Files$i.bin"
      test -f "$blk"
      unarc x -o+ -dp"$out" --noarcext "$blk"
      rm -f "$blk"
    done
    rm -rf "$TMPDIR/data"

    # unarc creates everything 0600/0700.
    chmod -R u+w,a+rX "$out"

    test -f "$out/Binaries/Win32/MassEffect3.exe"

    # PhysX runtime out of the NVIDIA System Software MSI (see PHYSX above).
    # Next to the exe: the loader plus a 2.8.4 core, because that is where a
    # 32-bit process looks first. Under physx-engine/: the same cores under
    # the version-named layout PhysXLoader expects behind the
    # "PhysXCore Path" registry value, materialised into the prefix by
    # preRun.
    msiextract -C "$TMPDIR/physx" ${physxMsi} >/dev/null
    px="$TMPDIR/physx/Program Files/NVIDIA Corporation/PhysX"
    install -m0644 "$px/Common/PhysXLoader.dll" \
      "$px/Common/PhysXUpdateLoader.dll" \
      "$px/Common/PhysXDevice.dll" \
      "$px/Common/cudart32_60.dll" \
      "$out/Binaries/Win32/"
    install -m0644 "$px/Engine/5182B3C9EFEC/PhysXCore.dll" \
      "$out/Binaries/Win32/PhysXCore.dll"
    install -Dm0644 "$px/Engine/5182B3C9EFEC/PhysXCore.dll" \
      "$out/physx-engine/v2.8.4/PhysXCore.dll"
    install -Dm0644 "$px/Engine/v2.8.3/PhysXCore.dll" \
      "$out/physx-engine/v2.8.3/PhysXCore.dll"
    install -Dm0644 "$px/Engine/v2.8.3/PhysXCooking.dll" \
      "$out/physx-engine/v2.8.3/PhysXCooking.dll"
  '';

  runtime = "proton";
  executable = "Binaries/Win32/MassEffect3.exe";

  # Load-bearing for AUDIO, and not about logging - see "AUDIO" above. ME3
  # initialises Wwise before it creates its own game window and takes
  # AkPlatformInitSettings.hWnd from GetForegroundWindow(); in a fresh wine
  # prefix nothing holds the foreground for that first second, so the audio
  # device init bails and AK::SoundEngine::Init is never called. UE3's -log
  # switch makes the engine allocate a console (the exe imports AllocConsole,
  # GetConsoleWindow, SetConsoleTitleW, FreeConsole), proton spawns
  # conhost.exe, and conhost's top-level window is the desktop's foreground
  # window well before UEngine::Init runs - so the HWND fetch succeeds and
  # Wwise comes up. Nothing else in the launch depends on this flag; do NOT
  # "tidy" it away. The engine log it also writes lands in the relocated
  # Documents/BioWare/Mass Effect 3/BIOGame/Logs (see saveLocations).
  executableArgs = [ "-log" ];

  # Verified empirically: a first launch creates
  #   drive_c/users/steamuser/Documents/BioWare/Mass Effect 3/
  #     BIOGame/{Config/GamerSettings.ini,Logs,Screenshots}
  #     Binaries/Win32/
  # so the whole "Mass Effect 3" dir is relocated. ME3 puts its savegames
  # in the same tree (BIOGame/Save), which is why this is the dir rather
  # than the Save subdir: the Config there also carries the AppCompat
  # detection results, which are expensive to redo on every prefix wipe.
  saveLocations = [ "Documents/BioWare/Mass Effect 3" ];

  # Seed what the NVIDIA PhysX System Software installer would leave
  # behind: the Engine/ tree under Program Files and the HKLM\Software\
  # AGEIA Technologies values PhysXLoader.dll reads (see PHYSX above).
  # Registry edits go straight into system.reg per AGENTS.md rather than
  # through `wine regedit`, and both the plain and the Wow6432Node path are
  # written because MassEffect3.exe is 32-bit and its HKLM\SOFTWARE reads
  # are WOW64-redirected. Idempotent: skipped once the key is present.
  preRun = ''
        PFX="$STROM_COMPATDATA/0/pfx"
        PHYSX_DIR="$PFX/drive_c/Program Files/NVIDIA Corporation/PhysX"
        if [ -d "$PFX/drive_c" ] && [ ! -d "$PHYSX_DIR/Engine" ]; then
          mkdir -p "$PHYSX_DIR"
          cp -r "$GAMEDIR/physx-engine" "$PHYSX_DIR/Engine"
          chmod -R u+w "$PHYSX_DIR"
        fi
        if [ -f "$PFX/system.reg" ] && ! grep -q 'AGEIA Technologies' "$PFX/system.reg"; then
          for __strom_base in 'Software' 'Software\\Wow6432Node'; do
            cat >> "$PFX/system.reg" <<EOF

    [$__strom_base\\\\AGEIA Technologies] 1782266459
    #time=1dd037d4d1cb964
    "HwSelection"="CPU"
    "PhysX Version"=dword:008b79de
    "PhysX (GPU) Version"=dword:008b79de
    "PhysX BuildCL"=dword:00000000
    "PhysXCore Path"="C:\\\\Program Files\\\\NVIDIA Corporation\\\\PhysX\\\\Engine"
    "enableLocalPhysXCore"="1"

    [$__strom_base\\\\AGEIA Technologies\\\\PhysX_A32_Engines] 1782266459
    #time=1dd037d4d1cb964
    "2.8.3"=dword:0000002b
    "2.8.4"=dword:0000000a
    EOF
          done
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
      # ME3 is a third-person mouse-look shooter; without a relative cursor
      # grab gamescope feeds absolute pointer warps and look speed comes out
      # seat-resolution dependent (same fix as dark-souls, arx-fatalis).
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Mass Effect 3 (BioWare 2012, Unreal Engine 3, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mass-effect-3";
  };
}
