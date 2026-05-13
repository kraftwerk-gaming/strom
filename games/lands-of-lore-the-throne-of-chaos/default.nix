{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  p7zip,
}:

let
  # Lands of Lore: The Throne of Chaos (1993 Westwood / Virgin) DOS
  # CD-ROM v1.02D. The archive.org item ships a 7z wrapping a single
  # ISO with the full CD layout (DATA/00.TLK ... DATA/HARDRIVE/ ...).
  # The original DOS installer (INSTALL.EXE) just copies DATA/HARDRIVE/*
  # to the user's drive; we do that copy in buildScript so the build
  # output already contains a fully-installed game directory (hd/) and
  # the CD image tree (cd/).
  #
  # LOLCD.EXE refuses to start without LANDS.CFG (it prints "Please run
  # SETUP before running LANDS." and exits). LANDS.CFG is a 10-byte
  # binary file produced by SETUP.EXE that pins the sound device. The
  # SB16 emulation in DOSBox-X is fixed at sbbase=220 irq=5 dma=1 so
  # the bytes don't depend on the host -- we ship a pre-captured copy
  # next to this default.nix and drop it into hd/ at build time. Users
  # can still override by running SETUP.EXE inside the overlay.
  #
  # The shipped LANDS.CFG is the community-curated "SB16" variant from
  # flynnsbit/Top300_updates (Top 300 DOS games pack), which encodes
  # Music=Sound Blaster, SFX=Sound Blaster Pro, Digital=IBM PC/Tandy
  # speaker. The previous self-baked variant accidentally selected the
  # SBPro mixer scale + IBM PC digital path, which produces effectively
  # silent output under DOSBox-X's sb16 emulation.
  src = fetchIpfs {
    cid = "QmU331ijQLC4A1ziNs5wXY1aZWYPqGXCxoD55vVamitQvW";
    fallbackUrl = "https://archive.org/download/lands-of-lore-1-the-throne-of-chaos-v-cd-1.02-d-1993-m-3-dos/Lands%20of%20Lore%201%20-%20The%20Throne%20of%20Chaos%20%28vCD1.02D%29%20%281993%29%20%28M3%29%20%28DOS%29.7z";
    hash = "sha256-40bWFG/yPJfBdHnZcWEpMb92pp5rA7h0bgvIYJ4Stkg=";
    name = "lands-of-lore-the-throne-of-chaos.7z";
  };

  # FluidR3_GM2 General MIDI SoundFont; used by DOSBox-X's fluidsynth
  # MIDI backend so Westwood's General MIDI music plays without an
  # external timidity/MT-32 daemon.
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
    core=auto
    cputype=auto
    cycles=auto

    [mixer]
    rate=44100
    prebuffer=20

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=5
    dma=1
    oplmode=auto
    oplrate=44100

    # Route MPU-401 / General MIDI to the bundled FluidR3 SoundFont via
    # DOSBox-X's built-in soft-synth (`synth`) so MIDI audio goes through
    # the DOSBox-X mixer -> SDL pipewire path rather than fluidsynth's
    # own audio driver (which doesn't see the host pipewire socket reliably
    # inside the bwrap sandbox).
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
  name = "lands-of-lore-the-throne-of-chaos";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out/cd" "$out/hd" /tmp/lol
    # Stage 1: 7z -> ISO
    7z x "$src" -o/tmp/lol
    isoFile=$(ls /tmp/lol/*.iso | head -n1)
    # Stage 2: ISO -> $out/cd (entire CD tree)
    7z x "$isoFile" -o"$out/cd"
    # Stage 3: pre-seed C: drive with the files INSTALL.EXE would copy.
    cp -r "$out/cd/DATA/HARDRIVE/." "$out/hd/"
    # Stage 4: drop the pre-captured LANDS.CFG so LOLCD.EXE doesn't bail
    # out on "Please run SETUP before running LANDS."
    install -m 0644 ${./LANDS.CFG} "$out/hd/LANDS.CFG"
    # Drop the .7z-extracted ISO so we don't bloat the store output.
    rm -rf /tmp/lol
  '';

  # The hd/ tree gets written to (LANDS.CFG, SAVEGAME.*) so the
  # fuse-overlayfs copy-up must include those file types. Pre-copy the
  # HARDRIVE payload itself; the overlay handles new files transparently.
  copyGlobs = [
    "hd/*"
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

  runScript = ''
    exec ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR/hd\"" \
      -c "mount d \"$GAMEDIR/cd\" -t cdrom" \
      -c "c:" \
      -c "LOLCD.EXE" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Lands of Lore: The Throne of Chaos (1993 Westwood CD, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lands-of-lore-the-throne-of-chaos";
  };
}
