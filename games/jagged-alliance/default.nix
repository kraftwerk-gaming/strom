{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  p7zip,
}:

let
  # Jagged Alliance (1995 Sir-Tech / Madlab Software) MS-DOS, v1.13.
  #
  # Asset: the archive.org item "Jagged Alliance | MS-DOS | Portable
  # Install" (CJ_Strife). It is a clean, already-installed game
  # directory -- no InstallShield, no floppy images -- wrapped in a
  # DOSBox-Staging-for-Windows launcher we throw away. Only
  # `Jagged Alliance/_dosbox/_gamefiles/` is kept; that tree is the
  # installed C: drive (JA.EXE, DOS4GW.EXE, DAT/ EDT/ FX/ INTRO/ ...)
  # plus JA1.BIN, the 408 MB CD-ROM ISO holding the speech/video that
  # the CD release streams from D:.
  #
  # The upstream bundle's run.conf does exactly two mounts:
  #   MOUNT C .\_dosbox\_gamefiles
  #   IMGMOUNT D ".\_dosbox\_gamefiles\JA1.BIN" -t iso -fs iso
  # and then runs JA.EXE. We reproduce that with two deviations.
  # First, JA1.BIN is split out of the C: tree into $out/ so a 408 MB
  # file can never be dragged through fuse-overlayfs copy-up. Second,
  # the image is mounted `-t cdrom` rather than `-t iso -fs iso`, which
  # is both the convention here (games/archimedean-dynasty,
  # games/lemmings, games/z all imgmount `-t cdrom`) and the more
  # correct mount: `-t iso` exposes the ISO9660 filesystem as a plain
  # drive, while `-t cdrom` registers an MSCDEX CD-ROM device, which is
  # what a 1995 CD release expects to find. The image is a single data
  # track with no CD audio, so the score comes from the MIDI drivers on
  # C:, not from redbook. The 1-byte `CD.ROM` marker in the game
  # directory is what tells JA.EXE this is the CD release, so it stays
  # on C:.
  #
  # Sound: the bundle ships a pre-made SOUND.CFG (produced by
  # SETSOUND.EXE) selecting `sb16.dig` for digital audio and
  # `ultra.mdi` -- the Miles Gravis Ultrasound driver -- for music.
  # So the [gus] block below is load-bearing, not decoration: without
  # `gus = true` the game's music driver finds no card and the score
  # is silent. DOSBox-X reads the GUS patch set from `ultradir`, and
  # the bundle ships the full Gravis patch set at C:\ULTRASND\MIDI, so
  # `ultradir = C:\ULTRASND` resolves inside the mounted C: drive.
  # SETSOUND.EXE can still be re-run from the overlay to pick AdLib /
  # MT-32 / PC speaker instead.
  #
  # CPU: JA is a DOS4GW protected-mode title from 1995 whose combat
  # engine is uncapped, so a fixed cycle count either crawls during
  # line-of-sight recalcs or fast-forwards the intro. `core = dynamic`
  # + `cycles = max` is what the upstream portable install uses and is
  # the right call for this era of protected-mode game.
  #
  # Saves: JA writes its savegames (SAVEGAME.SAV / *.DAT scratch files)
  # straight into its own install directory on C: rather than into a
  # user profile path -- verified against the bundle layout, there is
  # no separate SAVE/ directory and no configurable save path. That is
  # fine here: mk-game.nix mounts the nix-store game data under a
  # per-game fuse-overlayfs whose upper lives in ~/.strom/<slug>, so
  # new files written to C: land in the upper and survive across runs
  # with no relocation needed. Hence copyGlobs stays empty -- nothing
  # has to be pre-materialized, the overlay handles creates and
  # copy-ups transparently (this is only needed for Wine's mmap
  # writes, cf. games/realms-of-the-haunting).
  src = fetchIpfs {
    cid = "QmUPQbDJSSp7cAeeMz7AUWaAXBNs7RuyPKxM774JPSpdAN";
    fallbackUrl = "https://archive.org/download/jagged-alliance.-7z/Jagged%20Alliance.7z";
    hash = "sha256-duBGGn2+4oev8i340PUGNDG9CEh18+42pEzdC6+ACiQ=";
    name = "jagged-alliance.7z";
  };

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
    cputype=auto
    cycles=max

    [mixer]
    rate=44100

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=5
    dma=1

    # Music path: SOUND.CFG selects ultra.mdi (Gravis Ultrasound).
    # DOSBox-X exports ULTRASND/ULTRADIR into the guest environment
    # itself once the card is enabled.
    [gus]
    gus=true
    gusrate=44100
    gusbase=240
    gusirq=5
    gusdma=3
    gustype=classic
    ultradir=C:\ULTRASND

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "jagged-alliance";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out/hd" "$TMPDIR/ja"
    7z x "$src" -o"$TMPDIR/ja" "Jagged Alliance/_dosbox/_gamefiles"
    cp -r "$TMPDIR/ja/Jagged Alliance/_dosbox/_gamefiles/." "$out/hd/"
    # Keep the CD image out of the C: tree (see header comment).
    mv "$out/hd/JA1.BIN" "$out/JA1.BIN"
    rm -rf "$TMPDIR/ja"
  '';

  # The overlay handles save creation on C: transparently; nothing
  # needs pre-materializing.
  copyGlobs = [ ];

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
      -c "imgmount d \"$GAMEDIR/JA1.BIN\" -t cdrom" \
      -c "c:" \
      -c "JA.EXE" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Jagged Alliance (1995 Sir-Tech / Madlab, DOS CD release via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "jagged-alliance";
  };
}
