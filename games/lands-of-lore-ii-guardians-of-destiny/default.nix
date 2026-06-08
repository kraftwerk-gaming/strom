{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
  p7zip,
  unzip,
}:

let
  # Lands of Lore II: Guardians of Destiny (Westwood Studios / Virgin
  # Interactive 1997). 4-CD Win95 DirectX/Direct3D retail set (US, en,
  # v1.06), redump-verified ISOs from the Internet Archive item
  # Westwood_Lands_of_Lore_Guardians_of_Destiny_Win95-MSDOS_1997_Eng.
  #
  # No DRM-free digital re-release exists (GOG/Steam carry only the first
  # Lands of Lore), so there is no innoextract-able installer. The retail
  # InstallShield setup is interactive (sound-card + install-dir prompts)
  # and cannot run non-interactively at build time.
  #
  # We do NOT need it: the game data is stored UNCOMPRESSED on the discs.
  # CD1 \INSTALL is the complete C:\WESTWOOD\LOLG tree the installer would
  # copy (LOLG95.EXE, LOLG.DAT, MSS32.DLL, HMI sound drivers, OPTIONS.INI
  # config, and the core *.MIX data). The remaining game data lives as
  # plain *.MIX files at the root of each CD. So we reproduce the install
  # by copying CD1/INSTALL plus every root *.MIX from all four discs into
  # one directory, then launch with `LOLG95.EXE -CD .` so the engine reads
  # CD content from the game dir and never asks for a disc swap (and needs
  # no CD key). This mirrors the sibling lands-of-lore-the-throne-of-chaos
  # "copy the installed tree at build time" recipe.
  #
  # The one file the install tree lacks is lolsetup.ini, which the
  # InstallShield setup writes (and which LOLG95.EXE requires at startup);
  # we seed a conservative copy in buildScript (see ./LOLSETUP.INI).
  cd =
    name: hash: cid:
    fetchIpfs {
      inherit cid name hash;
      fallbackUrl = "https://archive.org/download/Westwood_Lands_of_Lore_Guardians_of_Destiny_Win95-MSDOS_1997_Eng/${name}";
    };

  cd1 =
    cd "LOLG_CD1of4.iso" "sha256-zAVPhcZtehzvkDwYmZMzEqMFWBb3bJprixUF80Pcy90="
      "QmPjapo3soDkDW3a3pSdV7g66ozEktqMDiBDRMQz4vNd3h";
  cd2 =
    cd "LOLG_CD2of4.iso" "sha256-Wrwiczfz2kGMT91kjAvmaNQDqtKz5cv2BCKv36OLw6s="
      "QmUq4yKd5gqRpvD1Y5p3nLQteWAJH8ZvQgALJW3exYh4JD";
  cd3 =
    cd "LOLG_CD3of4.iso" "sha256-ZD7C3ReDBONc25IDrLuek2Pgb1avBD6C/7lzcFTPkhE="
      "QmRWs2djkheWQ5KFEhbfQ66pXA6BiYqaKgRgjayeLriUvG";
  cd4 =
    cd "LOLG_CD4of4.iso" "sha256-xTGNvexeFAd7ViLmk5AgqSLEFmpFAYPkjTSReHdf0SA="
      "QmYkiMpHporgDAQqMy7UesXdmyAsu43Je5xh11ZniYahvr";

  # cnc-ddraw: an open-source DirectDraw wrapper built for late-90s Westwood /
  # Command & Conquer titles, re-implementing DirectDraw on OpenGL. The
  # Westwood VQA movie player blits each decoded frame onto the DirectDraw
  # FRONT BUFFER with IDirectDrawSurface::Blt. Under Proton's builtin (wined3d)
  # ddraw every front-buffer Blt is a synchronous GPU command-stream round-trip
  # (ddraw_surface_update_frontbuffer -> wined3d_device_context_blt), which
  # starves the player's per-frame timing so it spins re-blitting frame 1
  # forever at 100% CPU (gdb caught the loop at LOLG95 0x4d4684 -> 0x506c4a
  # `call [ecx+0x14]` = Blt). cnc-ddraw services that Blt against an in-process
  # OpenGL surface and presents on its own timer, so the call returns promptly
  # and the movie advances. Unlike dgVoodoo2 (which targets D3D11 and faults at
  # init under DXVK), cnc-ddraw's OpenGL renderer is Wine/Proton-native.
  # Loaded as native ddraw via WINEDLLOVERRIDES (see env below); tuned by the
  # ddraw.ini shipped beside it.
  cnc-ddraw = fetchurl {
    name = "cnc-ddraw.zip";
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-CxOriaZMmRgYmx2t1EnvbtPLO3sZyr2W2K29lVBbuQg=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lands-of-lore-ii-guardians-of-destiny";

  src = cd1;

  # The four retail ISOs are pinned on IPFS (cd helper -> fetchIpfs, with the
  # archive.org item kept as fallbackUrl). All four feed the assembled install
  # tree, so they all need to be present in the offline IPFS source set.
  ipfsSources = [
    cd1
    cd2
    cd3
    cd4
  ];

  nativeBuildInputs = [
    p7zip
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"

    # CD1 \INSTALL -> game dir (the installed C:\WESTWOOD\LOLG tree).
    7z x -y "${cd1}" 'INSTALL/*' -o"$TMPDIR/cd1" >/dev/null
    cp -r "$TMPDIR/cd1/INSTALL/." "$out/"
    rm -rf "$TMPDIR/cd1"

    # Every root-level *.MIX from all four discs -> game dir, so the engine
    # finds all CD data (GLOBAL.MIX, LOCAL.MIX, every level *.MIX) in one
    # place without disc swaps.
    for iso in "${cd1}" "${cd2}" "${cd3}" "${cd4}"; do
      7z x -y "$iso" '*.MIX' -o"$TMPDIR/mix" >/dev/null
      # only root-level .MIX (7z keeps the flat name for root entries)
      find "$TMPDIR/mix" -maxdepth 1 -type f -iname '*.MIX' -exec cp -n {} "$out/" \;
      rm -rf "$TMPDIR/mix"
    done

    # LOLG95.EXE aborts at startup with "Missing file lolsetup.ini from
    # installed directory" unless lolsetup.ini exists next to it. That file
    # is normally written by the interactive InstallShield setup, which we
    # skip. Ghidra-decompiling the sole function that reads it (FUN_00504cd0)
    # shows the engine only checks the file's existence and reads
    # [Swap] Swap_Size and [Video] Default; we ship a conservative copy.
    install -m 0644 ${./LOLSETUP.INI} "$out/LOLSETUP.INI"

    # The engine validates the CD drive (FUN_004e066c) by GetVolumeInformation
    # + matching the volume label against LOLG_CD1..LOLG_CD4 and checking that
    # <drive>\GLOBAL.MIX exists; otherwise it dies with "No CD path!!!!".
    # We map d: -> this dir at runtime, so seed Wine's per-drive volume label
    # (read from a `.windows-label` file in the drive root) with LOLG_CD1 so
    # GetVolumeInformation reports the expected label.
    printf 'LOLG_CD1\n' > "$out/.windows-label"

    # The startup story intro (OUTTAKES\lolg.vqa, gated by [Intro] Run_Intro in
    # OPTIONS.INI) is left ENABLED. With the Windows-98 winver seed (see preRun)
    # the Westwood VQA player no longer busy-loops on frame 1 under Proton, so
    # the boot intro and every in-game cutscene now play through to completion.
    # Force it on so the shipped Run_Intro=Off in the disc OPTIONS.INI doesn't
    # suppress it.
    sed -i 's/^Run_Intro=.*/Run_Intro=On/' "$out/OPTIONS.INI"

    # NOTE: cnc-ddraw is intentionally NOT installed here. The current fix is
    # the Windows-98 version lie (see preRun winver seed + env note) paired
    # with Wine's BUILTIN ddraw, mirroring the community reports. cnc-ddraw
    # was exhaustively tested (gdi + direct3d9 renderers, full vsync/maxfps/
    # maxgameticks/singlecpu matrix) and froze on movie frame 1 every time, so
    # leaving it out of the load path. The fetch/ddraw.ini are kept in-tree as
    # a documented dead end and a fallback for future lead #4 (dgVoodoo).

    # Files come off the ISO read-only; make them writable so the overlay
    # upper can update OPTIONS.INI / write SAVEGAME.* next to the binary.
    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Run the prefix as Windows 98 (see preRun winver seed). The Westwood VQA
  # movie player branches on GetVersion (imported by LOLG95.EXE): on a Win9x
  # platform id it takes a forgiving frame-pacing path, whereas on the
  # WinNT/WinXP id Proton reports by default it spins re-blitting frame 1
  # forever. The whole community fix is "set Win95/98 compatibility and the
  # movies play"; this is the registry equivalent. We use Wine's BUILTIN
  # ddraw here (no native override) because the community reports pair the
  # version lie with plain Windows ddraw, and our prior cnc-ddraw attempt
  # froze on frame 1 regardless of renderer.

  # The Win95 game executable. INSTALL/LOLG.EXE is only a tiny DOS stub;
  # LOLG95.EXE is the real Direct3D/DirectDraw engine Proton drives.
  executable = "LOLG95.EXE";

  # The `-CD` flag tells the engine where to find CD assets so it never
  # prompts for a disc swap. `-CD .` is NOT usable: the engine (FUN_004e0380)
  # expands `.` via GetCurrentDirectory, but Proton/umu launches LOLG95.EXE
  # with the Windows cwd at C:\windows\, so `.` never points at the game data.
  # We instead pass an explicit drive (d:) that preRun maps onto the game dir.
  #
  # We deliberately do NOT pass `-MIJAS` (the Westwood QA switch that suppresses
  # the TITLE_E.VQA publisher-logo movie). With the Windows-98 winver fix the
  # VQA player plays cleanly, so both the publisher logo and the story intro
  # are allowed to run, matching the retail boot experience.
  executableArgs = [
    "-CD"
    "d:\\"
  ];

  # Make d: a fake CD-ROM of the game data. The engine's CD validator
  # (FUN_004e066c) enumerates DRIVE_CDROM drives FIRST, matches the
  # GetVolumeInformation label against LOLG_CD1..LOLG_CD4, and checks for
  # <drive>\GLOBAL.MIX; otherwise it dies with "No CD path!!!!". A plain
  # dosdevices symlink registers d: as DRIVE_FIXED, so the validator never
  # even reaches it. Wine derives the drive type in mountmgr's
  # create_drive_devices() (dlls/mountmgr.sys/device.c) from the
  # HKLM\Software\Wine\Drives value -- "cdrom" -> DEVICE_CDROM -> DRIVE_CDROM
  # (5) from GetDriveTypeW. This is exactly what winecfg writes when you set
  # a drive to "CD-ROM", so it is honored by this Proton's wine build.
  # We therefore:
  #   - point dosdevices/d: at the merged overlay ($GAMEDIR), which holds
  #     GLOBAL.MIX + every disc's flattened *.MIX,
  #   - add the dosdevices/d:: device-link (Wine's per-drive unix-device
  #     link; the double colon) so the CD-ROM drive is fully formed,
  #   - seed the baked-in d:\.windows-label so GetVolumeInformation reports
  #     the LOLG_CD1 volume label,
  #   - set HKLM\Software\Wine\Drives "d:"="cdrom" in system.reg so
  #     GetDriveType returns DRIVE_CDROM. The prefix persists across launches
  #     (proton reuses $STROM_COMPATDATA/0/pfx), so the value is read by the
  #     wineserver on the next start; idempotent append, wine merges
  #     duplicate sections on startup.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    mkdir -p "$pfx/dosdevices"
    ln -snf "$GAMEDIR" "$pfx/dosdevices/d:"
    # d:: is Wine's unix-device link for the drive. For a directory-backed
    # virtual CD there is no /dev/srN node; pointing it at the same dir as
    # d: keeps the drive well-formed without claiming a real device.
    ln -snf "$GAMEDIR" "$pfx/dosdevices/d::"

    # Classify d: as a CD-ROM drive. mountmgr reads this at wineserver init.
    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -qF '[Software\\Wine\\Drives]' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wine\\\\Drives] %s\n' "$(date +%s)"
        printf '"d:"="cdrom"\n'
      } >> "$SYSREG"
    fi

    # Report the prefix as Windows 98 to LOLG95.EXE's GetVersion() call. This
    # is exactly what winecfg's "Windows 98" setting does. On a Win9x platform
    # id the Westwood VQA movie player avoids the NT-mode front-buffer-blit
    # busy-loop that spins on frame 1 under Proton (the canonical community
    # fix: "set Win95/98 compatibility and the movies play").
    #
    # Wine resolves the reported version in ntdll version_init() (verified in
    # wine dlls/ntdll/version.c): the AUTHORITATIVE source is a string value
    # "Version" under HKCU\Software\Wine (parse_win_version matches it against
    # the win95/win98/... name table). Only if that is ABSENT does it fall
    # back to the HKLM\Software\Microsoft\Windows\CurrentVersion VersionNumber/
    # SubVersionNumber keys (get_win9x_registry_version). We set BOTH:
    #   - HKCU\Software\Wine "Version"="win98" in user.reg (authoritative;
    #     overrides any Proton default and selects the full win98 VersionData
    #     entry: 4.10.2222, CSD " A ", platform VER_PLATFORM_WIN32_WINDOWS),
    #   - the HKLM 9x keys in system.reg as a belt-and-suspenders fallback.
    # Both are seeded idempotently; wine merges duplicate sections on startup.
    USERREG="$pfx/user.reg"
    # Proton creates user.reg only after first wineserver start; if it does
    # not exist yet, create a minimal valid reg file so the section lands.
    if [ ! -f "$USERREG" ]; then
      printf 'WINE REGISTRY Version 2\n\n' > "$USERREG"
    fi
    if ! grep -qF '[Software\\Wine]' "$USERREG"; then
      {
        printf '\n[Software\\\\Wine] %s\n' "$(date +%s)"
        printf '"Version"="win98"\n'
      } >> "$USERREG"
    fi

    if [ -f "$SYSREG" ] && ! grep -qF 'LOLG-WIN98-SEEDED' "$SYSREG"; then
      {
        printf '\n[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion] %s\n' "$(date +%s)"
        printf ';; LOLG-WIN98-SEEDED\n'
        printf '"VersionNumber"="4.10.2222"\n'
        printf '"SubVersionNumber"=" A "\n'
        printf '"ProductName"="Microsoft Windows 98"\n'
      } >> "$SYSREG"
    fi
  '';

  # Westwood's late-90s engine writes savegames (SAVEGAME.*) and updates
  # OPTIONS.INI next to the binary, persisted via the fuse-overlayfs
  # upper, so no in-prefix steamuser path needs relocating.
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
    description = "Lands of Lore II: Guardians of Destiny (Westwood 1997, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lands-of-lore-ii-guardians-of-destiny";
  };
}
