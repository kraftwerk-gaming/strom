{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  bchunk,
  p7zip,
  python3,
  fluidsynth,
  soundfont-fluid,
}:

let
  # Soundfont and synth daemon for the General-MIDI music — Wine
  # MCI plays the .MID files via ALSA seq, which on Linux without a
  # hardware synth needs a software soft-synth listening on the seq.
  # We bundle fluidsynth + FluidR3_GM2 so MIDI playback Just Works
  # without the user installing/configuring anything. See preRun for
  # the launch/cleanup contract.
  soundFont = "${soundfont-fluid}/share/soundfonts/FluidR3_GM2-2.sf2";

  # Gubble (Actual Entertainment, 1996) - 3D screw-puller puzzle game,
  # European "Pocket Price Games" PC CD-ROM redump from archive.org.
  # The zip wraps GUBBLECD.cue + GUBBLECD.bin (single 778 MiB MODE1/2352
  # data track, volume label GUBBLECD). The disc holds an InstallShield-
  # era SETUP.EXE + the runnable SETUP/ subtree (GUBBLECD.EXE, DATA/,
  # DSETUP*.DLL, DIRECTX/ shim).
  #
  # No interactive installer step is needed at build time: setup.exe
  # is a thin file-copier that lifts SETUP/GUBBLECD.EXE up to
  # c:\GubbleCD\ and writes a Software\Actual Entertainment\Gubble CD
  # registry key. We replicate that layout in $out and create the
  # registry key from preRun.
  #
  # The retail GUBBLECD.EXE iterates drive letters A-Z calling
  # GetDriveTypeA(); for any DRIVE_CDROM hit it fopen()s
  # %c:\setup\gubblecd.exe and only proceeds if that read succeeds.
  # GameCopyWorld / GameBurnWorld / MegaGames / Internet Archive have
  # no NoCD patch listed for this title, so we self-patch the binary:
  # the CD-check routine at VA 0x0040c2e0 (file offset 0x0000b6e0) is
  # rewritten by patch-gubble-nocd.py. See that script for details —
  # the stub both forces success AND seeds the asset-base buffer at
  # 0x004444be0 with "data\\", because every BMP/WAV/MID loader in
  # the game pushes 0x004444be0 as the %s prefix when formatting paths
  # like "%sintrolev\\%s" or "%smovies\\%s.bmp". Without that seed
  # the loaders construct bare "introlev\\..." paths relative to CWD
  # and find nothing.
  #
  # The asset-relative paths resolve relative to the running CWD,
  # which the wrapper sets to the directory holding GUBBLECD.EXE.
  # The disc layout places BMP/WAV/MID under SETUP\DATA\ next to
  # SETUP\GUBBLECD.EXE, so we run the binary in-tree at `setup/`
  # (`executable = "setup/GUBBLECD.EXE"`) — then `data\\introlev\\X`
  # resolves to `setup/data/introlev/X` which matches on-disk.
  src = fetchIpfs {
    cid = "QmY3cKyHYWXcYScJE8VfYmdBc5R2XJrHLFaG8UpqmRzpDM";
    fallbackUrl = "https://archive.org/download/gubblekoo/Gubble.zip";
    hash = "sha256-9ku9lKWNOLVCTJIlVVnmnPehZt9pM9jaw54hPmATqwY=";
    name = "gubble.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gubble";

  inherit src;

  nativeBuildInputs = [
    unzip
    bchunk
    p7zip
    python3
  ];

  # Unwrap the archive.org redump: unzip outer -> bchunk MODE1/2352 .bin
  # to .iso -> 7z the .iso filesystem out. Drop the bin/cue/iso staging
  # artefacts and the included logs.zip; keep only the disc filesystem.
  # The runnable binary lives at SETUP/GUBBLECD.EXE next to SETUP/DATA/
  # — we keep that layout because the game derives `<exedir>\data\` from
  # the running binary's path.
  buildScript = ''
    mkdir -p "$TMPDIR/zip" "$TMPDIR/iso" "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    ( cd "$TMPDIR/zip" && bchunk -v GUBBLECD.bin GUBBLECD.cue gubble >/dev/null )
    7z x -y -o"$TMPDIR/iso" "$TMPDIR/zip/gubble01.iso" >/dev/null

    cp -r "$TMPDIR/iso/SETUP" "$out/setup"

    # Drop docs alongside the install tree for the curious.
    install -m0644 "$TMPDIR/iso/Gubble_English.doc" "$out/manual.doc"
    install -m0644 "$TMPDIR/iso/Copyright.txt" "$out/Copyright.txt"

    chmod -R u+w "$out"

    # NoCD patch: stub out the CD-scan routine at VA 0x0040c2e0 so the
    # game doesn't probe for a mounted CD-ROM. See patch-gubble-nocd.py.
    python3 ${./patch-gubble-nocd.py} "$out/setup/GUBBLECD.EXE"

    # Startup-state-machine fix: change the initial value of the
    # screen-state selector byte at VA 0x004df3b8 from 0xa to 0x00 in
    # fcn.0040cb70's prologue, so fcn.0040d410's switch dispatches
    # through cases 0..7 (intro + gameplay init, including the
    # promotion of state byte 0x004d8460 to 0x14 and the per-screw
    # struct-array setup) before hitting case 10 (gameplay render
    # fcn.00410690). Without this the very first dispatch jumps
    # straight to case 10 and the render loop walks an uninitialized
    # struct array, faulting at VA 0x00410713 on `movsx eax,
    # word [esi + 6]`. See patch-gubble-race.py.
    python3 ${./patch-gubble-race.py} "$out/setup/GUBBLECD.EXE"
  '';

  runtime = "proton";
  # Run the in-tree binary so GetModuleFileNameA-derived `<exedir>\data\`
  # resolves to setup/DATA/ where the BMP/WAV/MID assets actually live.
  executable = "setup/GUBBLECD.EXE";

  # GUBBLECD.EXE writes its saves and options next to its binary
  # (%sgubble%d.sav, %sgubble.opt where %s is the install dir).
  # These land in the per-game fuse-overlayfs upper under $STROM_GAMEDIR,
  # not the wineprefix's drive_c/users/steamuser/, so saveLocations is
  # intentionally empty. Same pattern as portal / magicka / pico-park.
  saveLocations = [ ];

  # The NoCD patch in buildScript bypasses the drive-letter scan, so
  # no dosdevices wiring is needed at runtime. Still seed the registry
  # key the installer would have written, in case the game reads
  # HKLM\Software\Actual Entertainment\Gubble CD for an install path.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] \
       && ! grep -q 'Actual Entertainment\\\\Gubble CD' "$SYSREG"; then
      {
        printf '\n[Software\\\\Actual Entertainment\\\\Gubble CD] 0\n'
        printf '"InstallPath"="C:\\\\GubbleCD"\n'
      } >> "$SYSREG"
    fi

    # MIDI synth for the in-game music. GUBBLECD.EXE plays its .MID
    # tracks via Wine's MCI sequencer, which on Linux dispatches MIDI
    # events to the first available ALSA seq client. Without a soft-
    # synth listening, those events go to the kernel "Midi Through"
    # port and disappear. Launch fluidsynth bound to PulseAudio
    # (PipeWire's pulse shim) with the bundled FluidR3 GM soundfont,
    # then arm a child watchdog that polls the inner script's PID
    # and kills fluidsynth once the game (which inherits this PID
    # via the trailing `exec`) terminates. Stdin is redirected from
    # /dev/null so fluidsynth doesn't try to take over the terminal.
    ${lib.getExe fluidsynth} \
      --no-shell --server \
      -a pulseaudio -m alsa_seq \
      -o synth.lock-memory=0 \
      ${soundFont} \
      </dev/null >/dev/null 2>&1 &
    STROM_FLUID_PID=$!
    (
      while kill -0 $$ 2>/dev/null; do sleep 2; done
      kill "$STROM_FLUID_PID" 2>/dev/null || true
    ) &
    disown
  '';

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
    description = "Gubble (Actual Entertainment 1996, European CD redump, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gubble";
  };
}
