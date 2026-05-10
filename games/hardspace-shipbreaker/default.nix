{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmcVJd7C6vARAN7RudbqDB1aZr141ELitzqtCuN3wPoPaU";
    fallbackUrl = "https://ipfs.io/ipfs/QmcVJd7C6vARAN7RudbqDB1aZr141ELitzqtCuN3wPoPaU";
    hash = "sha256-OiGNcSLkwBkLA0Q5E+0XCj8q4griRuBa1KbdlXBv/SE=";
    name = "hardspace-shipbreaker-repackgames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hardspace-shipbreaker";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Repack ships two parallel exe trees:
  #   Hardspace.Shipbreaker.v1.3.0.1263554/Shipbreaker.exe          (top-level stub)
  #   Hardspace.Shipbreaker.v1.3.0.1263554/Hardspace Shipbreaker/   (the actual Unity 2020.3 install)
  # We strip the duplicate top-level stub and the !Extra/ soundtrack
  # folder, keeping just the playable game tree.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Hardspace.Shipbreaker.v1.3.0.1263554/Hardspace Shipbreaker/"* "$out"/

    # Unity's WindowsVideoMedia backend dispatches every StreamingAssets/Video
    # mp4 through Wine's Media Foundation reimplementation (mfplat.dll), which
    # rejects every mp4 we have tried (studio-shipped H.264 High, ffmpeg
    # H.264 Baseline stubs, and zero-byte files alike) with
    # WindowsVideoMedia error 0xc00d36bb (MF_E_UNSUPPORTED_BYTESTREAM_TYPE):
    # CreateObjectFromByteStream refuses the container before codec init.
    # Unity's VideoPlayer.Prepare retries every frame instead of surfacing
    # errorReceived — that's the BBI_logo splash hang the SkipSplashScreen
    # toggle below avoids, and the same hang on the in-game opening
    # cinematic (HSSB_opening_1080p.mp4) which has no skip toggle and
    # leaves the FTUE on a black screen with only the cursor.
    #
    # Delete the cinematic mp4s entirely. The Doozy.Engine UIView coroutine
    # that fronts the cinematic logs '[Graphics] [Warn]: File not found',
    # then throws a one-shot InvalidOperationException out of
    # UIView.ExecuteShow's enumerator (its collection of pending views is
    # cleared mid-iteration when the cinematic view bails), and the FTUE
    # state machine moves on. Confirmed end-to-end: log shows scene unload
    # / 'Initializing Session 1' / tutorial ship spawn
    # (A1_TUT_01_XX_MovementAndBasicTools_ModuleConstructionAsset) /
    # 'Starting Session 1' immediately after the warning.
    rm -rf "$out/Shipbreaker_Data/StreamingAssets/Video"
  '';

  runtime = "proton";
  executable = "Shipbreaker.exe";

  # Unity 2020.3 standalone player flags: force exclusive fullscreen at the
  # gamescope-nested resolution so Unity doesn't try its "borderless windowed"
  # path (which leaves a black backbuffer when Wine's WMF decoder stalls).
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  # Belt-and-braces alongside the StreamingAssets/Video deletion above:
  # the first frame of every Hardspace launch normally decodes
  # Shipbreaker_Data/StreamingAssets/Video/BBI_logo_1080p.mp4 through
  # Unity's WindowsVideoMedia (Windows Media Foundation), which fails under
  # wine-mf with 0xc00d36bb and hangs the engine on a black window. The
  # video deletion makes the splash bail with File not found, but flipping
  # the shipped SkipSplashScreen toggle skips the splash UIView outright
  # so the launch never even hits VideoPlayer.Prepare for BBI_logo.
  preRun = ''
    if [ -f "$GAMEDIR/config.ini" ]; then
      sed -i 's/^SkipSplashScreen=false$/SkipSplashScreen=true/' "$GAMEDIR/config.ini"
    fi
  '';

  # Pre-copy config.ini into the writable overlay layer so the sed above
  # mutates a real file rather than triggering fuse-overlayfs copy-up on
  # every launch.
  copyGlobs = [ "config.ini" ];

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
    description = "Hardspace: Shipbreaker (Blackbird Interactive 2022, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hardspace-shipbreaker";
  };
}
