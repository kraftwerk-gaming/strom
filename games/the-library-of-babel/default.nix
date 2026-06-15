{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # The Library of Babel (Tanuki Game Studio / Neon Doctrine / Raw Fury, 2023).
  # 2D cinematic stealth puzzle-platformer, Windows-only (Unity, Mono backend),
  # so runtime = "proton".
  #
  # SOURCE: SteamRIP pre-installed repack (Steam app 1822030, build dated
  # 2023-04-07), distributed as The-Library-of-Babel-SteamRIP.com.rar (RAR5,
  # 1,045,725,867 bytes) via megadb. The repack ships a CODEX Steam emulator
  # (steam_api64.dll + steam_emu.ini) that runs fully offline, so no
  # gbe_fork/Goldberg swap is needed. RAR5 layout:
  #   The Library Of Babel/
  #     The Library of Babel.exe
  #     UnityPlayer.dll
  #     The Library of Babel_Data/
  #     MonoBleedingEdge/
  src = fetchIpfs {
    cid = "QmYFD1X1zfm8daN5yre6aQZAwHSVSCgXhoYANNmMvuA6rQ";
    fallbackUrl = "";
    hash = "sha256-xGZKbqtfhov2AChWiaBFa+3mRjRIrhBetQeUqWgdh4w=";
    name = "the-library-of-babel-steamrip.rar";
  };

  # GE-Proton's bundled libavcodec.so.58 is NEEDED-linked against the old
  # libvpx.so.6 (Steam-Linux-Runtime era), which nixpkgs no longer ships
  # (current soname is .so.12). libavcodec references zero vpx symbols at
  # the dynamic level (the VP8/VP9 codecs are reached only when actually
  # decoding such a stream), so the loader only needs the file to exist to
  # resolve NEEDED. This shim aliases the current libvpx as .so.6 so
  # libgstlibav can dlopen and the intro video's H.264 decode path works.
  libvpxSo6Compat = pkgs.runCommand "libvpx-so6-compat" { } ''
    mkdir -p "$out/lib"
    ln -s ${lib.getLib pkgs.libvpx}/lib/libvpx.so "$out/lib/libvpx.so.6"
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-library-of-babel";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    # unar names the top dir after the archive; the game tree lives in the
    # inner "The Library Of Babel/" folder (holding the .exe). Locate it by
    # the executable rather than a fixed path.
    gamedir="$(dirname "$(find "$TMPDIR/extract" -name 'The Library of Babel.exe' -print -quit)")"
    cp -r "$gamedir"/* "$out"/
    rm -f "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "The Library of Babel.exe";

  # Unity Application.persistentDataPath: AppData/LocalLow/<company>/<product>.
  # app.info from the build confirms company "Tanuki Game Studio", product
  # "The Library of Babel". The bundled CODEX emu additionally keeps its
  # emulated Steam-cloud/achievement state under Public Documents; that path
  # is outside the steamuser-rooted saveLocations migration, so it is
  # relocated manually in preRun below.
  saveLocations = [ "AppData/LocalLow/Tanuki Game Studio/The Library of Babel" ];

  preRun = ''
    PUBLIC_DOCS="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Steam/CODEX"
    SAVE_SRC="$PUBLIC_DOCS/1822030"
    SAVE_DST="$STROM_GAMEDIR/codex-1822030"

    mkdir -p "$SAVE_DST" "$PUBLIC_DOCS"

    if [ -d "$SAVE_SRC" ] && [ ! -L "$SAVE_SRC" ]; then
      cp -an "$SAVE_SRC/." "$SAVE_DST/" 2>/dev/null || true
      rm -rf "$SAVE_SRC"
    fi
    ln -snf "$SAVE_DST" "$SAVE_SRC"
  '';

  # Unity's VideoPlayer plays the studio-logo intro (embedded in
  # sharedassets0.resource) through Proton's Media Foundation, which is backed
  # by GE-Proton's bundled GStreamer. The universal ffmpeg decoder plugin
  # (libgstlibav.so -> libavformat/libavcodec/libavfilter.so) is NEEDED-linked
  # against host libraries that the Steam Linux Runtime would normally provide:
  # libbz2.so.1.0 (bzip2), libva.so.2 + libva-drm/libva-x11.so.2 (libva),
  # libvdpau.so.1 (libvdpau) and the legacy libvpx.so.6. strom has no SLR
  # container, so without these the plugin fails to dlopen, MF has no video
  # decoder, and the VideoPlayer throws WindowsVideoMedia error 0xc00d36bb
  # (MF_E_UNSUPPORTED_BYTESTREAM_TYPE) on a tight retry loop -> the game wedges
  # on a black screen and never reaches the menu (verified via Player.log:
  # 10k+ identical errors). libvpxSo6Compat aliases the current libvpx as the
  # legacy soname. With all present libgstlibav loads, the intro decodes, and
  # the game proceeds to the title screen.
  targetPkgs = p: [
    p.bzip2
    p.libva
    p.libvdpau
    libvpxSo6Compat
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
    description = "The Library of Babel (Tanuki Game Studio 2023, Unity stealth puzzle-platformer, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-library-of-babel";
  };
}
