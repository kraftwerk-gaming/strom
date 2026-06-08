{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  p7zip,
  python3,
}:

let
  # Realms of the Haunting (Gremlin Interactive 1996/97) is a DOS
  # FMV/FPS-adventure shipped on four CDs. The archive.org item is the
  # original retail disc set: CD1 is a MODE1/2352 .bin/.cue (two data
  # tracks), CD2-4 are plain ISO9660 .iso images. ROTH.EXE is a DOS4GW
  # protected-mode binary that runs directly from the disc layout
  # (`REALMS.BAT` is just `roth @roth.res`); it reads video (GDV/),
  # map (M/) and sound (DATA/) data via relative paths.
  #
  # The retail game prompts for disc swaps as you move between chapters
  # because each CD carries a different slice of the GDV/ and M/ trees.
  # To avoid disc-swapping inside DOSBox we merge all four discs into one
  # on-disk C: tree at build time: shared files (ROTH.EXE, DATA/*) are
  # byte-identical across discs, and the per-disc GDV/M files accumulate
  # into a complete install (~1.6 GiB, 164 GDV videos, 51 maps).
  #
  # CD1's ISO9660 directory references files in BOTH .bin tracks via
  # contiguous absolute LBAs, so the whole .bin must be sector-stripped
  # (2352 -> 2048, dropping the 16-byte sync header and 288-byte ECC of
  # each MODE1 sector) into a single ISO; converting only track 1 leaves
  # ~20 files (INSTALL.EXE, several M/*.RAW, DBASE400.DAT, ...) truncated
  # to zero bytes because their extents live past the track boundary.
  src = fetchIpfs {
    cid = "QmVsZihNvVW3MmmdUQupGE7bpQmnNudvD8DWJBmFBLhGVj";
    fallbackUrl = "https://archive.org/download/realms-of-the-haunting-v-f-1.4-1997-en-dos.-7z/Realms%20of%20the%20Haunting%20%28vF1.4%29%20%281997%29%20%28En%29%20%28DOS%29.7z";
    hash = "sha256-L/XzxxeFzVE9PRwZs2mjPKDC8bnJMU6ytVli7DT9ZH8=";
    name = "realms-of-the-haunting.7z";
  };

  # FluidR3_GM2 General MIDI SoundFont; used by DOSBox-X's fluidsynth
  # backend so ROTH's General MIDI score (CONFIG.INI MusicCard=0xa001,
  # the "GeneralMidi" device in INSTALL.INI) plays without an external
  # timidity/MT-32 daemon. ROTH targets General MIDI over MPU-401, not a
  # real Roland MT-32, so a GM SoundFont is the correct instrument bank.
  soundFont = "${pkgs.soundfont-fluid}/share/soundfonts/FluidR3_GM2-2.sf2";

  dosboxConf = pkgs.writeText "dosbox.conf" ''
    [sdl]
    fullscreen=false
    output=opengl
    autolock=true
    showmenu=false

    [dosbox]
    machine=svga_s3
    memsize=16

    [cpu]
    core=dynamic
    cputype=pentium
    # ROTH's GDV cutscenes are CPU-bound and lagged at 45000; doubled to
    # 90000 (a fixed value, not max, to avoid over-driving game timing).
    cycles=90000

    [mixer]
    rate=44100
    prebuffer=20

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=7
    dma=1
    hdma=5
    oplmode=auto
    oplrate=44100

    # Route MPU-401 / General MIDI to the bundled FluidR3 SoundFont via
    # DOSBox-X's built-in soft-synth (`synth`) so MIDI audio goes through
    # the DOSBox-X mixer -> SDL pipewire path. The previous `mididevice=mt32`
    # emulated a Roland MT-32 but shipped no MT-32 ROMs, so all music was
    # silent.
    [midi]
    mpu401=intelligent
    mididevice=synth
    midiconfig=${soundFont}
    fluid.soundfont=${soundFont}

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "realms-of-the-haunting";

  inherit src;

  nativeBuildInputs = [
    p7zip
    python3
  ];

  buildScript = ''
    mkdir -p "$out" /tmp/roth/img
    # Stage 1: outer 7z -> the four raw disc images.
    7z x "$src" -o/tmp/roth/img

    # Stage 2: CD1 (.bin MODE1/2352) -> a 2048-byte/sector ISO9660 image.
    # Strip every sector's 16-byte sync header + 288-byte ECC across the
    # whole .bin so file extents in the second data track resolve.
    cd1bin=$(ls /tmp/roth/img/*CD1*.bin)
    python3 ${./bin2iso.py} "$cd1bin" /tmp/roth/cd1.iso

    # Stage 3: extract every disc into one merged C: tree. p7zip strips
    # the ISO9660 ";1" version suffixes. Identical files overwrite;
    # per-disc GDV/ and M/ payloads accumulate.
    7z x /tmp/roth/cd1.iso -o"$out" -y
    for iso in /tmp/roth/img/*CD2*.iso /tmp/roth/img/*CD3*.iso /tmp/roth/img/*CD4*.iso; do
      7z x "$iso" -o"$out" -y
    done

    # Stage 4: ROTH identifies its discs from the disk1..disk4 paths in
    # ROTH.RES (and reads FMV videos from the gdvs path). The retail
    # INSTALL.EXE writes these into a CONFIG.INI we never generate, so
    # ROTH falls back to scanning for an unlabelled boot CD and stalls
    # on "Insert ROTH 'Boot-CD'". Point all four discs and the GDV tree
    # at D:, where runScript re-mounts the merged install as a CD-ROM.
    {
      echo 'disk1=d:\'
      echo 'disk2=d:\'
      echo 'disk3=d:\'
      echo 'disk4=d:\'
      echo 'gdvs=d:\gdv\'
    } >> "$out/ROTH.RES"

    # Stage 5: ROTH.EXE refuses to make any sound without CONFIG.INI -- it
    # bails with "CONFIG.INI missing or corrupt, please re-install ROTH."
    # / "Cannot detect sound card." and inits no HMI device, so both the
    # digital speech/FX (DIGI\) and the MIDI score (MIDI\) stay silent.
    # The retail INSTALL.EXE/SETSOUND writes this file from its device
    # picker; we skip that interactive installer, so we seed it directly
    # (just like the disk1..disk4 paths above). The keys/values match
    # ROTH's parser template (...SOUNDCARD=S;SOUNDPORT=S;... ;MUSICIRQ=S;)
    # and INSTALL.EXE's writer (%#x for Card values, decimal for the rest):
    #   SoundCard=0xe018  -> SoundBlaster16 DIGIID (INSTALL.INI)
    #   MusicCard=0xa001  -> GeneralMidi MIDIID    (INSTALL.INI)
    # The digital path (220/IRQ7/DMA5) matches the [sblaster] section and
    # the SET BLASTER line in runScript; music goes over MPU-401 at 0x330,
    # which DOSBox-X bridges to the fluidsynth GM SoundFont.
    {
      echo 'SoundCard=0xe018'
      echo 'SoundPort=0x220'
      echo 'SoundIRQ=7'
      echo 'SoundDMA=5'
      echo 'MusicCard=0xa001'
      echo 'MusicPort=0x330'
      echo 'MusicIRQ=7'
    } > "$out/CONFIG.INI"

    rm -rf /tmp/roth
  '';

  # ROTH writes its save slots (and any captured config) into the game
  # directory, so the whole merged tree must be writable in the overlay.
  copyGlobs = [
    "*"
  ];

  runtime = "custom";

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

  # The boot-CD check (see buildScript Stage 4) reads its discs from the
  # disk1..disk4 paths baked into ROTH.RES, which point at D:. Mount the
  # merged tree a second time as a CD-ROM there so those paths resolve;
  # because the merge carries all four discs' GDV/ and M/ payloads, D:
  # alone satisfies every chapter and no disc-swapping is ever needed.
  # C: stays the writable install (save slots land there via the overlay).
  #
  # ROTH selects its sound hardware from CONFIG.INI (seeded in buildScript
  # Stage 5), not from the BLASTER env var. We still export BLASTER to match
  # the [sblaster] section so the HMI digital driver (HMIDRV.386) finds the
  # SB16 at the expected port/IRQ/DMA. `roth @roth.res` is exactly what the
  # shipped REALMS.BAT runs.
  runScript = ''
    exec ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR\"" \
      -c "mount d \"$GAMEDIR\" -t cdrom -label ROTH" \
      -c "c:" \
      -c "SET BLASTER=A220 I7 D1 H5 P330 T6" \
      -c "roth @roth.res" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Realms of the Haunting (1996 Gremlin Interactive FMV adventure, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "realms-of-the-haunting";
  };
}
