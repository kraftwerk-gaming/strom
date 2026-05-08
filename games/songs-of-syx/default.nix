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
  # GOG Linux release of Songs of Syx (v0.70.32 build 88113). The .sh is
  # a mojosetup self-extracting installer (shell-script header followed
  # by a zip), so unzip handles it directly. The "songsofsyx" ELF is a
  # tiny launcher that dlopens the bundled JRE's libjvm.so and invokes
  # SongsOfSyx.jar (mainClass init.MainLaunchLauncher).
  installer = fetchIpfs {
    cid = "QmaxzX2CGVuKvx8YeXyVXLrECE62jid5xCKphNKDJYVrK9";
    fallbackUrl = "https://archive.org/download/songs-of-syx-linux-gog-phoenix-games-lab/songs_of_syx_0_70_32_88113.sh";
    hash = "sha256-XNpPLAf/T5bDMv1sT6yej5HLSSYzFOYaYH2hijH2hHQ=";
    name = "songs-of-syx-linux-gog-0.70.32.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "songs-of-syx-data";
    version = "0.70.32";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      alsa-lib
      freetype
      fontconfig
      harfbuzz
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXtst
      xorg.libXrandr
      xorg.libXcursor
      xorg.libxcb
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      # mojosetup .sh is a shell-script header + zip; unzip handles it.
      unzip -q ${installer} 'data/noarch/game/*' || true
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/songsofsyx" "$out/jre/bin/"*
      # The shipped songsofsyx ELF is a tiny libjvm dlopener that runs
      # init.MainLaunchLauncher → init.Main → forks launcher GUI → forks
      # init.MainProcess via ProcessBuilder. The grandchild game JVM is
      # left as an orphan when init.Main returns, so mk-game.nix's
      # process-group cleanup kills it. Bypass the entire fork chain by
      # invoking the bundled JRE directly on init.MainProcess with the
      # classpath the launcher would have built (SongsOfSyx.jar plus
      # base/script/*.jar — the tutorial jars contain
      # jake.util.GoalManager$MessEnd which ScriptLoad reflects on by
      # name). Single JVM, no orphans, no cleanup foot-gun. The launcher
      # GUI is skipped entirely; persisted LauncherSettings.txt is still
      # consulted via launcher.LSettings inside MainProcess.
      mv "$out/songsofsyx" "$out/songsofsyx-bin-unused"
      cat > "$out/songsofsyx" <<'EOF'
      #!/bin/sh
      set -eu
      here="$(dirname "$0")"
      cd "$here"
      cp="SongsOfSyx.jar"
      for jar in base/script/*.jar; do
        [ -f "$jar" ] && cp="$cp:$jar"
      done
      # Append any user-installed mod jars from the persistence dir.
      if [ -n "''${STROM_GAMEDIR:-}" ] && [ -d "$STROM_GAMEDIR/userdata/mods" ]; then
        for jar in "$STROM_GAMEDIR/userdata/mods"/*/script/*.jar; do
          [ -f "$jar" ] && cp="$cp:$jar"
        done
      fi
      exec "$here/jre/bin/java" \
        -Xms512m -Xmx4096m \
        -XX:+UseCompressedOops \
        -Dfile.encoding=UTF-8 \
        -server \
        -Dfml.earlyprogresswindow=false \
        -XX:+UseSerialGC \
        -cp "$cp" \
        init.MainProcess "$@"
      EOF
      chmod +x "$out/songsofsyx"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "songs-of-syx";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # Bundled JRE is OpenJDK 17. The launcher dlopens libjvm.so by relative
  # path and the JRE itself dlopens libfreetype, libfontmanager helpers,
  # etc. by bare name. Use FHS env so /usr/lib has the system libs.
  runtime = "custom";
  executable = "songsofsyx";

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
      xorg.libxcb
      zlib
      udev
    ];

  preRun = ''
    export LD_LIBRARY_PATH="$GAMEDIR/jre/lib:$GAMEDIR/jre/lib/server:''${LD_LIBRARY_PATH:-}"
    # The launcher writes LauncherSettings.txt to a hardcoded
    # $HOME/.local/share/songsofsyx/ path (XDG_DATA_HOME is ignored).
    # $HOME is a tmpfs in our bwrap so it vanishes between launches,
    # and init.Main throws DataError when the file isn't there. Symlink
    # the path at $STROM_GAMEDIR so settings persist across runs.
    #
    # Important: the persistent dir name must NOT collide with the
    # "songsofsyx" launcher script in the lower layer — fuse-overlayfs
    # would let the upperdir directory shadow the lowerdir file, so on
    # the second run gamescope tries to exec a directory and bombs out
    # with EACCES ("Permission denied").
    mkdir -p "$STROM_GAMEDIR/userdata" "$HOME/.local/share"
    ln -sfn "$STROM_GAMEDIR/userdata" "$HOME/.local/share/songsofsyx"

  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Songs of Syx (native Linux, GOG v0.70.32 build 88113)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "songs-of-syx";
  };
}
