{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  gamescope,
  unzip,
}:

let
  # Z (1996, The Bitmap Brothers, published by Virgin Interactive).
  # Humorous robot RTS. Original DOS release; the archive.org item
  # ships an already-installed Z1996/ tree plus a single-track CD
  # image (cd/z.BIN + cd/z.cue) that the game expects mounted at
  # D: for cinematics. The original Z.BAT runs `ZED.EXE /CD:D` and
  # the bundled IAFIX.BAT does the imgmount + chdir to Z\. There
  # are no CD audio tracks on this image; the data track is the
  # only track, so music falls back to the in-game MIDI/XMI files
  # which are stored under Z\AUDIO\.
  src = fetchIpfs {
    cid = "QmQ5Q51cBoG66qiMkQq25vR8YCQJxovHU45JqeQaxwfPAd";
    fallbackUrl = "https://archive.org/download/msdos_Z_1996/Z_1996.zip";
    hash = "sha256-8Gm2mxJ3R9hewdcFCPaww1Fkjik3ScVvNLSfc+678gs=";
    name = "z.zip";
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
    cputype=pentium
    cycles=50000

    [mixer]
    rate=44100

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=7
    dma=1
    hdma=5

    [midi]
    mpu401=intelligent

    [joystick]
    joysticktype=2axis
    timed=false

    [mouse]
    sensitivity=30

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "z";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d /tmp/z-extract
    cp -r /tmp/z-extract/Z1996/* "$out"/
  '';

  copyGlobs = [ ];

  runtime = "custom";

  runScript = ''
    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --immediate-flips --expose-wayland --force-grab-cursor -- \
      ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "imgmount d \"$GAMEDIR/cd/z.cue\" -t cdrom" \
      -c "mount c \"$GAMEDIR/Z\"" \
      -c "c:" \
      -c "ZED.EXE /CD:D" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Z (Bitmap Brothers 1996, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "z";
  };
}
