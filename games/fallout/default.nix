{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unar,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "fallout";

  src = fetchIpfs {
    cid = "QmVcYYsXnYEEc2zLKUcq4FnXDjBsPMTGYc3Ehiko4EMHpx";
    fallbackUrl = "https://archive.org/download/fallout-1-classic-2.1.0.18-gog/Fallout%201%20%28Classic%29%202.1.0.18%20%5BGOG%5D.rar";
    hash = "sha256-9yTL7jYeu8pbZl5wRF0LJju69B3WmdjYru74u3KOPG0=";
    name = "fallout-1-classic-gog.rar";
  };

  nativeBuildInputs = [
    innoextract
    unar
  ];

  buildScript = ''
    mkdir -p "$out"
    # Extract the RAR to get the GOG setup exe
    unar -q -o /tmp/fallout-build "$src"
    # Extract the Inno Setup installer
    setup_exe=$(find /tmp/fallout-build -name 'setup_fallout_*.exe' | head -1)
    innoextract -d "$out" "$setup_exe"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
    rm -rf "$out/tmp" "$out/commonappdata"
    rm -rf /tmp/fallout-build
  '';

  runtime = "proton";
  executable = "falloutwHR.exe";

  saveLocations = [ "AppData/Roaming/Fallout" ];
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
    description = "Fallout (GOG Classic, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fallout";
  };
}
