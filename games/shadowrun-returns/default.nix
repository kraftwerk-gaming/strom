{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

let
  # Shadowrun Returns (Harebrained Schemes, 2013).
  # Unity 4.0 tactical cRPG; 32-bit Linux build shipped by GOG. The GOG
  # offline installer is a mojosetup .sh (shell-script header + zip
  # payload); unzip extracts it directly. Layout inside the zip:
  #   data/noarch/game/Shadowrun           — 32-bit ELF binary (Unity player)
  #   data/noarch/game/ShadowrunEditor     — content editor
  #   data/noarch/game/Shadowrun_Data/     — Unity assets, DLCs
  #   data/noarch/game/Shadowrun_Data/Mono/x86/libmono.so  — bundled Mono
  #   data/noarch/game/Shadowrun_Data/Plugins/             — Steam .so files
  #
  # Source: archive.org item
  #   shadowrun-returns-linux-gog-phoenix-games-lab
  #   file: gog_shadowrun_returns_2.0.0.7.sh
  #   size: 1,003,776,418 bytes  md5: 61c12b14c7e6040cb1465390320a61da
  installer = fetchIpfs {
    cid = "QmUxYa9rWM68JjTBLRE94JzCh7kkXqGYf73roH4xh5pLNa";
    fallbackUrl = "https://archive.org/download/shadowrun-returns-linux-gog-phoenix-games-lab/gog_shadowrun_returns_2.0.0.7.sh";
    hash = "sha256-lAMNuV7mgSJAM7zjzADX6mGxD/AKk+HSnCRZo1vUUSE=";
    name = "gog_shadowrun_returns_2.0.0.7.sh";
  };

  # i686 stdenv so autoPatchelfHook recognises the 32-bit ELF and patches
  # the RPATH/interpreter; the x86_64 hook skips foreign-arch binaries.
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "shadowrun-returns-data";
    version = "1.2.7";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgsi686Linux.autoPatchelfHook
    ];

    # Libraries the Unity 4.0 32-bit player and bundled .so files need.
    # No ScreenSelector.so in this version (Unity 4.0 pre-dates it).
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      libx11
      libxext
      SDL
      glib
    ];

    buildPhase = ''
      runHook preBuild
      # mojosetup .sh has a shell header; unzip warns but succeeds.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/Shadowrun"
      # ShadowrunEditor needs Qt4 which is not packaged; drop it.
      rm -f "$out/ShadowrunEditor"
      runHook postInstall
    '';

    # Bundled libs in Shadowrun_Data/Mono/x86/ and Plugins/ use
    # $ORIGIN-relative RPATHs; preserve them via autoPatchelf.
    appendRunpaths = [
      "$ORIGIN"
      "$ORIGIN/Shadowrun_Data/Mono/x86"
      "$ORIGIN/Shadowrun_Data/Plugins"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shadowrun-returns";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "Shadowrun";

  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity 4.x on Linux writes saves to ~/.config/unity3d/<Company>/<Product>/.
  saveLocations = [ ".config/unity3d/Harebrained Schemes/Shadowrun Returns" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  env = {
    # Old bundled libSDL/Unity probes Wayland and may abort; force X11.
    SDL_VIDEODRIVER = "x11";

    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgsi686Linux;
      [
        libGL
        libx11
        libxext
        libxi
        libxrandr
        libxcursor
        libxfixes
        libpulseaudio
        alsa-lib
        stdenv.cc.cc.lib
      ]
    );
  };

  meta = {
    description = "Shadowrun Returns (Harebrained Schemes 2013, native Linux, GOG v2.0.0.7)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadowrun-returns";
  };
}
