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
  # Burntime (1993, Max Design) freeware re-release. The mr-abandonware
  # bundle ships a Windows NSIS installer that wraps the DOS files; the
  # NSIS payload uses base64-of-UTF-16LE filename components, so we
  # extract twice and decode the names back.
  src = fetchIpfs {
    cid = "QmaneMxgrsy4vZPXTGtSf5DEbbZ3DjHKhjqtYYVe8UN8to";
    fallbackUrl = "https://archive.org/download/burntime-mr-abandonware/Burntime.7z";
    hash = "sha256-Y1Th6SkiuZSJ6qHrBmI8oOwnnUO1cOyVq2tgMhtAFrs=";
    name = "burntime-mr.7z";
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
  name = "burntime";

  inherit src;

  nativeBuildInputs = [
    p7zip
    python3
  ];

  buildScript = ''
    mkdir -p /tmp/bt /tmp/bt-raw "$out"
    7z x "$src" -o/tmp/bt
    7z x '/tmp/bt/Burntime (DOSBox) Installer.exe' -o/tmp/bt-raw

    # NSIS stores each path component as base64(UTF-16LE name). Decode and
    # copy only the C/BURNTIME/* tree (skip the bundled DOSBox.exe / SDL).
    python3 <<'PY'
    import os, base64, shutil, sys
    def dec(p):
        try:
            return base64.b64decode(p + '==').decode('utf-16-le').rstrip('\x00')
        except Exception:
            return p
    out = os.environ['out']
    for root, _, files in os.walk('/tmp/bt-raw'):
        for f in files:
            srcp = os.path.join(root, f)
            rel = os.path.relpath(srcp, '/tmp/bt-raw').replace('\\', '/')
            decoded = '/'.join(dec(p) for p in rel.split('/'))
            # Keep only files inside C/BURNTIME/, drop bundled DOSBox / SDL
            if not decoded.startswith('C/BURNTIME/'):
                continue
            inner = decoded[len('C/BURNTIME/'):]
            if inner in ('DOSBox.exe', 'SDL.dll', 'SDL_net.dll', 'dosbox.conf') \
               or inner.startswith('zmbv/') or inner.startswith('Capture/'):
                continue
            dstp = os.path.join(out, inner)
            os.makedirs(os.path.dirname(dstp) or out, exist_ok=True)
            shutil.copy2(srcp, dstp)
    PY
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
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR\"" \
      -c "c:" \
      -c "burn /5 /220 /1" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Burntime (1993 Max Design freeware re-release, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "burntime";
  };
}
