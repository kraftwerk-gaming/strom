{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  autoPatchelfHook,
  stdenv,
}:

let
  # Luftrausers 2014 IndieBox (USA) physical release. The 7z holds a
  # 1 GiB FAT16 disc image with the bundled Windows / Mac / *Linux*
  # ports. We pull only the Linux/x86-64/ subtree and drop the i686
  # build, the MS-Windows tree, the DRM-free OS X bundle, and the
  # Ubuntu-specific apt-get install launch.sh.
  src = fetchIpfs {
    cid = "QmVk6ehxh5dK6wEMzH6CtLLwpK5KGRyJU8ftMetABbqPTw";
    fallbackUrl = "https://archive.org/download/Nova_LuftrausersIndieBox_USA/Luftrausers%20%28USA%29%20%28IndieBox%29.7z";
    hash = "sha256-Fr6F9Ym0nxVe15TRGjr0raurnZQwlXlwwGj5T9NDheQ=";
    name = "luftrausers-indiebox-usa.7z";
  };

  gameData = stdenv.mkDerivation {
    pname = "luftrausers-data";
    version = "2014-09-08";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      autoPatchelfHook
    ];

    # The luftrausers binary NEEDs SDL2 + freetype + GL + X11 + audio.
    # SFML, sndfile, libjsoncpp, FLAC, vorbis, openal, FreeType ship
    # bundled in x86-64/, but autoPatchelf still needs system runtimes
    # for the host-side libraries it depends on.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      libGL
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXrender
      xorg.libXau
      xorg.libXdmcp
      xorg.libxcb
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      # Two-step extract: 7z (LZMA) -> FAT16 image -> Linux subtree.
      7z x -bd "${src}" "Luftrausers (USA) (IndieBox).bin"
      7z x -bd "Luftrausers (USA) (IndieBox).bin" "Luftrausers/Linux/*"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r Luftrausers/Linux/. "$out"/
      chmod +x "$out/x86-64/luftrausers"
      # Drop the 32-bit build; we ship x86_64 only.
      rm -rf "$out/i686"
      # The launch.sh tries to gksudo / apt-get install dependencies on
      # Ubuntu — useless under Nix; we run the binary directly.
      rm -f "$out/launch.sh"
      # Wrap the binary so the bundled libSDL2/libsfml/etc. in x86-64/
      # are LD_LIBRARY_PATH-visible only to the game process, not to
      # gamescope (gamescope's libSDL2 must come from the system; the
      # 2014 bundled SDL is missing SDL_GetWindowSizeInPixels). Mirrors
      # the carrion / hotline-miami-2 pattern.
      cat > "$out/luftrausers" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      cd "$here/x86-64"
      exec env LD_LIBRARY_PATH="$here/x86-64" ./luftrausers "$@"
      EOF
      chmod +x "$out/luftrausers"
      runHook postInstall
    '';

    # Bundled libs (libSDL2, libsfml, libsndfile, libopenal, libFLAC,
    # libfreetype, libvorbis*, libogg, libjsoncpp, libz) live next to
    # the binary in x86-64/. Tell autoPatchelf to add $ORIGIN so the
    # bundled SDL2 finds bundled freetype etc., and the bundled libs
    # find each other.
    appendRunpaths = [ "$ORIGIN" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "luftrausers";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # The bundled libSDL2 from 2014 dlopens libudev/libpulse/libasound
  # and a couple of X helper libs by bare name. Use FHS env (custom
  # runtime) so those resolve via /usr/lib at runtime.
  runtime = "custom";
  executable = "luftrausers";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      udev
      libpulseaudio
      alsa-lib
      dbus
      xorg.libX11
      xorg.libXext
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXfixes
      xorg.libxcb
    ];

  env = {
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Luftrausers (2014 Vlambeer / Devolver, native Linux from IndieBox USA)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "luftrausers";
  };
}
