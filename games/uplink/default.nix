{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

let
  gameSrc = fetchIpfs {
    cid = "Qmc19LJsreV5YiXRstCF4ZzJzCn5b32AthwFgYrWJsMp2N";
    hash = "sha256-XL5AqBwwNusFAIiUd7vkNi92bOUANM8qgEo9WRtCK34=";
    name = "uplink-1.6.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "uplink";

  ipfsSources = [ gameSrc ];
  src = gameSrc;

  nativeBuildInputs = [
    innoextract
  ];

  buildScript = ''
    mkdir -p /tmp/extract
    innoextract --exclude-temp -d /tmp/extract "$src"

    mkdir -p "$out"
    # Game files are at the root level of the extract
    cp -r /tmp/extract/* "$out"/
    # Remove installer artifacts
    rm -rf "$out"/__redist "$out"/commonappdata "$out"/app
    rm -f "$out"/goggame-*
  '';

  runtime = "proton";
  executable = "uplink.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
  };

  env = {
    PROTON_USE_WINED3D = "1";
    PULSE_LATENCY_MSEC = "60";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
    pkgs.systemd
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  meta = {
    description = "Uplink: Hacker Elite v1.6 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "uplink";
  };
}
