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
  # SimCity 2000 Special Edition (Maxis 1996 DOS), already-installed
  # tree from archive.org/details/msdos_SimCity_2000_SE_1995. The
  # SC2KSEPC GOG ISO ships the unsupported ._-archived city/scenario
  # blobs that only INSTALL.EXE knows how to expand; the msdos zip is
  # the post-install on-disk layout (DATA/ + DOS/ at the root) so we
  # can mount it directly. WillTV (the in-game television interface)
  # plays Smacker videos from the DATA/ tree, and the original
  # simcity.bat mounts that as a CD-ROM so SC2K.EXE finds them at
  # D:\DATA. We replicate that mount layout below.
  src = fetchIpfs {
    cid = "QmeKBV2g2rp4YK1p7rCjyn54xKsNUDVehfHQXazvtWX6BH";
    fallbackUrl = "https://archive.org/download/msdos_SimCity_2000_SE_1995/SimCity_2000_Special_Edition_DOS.zip";
    hash = "sha256-4ZAfqooJQazJo7ku0eoe9BNaJTEqJCWWOeOIUJst81k=";
    name = "simcity-2000-se-dos.zip";
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
    core=auto
    cputype=auto
    cycles=auto

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
  name = "simcity-2000";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
  '';

  copyGlobs = [ ];

  runtime = "custom";

  runScript = ''
    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --immediate-flips --expose-wayland --force-grab-cursor -- \
      ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR\"" \
      -c "mount d \"$GAMEDIR\" -t cdrom" \
      -c "c:" \
      -c "cd DOS" \
      -c "SC2K" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "SimCity 2000 Special Edition (Maxis 1996 DOS, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "simcity-2000";
  };
}
