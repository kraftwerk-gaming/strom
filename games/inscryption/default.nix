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
  # GOG Linux release of Inscryption (build 57447, v1.10). Mojosetup
  # self-extracting installer: shell-script header + zip archive.
  # Standard Unity 2019 layout (Inscryption.x86_64 + Inscryption_Data/
  # + UnityPlayer.so). The bundled libsteam_api.so handles only Steam
  # achievements; the GOG release does not gate gameplay on it.
  installer = fetchIpfs {
    cid = "QmeSwwu2sU9kjqb5Ua9YwV37jGjNjscNmTbTJZNMmef5bj";
    fallbackUrl = "https://archive.org/download/inscryption-linux-gog-phoenix-games-lab/inscryption_1_10_linux_57447.sh";
    hash = "sha256-ff75rwTcj6MI8nGuIh9vrZDnyQESxM4vyxhs7lLF9Ew=";
    name = "inscryption-linux-gog-1.10.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "inscryption-data";
    version = "1.10";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # Inscryption.x86_64 NEEDs only libc/libpthread/libm/libgcc; UnityPlayer.so
    # adds libstdc++ and dlopens GL/X11/audio/vulkan/wayland by bare name.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
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
      chmod +x "$out/Inscryption.x86_64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "inscryption";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Inscryption.x86_64";
  # Force fullscreen at gamescope's resolution; modern Unity does not
  # show a resolution dialog at launch but honours these flags too.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
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
        libxkbcommon
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

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Inscryption (native Linux, GOG v1.10 build 57447)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "inscryption";
  };
}
