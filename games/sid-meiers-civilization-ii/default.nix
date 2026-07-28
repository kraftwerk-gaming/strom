{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  bchunk,
  binutils-unwrapped,
  cabextract,
  mscompress,
  p7zip,
  unshield,
  writeText,
}:

let
  # Sid Meier's Civilization II - the *base* 1996 MicroProse release
  # (NOT Multiplayer Gold Edition, NOT Test of Time). English retail
  # CD-ROM, EN/FR/DE multilanguage data, game build dated 1996-03-05.
  #
  # Build flavour: this is the Windows 3.1/95 release. CIV2.EXE is a
  # 16-bit NE ("MS-DOS executable, NE for MS Windows 3.x") binary - Civ II
  # never shipped a DOS build, and the 32-bit PE rewrite only arrived with
  # Multiplayer Gold Edition (1998). So this runs on Proton's Win16
  # subsystem, not DOSBox.
  #
  # Asset: the redump-style multi-track BIN from
  # archive.org/details/sid-meiers-civilization-ii (track 1 = MODE1/2352
  # data, tracks 2-10 = the CD-audio soundtrack, which the 16-bit MCI path
  # cannot reach under Proton anyway). Track 1 carries a complete loose
  # install tree under CIV2/ (CIV2.EXE, CV.DLL, TILES.DLL, SOUND/, VIDEO/,
  # KINGS/, PEDIA/, ...), so SETUP.EXE - an InstallShield-era MSCOMSTF
  # installer - is not needed: we copy the tree straight out of the ISO
  # and get the "full install" layout the game expects.
  src = fetchIpfs {
    cid = "QmZLYBr81qMLpSmtAyTKJnFJizTofbFzQVxvHokmbUNbQj";
    fallbackUrl = "https://archive.org/download/sid-meiers-civilization-ii/Civilization_II.bin";
    hash = "sha256-iFXmssmOeL7jLgqpVL9NgUel/59mPlfK0CFBX9subwQ=";
    name = "sid-meiers-civilization-ii-cd.bin";
  };

  # bchunk needs a cue next to the bin; the store name differs from the
  # one in the item's own cue, so synthesise it (same track layout).
  cue = writeText "civ2.cue" ''
    FILE "sid-meiers-civilization-ii-cd.bin" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
      TRACK 02 AUDIO
        PREGAP 00:02:00
        INDEX 01 40:41:37
      TRACK 03 AUDIO
        INDEX 01 41:19:06
      TRACK 04 AUDIO
        INDEX 01 42:06:21
      TRACK 05 AUDIO
        INDEX 01 43:48:50
      TRACK 06 AUDIO
        INDEX 01 45:56:23
      TRACK 07 AUDIO
        INDEX 01 48:01:62
      TRACK 08 AUDIO
        INDEX 01 50:50:11
      TRACK 09 AUDIO
        INDEX 01 53:31:62
      TRACK 10 AUDIO
        INDEX 01 55:22:17
  '';

  # Ligos "Indeo Software" (iv5setup.exe, 2000) - the second of the two
  # archives winetricks' `icodecs` verb pulls, and the only one carrying
  # all three video codecs in one place: Indeo 3.2 (ir32_32.dll), Indeo
  # 4.1 (ir41_32.ax) and Indeo 5 (ir50_32.dll). winetricks fetches it from
  # download.civforum.de; this is the byte-identical Wayback capture of
  # the original s3.amazonaws.com/moviecodec copy, same sha256 winetricks
  # pins (51bec25488b5b94eb3ce49b0a117618c9526161fd0753817a7a724ce25ff0cad).
  #
  # fetchurl rather than fetchIpfs: like the DirectX redists in
  # age-of-empires-ii-the-conquerors and gothic this is a small
  # third-party runtime, not a shipped game asset.
  indeoSetup = fetchurl {
    url = "https://web.archive.org/web/20170904095949id_/https://s3.amazonaws.com/moviecodec/files/iv5setup.exe";
    hash = "sha256-Ub7CVIi1uU6zzkmwoRdhjJUmFh/QdTgXp6ckziX/DK0=";
    name = "iv5setup.exe";
  };

  # Unpack at build time instead of driving the InstallShield wizard at
  # runtime: winetricks runs it under bare wine with a recorded .iss
  # response file, which this repo forbids, and 16-bit InstallShield
  # setups are broken under new-WoW64 anyway (winehq bug 54670 - that bug
  # is about the *installer*, not the codecs). Two stages, same shape as
  # the DirectX redists elsewhere in this repo: the outer SFX cabinet ->
  # data1.cab/data1.hdr, then unshield on the InstallShield 5 cabinet ->
  # one directory per component group.
  indeoCodecs =
    pkgs.runCommandLocal "indeo-codecs"
      {
        nativeBuildInputs = [
          binutils-unwrapped
          cabextract
          unshield
        ];
      }
      ''
        mkdir -p "$out"
        cabextract -q -L -d sfx ${indeoSetup}
        unshield -d is5 x sfx/data1.cab > /dev/null
        install -m0644 is5/Indeo_3_2_codec/ir32_32.dll "$out/ir32_32.dll"
        install -m0644 is5/Indeo_4_codec/ir41_32.ax "$out/ir41_32.ax"
        install -m0644 is5/Indeo_5_codec/ir50_32.dll "$out/ir50_32.dll"

        # These must be 32-bit PE. The disc's own VFW_INST/IR41.DL_ looks
        # like a candidate but is a 16-bit NE (and KWAJ-compressed), and
        # wine routes even a 16-bit app's ICLocate through 32-bit msvfw32,
        # so anything but pei-i386 here is the wrong file.
        for f in "$out"/*; do
          objdump -f "$f" | grep -q 'file format pei-i386' \
            || { echo "not a 32-bit PE: $f" >&2; exit 1; }
          objdump -p "$f" | grep -q ' DriverProc$' \
            || { echo "no VFW DriverProc export: $f" >&2; exit 1; }
        done
      '';

  # Drivers32 value -> file name, taken from Indeo's own InstallShield
  # script (setup.rul inside the redist: RegDBSetKeyValueEx on
  # "\Software\Microsoft\Windows NT\CurrentVersion\Drivers32"). The Indeo
  # 4 codec really is named ir41_32.ax, not .dll - the same binary doubles
  # as a DirectShow filter. msvfw32 LoadLibrary()s whatever string the
  # value holds, so the extension is irrelevant to it.
  indeoDrivers32 = {
    "vidc.IV31" = "ir32_32.dll";
    "vidc.IV32" = "ir32_32.dll";
    "vidc.IV41" = "ir41_32.ax";
    "vidc.IV50" = "ir50_32.dll";
  };

  # Wine-format .reg fragment, appended to the prefix's system.reg (all
  # keys there are relative to HKLM). Written under both the plain path
  # and the Wow6432Node view: CIV2.EXE runs inside the 32-bit WoW64
  # environment, so its HKLM\Software lookups are redirected to
  # Wow6432Node, and in a GE-Proton prefix that Drivers32 key is a real
  # key rather than a symlink to the 64-bit one - the 64-bit copy alone
  # would never be read.
  indeoReg = writeText "indeo-drivers32.reg" (
    lib.concatMapStrings
      (
        view:
        "\n[Software\\\\${view}Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Drivers32]\n"
        + lib.concatStrings (lib.mapAttrsToList (fcc: dll: "\"${fcc}\"=\"${dll}\"\n") indeoDrivers32)
      )
      [
        ""
        "Wow6432Node\\\\"
      ]
  );
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sid-meiers-civilization-ii";

  inherit src;

  nativeBuildInputs = [
    bchunk
    mscompress
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/cd"
    ln -s "$src" "$TMPDIR/cd/sid-meiers-civilization-ii-cd.bin"
    cp ${cue} "$TMPDIR/cd/civ2.cue"
    bchunk "$TMPDIR/cd/sid-meiers-civilization-ii-cd.bin" "$TMPDIR/cd/civ2.cue" "$TMPDIR/cd/track"

    # bchunk writes an ISO whose recorded volume size covers the whole
    # multi-track disc, so 7z reports "Unexpected end of archive" even on a
    # clean extraction - ignore the status and assert on the payload.
    7z x -bso0 -bsp0 -o"$TMPDIR/iso" "$TMPDIR/cd/track01.iso" CIV2 WING || true
    test -f "$TMPDIR/iso/CIV2/CIV2.EXE"
    cp -r "$TMPDIR/iso/CIV2/." "$out"/
    chmod -R u+w "$out"

    # CIV2.EXE LoadLibrary()s "wing.dll" (Microsoft WinG 1.0, the 16-bit
    # pre-DirectDraw blitter) at startup and dies without it. The retail
    # installer runs WING/WINGSET.EXE to drop it into the Windows dir; that
    # is an interactive MSCOMSTF setup, so instead we expand the four
    # SZDD-compressed WinG runtime files (msexpand) next to CIV2.EXE, where
    # the 16-bit loader looks first. WINGDIB.DRV/WINGPAL.WND are loaded by
    # WING.DLL itself, WINGDE.DLL is its dib engine.
    msexpand < "$TMPDIR/iso/WING/WING.DL_" > "$out/WING.DLL"
    msexpand < "$TMPDIR/iso/WING/WINGDE.DL_" > "$out/WINGDE.DLL"
    msexpand < "$TMPDIR/iso/WING/WINGDIB.DR_" > "$out/WINGDIB.DRV"
    msexpand < "$TMPDIR/iso/WING/WINGPAL.WN_" > "$out/WINGPAL.WND"

    # INTER.DAT is the interface-language table CIV2.EXE reads at startup:
    # "@KEY" followed by one flag per language (English, Francais,
    # Deutsch). The disc ships 1/1/0, so an install straight off the CD
    # opens a modal English-vs-Francais chooser on EVERY launch. The retail
    # installer writes the flags for the language actually installed; this
    # is the English package, so do the same. All three language data sets
    # (*.TXT / *.FRE / *.GER) are still installed - flip the second or third
    # flag back to 1 in the game dir to get the chooser and French/German.
    printf '\r\n@KEY\r\n1\r\n0\r\n0\r\n\r\n' > "$out/INTER.DAT"
  '';

  runtime = "proton";
  executable = "CIV2.EXE";

  # Civ II is a Win3.1-era title: saved games (*.SAV), scenarios (*.SCN),
  # the map editor's *.MP files and the INTER.DAT language table all live in
  # the install directory next to CIV2.EXE, not under
  # drive_c/users/steamuser/. Those persist through the per-game
  # fuse-overlayfs upper, so there is nothing to relocate. (The only file
  # that escapes to the prefix is CIV.INI - see preRun - and it holds one
  # first-run acknowledgement flag, no progress.)
  saveLocations = [ ];

  # Four first-run fixups, all of which a prefix wipe undoes.
  #
  # 1. CIV.INI. First launch otherwise stops on a modal "Civ2 Diplomatic
  #    Heralds" prompt asking whether the machine has 16 MB of RAM, i.e.
  #    whether to play the KINGS/HRLD*.AVI diplomat animations; pre-write
  #    the acknowledgement the game itself would store. CIV.INI is opened
  #    with a bare filename, so the 16-bit profile API resolves it against
  #    C:\windows inside the prefix - hence seeding it on every run rather
  #    than once. Skipped when the prefix does not exist yet (very first
  #    launch, before proton has run wineboot).
  #
  # 2. Indeo. Every movie on the disc is Indeo 4.1 and the intro is not
  #    skippable, so without a decoder the game never reaches its menu
  #    (see longDescription). This is winetricks' `icodecs` verb done by
  #    hand, the way age-of-empires-ii-the-conquerors installs native
  #    DirectPlay: drop the DLLs in, then write the Drivers32 values that
  #    ICLocate reads, by appending to system.reg rather than shelling out
  #    to `wine reg add`.
  #
  #    syswow64 is the right directory. CIV2.EXE is a 16-bit NE, but its
  #    16-bit MSVIDEO.DLL thunks into 32-bit msvfw32, and msvfw32's
  #    ICOpen does OpenDriver("vidc.IV41", "drivers32") -> LoadLibraryW of
  #    the registry value. That LoadLibrary runs in the 32-bit WoW64
  #    process, where C:\windows\system32 resolves to the physical
  #    drive_c/windows/syswow64 - which is also where GE-Proton keeps the
  #    32-bit msvfw32.dll doing the lookup. drive_c/windows/system32 holds
  #    the 64-bit DLLs and is never consulted here.
  #
  # 3. The CD-ROM drive. CIV2.EXE hunts for the disc at startup and, when
  #    it comes up empty, shows the "We were unable to find the
  #    Civilization II CD-ROM" notice and then runs without "the
  #    additional multimedia, music, and art supplied by the CD".
  #
  #    Every CD path the binary builds is a drive root plus a
  #    *disc-relative* subpath - its string table holds ":\" next to
  #    "civ2\civ2.exe", "civ2\civ2art.dll", "civ2\mk.dll",
  #    "civ2\video\opening.avi", "civ2\kings\" + "hrld" + ".avi",
  #    "civ2\pedia\get_info.exe" and "CIV2\SOUND\". So the drive has to
  #    look like the pressed disc (a root holding CIV2\), not like the
  #    install tree flattened into a drive root. We build that one-entry
  #    disc root inside the prefix and point d: at it:
  #      - $pfx/drive_d/CIV2 -> the merged game overlay ($GAMEDIR), which
  #        is byte-identical to the disc's CIV2\ (that is where
  #        buildScript got it from) and stays live across launches,
  #      - dosdevices/d:  -> $pfx/drive_d, the path all d:\... lookups
  #        resolve through,
  #      - dosdevices/d:: -> the same dir. That is Wine's per-drive
  #        unix-device link; there is no /dev/srN to point it at, and
  #        leaving it out makes ntdll's get_dos_device() fall back to
  #        guessing a device for the mount point out of /proc/mounts.
  #      - HKLM\Software\Wine\Drives "d:"="cdrom" in system.reg, which is
  #        what winecfg's "CD-ROM" drive type writes. mountmgr reads it in
  #        create_drive_devices() at wineserver init and gives the drive a
  #        DEVICE_CDROM disk device, so GetDriveType reports DRIVE_CDROM
  #        and the fs type is forced to ISO9660/CDFS. Without it d: is a
  #        DRIVE_FIXED and the game's drive scan walks straight past it.
  #
  #    No .windows-label is written, on purpose. That file is how Wine
  #    reports a volume label for a directory-backed drive, but this disc
  #    has no label to report: its ISO9660 primary volume descriptor
  #    (track 1, LBA 16) carries 32 spaces in the volume identifier and
  #    the descriptor set terminates at LBA 17, i.e. there is no Joliet
  #    SVD at all - `isoinfo -d` prints an empty "Volume id:" and "NO
  #    Joliet present". An empty label is therefore exactly what the
  #    pressed disc reports, and that is already what mountmgr's
  #    get_filesystem_label() yields when the file is absent. Don't invent
  #    one.
  #
  # 4. No wave-audio driver. CIV2.EXE's AVI player drives the movie clock
  #    from waveOutGetPosition and streams the movie's PCM track through
  #    16-bit MMSYSTEM. Give it a wave device and it GP-faults before the
  #    main menu, every launch, on every driver Proton has:
  #
  #      "Unhandled exception: page fault on read access to 0xffffffff
  #       in 16-bit code (04c7:1dfc)"      0x04c7:0x1dfc: lodsb (%si),%al
  #       CS:04c7 SS:07cf DS:0967 ES:1c27
  #       sel=0967 base=... limit=000001df 16-bit rw-
  #       sel=1c27 base=... limit=0000201f 16-bit rw-
  #
  #    Root cause, from a +relay trace of the movie loop. The player
  #    demuxes through the 16-bit AVIFILE thunk and hands AVIStreamRead a
  #    far pointer into its own audio ring buffer, then _fmemcpy's 0x1000
  #    bytes at a time out of that buffer into the 0x2020-byte
  #    WAVEHDR+8192 blocks it prepared. The ring buffer is a Win16 global
  #    block addressed as a HUGE pointer: the trace walks
  #    095f:fde8 -> 095f:fe68 -> ... -> 095f:ffe8 and then wraps to
  #    0967:0068, i.e. base selector + __AHINCR(8), the textbook tiled
  #    walk. Under Wine that next tile is not the game's: selector 0967
  #    is WING.DLL's 480-byte krnl386 module block (NtSetLdtEntries
  #    00000967 limit 0x1df, set when LoadLibrary16("wing.dll") ran, long
  #    before any audio), while the base selector 095f carries limit
  #    0xffff - one 64K tile, nothing after it. The first read through
  #    the wrapped pointer (src 0967:0970, dst <wavehdr>:0020, len
  #    0x1000) is a segment-limit violation and the app dies.
  #
  #    The write side of the same mistake goes unpunished, which is why
  #    it gets that far: the very first read is
  #    AVISTREAMREAD(...,lpBuffer=095f:17e8,cbBuffer=0x10000,...) - 64K
  #    into a 64K selector at offset 0x17e8 - and Wine's avifile.dll16
  #    thunk resolves lpBuffer with MapSL() and memcpy's straight past
  #    the selector limit into whatever 16-bit memory follows, returning
  #    S_OK. Only the app's own CPU-checked lodsb notices.
  #
  #    Two separate observations, so be precise about what came from
  #    where. The register/selector dump above is the ordinary run and
  #    reproduces exactly: six launches (pulse, alsa, no key, win31,
  #    'txts' AVI, intro-skip attempt) all landed on 04c7:1dfc with
  #    CS:04c7 SS:07cf DS:0967 and sel=0967 limit=0x1df, ES varying only
  #    over the eight WAVEHDR buffers (1c17/1c1f/1c27). The AVIStreamRead
  #    pointer walk and the WING.DLL identification of selector 0967 come
  #    from the +relay,+module run, which does NOT end the same way -
  #    relay tracing eats the 16-bit stack, so that run marches one tile
  #    further and dies of "stack overflow in segmented 32-bit code
  #    (096f:0000016f)", 096f being 0967 + __AHINCR again (limit 0x17f).
  #    Same walk off the end of the app's own allocation, whichever
  #    unrelated selector the CPU checks first.
  #
  #    Nothing about that is per-driver, and the measurements say so.
  #    Every row below is a separate launch on the current tree, with the
  #    CD-ROM drive of 3 in place (a disc in the drive changes which
  #    audio paths the game arms at all - it does not change this one):
  #
  #      Audio="pulse"  winepulse.drv loads, priority Preferred,
  #                     waveOutGetNumDevs 5, waveOutOpen OK at
  #                     22050/8-bit/stereo -> fault 04c7:1dfc, DS=0967,
  #                     ~500 ms into OPENING.AVI, no menu.
  #      Audio="alsa"   winealsa.drv, priority Neutral, same device
  #                     count, same waveOutOpen -> byte-identical fault,
  #                     identical selectors and identical backtrace.
  #      Audio absent   mmdevapi's own list "pulse,alsa,oss,coreaudio":
  #                     winepulse Preferred wins -> same fault again.
  #      oss/coreaudio  not shipped by GE-Proton11-1. load_driver returns
  #                     126 (ERROR_MOD_NOT_FOUND) for both;
  #                     i386-windows/ holds only winealsa.drv and
  #                     winepulse.drv.
  #      Audio=""       0 devices, waveOutOpen fails, stable. Shipped.
  #
  #    The pulse rows matter because the earlier round could not produce
  #    them: before lib/proton.nix grew 32-bit libudev, winepulse.so
  #    could not dlopen ("err:mmdevapi:load_driver Unable to load UNIX
  #    functions: c0000135") and waveOutGetNumDevs returned 0, so only
  #    winealsa was ever exercised. winepulse works now, is what mmdevapi
  #    picks by default, and changes nothing here.
  #
  #    Three more things were tried and are dead ends. Setting
  #    AppDefaults\CIV2.EXE\Version=win31 (winevdm passes --app-name, so
  #    the key does apply to the 16-bit app): identical fault. Making the
  #    movie's audio unplayable by patching OPENING.AVI's strf
  #    wFormatTag to 0xffff: the game opens the wave device anyway and
  #    faults at the same instruction. Retyping the AVI's audio stream
  #    from 'auds' to 'txts' so there is no audio stream to find: the
  #    game still opens the device, plays the whole 92-second intro, and
  #    then faults at the same 04c7:1dfc through a second call site
  #    (04f7:8c0f rather than 04f7:8817) as the intro ends - so there is
  #    no "movie audio off, effects on" split to be had, and no
  #    configuration reaches the main menu with a wave device present.
  #
  #    Emptying HKCU\Software\Wine\Drivers\Audio leaves the prefix with
  #    no wave device at all, waveOutOpen fails, and the movie player
  #    falls back to its timer clock - the intro then plays through and
  #    the main menu comes up. The cost is that Civ II is silent
  #    (SOUND/*.WAV effects and movie audio). The key is per-prefix, so
  #    this only mutes this game.
  #
  #    Sentinel-gated so a wiped prefix re-installs and a warm one does
  #    not re-append; gated on system.reg existing so the very first
  #    launch (before proton bootstraps the prefix) is a no-op and the
  #    next one lands it.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"

    civ_ini="$pfx/drive_c/windows/CIV.INI"
    if [ -d "''${civ_ini%/*}" ] && [ ! -e "$civ_ini" ]; then
      printf '[Civilization 2000]\r\nHerald Warning Shown=1\r\n' > "$civ_ini"
    fi

    syswow64="$pfx/drive_c/windows/syswow64"
    indeo_sentinel="$pfx/.strom-indeo-installed"
    if [ -d "$syswow64" ] && [ -f "$pfx/system.reg" ] \
        && [ ! -e "$indeo_sentinel" ]; then
      echo "[strom] sid-meiers-civilization-ii: installing Indeo codecs" >&2
      for f in ${lib.escapeShellArgs (lib.unique (lib.attrValues indeoDrivers32))}; do
        install -m0644 "${indeoCodecs}/$f" "$syswow64/$f"
      done
      cat ${indeoReg} >> "$pfx/system.reg"
      touch "$indeo_sentinel"
    fi

    # Fake CD-ROM at d:, laid out like the pressed disc (see 3 above).
    # Gated on system.reg the same way as the Indeo install: on a cold
    # prefix proton has not created $pfx yet, and mkdir'ing into it would
    # put a real directory where proton wants to place its own tree. First
    # launch is a no-op, the next one lands the drive.
    if [ -f "$pfx/system.reg" ]; then
      cdroot="$pfx/drive_d"
      mkdir -p "$cdroot" "$pfx/dosdevices"
      ln -snf "$GAMEDIR" "$cdroot/CIV2"
      ln -snf "$cdroot" "$pfx/dosdevices/d:"
      ln -snf "$cdroot" "$pfx/dosdevices/d::"
      if ! grep -qF '"d:"="cdrom"' "$pfx/system.reg"; then
        echo "[strom] sid-meiers-civilization-ii: registering d: as CD-ROM" >&2
        printf '\n[Software\\\\Wine\\\\Drives] %s\n"d:"="cdrom"\n' \
          "$(date +%s)" >> "$pfx/system.reg"
      fi
    fi

    if [ -f "$pfx/user.reg" ] \
        && ! grep -q '^"Audio"=""' "$pfx/user.reg"; then
      printf '\n[Software\\\\Wine\\\\Drivers]\n"Audio"=""\n' >> "$pfx/user.reg"
    fi
  '';

  # Native 640x480 fixed-resolution GDI/WinG output; upscale it.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Sid Meier's Civilization II (MicroProse 1996, English Win3.1/95 retail CD, via Proton)";
    longDescription = ''
      Base Civilization II, not the 1998 Multiplayer Gold Edition or the
      1999 Test of Time. The complete retail "full install" tree is here
      (art, sounds, Civilopedia, movies, scenarios, the map editor).

      Startup order is: language table (pre-set to English, see INTER.DAT
      above), the diplomat-herald prompt (pre-answered, see preRun), then
      VIDEO/OPENING.AVI - and that intro is where this used to stop. A "We
      were unable to find the Civilization II CD-ROM" notice used to open
      the show; the emulated CD-ROM drive in preRun retires it.

      Every movie on the disc is Indeo 4.1 (fourcc IV41): the intro, the
      three advisor councils, 28 wonder clips, 21 animated heralds. Wine
      and Proton ship no Indeo decoder, so msvfw32's ICLocate walked
      mrle/msvc/cvid/iyuv, found no IV41 handler, and CIV2.EXE sat on a
      black full-screen movie window forever (Escape or a click aborted
      straight to exit). Fixed by installing Ligos' own 32-bit Indeo
      3.2/4.1/5 codecs into the prefix plus the Drivers32 values that make
      ICLocate find them - see indeoCodecs/indeoReg above and preRun
      below.

      Second half of the fix: the prefix is left with no wave-audio driver
      (preRun empties HKCU\Software\Wine\Drivers\Audio). With one present,
      CIV2.EXE dies before its main menu - always, on every wave driver
      GE-Proton11-1 has. Its movie player addresses the AVI audio ring
      buffer as a Win16 huge pointer and walks off the end of its own 64K
      selector into WING.DLL's 480-byte krnl386 module block, so the first
      _fmemcpy out of the wrapped pointer takes a segment-limit #GP:
      "page fault on read access to 0xffffffff in 16-bit code
      (04c7:1dfc)". preRun carries the full analysis, the per-driver table
      and the dead ends. The short version: winepulse (Preferred, working
      since lib/proton.nix grew 32-bit libudev - the previous round could
      only ever test winealsa) faults byte-identically to winealsa, same
      instruction, same selectors, same backtrace; mmdevapi's default
      driver list lands on winepulse and faults too; wineoss and
      winecoreaudio are not shipped at all (load_driver 126). It is
      CIV2.EXE's own 16-bit code, not a driver we can swap.

      With the driver gone, waveOutOpen fails, the movie player falls back
      to its timer clock, the 92-second intro plays through and the main
      menu comes up. Verified headless: intro frames decode, then the
      "Civilization II" menu (Start a New Game / ... / View Credits), a
      new game down to the map, and the advisor movies.

      The standing cost of that is silence: SOUND/*.WAV effects (combat,
      the MENULOOP/MENUEND menu bed, the throne-room drums) and movie
      audio all go with the wave device. There is no partial win to take
      here either - the effects and the movie audio share the one 16-bit
      sound engine and the one broken pointer, and with a device present
      the game cannot reach the menu at all (preRun, dead ends). Silence
      is the only stable state. Everything else the CD gates is there.

      The disc is now in the drive. preRun builds a disc-shaped root in
      the prefix ($pfx/drive_d holding CIV2 -> the game overlay), maps d:
      onto it and registers d: as "cdrom" - see preRun for why the tree
      has to sit under CIV2\ rather than at the drive root. CIV2.EXE's
      startup search enumerates the drives, finds the one that reports
      DRIVE_CDROM and probes it: `OpenFile16("d:\civ2\civ2.exe")` now
      returns a handle (WINEDEBUG=+file), the CD notice is gone, and the
      CD-gated content is live - the High Council screen plays its five
      Indeo advisor panels, the Civilopedia and city-style art render,
      SOUND/MENULOOP.WAV gets opened.

      Music does not work and cannot, short of a kernel-level virtual
      optical drive. Civ II's soundtrack is CD-DA on tracks 2-10 of the
      BIN (the "Pick Music" list - Funeral March, Ode to Joy,
      Tenochtitlan Revealed, ...), played through the MCI "cdaudio"
      device. There is no second source to fall back on, and that is a
      fact about the disc rather than a guess: the whole installed tree is
      78 .WAV, 59 .AVI and text/art/code, with not one .MID, .RMI, .XMI,
      .MUS, .HMP or .CMF anywhere on it. CIV2.EXE does carry a MIDI path
      ("Midi Device failed to open", "The MIDI Mapper is not available.
      Continue?"), and mmdevapi does load winealsa.drv as the prefix's
      MIDI driver even when the wave driver is something else - but there
      is no MIDI content for it to play, so providing a synth would change
      nothing. As for the CD-DA itself: Wine's mcicda scans for a
      DRIVE_CDROM drive - it now finds d: - and then does
      CreateFileW("\\.\D:"), which for a directory-backed drive resolves
      to dosdevices/d:: and fails with STATUS_FILE_IS_A_DIRECTORY. The
      game logs MCI_OPEN failing with 0x123 (MCIERR_MUST_USE_SHAREABLE,
      exactly mcicda's CreateFile-failed return) and greys the feature
      out: "Pick Music" answers "This option is not available unless the
      Civilization II CD is in the CDROM drive".

      Extracting the audio tracks (bchunk already writes track02..10.cdr)
      would not help, because Wine has no file-backed CD-audio path to
      wire them into: every mcicda operation is an IOCTL_CDROM_* on the
      drive's unix device, including the DirectSound fallback, whose
      playLoop pulls raw sectors with IOCTL_CDROM_RAW_READ. Serving those
      needs a real block/char device with a TOC, i.e. vhba/cdemu - a
      kernel module load, which this sandbox cannot do. A soundtrack
      overlay would have to be a game-side patch, and base Civ II has no
      hook for one.

      Things that were tried and are dead ends, don't repeat them.
      Deleting the movies makes CIV2.EXE quit at that point in startup
      (the intro is not optional) and transcoding OPENING.AVI to msvideo1
      makes it quit the same way. Neither of the two ways to take the
      movie's audio away buys anything with a wave device present:
      patching the audio strf's wFormatTag to 0xffff changes nothing at
      all (the game opens the device before it looks at the format and
      faults on schedule), and retyping the audio stream from 'auds' to
      'txts' merely defers it - the game opens the device, plays the full
      92-second intro with the ring buffer never filled, then faults at
      the same 04c7:1dfc through a second call site as the intro ends,
      still short of the menu. Reporting the app as win31 via
      AppDefaults\CIV2.EXE\Version is identical to not doing it. The
      disc's own VFW_INST/IR41.DL_ is not a substitute for the codec
      either - it is 16-bit and KWAJ-compressed (msexpand only handles
      SZDD), and Wine routes even a 16-bit app's ICLocate through 32-bit
      msvfw32.

      Everything else checks out: Proton's Win16 subsystem loads the NE
      binary, WinG blits, and GDI dialogs, the title screen and the
      Civilopedia art all render.
    '';
    platforms = [ "x86_64-linux" ];
    mainProgram = "sid-meiers-civilization-ii";
  };
}
