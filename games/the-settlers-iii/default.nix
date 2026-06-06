{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  innoextract,
  unzip,
  writeText,
}:

let
  # The Settlers III (Blue Byte 1998) - GOG "Ultimate Collection" reissue.
  # archive.org item the_settlers_3_-_ultimate_collection_201912 ships
  # the GOG inno-setup installer as a single .exe (no .bin slices), so
  # innoextract pulls the game tree straight out. Files land at the
  # install root (S3.EXE, S3_multi.EXE, SND/, S3/, S3QOTA/, ...); GOG
  # Galaxy/scripted leftovers live under app/, tmp/, commonappdata/,
  # __redist/ and __support/ and are dropped here since strom does not
  # use the Galaxy launcher path.
  src = fetchIpfs {
    cid = "QmaWFgt4NGDQ3uAW17Qj2tZHoujciB2yWersWNNM4Sf69D";
    fallbackUrl = "https://archive.org/download/the_settlers_3_-_ultimate_collection_201912/setup_the_settlers_3_-_ultimate_collection_1.60_v2_english_%2830349%29.exe";
    hash = "sha256-1P2AGJKpECsVq2jMUguvpL1rwI1c05mqLn0dlAUhuig=";
    name = "the-settlers-iii-gog-1.60-v2-english.exe";
  };

  # FunkyFr3sh's cnc-ddraw: a community DirectDraw->OpenGL/D3D9/GDI wrapper
  # for old Windows games on Wine. S3.EXE renders through DirectDraw 6/7
  # (it GetProcAddress's DirectDrawEnumerateA and creates exclusive
  # full-screen surfaces). Under proton's wined3d the DDraw display-mode
  # init fails inside the gamescope nest and S3.EXE exits during startup
  # before it ever opens its own data files. cnc-ddraw renders windowed
  # into a normal Win32 window that gamescope can composite.
  # https://github.com/FunkyFr3sh/cnc-ddraw
  cncDdraw = fetchurl {
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-CxOriaZMmRgYmx2t1EnvbtPLO3sZyr2W2K29lVBbuQg=";
    name = "cnc-ddraw.zip";
  };

  # cnc-ddraw config, cloned from the repo's known-working RTS games (Red
  # Alert 2, Anno 1602/1503). The proven pattern for an edge-scroll RTS under
  # gamescope is: cnc-ddraw renders a windowed OpenGL surface with maintas +
  # adjmouse + handlemouse + nonexclusive, and gamescope does the upscale from
  # the native nest to 1080p (with --force-grab-cursor, see the gamescope
  # block, which is what actually fixes edge-scroll). renderer=opengl matches
  # the reference exactly: auto can pick a path that misbehaves under the grab.
  #
  # The S3 engine renders at its internal "Resolution" mode (0=640x480,
  # 1=800x600, 2=1024x768; verified from S3.EXE's mode dispatch). The registry
  # seed picks 2 (1024x768, the max native mode); gamescope upscales the nest
  # to 1080p. (No clean true-16:9 path exists: the Community Edition / s3ce
  # widescreen route is gated behind the aLobby account client AND capped at
  # 900px height, so it can neither reach real 1080p nor stay serial-prompt-
  # free.)
  #
  # This GOG release ships NO video files (no .avi/.smk/.bik - only the
  # ir50_*.dll Indeo codec stubs and empty 156-byte GFX slideshow packs); what
  # looks like a "video" is the engine's own DirectDraw cinematic slideshow,
  # rendered through the same native surface.
  ddrawIni = writeText "ddraw.ini" ''
    [ddraw]
    renderer=opengl
    windowed=true
    fullscreen=false
    maintas=true
    adjmouse=true
    handlemouse=true
    nonexclusive=true
    maxfps=60
    singlecpu=true
    no_compat_warning=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-settlers-iii";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$out" "$src"
    chmod -R u+w "$out"

    # Defeat the per-session campaign serial-number ("CD-key") prompt by
    # patching the two engine routines that actually spawn the serial-entry
    # dialog so they fall straight through to their "serial confirmed" exit.
    #
    # S3.EXE (PE32, ImageBase 0x400000, .text RVA==raw so file offset =
    # VA-0x400000). The dialog is the engine's own DirectDraw UI: a helper
    # FUN_005faaa0(dialogId, -1) creates/shows it; dialogId 0x90004 is the
    # "Please enter your Settlers III serial number" entry box and 0x90017
    # the "wrong serial, try again" box. Two functions run that entry loop on
    # single-player / campaign entry:
    #
    #   * FUN_00476920 (the live campaign-button gate; confirmed by GDB - the
    #     0x90004 dialog spawns from its call site 0x476a2b on every campaign
    #     click). Structure:
    #         iVar = FUN_0040a140(...stored serial DAT_007a7868...)
    #         if (iVar == 0 || FUN_00411d10(typed) == 0) { ...serial loop... }
    #         return local_81;            // local_81 initialised to 1
    #     The leading `iVar == 0` is why the previous validator-only patch did
    #     nothing: the stored serial DAT_007a7868 is blank, so FUN_0040a140
    #     returns 0, the `||` short-circuits and FUN_00411d10 is never reached
    #     - the dialog loop runs regardless of the validator's return value.
    #     (GDB confirmed 0x411d10 was never hit while the dialog popped.)
    #   * FUN_00439540 (the other single-player entry path): same dialog loop,
    #     gated by a single `SETZ AL; TEST AL,AL; JZ <success>` at 0x43961a.
    #
    # Both functions reach a clean "confirmed" exit label with local_81/return
    # already holding the success value, so unconditionally jumping the gate to
    # that label suppresses the dialog AND leaves the engine in the exact state
    # its OK-handler would set (campaign entry then proceeds normally). All
    # patches are length-preserving near-jumps - no relocation/section resize.
    #
    #   0x43961a  FUN_00439540 gate: JZ 0x439979 -> JMP 0x439979 (+nop)
    #             0f 84 59 03 00 00 -> e9 5a 03 00 00 90
    #   0x476a00  FUN_00476920: JNZ 0x476a19 (into dialog) -> JMP 0x476a13
    #             (skip the blank-serial branch, fall to the validator-result
    #             branch) 75 17 -> eb 11
    #   0x476a13  FUN_00476920: JNZ 0x476d01 -> JMP 0x476d01 (unconditional
    #             success, dialog at 0x476a2b unreachable)
    #             0f 85 e8 02 00 00 -> e9 e9 02 00 00 90
    #
    # The validator FUN_00411d10 @ 0x11d10 is additionally forced to return 1
    # (mov eax,1; ret 0x4). It is no longer on the dialog path, but it is also
    # called by the startup registry load (FUN_0040d700), which BLANKS the
    # in-session serial when it reports invalid; pinning it to "valid" keeps
    # that path from wiping state. Defensive, harmless, length-preserving.
    #
    # Each site is gated on its exact original bytes (and the whole asset on
    # sha256) so the build fails loudly if S3.EXE ever changes.
    s3exe="$out/S3.EXE"
    expected_sha=00a925cfdcfc3349b5d0f3b8a4c312f01b813e363b4464f6f3d6de17804d950b
    actual_sha=$(sha256sum "$s3exe" | cut -d' ' -f1)
    if [ "$actual_sha" != "$expected_sha" ]; then
      echo "S3.EXE sha256 mismatch: got $actual_sha, expected $expected_sha" >&2
      echo "serial-prompt patch targets a specific build; refusing to patch blindly." >&2
      exit 1
    fi
    # patch_site <file-offset> <expected-hex> <replacement-hex>
    patch_site() {
      __off=$1; __want=$2; __new=$3
      __len=$(( ''${#__want} / 2 ))
      __got=$(dd if="$s3exe" bs=1 skip=$(($__off)) count=$__len 2>/dev/null \
                | od -An -tx1 | tr -d ' \n')
      if [ "$__got" != "$__want" ]; then
        echo "unexpected bytes at offset $__off: got $__got, want $__want" >&2
        echo "serial-prompt patch targets a specific build; refusing to patch." >&2
        exit 1
      fi
      printf "$(printf '\\x%s' $(echo "$__new" | sed 's/../& /g'))" \
        | dd of="$s3exe" bs=1 seek=$(($__off)) conv=notrunc 2>/dev/null
    }
    # FUN_00476920 - the live campaign-button gate (skip dialog -> success)
    patch_site $((0x76a00)) 7517         eb11
    patch_site $((0x76a13)) 0f85e8020000 e9e902000090
    # FUN_00439540 - the other single-player entry gate
    patch_site $((0x3961a)) 0f8459030000 e95a03000090
    # FUN_00411d10 - validator pinned valid (startup serial-blank guard)
    patch_site $((0x11d10)) 81ec080100005556 b801000000c20400

    # S3.EXE statically imports _INMM.dll - GOG's CD-audio emulation shim
    # that plays the ripped Vorbis soundtrack (MUSIC/*.ogg via the bundled
    # libvorbisfile-3.dll) in place of real CD audio. The GOG installer's
    # Galaxy .script copies __support/add/winmm.dll into the install root as
    # _INMM.dll; strom skips the Galaxy path, so do it here. Without this
    # file S3.EXE fails to load with STATUS_DLL_NOT_FOUND and exits instantly
    # before any window appears.
    cp "$out/__support/add/winmm.dll" "$out/_INMM.dll"

    # CD-presence markers. On entering a campaign the engine asks "which
    # disc is this content on" and probes for a 0-byte marker .DAT in the
    # current dir (the install root) named after that disc - S3GOLD2.DAT for
    # the Gold main campaign ("CD2"), S3MCD1.DAT for the Mission CD,
    # S3GOLD1/S3QOTA1 for the other modes. If the marker is absent it pops
    # "Please insert CDx in your CD-ROM drive" and blocks. The retail discs
    # carried these markers at their root; GOG reproduces them as empty
    # files under app/ (S3CD1/S3CD2 already sit at the install root, the
    # rest only under app/). Hoist them to the root before app/ is dropped
    # so every campaign mode's disc check passes with no prompt.
    for __m in S3.DAT S3GOLD1.DAT S3GOLD2.DAT S3MCD1.DAT S3QOTA1.DAT; do
      [ -e "$out/app/$__m" ] && cp "$out/app/$__m" "$out/$__m"
    done

    # Drop GOG Galaxy / installer scaffolding; the engine only needs the
    # tree at the install root (S3.EXE + data dirs + _INMM.dll above).
    rm -rf \
      "$out/tmp" \
      "$out/commonappdata" \
      "$out/__redist" \
      "$out/__support" \
      "$out/app"
    rm -f \
      "$out"/goggame-*.* \
      "$out/goggame_noxp.sdb" \
      "$out/directplay.cmd"

    # Ship cnc-ddraw's ddraw.dll next to S3.EXE. Strip any case variants
    # first so the loose override is unambiguous on Wine's case-insensitive
    # FS (the GOG tree has none, but be defensive).
    rm -f "$out"/ddraw.dll "$out"/Ddraw.dll "$out"/DDraw.dll "$out"/DDRAW.DLL
    unzip -o ${cncDdraw} ddraw.dll -d "$out/"
    cp ${ddrawIni} "$out/ddraw.ini"
  '';

  runtime = "proton";
  executable = "S3.EXE";

  # `n,b`: load the bundled native cnc-ddraw ddraw.dll first, builtin as
  # fallback. WINE_LARGE_ADDRESS_AWARE keeps the 1998 32-bit engine from
  # OOMing under modern address-space layout.
  #
  # PULSE_SERVER points winepulse.drv at the host pipewire-pulse socket
  # directly, fixing the "DirectSound error" dialog at startup. Root cause:
  # the strom gamescope wrapper runs each launch under a private
  # $XDG_RUNTIME_DIR (a strom-gs-XXXXXX dir) and symlinks `pulse` into it
  # (lib/gamescope.nix). libpulse refuses to use $XDG_RUNTIME_DIR/pulse when
  # it is a symlink (it wants to own that dir, 0700) and aborts the
  # connection with "Failed to create secure directory (...): Too many levels
  # of symbolic links". winepulse.drv then fails, mmdevapi falls back to
  # winealsa.drv (which also unloads), and S3's DirectSoundCreate gets no
  # usable device -> the engine pops its "DirectSound error" box. Setting
  # PULSE_SERVER to the absolute server socket makes libpulse connect to it
  # straight away and skip the $XDG_RUNTIME_DIR/pulse directory probe
  # entirely. On this NixOS host pipewire-pulse listens on the system socket
  # /run/pulse/native (verified: `PULSE_SERVER=unix:/run/pulse/native pactl
  # info` returns the live server with a default sink); /run is shared into
  # the bwrap sandbox, so the socket is reachable in-prefix. Modern Wine's
  # dsound (rewritten on mmdevapi) reads NO HKLM DirectSound config keys -
  # only HKCU\Software\Wine\DirectSound\HelBuflen - so the classic
  # HardwareAcceleration/DefaultBitsPerSample/DefaultSampleRate reg keys are
  # dead code here and are deliberately NOT seeded; the fix is purely getting
  # the audio backend reachable.
  env = {
    WINEDLLOVERRIDES = "ddraw=n,b";
    WINE_LARGE_ADDRESS_AWARE = "1";
    PULSE_SERVER = "unix:/run/pulse/native";
  };

  # Saves persist via the per-game fuse-overlayfs upper: the engine writes
  # savegames next to its binary (under SAVEGAME/ in the install tree),
  # not under drive_c/users/steamuser/...
  saveLocations = [ ];

  # Overwrite ddraw.ini in the overlay every launch (cnc-ddraw mutates it
  # in place with posX/posY/savesettings, and a stale upper-layer copy
  # would shadow the nix-store lower).
  #
  # S3.EXE reads HKLM\Software\BlueByte\Siedler3\1.0 (RegOpenKeyExA) and
  # App Paths\s3.exe at startup; without them the engine's sSiedler3Path
  # is empty and Resolution/Language are unreadable, so it exits before
  # touching any game data. The GOG installer normally seeds these via
  # regs.cmd; strom skips the Galaxy path, so replicate the key subset the
  # engine needs into system.reg on first launch. S3.EXE is 32-bit, so the
  # keys live under Wow6432Node (mirrored under the plain key as
  # belt-and-braces). GAMEDIR_WIN is the in-prefix Z: path mapping the
  # fuse-overlayfs install tree.
  preRun = ''
    install -m 644 ${ddrawIni} "$GAMEDIR/ddraw.ini"

    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
    if [ -f "$SYSREG" ] && ! grep -q 'BlueByte\\\\Siedler3\\\\1.0\\\\Patches' "$SYSREG"; then
      TS="$(date +%s)"
      seed_keys() {
        # $1 = key prefix (with or without Wow6432Node)
        printf '\n[%s\\\\BlueByte] %d\n' "$1" "$TS"
        printf '\n[%s\\\\BlueByte\\\\Siedler3] %d\n' "$1" "$TS"
        printf '\n[%s\\\\BlueByte\\\\Siedler3\\\\1.0] %d\n' "$1" "$TS"
        printf '\n[%s\\\\BlueByte\\\\Siedler3\\\\1.0\\\\General] %d\n' "$1" "$TS"
        # Resolution selects the engine's internal render mode: 0=640x480,
        # 1=800x600, 2=1024x768 (the only three modes; verified from S3.EXE's
        # mode dispatch). 2 = the max native mode; cnc-ddraw presents it 1:1
        # and gamescope upscales the nest to 1080p (see the gamescope block).
        printf '"Resolution"=dword:00000002\n'
        printf '"NoAlpha"=dword:00000000\n'
        printf '"FogSpeed"=dword:00000001\n'
        printf '"GDIMouse"=dword:00000001\n'
        printf '"WaitVBlank"=dword:00000001\n'
        printf '"ScrollMode"=dword:00000000\n'
        printf '"ScrollSpeed"=dword:00000005\n'
        printf '"SoundFormat"=dword:00000001\n'
        printf '"CDAudio"=dword:00000002\n'
        printf '"VideoFormat"=dword:00000001\n'
        printf '"Intro"=dword:00000000\n'
        printf '"Language"=dword:00000009\n'
        printf '"Plus"=dword:00000001\n'
        printf '"Gold"=dword:00000001\n'
        printf '"BuildHelp"=dword:00000001\n'
        printf '"Newbie"=dword:00000000\n'
        printf '"FirstLogon"=dword:00000001\n'
        printf '"Playername"="Player"\n'
        printf '"Font"="MS Sans Serif"\n'
        printf '"FontSize"=dword:0000000f\n'
        # SingleNumber is the game's serial / CD-key. On entering Campaign
        # (or any non-Tutorial single-player mode) the engine pops a custom
        # DirectDraw-rendered dialog "Please enter your Settlers III serial
        # number:" and blocks until a serial is typed.
        #
        # KNOWN LIMITATION (not yet bypassable via registry): this prompt is
        # gated by an in-session "serial confirmed" flag that ONLY the dialog's
        # OK handler sets - it is NOT gated by any persistent registry value.
        # This was verified exhaustively under this proton build:
        #   * Seeding the GOG regs.cmd plaintext (serial repeated 4x) -> the
        #     engine reads it, rejects it, blanks SingleNumber to "" and prompts.
        #   * Capturing the engine's OWN accepted state (the encrypted 48-byte
        #     blob it writes after the user types the valid serial, plus the
        #     matching Campaigns/CampaignsPlus blobs) and seeding that EXACT
        #     byte-identical state on the next launch -> the engine reads it
        #     fine (does not blank it) yet STILL prompts.
        # i.e. the registry state that exists immediately after a successful
        # in-game serial entry does not prevent the prompt on a fresh launch.
        # Defeating it requires a binary patch of the engine's campaign-entry
        # serial gate (the prompt text lives in GFX/siedler3_09.*.dat, not in
        # S3.EXE, and the dialog is the engine's own UI - no Win32 DialogBox or
        # in-exe string to anchor a patch yet), or the user typing the serial
        # 0497-2584-2194-4356-2336 once per session into the dialog.
        #
        # The plaintext value below is what GOG's regs.cmd writes (the GOG-
        # issued key 0497-2584-2194-4356-2336 concatenated 4x, no separator);
        # it is kept because it is the canonical/documented value, is harmless,
        # matches what would satisfy the engine on stock Windows, and may be
        # honoured by a future proton/wine that validates it the way Windows
        # does. It does NOT currently suppress the prompt here.
        printf '"SingleNumber"="0497-2584-2194-4356-23360497-2584-2194-4356-23360497-2584-2194-4356-23360497-2584-2194-4356-2336"\n'
        printf '"Mission"=dword:00000001\n'
        printf '"Tips&Tricks"=dword:00000001\n'
        printf '"MessageLevel"=dword:00000009\n'
        printf '"GameZoneSelection"=dword:000001ff\n'
        # Campaigns / CampaignsPlus are the engine's per-campaign unlock
        # bitfields (the obfuscated blobs FUN_00410370 reads at 0x410370 and
        # XOR-deobfuscates). regs.cmd seeds them so every mission is unlocked;
        # without them the campaign list can come up empty/locked. These are
        # the exact REG_BINARY values regs.cmd writes (system.reg stores
        # REG_BINARY as hex(3):<comma bytes>, line-continued with \ + leading
        # spaces, same as wine's own writer).
        printf '"Campaigns"=hex:20,72,d5,87,23,9c,bf,aa,b1,14,78,5c,d2,f9,5b,63,13,57,\\\n'
        printf '  37,5b,7a,65,7b,3d,7b,3b,48,62,fa,a0,77,6c,56,7a,43,1a,81,91,32,a4,df,\\\n'
        printf '  fb,53,70,e2,48,2b,ed,1b,87,31,b1,d1,00\n'
        printf '"CampaignsPlus"=hex:c2,43,d4,d6,2c,17,a2,80,e4,d1,56,8b,a1,94,17,72,\\\n'
        printf '  d9,5b,9d,40,04,23,cd,69,74,1a,0b,cc,f4,c5,c6,c6,b8,e1,60,d8,b5,ee,16,\\\n'
        printf '  73,0c,63,59,75,b3,b7,e5,2c,d2,db,bd,b7,20,00\n'
        printf '"ClanFlag"=dword:00000000\n'
        printf '"BannerId"=dword:00000000\n'
        printf '"BannerSubId"=dword:00000000\n'
        # Patches\convert=0: GOG pre-applies the 1.60 update (the converted
        # Gfx\Siedler3_60.*.dat already ships in the tree). Without this key
        # the engine thinks the conversion is pending, tries to run
        # Update.exe / FileConvert.exe off the (absent) CD, fails, and pops
        # "Your Settlers III installation is corrupt!" before exiting.
        printf '\n[%s\\\\BlueByte\\\\Siedler3\\\\1.0\\\\Patches] %d\n' "$1" "$TS"
        printf '"convert"="0"\n'
        # App Paths\s3.exe: the (Default) value is the engine's install
        # path (sSiedler3Path). The Path value is the directory.
        printf '\n[%s\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\App Paths\\\\s3.exe] %d\n' "$1" "$TS"
        printf '@="%s\\\\S3.EXE"\n' "$GAMEDIR_WIN"
        printf '"Path"="%s\\\\"\n' "$GAMEDIR_WIN"
      }
      {
        seed_keys 'Software\\Wow6432Node'
        seed_keys 'Software'
      } >>"$SYSREG"
    fi

    # Idempotent Resolution upgrade (runs EVERY launch, in addition to the
    # first-launch seed above). The seed block only fires on a brand-new
    # prefix (it is gated on the absence of the ...\1.0\Patches key), so a
    # prefix created before this default.nix shipped Resolution=2 stays stuck
    # at the engine's 640x480 default. Here we reconcile the value in-place,
    # touching ONLY the "Resolution" line inside each ...\1.0\General section,
    # without re-seeding or duplicating any key. If the value is already
    # correct in both sections the file is left byte-for-byte untouched.
    #
    # On-disk wine system.reg uses doubled backslashes in section headers, so
    # the General sections read literally:
    #   [Software\\Wow6432Node\\BlueByte\\Siedler3\\1.0\\General] <ts>
    #   [Software\\BlueByte\\Siedler3\\1.0\\General] <ts>
    # awk walks the file line by line, tracking whether the current section is
    # one of those two General sections; within such a section it rewrites a
    # stray "Resolution"=dword:... to dword:00000002, and if the section ends
    # (next "[" header or EOF) without a Resolution line it injects one right
    # after the header. Sections it does not recognise are passed through
    # verbatim. It exits non-zero (no change) when nothing needed editing, so
    # we only rewrite the file when a real change was made.
    if [ -f "$SYSREG" ]; then
      __sysreg_tmp="$SYSREG.strom.tmp"
      if awk '
        # Is $0 a [Software...\1.0\General] section header for either variant?
        function is_general_header(line) {
          return line ~ /^\[Software\\\\(Wow6432Node\\\\)?BlueByte\\\\Siedler3\\\\1\.0\\\\General\]/
        }
        # When leaving a General section, ensure a Resolution line was emitted.
        function close_section() {
          if (in_general && !seen_res) {
            print "\"Resolution\"=dword:00000002"
            changed = 1
          }
          in_general = 0
          seen_res = 0
        }
        /^\[/ {
          close_section()
          if (is_general_header($0)) { in_general = 1 }
          print
          next
        }
        in_general && /^"Resolution"=dword:/ {
          seen_res = 1
          if ($0 != "\"Resolution\"=dword:00000002") {
            print "\"Resolution\"=dword:00000002"
            changed = 1
          } else {
            print
          }
          next
        }
        { print }
        END { close_section(); exit (changed ? 0 : 1) }
      ' "$SYSREG" >"$__sysreg_tmp"; then
        # awk returned 0 -> it made a change; swap the file in atomically.
        cat "$__sysreg_tmp" >"$SYSREG"
      fi
      rm -f "$__sysreg_tmp"
    fi
  '';

  # Cloned verbatim from Anno 1602's gamescope block (the same 1024x768 -> 1080p
  # 4:3 RTS case). The nest is the game's NATIVE 1024x768; gamescope upscales
  # to the 1080p output. --force-grab-cursor is the edge-scroll fix: all the
  # repo's working RTS games (Red Alert 2, Anno 1602, Anno 1503) set it. It
  # confines the pointer to the nest so S3's mouse-position-based edge-scroll
  # reaches the viewport edge instead of the cursor escaping the window. Outer
  # gamescope stays windowed (no -f/-b).
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags."--expose-wayland" = true;
    flags."--force-grab-cursor" = true;
  };

  meta = {
    description = "The Settlers III (Blue Byte 1998, GOG Ultimate Collection v1.60 v2 English, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-settlers-iii";
  };
}
