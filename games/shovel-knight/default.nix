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
  # GOG Linux release of Shovel Knight: Treasure Trove (v4.1b).
  # Standard mojosetup .sh = Makeself shell preamble + zip payload, so
  # `unzip` happily reads it directly. Layout: data/noarch/game/{32,64}/
  # ShovelKnight (ELF) + bundled libSDL2, data/noarch/game/data/*.pak
  # assets, and a `shovelknight` shell launcher that picks the right
  # arch. We only ship the 64-bit binary tree; the 32-bit dir is
  # duplicated assets we don't need.
  installer = fetchIpfs {
    cid = "QmbeTW7wah4vhqL6pQdJfAgwKMh1uyzmWxbDLGwnJSy41n";
    fallbackUrl = "";
    hash = "sha256-wUvGamTa7MWuDPhfhfpdc91zca1wp/scyFDATZ3PiAo=";
    name = "shovel-knight-treasure-trove-4.1b.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "shovel-knight-data";
    version = "4.1b";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      libpulseaudio
      alsa-lib
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libxcb
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/64 "$out"/64
      cp -r data/noarch/game/data "$out"/data
      chmod +x "$out/64/ShovelKnight"
      runHook postInstall
    '';

    appendRunpaths = [ "$ORIGIN/lib" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shovel-knight";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "custom";
  executable = "64/ShovelKnight";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      libpulseaudio
      alsa-lib
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libxcb
    ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Shovel Knight: Treasure Trove (Yacht Club Games, native Linux GOG v4.1b)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shovel-knight";
  };
}
