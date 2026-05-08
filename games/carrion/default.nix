{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  xz,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of CARRION (v1.0.5). The .tar.xz is the
  # already-extracted mojosetup payload (.mojosetup, game/, support/,
  # start.sh) — no installer to run, just untar. Carrion itself is a
  # single-file .NET Core 3.1 self-contained publish that embeds the
  # runtime + app DLLs inside the apphost ELF, so we only need to
  # patchelf the apphost and the bundled FMOD/SDL libs.
  installer = fetchIpfs {
    cid = "QmeYaTv2cbe37S7jFtg7x12WpwToWLEQZiujfi7zhn5Ftq";
    fallbackUrl = "https://archive.org/download/carrion-linux-gog-phoenix-games-lab/game-CARRION_(v1.0.5)_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_Libs%5D.tar.xz";
    hash = "sha256-KSUmJPGf/3aPE+K1aRZKKcia5b/24UTBBY/Y6qOvWjk=";
    name = "carrion-linux-gog-1.0.5.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "carrion-data";
    version = "1.0.5";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      alsa-lib
      libpulseaudio
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libXext
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xf ${installer} -C "$out" game
      mv "$out/game"/* "$out"/
      rmdir "$out/game"
      chmod +x "$out/Carrion"
      # FMOD libs are versioned (libfmod.so.10.9) but reference each
      # other via libfmod.so.10 / libfmodstudio.so.10. Add the missing
      # SONAME-style aliases so autoPatchelf finds them.
      ln -sf libfmod.so.10.9 "$out/libfmod.so.10"
      ln -sf libfmodstudio.so.10.9 "$out/libfmodstudio.so.10"
      ln -sf libfsbank.so.10.9 "$out/libfsbank.so.10"
      # Carrion dlopens libSDL2 / libfmod / libssl by bare name at
      # runtime; they live next to the binary (and lib64/ for libssl).
      # We can't put $GAMEDIR on a global LD_LIBRARY_PATH because that
      # leaks into gamescope and the bundled 2018-vintage libSDL2 is
      # missing SDL_GetWindowSizeInPixels (gamescope 3.16+ needs it).
      # Instead, replace the binary with a tiny launcher that scopes
      # LD_LIBRARY_PATH to the game process only.
      mv "$out/Carrion" "$out/Carrion-bin"
      cat > "$out/Carrion" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      exec env LD_LIBRARY_PATH="$here:$here/lib64" "$here/Carrion-bin" "$@"
      EOF
      chmod +x "$out/Carrion"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "carrion";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # Bundled libSDL2-2.0.so.0 dlopens libudev/libGL/libwayland/etc by bare
  # name. Use FHS env (custom runtime) so those are visible via /usr/lib.
  runtime = "custom";
  executable = "Carrion";

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
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "CARRION (native Linux, GOG v1.0.5)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "carrion";
  };
}
