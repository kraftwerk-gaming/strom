{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  bzip2,
  autoPatchelfHook,
  stdenv,
}:

let
  # Bay 12 Games' free Classic Dwarf Fortress (v53.12, Linux native).
  # The 2022 Steam release is non-redistributable; the Classic build
  # at bay12games.com/dwarves/ is freely distributable. Tarball
  # contents extract at the root (no df_linux/ prefix): dwarfort
  # (ELF), libfmod.so.13, libg_src_lib.so, libsdl_mixer_plugin.so,
  # data/, run_df shell launcher.
  src = fetchIpfs {
    cid = "QmYcTstDWS5mMCf6GT9AsWDu3pw7d4sZZBmBVxYrjeocA9";
    fallbackUrl = "https://www.bay12games.com/dwarves/df_53_12_linux.tar.bz2";
    hash = "sha256-+YMhu+5hGpqyJBBOXINK2DzAIZ7jPKfqHdOkaJoDihs=";
    name = "df_53_12_linux.tar.bz2";
  };

  gameData = stdenv.mkDerivation {
    pname = "dwarf-fortress-data";
    version = "53.12";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      bzip2
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      SDL2
      SDL2_image
      SDL2_mixer
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xjf ${src} -C "$out"
      chmod +x "$out/dwarfort" "$out/run_df"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dwarf-fortress";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # Bundled libfmod.so.13 dlopens ALSA/PulseAudio by bare name and the
  # binary needs SDL2 from the system; FHS keeps the runtime predictable.
  runtime = "custom";
  executable = "dwarfort";

  targetPkgs =
    p: with p; [
      SDL2
      SDL2_image
      libGL
      libglvnd
      mesa
      alsa-lib
      libpulseaudio
      dbus
      udev
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
    ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Dwarf Fortress (Bay 12 Games free Classic v53.12, native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dwarf-fortress";
  };
}
