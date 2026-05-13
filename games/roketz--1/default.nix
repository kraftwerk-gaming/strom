{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  unzip,
}:

let
  dosboxConf = pkgs.writeText "dosbox.conf" ''
    [sdl]
    fullscreen=false
    output=opengl
    autolock=true
    showmenu=false

    [cpu]
    core=dynamic
    cputype=pentium
    cycles=20000

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

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "roketz--1";

  src = fetchIpfs {
    cid = "QmZ1nZ8Hkm81P48ABcfGBot8rSkb2c4K2badYPBrMsT2zp";
    fallbackUrl = "https://archive.org/download/msdos_Roketz_1996/Roketz_1996.zip";
    hash = "sha256-B7watv6BBqGmuM57lMo2va3z8jkcC9mT+qtNClGWf+w=";
    name = "roketz-1996.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d /tmp/rk
    cp -r /tmp/rk/Roketz/roketz/* "$out"/
  '';

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
      -fastlaunch \
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR\"" \
      -c "mount d \"$GAMEDIR\" -t cdrom" \
      -c "c:" \
      -c "ROKETZ.EXE" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Roketz (1996, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "roketz--1";
  };
}
