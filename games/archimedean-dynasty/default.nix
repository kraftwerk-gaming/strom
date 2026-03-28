{
  dosbox-x,
  fetchurl,
  gamescope,
  runCommandLocal,
  stdenvNoCC,
  unzip,
  writeShellScript,
  writeText,
}:

let
  gameArchive = fetchurl {
    url = "https://archive.org/download/msdos_Archimedean_Dynasty_1996/msdos_Archimedean_Dynasty_1996.zip";
    hash = "sha256-CBIRQ3TqzVgRa99DDbTZLJHrueouYUQJo4Aeq0H016o=";
    name = "archimedean-dynasty.zip";
  };

  gameFiles =
    runCommandLocal "archimedean-dynasty-data"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -o ${gameArchive} -d /tmp/ad
        cp -r /tmp/ad/Archimed/* "$out"/

        # Rename CD image to avoid spaces in paths
        mv "$out/CD/Archimedean Dynasty.bin" "$out/CD/ad.bin"
        mv "$out/CD/Archimedean Dynasty.cue" "$out/CD/ad.cue"
        sed -i 's/Archimedean Dynasty/ad/g' "$out/CD/ad.cue"
      '';

  dosboxConf = writeText "dosbox.conf" ''
    [sdl]
    fullscreen=false
    output=opengl
    autolock=true


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

  wrapper = writeShellScript "archimedean-dynasty" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/archimedean-dynasty"
    mkdir -p "$GAMEDIR"

    # Copy game files (DOSBox needs writable directory for saves/config)
    if [ ! -f "$GAMEDIR/BLUEBYTE/AD/AD.EXE" ]; then
      cp -r "${gameFiles}"/. "$GAMEDIR/"
      chmod -R u+w "$GAMEDIR"

      # Enable joystick in game config
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
in
stdenvNoCC.mkDerivation {
  pname = "archimedean-dynasty";
  version = "1996";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${wrapper} $out/bin/archimedean-dynasty
  '';

  meta = {
    description = "Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "archimedean-dynasty";
  };
}
