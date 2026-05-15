{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unzip,
}:

# Total Overdose (Deadline Games 2005) runs under Proton with the stock
# binkw32.dll and no DLL overrides.
#
# Sources:
#   * `src` — Redump-verified European retail DVD ISO (En, Fr, De, Es, It;
#     MD5 7a53e4e4c28e7c020a43f164f3db1eab). Carries the full data set:
#     `blocks.naz`, `sounds.naz` (global music/dialogue/ambient),
#     `uk/de/fr/es/it_sounds.naz`, `videos00.naz`, `videos01.naz`.
#     The retail TOD.exe in the ISO is SafeDisc-wrapped (10,395,648 bytes)
#     and on launch pops "Please insert the original Total Overdose DVD"
#     because wine cannot run the SafeDisc layer (SafeDisc requires
#     `SECDRV.SYS`, disabled on Win10/MS15-097 and not implemented in
#     wine — see PCGamingWiki SafeDisc article).
#   * `nodvdSrc` — pre-cracked install rip whose TOD.exe (18,032,384 bytes,
#     MD5 01e1b37ce90d4d7cfda53bb868bac1bb) has the SafeDisc wrapper
#     stripped. The rest of that archive (blocks.naz, videos00.naz, DLLs)
#     is byte-identical to the ISO, but `sounds.naz` and the locale-/
#     videos01 packs were never extracted from the original media — which
#     is why rounds 1-2 had silent music/dialogue. We splice: data files
#     from the ISO, TOD.exe from the cracked rip.
#
# Round-1 audio fixes are retained:
#   * `executable = "TOD.exe"` skips the launcher.exe shell-exec, which
#     would exit early under proton's waitforexitandrun and clip the
#     Diesel DirectSound init in the orphaned child.
#   * `preRun` seeds `HKCU\Software\Eidos\Total Overdose\SoundRenderer=2`
#     (DSOUND) so the engine bypasses the AM3D "Diesel Power 3D" software
#     mixer whose tight cadence stalls under wine.
#   * 32-bit `systemd` in `targetPkgs` so the 32-bit `winepulse.drv`
#     finds a matching ELFCLASS32 `libudev.so.1`.
let
  src = fetchIpfs {
    cid = "QmcZppB5Y4djdJkTDMoKpS5rWkpFhvEpSZC4aQS8VH8Z9W";
    fallbackUrl = "https://archive.org/download/totaloverdoseeuropeenfrdeesit/Total%20Overdose%20%28Europe%29%20%28En%2CFr%2CDe%2CEs%2CIt%29.iso";
    hash = "sha256-23ASxfCzTTY6iOST+y/4NqVzRDBtjkhiRqO3QISD0Kw=";
    name = "total-overdose-eu.iso";
  };
  nodvdSrc = fetchIpfs {
    cid = "QmTtaBsdWEYtwddHrdH7qMP7KRCu8sGKywTrxD65nutdAY";
    fallbackUrl = "https://archive.org/download/total-overdose_202112/Total_Overdose_PC-Game.zip";
    hash = "sha256-1djeZBgOdoBl4Rc/5LQOxPoW/+gwaYVrLpHA9r1rpUs=";
    name = "total-overdose-nodvd.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "total-overdose";

  inherit src;

  nativeBuildInputs = [
    p7zip
    unzip
  ];

  # Layout: game files on the ISO live at "Program Files/Eidos/Total
  # Overdose/" (alongside an ignored DirectX9/ redist + setup_*.msi at the
  # ISO root). After dropping those into $out, overwrite TOD.exe with the
  # SafeDisc-stripped 18 MB build from the no-DVD rip — every other file
  # in the rip is byte-identical to the ISO so we only need that one
  # binary.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iso" "$TMPDIR/nodvd"
    7z x -y "$src" -o"$TMPDIR/iso" >/dev/null
    cp -r "$TMPDIR/iso/Program Files/Eidos/Total Overdose"/. "$out"/

    unzip -q "${nodvdSrc}" -d "$TMPDIR/nodvd"
    cp -f "$TMPDIR/nodvd/Total Overdose/TOD.exe" "$out/TOD.exe"
  '';

  runtime = "proton";
  # TotalOverdose.exe is a 52KB launcher that ShellExecutes TOD.exe
  # (the real 10MB game). Under proton's `waitforexitandrun` the
  # launcher exits a few ms after spawning TOD.exe, wineserver enters
  # shutdown mode, and the Diesel engine's DirectSound init in the
  # orphaned child gets clipped — cutscene audio mixes silent, in-game
  # SFX intermittently miss. Skip the launcher and run TOD.exe directly
  # so proton wraps the right process and audio init runs against a
  # live wineserver. Same pattern as NOLF's lithtech.exe bypass.
  executable = "TOD.exe";

  saveLocations = [ "Documents/Total Overdose" ];

  # The Diesel engine offers three audio renderers (TOD_tools enum
  # SoundSystemType, StreamedSoundBuffers.h):
  #   1 = AUTOSELECT (picks DIESELPOWER for stereo, DSOUND for surround)
  #   2 = DSOUND     (plain DirectSound)
  #   3 = DIESELPOWER (custom AM3D "Diesel Power 3D" software mixer)
  # The renderer id lives in the Windows registry at
  #   HKCU\Software\Eidos\Total Overdose\SoundRenderer (REG_DWORD)
  # On a fresh prefix the key is absent, AUTOSELECT picks DIESELPOWER on
  # wine's default stereo speaker config, and the AM3D mixer's tight
  # output cadence stalls under wine — music/dialogue/ambient channels go
  # silent while short DSOUND-backed SFX (gunfire, menu clicks) still
  # play. Same root cause as the long-standing WineHQ bug #27603 /
  # #30836 reports.
  #
  # Seed SoundRenderer=2 (DSOUND) into user.reg if absent so the engine
  # skips AM3D and uses DirectSound from launch. On a truly fresh prefix
  # user.reg doesn't exist yet (proton creates it on first run, after
  # preRun); the guard is the freelancer-style "wait for proton bootstrap
  # then append" pattern, so on a brand-new install the first launch
  # still uses the broken Diesel renderer and only the second launch
  # picks up the seed. Subsequent launches keep DSOUND. If the user
  # flips the renderer in the in-game Sound Setup menu, the engine
  # writes the same registry value and our grep guard leaves the
  # user-chosen setting alone.
  #
  # DirectInput MouseWarpOverride=disable (Software\Wine\DirectInput).
  # Round-3 +dinput trace evidence: Diesel grabs the mouse with
  # DISCL_EXCLUSIVE|DISCL_FOREGROUND, which makes wine's dinput8 run its
  # warp_check loop on every mouse delta — ClipCursor every 10ms while the
  # engine is also re-centering the cursor itself each frame. The fighting
  # warp/clip cycle is the visible jank on fast flicks; it manifests as
  # cursor stutter even when the gamescope --force-grab-cursor flag has
  # already given the engine clean relative deltas.
  #
  # Setting MouseWarpOverride to "disable" tells wine's dinput8 to skip
  # the warp/ClipCursor cycle entirely (mouse.c: impl->warp_override =
  # WARP_DISABLE short-circuits both the WM_MOUSEMOVE and rawinput paths)
  # and let the engine handle cursor positioning. The value is REG_SZ.
  #
  # The earlier DefaultBufferSize=512 seed was dead code: current wine
  # never reads it, and the +dinput trace shows the engine calls
  # SetProperty(DIPROP_BUFFERSIZE, 30) itself right after CreateDevice —
  # so any registry-side default is overwritten on every launch.
  #
  # Bootstrap user.reg with a valid wine-format header before seeding so
  # the registry tweaks below take effect on the FIRST launch, not the
  # second. Without this, the original "seed only if user.reg exists"
  # guard skipped both keys on a fresh prefix (proton doesn't create
  # user.reg until after preRun finishes), and the first launch ran
  # with broken-Diesel audio AND no MouseWarpOverride.
  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    USERREG="$PFX/user.reg"
    mkdir -p "$PFX"
    if [ ! -f "$USERREG" ]; then
      printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\.Default\n\n' > "$USERREG"
    fi
    if ! grep -q '"SoundRenderer"' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Eidos\\\\Total Overdose] %s\n' "$TS"
        printf '"SoundRenderer"=dword:00000002\n'
      } >> "$USERREG"
    fi
    if ! grep -q '"MouseWarpOverride"' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Wine\\\\DirectInput] %s\n' "$TS"
        printf '"MouseWarpOverride"="disable"\n'
      } >> "$USERREG"
    fi
  '';

  # TOD.exe is 32-bit and proton loads the 32-bit winepulse.drv
  # (i386-unix/winepulse.so), which links against libudev.so.1.
  # The baseline FHS chroot ships only 64-bit systemd, so the 32-bit
  # loader picks /usr/lib/libudev.so.1 (ELFCLASS64) and refuses it with
  #   err:module:get_builtin_unix_funcs failed to load winepulse.so:
  #   libudev.so.1: wrong ELF class: ELFCLASS64
  # winepulse.drv then fails to init, dsound falls back to a degraded
  # path that produces underruns ("DSOUND_PerformMix Probable buffer
  # underrun" + endless "Overwriting mixing position, case 1"), and
  # cutscene audio is silent while in-game SFX drop. Add 32-bit systemd
  # so /usr/lib32/libudev.so.1 exists for the 32-bit driver.
  targetPkgs = p: [ p.pkgsi686Linux.systemd ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Force relative mouse mode so gamescope sends pure deltas to
      # Xwayland; without this the absolute Wayland coordinates leak
      # through and the Diesel engine's input handler chokes on
      # the per-pixel event flood, producing visible jank on fast
      # mouse movement. Same fix pattern as games/aquanox.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Total Overdose: A Gunslinger's Tale in Mexico (Deadline Games 2005, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "total-overdose";
  };
}
