{
  self,
  lib,
  pkgs,
  fetchurl,
  dosbox-x,
  gamescope,
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

    [pci]
    voodoo=true

    [voodoo]
    voodoo_card=auto
    voodoo_maxmem=true
    glide=true
    lfb=full_noaux
    splash=false

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "archimedean-dynasty";

  src = fetchurl {
    url = "https://archive.org/download/msdos_Archimedean_Dynasty_1996/msdos_Archimedean_Dynasty_1996.zip";
    hash = "sha256-CBIRQ3TqzVgRa99DDbTZLJHrueouYUQJo4Aeq0H016o=";
    name = "archimedean-dynasty.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -o $src -d /tmp/ad
    cp -r /tmp/ad/Archimed/* "$out"/

    mv "$out/CD/Archimedean Dynasty.bin" "$out/CD/ad.bin"
    mv "$out/CD/Archimedean Dynasty.cue" "$out/CD/ad.cue"
    sed -i 's/Archimedean Dynasty/ad/g' "$out/CD/ad.cue"
  '';

  copyGlobs = [ ];

  runtime = "custom";

  runScript = ''
    export XDG_CONFIG_HOME="$GAMEDIR/.config"

    # Enable joystick on first run
    if grep -q "Joystick = 0" "$GAMEDIR/BLUEBYTE/AD/CONFIG.DES" 2>/dev/null; then
      sed -i 's/Joystick = 0/Joystick = 1/' "$GAMEDIR/BLUEBYTE/AD/CONFIG.DES"
    fi

    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --immediate-flips --expose-wayland --force-grab-cursor -- \
      ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "imgmount d \"$GAMEDIR/CD/ad.cue\" -t cdrom" \
      -c "mount c \"$GAMEDIR/BLUEBYTE/AD\"" \
      -c "c:" \
      -c "AD3DFX.EXE" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "archimedean-dynasty";
  };
}
