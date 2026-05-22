{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  p7zip,
  python3,
}:

let
  # Goldberg / gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init etc. The 2021 paid PICO PARK build (Steam app id
  # 1509960) links against Steamworks and exits with "Steam must be
  # running to play this game (SteamAPI_Init() failed)" without a real
  # Steam process. Goldberg satisfies the Steamworks ABI offline.
  # Bumped from release-2026_04_25 to release-2026_05_19 to pick up
  # PR #501 (24c07cb "fix(gamepad): stop polling HID devices every
  # callback" - libs/gamepad/gamepad.c inotify-based device-watch),
  # a20038f2 (double Init/Shutdown fix in Steam_Client - matters if
  # the game re-inits ISteamInput during the controller-config UI),
  # and 8548cb03 (ICMCallback wrapper fix). The PR #501 change is
  # Linux-only (Win32 path in gamepad.c:112-139 still snapshots via
  # XInputGetState every call), so it does not by itself reduce the
  # ~300ms steady-state pad latency observed under wine; see the
  # configs.main.ini cadence note below for the actual mitigation.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_19/emu-win-release.7z";
    hash = "sha256-e+Dq0x+y1HdHzEwmmi4vbBmtOTsji/erVhSZRPyK9bs=";
  };

  # 2021 paid release of PICO PARK (Steam app id 1509960, confirmed via
  # the bundled steam_appid.txt). 64-bit PE32+ pico_park.exe (~12 MB,
  # PE timestamp 2021-08-06) with a D3D11 renderer, 48 World stages
  # plus Battle and Endless modes. The archive.org item ships a flat
  # "Pico Park/" tree with pico_park.exe, resource/, save/userdata.sav,
  # and bundled steam_api{,64}.dll. The exe has NO SteamStub wrap
  # (no .bind section, sections are .text/.rdata/.data/.pdata/.tls/
  # .gfids/_RDATA/.rsrc/.reloc only) so no Steamless step is needed -
  # the only Steam dependency is the steam_api64.dll import, which we
  # swap for Goldberg.
  src = fetchIpfs {
    cid = "QmTdBHTieEyv11xE2phVhmfFCWhJFGyk8btD3M2kMa5jti";
    fallbackUrl = "https://archive.org/download/pc-3_20220101/Pico%20Park.zip";
    hash = "sha256-UEOAcEtEQC0tkFFzlOvaF/QJLwdFITqgEypTlDwPsvg=";
    name = "pico-park-2021.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pico-park-2021";

  inherit src;

  nativeBuildInputs = [
    unzip
    p7zip
    python3
  ];

  # Zip layout: "Pico Park/{pico_park.exe,resource/,save/,steam_api.dll,
  # steam_api64.dll,steam_appid.txt}". Flatten one level into $out.
  buildScript = ''
    mkdir -p "$TMPDIR/extract"
    unzip -q "$src" -d "$TMPDIR/extract"
    mv "$TMPDIR/extract/Pico Park" "$out"
    chmod -R u+w "$out"

    # Replace bundled steam_api64.dll with Goldberg / gbe_fork. The exe
    # is 64-bit so steam_api64.dll is the one that actually gets
    # imported; the bundled steam_api.dll (32-bit) is unused but we
    # swap it too for consistency in case future binaries link it.
    # Use the `experimental` build (not `regular`): per gbe_fork's
    # README.release.md "SteamController/SteamInput support [...] is
    # only enabled in the Windows experimental builds and the linux
    # builds". PICO PARK 2021 calls ISteamInput::GetConnectedControllers
    # / GetDigitalActionData (action set name "GameControls", actions
    # Action_Up/Down/Left/Right/Skill/Select/Cancel/Menu/SubMenu/
    # PageLeft/PageRight - visible in the exe's strings) for its
    # gamepad path, alongside a TbPadDirectInput fallback that the game
    # only uses to enumerate raw HIDs on the controller-config screen.
    # Without SteamInput the game silently treats every pad as
    # unmapped, breaking 1-to-4-player local. The experimental build's
    # side-effect (block non-LAN outgoing sockets) is fine for an
    # offline local-coop game.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    install -m0644 "$TMPDIR/goldberg/release/experimental/x64/steam_api64.dll" \
      "$out/steam_api64.dll"
    install -m0644 "$TMPDIR/goldberg/release/experimental/x86/steam_api.dll" \
      "$out/steam_api.dll"

    # Lower gbe_fork's hard-coded `max_stall_ms = 300ms` watchdog cadence
    # (dll/dll/steam_client.h:120 - constexpr static, no ini knob) to 8ms
    # (125 Hz) inside the prebuilt experimental x64 DLL. Two MSVC use
    # sites compile the 0x12C literal directly:
    #   1. Steam_Client::background_thread_proc, instruction
    #        LEA RAX, [RCX + 0x12c]     (48 8d 81 2c 01 00 00)
    #      at file offset 0xb761b in the gbe_fork release-2026_05_19
    #      experimental x64 DLL. This is the `last_cb_run +
    #      max_stall_ms.count()` add for the "did the game call
    #      RunCallbacks recently?" check. Patching only this is not
    #      enough on its own - the worker would still poll every 300ms.
    #   2. Steam_Client::Steam_Client (KillableWorker ctor call), inst
    #        MOV R9D, 0x12c             (41 b9 2c 01 00 00)
    #      at file offset 0xb2379. This is the `polling_time` arg
    #      passed to KillableWorker, which drives the condvar wait_for
    #      cadence in the background thread (helpers/common_helpers.cpp
    #      KillableWorker::thread_proc, the `wait_for(lck, polling_time
    #      ...)` call). Without this the worker sleeps 300ms between
    #      wakes regardless of the patched check.
    # Both `2C 01 00 00` little-endian imm32 dwords become `08 00 00 00`
    # (8). Net diff against upstream DLL: 4 bytes (2 dwords). The patch
    # asserts the original bytes match before writing - so a future
    # gbe_fork release that changes either instruction encoding (or the
    # constant) will fail loudly at build time instead of silently
    # patching unrelated code.
    python3 - "$out/steam_api64.dll" <<'PATCH'
    import sys, struct
    NEW_MS = 8  # 125 Hz, was 300 (3.3 Hz)
    path = sys.argv[1]
    # (file_offset, expected_bytes, description)
    sites = [
        (0xb761b, b'\x48\x8d\x81\x2c\x01\x00\x00',
         'background_thread_proc: LEA RAX,[RCX+0x12C]'),
        (0xb2379, b'\x41\xb9\x2c\x01\x00\x00',
         'Steam_Client ctor: MOV R9D,0x12C (KillableWorker polling_time)'),
    ]
    with open(path, 'r+b') as f:
        data = f.read()
        for off, expect, desc in sites:
            got = data[off:off+len(expect)]
            if got != expect:
                sys.exit(f'gbe_fork patch: bytes at {off:#x} are {got.hex()}, '
                         f'expected {expect.hex()} ({desc})')
        new_imm = struct.pack('<I', NEW_MS)
        for off, expect, _ in sites:
            # rewrite only the trailing imm32 (last 4 bytes of each match).
            imm_off = off + len(expect) - 4
            f.seek(imm_off)
            f.write(new_imm)
    print(f'gbe_fork: patched {len(sites)} max_stall_ms sites to {NEW_MS}ms', file=sys.stderr)
    PATCH

    # Goldberg config: report PICO PARK (appid 1509960) as owned.
    # Goldberg looks for steam_settings/ next to its steam_api64.dll.
    settings="$out/steam_settings"
    mkdir -p "$settings"
    echo -n 1509960 > "$settings/steam_appid.txt"
    # The bundled steam_appid.txt already contains 1509960; keep it.

    # Steam Input action set bindings. gbe_fork's ISteamInput
    # implementation needs an ACTION_SET_NAME.txt file in
    # steam_settings/controller/ for each action set the game uses,
    # otherwise GetDigitalActionData() returns "not bound" for every
    # input and the gamepad appears dead. PICO PARK 2021 uses a single
    # action set called "GameControls" (only action-set string in the
    # exe besides the Action_* action names). Map the 11 actions onto
    # a standard XInput layout. Proton's xinput1_4 exposes any
    # evdev-recognised pad (Xbox, PS, Switch, generic) as an XInput
    # device, which is what gbe_fork polls under the hood
    # (XINPUT1_4.dll is the only XInput import in steam_api64.dll).
    mkdir -p "$settings/controller"
    {
      echo "Action_Up=DUP,DLJOYUP"
      echo "Action_Down=DDOWN,DLJOYDOWN"
      echo "Action_Left=DLEFT,DLJOYLEFT"
      echo "Action_Right=DRIGHT,DLJOYRIGHT"
      echo "Action_Skill=A"
      echo "Action_Select=A"
      echo "Action_Cancel=B"
      echo "Action_Menu=START"
      echo "Action_SubMenu=BACK"
      echo "Action_PageLeft=LBUMPER"
      echo "Action_PageRight=RBUMPER"
    } > "$settings/controller/GameControls.txt"

    # gbe_fork experimental ships an imgui-based overlay (Shift+Tab) that
    # hooks the D3D9 renderer AND installs a WndProc handler when active.
    # Per dll/settings_parser.cpp:1526 and overlay_experimental/steam_overlay.cpp
    # line 154, the entire overlay subsystem (Steam_Overlay::Steam_Overlay
    # ctor early-returns; renderer_hook_init_thread / WndProc setup never
    # start) is gated on `enable_experimental_overlay=1`, defaulting to 0
    # (settings.h:342 `bool disable_overlay = true`). Drop an explicit
    # configs.overlay.ini that pins the flag to 0 anyway, so a future
    # gbe_fork release flipping the default cannot regress us into the
    # overlay's input-hook codepath.
    cat > "$settings/configs.overlay.ini" <<'OVERLAYINI'
    [overlay::general]
    enable_experimental_overlay=0
    OVERLAYINI

    # gbe_fork's networking stack runs from the same per-frame
    # `RunCallbacks` chain that polls the pad. With networking ON,
    # `Steam_Client::RunCallbacks` (dll/steam_client.cpp:997-1037)
    # calls `network->Run()` first under the global recursive mutex,
    # then iterates 17 per-frame subsystem callbacks (matchmaking,
    # lobby, networking_sockets, networking_messages, friends, etc.
    # - one `run_every_runcb->add` per dll/steam_*.cpp) before the
    # `Steam_Controller::steam_run_every_runcb` -> RunCallbacks ->
    # RunFrame -> GamepadUpdate path that actually refreshes pad
    # state. The same chain runs from gbe_fork's background watchdog
    # thread (steam_client.cpp:23-43, fires every max_stall_ms=300ms
    # per dll/dll/steam_client.h:120 - a constexpr static, not
    # ini-tunable). Each of those subsystem callbacks holds the
    # global_mutex; if the game's per-frame SteamAPI_RunCallbacks
    # collides with the background watchdog the pad-poll waits on
    # the lock. PICO PARK is local-coop offline only - it never
    # opens an outbound socket - so disable both networking and the
    # LAN-broadcast fallback to cut that chain down to the
    # gamepad/utils/timeline/inventory paths and free the mutex
    # faster on every frame. See post_build/steam_settings.EXAMPLE/
    # configs.main.EXAMPLE.ini for the documented keys.
    cat > "$settings/configs.main.ini" <<'MAININI'
    [main::connectivity]
    disable_networking=1
    disable_lan_only=1
    MAININI
  '';

  runtime = "proton";
  executable = "pico_park.exe";

  # Gamepad input-lag mitigation for 4-player local coop with mixed
  # USB+Bluetooth pads. The binary has TWO controller paths, both
  # active concurrently per the RTTI strings (`.?AVTbSteamPad@toybox@@`
  # AND `.?AVTbPadDirectInput@toybox@@`): a `TbSteamPad` reader that
  # goes through ISteamInput -> gbe_fork -> XInputGetState -> wine
  # xinput1_4 -> winebus evdev, and a `TbPadDirectInput` reader that
  # goes straight through DINPUT8.dll -> wine dinput8 -> winebus
  # evdev (the exe's import table contains DINPUT8.dll +
  # DirectInput8Create + steam_api64.dll but NOT xinput1_*.dll, so the
  # only XInput consumer is gbe_fork itself). Both paths share the
  # same evdev nodes, so any backlog there affects both.
  #
  # If SDL HIDAPI is live for the same hidraw, the SDL reader inside
  # the game process races the wine winebus evdev reader on the BT
  # pad's HID report stream, and one of them accumulates a per-
  # controller backlog -- BT pads send reports at 125-250 Hz with
  # 8-20 ms one-way latency, so any reader that drains at the game's
  # 60 Hz tick falls behind monotonically. Symptom: pads respond fast
  # at start of session, lag grows over minutes, keyboard (separate
  # xinput path) stays snappy, and the BT pads degrade worse than the
  # wired ones. lib/proton.nix only disables the Xbox 360 HIDAPI
  # subdriver globally; force all HIDAPI off here so winebus's evdev
  # path is the single reader. Pico Park doesn't need any HIDAPI-only
  # feature (touchpad, gyro, advanced rumble), it only reads buttons +
  # dpad + sticks which evdev provides fully.
  #
  # Known residual (mitigated by the buildScript binary patch above):
  # with HIDAPI=0 the unbounded growth stops but a ~300ms steady-state
  # floor remains, matching gbe_fork's `max_stall_ms =
  # std::chrono::milliseconds(300)` watchdog (dll/dll/steam_client.h:120
  # - constexpr static, not ini-tunable; the value also drives the
  # `KillableWorker` poll period in dll/steam_client.cpp:51-55).
  # If the game's per-frame SteamAPI_RunCallbacks call falls behind,
  # the next `GamepadUpdate` is gated on that watchdog. Rebuilding
  # gbe_fork's mingw DLL (premake5 + cross-mingw) would be the clean
  # fix; instead the buildScript edits the 0x12C immediate inline.
  # Classic pico-park (DINPUT8 only, no gbe_fork) does not hit this
  # floor.
  env = {
    SDL_JOYSTICK_HIDAPI = "0";
  };

  # Input-latency tuning for the D3D9 + DINPUT8 renderer (see
  # `strings pico_park.exe | grep -i 'd3d9\|dinput8\|xinput'` -- the binary
  # imports d3d9.dll / d3dx9_43.dll / DINPUT8.dll). DXVK's default D3D9
  # present queue allows up to 3 frames in flight, which at 60 fps adds
  # ~33-50 ms of perceptible lag between the controller / keyboard event
  # and the on-screen reaction. pico_park polls via ISteamInput per frame
  # (gbe_fork RunFrame -> GamepadUpdate -> XInputGetState), so reducing
  # the frame queue depth directly tightens the input-to-display path.
  # Drop a dxvk.conf next to the exe with maxFrameLatency=1 (same pattern
  # used by games/bioshock/default.nix for the same engine family).
  # DXVK auto-loads `dxvk.conf` from cwd, but we also export
  # DXVK_CONFIG_FILE so wine's cwd quirks under proton don't matter.
  preRun = ''
    cat > "$GAMEDIR/dxvk.conf" <<'DXVKCONF'
    d3d9.maxFrameLatency = 1
    dxvk.maxFrameLatency = 1
    DXVKCONF
    export DXVK_CONFIG_FILE="$GAMEDIR/dxvk.conf"
  '';

  # The 2021 TECOPARK build writes its save to ./save/userdata.sav next
  # to the binary, not under drive_c/users/steamuser/... So saves
  # persist via the per-game fuse-overlayfs upper and saveLocations
  # stays empty (same pattern as Classic pico-park / portal / magicka).
  saveLocations = [ ];

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
    description = "PICO PARK (2021 paid release, Steamworks shimmed with Goldberg, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pico-park-2021";
  };
}
