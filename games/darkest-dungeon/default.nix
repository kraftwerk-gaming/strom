{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  unzip,
  stdenv,
}:

let
  # GOG Linux release of Darkest Dungeon (game v24788 / GOG build 82473).
  # The archive is a tar containing a Bonus/ directory (avatars +
  # soundtrack + wallpapers), a DLC/ directory (four DLC installers) and
  # the main mojosetup base installer .sh. mojosetup .sh files are a
  # shell-script header + zip archive, so unzip handles them directly
  # (it warns about the leading script bytes but extracts fine). We
  # extract only the base game.
  installer = fetchIpfs {
    cid = "QmSMioNkvVNH2UZSys9UwmZvJhhhF8np18g73jDhNtBfGi";
    fallbackUrl = "https://archive.org/download/darkest-dungeon-linux-gog-phoenix-games-lab/Darkest_Dungeon_%2B4_DLC-Bonus_%28v24788%29_%5BLinux%2C_GOG%2C_v82473%5D.tar";
    hash = "sha256-11CW+E41u1oXWrc3gptg90E1NewThJMbmXA3yBpbzSw=";
    name = "darkest-dungeon-linux-gog-v82473.tar";
  };

  gameData = stdenv.mkDerivation {
    pname = "darkest-dungeon-data";
    version = "82473";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      unzip
    ];

    # No autoPatchelfHook: darkest.bin.x86_64 keeps its $ORIGIN/lib64
    # rpath (bundled libSDL2/libfmod/libfmodstudio) and the standard
    # /lib64/ld-linux interpreter, both satisfied by the "custom" FHS
    # env at runtime. Patchelf would rewrite the rpath and break the
    # self-referential bundled-lib lookup.
    buildPhase = ''
      runHook preBuild
      tar -xf ${installer} darkest_dungeon_24788_82473.sh
      unzip -q darkest_dungeon_24788_82473.sh "data/noarch/game/*" || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/darkest.bin.x86_64"
      # Drop the 32-bit binary + its libs; we ship x86_64 only.
      rm -f "$out/darkest.bin.x86"
      rm -rf "$out/lib"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "darkest-dungeon";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # The binary's bundled libSDL2 (lib64/, found via $ORIGIN/lib64 rpath)
  # dlopens libGL/libX11/libudev/audio/etc. by bare soname, so we need
  # an FHS env (which the "native" runtime doesn't provide). Use
  # "custom" so we get the FHS at /usr with targetPkgs.
  runtime = "custom";
  executable = "darkest.bin.x86_64";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      udev
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      mesa
      vulkan-loader
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libXinerama
      xorg.libxcb
      wayland
    ];

  env = {
    # Force X11 so SDL goes through gamescope's Xwayland rather than a
    # bundled SDL2's Wayland GL path against modern Mesa.
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Darkest Dungeon (native Linux, GOG v24788 build 82473)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "darkest-dungeon";
  };
}
