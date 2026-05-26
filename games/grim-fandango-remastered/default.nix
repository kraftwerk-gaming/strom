{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  pkgsi686Linux,
}:

let
  # GOG native Linux build of Grim Fandango Remastered (Double Fine
  # 2015 remaster, game v1.4, installer v2.3.0.7). Standard mojosetup
  # `.sh` -> zip payload pattern: unzip the script, copy
  # `data/noarch/game/`, run the bundled `bin/GrimFandango` ELF.
  #
  # The bundled `bin/GrimFandango` is a 32-bit i386 ELF (the `amd64/`
  # tree next to it is only the Steam Runtime library bundle that
  # `run.sh` would prepend to LD_LIBRARY_PATH). Build the data
  # derivation with `pkgsi686Linux.stdenv` so autoPatchelfHook
  # recognises the binary and the bundled 32-bit libs as a matching
  # arch -- the x86_64 stdenv's hook silently skips ELF32 with
  # "architecture differs", leaving the interpreter as
  # `/lib/ld-linux.so.2` (not present in our FHS rootfs) and crashing
  # the game with an immediate ENOENT in gamescope's reaper.
  installer = fetchIpfs {
    cid = "QmWeeupcjMJZQjn4q6rrZ4voYK5bb6VtcaLczMtEk9Wsbc";
    fallbackUrl = "https://archive.org/download/grim-fandango-remastered-linux-gog-phoenix-games-lab/gog_grim_fandango_remastered_2.3.0.7.sh";
    hash = "sha256-qu/OyQuwiLg0y+BSVpegJeBm4bplCaaW2rOuYGz3T/g=";
    name = "gog_grim_fandango_remastered_2.3.0.7.sh";
  };

  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "grim-fandango-remastered-data";
    version = "1.4";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgsi686Linux.autoPatchelfHook
    ];

    # 32-bit runtime libs for the bundled GrimFandango binary +
    # libchore/libLua/libSDL2. The game dlopens X11 / audio / GL
    # backends at runtime, so they have to be reachable at run time
    # too (see env.LD_LIBRARY_PATH below).
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      openal
      libpulseaudio
      alsa-lib
      libxkbcommon
      libx11
      libxext
      libxrandr
      libxi
      libxcursor
      libxinerama
      libxcb
      SDL2
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      # Drop the bundled Steam Runtime trees; autoPatchelfHook will
      # repoint the game and its sibling 32-bit libs at nixpkgs.
      rm -rf "$out/bin/amd64" "$out/bin/i386"
      chmod +x "$out/bin/GrimFandango"
      runHook postInstall
    '';

    # Make sure the patched binary still finds the bundled libs that
    # live next to it (libchore.so, libLua.so, libSDL2-2.0.so.1).
    appendRunpaths = [ "$ORIGIN" ];

    autoPatchelfIgnoreMissingDeps = [
      "libSDL2-2.0.so.0"
      "libcrypt.so.1"
      "libdb-5.1.so"
      "libthai.so.0"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "grim-fandango-remastered";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # Patchelf'd ELF resolves everything through /nix/store paths, so
  # the FHS chroot is unnecessary. Match the Braid recipe (same GOG
  # mojosetup shape) and run native.
  runtime = "native";
  executable = "bin/GrimFandango";

  env = {
    # The bundled libSDL2 (2015 vintage) probes Wayland and aborts
    # SDL_Init when the host wayland-client ABI doesn't match; force
    # the X11 backend via Xwayland.
    SDL_VIDEODRIVER = "x11";
    # SDL2 / libGL / libpulse dlopen further backends at runtime.
    # Provide 32-bit copies of everything the game touches.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgsi686Linux;
      [
        libGL
        libGLU
        libglvnd
        openal
        libpulseaudio
        alsa-lib
        libxkbcommon
        SDL2
        libx11
        libxext
        libxrandr
        libxi
        libxcursor
        libxinerama
        libxcb
        libxfixes
        systemdLibs
      ]
    );
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Grim Fandango Remastered (Double Fine 2015 remaster of 1998 LucasArts adventure, GOG native Linux v1.4)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "grim-fandango-remastered";
  };
}
