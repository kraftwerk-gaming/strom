{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  patchelf,
  stdenv,
}:

let
  # GOG Linux build with bundled 32-bit Cg libs (libCg.so, libCgGL.so).
  src = fetchIpfs {
    cid = "QmYThFTzNnuUx7o7ywWqWDSw6tqeKzY27MQUnFhckqv7Zs";
    fallbackUrl = "https://archive.org/download/game-hotline_miami_linux_gog_built-in-libs.7z/game-Hotline_Miami_%5BLinux%2C_GOG%2C_Built-In-Libs%5D.7z";
    hash = "sha256-dJVMz8qPPMrJ9KM8wp40L1EReU1jZRmGmuBY03sTnYA=";
    name = "hotline-miami-linux-gog-built-in-libs.7z";
  };

  i686 = pkgs.pkgsi686Linux;

  gameData = stdenv.mkDerivation {
    pname = "hotline-miami-data";
    version = "2.0.0.4";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      patchelf
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib"
      # Extract full archive into staging dir, then pick what we need.
      # game/ holds the executable + WAD + music; lib32/ holds libCg.so, libCgGL.so
      7z x -o"$TMPDIR/extract" ${src}
      cp -r "$TMPDIR/extract/game/"* "$out/"
      cp "$TMPDIR/extract/lib32/"*.so "$out/lib/"
      chmod +x "$out/Hotline"
      # Patch to 32-bit NixOS interpreter; $ORIGIN/lib rpath is left intact
      # so the bundled Cg libs in lib/ are found at runtime.
      patchelf --set-interpreter "${i686.glibc}/lib/ld-linux.so.2" "$out/Hotline"
      runHook postInstall
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hotline-miami";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Hotline";

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with i686;
      [
        libGL
        libGLU
        libX11
        libvorbis
        libogg
        openal
        gcc-unwrapped.lib
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
    description = "Hotline Miami (native Linux, GOG v2.0.0.4)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hotline-miami";
  };
}
