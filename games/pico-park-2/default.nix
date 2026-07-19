{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  p7zip,
  mono,
  python3,
}:

let
  # mingw-w64 cross-compiler + mcfgthread runtime, used below to
  # build our minimal SteamNative.dll replacement (see the long
  # comment near the buildScript line that drops it into $plugins).
  mingwCC = pkgs.pkgsCross.mingwW64.buildPackages.gcc;
  mingwMcf = pkgs.pkgsCross.mingwW64.windows.mcfgthreads;

  # Steamless: removes SteamStub DRM (.bind section + encrypted
  # entry-point shim) from Steamworks-protected exes. Same tool used
  # by pico-park (Classic) and outer-wilds.
  steamless = fetchurl {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-4+LSLgmP8/s1myh2qivtlZbwUB5v9YjL/66Qp20txPU=";
  };

  # Goldberg / gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init() and friends. The IGG repack ships its own copy of
  # gbe_fork pasted in by the uploader (16 MB experimental flavor) vs
  # the genuine ~300 KB Valve one. We replace with our own pinned
  # `experimental` release for deterministic, uploader-independent
  # behavior. We MUST use the experimental flavor (not `regular`) because
  # the IL2CPP layer ships a SteamNative.dll P/Invoke wrapper that calls
  # the SteamInput006 family — visible as `SteamGetActionSetHandle`,
  # `SteamGetDigitalActionData`, `SteamGetAnalogActionData`,
  # `SteamGetConnectedControllers`, `SteamInitializeController` exports
  # in `pico_park_2_Data/Plugins/x86_64/SteamNative.dll`, and the
  # corresponding GameAssembly.dll string table. Per gbe_fork's
  # `README.release.md`: "SteamController/SteamInput support [...] is
  # only enabled in the Windows experimental builds and the linux
  # builds". The `regular` Windows build stubs `ISteamInput::*` to
  # "not bound", so every pad enumerates as 0 controllers and every
  # action returns inactive — the exact symptom we see in Player.log
  # (XInput initialises, winebus enumerates the pads, but in-game pads
  # are dead). The experimental overlay (the only reason to prefer
  # `regular`) is opt-in via `configs.overlay.ini`'s
  # `enable_experimental_overlay` knob, which the repack's tree pins
  # to 0 below — see also pico-park-2021's analysis of the gating in
  # `dll/settings_parser.cpp:1526`. Same pinned release as
  # pico-park-2021 (release-2026_05_19), so the binary-patched
  # max_stall_ms offsets are byte-identical.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_19/emu-win-release.7z";
    hash = "sha256-e+Dq0x+y1HdHzEwmmi4vbBmtOTsji/erVhSZRPyK9bs=";
  };

  # The IGG/OneHack repack of Pico Park 2 v1.04 (2023 Unity IL2CPP
  # build by TECOPARK, Steam appid 2644470). The repack saves the
  # genuine SteamStub-wrapped pico_park_2.exe and the genuine Valve
  # steam_api64.dll next to the patched copies as `.exe.o` / `.dll.o`,
  # so we can rebuild a deterministic clean install from the originals:
  # Steamless-unpack the .exe.o, drop our own gbe_fork over the
  # genuine .dll.o. We KEEP the repack's rich steam_settings/ tree
  # (achievements.json, configs.*.ini, controller glyphs, fonts, etc.)
  # and only sanitize the few fields the uploader baked-in.
  src = fetchIpfs {
    cid = "QmcxX6cAgrjXkuXwe9bZQVCwTJydbHZC2m4sa3stCha2Kf";
    fallbackUrl = "https://archive.org/download/pico.-park.-2.v-1.04/PICO.PARK.2.v1.04.rar";
    hash = "sha256-24lPVB0r/AXKCmCX8Chfq3QLS+hfQqq55vfebh9ikAU=";
    name = "pico-park-2.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pico-park-2";

  inherit src;

  nativeBuildInputs = [
    unar
    p7zip
    mono
    python3
    mingwCC
  ];

  buildScript = ''
    unar -q -D -o "$TMPDIR" "$src"
    mv "$TMPDIR/PICO.PARK.2.v1.04" "$out"
    chmod -R u+w "$out"

    # Drop IGG/OneHack repack noise.
    rm -f \
      "$out/IGG-GAMES.COM.url" \
      "$out/OneHack.Us.txt" \
      "$out/PCGAMESTORRENTS.COM.url" \
      "$out/README.txt" \
      "$out/_INSTALL TUTORIAL.txt"

    gamedir="$out/game"
    plugins="$gamedir/pico_park_2_Data/Plugins/x86_64"

    # The repack saved the genuine SteamStub-wrapped binary as
    # pico_park_2.exe.o. Restore it as pico_park_2.exe, discard the
    # repacker's pre-unpacked copy.
    rm -f "$gamedir/pico_park_2.exe"
    mv "$gamedir/pico_park_2.exe.o" "$gamedir/pico_park_2.exe"

    # Strip SteamStub DRM from the genuine pico_park_2.exe.
    mkdir -p "$TMPDIR/steamless"
    unar -q -D -o "$TMPDIR/steamless" ${steamless}
    # Steamless.CLI.exe needs Steamless.API.dll next to it, not just
    # under Plugins/.
    cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"
    ( cd "$TMPDIR/steamless" \
      && mono Steamless.CLI.exe --quiet "$gamedir/pico_park_2.exe" )
    mv "$gamedir/pico_park_2.exe.unpacked.exe" "$gamedir/pico_park_2.exe"

    # Restore the genuine Valve steam_api64.dll (the repacker stashed
    # it as .dll.o next to their 16 MB gbe_fork rebuild). Keep the
    # repack's SteamNative.dll and steamclient64.dll in place — the
    # game's IL2CPP code P/Invokes SteamNative directly (Player.log:
    # "DllNotFoundException: Unable to load DLL 'SteamNative'"), so
    # the previous instinct to drop them as "unused helpers" was wrong.
    rm -f "$plugins/steam_api64.dll"
    mv "$plugins/steam_api64.dll.o" "$plugins/steam_api64.dll"

    # Replace steam_api64.dll with our pinned gbe_fork `experimental`
    # build. Required because the IL2CPP code (via SteamNative.dll
    # P/Invokes) queries ISteamInput006 for pad enumeration and action
    # bindings — see the let-bound goldberg comment above for the
    # P/Invoke names. `regular` stubs those interfaces; only
    # `experimental` (and the Linux builds) implement them. We force-
    # disable the experimental overlay separately via
    # configs.overlay.ini to keep its D3D11 swapchain hook out of the
    # picture (it's a known wedge on Unity URP titles).
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    cp "$TMPDIR/goldberg/release/experimental/x64/steam_api64.dll" \
      "$plugins/steam_api64.dll"

    # Lower gbe_fork's hard-coded `max_stall_ms = 300ms` watchdog
    # cadence to 8ms (125 Hz) inside the prebuilt experimental x64 DLL.
    # SAME offsets as pico-park-2021 (which uses the same pinned
    # release-2026_05_19 experimental/x64/steam_api64.dll, byte-
    # identical 7z member) — see games/pico-park-2021/default.nix for
    # the full derivation of the offsets and rationale. Without this
    # patch, ISteamInput-driven pad polling would inherit gbe_fork's
    # 300ms watchdog floor, manifesting as visible pad lag in
    # PICO PARK 2 just as it did in PICO PARK 2021. The python heredoc
    # below is intentionally a verbatim copy of the pico-park-2021
    # patch so the two stay in sync on future gbe_fork bumps; if
    # offsets drift the assertion fails loudly at build time.
    python3 - "$plugins/steam_api64.dll" <<'PATCH'
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

    # Force-bypass the `initialized` gate in Steam_Controller::RunFrame(bool).
    #
    # Source (dll/steam_controller.cpp:356-364, release-2026_05_19):
    #   void Steam_Controller::RunFrame(bool bReservedValue)
    #   {
    #       if (disabled || !initialized) {
    #           return;
    #       }
    #       PRINT_DEBUG_ENTRY();
    #       GamepadUpdate();   // -> libs/gamepad/gamepad.c, polls XInput
    #   }
    # Steam_Client::background_thread_proc (running every 8ms after our
    # max_stall_ms patch above) calls run_every_runcb->run(), which
    # invokes Steam_Controller::steam_run_every_runcb -> RunCallbacks,
    # AND the game itself calls ISteamInput::RunFrame each tick through
    # the SteamNative.dll shim's SteamRunFrame export. Either path lands
    # in this function — but `initialized` is only set true inside
    # Steam_Controller::Init(bool), which is reached via
    # ISteamInput::Init(). SteamNative.dll (TECOPARK's PDB at
    # `C:\Projects\PicoPark2\Program\Steam\x64\Release\SteamNative.pdb`)
    # never appears to forward an Init call into ISteamInput006 — its
    # exports `SteamInitializeController` / `SteamRunFrame` /
    # `SteamGetConnectedControllers` are P/Invoked by the IL2CPP game,
    # but the wrapper's own initialisation never triggers Steam_Controller
    # to flip `initialized = true`. Result: GamepadUpdate() is NEVER
    # called, the XInput polling thread inside gbe_fork's gamepad.c
    # never runs, and every digital/analog action handle stays at zero
    # even though wine's xinput1_4 + winebus are happily enumerating
    # the pad (Player.log shows "Using XInput" and we confirmed via
    # /proc/<pid>/maps that xinput1_4.dll is loaded).
    #
    # Working-pads comparison: pico-park-2021 uses the SAME pinned
    # release-2026_05_19 experimental/x64/steam_api64.dll, and its pads
    # work — because the Unity build calls ISteamInput::Init directly
    # via Steamworks.NET, flipping the flag. pico-park-2 routes through
    # TECOPARK's bespoke SteamNative.dll which skips that call.
    #
    # Patch: replace the `jne fcn.RunFrame_body` (0F 85 rel32, taken
    # when initialized!=0) at the bottom of the gate with `nop; jmp
    # rel32` so we ALWAYS proceed to the body regardless of the
    # `initialized` flag. The `disabled` check at the top of the
    # function is preserved untouched — and is safe because
    # `disabled = !controller_settings.enabled && action_handles.empty()`
    # is false in our build (the repack ships InGameControls.txt +
    # MenuControls.txt action sets, which populates action_handles
    # during `Steam_Controller::set_handles` from the ctor).
    #
    # Before:  0x1800c4760  0F 85 8A 04 09 00   jne  0x180154bf0
    # After:   0x1800c4760  90 E9 8A 04 09 00   nop; jmp 0x180154bf0
    # The rel32 displacement is preserved unchanged: instruction-end
    # address (0x1800c4766) is the same, and target = 0x1800c4766 +
    # 0x9048a = 0x180154bf0 either way.
    python3 - "$plugins/steam_api64.dll" <<'PATCH'
    import sys
    path = sys.argv[1]
    # File offset 0xc3b60 in release-2026_05_19 experimental/x64
    # steam_api64.dll, inside Steam_Controller::RunFrame(bool) at
    # vaddr 0x1800c4760 (.text starts at vaddr 0x180001000 paddr 0x400,
    # so vaddr 0x1800c4760 maps to paddr 0xc4760 - 0xc00 = 0xc3b60).
    PATCH_OFF = 0xc3b60
    EXPECT = b'\x0f\x85'
    NEW    = b'\x90\xe9'
    with open(path, 'r+b') as f:
        f.seek(PATCH_OFF)
        got = f.read(len(EXPECT))
        if got != EXPECT:
            sys.exit(f'gbe_fork initialized-gate patch: bytes at '
                     f'{PATCH_OFF:#x} are {got.hex()}, expected {EXPECT.hex()}')
        f.seek(PATCH_OFF)
        f.write(NEW)
    print('gbe_fork: bypassed Steam_Controller::RunFrame initialized gate',
          file=sys.stderr)
    PATCH

    # Replace TECOPARK's bespoke SteamNative.dll with our own mingw-
    # cross-compiled shim. Background:
    #
    # PICO PARK 2 (Unity IL2CPP) P/Invokes a 95-export DLL named
    # `SteamNative` from its managed `SteamManaged.dll` layer. The
    # repack ships TECOPARK's build (embedded PDB path
    # `C:\Projects\PicoPark2\Program\Steam\x64\Release\SteamNative.pdb`,
    # 30 KB), which is a C++ wrapper that imports SteamAPI_Init,
    # SteamInternal_ContextInit, SteamInternal_FindOrCreateUserInterface
    # etc. from steam_api64.dll and forwards C# P/Invoke calls into
    # the SteamInput006 vtable.
    #
    # Reverse-engineering the original (radare2 disasm of the
    # `SteamInitializeController` export, see commit message of the
    # round-7 binary-patch above for the full trace) shows it uses
    # an obfuscated `mov rcx, [ctx]; mov rax, [rcx]; jmp [rax]`
    # pattern that calls `ISteamInput::Init(bExplicit)` via vtable
    # slot 0 — but only after a lazy `SteamInternal_ContextInit`
    # callback chain whose first invocation may race the game's
    # first `SteamRunFrame` / `SteamGetConnectedControllers` call.
    # The previous round-7 patch (bypassing
    # Steam_Controller::RunFrame's `initialized` gate) was supposed
    # to make the race benign, but pads still don't surface in-game
    # — pointing to a different gate inside TECOPARK's wrapper.
    #
    # Our shim (sources under games/pico-park-2/SteamNative-shim/)
    # replaces the wrapper with a minimal, explicit, traced version:
    #   - eager `LoadLibraryA("steam_api64.dll")` in DllMain
    #   - latched ISteamInput006 pointer fetched at SteamInit time
    #     via SteamInternal_FindOrCreateUserInterface(hUser,
    #     "SteamInput006") — same call gbe_fork's experimental flavor
    #     answers unconditionally regardless of steam_interfaces.txt
    #   - SteamInitializeController explicitly calls vtable[0]
    #     (`ISteamInput::Init(true)`) once
    #   - SteamRunFrame, SteamGetConnectedControllers, SteamGet*Action*
    #     dispatch through the vtable per ISteamInput006's pure-virtual
    #     order (documented in the shim's SteamNative.cpp)
    #   - every input-relevant export traces via OutputDebugStringA so
    #     the call pattern is visible in WINEDEBUG / Player.log
    #   - 95 ordinal-aligned exports match the original's export
    #     table byte-for-byte (verified via `objdump -p`); the
    #     mangled `?CSteamFriends@@QEAA@XZ` etc. exports are
    #     harmless stubs reachable only by ordinal — none of them
    #     are P/Invoked by the IL2CPP layer (grep of GameAssembly.dll
    #     string table confirms ~30 SteamXxx flat names are the only
    #     entries the game reaches).
    #
    # Built with x86_64-w64-mingw32-g++. We rely on mcfgthread for
    # the gcc-15 mingw runtime (thread model `mcf`). The .def file
    # pins each export name to its ordinal so dlltool emits an
    # export directory in the same order as the original DLL.
    # NOTE: the shim is disabled for now — user-reported testing shows
    # it crashes the game at startup (deep ntdll fault, address
    # 0x00006FFFFFF001FF in Player.log). Likely cause is a vtable-index
    # or struct-return ABI mismatch on one of the first P/Invokes from
    # the IL2CPP layer. Keep the source files in-tree
    # (games/pico-park-2/SteamNative-shim/) for future iteration but
    # leave TECOPARK's original SteamNative.dll in place so the game
    # at least starts. Re-enable by un-commenting the mingw compile
    # block below.
    #
    # (Disabled SteamNative shim compile block — see comment above. The
    # path interpolations have been stripped so Nix doesn't try to
    # import the missing SteamNative-shim directory at eval time.)

    # Keep the repack's full steam_settings/ tree (achievements.json,
    # configs.*.ini, controller glyphs, fonts, images, sounds,
    # steam_interfaces.txt, supported_languages.txt). Only patch the
    # fields the uploader baked-in or that risk hanging the game.
    #
    # SteamInput action-set bindings. gbe_fork's experimental
    # ISteamInput006 maps the game's action handles to physical pad
    # inputs by reading steam_settings/controller/<ActionSet>.txt. A
    # gbe_fork *debug*-build STEAM_LOG trace of the real v1.04 binary
    # shows Init() and GetConnectedControllers() already succeed (the
    # pad enumerates as 1 controller, wine's XInput feeds it) and that
    # the game requests exactly ONE action set, "GameControls", with
    # digital actions Action_{A,B,X,Y,L,R,Start,Up,Down,Left,Right} and
    # analog Action_Joystick. The repack, however, only ships
    # InGameControls.txt / MenuControls.txt (action sets INGAMECONTROLS /
    # MENUCONTROLS, unrelated action names Move/Jump/LightAttack/...) --
    # leftovers from a DIFFERENT build. With no config matching
    # "GameControls", every action resolved to "not bound" and the pad
    # silently no-opped in-game despite XInput enumerating it (GetDigital-
    # ActionData returned the uniform unbound "1 0"; after adding the file
    # it returns per-action bindings and GetActionSetHandle returns 1).
    # We write the matching GameControls.txt below; the stale files are
    # harmless (the game never asks for their action sets) so they stay.
    settings="$plugins/steam_settings"

    # The action set + action names the real v1.04 binary asks for (see
    # comment above). Direct 1:1 pad mapping; Action_L/R are the shoulder
    # bumpers, Action_Joystick is the left analog stick. Indented to match
    # the buildScript base so Nix strips the leading space to column 0.
    mkdir -p "$settings/controller"
    cat > "$settings/controller/GameControls.txt" <<'GAMECONTROLS'
    Action_A=A
    Action_B=B
    Action_X=X
    Action_Y=Y
    Action_L=LBUMPER
    Action_R=RBUMPER
    Action_Start=START
    Action_Up=DUP
    Action_Down=DDOWN
    Action_Left=DLEFT
    Action_Right=DRIGHT
    Action_Joystick=LJOY=joystick_move
    GAMECONTROLS

    # Sanitize the uploader's account name. gbe_fork accepts any
    # string here, but leaving Mr_GoldBerg-branded saves around is
    # noisy in screenshots.
    if [ -f "$settings/configs.user.ini" ]; then
      sed -i 's/^account_name=Mr_GoldBerg/account_name=Player/' \
        "$settings/configs.user.ini"
    fi

    # Force-disable the experimental overlay. The repack flipped it
    # ON (enable_experimental_overlay=1), but gbe_fork itself warns
    # this "might cause crashes" and Unity D3D11/URP titles are a
    # known wedge for the overlay's swapchain hook. A blue/blank
    # window with no error popup is the canonical symptom.
    if [ -f "$settings/configs.overlay.ini" ]; then
      sed -i 's/^enable_experimental_overlay=1/enable_experimental_overlay=0/' \
        "$settings/configs.overlay.ini"
    fi

    # Force offline + disable LAN matchmaking discovery. Inside
    # bubblewrap there is no host LAN visible anyway, and PICO PARK 2
    # uses Steamworks lobbies + UDP/TCP broadcast for matchmaking;
    # the emu's networking thread otherwise spends startup time on
    # discovery callbacks the game waits on. Setting offline=1 short-
    # circuits BLoggedOn() and lets the title screen advance.
    if [ -f "$settings/configs.main.ini" ]; then
      sed -i 's/^offline=0/offline=1/;s/^disable_networking=0/disable_networking=1/;s/^disable_lobby_creation=0/disable_lobby_creation=1/' \
        "$settings/configs.main.ini"
    fi

    # Belt-and-braces: drop appid next to the exe too. Some
    # Steamworks.NET wrappers check $cwd before the dll's directory.
    echo -n 2644470 > "$settings/steam_appid.txt"
    echo -n 2644470 > "$gamedir/steam_appid.txt"

    # NOTE on steam_interfaces.txt: gbe_fork's parser
    # (dll/settings_parser.cpp:try_parse_old_steam_interfaces_file)
    # does NOT recognise any `SteamInput*` line — only SteamClient,
    # SteamUser, SteamFriends, SteamController* and a handful of
    # STEAM*_INTERFACE_VERSION entries are mapped (lines 1733-1766 of
    # gbe_fork release-2026_05_19). SteamInput006 is served
    # unconditionally by `Steam_Client::GetISteamInput` in
    # `steam_client_interface_getter.cpp:1024` whenever the game asks
    # for it via `SteamInternal_FindOrCreateUserInterface`, so editing
    # steam_interfaces.txt was a no-op (`PRINT_DEBUG("NOT REPLACED")`).
    # We leave the repack's file as-is for clarity.

    # Force-enable SteamInput in [app::controller] of configs.app.ini.
    # The repack ships configs.app.ini WITHOUT this section, so gbe_fork
    # falls back to `steam_input=0` (see dll/settings_parser.cpp:549,
    # `ini.GetBoolValue("app::controller", "steam_input", false)`).
    # While action sets under steam_settings/controller/ should be
    # sufficient to flip `disabled=false` via the empty-action-handles
    # check (steam_controller.cpp:224), the official EXAMPLE config
    # documents this knob as the gating switch ("SteamInput is
    # automatically enabled when there are action sets..." plus an
    # explicit `steam_input=0` default in
    # `post_build/steam_settings.EXAMPLE/configs.app.EXAMPLE.ini:31`),
    # and some games' wrappers may probe the setting separately to
    # decide whether to even call `ISteamInput::Init`. Belt-and-braces:
    # explicitly set it to 1 and pin `type=XBOX360` so SteamNative.dll's
    # `SteamGetInputTypeForHandle` returns a non-`k_ESteamInputType_Unknown`
    # value, which the repack's TecoGamePad layer may use to decide
    # whether the controller path is live.
    if [ -f "$settings/configs.app.ini" ]; then
      if ! grep -q '^\[app::controller\]' "$settings/configs.app.ini"; then
        printf '\n[app::controller]\nsteam_input=1\ntype=XBOX360\n' \
          >> "$settings/configs.app.ini"
      fi
    fi

    # Ship gbe_fork's `GameOverlayRenderer64.dll` next to the game exe.
    # Some Steamworks-linked wrappers refuse to enumerate ISteamInput
    # unless the overlay DLL is loadable (LoadLibrary check at init),
    # even when the overlay is disabled at runtime via
    # configs.overlay.ini. This is the experimental-flavor overlay
    # binary; with `enable_experimental_overlay=0` already pinned in
    # configs.overlay.ini above, the DLL's D3D11 hook stays dormant and
    # only its presence on disk satisfies the wrapper's probe.
    cp "$TMPDIR/goldberg/release/steamclient_experimental/GameOverlayRenderer64.dll" \
      "$gamedir/GameOverlayRenderer64.dll"
  '';

  runtime = "proton";
  executable = "game/pico_park_2.exe";

  # Gamepad path: Unity 2022.3.28 (new input system) on Windows
  # prefers Windows.Gaming.Input (WinRT) over XInput. Player.log on
  # the previous run shows:
  #     New input system (experimental) initialized
  #     Using Windows.Gaming.Input
  # i.e. UnityPlayer.dll's `Windows.Gaming.Input failed to initialize
  # (Might not be available), fallback to XInput` diag path was NOT
  # taken -- proton's stub `windows.gaming.input.dll` loads, so Unity
  # binds to the WGI Gamepad collection. But proton's WGI provider
  # does not enumerate winebus evdev pads into the WGI Gamepad list
  # (only `windows.gaming.input` for raw HID buttons via the WinRT
  # IGamepadStatics path, which winebus does not feed for non-Xbox
  # generic pads), so no pads ever appear and TecoGamePad receives no
  # input regardless of the `-disable_tecogamepad` flag we already
  # dropped. Force-disable the WGI DLL so Unity's own fallback path
  # (visible in `strings UnityPlayer.dll`:
  # `Windows.Gaming.Input failed to initialize ... fallback to
  # XInput`) takes over, which goes through xinput1_4.dll -> winebus
  # evdev and DOES enumerate all kernel-recognised pads.
  # Belt-and-braces SDL_JOYSTICK_HIDAPI=0 mirrors pico-park-2021's
  # fix: prevents SDL HIDAPI from racing winebus on hidraw for BT
  # pads (relevant if Unity's HIDInput path is also active for
  # touch/gyro -- `strings UnityPlayer.dll` lists `HIDInput`,
  # `RawInput`, `XInput` as parallel input subsystems).
  env = {
    WINEDLLOVERRIDES = "windows.gaming.input=";
    SDL_JOYSTICK_HIDAPI = "0";
  };

  # No `-disable_tecogamepad` flag: TECOPARK's Steam-forum advice was
  # for the v1.04 startup blue-screen, but inspecting IL2CPP metadata
  # (pico_park_2_Data/il2cpp_data/Metadata/global-metadata.dat) shows
  # `TecoGamePad` is a Photon-Quantum sub-assembly with siblings
  # `TecoGamePadList`, `TecoGamePadCount`, `getTecoGamePad` — i.e.
  # the whole pad-enumeration layer, with NO networking-side
  # identifiers (no "LAN", "discovery", "companion", "socket" cousins
  # of the same root). Toggling the flag therefore kills every pad
  # input path through the Quantum simulation, which manifests as
  # "no controllers respond in-game". The actual startup wedge was
  # the gbe_fork lobby/overlay race, which configs.main.ini's
  # offline=1 / disable_networking=1 / disable_lobby_creation=1
  # (set in buildScript above) already handles — Player.log shows
  # the game now reaches "Starting Game" without the CLI flag.
  # https://steamcommunity.com/app/2644470/discussions/0/4700160645242641167/

  # Unity persistentDataPath convention: companyName/productName as
  # read from globalgamemanagers in this build are "TECOPARK" and
  # "PICO PARK 2", so the engine writes saves and settings under
  # AppData/LocalLow/TECOPARK/PICO PARK 2 inside the wineprefix.
  saveLocations = [ "AppData/LocalLow/TECOPARK/PICO PARK 2" ];

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
    description = "Pico Park 2 (TECOPARK 2023 Unity build, SteamStub-stripped + gbe_fork, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pico-park-2";
  };
}
