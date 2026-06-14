{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  autoPatchelfHook,
  stdenv,
}:

let
  # Cult of the Lamb (Massive Monster / Devolver Digital, 2022) — native
  # Linux build, v1.2.7.29, Unity 2019.4.40f1. Distributed as a "YAD
  # Simple Installer" (.run) self-extractor: a YAD/shell header with a
  # bundled unrar binary and the real payload appended as a RAR5 archive
  # at the tail of the file. The header records the archive size as
  # `arcsz=806250212`, so the payload is simply the last 806250212 bytes
  # of the .run — we slice it off with `tail -c` and unpack the RAR5 with
  # `unar` (the unfree `unrar` is avoided). Standard Unity layout under
  # "Cult of the Lamb/": Cult.x86_64 (a 6KB Unity loader stub) +
  # Cult_Data/ + UnityPlayer.so. The build ships a pre-configured
  # gbe_fork/Goldberg Steam emulator (Cult_Data/Plugins/libsteam_api.so +
  # Cult_Data/Plugins/steam_settings/), so it runs fully offline without a
  # steam_api swap.
  installer = fetchIpfs {
    cid = "QmU2q6xopnGA8iVxtrAZFLXwjig7UkiYjxF9RVycquodBP";
    fallbackUrl = "magnet:?xt=urn:btih:6C2C5753A5DA26111C95E6482728BD46918E0E74";
    hash = "sha256-HofnHhjKZNuRUSzYMpxvWfc0+ap42MAvIhA4VspwFEY=";
    name = "cult-of-the-lamb-linux-1.2.7.29.run";
  };

  # Byte offset of the embedded RAR5 archive at the tail of the .run,
  # read straight from the YSI header's `arcsz` value.
  arcsz = 806250212;

  gameData = stdenv.mkDerivation {
    pname = "cult-of-the-lamb-data";
    version = "1.2.7.29";

    dontUnpack = true;

    nativeBuildInputs = [
      unar
      autoPatchelfHook
    ];

    # The Cult.x86_64 loader stub and the bundled .so objects NEED only
    # libc/libstdc++/libgcc; the GL/X11/audio/wayland/vulkan surface is
    # dlopened by UnityPlayer.so at runtime (provided on LD_LIBRARY_PATH
    # below). UnityPlayer.so / libMonoPosixHelper.so carry NEEDED entries
    # for zlib/glib-style libs, so add those for autoPatchelf to resolve.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      tail -c ${toString arcsz} ${installer} > payload.rar
      unar -force-overwrite -output-directory game payload.rar
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "game/Cult of the Lamb/." "$out"/
      chmod +x "$out/Cult.x86_64"
      # Drop the YSI launcher/uninstaller shims; the strom wrapper execs
      # the binary directly.
      rm -f "$out/run.sh" "$out/uninstall.sh"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cult-of-the-lamb";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "Cult.x86_64";

  # Skip Unity's standalone "select your monitor" configuration dialog;
  # gamescope already sets the nested output resolution and fullscreens
  # the window.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # UnityPlayer.so dlopens GL/X11/wayland/audio/udev/dbus/vulkan by bare
    # name; provide the full set on LD_LIBRARY_PATH.
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

  # Unity writes config + saves under
  # $HOME/.config/unity3d/<company>/<product>; this build's
  # globalgamemanagers carries company "Massive Monster" / product
  # "Cult Of The Lamb". runtime = "native" binds $HOME to $STROM_GAMEDIR
  # (~/.strom/cult-of-the-lamb), so this persists across overlay rebuilds.
  saveLocations = [ ".config/unity3d/Massive Monster/Cult Of The Lamb" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Cult of the Lamb (Massive Monster / Devolver Digital 2022, Unity roguelike, native Linux v1.2.7.29)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cult-of-the-lamb";
  };
}
