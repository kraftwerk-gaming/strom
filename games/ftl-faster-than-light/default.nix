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
  # GOG Linux release of FTL: Advanced Edition (mojosetup .sh, shell-script
  # header + zip archive). Native x86_64 ELF; data/ftl.dat holds the assets.
  installer = fetchIpfs {
    cid = "QmXvTneLsSXRe7GUdYVirXBuxz9JehaoSM8d52bxbB4VMg";
    fallbackUrl = "https://archive.org/download/ftl-advanced-edition-linux-gog-phoenix-games-lab/ftl_advanced_edition_1_6_12_2_35269.sh";
    hash = "sha256-qsi9y79HuCP3eInie+d9Ut/eBBxJd+w3UXaipSBj4Mk=";
    name = "ftl-advanced-edition-1.6.12.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "ftl-faster-than-light-data";
    version = "1.6.12.2";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      libGL
      xorg.libX11
      alsa-lib
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/FTL" "$out/data/FTL" "$out/data/FTL.amd64"
      # Drop the 32-bit binary; we ship x86_64 only.
      rm -f "$out/data/FTL.x86"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "ftl-faster-than-light";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  # The bundled FTL launcher does `cd data && exec ./FTL`, which the
  # binary needs in order to find ftl.dat in its working directory.
  executable = "FTL";

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libxkbcommon
        libpulseaudio
        alsa-lib
        xorg.libX11
        xorg.libXext
        xorg.libXrandr
        xorg.libXcursor
        xorg.libXi
        xorg.libXfixes
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
    description = "FTL: Faster Than Light Advanced Edition (native Linux, GOG v1.6.12)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ftl-faster-than-light";
  };
}
