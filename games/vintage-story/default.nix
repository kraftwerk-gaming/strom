{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
}:

let
  # Phoenix Games Lab repack of the official Vintage Story v1.22.0 Linux
  # build (Built-In Libs flavour - ships its own dotnet 10.0.7 runtime).
  # Tarball lays out: start.sh + game/ + ReadMe + desktop helper. The
  # PlayVintageStory ELF is the dotnet apphost; the actual game lives
  # in Vintagestory.dll via the bundled runtime.
  archive = fetchIpfs {
    cid = "QmQYxnSfCDhtjQ7WqRJwFtMsAkkVoeDkDstaJNdweG7AVP";
    fallbackUrl = "https://archive.org/download/vintage-story-1.21.6-linux-phoenix-games-lab/game-Vintage_Story_%28v1.22.0%29_%5BLinux%2C_Built-In_Libs%5D.tar.xz";
    hash = "sha256-/3vzMey7nCy5hviprV7ircipc7pTVUM2Z6yYWNMCunU=";
    name = "vintage-story-linux-1.22.0.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "vintage-story-data";
    version = "1.22.0";

    src = archive;
    sourceRoot = ".";

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    # libcoreclrtraceptprovider.so is the optional LTTng tracing module
    # for the dotnet runtime; nothing the game uses needs it.
    autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      openal
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      icu
      xorg.libX11
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXext
      xorg.libxcb
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r game "$out"/
      chmod +x "$out/game/PlayVintageStory" "$out/game/Vintagestory" \
               "$out/game/VintagestoryServer" "$out/game/VSCrashReporter" \
               "$out/game/ModMaker" \
               "$out/game/dotnet-runtime-10.0.7-linux-x64/dotnet"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vintage-story";

  ipfsSources = [ archive ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # Vintagestory is a .NET 10 app; the bundled apphost dlopens the bundled
  # dotnet runtime + libfreetype/libfontconfig/libGL/libopenal/etc. by bare
  # name. Use the custom FHS runtime so /usr/lib has the libs autoPatchelf
  # cannot rewrite (the .NET shared store resolves natives at runtime).
  runtime = "custom";
  executable = "game/PlayVintageStory";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      openal
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      icu
      zlib
      xorg.libX11
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXext
      xorg.libxcb
    ];

  preRun = ''
    # Mirror what the official start.sh sets up: point dotnet apphost
    # at the bundled runtime and force fontconfig to read the bundled
    # fonts.conf so Vintage Story finds its own fonts.
    export DOTNET_ROOT="$GAMEDIR/game/dotnet-runtime-10.0.7-linux-x64"
    export FONTCONFIG_FILE="$GAMEDIR/game/fonts.conf"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Vintage Story (native Linux, v1.22.0 with built-in libs)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vintage-story";
  };
}
