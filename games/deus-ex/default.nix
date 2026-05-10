{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # GOG GOTY edition of Deus Ex (2000). Archive ships a rar bundling both
  # the GOTY installer (self-contained .exe) and a separate Revision-mod
  # installer with a .bin slice; we only need the GOTY .exe.
  src = fetchIpfs {
    cid = "QmYirjSSa4qwbxoBWH3Cc2g8Ywn1ZwUa3hphcmH7phq8bg";
    fallbackUrl = "https://archive.org/download/deus-ex-goty-edition/Deus%20Ex%20-%20GOTY%20Edition.rar";
    hash = "sha256-tVEYGrn7iYPDUJunpQ0EQFgMt352rblRSbTrTbldafg=";
    name = "deus-ex-goty.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "deus-ex";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    cd "$TMPDIR/rar/DeusEx" || cd "$TMPDIR/rar"/*
    innoextract --gog -d "$TMPDIR/iss" \
      "setup_deus_ex_goty_1.112fm(revision_1.6.1.0)_(45326).exe"
    # innoextract drops game files at the root; app/ holds only the GOG
    # icon, webcache.zip, and an empty Save dir we don't need.
    cp -r "$TMPDIR/iss"/* "$out/"
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata" "$out/app"

    # The default DeusEx.ini ships with FirstRun=0, which makes DeusEx.exe
    # pop the hardware-detection wizard on launch. Set a version-stamped
    # value (any non-zero engine build) so the wizard is skipped. Bump
    # the default 640x480/16bpp to 1920x1080/32bpp. The .ini uses CRLF
    # line endings, so the `$` anchor has to allow the trailing \r.
    sed -i -E \
      -e 's/^FirstRun=0\r?$/FirstRun=1100\r/' \
      -e 's/^FullscreenViewportX=.*$/FullscreenViewportX=1920\r/' \
      -e 's/^FullscreenViewportY=.*$/FullscreenViewportY=1080\r/' \
      -e 's/^FullscreenColorBits=.*$/FullscreenColorBits=32\r/' \
      -e 's/^WindowedColorBits=.*$/WindowedColorBits=32\r/' \
      -e 's/^ColorDepth=.*$/ColorDepth=32\r/' \
      -e 's|^GameRenderDevice=GlideDrv.GlideRenderDevice\r?$|GameRenderDevice=D3DDrv.D3DRenderDevice\r|' \
      -e 's|^RenderDevice=GlideDrv.GlideRenderDevice\r?$|RenderDevice=D3DDrv.D3DRenderDevice\r|' \
      -e 's|^WindowedRenderDevice=SoftDrv.SoftwareRenderDevice\r?$|WindowedRenderDevice=D3DDrv.D3DRenderDevice\r|' \
      -e 's|^UseDirectDraw=True\r?$|UseDirectDraw=False\r|' \
      "$out/System/DeusEx.ini"
  '';

  runtime = "proton";
  executable = "System/DeusEx.exe";
  # Force resolution at launch — the Unreal-1 engine probes the X server
  # for video modes and picks something tiny in the gamescope nested
  # session, ignoring whatever we pre-wrote into DeusEx.ini.
  executableArgs = [
    "-ResX=1920"
    "-ResY=1080"
    "-32bit"
  ];

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

  meta = {
    description = "Deus Ex GOTY (2000, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "deus-ex";
  };
}
