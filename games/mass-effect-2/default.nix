{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
  p7zip,
  unar,
}:

let
  # Patched 32-bit DXVK d3d9.dll that makes D3DSWAPEFFECT_DISCARD behave the
  # way Windows drivers do (back buffer blank after Present) instead of the way
  # DXVK and wined3d both do (contents preserved). That difference is the whole
  # green-block defect on ME2's full-screen Scaleform screens; the patch file
  # carries the measurements. The behaviour is opt-in inside the DLL, keyed on
  # DXVK_D3D9_DISCARD_BACKBUFFER=1, which is set in env below.
  #
  # Version-pinned on purpose: the patch is a context diff against DXVK 2.7.1's
  # d3d9_swapchain.cpp, which is also the version GE-Proton10-34/11-1 bundle, so
  # this is the same code with one behaviour flipped rather than a version
  # downgrade. If nixpkgs moves off 2.7.1 the assert fires instead of silently
  # shipping an unpatched or mismatched DLL.
  # pkgs.dxvk.dxvk32 is the 32-bit mingw build nixpkgs itself feeds into its
  # DXVK setup script (win32 thread model, i686-w64-mingw32); ME2 is a PE32, so
  # that is the architecture that matters here.
  dxvkDiscardBackBuffer =
    assert pkgs.dxvk.version == "2.7.1";
    pkgs.dxvk.dxvk32.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./dxvk-2.7.1-d3d9-discard-backbuffer.patch ];
    });

  # Mass Effect 2 (BioWare 2010), the standalone PC release - NOT the
  # Legendary Edition. Unreal Engine 3 (SFXGame / "sfx2" build 1593.02),
  # Windows-only, so runtime = "proton".
  #
  # SOURCE: archive.org item `mass-effect-2_202509` ("Mass Effect 2 (PC)
  # EU"), file ME2.7z. Despite the name it is not a pre-installed tree: it
  # is a 7z of the two EU retail DVD images (ME2/MassEffect2.iso = disc 1,
  # ME2/ME2_Disc2.iso = disc 2) plus three box scans we drop.
  #
  # WHY NO INSTALLER RUN IS NEEDED: the retail Setup.exe does nothing but
  # unpack plain RAR4 payloads from <disc>/data/ into the install dir and
  # write a couple of registry values. disc 1's data/installmanifest_en.ini
  # enumerates the exact English (TextLanguage=INT / VOLanguage=INT) set and
  # which disc each archive lives on, so buildScript reproduces the install
  # by extracting those ten archives directly - no InstallShield, no serial
  # prompt, no GUI. The four other localisations (french/german/italian/
  # spanish.rar, ~5.0 GB) are deliberately skipped.
  #
  # DISC AUTHENTICATION, and how it is beaten. Out of the box the tree
  # builds and the engine runs a long way headlessly - it creates the
  # D3D9/DXVK device, runs its AppCompat probe (GamerSettings.ini gets
  # MeasuredCPUScore and the real GPUVendorID), initialises PhysX - and then
  # pops a modal
  #   "Failed to authenticate the disc. Please insert the correct disc and
  #    try again."
  # This is the EU DVD's own check, not a wrapped executable:
  # `Binaries/MassEffect2.exe` out of exe.rar is a plain MSVC PE
  # (.text/.rdata/.data/.rsrc/.reloc, zero SecuROM / Sony-DADC / CmdLineExt
  # markers) and the dialog string lives in the cooked TLKs, not the exe.
  #
  # WHAT THE CHECK ACTUALLY READS (disassembled in the retail 01593.02 exe,
  # image base 0x400000; the authenticator is the function at 0x9d67a0):
  #   1. GetLogicalDrives(), then for i in 0..25 over 'A'+i:
  #   2. GetDriveTypeW("X:") must be 5 = DRIVE_CDROM               @0x9d6803
  #   3. GetVolumeInformationW("X:") and wcsncmp(label, L"MassEffect2", 0x18)
  #                                                               @0x9d6823
  #   4. only on a label hit, the function at 0xd48870 does the real work:
  #      sprintf("\\\\.\\%c:") and CreateFileA() on that RAW DEVICE @0xd49625
  #      then DeviceIoControl(h, 0x00335140, in=0x11, out=0x804)   @0xd4987f
  #      = IOCTL_DVD_READ_STRUCTURE (FILE_DEVICE_DVD 0x33, function 0x450,
  #      METHOD_BUFFERED, FILE_READ_ACCESS) - i.e. the DVD PHYSICAL FORMAT /
  #      layer descriptor. Two further sites (@0xd49b6e, @0xd49d81) retry the
  #      same query as a SCSI pass-through with CDB opcode 0xAD
  #      (READ DVD STRUCTURE) and a 0x0804-byte allocation length.
  #      GetComputerNameA @0xd48912 is folded into the cached verdict.
  #   The authenticator returns 0 on success and 4 otherwise; non-zero raises
  #   the modal.
  #
  # Steps 1-3 are satisfiable by a fake drive, step 4 is not, and that is
  # confirmed at runtime rather than only read off the disassembly. The retail
  # exe under WINEDEBUG=+file,+cdrom,+ntoskrnl with a directory-backed D:
  # typed "cdrom" and labelled MassEffect2 logs exactly this, immediately
  # before it loads msimg32 for the message box:
  #   NtCreateFile    L"\??\D:\"                        drive root / label
  #   CreateFileW     L"\\.\D:"  GENERIC_READ           raw device handle
  #   DeviceIoControl 0x00041018 IOCTL_SCSI_GET_ADDRESS       out 8
  #   DeviceIoControl 0x00335140 IOCTL_DVD_READ_STRUCTURE     in 17 out 2052
  #   CreateFileW     L"\\.\D:"  GENERIC_READ|GENERIC_WRITE
  #   DeviceIoControl 0x00041018 IOCTL_SCSI_GET_ADDRESS       out 8
  #   DeviceIoControl 0x00335140 IOCTL_DVD_READ_STRUCTURE     in 17 out 2052
  #   DeviceIoControl 0x0004d004 IOCTL_SCSI_PASS_THROUGH      in/out 2132
  # Reaching the raw open at all proves the label gate passed, so the earlier
  # attempt here (a directory-backed CD-ROM D: carrying disc 1's label
  # MassEffect2 - it is the volume id in both the ISO9660 PVD and the Joliet
  # SVD - via .windows-label plus [Software\Wine\Drives] "d:"="cdrom") died on
  # the DVD structure read behind it, which is why its dialog was
  # byte-identical. With no CD-ROM drive at all the trace shows zero device
  # traffic: the drive loop finds no DRIVE_CDROM and gives up at once.
  #
  # Nothing driveless can answer those two ioctls. Wine routes them to its
  # cdrom handler, but the \Device\CdRom0 that mountmgr creates for a
  # directory-backed drive has no unix optical device behind it, and an ISO -
  # loop-mounted, fuseiso-mounted or 7z-extracted into the store - carries no
  # DVD layer descriptor and cannot service a SCSI CDB either. So the fix has
  # to be in the executable - noCdExe below.
  #
  # Disc 1's image has nothing authentic to present anyway. Its volume
  # descriptors (MassEffect2.iso sectors 16 and 17, read over HTTP range
  # requests) give volume id "MassEffect2" in both the ISO9660 PVD and the
  # Joliet SVD (escape %/E), 3829635 x 2048-byte sectors = 7843092480 bytes
  # so DVD9-sized, volume set size/sequence 1, EMPTY volume-set/publisher/
  # preparer/application ids, and a creation and modification timestamp of
  # 2025-09-30 21:20:25 - the uploader's rip date, not a pressing date. Root
  # directory: AUTORUN.EXE/INF, DATA/, DIRECTX/, DOCS/, SOFTWARE/, SUPPORT/,
  # SETUP.EXE and the EULA/readme set.
  #
  # Not to be confused with the retail activation in the root
  # MassEffect2Launcher.exe; that is a separate gate and we never launch it.
  #
  # Once the disc gate is gone the engine plays its intro reel and lands on
  # the Scaleform frontend, where a first launch on a fresh prefix shows the
  # game's own "Welcome to Cerberus Network activation" prompt
  # (Continue/Cancel) over the main-menu backdrop. That is the shipped
  # EA-Online DLC prompt, not a disc gate, and it is mouse-only: no key
  # dismisses it. It could not be clicked away in the headless harness
  # because gamescope's headless backend delivers XTEST keyboard input to the
  # game (Escape skips the intro movies) but no pointer input at all - dinput
  # never sees the warps, so the frontend draws no cursor. Verified that far;
  # dismissing it needs a real pointer.
  #
  # AUDIO IS FIXED AS OF GE-Proton11-1 -- the section below is kept for its
  # mechanism, but its conclusion no longer reproduces. Re-measured on
  # GE-Proton11-1 (AGENTS.md warns that proton floats with flake.lock and that
  # diagnoses must be re-verified after a bump; this is that re-verification):
  #
  #   WINEDEBUG=+dsound on a headless gamescope run shows binkw32's
  #   DirectSoundCreate ZERO times and Wwise's COM route instead --
  #   DllGetClassObject({3901cc3f-84b5-4fa4-ba35-aa8172b8a09b}) ->
  #   DSCF_CreateInstance({c50a7e93-...}) -> IDirectSound8Impl_Initialize ->
  #   DSOUND_PrimaryOpen -> CreateSoundBuffer. That is the "AUDIBLE run"
  #   signature described in point 4 below, i.e. AK::SoundEngine::Init now
  #   runs, so GetForegroundWindow() is returning a usable HWND on this
  #   proton where it returned NULL on the older one.
  #
  #   Measured, not asserted: the game routed alone onto a dedicated
  #   module-null-sink and its monitor recorded with parecord + `sox -n
  #   stats` gives Pk -10.30 dBFS / RMS -25.04 dBFS over 12.3 s. The sink was
  #   unloaded afterwards and the operator's streams were never touched.
  #
  # So do NOT patch GetForegroundWindow. That workaround was prototyped
  # (redirecting the import to GetDesktopWindow does make Wwise init on a
  # proton where the gate fails) and then dropped as unnecessary here: it
  # rewrites all five call sites of a function the engine also uses for focus
  # decisions, which is a real risk to take for a defect that no longer
  # exists on the pinned toolchain.

  # AUDIO: WHY THE HEADLESS HARNESS HEARS ONLY THE INTRO. Play-testing
  # reported "sound during the intro movies, silence afterwards". The cause is
  # NOT a driver, a device or a missing redistributable, and it is NOT the
  # OpenAL runtime the tree ships. Findings, so nobody re-runs this:
  #
  # 1. ME2 DOES NOT USE OPENAL AT ALL. Binaries/OpenAL32.dll and
  #    Binaries/wrap_oal.dll are vestigial ME1-era leftovers.
  #    MassEffect2.exe's import table has no OpenAL32.dll and no DSOUND.dll
  #    (its only delay-imports are d3d10.dll/dxgi.dll/PhysXLoader.dll), and
  #    the image contains no "OpenAL"/"wrap_oal" string in either encoding.
  #    WINEDEBUG=+loaddll across four launches never loads either DLL.
  #    Contrast games/mass-effect (ME1, audio works): its MassEffect.exe
  #    statically imports BOTH OpenAL32.dll and DSOUND.dll and carries
  #    Get/SetOpenALSourceProperty plus the whole ISACTAudioDevice class set.
  #    That is the real ME1-vs-ME2 difference: different middleware, not
  #    different configuration. So WINEDLLOVERRIDES="openal32=b" is a no-op
  #    here, and the absence of HKLM\Software\Khronos\OpenAL is irrelevant
  #    (ME1's working prefix has no such key either).
  #
  # 2. ME2's audio is Wwise, statically linked - 72 Ak/CAk RTTI descriptors
  #    (CAkAudioNode, CAkMusicRenderer, CAkSrcFileVorbis, ...), AK::BankManager,
  #    and 315 Wwise symbols EXPORTED by name from the exe, which makes the
  #    addresses below free:
  #      0x00DEE9F0 ?Init@SoundEngine@AK@@...
  #      0x00DEBC40 ?GetDefaultPlatformInitSettings@SoundEngine@AK@@...
  #      0x00E32100 ?CreatePool@MemoryMgr@AK@@...
  #    Its sink is DirectSound reached over COM, not via the dsound exports:
  #    CLSID_DirectSound8 {3901CC3F-84B5-4FA4-BA35-AA8172B8A09B} @0x00FE307C
  #    and IID_IDirectSound8 {C50A7E93-...} @0x00FE308C are referenced by
  #    exactly one routine, 0x00E26A40, which does
  #    CoCreateInstance(CLSID_DirectSound8, NULL, CLSCTX_INPROC_SERVER,
  #    IID_IDirectSound8, &g_pDS@0x0123E3D0) then Initialize(NULL) [vtbl+0x28],
  #    SetCooperativeLevel(hWnd, DSSCL_PRIORITY) [+0x18], CreateSoundBuffer of
  #    a DSBCAPS_PRIMARYBUFFER [+0x0C], GetCaps [+0x10], GetSpeakerConfig
  #    [+0x20]. CAkSink::Create @0x00E26CC0 picks between that 0x30-byte
  #    CAkSinkDirectSound (vtable 0x00FED1E8) and a 0x18-byte silent dummy
  #    sink (vtable 0x00FED210).
  #
  # 3. THE INTRO AUDIO IS BINK'S, NOT THE ENGINE'S. The exe imports
  #    binkw32!_BinkOpenDirectSound@4, and in a silent run the only
  #    DirectSound consumer in the whole session is
  #      dsound:DirectSoundCreate ((null),1802D574,00000000)
  #    where 0x1802D574 lies inside binkw32.dll (loaded at 0x18000000). Bink
  #    opens DirectSound itself, plays the reel, and releases it
  #    (directsound_destroy ... released) - after which there is silence, and
  #    not one dsound COM call ever appears. mmdevapi is healthy throughout:
  #      load_driver Successfully loaded L"winepulse.drv" with priority Preferred
  #      init_driver Selecting driver L"pulse" with priority Preferred
  #
  # 4. THE ENGINE NEVER INITIALISES WWISE. ME2's UE3 audio-device init lives
  #    at 0x00973BA4 and runs: MemoryMgr::IsInitialized -> create
  #    AK::IAkStreamMgr (global 0x0127D2B0) -> GetDefaultInitSettings ->
  #    GetDefaultPlatformInitSettings -> AK::SoundEngine::Init. The middle step
  #    is the gate. 0x00DEBC40 tail-calls 0x00E1C310, which at 0x00E1C324 does
  #    `call ds:0x00EEE620` = user32!GetForegroundWindow and stores the result
  #    as AkPlatformInitSettings.hWnd (+0x00), alongside
  #    uLEngineDefaultPoolSize=0x1000000 (+0x1C) and uNumRefillsInVoice=4
  #    (+0x24). Back in the caller:
  #      0x00973C02  if (plat.hWnd != 0)                 -> proceed
  #      0x00973C09  else if (g_GameWindow@0x0127D16C)   -> use it
  #      0x00973C9A  else Sleep(100) + retry for ~1.0 s (appSeconds bound)
  #      0x00973CEF  if still 0 -> log and return FALSE
  #    and AK::SoundEngine::Init @0x00973C67 is then NEVER CALLED, silently,
  #    for the rest of the process. ME2 imports no EnumWindows/GetWindowTextW/
  #    GetClassNameW, so unlike ME3 there is no splash-window fallback:
  #    GetForegroundWindow() is the only source of that HWND. The game's own
  #    window does not exist yet at this point, so under gamescope - where
  #    nothing in the wine session has ever been activated - wine's desktop
  #    foreground window is NULL and the gate fails. On Windows the desktop
  #    always has SOME foreground window, ME2 hands that foreign HWND to
  #    Wwise, and DirectSound ignores it anyway (wine even warns
  #    "SetCooperativeLevel level=DSSCL_PRIORITY not fully supported").
  #
  #    Read live out of /proc/<pid>/mem (the exe maps at its preferred base
  #    0x00400000), at the main menu:
  #      SILENT run: AkPlatformInitSettings @0x0123DD50 all zero (hWnd=0,
  #        uNumRefillsInVoice @0x0123DD74 = 0), LEngine pool id @0x0120D6D0 =
  #        0xFFFFFFFF (AK_INVALID_POOL_ID), CoInitializeEx-ok @0x0123DD94 = 0,
  #        g_pSink @0x0123DD4C = NULL, g_pDirectSound @0x0123E3D0 = NULL --
  #        while AK::IAkStreamMgr @0x0127D2B0 = 0x0129ABB0 IS created, which
  #        places the failure exactly at the hWnd gate and nowhere else.
  #      AUDIBLE run: hWnd = 0x0002009C, uNumRefillsInVoice = 4, pool id = 3,
  #        g_pSink = 0x071A0C80 with vtable 0x00FED1E8 = CAkSinkDirectSound,
  #        g_pDirectSound = 0x01B6006C.
  #
  # 5. A/B THAT PINS IT. Same WINEDEBUG=+loaddll,+dsound,+mmdevapi, the only
  #    difference being UE3's `-log` on the command line. The module-load order
  #    is byte-identical through gameux.dll, ddraw.dll, PhysXLoader.dll,
  #    PhysXCooking.dll, physxcudart_20.dll, PhysXCore.dll, PhysXDevice.dll,
  #    nvcuda.dll and then diverges precisely at the audio step:
  #      without -log: Loaded L"C:\windows\system32\DSOUND.DLL" (the uppercase
  #        name binkw32 passes to LoadLibrary) followed by Bink's
  #        DirectSoundCreate above - Wwise never appears.
  #      with -log: conhost.exe (i.e. a console WINDOW, which is what makes
  #        wine's foreground window non-NULL) then
  #        Loaded L"C:\windows\system32\dsound.dll" (lowercase: the
  #        InprocServer32 value), dsound:DllGetClassObject
  #        ({3901cc3f-84b5-4fa4-ba35-aa8172b8a09b}, {00000001-...}),
  #        dsound:DSCF_CreateInstance (..., {c50a7e93-...}),
  #        IDirectSound8Impl_Initialize (01B60068, (null)), PrimaryOpen at
  #        48000/2ch/16bit, then CreateSoundBuffer with
  #        DSBCAPS_CTRLVOLUME|GLOBALFOCUS|GETCURRENTPOSITION2 - Wwise's own
  #        flags - and Bink then REUSES that same IDirectSound8 01B60068.
  #    `-log` is a symptom of the predicate, not the predicate: it is the
  #    console window, not the logging, that satisfies GetForegroundWindow().
  #
  # 6. MEASUREMENTS, isolated the only way that is meaningful on a shared
  #    machine: move ONLY the game's own PulseAudio sink-input onto a
  #    dedicated module-null-sink, then parec that null sink's monitor
  #    (s16le/48000/stereo) and `sox ... -n stats`.
  #      silent run at the main menu: NO ME2 sink-input exists at all;
  #        9.2 s of the null monitor reads Pk -inf / RMS -inf (digital silence).
  #      during the intro/attract reel: an ME2 sink-input DOES exist
  #        (application.name="Mass Effect 2", wine-preloader, uncorked) and
  #        10.2 s reads Pk -4.28 / RMS -18.71 dBFS. That is Bink.
  #      audible run at the main menu, with Bink's buffer already destroyed and
  #        only Wwise's 16384-byte secondary buffer being polled: 12.3 s reads
  #        Pk -22.47 / RMS -36.35 dBFS. That is Wwise.
  #
  # RULED OUT along the way, so it does not get re-tested: the shipped OpenAL
  # router and any missing OpenAL implementation (never loaded; wrap_oal.dll
  # ships anyway); HKLM\Software\Khronos\OpenAL (absent in ME1's working
  # prefix too); dsound's COM registration (Software\Classes\CLSID and
  # Software\Classes\Wow6432Node\CLSID {3901CC3F-...}\InprocServer32 =
  # C:\windows\system32\dsound.dll, present and identical in the ME1 and ME2
  # prefixes); mmdevapi/winepulse driver selection (successful in every run);
  # the 32-bit libudev in lib/proton.nix (present); missing audio content
  # (1155 .afc plus WwiseAudio.pcc and Wwise_Load_Audio_Default.* are all in
  # the tree); an ini-selected provider that resolves to nothing
  # (BioGame/Config/DefaultEngine.ini's [WinDrv.WindowsClient]
  # AudioDeviceClass=WwiseAudio.WwiseAudioDevice is correct, and the class-name
  # lookup at 0x00976120 never even executes - its globals 0x0129FC2C/
  # 0x0129FC30 stay 0 in an AUDIBLE run); and Wwise memory exhaustion (the
  # 16 MB LEngine pool is never even attempted).
  #
  # THE FIX is `executableArgs = [ "-log" ]` further down - read the comment
  # there before touching it. It is not debug leftovers: UE3's -log allocates a
  # console, which spawns conhost.exe and with it a real top-level WINDOW, and
  # that is what makes wine's desktop foreground window non-NULL before the
  # ~1 s grace period at 0x00973C9A expires. The gate at 0x00973C02 then
  # passes and AK::SoundEngine::Init actually runs.
  # Measured, 4 consecutive cold headless runs, isolated on a dedicated
  # module-null-sink: a live "Mass Effect 2" sink-input every time, Pk -24.09
  # / -22.68 / -15.62 / -22.10 dBFS. Without the flag: no sink-input for the
  # game at all and Pk/RMS -inf on the same sink.
  #
  # STALE-FRAME ACCUMULATION IN THE FULL-SCREEN SCALEFORM MENUS: FIXED, by the
  # patched DXVK d3d9.dll built as dxvkDiscardBackBuffer at the top of this file
  # and installed next to the executable. The diagnosis below is why that patch
  # exists and why nothing short of it works, so keep it: every plausible
  # config-level option was eliminated first, and this package must not go back
  # to spending runs on them.
  #
  # SYMPTOM. Any full-screen Scaleform menu - the New Game difficulty screen
  # (Combat Difficulty / Auto Level Up / Subtitles / Squad Power Usage /
  # Autosave + Continue) and the in-game pause-wheel Options screen (Gameplay /
  # Key Bindings / Input / Graphics / Sound) - fills its option rows with solid
  # bright-green streaked blocks and doubles the row labels. Everything drawn
  # opaquely in the same frame is CORRECT: the heading, the description box, the
  # Normandy loading backdrop, the layout.
  #
  # WHAT IS ACTUALLY HAPPENING. The green block is not corruption of one draw:
  # it is the row-selection HIGHLIGHT BAR, drawn correctly, that is never
  # erased. Hover rows 1..5 in turn and you are left with FIVE green bars, one
  # per visited row; the streaks inside them and the doubled labels are the
  # same accumulation of the slide-in animation's intermediate positions. The
  # frame is never cleared, so every alpha-blended Scaleform draw composites on
  # top of the history of every earlier frame that landed in the same D3D9 back
  # buffer. Opaque draws overwrite that history, which is exactly why the
  # surrounding art looks right.
  #
  # THE DRAW PATH, from a WINEDEBUG=+d3d9 call trace of a full session
  # (37674 presented frames). A frame on the difficulty screen is 17 traced
  # calls end to end:
  #   SetRenderTarget idx 0, surface <backbuffer>      (x3, with SetViewport)
  #   Clear flags 0x4   = D3DCLEAR_STENCIL only        (x2, GFx mask stencil)
  #   ... Scaleform draws ...
  #   SetRenderTarget idx 0, surface <backbuffer>      (x2)
  #   Present
  # The render target is the BACK BUFFER for the entire frame, there is no
  # scene, no offscreen target, no post-process chain, and - decisively - NO
  # D3DCLEAR_TARGET. Compare a main-menu frame, which renders correctly: 62
  # traced calls, the scene goes to offscreen targets (Clear flags 0x6 =
  # ZBUFFER|STENCIL twice, plus one flags 0x1 colour clear of a post-process
  # target to 0x00000000), and the back buffer is then fully overwritten by the
  # opaque post-process resolve. That resolve, not a clear, is what keeps the
  # back buffer honest everywhere else in the game.
  #
  # The engine DOES own a back-buffer colour-clear path - 3097 Clear calls with
  # flags 0x1 and colour 0xff000000 bound to the back buffer across the session
  # - but it only runs during Bink playback and UE3 transition screens. Bucketed
  # over the session the clear rate is 70% at startup, 88%/63% through the intro
  # reel, 44% across the New Game transition, and exactly 0% from the moment the
  # difficulty screen appears onward. So the menu path deliberately relies on
  # the back buffer coming back blank.
  #
  # WHY IT COMES BACK DIRTY HERE. DXVK's own log for our device:
  #   Width 1280, Height 720, Format A8R8G8B8, Auto Depth Stencil false,
  #   Windowed false, Swap effect 1 = D3DSWAPEFFECT_DISCARD, 1 back buffer.
  # D3DSWAPEFFECT_DISCARD leaves the back buffer's contents UNDEFINED after
  # Present, and Windows drivers hand back something blank, which is what ME2
  # was shipped against. Neither wine D3D9 backend does: the app-visible back
  # buffer is always a private image that gets blitted into the swapchain, so
  # its contents survive. DXVK rotates between its 2 buffers in fullscreen
  # (which is why two consecutive xwd grabs of a frozen screen differ - each
  # buffer carries its own frame history) and, per the comment in
  # d3d9_swapchain.h SwapWithFrontBuffer(), deliberately emulates COPY for
  # windowed DISCARD with 1 back buffer. Both branches were tested. Both
  # accumulate.
  #
  # BLAST RADIUS, measured in a real playthrough (New Game -> difficulty ->
  # opening cinematic -> Lazarus Station, playable):
  #   AFFECTED  every full-screen Scaleform menu, i.e. the New Game difficulty
  #             screen and the pause-wheel Options screen. In the latter the
  #             pause wheel behind it ghosts too (Codex/Codex, Main Menu/Main
  #             Menu, Resources four times), because opening a full-screen menu
  #             stops world rendering and with it the post-process resolve.
  #   CLEAN     all 3D rendering, and every Scaleform element drawn OVER a live
  #             world: the dialogue wheel and subtitles in the opening
  #             conversation, and the pause "Mission Computer" wheel itself, all
  #             render crisply with the world visible behind them. Gameplay,
  #             cinematics and the main menu are unaffected.
  #
  # RULED OUT - do not re-test any of these, every one was a capture-verified
  # run against the same screen:
  #   - IT IS NOT DXVK AND NOT RADV. PROTON_USE_WINED3D=1 corrupts IDENTICALLY,
  #     with wine's builtin files/lib/wine/i386-windows/d3d9.dll loaded and
  #     libGL/libGLX_mesa mapped, i.e. a completely different translation layer
  #     on a completely different driver stack. Two independent D3D9
  #     implementations, one on Vulkan and one on OpenGL, same artefact.
  #   - No DXVK per-app profile is being missed or mis-keyed: the d3d9.dll in
  #     GE-Proton11-1 is dxvk v2.7.1-822-g8c9b4822d and its built-in profile
  #     table has an entry for MassEffectAndromeda.exe and NONE for
  #     MassEffect2.exe.
  #   - The d3d9/dxvk option space. Fourteen options applied at once via
  #     DXVK_CONFIG - presentInterval=1, maxFrameLatency=1,
  #     deferSurfaceCreation, lenientClear, extraFrontbuffer,
  #     floatEmulation=Strict, forceSamplerTypeSpecConstants,
  #     cachedWriteOnlyBuffers, forceDrawTimeBufferUpload, memoryTrackTest,
  #     supportDFFormats=False, supportX4R4G4B4=False,
  #     dxvk.enableImplicitResolves=False, samplerAnisotropy=16 - changed
  #     nothing. DXVK_CONFIG was proven to be reaching DXVK in the same setup by
  #     asking for dxvk.hud and reading "DXVK v2.7.1-822-g8c9b4822" back off the
  #     game window, so this is a real negative and not a plumbing failure.
  #     Nothing in that namespace can help anyway: DXVK cannot discard a back
  #     buffer it owns.
  #   - GPU spoofing. d3d9.customVendorId=1002 / customDeviceId=9440 (Radeon HD
  #     4870) with GamerSettings.ini deleted so ME2 re-ran its AppCompat probe
  #     moved CompatLevelGPU/Composite from 3 to 5 - confirmed in the regenerated
  #     [AppCompat] block - and made no difference. ME2's GPU database
  #     (BIOCompat.ini inside Coalesced.ini) does not know device 0x1114.
  #   - Presentation mode. Fullscreen=False + BorderlessWindow=True in
  #     GamerSettings.ini, which is what makes DXVK take the non-rotating
  #     COPY-emulation branch: identical corruption.
  #   - The game's render settings. Eleven applied at once in
  #     [SystemSettings] - ScreenPercentage=99 with UpscaleScreenPercentage,
  #     MaxMultisamples=4, OneFrameThreadLag=False, DepthOfField, Bloom,
  #     Distortion, LensFlares, FloatingPointRenderTargets, DynamicShadows,
  #     DynamicLights: no change. The full shipped default set lives in
  #     BioGame/Config/PC/Cooked/Coalesced.ini, not in DefaultEngine.ini.
  #   - [Engine.GameEngine] m_bPlayScaleformOverLevelLoads. Setting it false in
  #     BioGame/Config/DefaultEngine.ini is a NO-OP (the cooked Coalesced.ini
  #     copy wins); doing it properly in Coalesced.ini does not fix the screen,
  #     it DELETES it - the New Game flow bounces straight back to the main
  #     menu. That is the proof that this screen IS the Scaleform-over-level-load
  #     overlay, so the switch can never be the fix.
  #   - A missing loading movie. [BIOGame.Movies] NewGameLoadingMovie=load_f80.bik
  #     and the tree ships only load_f80_INT.bik / load_f80_ESN.bik, so this
  #     looked like an install step we skip. Providing an unsuffixed
  #     load_f80.bik changed nothing; the engine resolves the localised name by
  #     itself and the visible backdrop is the Scaleform LoadingSFMovie anyway.
  #   - `-log`. Removed as a throwaway diagnostic (never committed): identical
  #     corruption, so the audio fix is not implicated and must stay. It was
  #     already excluded on the data anyway - the main menu renders its full
  #     scene in the same process with conhost holding wine's foreground window.
  #   - Not a capture artefact: the operator sees it on their own seat, and the
  #     frames here were grabbed with xwd against the game window id (xwd -root
  #     fails BadMatch under gamescope).
  #   - The hex/honeycomb pattern on the Continue button is NOT a defect. It is
  #     ME2's normal button art - the main menu's "Are you sure you wish to
  #     exit?" Yes/No buttons show the same pattern on a frame that is otherwise
  #     perfect.
  #
  # THE FIX, and why it lives in a patched DLL. This is a shared D3D9-emulation
  # gap rather than a DXVK regression or a driver bug: DXVK deliberately keeps
  # the app-visible back buffer's contents when the swap chain has a single back
  # buffer (its own comment in d3d9_swapchain.cpp says games rely on that), and
  # wined3d keeps them too, while Windows drivers hand back an undefined -- in
  # practice blank -- surface for D3DSWAPEFFECT_DISCARD. So the runtime, not the
  # game and not this wrapper, is where it has to be corrected:
  # dxvk-2.7.1-d3d9-discard-backbuffer.patch clears the back buffer after a
  # successful Present when the swap effect is DISCARD, gated on
  # DXVK_D3D9_DISCARD_BACKBUFFER=1 so the DLL stays a drop-in replacement for
  # every other game. Opt-in is not optional here: DXVK issue #1368 is the
  # mirror image, a game that broke when DXVK stopped preserving the buffer,
  # which is presumably why preserving is the default.
  #
  # A/B, one variable, same DLL (2.7.1 in the HUD both times, i.e. this build
  # and not GE-Proton's 2.7.1-822): launch, New Game, Male, then walk the
  # pointer down the five option rows.
  #   flag off -> all five rows end up solid green, labels doubled
  #               (strom-handoff/me2-shots/off-1.png)
  #   flag on  -> only the hovered row is highlighted, labels crisp, backdrop
  #               black the way a blank DISCARD buffer makes it on Windows
  #               (strom-handoff/me2-shots/on-1.png)
  # No regression on the paths that were already clean: the 3D main menu still
  # renders its scene and panels (on-mainmenu.png), and the loading screen's
  # art comes back correct instead of smeared.
  #
  # Upstreaming is still the right long-term home: the same change as a DXVK
  # app profile keyed on MassEffect2.exe would drop the patch and the env flag
  # from this file.
  #
  # Captures: ~/.claude/outputs/me2-ui-glitch/frames/ - BEFORE-dxvk-stock.png
  # (pixel-identical to the operator's report), AB-wined3d.png, T-screening.png,
  # T1-windowed.png, T3-gamescreen.png, T7-gpuspoof.png,
  # AFTER-ingame-options.png, and the clean counter-examples G-20.png (dialogue
  # wheel over a live world) and H-hud2.png (pause wheel over a live world).
  src = fetchIpfs {
    cid = "QmXTrjMzTCVz8Hm6nkBQDAV4iHemQqYYmsrL8qeR4pMB15";
    fallbackUrl = "https://archive.org/download/mass-effect-2_202509/ME2.7z";
    hash = "sha256-xt1fZ10qV2kCcvoQgausKLwAInikGnqVFq8uDYvKVHU=";
    name = "mass-effect-2-eu-retail-2disc.7z";
  };

  # ViTALiTY release vty-0293, "Mass Effect 2 Update 1.01 (c) EA /
  # Protection: Disc-Check" - the 1.01 executable with the authenticator
  # above neutralised. 3.7 MB .7z carrying exactly three files
  # (MassEffect2.exe, update.txt, vitality.nfo), so p7zip unpacks it
  # non-interactively: no patcher GUI, no installer.
  #   archive.org item vty-0293.7z ("Mass Effect 2 No-CD patch", 2010-02-22)
  #   sha256 17631d8bdcd3ff13c95a90a6e07a3352ae4d37c45815aaa8427826365605ebd8
  #   md5    b1bc03b95d6db05a1b01aa238f5e8e1e (matches the item's own md5)
  #
  # What was verified statically against our retail exe before shipping it:
  #   - version resource 1.1.1599.0 / "01599.00", link stamp 2010-02-16,
  #     Internal/Original name "Mass Effect 2"/"BioGame.exe", CompanyName
  #     BioWare, same LTCG-BioGame.pdb path -> a genuine BioWare ME2 build,
  #     namely the one the official 1.01 update shipped (the release's
  #     update.txt is EA's 1.01 changelog verbatim). Ours is 1.0.1593.2 /
  #     "01593.02", stamped 2009-12-16.
  #   - identical section layout: .text/.rdata/.data/.rsrc/.reloc and nothing
  #     else, so no protection wrapper was added. For contrast the official
  #     1.02 update's exe (build 01604.00) carries three extra nameless
  #     sections and imports only kernel32+user32 - that one IS wrapped.
  #   - byte-identical import surface: the same 30 DLLs and the same function
  #     set as our retail exe, set-difference empty in both directions. No
  #     SecuROM/Sony-DADC/activation import was added and none removed, so the
  #     change is a code patch inside the authenticator, not a shim.
  #
  # Pairing a 01599.00 exe with 01593.02 cooked content is safe: the 1.0x
  # patches do not touch the package ABI. Both our BioGame/CookedPC/
  # SFXGame.pcc and the one in the official 1.02 update carry UE3 package
  # version 512 / licensee version 130 and differ by 1443 bytes out of
  # 20449498, i.e. content bugfixes only. Confirmed in a launch: the engine
  # loads the 1.0 cook and renders its Scaleform frontend with no version
  # complaint.
  #
  # The displaced retail executable stays in the output as
  # Binaries/MassEffect2.exe.retail-01593.02 so the swap is auditable and
  # reversible.
  noCdExe = fetchurl {
    url = "https://archive.org/download/vty-0293.7z/vty-0293.7z";
    hash = "sha256-F2Mdi9zT/xPJWpCm4HozUq5NN8RYFaqoQngmNlYF69g=";
    name = "mass-effect-2-vty-0293-nodvd.7z";
  };
  # Official ME2 DLC, all 23 of them. EA made the entire set free on
  # 2022-07-13 and still serves it unauthenticated; 15 are additionally
  # mirrored on archive.org byte-identically (md5s checked against EA's
  # CDN), which is what the fallbackUrls point at where one exists.
  #
  # Each is an NSIS self-extractor wrapping either a STORED RAR4 whose
  # paths are already BioGame/DLC/<TAG>/CookedPC/..., or (for the three
  # 2010-12+ ones) that same tree loose in the NSIS payload. Both are
  # plain extractions -- ME2 PC DLC is loose-file, there is no .sfar
  # anywhere (that is ME3), so nothing here runs an installer.
  dlcInstallers = [
    {
      tag = "DLC_CER_02";
      label = "Aegis Pack";
      src = fetchIpfs {
        cid = "QmQYMwqDgBm9hju4GBcmuHCuBKGaiYiNUUr8FZqxqvvYPu";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_AegisPack.exe";
        hash = "sha256-4nAoWDtnG7rF98mvXtrCQT9HSa+5SqLNAHjlGA+Z7rU=";
        name = "ME2_AegisPack.exe";
      };
    }
    {
      tag = "DLC_CER_Arc";
      label = "Arc Projector";
      src = fetchIpfs {
        cid = "QmZ8YUQiMnsK5va7hWejzqsSZDnEX1cggJNrC3xpEFQP18";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_CerberusArc.exe";
        hash = "sha256-a4hcLFLysbUDUP006GYmD/0NNcNqGMz90JabCvVG8f4=";
        name = "ME2_CerberusArc.exe";
      };
    }
    {
      tag = "DLC_CON_Pack01";
      label = "Alternate Appearance Pack 1";
      src = fetchIpfs {
        cid = "QmU1SfdK3dyZ4HGDfhk387SGuMR8JoiPcXPKCx7g5LnedS";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_AltAppearance1-1.exe";
        hash = "sha256-BEq6d4PnH2HOaOpMOhjBDwf1QYBe+fn11PXe3tFfVaU=";
        name = "ME2_AltAppearance1-1.exe";
      };
    }
    {
      tag = "DLC_CON_Pack02";
      label = "Alternate Appearance Pack 2";
      src = fetchIpfs {
        cid = "QmX3SqxcokKjCE6kPnx3jkmVsoMhUzEiTXR7i4D1Mf6aBu";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_AltAppearance2.exe";
        hash = "sha256-PJpq1iJEWUnGJVXzCA0VSVDFwbqdarnxfdCShTaUq8s=";
        name = "ME2_AltAppearance2.exe";
      };
    }
    {
      tag = "DLC_DHME1";
      label = "Genesis interactive comic";
      src = fetchIpfs {
        cid = "QmaERFGgZzTQzLwv26aoHh7pKv6azx1mXoPmDdy3oyQBwW";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Genesis.exe";
        hash = "sha256-g4XLkvmkcRIxM6PYqXRUKB7BytJultn8nWoF0Y7BZdo=";
        name = "ME2_Genesis.exe";
      };
    }
    {
      tag = "DLC_EXP_Part01";
      label = "Lair of the Shadow Broker";
      src = fetchIpfs {
        cid = "QmcEKj1N8jZeHJDpmr9mekDjT9ZEfqQrXk5XjL61YzYTUY";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_ShadowBroker.exe";
        hash = "sha256-z9+u7iIDf266WkttJlR2vS2jHBjn0qSvpRopizAiaLk=";
        name = "ME2_ShadowBroker.exe";
      };
    }
    {
      tag = "DLC_EXP_Part02";
      label = "Arrival";
      src = fetchIpfs {
        cid = "QmSsR7Sb4ebkm98dV4jZ1DGCJwxryZPF99p7UMbisv9uSz";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Arrival.exe";
        hash = "sha256-GEk+5Eig4nKUf1zdzLtvvQ7DMOCV/4MfSFRgMvggzMY=";
        name = "ME2_Arrival.exe";
      };
    }
    {
      tag = "DLC_HEN_MT";
      label = "Kasumi - Stolen Memory";
      src = fetchIpfs {
        cid = "QmSR3W1FkDQPJJwC5fbCuCNV3qRuUb2DWErnWWeZ9VMkEL";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Kasumi.exe";
        hash = "sha256-7D5Lud2UcOo1rsm/rNJjcFoOStJXi3yh6WBtdUj0xkg=";
        name = "ME2_Kasumi.exe";
      };
    }
    {
      tag = "DLC_HEN_VT";
      label = "Zaeed - The Price of Revenge";
      src = fetchIpfs {
        cid = "QmeywETUQB8RewWY7UYdckxwDHt8mvh7G4qsMZR3EJJXR9";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Zaeed.exe";
        hash = "sha256-3xPyJp2VqXmlj5D1FzS6PRLEhUShsdi5fU8iH/Rh44I=";
        name = "ME2_Zaeed.exe";
      };
    }
    {
      tag = "DLC_MCR_01";
      label = "Firepower Pack";
      src = fetchIpfs {
        cid = "QmRkysBNF2K8aq3Jy26R4bNqp2yaLaVg58jStVNEnCRsAR";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_FirepowerPack.exe";
        hash = "sha256-bOV++KHJjmampqiIFl38EVhn9Ac5pbiow0Y6Gw7xv60=";
        name = "ME2_FirepowerPack.exe";
      };
    }
    {
      tag = "DLC_MCR_03";
      label = "Equalizer Pack";
      src = fetchIpfs {
        cid = "QmPcMAnHE2778HvgP45yd3h97RN8Xm4gE632HFd37cHomj";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_EqualizerPack.exe";
        hash = "sha256-ts+InTbpTQP2jJTqyX/Rpb3wnfI1QZF2Xf489FY0LCw=";
        name = "ME2_EqualizerPack.exe";
      };
    }
    {
      tag = "DLC_PRE_Cerberus";
      label = "Cerberus Weapon and Armor";
      src = fetchIpfs {
        cid = "QmeASxdM4auxyCWrEKh6nk6ZwaTAk4YwnAxPtgR9HT3aDe";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_CerberusWpnArmor.exe";
        hash = "sha256-7yCsv7yjcqWnbKedi5ENXM/SPb+BSAccA15MqfvKTNI=";
        name = "ME2_CerberusWpnArmor.exe";
      };
    }
    {
      tag = "DLC_PRE_Collectors";
      label = "Collectors Weapon and Armor";
      src = fetchIpfs {
        cid = "QmRcKT5DsYtTV4yapYDV2eMXESrk5xfp26d1dqegpALrxP";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_Collectors.exe";
        hash = "sha256-B22UevfVkf0wEPe1D4/Acyji312QyYxB/btAJDnT0H8=";
        name = "ME2_Collectors.exe";
      };
    }
    {
      tag = "DLC_PRE_DA";
      label = "Blood Dragon Armor";
      src = fetchIpfs {
        cid = "QmQonmU7t9txGUBK5yd4D2RqY18xxCEfLupfDsm6EwGwmL";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_BloodDragon.exe";
        hash = "sha256-Vmx4wfoxEHPbeee7/HxqjjdMtT92kcoLK1Q2G4niU3Q=";
        name = "ME2_BloodDragon.exe";
      };
    }
    {
      tag = "DLC_PRE_Gamestop";
      label = "Terminus Weapon and Armor";
      src = fetchIpfs {
        cid = "QmP2MUFGFiGpnN1q7BgdxYvcNC5y54FBbjLEcdmvwzAwRf";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_Terminus.exe";
        hash = "sha256-IUTd1JB+BUF8Xzh0sPNhtoiFPDF+bXeHn/eS/2GXctI=";
        name = "ME2_Terminus.exe";
      };
    }
    {
      tag = "DLC_PRE_General";
      label = "Inferno Armor";
      src = fetchIpfs {
        cid = "QmXZxRQrQsmmHaeeU3NKSV3jwfPPvysi66NF5H7VKgozby";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_Inferno.exe";
        hash = "sha256-IDMvYQU0oOEbx3orHhJ3rkOHPBuQOg3s05yKIbSb7d4=";
        name = "ME2_Inferno.exe";
      };
    }
    {
      tag = "DLC_PRE_Incisor";
      label = "Incisor Sniper Rifle";
      src = fetchIpfs {
        cid = "QmV9Kzz87bqQ7mDQsx96wVY4mfCfScGHrEKmdaVB5dsES9";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_Incisor.exe";
        hash = "sha256-oneGnSOtZ5gc4CvFp9SI7AuOMASVd8oqgXqunNm38Hg=";
        name = "ME2_Incisor.exe";
      };
    }
    {
      tag = "DLC_PRO_Gulp01";
      label = "Sentry Interface";
      src = fetchIpfs {
        cid = "Qmb8dEqBdrkGwc2NEQ6vNf1HeoB2zXVaBGAhddc4A6Uffj";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_Sentry.exe";
        hash = "sha256-FnwpMAdbHx7vGl7V4+0N+AXCm01SofOPzvTv/PT6IvU=";
        name = "ME2_Sentry.exe";
      };
    }
    {
      tag = "DLC_PRO_Pepper01";
      label = "Umbra Visor";
      src = fetchIpfs {
        cid = "QmaZNAh5jJJDfAVZsCcbDNcSiGaLMpXHgSzKF2g8esUrD1";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_UmbraVisor.exe";
        hash = "sha256-Qm6Gll42/oYyZJt2sfT2gAY7pTnD0ulZUXdnRaBsytg=";
        name = "ME2_UmbraVisor.exe";
      };
    }
    {
      tag = "DLC_PRO_Pepper02";
      label = "Recon Hood";
      src = fetchIpfs {
        cid = "QmXGECmgPvJxkyC2gUzrG6CBxwY7ZAtrUWNLWZWn1X3L6p";
        fallbackUrl = "https://eaassets-a.akamaihd.net/bioware/u/f/eagames/bioware/masseffect2/ME2_DLC/ME2_ReconHood.exe";
        hash = "sha256-s/yrZU7268A+RUGhJi1CHm1m6JX/lbYw488WB8lbkWY=";
        name = "ME2_ReconHood.exe";
      };
    }
    {
      tag = "DLC_UNC_Hammer01";
      label = "Firewalker Pack";
      src = fetchIpfs {
        cid = "QmWhJ66s9JSsz6a69gbWorJtEpk4FNc2Tn1Aqsek3AJocN";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Hammerhead.exe";
        hash = "sha256-9SC3PREhLuNr275Kswx3ZFRlFHjzYAddFUyxsvqHZXE=";
        name = "ME2_Hammerhead.exe";
      };
    }
    {
      tag = "DLC_UNC_Moment01";
      label = "Normandy Crash Site";
      src = fetchIpfs {
        cid = "QmTex3DMRSqBUhhdMnEd1m52tkjHvf4HTm9w2NeTVzQuRq";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_NormandyCrash.exe";
        hash = "sha256-fmSAhoQ/qiL+MRG825wW+YD0Wh/kqzjW6p1+IHn7CLY=";
        name = "ME2_NormandyCrash.exe";
      };
    }
    {
      tag = "DLC_UNC_Pack01";
      label = "Overlord";
      src = fetchIpfs {
        cid = "Qmb2vf4DXrWUmuGUmkKsvqRz5FbxN5cNm9vHFVy6bpuvR6";
        fallbackUrl = "https://archive.org/download/mass-effect-dlc/ME2_Overlord.exe";
        hash = "sha256-xVjj29apmatVacrTVo9nPckD4nOUdmZ2rLjMh+7iCc8=";
        name = "ME2_Overlord.exe";
      };
    }
  ];

  # The entitlement gate. Dropping DLC folders in is necessary but not
  # sufficient: MassEffect2.exe carries EA's Cerberus Network entitlement
  # stack (IsCerberusMember / HasCerberusDLC / CheckEntitlement /
  # StartCerberusLogin), hashes each DLC's INI/PCC files into
  # BioPersistentEntitlementCache.ini keyed by LastNucleusID, and refuses
  # what it cannot authorise -- "Unable to authorize the listed DLC".
  #
  # Erik-JS/masseffect-binkw32 is the standard answer and is a pure DLL
  # drop, matching how this repo handles DRM elsewhere: binkw32.dll becomes
  # a proxy that forwards to the renamed original (binkw23.dll) and patches
  # the authorisation routine in memory to return "authorised". It scans
  # .text for a pop/add-esp/ret 0xC epilogue and rewrites the tail as
  # `mov eax,1; ret 0xC`. Verified against the exe this recipe ships: the
  # pattern occurs EXACTLY ONCE, at file offset 0x55881B. No server, no
  # login, no network. It also brings an ASI loader along.
  binkw32Proxy = fetchurl {
    url = "https://github.com/Erik-JS/masseffect-binkw32/releases/download/r4/me2_binkw32.zip";
    hash = "sha256-kelJbEl5PDt7oF2ynHd6Ljr7H1NUE5GXrk/qjMW+UN0=";
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mass-effect-2";

  inherit src;

  nativeBuildInputs = [
    cabextract
    p7zip
    unar
  ];

  # p7zip reads both the outer 7z and the ISO9660/Joliet images, but it
  # cannot open these RAR4 archives ("Can not open the file as archive"),
  # so the payloads go through unar. `-D` is required: apps.rar and the
  # data0N.rar family have several top-level entries, and without it unar
  # wraps each extraction in a containing directory named after the archive.
  buildScript = ''
    mkdir -p "$out"

    7z x -y -o"$TMPDIR/iso" "$src" 'ME2/MassEffect2.iso' 'ME2/ME2_Disc2.iso' >/dev/null

    # Disc 1: engine binary, prerendered movies, NVIDIA PhysX redist, and
    # DataSetup.exe -- see the BIOG_UIWorld note further down for why that
    # last one is not optional.
    7z x -y -o"$TMPDIR/rar" "$TMPDIR/iso/ME2/MassEffect2.iso" \
      'data/exe.rar' 'data/movies.rar' 'data/DataSetup.exe' \
      'software/PhysX_9.09.0814_SystemSoftware.exe' >/dev/null
    rm -f "$TMPDIR/iso/ME2/MassEffect2.iso"

    # Disc 2: English VO/text, maps, launcher+redist DLLs, bulk data.
    7z x -y -o"$TMPDIR/rar" "$TMPDIR/iso/ME2/ME2_Disc2.iso" \
      'data/english.rar' 'data/maps.rar' 'data/apps.rar' \
      'data/data01.rar' 'data/data02.rar' 'data/data03.rar' \
      'data/other.rar' 'data/dialog.rar' >/dev/null
    rm -f "$TMPDIR/iso/ME2/ME2_Disc2.iso"

    # Unpack in installmanifest_en.ini order, dropping each archive as it
    # lands so peak build disk stays near the installed size rather than
    # twice it.
    for r in exe movies english maps apps data01 data02 data03 other dialog; do
      unar -q -D -f -o "$out" "$TMPDIR/rar/data/$r.rar" >/dev/null
      rm -f "$TMPDIR/rar/data/$r.rar"
    done
    chmod -R u+w "$out"

    # Swap in the disc-check-free 1.01 executable, keeping the retail one
    # beside it (see noCdExe above for provenance and what was verified).
    7z x -y -o"$TMPDIR/nocd" "${noCdExe}" 'MassEffect2.exe' >/dev/null
    mv "$out/Binaries/MassEffect2.exe" \
      "$out/Binaries/MassEffect2.exe.retail-01593.02"
    install -m644 "$TMPDIR/nocd/MassEffect2.exe" "$out/Binaries/MassEffect2.exe"

    # Patched DXVK d3d9.dll next to the executable. Wine resolves an implicit
    # import from the application directory before the prefix's system32/
    # syswow64, so this shadows the DXVK that Proton installs -- for THIS game
    # only, without touching the prefix or any other title. Same 2.7.1 DXVK,
    # one behaviour flipped; see dxvkDiscardBackBuffer above.
    install -m644 "${dxvkDiscardBackBuffer}/bin/d3d9.dll" "$out/Binaries/d3d9.dll"

    # SKU descriptor. Binaries/MassEffect2.exe reads
    # HKLM\SOFTWARE\BioWare\Mass Effect 2 "Flavour" and falls back to
    # ..\Data\SKU.ini's [SKU] Flavour / VOLanguage / TextLanguage. The retail
    # Setup.exe writes both, and none of the ten RAR payloads carries a
    # SKU.ini, so without this the engine has neither source. The values are
    # exactly what disc 1's data/installmanifest_en.ini declares for this SKU
    # (Build=1593.02, TextLanguage=INT, VOLanguage=INT); "01593.02" is also
    # the flavour string hardcoded in the engine binary immediately next to
    # that registry lookup.
    printf '%s\n' '[SKU]' 'Flavour=01593.02' 'VOLanguage=INT' 'TextLanguage=INT' \
      > "$out/data/SKU.ini"

    # BIOG_UIWorld.pcc: the file the ten RAR payloads do not carry, and
    # without which character creation crashes. Traced end to end:
    #
    #   Coalesced.ini [SFXGame.BioUIWorld] m_sMapFile=BIOG_UIWorld names the
    #   world the character creator renders Shepard into. The creator's setup
    #   method (0x00B41210) copies that name out of its own +0x3C FString and
    #   calls the world factory at 0x0093E470; the factory's first act is an
    #   empty-string / cannot-open check, so a missing package makes it
    #   return NULL. The caller then takes the early exit at 0x00B412BE and
    #   leaves the object's +0xB0 slot NULL -- silently, no error surfaced.
    #   Any later method of that class locks it:
    #     0x00B41438  mov 0xb0(%esi),%eax    ; NULL
    #     0x00B4143E  lea 0x4(%eax),%edi     ; 0+4
    #     0x00B4144A  call TryEnterCriticalSection
    #   which writes at 4+4 and takes an access violation on address 0x8.
    #   That is the "quits right after the Lazarus revival" crash: the dump's
    #   only game-side strings are SetupCharCreate / CharCreateSpawnPoint /
    #   HMM_GUI_Soldier, and WINEDEBUG=+file shows the engine's last act is
    #   CreateFileW(L"BIOG_UIWorld") failing.
    #
    # The ten RARs do not carry it, but the DISC does: it is the sole payload
    # of data/DataSetup.exe, a 578,714-byte NSIS stub that retail Setup.exe
    # runs AFTER the RAR install. installmanifest_en.ini declares
    # NumberOfFiles=10 and never mentions DataSetup.exe, which is exactly why
    # a manifest-driven extraction misses it -- and why players who unpack
    # the RARs by hand have been missing this one file since 2010.
    #
    # 482,737 bytes, md5 dcc5c358283c37e5fe60547413cb21b7, UE3 package
    # version 512 / licensee 130 (same as the tree's own packages). Matches
    # MassEffectModderLegacy's vanilla ME2 database entry for
    # \BioGame\CookedPC\BIOG_UIWorld.pcc exactly. Present byte-identically on
    # both EU discs, and the USA/Asia SKU carries an equivalent copy.
    #
    # Note ME3's BIOG_UIWorld.pcc is NOT a substitute: it is UE3 version 684
    # / licensee 194 and cannot load in this 512/130 engine.
    7z e -y -o"$out/BioGame/CookedPC" "$TMPDIR/rar/data/DataSetup.exe" \
      BIOG_UIWorld.pcc -r >/dev/null
    test -s "$out/BioGame/CookedPC/BIOG_UIWorld.pcc"
    test "$(stat -c%s "$out/BioGame/CookedPC/BIOG_UIWorld.pcc")" -eq 482737

    # DLC. Every installer is an NSIS self-extractor; inside is either a
    # RAR whose entries are already BioGame/DLC/<TAG>/..., or that tree
    # loose in the NSIS output. Handle both, and fail loudly rather than
    # silently shipping a game missing a squadmate.
    installDlc() {
      local exe="$1" tag="$2" rar bg
      rm -rf "$TMPDIR/dlcx"; mkdir -p "$TMPDIR/dlcx"
      7z x -y -o"$TMPDIR/dlcx" "$exe" >/dev/null 2>&1 || true
      rar=$(find "$TMPDIR/dlcx" -iname '*.rar' -print -quit)
      if [ -n "$rar" ]; then
        unar -q -D -f -o "$out" "$rar" >/dev/null
      else
        bg=$(find "$TMPDIR/dlcx" -type d -iname 'BioGame' -print -quit)
        if [ -z "$bg" ]; then
          echo "$tag: no RAR and no BioGame tree in $exe" >&2
          exit 1
        fi
        mkdir -p "$out/BioGame"
        cp -r --no-preserve=mode,ownership "$bg/." "$out/BioGame/"
      fi
      rm -rf "$TMPDIR/dlcx"
      # Mount.dlc is what the engine scans for; no Mount, no DLC.
      if [ ! -s "$out/BioGame/DLC/$tag/CookedPC/Mount.dlc" ]; then
        echo "$tag: installed but has no CookedPC/Mount.dlc" >&2
        exit 1
      fi
    }

    ${lib.concatMapStrings (d: ''
      installDlc ${d.src} ${d.tag}
    '') dlcInstallers}

    test "$(ls "$out/BioGame/DLC" | wc -l)" -eq ${toString (builtins.length dlcInstallers)}

    # Entitlement proxy: rename the stock bink to the name the proxy
    # forwards to, then take the proxy's binkw32.dll. The zip also carries
    # its own copy of the original; assert ours is that same 171,008-byte
    # file so a tree change cannot silently leave a mismatched pair.
    test "$(stat -c%s "$out/Binaries/binkw32.dll")" -eq 171008
    7z e -y -o"$TMPDIR/bink" ${binkw32Proxy} >/dev/null
    mv "$out/Binaries/binkw32.dll" "$out/Binaries/binkw23.dll"
    install -m644 "$TMPDIR/bink/binkw32.dll" "$out/Binaries/binkw32.dll"
    test "$(stat -c%s "$out/Binaries/binkw32.dll")" -eq 113152

    # NVIDIA PhysX System Software 9.09.0814, from disc 1's software/.
    # MassEffect2.exe LoadLibrary()s PhysXLoader.dll during startup and pops a
    # modal "Failed to initialize the physics system. Please ensure you have an
    # updated version of the PhysX System Software installed." when the runtime
    # is absent (observed on the first headless run) - the retail Setup.exe
    # runs this redist and we cannot. It is a Wise installer whose payload is
    # an MS cabinet in its .WISE section, carrying one PhysXCore/NxCooking pair
    # per shipped SDK generation, suffixed with the installer component GUID.
    #
    # The core must match the SDK the game was built against: ME2's own
    # Binaries/NxCooking.dll and PhysXExtensions.dll are Epic's PhysX 2.8.0
    # build (`.../EpicPhysX/Epic/2.8.0_FC7/...pdb` in their string tables), so
    # GUID 7ED65BD8 is the right core - 2.8.0.24, established by parsing every
    # cabinet DLL's VS_FIXEDFILEINFO (the neighbouring 6CB22D51 is 2.8.1.33,
    # the generation games/risen needs). A mismatched core loads but fails
    # NpCreatePhysicsSDK's version handshake and reproduces the same dialog.
    #
    #   Binaries/  : PhysXLoader.dll + PhysXDevice.dll, resolved out of the exe
    #                directory by the game's own LoadLibrary, plus a
    #                PhysXCore/physxcudart copy for the loader's
    #                enableLocalPhysXCore branch (a bare
    #                LoadLibraryA("PhysXCore.dll"), so the exe directory wins).
    #   $out root  : PhysXCore.dll + physxcudart_20.dll staged for preRun to
    #                install inside the wineprefix at the registry-pointed
    #                path.
    7z x -y -o"$TMPDIR/physx-pe" \
      "$TMPDIR/rar/software/PhysX_9.09.0814_SystemSoftware.exe" >/dev/null
    mkdir -p "$TMPDIR/physx"
    cabextract -q -d "$TMPDIR/physx" \
      -F 'PhysXLoader.dll.EFBABE66*' \
      -F 'PhysXDevice.dll.EFBABE66*' \
      -F 'PhysXCore.dll.7ED65BD8*' \
      -F 'physxcudart_20.dll.8411CAB1*' \
      "$TMPDIR/physx-pe/.WISE"
    install -m644 \
      "$TMPDIR/physx/PhysXLoader.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/Binaries/PhysXLoader.dll"
    install -m644 \
      "$TMPDIR/physx/PhysXDevice.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/Binaries/PhysXDevice.dll"
    for __physxdest in "$out/Binaries" "$out"; do
      install -m644 \
        "$TMPDIR/physx/PhysXCore.dll.7ED65BD8_8C4A_4040_9194_D559408A0820" \
        "$__physxdest/PhysXCore.dll"
      install -m644 \
        "$TMPDIR/physx/physxcudart_20.dll.8411CAB1_77D8_41F8_B107_07F845725F8D" \
        "$__physxdest/physxcudart_20.dll"
    done

    test -f "$out/Binaries/MassEffect2.exe"
    test -f "$out/Binaries/MassEffect2.exe.retail-01593.02"
    test -f "$out/Binaries/PhysXLoader.dll"
    test -f "$out/Binaries/d3d9.dll"
    test -f "$out/BioGame/Config/DefaultEngine.ini"
  '';

  runtime = "proton";

  # Turns on the patched DXVK's Windows-style DISCARD behaviour. Without this
  # the shipped d3d9.dll behaves exactly like stock DXVK 2.7.1, so the flag and
  # the DLL are only meaningful together.
  env.DXVK_D3D9_DISCARD_BACKBUFFER = "1";

  # Binaries/MassEffect2.exe, not the root MassEffect2Launcher.exe: the
  # launcher is a separate windowed app that does the retail activation
  # check and then spawns the engine, so pointing at it would park a
  # blocking window in front of every launch (headless included).
  executable = "Binaries/MassEffect2.exe";

  # `-log` IS THE AUDIO FIX. It is not a debug leftover -- do not remove it.
  #
  # ME2's Wwise integration refuses to initialise without a non-NULL
  # GetForegroundWindow(). The UE3 audio-device init at 0x00973BA4 reaches
  # AK::SoundEngine::GetDefaultPlatformInitSettings (0x00DEBC40 ->
  # 0x00E1C310), which at 0x00E1C324 calls user32!GetForegroundWindow and
  # stores the result as AkPlatformInitSettings.hWnd. The caller then gates
  # on it: hWnd != 0 -> proceed; else the game-window global 0x0127D16C,
  # which is not created until much later in startup; else Sleep(100) and
  # re-poll for ~1.0 s; and finally at 0x00973CEF it logs and RETURNS
  # FALSE, so AK::SoundEngine::Init at 0x00973C67 is never called and the
  # process is mute for its whole life -- silently, with no dialog. ME2
  # imports no EnumWindows/GetWindowTextW/GetClassNameW, so unlike ME3
  # there is not even a splash-window fallback: GetForegroundWindow() is
  # the ONLY source of that HWND.
  #
  # Nothing in a fresh wine session under gamescope has ever been
  # activated, so wine's desktop foreground window is NULL and the gate
  # fails. On Windows the desktop always has some foreground window, ME2
  # hands that foreign HWND to Wwise, and DirectSound ignores it anyway
  # (wine warns "SetCooperativeLevel level=DSSCL_PRIORITY not fully
  # supported"), which is why any window at all is enough.
  #
  # UE3's `-log` spawns conhost.exe -- a real console window -- which makes
  # the desktop foreground window non-NULL during that ~1 s grace period.
  # So this flag satisfies the engine's precondition; the log output is the
  # incidental part.
  #
  # X INPUT FOCUS AND WINE'S FOREGROUND WINDOW ARE DIFFERENT THINGS, and
  # confusing them is the easy way to talk yourself out of this flag. Wine
  # keeps its own per-desktop foreground window; it is NULL until some wine
  # window is activated, and conhost showing its console is what sets it.
  # The X server's input focus is a separate thing and stays on the game:
  # with the console present, XTEST keys injected into the wine namespace
  # still reach the game (Return/space walk the title screen into the main
  # menu), and gamescope still composites the game, never the console. The
  # console is inert for input and for display, and load-bearing only for
  # that one HWND read.
  #
  # Verified over 4 consecutive cold headless runs. Each was measured on a
  # dedicated module-null-sink that only this game was routed to (PULSE_SINK
  # set from launch, so nothing else could contaminate it), captured with
  # parec s16le/48k/stereo and summarised with `sox -n stats`. Every run
  # reached the same state -- AkPlatformInitSettings.hWnd non-NULL, Wwise
  # pool id 3, g_pStreamMgr 0x0129ABB0, g_pSink 0x071A0C80 whose vtable is
  # 0x00FED1E8 (CAkSinkDirectSound, not the 0x00FED210 dummy sink) -- and
  # each produced a live "Mass Effect 2" sink-input carrying signal:
  #   Pk -24.09 / RMS -36.47 dBFS  (12.3 s, main menu)
  #   Pk -22.68 / RMS -36.31 dBFS  (12.3 s, main menu)
  #   Pk -15.62 / RMS -29.55 dBFS  (12.3 s, title screen)
  #   Pk -22.10 / RMS -35.85 dBFS  (14.3 s, main menu)
  # Without the flag, same method and same screens: no sink-input for the
  # game exists at all and the null sink reads Pk/RMS -inf, i.e. digital
  # silence. In every measured window the only DirectSound buffer still
  # being polled was Wwise's own; bink's movie buffers had already been
  # created and destroyed, which is what separates engine audio from the
  # intro-movie audio that always worked.
  #
  # Side effects: none observed. This is a FINAL_RELEASE UE3 build, so GLog is
  # compiled out -- Documents\BioWare\Mass Effect 2\BIOGame\Logs stays empty
  # with or without the flag, nothing lands on disk and startup time is
  # unchanged. gamescope keeps compositing the game and not the console: the
  # captured frames show the intro reel, the title screen and the main menu
  # exactly as before.
  #
  # Rejected alternatives, recorded so nobody has to re-derive them:
  #   - Patch the gate: NOP the 6-byte `je 0x00973C9A` at 0x00973C10
  #     (0f 84 84 00 00 00 -> 90 90 90 90 90 90) so the both-HWNDs-NULL case
  #     falls through to Init with hWnd=NULL. DirectSound ignores the HWND
  #     anyway, so this would probably work, but it is untested and patching
  #     the shipped exe to avoid one command-line flag is a bad trade.
  #   - A pkgsCross.mingw32 stub that takes foreground, launches the game as
  #     its child and drops its own window once the engine's window class
  #     appears. Real code and a new build input for the same one-bit
  #     effect; games/mass-effect-3 had one compiling and dropped it too.
  #
  # Symptom if this regresses: intro movies still have sound (that is
  # BINK's own DirectSound object via binkw32!_BinkOpenDirectSound, not the
  # engine) and everything afterwards is silent.
  executableArgs = [ "-log" ];

  # PhysXLoader.dll resolves the runtime as
  # <AGEIA "PhysXCore Path">\v<requested SDK>\{PhysXCore,PhysXCooking}.dll --
  # verified by disassembling the 9.09.0814 loader and then confirmed in a
  # WINEDEBUG=+module,+reg launch, which showed it read
  # HKLM\Software\Ageia Technologies "PhysXCore Path", loaded
  # C:\windows\syswow64\PhysX\v2.8.0\PhysXCore.dll, then failed on
  # ...\v2.8.0\PhysXCooking.dll with c0000135. The registry value is a
  # DIRECTORY; the loader appends \v2.8.0\ itself (2.8.0 = the SDK version
  # MassEffect2.exe requests). Wine's prefix has neither the key nor the DLLs,
  # so lay the layout down under syswow64\PhysX and stamp the key. Mirrors
  # games/risen and games/arcania (same redist family, same loader build),
  # including their one limitation: Proton creates the prefix during the launch
  # itself, so on a cold ~/.strom/.compatdata/mass-effect-2 the stamp lands
  # from the second launch onward.
  #
  # The cooking library the loader wants under that name is the game's own
  # Binaries/NxCooking.dll (Epic PhysX 2.8.0.7). The 9.09.0814 cabinet's 2.8.0
  # component calls its cooking DLL NxCooking.dll too -- only redists from
  # 9.10 onward ship it pre-named PhysXCooking.dll -- and using ME2's copy
  # keeps the cooking lib bit-identical to what the engine itself links,
  # instead of pairing it with a second stock 2.8.0.24 build.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    physxdir="$pfx/drive_c/windows/syswow64/PhysX"
    if [ -d "$pfx/drive_c/windows/syswow64" ] && [ -f "$STROM_OVERLAY/PhysXCore.dll" ]; then
      mkdir -p "$physxdir/v2.8.0"
      install -m0644 "$STROM_OVERLAY/PhysXCore.dll" "$physxdir/v2.8.0/PhysXCore.dll"
      install -m0644 "$STROM_OVERLAY/Binaries/NxCooking.dll" \
        "$physxdir/v2.8.0/PhysXCooking.dll"
      # PhysXCore.dll's import table binds physxcudart_20.dll, so co-locate it
      # next to the core and in syswow64 for any short-name LoadLibrary.
      install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" \
        "$physxdir/v2.8.0/physxcudart_20.dll"
      install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" \
        "$pfx/drive_c/windows/syswow64/physxcudart_20.dll"
    fi
    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -qF 'syswow64\\PhysX"' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wow6432Node\\\\Ageia Technologies] %s\n' "$(date +%s)"
        printf '"PhysXCore Path"="C:\\\\windows\\\\syswow64\\\\PhysX"\n'
        printf '"enableLocalPhysXCore"=dword:00000001\n'
      } >> "$SYSREG"
    fi
  '';

  # UE3 builds its user directory as
  # My Documents\BioWare\<MyDocumentsSubDirName>, where the vendor segment is
  # a literal in the engine binary and the tail comes from
  # BioGame/Config/DefaultEngine.ini ("MyDocumentsSubDirName=Mass Effect 2").
  # A launch confirms it: the engine created BIOGame/Config (GamerSettings.ini
  # with the detected CPU/GPU compat levels), BIOGame/Logs, BIOGame/Screenshots
  # and Binaries/ under Documents\BioWare\Mass Effect 2, and campaign saves go
  # to Save/ beside them. Relocating the whole subtree keeps saves AND the
  # graphics/input settings across a prefix wipe.
  saveLocations = [ "Documents/BioWare/Mass Effect 2" ];

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
    description = "Mass Effect 2 (BioWare 2010, EU retail DVD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mass-effect-2";
  };
}
