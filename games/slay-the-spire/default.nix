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
  # GOG Linux release of Slay the Spire (v2020-12-15). The .tar.xz is
  # the already-extracted mojosetup payload (.mojosetup, game/, support/,
  # start.sh) — no installer to run, just untar. SlayTheSpire is a
  # tiny native launcher that dlopens the bundled JRE 1.8 libjvm.so and
  # invokes desktop-1.0.jar (mainClass DesktopLauncher).
  installer = fetchIpfs {
    cid = "Qmb1jof4oMBy4KkAQq6wXLG1JDGagZjwpTQCusJUZGLcHJ";
    fallbackUrl = "https://archive.org/download/slay-the-spire-linux-gog-phoenix-games-lab/game-Slay_the_Spire_(v2020-12-15)_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_start%5D.tar.xz";
    hash = "sha256-vIRs+vVsbEpyslRhKsR703LyoDZI1jGpdLfy0hkmSdg=";
    name = "slay-the-spire-linux-gog-2020-12-15.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "slay-the-spire-data";
    version = "2020-12-15";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      glib
      gtk2
      pango
      cairo
      atk
      gdk-pixbuf
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXtst
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXxf86vm
      xorg.libxcb
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xf ${installer} -C "$out" game
      mv "$out/game"/* "$out"/
      rmdir "$out/game"
      chmod +x "$out/SlayTheSpire" "$out/jre/bin/"*
      # Wrap the launcher so the bundled JRE in jre/lib/amd64 is
      # LD_LIBRARY_PATH-visible only to the game process, not to
      # gamescope. Mirrors the carrion / hotline-miami-2 pattern.
      mv "$out/SlayTheSpire" "$out/SlayTheSpire-bin"
      cat > "$out/SlayTheSpire" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      exec env LD_LIBRARY_PATH="$here/jre/lib/amd64:$here/jre/lib/amd64/server" \
        "$here/SlayTheSpire-bin" "$@"
      EOF
      chmod +x "$out/SlayTheSpire"
      # Bump default resolution from 1280x720 to 1920x1080 in
      # info.displayconfig (two blocks of 6 lines: windowed then
      # fullscreen, each is width/height/refresh/fullscreen/borderless/
      # vsync). The user can change it in-game; settings are saved per
      # user, not back to this file.
      cat > "$out/info.displayconfig" <<'EOF'
      1920
      1080
      60
      false
      false
      true
      1920
      1080
      60
      false
      false
      true
      EOF
      runHook postInstall
    '';

    # The bundled JRE 1.8 ships JavaFX with libavplugin-* that pulls in
    # ancient ffmpeg sonames (libavcodec.so.53..56, libavformat.so.53..56)
    # plus libavplugin-ffmpeg-56 / libxml2.so.2 / libxslt.so.1 in
    # libjfxwebkit. The game itself uses LWJGL, not JavaFX, so these
    # plugins are never loaded; let auto-patchelf leave their unresolved
    # deps alone instead of failing the build.
    autoPatchelfIgnoreMissingDeps = [
      "libavcodec.so.53"
      "libavcodec.so.54"
      "libavcodec.so.55"
      "libavcodec.so.56"
      "libavcodec-ffmpeg.so.56"
      "libavformat.so.53"
      "libavformat.so.54"
      "libavformat.so.55"
      "libavformat.so.56"
      "libavformat-ffmpeg.so.56"
      "libxml2.so.2"
      "libxslt.so.1"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "slay-the-spire";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # Bundled JRE 1.8 dlopens libfreetype/libfontmanager/etc. by bare name
  # via /usr/lib paths, and LWJGL (used by libGDX) dlopens libGL/libX11.
  # Use FHS env so the JRE finds them.
  runtime = "custom";
  executable = "SlayTheSpire";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXtst
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXxf86vm
      xorg.libxcb
      xorg.xrandr
      zlib
      udev
    ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Slay the Spire (native Linux, GOG v2020-12-15)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "slay-the-spire";
  };
}
