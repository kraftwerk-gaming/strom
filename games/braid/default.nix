{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

let
  # GOG Linux release of Braid (mojosetup self-extracting installer:
  # shell-script header + zip archive). Native 32-bit ELF binaries,
  # DRM-free.
  installer = fetchIpfs {
    cid = "QmUVVVtFTDg7MUPL6q8a5F6wYqgZdsrtp29j653NvWesjN";
    fallbackUrl = "https://archive.org/download/braid-gog-linux-phoenix-games-lab/Braid_%5BLinux%2C_GOG%5D%2Fgog_braid_2.0.0.3.sh";
    hash = "sha256-U39DZ6XvESQxKwVz1PDzRumGxS/osXoutZsn1ly5OAk=";
    name = "braid-gog-2.0.0.3.sh";
  };

  # Use the i686 stdenv so autoPatchelfHook recognises the bundled
  # 32-bit ELF binaries as a valid target arch and actually patches them
  # (the x86_64 stdenv's hook skips them with "architecture differs").
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "braid-data";
    version = "2.0.0.3";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgsi686Linux.autoPatchelfHook
    ];

    # 32-bit runtime libs needed by the bundled binaries.
    # launcher.bin.x86 uses fltk + libX11; Braid.bin.x86 uses SDL2 + GL +
    # NVIDIA's Cg toolkit (libCg/libCgGL are bundled in game/lib/).
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc
      glibc
      libGL
      libx11
      fltk_1_3
      SDL2
    ];

    buildPhase = ''
      runHook preBuild
      # The mojosetup .sh is a zip with a shell-script preamble; unzip
      # complains about the extra header bytes but extracts cleanly.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/Braid.bin.x86" "$out/launcher.bin.x86"
      runHook postInstall
    '';

    # autoPatchelfHook should also patch the bundled libs in lib/ so they
    # find their own deps from the nix store.
    appendRunpaths = [ "$ORIGIN/lib" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "braid";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  # launcher.bin.x86 is the small fltk options launcher; Braid.bin.x86 is
  # the actual game and works standalone.
  executable = "Braid.bin.x86";
  # Braid.bin.x86 spawns launcher.bin.x86 (a fltk options dialog) on
  # startup unless this flag is passed. We always want to go straight
  # to the game.
  executableArgs = [ "-no_launcher" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  env = {
    # The bundled libSDL2 (2015 vintage) probes for Wayland support and
    # aborts SDL_Init when its wayland-client/protocols ABI doesn't match
    # what's on the host. Force the X11 backend (Xwayland) instead.
    SDL_VIDEODRIVER = "x11";
    # SDL2 dlopens X11/udev/audio backends at runtime. The bundled
    # libSDL2 also pulls in libudev.so.1 for joystick hotplug.
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      pkgsi686Linux.libx11
      pkgsi686Linux.libxext
      pkgsi686Linux.libxcursor
      pkgsi686Linux.libxrandr
      pkgsi686Linux.libxi
      pkgsi686Linux.libxfixes
      pkgsi686Linux.libxkbcommon
      pkgsi686Linux.libGL
      pkgsi686Linux.libpulseaudio
      pkgsi686Linux.alsa-lib
      pkgsi686Linux.systemdLibs
    ];
  };

  # Bundled 32-bit libCg/libCgGL/libSDL2/libfltk live next to the game
  # binary; prepend $GAMEDIR/lib so they take precedence over system libs.
  preRun = ''
    export LD_LIBRARY_PATH="$GAMEDIR/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  meta = {
    description = "Braid (native Linux, GOG)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "braid";
  };
}
