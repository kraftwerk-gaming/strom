{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "age-of-empires-ii-the-conquerors";

  src = fetchIpfs {
    cid = "Qmaty9puM8eHXB1qmdHYF7G9dBJNVr6ezV99w5iuNADPxY";
    fallbackUrl = "https://archive.org/download/aoe-2-con/AOE2-CON.zip";
    hash = "sha256-V/IRivuCKy8HUPLIc/n2S9jgsY3vbo5jh6y1wZhbamY=";
    name = "AOE2-CON.zip";
  };

  nativeBuildInputs = [
    unzip
    pkgs.ffmpeg
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q $src -d "$out"
    # Remove third-party hooks that cause problems under Proton/Wine.
    # cnc-ddraw: fails to find a DirectDraw device under gamescope
    # IPXWrapper: hooks networking, not needed for single-player
    rm -f "$out/AOE2-CON/age2_x1/ddraw.dll"
    rm -f "$out/AOE2-CON/age2_x1/ddraw.ini"
    rm -f "$out/AOE2-CON/age2_x1/wsock32.dll"
    rm -f "$out/AOE2-CON/age2_x1/mswsock.dll"
    rm -f "$out/AOE2-CON/age2_x1/dpwsockx.dll"
    rm -f "$out/AOE2-CON/age2_x1/dplayerx.dll"
    rm -f "$out/AOE2-CON/age2_x1/ipxwrapper.dll"
    rm -f "$out/AOE2-CON/age2_x1/clokspl.exe"
    rm -f "$out/AOE2-CON/age2_x1/Greetz.exe"
    rm -f "$out/AOE2-CON/age2_x1/spectate.exe"
    rm -f "$out/AOE2-CON/age2_x1/ipxconfig.exe"
    rm -f "$out/AOE2-CON/age2_x1/cnc-ddraw config.exe"
    rm -rf "$out/AOE2-CON/age2_x1/Shaders"
    # Replace intro AVI videos (Indeo Video 5, unsupported in Wine) with
    # 0.1-second black stub AVIs using msvideo1 (built-in Wine VFW codec).
    # Encodes in milliseconds; the game skips past them instantly.
    for avi in "$out/AOE2-CON/Avi/"*.AVI "$out/AOE2-CON/Avi/"*.avi; do
      [ -f "$avi" ] || continue
      ffmpeg -f lavfi -i color=black:size=320x240:duration=0.1:rate=15 \
        -vcodec msvideo1 -acodec pcm_u8 -ar 22050 -ac 1 -y "$avi"
    done
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # next to its binary, not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "AOE2-CON/age2_x1/age2_x1.5.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    PROTON_USE_WINED3D = "1";
    WINEDLLOVERRIDES = "ddraw=b";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # wined3d cannot create 8bpp palettized (P8_UINT) surfaces required by
  # AoE2. Set DirectDrawRenderer=gdi (software) in the Wine registry so
  # Wine uses GDI rendering for DirectDraw, which handles 8bpp correctly.
  # user.reg uses Wine registry format: paths relative to HKEY_CURRENT_USER.
  preRun = ''
    reg_file="$STROM_COMPATDATA/0/pfx/user.reg"
    if ! grep -q 'DirectDrawRenderer' "$reg_file" 2>/dev/null; then
      printf '\n[Software\\\\Wine\\\\Direct3D]\n"DirectDrawRenderer"="gdi"\n' \
        >> "$reg_file" 2>/dev/null || true
    fi
  '';

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
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
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
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Age of Empires II: The Conquerors (Classic, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "age-of-empires-ii-the-conquerors";
  };
}
