{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of World of Goo (the 2025 Tomorrow Corp re-release,
  # build 87464, v1.6.538). Mojosetup self-extracting installer:
  # shell-script header + zip archive containing a 64-bit ELF that uses
  # SDL2 / SDL2_mixer.
  installer = fetchIpfs {
    cid = "QmZcRK1T6GKK5x75G9L2w8JSEt5c9Ljcf8FXDyA4GcxoCc";
    fallbackUrl = "https://archive.org/download/world_of_goo_1_6_538_87464/world_of_goo_1_6_538_87464.sh";
    hash = "sha256-f4Bmrs/xyA0fImsN78GcGNpIOBAqkiTWVU5Rek+eU6Y=";
    name = "world-of-goo-linux-gog-1.6.538.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "world-of-goo-data";
    version = "1.6.538";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      SDL2
      SDL2_mixer
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/WorldOfGoo.bin.x86_64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "world-of-goo";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "WorldOfGoo.bin.x86_64";

  env = {
    # SDL2 dlopens the X/Wayland/audio/GL backends by bare name; provide
    # them on LD_LIBRARY_PATH for autoPatchelf-fixed-up SDL2 to find.
    # The bundled libSDL2 hard-requires libudev (SDL_Init returns
    # "Could not initialize UDEV" if it can't dlopen libudev.so.1) — see
    # gdb on SDL_Init's return-error path.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libxkbcommon
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        udev
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  preRun = ''
    # The game writes save data to $HOME/.WorldOfGoo/ (hardcoded — see the
    # SDL2PersistenceLayer::homeDir symbol in the binary; XDG_DATA_HOME is
    # ignored). $HOME is a tmpfs in our bwrap so it vanishes between runs.
    # Symlink the path at $STROM_GAMEDIR so saves persist.
    mkdir -p "$STROM_GAMEDIR/userdata"
    ln -sfn "$STROM_GAMEDIR/userdata" "$HOME/.WorldOfGoo"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "World of Goo (native Linux, GOG v1.6.538 build 87464)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "world-of-goo";
  };
}
