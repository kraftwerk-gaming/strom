{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # SiN Gold (GOG re-release, version 1.13b build 36951). Ritual
  # Entertainment 1998 FPS on a heavily modified Quake II engine,
  # bundled here with the Wages of Sin expansion (game = "2015") and
  # the SiN CTF mod (game = "ctf"). The GOG installer is a single
  # Inno Setup .exe; innoextract --gog yields sin.exe + ref_gl.dll +
  # ref_soft.dll at the tree root, with base/ (main game), 2015/
  # (Wages of Sin), and ctf/ as the three Q2-style game directories.
  src = fetchIpfs {
    cid = "Qmbj3vMjcFQoFd8kCKgS1wMuB2L5swHtcFATKU7SCbhLy6";
    fallbackUrl = "https://archive.org/download/setup_sin_gold_1.13b_36951/setup_sin_gold_1.13b_%2836951%29.exe";
    hash = "sha256-uHq2SbpMzd9AdKON8Bjlh4iR0yFmLOxqm/KPTZ7q770=";
    name = "sin-gold-gog.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sin";

  inherit src;

  nativeBuildInputs = [
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + redistributables + SDK + 3dfx Glide
    # wrappers: not needed at runtime. The actual game lives at $out
    # root (sin.exe + ref_*.dll + base/ + 2015/ + ctf/).
    rm -rf "$out/app" "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" "$out/sdk" "$out/reslists"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico
  '';

  runtime = "proton";
  executable = "sin.exe";

  # Quake II-derived engine: savegames and config land in each game dir
  # next to the binary (base/save/, 2015/save/, ctf/save/) in the install
  # tree, so they persist via the per-game fuse-overlayfs upper. No
  # wineprefix relocation needed.
  saveLocations = [ ];
  # Force fullscreen so gamescope sees a fullscreen surface; the
  # shipped base/default.cfg sets vid_fullscreen 0, which would
  # otherwise spawn the engine in a small window inside gamescope.
  # gl_mode 6 = 1024x768; gamescope upscales to 1920x1080.
  executableArgs = [
    "+set"
    "vid_fullscreen"
    "1"
    "+set"
    "gl_mode"
    "6"
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
    description = "SiN Gold (Ritual Entertainment 1998, GOG v1.13b build 36951, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sin";
  };
}
