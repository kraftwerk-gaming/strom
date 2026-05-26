{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # Anatomy (Kitty Horrorshow 2016): a short Unity 5.2 horror about a
  # house. The Kitty Horrorshow archive.org item ships a single 7z
  # bundling three platform-specific zips (Win/Mac/Linux).
  bundle = fetchIpfs {
    cid = "QmTZdKgZN2S1SqyYp9iiReNq7kDW8V21Q79uJbVVs8yb7h";
    fallbackUrl = "https://archive.org/download/anatomy-by-kitty-horrorshow/%5BWIN-MAC-LINUX%5D%20Anatomy%20by%20Kitty%20Horrorshow.7z";
    hash = "sha256-jZ/dyq+Eorgi2pMR/kpGHIyqCVtaEws+COKrErIyrBg=";
    name = "anatomy.7z";
  };

  # We previously ran the Windows build under Proton because the Linux
  # build was thought to SEGV on modern mesa. Three Proton rounds (DX11
  # hang at touch-support init, D3D9 missing-variant magenta, GLcore
  # hang at input init) all dead-ended around Unity 5.2's RawInput on
  # this host (4 gamepads, 2 BT). Switching to the native build: same
  # engine and shader bundle, but Linux Unity uses SDL for input and
  # OpenGL for rendering, neither of which has the wine touchpoint.
  gameData = stdenv.mkDerivation {
    pname = "anatomy-data";
    version = "1.0";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      unzip
      autoPatchelfHook
    ];

    # Anatomy.x86_64 has NEEDED entries for libGL/libX11/libXcursor/
    # libXrandr/libstdc++ (unlike broforce, which loads them via dlopen
    # only). ScreenSelector.so has NEEDED gtk2 entries. Feed autoPatchelf
    # everything that's in NEEDED; the rest of the GL/audio/SDL stack
    # gets injected via LD_LIBRARY_PATH at runtime.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      gtk2
      gdk-pixbuf
      glib
      zlib
      xorg.libX11
      xorg.libXcursor
      xorg.libXrandr
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$TMPDIR/lin"
      7z x -so ${bundle} Anatomy_lin.zip > "$TMPDIR/lin.zip"
      unzip -q "$TMPDIR/lin.zip" -d "$TMPDIR/lin"
      mkdir -p "$out"
      cp -r "$TMPDIR/lin"/. "$out"/
      chmod +x "$out/Anatomy.x86_64"
      # Ship 64-bit only.
      rm -f "$out/Anatomy.x86"
      rm -rf "$out/Anatomy_Data/Mono/x86" "$out/Anatomy_Data/Plugins/x86"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anatomy";

  ipfsSources = [ bundle ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "Anatomy.x86_64";
  # Skip the Unity ScreenSelector popup; gamescope already owns the
  # output resolution.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # Unity 5 dlopens GL/X11/audio/SDL by bare soname; provide them via
    # LD_LIBRARY_PATH (same recipe as broforce).
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        udev
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  # Unity 5 PlayerPrefs / save data on Linux land in
  # ~/.config/unity3d/<company>/<product>/.
  saveLocations = [ ".config/unity3d/Kitty Horrorshow/ANATOMY" ];

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
    description = "Anatomy (Kitty Horrorshow 2016, native Linux build)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anatomy";
  };
}
