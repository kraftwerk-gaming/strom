{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "fallout-2";

  src = fetchIpfs {
    cid = "Qmcp7sfYBKRtWSZnfy1aPLv4DJGu3VPEGn9vddf1dAVU4K";
    fallbackUrl = "https://archive.org/download/fallout_2_classic_2.1.0.18_win_gog_20240211/setup_fallout2_2.1.0.18.exe";
    hash = "sha256-XcXbQwdJ3c3+hWYT/LYK6KzBQFh3lS6HKBS7wUD3/6Y=";
    name = "setup_fallout2_2.1.0.18.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" $src
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
    rm -rf "$out/tmp" "$out/commonappdata"
  '';

  runtime = "proton";
  executable = "fallout2HR.exe";

  saveLocations = [ "AppData/Roaming/Fallout2" ];
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
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
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
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
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
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Fallout 2 (GOG Classic, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fallout-2";
  };
}
