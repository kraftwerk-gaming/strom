{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  gnutar,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of Graveyard Keeper (v1.405 build 55214) bundled
  # with three DLC installers. The tar contains the base game mojosetup
  # .sh plus DLC/{better_save_soul,game_of_crone,stranger_sins}.sh.
  # mojosetup installers are shell-script header + zip archive; unzip
  # handles them directly. Base game ships as a Unity 2018 build under
  # data/noarch/game/, with the main binary named "Graveyard Keeper.x86_64"
  # (space in the filename); we rename it to graveyard-keeper.x86_64 in
  # the build script so the mkGame executable path is space-free.
  installer = fetchIpfs {
    cid = "QmWFSw81EZnicAZnt57Zpp6FT51Pjq1oyd1knChkXibWxb";
    fallbackUrl = "https://archive.org/download/graveyard-keeper-linux-gog-phoenix-games-lab/Graveyard_Keeper_%2B3_DLC_%28v1.405%29_%5BLinux%2C_GOG%2C_v55214%5D.tar";
    hash = "sha256-BW7d+nAbhcnE4rHDkouW4DGFWTyPKAVTHB5mhzSL0o4=";
    name = "graveyard-keeper-linux-gog-1.405.tar";
  };

  gameData = stdenv.mkDerivation {
    pname = "graveyard-keeper-data";
    version = "1.405";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      unzip
      autoPatchelfHook
    ];

    # Unity 2018 standalone player: the x86_64 ELF mostly NEEDs libc /
    # libstdc++ / libpthread, with the GL/X11/audio/wayland surface
    # dlopened by libUnityPlayer.so at runtime. autoPatchelf handles the
    # NEEDED entries; we add the dlopen targets via LD_LIBRARY_PATH below.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      tar -xf ${installer} graveyard_keeper_1_405_55214.sh
      unzip -q graveyard_keeper_1_405_55214.sh || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "data/noarch/game/." "$out/"
      # Strip the GOG installer shim + system-report helpers; we don't
      # ship the mojosetup uninstaller.
      rm -f "$out/start.sh" "$out/gameinfo" "$out/goggame-"*.info \
            "$out/goggame-"*.hashdb "$out/goggame-"*.script
      # Rename the space-containing binary + data dir so executable paths
      # don't need shell quoting.
      mv "$out/Graveyard Keeper.x86_64" "$out/graveyard-keeper.x86_64"
      mv "$out/Graveyard Keeper_Data" "$out/graveyard-keeper_Data"
      chmod +x "$out/graveyard-keeper.x86_64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "graveyard-keeper";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "graveyard-keeper.x86_64";

  # Skip Unity's standalone configuration dialog; gamescope sets the
  # nested output resolution and fullscreens the window.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # Unity 2018's libUnityPlayer.so dlopens GL/X11/wayland/audio/udev/
    # dbus by bare name; provide the full set on LD_LIBRARY_PATH.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        wayland
        libxkbcommon
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

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Graveyard Keeper +3 DLC (native Linux, GOG v1.405 build 55214)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "graveyard-keeper";
  };
}
