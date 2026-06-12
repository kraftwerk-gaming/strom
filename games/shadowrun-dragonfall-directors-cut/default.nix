{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

let
  # Shadowrun: Dragonfall — Director's Cut (Harebrained Schemes, 2014).
  # Unity 4.x tactical RPG; 32-bit Linux build shipped by GOG. The GOG
  # offline installer is a mojosetup .sh (shell-script header + zip
  # payload); unzip extracts it directly. Layout inside the zip:
  #   data/noarch/game/Dragonfall          — 32-bit ELF binary (Unity player)
  #   data/noarch/game/ShadowrunEditor     — content editor
  #   data/noarch/game/Dragonfall_Data/    — Unity assets, DLCs
  #   data/noarch/game/Dragonfall_Data/Mono/x86/libmono.so   — bundled Mono
  #   data/noarch/game/Dragonfall_Data/Plugins/x86/          — Screen/Steam .so
  #
  # Source: archive.org item
  #   shadowrun-dragonfall-dc-linux-gog-phoenix-games-lab
  #   file: gog_shadowrun_dragonfall_director_s_cut_2.6.0.11.sh
  #   size: 1,998,214,250 bytes  md5: ee3db5bc8554852337b063b993f66012
  installer = fetchIpfs {
    cid = "QmVfdbdot5WARgLhi1eJ9BxRvmrsDD8e97RnAsMrZc2Y9h";
    fallbackUrl = "https://archive.org/download/shadowrun-dragonfall-dc-linux-gog-phoenix-games-lab/gog_shadowrun_dragonfall_director_s_cut_2.6.0.11.sh";
    hash = "sha256-pZe4W3a4gy2ZhIPpM02QHXpKI15Ej1dwpVX7H8bKRAo=";
    name = "gog_shadowrun_dragonfall_director_s_cut_2.6.0.11.sh";
  };

  # i686 stdenv so autoPatchelfHook recognises the 32-bit ELF and patches
  # the RPATH/interpreter; the x86_64 hook skips foreign-arch binaries.
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "shadowrun-dragonfall-directors-cut-data";
    version = "2.0.9";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgsi686Linux.autoPatchelfHook
    ];

    # Libraries the Unity 4.x 32-bit player and bundled .so files need.
    # Dragonfall: libGLU.so.1 + libGL; ScreenSelector.so: GTK2 stack.
    # ShadowrunEditor needs Qt4 but we drop it (game-only install).
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      libx11
      libxext
      SDL
      # GTK2 stack for ScreenSelector.so (Unity 4.x screen-resolution picker)
      gtk2
      glib
      pango
      cairo
      atk
      gdk-pixbuf
      freetype
      fontconfig
    ];

    buildPhase = ''
      runHook preBuild
      # mojosetup .sh has a ~795 KB shell header; unzip warns but succeeds.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/Dragonfall"
      # ShadowrunEditor needs Qt4 which is not packaged; drop it.
      rm -f "$out/ShadowrunEditor"
      runHook postInstall
    '';

    # Bundled libs in Dragonfall_Data/Mono/x86/ and Plugins/x86/ use
    # $ORIGIN-relative RPATHs; preserve them via autoPatchelf.
    appendRunpaths = [
      "$ORIGIN"
      "$ORIGIN/Dragonfall_Data/Mono/x86"
      "$ORIGIN/Dragonfall_Data/Plugins/x86"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shadowrun-dragonfall-directors-cut";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "Dragonfall";

  # Suppress Unity's on-screen log overlay (-logFile -) and keep a copy
  # next to the binary for post-mortem inspection (-logFile output.log is
  # the launcher default, but the overlay is noisy).
  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity 4.x on Linux writes saves to ~/.config/unity3d/<Company>/<Product>/.
  # The native runtime binds $HOME -> $STROM_GAMEDIR so this persists across
  # overlay rebuilds without an explicit relocation.
  saveLocations = [ ".config/unity3d/Harebrained Schemes/Dragonfall - Director's Cut" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  env = {
    # Old bundled libSDL/Unity probes Wayland and may abort; force X11
    # (gamescope exposes an Xwayland DISPLAY inside the nest).
    SDL_VIDEODRIVER = "x11";

    # System libs needed by the 32-bit Unity player.  Bundled Mono and
    # Steam plugin .so files are loaded via $ORIGIN RPATHs patched above.
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
    description = "Shadowrun: Dragonfall — Director's Cut (Harebrained Schemes 2014, native Linux, GOG v2.0.9)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadowrun-dragonfall-directors-cut";
  };
}
