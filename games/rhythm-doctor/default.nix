{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
}:

let
  # Phoenix Games Lab "LinuxRuleZ!" repack of the full Rhythm Doctor
  # v1.0.0 native Linux build (7th Beat Games, Unity 2021). The .sh is a
  # YAD Simple Installer: a shell-script preamble followed by an
  # xz-compressed tar payload of `arcsz` bytes at the tail (the header
  # records appsz/arcsz on lines ~93-96). The xz unpacks to:
  #   Rhythm Doctor/game/Rhythm Doctor        (Unity 2021 Linux player)
  #   Rhythm Doctor/game/UnityPlayer.so
  #   Rhythm Doctor/game/Rhythm Doctor_Data/
  installer = fetchIpfs {
    cid = "QmUaVWWi5qFG2HkkWMD8vQA7TZyFwYwW28PVZGLqCtX6zV";
    fallbackUrl = "https://archive.org/download/rhythm-doctor-linux-linuxrulez-phoenix-games-lab/Rhythm%20Doctor%20%282025%29%20%28v.1.0.0%29%20%5BMULTi10%5D%20%5BUnity3D%5D%20%5BLinuxRuleZ%21%5D.sh";
    hash = "sha256-4JBRFdH7yFcAtNqxxuicHzj3sMcsJJOTW9Mm7Kzdyd8=";
    name = "rhythm-doctor-linux.sh";
  };

  arcsz = 386554080;

  gameData = stdenv.mkDerivation {
    pname = "rhythm-doctor-data";
    version = "1.0.0";

    dontUnpack = true;

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      alsa-lib
      libpulseaudio
      xorg.libX11
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXext
      xorg.libXinerama
    ];

    # Strip the YAD shell header off the front and decompress the xz
    # payload directly into the build dir, keeping only the `game/`
    # subtree (the launcher/uninstaller assume a system YAD install).
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tail -c ${toString arcsz} ${installer} | xzcat | tar -xf - --strip-components=2 "Rhythm Doctor/game"
      cp -r ./* "$out"/
      chmod +x "$out/Rhythm Doctor"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rhythm-doctor";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "custom";
  executable = "Rhythm Doctor";
  # Unity logs to ~/.config/unity3d/.../Player.log by default, which the
  # custom-runtime HOME->$STROM_GAMEDIR bind would persist; force logs to
  # stdout so startup errors surface in the launcher output.
  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity 2021 Linux player + bundled UnityPlayer.so reach for the
  # standard X11/GL/audio stack by bare soname.
  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      alsa-lib
      libpulseaudio
      udev
      dbus
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXi
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXinerama
      xorg.libxcb
      zlib
    ];

  env = {
    # Force X11 so UnityPlayer.so targets gamescope's Xwayland instead of
    # autodetecting Wayland and crashing.
    SDL_VIDEODRIVER = "x11";
  };

  # Unity persistentDataPath on Linux is
  # ~/.config/unity3d/<company>/<product> (UnityPlayer.so builds it from
  # XDG_CONFIG_HOME); Rhythm Doctor's saves live there.
  saveLocations = [ ".config/unity3d/7th Beat Games/Rhythm Doctor" ];

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
    description = "Rhythm Doctor (7th Beat Games 2021, native Linux v1.0.0, LinuxRuleZ! repack)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rhythm-doctor";
  };
}
