{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
  libGL,
  libx11,
  libpulseaudio,
  alsa-lib,
}:

let
  # Baba Is You Linux build (Chowdren runtime), version 221215.
  archive = fetchIpfs {
    cid = "QmdZ1QpiFWpYEpYQisNaLVdyRidj9jQ6f7UwqeE4X8FokF";
    fallbackUrl = "https://archive.org/download/biy-linux-221215.tar/BIY_linux_221215.tar.gz";
    hash = "sha256-WlbQ5164hS3sAWR8A+CjziAYFOT8KVtZF+zn7x1bNAs=";
    name = "baba-is-you-linux.tar.gz";
  };

  gameData = pkgs.stdenv.mkDerivation {
    pname = "baba-is-you-data";
    version = "221215";

    src = archive;

    nativeBuildInputs = [
      autoPatchelfHook
      stdenv.cc.cc.lib
    ];

    buildInputs = [ libGL ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"/
      chmod +x "$out/bin64/Chowdren" "$out/bin32/Chowdren" "$out/run.sh"
      autoPatchelf "$out/bin64/Chowdren" "$out/bin32/Chowdren"
      runHook postInstall
    '';
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "baba-is-you";

  ipfsSources = [ archive ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "bin64/Chowdren";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags."--expose-wayland" = true;
  };

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      libGL
      libx11
      libpulseaudio
      alsa-lib
    ];
  };

  meta = {
    description = "Baba Is You (native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "baba-is-you";
  };
}
