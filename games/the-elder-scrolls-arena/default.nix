{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  unzip,
}:

let
  # The Elder Scrolls: Arena (Bethesda 1994). Bethesda made the game
  # free in 2004 to mark the series' tenth anniversary; this archive.org
  # mirror is the unmodified floppy release. The zip ships the .gld /
  # .mif / .rmd map and resource files plus `a.exe` (the DOS game) and
  # `arena.bat` (launcher) at the zip root.
  #
  # Arena does not autodetect sound: `a.exe` plays silently unless told
  # which driver (.adv) to load and on which IO/IRQ/DMA. The shipped
  # `arena.bat` carries the working invocation:
  #   A -sa:220 -si:5 -sd:1 -ma:220 -mq:5 -md:1 -ssbdig.adv -msbfm.adv
  # i.e. Sound Blaster digital SFX/speech (sbdig.adv) at IO 220 / IRQ 5 /
  # DMA 1 and Sound Blaster FM (AdLib/OPL) music (sbfm.adv). The IRQ 5
  # already matches the [sblaster] block below, and OPL music is handled
  # entirely by DOSBox's SB emulation, so no MPU-401 MIDI synth/soundfont
  # is needed. Booting a.exe with these args is what `arena.bat` does.
  src = fetchIpfs {
    cid = "QmXbuyCFgRhEzaZroetAdgUKFmipfu1McDVtqg4WB4fXDt";
    fallbackUrl = "https://archive.org/download/the-elder-scrolls-arena/the-elder-scrolls-arena.zip";
    hash = "sha256-EFOZkUF6WRVf/bbKhcD6NrMLsZRIOcyOIwoMRxsZvwg=";
    name = "the-elder-scrolls-arena.zip";
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
    cycles=20000

    [mixer]
    rate=44100

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=5
    dma=1

    [midi]
    mpu401=intelligent

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-elder-scrolls-arena";

  inherit src;

  nativeBuildInputs = [
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
  '';

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
      -c "mount c \"$GAMEDIR\"" \
      -c "c:" \
      -c "a.exe -sa:220 -si:5 -sd:1 -ma:220 -mq:5 -md:1 -ssbdig.adv -msbfm.adv" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "The Elder Scrolls: Arena (Bethesda 1994, freeware re-release via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-elder-scrolls-arena";
  };
}
