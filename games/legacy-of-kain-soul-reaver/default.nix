{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
  unzip,
}:

let

  dxwrapper = fetchurl {
    url = "https://github.com/elishacloud/dxwrapper/releases/download/v1.6.8300.25/dx7.games.zip";
    hash = "sha256-JwAc533qpi0tK7ilVX7FS0X9RI3VuIBI+si93wRHF54=";
    name = "dxwrapper.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "legacy-of-kain-soul-reaver";

  src = fetchIpfs {
    cid = "Qmb1u6CUu1gLRvb2tiWY1LaV1Bhe51xhXrpu8bpHnLXEKp";
    fallbackUrl = "https://archive.org/download/legacy-of-kain-soul-reaver-gog/Legacy%20of%20Kain%20Soul%20Reaver%20%5BGOG%5D.zip";
    hash = "sha256-RWC9JCqwRTqAOrMzKz70o3RrFaKsrkNQrHwc3yq5FDI=";
    name = "soul-reaver-gog.zip";
    };

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -j $src "*/setup_legacy_of_kain_soul_reaver_*.exe" -d /tmp/sr
    innoextract -d /tmp/sr-extract /tmp/sr/setup_legacy_of_kain_soul_reaver_*.exe
    mv /tmp/sr-extract/app/* "$out"/

    # Add dxwrapper (DirectDraw 7 -> Direct3D 9 conversion)
    unzip -o ${dxwrapper} -d "$out"/

    # Configure dxwrapper
    sed -i \
      -e 's/Dinputto8                  = 0/Dinputto8                  = 1/' \
      -e 's/DdrawLimitDisplayModeCount = 0/DdrawLimitDisplayModeCount = 1/' \
      "$out/dxwrapper.ini"

    # Create dinput.dll wrapper
    cp "$out/ddraw.dll" "$out/dinput.dll"
  '';

  runtime = "proton";
  executable = "kain2.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland";

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    STEAM_COMPAT_CONFIG = "sdlinput";
    WINEDLLOVERRIDES = "ddraw,dinput=n,b";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  preRun = ''
    # Override .arg to select hardware D3D device
    echo "under 0 -mainmenu -voice -inspectral" > "$GAMEDIR/kain2.arg"
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
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
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
    description = "Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "legacy-of-kain-soul-reaver";
  };
}
