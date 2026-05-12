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
  # GOG Linux release of Shovel Knight: Treasure Trove v4.1B (Arby's build
  # 46298). Phoenix Games Lab mojosetup .sh = shell-script header + zip,
  # unzip handles it directly. The game is a custom C++ engine (not Unity):
  # the 64-bit ELF at data/noarch/game/64/ShovelKnight has RPATH $ORIGIN/lib
  # and bundles libBox2D, libSDL2, libGLEW, libfmodex64, libfmodevent64.
  # libGL.so.1, libstdc++ and libc come from the system.
  installer = fetchIpfs {
    cid = "QmbeTW7wah4vhqL6pQdJfAgwKMh1uyzmWxbDLGwnJSy41n";
    fallbackUrl = "https://archive.org/download/shovel-knight-treasure-trove-linux-gog-phoenix-games-lab/shovel_knight_treasure_trove_4_1b_arby_s_46298.sh";
    hash = "sha256-wUvGamTa7MWuDPhfhfpdc91zca1wp/scyFDATZ3PiAo=";
    name = "shovel-knight-treasure-trove-4.1b.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "shovel-knight-treasure-trove-data";
    version = "4.1b";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # The 64-bit ELF NEEDs libpthread/libc/libm/libstdc++/libGL plus its
    # bundled libs (resolved via $ORIGIN/lib RPATH). autoPatchelf fixes
    # the interpreter and NEEDED entries; dlopen targets from SDL2 land
    # via LD_LIBRARY_PATH below.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
    ];

    buildPhase = ''
      runHook preBuild
      # mojosetup .sh is a shell header followed by a zip archive; unzip
      # finds the zip automatically. It warns about the prefix bytes and
      # exits 1, but extraction succeeds.
      unzip -q ${installer} "data/noarch/game/*" || [ $? -eq 1 ]
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      # Drop the 32-bit tree, GOG installer metadata, and shipped launcher
      # (we provide our own below).
      rm -rf "$out/32"
      rm -f "$out/shovelknight" "$out/softwarelicense.txt" \
            "$out/goggame-"*.info "$out/goggame-"*.hashdb \
            "$out/goggame-"*.script
      chmod +x "$out/64/ShovelKnight"

      # ShovelKnight's bundled libs sit in 64/lib and the binary's RPATH
      # is $ORIGIN/lib, so it must run with cwd = 64/. The shipped
      # launcher does this via readlink/dirname; provide an equivalent
      # top-level entry point so mkGame's executable path stays simple.
      cat > "$out/shovel-knight-treasure-trove" <<'EOF'
      #!/bin/sh
      here="$(dirname "$(readlink -f "$0")")"
      cd "$here/64"
      exec "./ShovelKnight" "$@"
      EOF
      chmod +x "$out/shovel-knight-treasure-trove"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shovel-knight-treasure-trove";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "shovel-knight-treasure-trove";

  env = {
    # SDL2 dlopens GL/X11/wayland/audio/udev/dbus by bare name. Mirror
    # graveyard-keeper's set so the game finds everything regardless of
    # which video/audio driver SDL picks at startup.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        wayland
        libxkbcommon
        udev
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
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
    description = "Shovel Knight: Treasure Trove (native Linux, GOG v4.1B Arby's build 46298)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shovel-knight-treasure-trove";
  };
}
