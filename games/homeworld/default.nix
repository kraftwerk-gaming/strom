{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Homeworld Remastered Collection v2.1 (build
  # 3877). Three-part GOG installer (.exe + 2 .bin slices). innoextract
  # reads them together when they sit next to each other; we symlink
  # them in $TMPDIR with the original filenames before extracting.
  setupExe = fetchIpfs {
    cid = "QmNZii5dEietiWJ3XWamoXtZVJ4G8uWoMokCFXjg38puiQ";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29.exe";
    hash = "sha256-G5xedp7ALYkNvhfF0hU1UnTGxwwxflBAlgFTZo7Cijs=";
    name = "homeworld-remastered-gog-2.1.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "QmcAz3HugvgxsXrqUjSpoz2pKDQKiMi9bee8fbKDcz9nV4";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-1.bin";
    hash = "sha256-V82oiqkkQGMPEv1iohZ0d2ZiwK7PvUWKzkqU/m04aHM=";
    name = "homeworld-remastered-gog-2.1-1.bin";
  };

  setupBin2 = fetchIpfs {
    cid = "QmWNTi4bwTDXjQRmsu2ua4z6nvPvYBK5kEBPWWyC8RxPYy";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-2.bin";
    hash = "sha256-CjcrK21uVNwbC0Pz8/JNsviaSHwNKKfh9zt6JFd9XyQ=";
    name = "homeworld-remastered-gog-2.1-2.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "homeworld";

  ipfsSources = [
    setupExe
    setupBin1
    setupBin2
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    mkdir -p "$TMPDIR/hw"
    ln -s ${setupExe}  "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    ln -s ${setupBin1} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-1.bin"
    ln -s ${setupBin2} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-2.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    rm -rf "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" "$out/webcache.zip" 2>/dev/null || true
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # Profiles/<name>/* + local.ini next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  # The Remastered Collection ships four engine builds — HomeworldRM
  # (a modern HW1+HW2 unified DX9 renderer for the remastered
  # campaigns), Homeworld1Classic and Homeworld2Classic (legacy
  # 1999/2003 ports) and HWLauncher (the .NET/WPF Gearbox picker GUI).
  #
  # HomeworldRM.exe statically imports Galaxy.dll (GOG Galaxy SDK) and
  # calls galaxy::api::Init() on startup. An earlier note here blamed
  # that for a silent ~10s exit. THAT CONCLUSION WAS WRONG, and the
  # correction is worth keeping because the observation behind it was
  # right: Galaxy.dll really does throw (16x e06d7363, with catch types
  # .?AVIRuntimeError@api@galaxy@@ / IUnauthorizedAccessError /
  # IInvalidArgumentError / IInvalidStateError registered by its own SEH
  # descriptors). But Galaxy.dll CATCHES it, the engine's g_galaxyInit
  # gate goes false, and all 50 gated call sites take the offline
  # branch, so the game runs. The silent exit was the pre-73e3ae6
  # overlay copy-up EXDEV bug killing the engine's write-next-to-binary
  # probe. Measured on the fixed base: stock tree, stock Galaxy.dll,
  # reaches the Remastered main menu and is still rendering it at 203s.
  # No stub DLL is needed; one was written and proven correct, then
  # deliberately not shipped. games/homeworld-remastered-collection now
  # ships that RM build from these same three CIDs.
  #
  # Homeworld1Classic is the original 1999 Relic binary preserved
  # alongside the remaster. Imports table (verified with strings):
  # DDRAW / DSOUND / glide2x / opengl32 / binkw32 / rgl — zero
  # Galaxy.dll, zero steam_api, zero .NET. Runs cleanly under Proton on
  # AMD Mesa via Wine's builtin ddraw onto wined3d. (NOT via DXVK: no
  # DXVK ddraw exists. GE-Proton's dxvk dir ships only d3d8, d3d9,
  # d3d10core, d3d11 and dxgi, so DirectDraw never goes through it.)
  executable = "Homeworld1Classic/exe/Homeworld.exe";
  # HW1 only knows about a fixed set of CLI resolutions (/640, /800,
  # /1024, /1280, /1600 — no /1920). Picking /1280 sidesteps the
  # default 800x600 startup AND the in-game resolution-change crash:
  # changing it via the options menu issues an SDL/DDRAW mode-set
  # round-trip that Wine + gamescope's nested compositor can't satisfy
  # cleanly, killing the engine. /fullscreen pairs with the gamescope
  # 1920x1080 outer surface so the engine never tries to renegotiate.
  executableArgs = [
    "/1280"
    "/fullscreen"
    "/safeGL"
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

  env = {
    # Homeworld's GL renderer (rgl.dll → opengl32) only knows how to
    # bind a fixed-pipeline profile; on Mesa the default 4.x core
    # context is rejected by the engine's GL probe. Forcing a 3.3
    # compatibility profile satisfies the probe and lets the engine
    # build its GL context.
    MESA_GL_VERSION_OVERRIDE = "3.3COMPAT";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LANG = "en_US.UTF-8";
  };

  preRun = ''
    # Homeworld.exe resolves its data archive (Homeworld1Classic/Data/
    # homeworld.big) relative to ../Data — i.e. cwd must be the
    # Homeworld1Classic/exe subdir, not the install root.
    cd "$GAMEDIR/Homeworld1Classic/exe"
  '';

  meta = {
    description = "Homeworld (Relic, 1999 classic, GOG Remastered Collection v2.1 build 3877, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "homeworld";
  };
}
