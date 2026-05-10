{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
  unar,
  stdenv,
}:

let
  # GOG Windows release of Psychonauts. The archive.org item ships the
  # multi-part installer as a single zip: the .exe stub + two RAR-packed
  # .bin slices. innoextract --gog handles them when unar is on PATH.
  src = fetchIpfs {
    cid = "QmUFsFYE2ywPcRZgdjt8XU4NypzP34bsU3mgnWY62HrLn7";
    fallbackUrl = "https://archive.org/download/psychonauts_202602/Psychonauts.zip";
    hash = "sha256-GvppUhQHq6XmBmtwgKRfWE85swX6eKsLdyW12VXOFOE=";
    name = "psychonauts-gog.zip";
  };

  gameData = stdenv.mkDerivation {
    pname = "psychonauts-data";
    version = "2.2.0.13";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      innoextract
      unar
    ];

    buildPhase = ''
      runHook preBuild
      mkdir -p installer
      unzip -q ${src} -d installer
      cd installer/Psychonauts
      innoextract --gog -d "$TMPDIR/iss" setup_psychonauts_2.2.0.13.exe
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "$TMPDIR/iss/game"/. "$out"/
      runHook postInstall
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "psychonauts";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "Psychonauts.exe";

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

  env = {
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Psychonauts (GOG Windows, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "psychonauts";
  };
}
