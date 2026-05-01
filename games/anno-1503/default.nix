{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

let
  # GOG-style "Anno 1503 A.D." installer (Inno Setup 5.5.0). Single
  # self-contained .exe, no separate disc image. Extracts cleanly with
  # innoextract; the game lives under "app/" and is DRM-free.
  setupExe = fetchIpfs {
    cid = "QmdmLrow98WgTbxK4xMoZFS9SpBMSX3WBJQdsw4SSnDLhy";
    fallbackUrl = "https://archive.org/download/anno-1503_202601/Anno-1503-setup.exe";
    hash = "sha256-HHjrjh0qd1LavaP1ASaK+vIizD9G8K5axx0F4Pkd0jM=";
    name = "anno-1503-setup.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anno-1503";

  ipfsSources = [ setupExe ];
  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" "$src"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
  '';

  runtime = "proton";
  # 1503Startup.exe is the launcher shipped by the GOG installer; it
  # invokes the actual game binary.
  executable = "1503Startup.exe";
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 1024;
    flags."--expose-wayland" = true;
    # Same edge-scroll workaround as Anno 1602: gamescope's pointer
    # mapping at fast cursor speeds produces phantom edge events without
    # an explicit grab.
    flags."--force-grab-cursor" = true;
  };

  env = {
    PROTON_NO_PROTONFIXES = "1";
    PROTON_USE_WINED3D = "1";
    PULSE_LATENCY_MSEC = "60";
    WINE_VD = "1280x1024";
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
    # Same DirectInput joystick-axis workaround as Anno 1602: the engine
    # turns any non-zero axis into permanent edge-scrolling. Hide all
    # joystick / evdev devices from the sandbox.
    "--tmpfs /dev/input"
  ];

  meta = {
    description = "Anno 1503 A.D. (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anno-1503";
  };
}
