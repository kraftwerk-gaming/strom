{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

let
  # Shadowrun: Hong Kong — Extended Edition (Harebrained Schemes, 2015).
  # Unity 5.x tactical cRPG; 32-bit Linux build shipped by GOG. The GOG
  # offline installer is a mojosetup .sh (shell-script header + zip payload);
  # unzip extracts it directly. Layout inside the zip:
  #   data/noarch/game/SRHK            — 32-bit ELF Unity player
  #   data/noarch/game/SRHK.sh         — launch wrapper
  #   data/noarch/game/ShadowrunEditor — content editor (dropped)
  #   data/noarch/game/SRHK_Data/      — Unity assets
  #   data/noarch/game/SRHK_Data/Mono/x86/libmono.so   — bundled Mono
  #   data/noarch/game/SRHK_Data/Plugins/x86/          — ScreenSelector, Steam .so
  #
  # Source: archive.org item
  #   shadowrun-hong-kong-ee-linux-gog-phoenix-games-lab
  #   file: gog_shadowrun_hong_kong_extended_edition_2.8.0.11.sh
  #   size: 3,401,437,059 bytes  md5: 643ba68e47c309d391a6482f838e46af
  installer = fetchIpfs {
    cid = "QmZx67dsoursuByjTNYt8jPHqrSJzWpJfecr4fQMePDDCg";
    fallbackUrl = "https://archive.org/download/shadowrun-hong-kong-ee-linux-gog-phoenix-games-lab/gog_shadowrun_hong_kong_extended_edition_2.8.0.11.sh";
    hash = "sha256-m6a6hVOSx+ay4fKnQFxC4i6W7JhABPO5aWVXtrctzgw=";
    name = "gog_shadowrun_hong_kong_extended_edition_2.8.0.11.sh";
  };

  # i686 stdenv so autoPatchelfHook recognises the 32-bit ELF and patches
  # the RPATH/interpreter; the x86_64 hook skips foreign-arch binaries.
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "shadowrun-hong-kong-extended-edition-data";
    version = "2.8.0.11";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgsi686Linux.autoPatchelfHook
    ];

    # Libraries the Unity 5.x 32-bit player and bundled .so files need.
    # SRHK: libGLU.so.1 + libGL; ScreenSelector.so: GTK2 stack.
    # ShadowrunEditor needs Qt4 but we drop it (game-only install).
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      libx11
      libxext
      SDL
      # GTK2 stack for ScreenSelector.so (Unity screen-resolution picker)
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
      # mojosetup .sh has a ~880 KB shell header; unzip warns but succeeds.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/SRHK"
      # ShadowrunEditor needs Qt4 which is not packaged; drop it.
      rm -f "$out/ShadowrunEditor"
      runHook postInstall
    '';

    # Bundled libs in SRHK_Data/Mono/x86/ and Plugins/x86/ use
    # $ORIGIN-relative RPATHs; preserve them via autoPatchelf.
    appendRunpaths = [
      "$ORIGIN"
      "$ORIGIN/SRHK_Data/Mono/x86"
      "$ORIGIN/SRHK_Data/Plugins/x86"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shadowrun-hong-kong-extended-edition";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "SRHK";

  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity on Linux writes saves to ~/.config/unity3d/<Company>/<Product>/.
  saveLocations = [ ".config/unity3d/Harebrained Schemes/Shadowrun Hong Kong" ];

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
    description = "Shadowrun: Hong Kong — Extended Edition (Harebrained Schemes 2015, native Linux, GOG v2.8.0.11)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadowrun-hong-kong-extended-edition";
  };
}
