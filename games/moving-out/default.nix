{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  p7zip,
}:

let
  # Moving Out (SMG Studio / DevM Games / Team17, 2020). Co-op physics
  # furniture-moving party game on Unity (IL2CPP: MovingOut.exe +
  # GameAssembly.dll + MovingOut_Data/ + UnityPlayer.dll). No native
  # Linux build, so runtime = "proton".
  #
  # SOURCE: a SteamUnlocked pre-extracted, ready-to-run Windows repack
  # of Steam build 1.3.4856.169 incl. all DLC, shipped as a plain zip
  # (no installer to run). The game tree sits two folders deep inside:
  #   Moving.Out.v1.3.4856.169.Incl.ALL.DLC/
  #     Moving.Out.v1.3.4856.169.Incl.ALL.DLC/<game files>
  src = fetchIpfs {
    cid = "QmaphiAZynKkXcy56i4VMDS4XBLCCrbsEbkhohVr74N1P8";
    fallbackUrl = "";
    hash = "sha256-KQm1WzctSBf/uwTqKAaBFZlfSlkby0XyZ2lwcdCPQEM=";
    name = "moving-out-1.3.4856.169.zip";
  };

  # gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init and the rest of the Steamworks surface. The repack
  # ships a packed ALI213-style emu (MovingOut_Data/Plugins/
  # steam_api64.dll + SteamConfig.ini) that wedges MovingOut.exe under
  # GE-Proton -- the process starts but never creates its D3D11 render
  # window (persistent black screen). gbe_fork is a static DLL with no
  # watchdog/anti-debug threads and initializes cleanly offline under
  # proton, letting the game reach the main menu.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_30/emu-win-release.7z";
    hash = "sha256-ONDOgi949bIt0o2Uj0scmLxl9fw6hQt3dShnQ6YONRY=";
  };

  # GE-Proton bundles ffmpeg 4.x (libavcodec.so.58) for winegstreamer, but
  # that libavcodec is NEEDED-linked against libvpx.so.6 (libvpx 1.9.x) --
  # a soname nixpkgs no longer ships (current libvpx is .so.12). Pin 1.9.0
  # so Proton's bundled libavcodec/libgstlibav can resolve it in the FHS.
  libvpx6 = pkgs.libvpx.overrideAttrs (old: {
    version = "1.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "webmproject";
      repo = "libvpx";
      rev = "v1.9.0";
      hash = "sha256-PsN8AOHZalYaB9OCu1yS5vJTvN8BAx8gCU8gtqoyu5s=";
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "moving-out";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    unzip
    p7zip
  ];

  buildScript = ''
    mkdir -p "$TMPDIR/extract"
    unzip -q "$src" -d "$TMPDIR/extract"
    # Game tree is nested two folders deep; copy the inner one that holds
    # MovingOut.exe out to the install root.
    inner="$(dirname "$(find "$TMPDIR/extract" -name MovingOut.exe -print -quit)")"
    mkdir -p "$out"
    cp -a "$inner"/. "$out"/

    # SteamUnlocked clutter + bundled redist installers (Proton's FHS
    # already provides the VC/.NET/DirectX/OpenAL runtimes).
    rm -rf "$out/_Redist" "$out/Redist"
    rm -f "$out"/*.url "$out"/*.txt

    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. atomicrops/dredge).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"

    # Replace the repack's packed ALI213 emu with gbe_fork (see comment
    # above). Drop its SteamConfig.ini too; gbe_fork reads steam_settings/
    # next to its dll instead.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    plugins="$out/MovingOut_Data/Plugins"
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$plugins/steam_api64.dll"
    rm -f "$plugins/SteamConfig.ini"

    # gbe_fork looks for steam_settings/ next to steam_api64.dll, and
    # many games also read steam_appid.txt next to the exe. Moving Out is
    # Steam AppID 996770.
    mkdir -p "$plugins/steam_settings"
    echo -n 996770 > "$plugins/steam_settings/steam_appid.txt"
    echo -n 996770 > "$out/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "MovingOut.exe";

  # Unity 2019 standalone player flags: force exclusive fullscreen at the
  # gamescope-nested resolution so Unity uses that path rather than its
  # "borderless windowed" one, which otherwise leaves a black backbuffer
  # in the nested compositor (cf. hardspace-shipbreaker).
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  # Fix the startup-splash black-screen hang. Unity's WindowsVideoMedia
  # backend plays the StreamingAssets .mp4 movies through Wine's Media
  # Foundation, which Proton implements on top of winegstreamer using its
  # bundled gstreamer plugin tree (files/lib/.../gstreamer-1.0; that's the
  # only dir on the GST_PLUGIN_SYSTEM_PATH the proton script computes, and
  # its plugins are built for Proton's gstreamer 1.22 core so swapping in
  # newer host plugins fails on undefined symbols). The H.264 decoder
  # there, libgstlibav.so -> libavcodec.so.58, is NEEDED-linked against a
  # chain of host libraries GE-Proton expects from the Steam Linux Runtime
  # container -- libbz2.so.1.0, libvpx.so.6, libva.so.2, libvdpau.so.1 --
  # which strom's FHS doesn't carry. The dlopen fails, gstreamer registers
  # no H.264 decoder, and Media Foundation's source resolver can't build a
  # pipeline for the splash mp4: it fails at CreateObjectFromByteStream
  # with WindowsVideoMedia error 0xc00d36bb (MF_E_UNSUPPORTED_BYTESTREAM_
  # TYPE). Moving Out's splash coroutine then waits forever on a
  # VideoPlayer end event that never fires, so the already-loaded MainMenu
  # never presents (black screen). Supplying those libs in the FHS lets
  # the bundled decoder load, the splash plays, and the menu appears.
  targetPkgs = p: [
    p.bzip2
    p.libva
    p.libvdpau
    libvpx6
  ];

  # Moving Out persists progress through Steamworks remote-storage, which
  # gbe_fork redirects to its local save tree under
  # AppData/Roaming/Goldberg SteamEmu Saves/<appid>/ inside the prefix.
  # Relocate that so a prefix wipe doesn't take user progress.
  saveLocations = [ "AppData/Roaming/Goldberg SteamEmu Saves" ];

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Moving Out (SMG Studio / Team17 2020, Unity co-op moving party game incl. all DLC, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "moving-out";
  };
}
