{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  python3,
}:

self.lib.mkGame { inherit lib pkgs; } {
  imports = [
    (
      { config, lib, ... }:
      let
        inherit (lib) mkOption types;
      in
      {
        options = {
          mods = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = ''
              Mod derivations stacked onto Half-Life as additional
              overlay lowers. Each entry should produce a tree shaped
              like `Half-Life/<modname>/...` (e.g.
              `Half-Life/CryOfFear/cl_dlls/...`); it is merged into
              the sandbox view above `_gameData` without re-extracting
              the base Half-Life tree. Later list entries override
              earlier ones on conflicting paths.

              To launch a specific mod, set `mod` to its directory
              name; the engine then receives `-game <name>` and loads
              that mod's cl_dlls/dlls/maps/...
            '';
          };

          mod = mkOption {
            type = types.str;
            default = "valve";
            description = ''
              Mod directory name passed to hl.exe as `-game <mod>`.
              `"valve"` (vanilla Half-Life) suppresses the `-game`
              argument entirely; any other value prepends `-game
              <mod>` to `executableArgs`.
            '';
          };
        };

        config = {
          name = "half-life";

          src = fetchIpfs {
            cid = "QmeUQvq7qxgmktqQyWR5XmyDEXxayjJaQrEpkMg1P8F1qP";
            fallbackUrl = "https://archive.org/download/half-life_20210825/Half-Life.zip";
            hash = "sha256-29sxE98uie7xn5TpUrGuVz8cv5i99aT64aIffkVh8lc=";
            name = "Half-Life.zip";
          };

          nativeBuildInputs = [
            unzip
            python3
          ];

          buildScript = ''
                mkdir -p "$out/Half-Life"
                unzip -q $src -d "$out"

                # Remove kver.kp - the bundled cert belongs to a different key and
                # confuses the auth check even with IsValid patched
                rm -f "$out/Half-Life/kver.kp"

                # Point WON auth servers to localhost so the dead-server check fails fast
                cat > "$out/Half-Life/woncomm.lst" <<'EOF'
            server
              addr 127.0.0.1:27010
            master
              addr 127.0.0.1:27010
            modserver
              addr 127.0.0.1:27011
            secure
              addr 127.0.0.1:27012
            EOF

                # Patch WONAuth.dll: IsValid, Verify, VerifyCertificate -> always return 1
                python3 << PYEOF
            data = bytearray(open("$out/Half-Life/WONAuth.dll","rb").read())
            for off in [0x43c, 0x45a, 0x4c3]:
                data[off:off+6] = bytes([0xB8,0x01,0x00,0x00,0x00,0xC3])
            open("$out/Half-Life/WONAuth.dll","wb").write(data)
            print("Patched WONAuth.dll")
            PYEOF

                # Patch hl.exe: force the CD-key entry dialog to be skipped.
                #
                # The 1.1.1.0 hl.exe gate runs in the function at VA 0x4220f6:
                #   * Reads HKCU\Software\Valve\Half-Life\Settings\Key into a
                #     local CString (via Registry_GetString at 0x4250a0) unless
                #     `-steam` is on the cmdline.
                #   * Tests CString::IsEmpty() at 0x422254.
                #   * If empty, falls into a dialog loop at 0x422261 that calls
                #     LoadString id 0x162 = "Please type in the CD Key displayed
                #     on the Half-Life CD case" then spawns the modal entry
                #     dialog via the CreateDialogIndirectParamA wrapper at
                #     0x49680c.
                #   * If non-empty, jumps to 0x4224fd which calls the validator
                #     at 0x422a1a (strlen==13 + WON checksum at 0x401000) and
                #     either re-prompts or proceeds.
                #
                # Seeding the registry alone does not work: HL re-initialises
                # the Settings subkey early in startup and overwrites our
                # `Key` value with `""`. So we patch the IsEmpty test instead.
                #
                # Original:
                #   0x42225b: 0F 84 9C 02 00 00     je 0x4224fd  ; (jump if non-empty)
                # Patched (force unconditional jump):
                #   0x42225b: E9 9D 02 00 00 90     jmp 0x4224fd ; nop
                # (jmp rel32 is 5 bytes vs je 6, so we displace by +1 and tail
                # with a NOP to keep instruction-stream alignment.)
                #
                # We also patch the validator at VA 0x422a1a to always return 1,
                # so the post-jump `0x4224fd` path (which still runs the strlen
                # + checksum check) accepts the placeholder registry value
                # without needing it to be a genuine WON-checksum-valid key.
                # That keeps everything table-driven: any seed survives, including
                # the empty `""` HL writes for Settings\Key on first launch.
                python3 << PYEOF
            hl_path = "$out/Half-Life/hl.exe"
            data = bytearray(open(hl_path, "rb").read())

            # Skip-dialog patch: turn the `je 0x4224fd` into `jmp 0x4224fd; nop`.
            off = 0x2225b
            assert data[off:off+6] == b"\x0F\x84\x9C\x02\x00\x00", \
                f"hl.exe skip-dialog pattern mismatch at 0x{off:x}: {data[off:off+6].hex()}"
            data[off:off+6] = bytes([0xE9, 0x9D, 0x02, 0x00, 0x00, 0x90])

            # Validator-stub patch: `mov eax, 1; ret 4` at the prologue.
            off = 0x22a1a
            assert data[off:off+3] == b"\x55\x8B\xEC", \
                f"hl.exe validator pattern mismatch at 0x{off:x}: {data[off:off+8].hex()}"
            data[off:off+8] = bytes([0xB8, 0x01, 0x00, 0x00, 0x00, 0xC2, 0x04, 0x00])

            # Resolution-cap patch: unlock widescreen / >1024-wide video modes.
            #
            # The 1.1.1.0 launcher builds its selectable video-mode list in a
            # loop that, for each mode the GL/X driver reports, gates whether
            # the mode is added to the table with two bounds checks at VA
            # 0x413f22:
            #     0x413f22: 81 FE 00 04 00 00   cmp esi, 0x400   ; width  > 1024 ?
            #     0x413f28: 77 12               ja  +0x12        ;   -> reject mode
            #     0x413f2a: 81 FD 90 01 00 00   cmp ebp, 0x190   ; height < 400  ?
            #     0x413f30: 72 0A               jb  +0x0A        ;   -> reject mode
            #     0x413f32: C7 82 ... 01        mov [edx+...], 1 ; accept: store W/H
            # The `cmp esi,0x400 / ja` upper-bound on width is what drops every
            # widescreen / >1024-wide mode (incl. 1920x1080), so stock WON
            # silently falls back to its 640x480 minimum under a 1920x1080
            # gamescope nested display. NOP both rejecting jumps so every mode
            # the X server advertises is accepted; the engine can then select
            # 1920x1080 (seeded into EngineModeW/H by preRun). This is the
            # documented community WON resolution unlock (UCyborg et al.),
            # applied surgically here rather than shipping a separate patcher.
            for off, orig, name in (
                (0x13f28, b"\x77\x12", "width<=1024 JA"),
                (0x13f30, b"\x72\x0A", "height>=400 JB"),
            ):
                assert data[off:off+2] == orig, \
                    f"hl.exe res-cap pattern mismatch ({name}) at 0x{off:x}: {data[off:off+2].hex()}"
                data[off:off+2] = b"\x90\x90"

            # GL-surface-size patch: make the OpenGL render window 1920x1080.
            #
            # Root cause of "320p gameplay" (proven via live GDB): hl.exe's GL
            # window-sizer FUN_004627e0 matches the seeded EngineModeW x H x BPP
            # against the mode table to pick the GL render-surface size, but
            # EngineModeW arrives as 0 -> no row matches -> it falls back to
            # mode index 0 = 320x200, which becomes the real OpenGL surface
            # (gamescope then upscales that blurry 320x200 box). The 1080p menu
            # is a SEPARATE launcher window (-lw/-lh via GetSystemMetrics), which
            # is why the menu is crisp but the 3D world is 320p.
            #
            # Fix: source the GL surface width/height from the launcher-window
            # globals (0x4cfcd0 / 0x4cfcd4), which -lw/-lh set reliably to
            # 1920x1080, instead of the mis-matched mode-table row:
            #   0x46281f: 8B 87 6C 77 CE 03  mov eax,[edi+0x3ce776c]
            #             -> A1 D0 FC 4C 00 90   mov eax,[0x4cfcd0]; nop
            #   0x46283f: 8B 97 70 77 CE 03  mov edx,[edi+0x3ce7770]
            #             -> 8B 15 D4 FC 4C 00   mov edx,[0x4cfcd4]
            off = 0x6281f
            assert data[off:off+6] == b"\x8B\x87\x6C\x77\xCE\x03", \
                f"hl.exe GL-width pattern mismatch at 0x{off:x}: {data[off:off+6].hex()}"
            data[off:off+6] = bytes([0xA1, 0xD0, 0xFC, 0x4C, 0x00, 0x90])

            off = 0x6283f
            assert data[off:off+6] == b"\x8B\x97\x70\x77\xCE\x03", \
                f"hl.exe GL-height pattern mismatch at 0x{off:x}: {data[off:off+6].hex()}"
            data[off:off+6] = bytes([0x8B, 0x15, 0xD4, 0xFC, 0x4C, 0x00])

            open(hl_path, "wb").write(data)
            print("Patched hl.exe: CD-key dialog skip + validator stub + "
                  "resolution-cap unlock + GL-surface 1920x1080 (window-sizer "
                  "sourced from launcher dims 0x4cfcd0/0x4cfcd4)")
            PYEOF
          '';

          copyGlobs = [ ];

          runtime = "proton";

          # Saves persist via the per-game fuse-overlayfs upper (engine writes
          # Half-Life/valve/SAVE/* + config.cfg next to its binary, not under
          # drive_c/users/steamuser/...).
          saveLocations = [ ];
          executable = "Half-Life/hl.exe";

          # Stack mod derivations above _gameData. Each mod ships a
          # Half-Life/<modname>/ subtree that the overlay merges into
          # the game install dir; the engine sees a fat install with
          # every mod's cl_dlls/dlls/maps/... available, exactly as
          # if they were copied in. mkBefore prepends to mk-game's
          # default `[ _gameData ]` so mod files win on path conflict.
          bwrap.overlay.lowers = lib.mkBefore (map toString config.mods);

          # `-gl` (+ the EngineType/EngineDLL registry seed) forces the OpenGL
          # renderer. Without it the engine runs the SOFTWARE renderer
          # (sw.dll), hard-capped at 320x200/640x480 — that was the "starts in
          # 320p" report. This is the load-bearing picture-quality fix.
          #
          # `-windowed` (with EngineModeWindowed=1) keeps the engine in a
          # single windowed GL surface for the whole session: no menu->map
          # ChangeDisplaySettings mode switch, so no Con_CheckResize AV at
          # hw.dll 0x01D229D4 (the crash that killed every `-game <mod>` New
          # Game), AND keyboard/mouse focus reaches the game normally.
          #
          # `-lw 1920 -lh 1080` is the load-bearing native-1080p lever, and
          # the clean replacement for the rejected wine virtual desktop. WON
          # hl.exe is a thin launcher that creates the engine's top-level
          # window and then hands hw.dll a launch struct to render into. Two
          # facts, both confirmed by inspecting hl.exe FUN_00423ec7 and by
          # reading the live X window size under a true 1920x1080 gamescope
          # nest:
          #   * `-w/-h` (and the EngineModeW/H registry seed) only set the
          #     struct's "desired mode" fields. hw.dll IGNORES them for the
          #     windowed/fullscreen GL surface: with EngineModeW/H=1920x1080
          #     seeded AND the mode-cap unlocked, the engine STILL created a
          #     640x480 X window (verified: `xdotool getwindowgeometry`), which
          #     gamescope's --force-windows-fullscreen then UPSCALED to fill
          #     1080p. That blurry 640x480-stretched-to-1080p is exactly the
          #     "windowed floored low-res on the real seat" report — not a
          #     broken test nest.
          #   * `-lw/-lh` set DAT_004cfcd0/DAT_004cfcd4 (the launcher window
          #     width/height) directly, BEFORE hw.dll. With `-lw 1920 -lh 1080`
          #     hl.exe creates a real 1920x1080 top-level window and the engine
          #     renders NATIVELY into it (verified: the HL X window comes up
          #     1920x1080, the menu uses the high-res text scheme, no upscale).
          # This forces the true surface size the same way the wine virtual
          # desktop did, but as a plain engine arg — so there is no wine
          # Explorer desktop, no input grab / cursor capture, and (the operator
          # confirmed) no runaway view spin. gamescope --force-windows-fullscreen
          # then maps the already-1920x1080 window 1:1 onto the nested display
          # with no scaling.
          #
          # `-nojoy` best-effort-disables the joystick. `-w 1920 -h 1080`
          # restates the desired mode for the menu's video list. `-game <mod>`
          # boots mods into their gamedir.
          executableArgs =
            lib.optionals (config.mod != "valve") [
              "-game"
              config.mod
            ]
            ++ [
              "-gl"
              "-windowed"
              "-nojoy"
              "-w"
              "1920"
              "-h"
              "1080"
              "-lw"
              "1920"
              "-lh"
              "1080"
            ];

          preRun = ''
            # Seed a genuinely WON-checksum-VALID CD-key into
            # HKCU\Software\Valve\Half-Life and \Settings. The value matters:
            # the hl.exe IsEmpty/validator patches above only cover the startup
            # DIALOG, but the listen-server (New Game) auth path in swds.dll
            # runs its OWN WON checksum on the key (the GetCDKey routine at the
            # global ptr ds:0x1097a90). A bad-checksum key — e.g. the old
            # 1911111111115 — makes GetCDKey return error + length 0, so the
            # connection-request builder prints "Bogus key length on CD Key" +
            # "Invalid authentication certificate length" and the engine drops
            # to the console instead of spawning the map. 3333333333333 is a
            # WON-valid key (it is the value a working vanilla prefix carries),
            # so server-create succeeds.
            USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
            # preRun runs before proton bootstraps the wineprefix on a truly
            # fresh launch, so user.reg may not exist yet — create a minimal
            # header so wine accepts the seeded section on first load. (See
            # MEMORY: feedback_prerun_userreg_bootstrap.)
            if [ ! -f "$USERREG" ]; then
              mkdir -p "$(dirname "$USERREG")"
              {
                printf 'WINE REGISTRY Version 2\n'
                printf ';; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n'
              } > "$USERREG"
            fi
            if ! grep -q 'Valve\\\\Half-Life\]' "$USERREG"; then
              TS=$(date +%s)
              {
                printf '\n[Software\\\\Valve\\\\Half-Life] %s\n' "$TS"
                printf '"Key"="3333333333333"\n'
              } >> "$USERREG"
            fi
            # The WON server-create (listen-server / New Game) auth path reads
            # the CD key from the *Settings* subkey, NOT the parent
            # Software\Valve\Half-Life\Key the startup dialog uses. On a fresh
            # prefix the engine initialises Settings\Key="" during startup;
            # server-create then sees a zero-length key and bails with
            # "Bogus key length on CD Key" + "Invalid authentication
            # certificate length", dropping to the console instead of spawning
            # the map. The engine only writes Settings\Key="" when the subkey
            # is ABSENT, so pre-seeding a valid 13-digit key here makes it
            # persist (this is exactly why a vanilla persistent prefix, which
            # already holds a non-empty Settings\Key, creates the server fine).
            # Seed the Settings subkey too. Idempotent: skip if it already
            # carries a non-empty Key.
            if ! grep -q 'Valve\\\\Half-Life\\\\Settings\]' "$USERREG"; then
              TS=$(date +%s)
              {
                printf '\n[Software\\\\Valve\\\\Half-Life\\\\Settings] %s\n' "$TS"
                printf '"Key"="3333333333333"\n'
              } >> "$USERREG"
            fi

            # Seed the WON video mode so the engine boots NATIVE 1920x1080
            # from the MENU onward (no upscale-from-low, no mid-session
            # resolution SWITCH). The 1.1.1.0 launcher (hl.exe FUN_00423ec7)
            # reads these EngineMode* values out of
            # HKCU\Software\Valve\Half-Life\Settings and writes them straight
            # back, so a seed persists across launches. Requires the
            # buildScript resolution-cap unlock (without it the launcher drops
            # 1920x1080 from its mode list and floors to 640x480). Values are
            # wine-reg DWORDs:
            #   EngineModeW        = 0x780 (1920)
            #   EngineModeH        = 0x438 (1080)
            #   EngineModeBPP      = 0x20  (32-bit)
            #   EngineModeWindowed = 1     (windowed — keeps a single GL surface
            #     size all session, so no menu->map ChangeDisplaySettings
            #     switch -> no Con_CheckResize crash, and keyboard/mouse focus
            #     reaches the game. See executableArgs.)
            #   EngineModeCaptured = 1     (mode already chosen; skip the
            #     launcher's first-run video dialog)
            #   EngineType         = 2     (OpenGL renderer / hw.dll). CRITICAL:
            #     stock prefixes — and Uplink especially — default to
            #     EngineType=1 (SOFTWARE / sw.dll), whose "surface cache"
            #     rasteriser is hard-capped at 320x200/640x480 and ignores
            #     EngineModeW/H entirely. That was the "starts in 320p" report:
            #     the engine wasn't clamping a 1080p request, it was in the
            #     software renderer the whole time. EngineType=2 + EngineDLL=
            #     hw.dll switch it to OpenGL.
            #   EngineDLL          = "hw.dll"  (the OpenGL/D3D engine module)
            #
            # The engine also writes its own EngineMode* on shutdown, so on an
            # existing prefix the Settings section already carries (stale)
            # values; rewrite in place rather than append. awk: inside the
            # [..\Settings] section, drop any existing EngineMode{W,H,BPP,
            # Windowed,Captured} line, then re-emit our values right after the
            # section header. Idempotent.
            awk '
              BEGIN { ins = 0 }
              /^\[Software\\\\Valve\\\\Half-Life\\\\Settings\]/ {
                print
                print "\"EngineModeW\"=dword:00000780"
                print "\"EngineModeH\"=dword:00000438"
                print "\"EngineModeBPP\"=dword:00000020"
                print "\"EngineModeWindowed\"=dword:00000001"
                print "\"EngineModeCaptured\"=dword:00000001"
                print "\"EngineType\"=dword:00000002"
                print "\"EngineDLL\"=\"hw.dll\""
                # ins guards the line-drop below to this section.
                ins = 1
                next
              }
              /^\[/ { ins = 0 }
              ins && /^"(EngineMode(W|H|BPP|Windowed|Captured)|EngineType|EngineDLL)"=/ { next }
              { print }
            ' "$USERREG" > "$USERREG.strom-tmp" && mv -f "$USERREG.strom-tmp" "$USERREG"

            # NB: a wine VIRTUAL DESKTOP (Software\Wine\Explorer\Desktops) was
            # tried to force a true 1920x1080 surface, but combined with
            # -fullscreen it left the game with NO working input + a runaway
            # view spin under gamescope, so it is deliberately NOT seeded. If a
            # stale prefix still carries it, drop it so input works.
            if grep -q 'Wine\\\\Explorer\\\\Desktops\]' "$USERREG"; then
              awk '
                /^\[Software\\\\Wine\\\\Explorer(\\\\Desktops)?\]/ { skip = 1; next }
                /^\[/ { skip = 0 }
                !skip { print }
              ' "$USERREG" > "$USERREG.strom-tmp" && mv -f "$USERREG.strom-tmp" "$USERREG"
            fi
          '';

          gamescope = {
            output-width = 1920;
            output-height = 1080;
            nested-width = 1920;
            nested-height = 1080;
            flags = {
              "-r" = "60";
              "--immediate-flips" = true;
              "--expose-wayland" = true;
              # Stretch the engine's windowed GL surface to fill the nested
              # display rather than centring it with black borders. INNER-window
              # flag only — the outer gamescope window stays windowed/killable
              # (NOT the forbidden -f/-b).
              "--force-windows-fullscreen" = true;
            };
          };
        };
      }
    )
  ];

  meta = {
    description = "Half-Life (WON v1.1.1.0, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "half-life";
  };
}
