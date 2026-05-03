{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
  libGL,
  libpulseaudio,
  alsa-lib,
  libxkbcommon,
  libx11,
  libxext,
  libxcursor,
  libxrandr,
  libxi,
  wayland,
}:

let
  installer = fetchIpfs {
    cid = "QmWyxQuzz5JxCGEkdFiDyvi2EcreFHXvGNnLwRXVbrfT1c";
    fallbackUrl = "https://archive.org/download/papers-please-linux-gog/papers_please_1_4_11_124_63295.sh";
    hash = "sha256-Zocv2fqzXWOmpECKnv4DtgujaH7QID/domqsNnVnWgM=";
    name = "papers-please-gog.sh";
  };

  gameData = pkgs.stdenv.mkDerivation {
    pname = "papers-please-data";
    version = "1.4.11.124";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
      stdenv.cc.cc.lib
    ];

    buildInputs = [
      libGL
      libx11
      libxext
      libxcursor
      libxrandr
      libxi
      libpulseaudio
      alsa-lib
      libxkbcommon
      wayland
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
      chmod +x "$out/PapersPlease"
      autoPatchelf "$out"
      runHook postInstall
    '';
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "papers-please";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "PapersPlease";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      libGL
      libx11
      libxext
      libxcursor
      libxrandr
      libxi
      libpulseaudio
      alsa-lib
      libxkbcommon
      wayland
    ];
  };

  meta = {
    description = "Papers, Please (native Linux, GOG)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "papers-please";
  };
}
