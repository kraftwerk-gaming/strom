{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Condemned: Criminal Origins (Monolith Productions, 2005). Lithtech
  # Jupiter EX engine, 32-bit DirectX 9. The zip is a Steam install drop
  # of the standard Steam library subtree, captured at the top level as
  # `Condemned Criminal Origins/` containing Condemned.exe, the engine
  # DLLs (EngineServer.dll, GameClient.dll, GameServer.dll, binkw32.dll,
  # eax.dll, LTMemory.dll, SndDrv.dll, MFC/MSVC 7.1 runtimes), the
  # Lithtech .Arch00 archives under Game/ (CondemnedA.Arch00 ~6.6 GB +
  # CondemnedL.Arch00), and the Steam-side Redist/ + installscript.vdf
  # we ignore. Steam appid 4720, used by umu-proton's protonfixes layer.
  src = fetchIpfs {
    cid = "QmTUyjaAtWX34K8hBtggLbupdY6XoHmomzRtab2PJ7uZ16";
    fallbackUrl = "https://archive.org/download/condemned-criminal-origins/Condemned%20Criminal%20Origins.zip";
    hash = "sha256-PUl1Xh9ZL3XFH8DlFHVfc5gsEmvSqyPlPx0O6pkbyU0=";
    name = "condemned-criminal-origins.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "condemned-criminal-origins";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Zip wraps everything in a single `Condemned Criminal Origins/`
  # directory. Flatten that to $out so Condemned.exe sits at the
  # gamedir root, matching how the engine resolves Game/*.Arch00 and
  # the language asset dirs via cwd-relative paths. Drop Redist/ and
  # installscript.vdf: the DirectX/vcredist installers are Steam
  # first-launch bootstrap that has no business in a proton prefix
  # (DXVK and Proton's bundled vcrun cover what the engine needs).
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Condemned Criminal Origins/." "$out/"
    chmod -R u+w "$out"
    rm -rf "$out/Redist" "$out/installscript.vdf"

    # Lithtech Jupiter EX runs autoexec.cfg cvar commands at engine
    # startup, before CPerformanceMgr's GPU auto-detect runs and before
    # the per-profile gps blob is applied. We use it as the single
    # source of truth for first-launch graphics state — the engine
    # writes the resulting cvar values into Profile000.gps as the new
    # profile is created, so the in-game menu reflects High from
    # launch 1.
    #
    # Texture-quality fix: CPerformanceMgr (CPerformanceMgr::GetDetailLevel
    # in GameClient.dll) looks up the host GPU in the engine's bundled
    # video-card table; under DXVK the reported card doesn't match any
    # 2005-era record, so the fallback picks the Minimum tier and writes
    # GPUDetailLevel=0 / CPUDetailLevel=0 / ClientFXDetailLevel=0 plus
    # high LOD bias on every texture group — the "horribly low"
    # textures the user observes. Pinning each cvar from autoexec.cfg
    # short-circuits the auto-detect path: the values are already at
    # High by the time GetDetailLevel runs.
    #
    # Settings-menu crash fix: Windowed=1 keeps the engine's swap
    # chain anchored to the child HWND so resolution changes from the
    # in-game Display dialog go through ResizeBuffers / SetWindowPos
    # instead of D3D9 Reset() against a mode-list-empty headless
    # adapter (DXVK + gamescope present no real CRT modes, which is
    # what trips the crash). Gamescope still draws fullscreen to the
    # host, so this is transparent to the user.
    #
    # Cvar names verified from `strings` of GameClient.dll, GameServer.dll,
    # EngineServer.dll, and Condemned.exe in the unpacked tree.
    cat > "$out/autoexec.cfg" <<'EOF'
    ScreenWidth 1920
    ScreenHeight 1080
    BitDepth 32
    Windowed 1
    GPUDetailLevel 3
    CPUDetailLevel 3
    ClientFXDetailLevel 3
    WorldDetail 3
    ModelDecalPerformanceLevel 3
    RenderTargetLOD 0
    PerformanceTestRan 1
    PerformanceTestLevel 3
    TextureGroupOffsetD 0
    TextureGroupOffsetE 0
    TextureGroupOffsetN 0
    TextureGroupOffsetS 0
    PGResolutionScale 1
    LODLights 0
    LODMaterials 0
    LODShadows 0
    Light_ShadowBlur 1
    Light_ShadowVolume 1
    VolumetricLightShadow 1
    VolumetricLightSlices 64
    VolumetricLightNoise 1
    EnableScreenBloom 1
    EnableScreenEffects 1
    EnableVolumetricLight 1
    EnableHighPerformanceSounds 1
    Anisotropic 1
    Trilinear 1
    AntiAliasFSOverSample 1
    VSyncOnFlip 1
    DisableHardwareCursor 1
    EOF
  '';

  runtime = "proton";
  executable = "Condemned.exe";

  # Condemned writes savegames + Profile000.gdb/.gps + settings.cfg to
  # the wineprefix's PUBLIC user docs at
  #   drive_c/users/Public/Documents/Monolith Productions/Condemned/
  # (the path is hard-coded as `\Monolith Productions\Condemned\` in
  # Condemned.exe; the engine resolves it via SHGetFolderPath
  # CSIDL_COMMON_DOCUMENTS, which proton maps to users/Public/Documents
  # — NOT users/steamuser/Documents). That falls outside the
  # steamuser-rooted saveLocations migration in lib/proton.nix, so we
  # do the relocation manually in preRun below. Leaving saveLocations
  # empty so the lib code doesn't conjure a steamuser/Documents/...
  # symlink that never gets written to.
  saveLocations = [ ];

  # First-launch setup:
  #   1. Symlink the wineprefix Condemned save dir at
  #      users/Public/Documents/Monolith Productions/Condemned to
  #      $STROM_GAMEDIR/Condemned, so saves + profile binaries
  #      (Profile000.gdb/.gps) survive a prefix wipe.
  #   2. Pre-seed settings.cfg with the desired display state. The
  #      autoexec.cfg cvars cover the same fields on the engine side,
  #      but the in-game Options -> Display dialog reads settings.cfg
  #      directly on open: without the file, the dialog renders empty
  #      strings and the user can't preview before applying, which
  #      makes the (already mitigated) D3D9 Reset() path more likely
  #      to be exercised against bad input.
  preRun = ''
    PUBLIC_DOCS="$STROM_COMPATDATA/0/pfx/drive_c/users/Public/Documents/Monolith Productions"
    SAVE_SRC="$PUBLIC_DOCS/Condemned"
    SAVE_DST="$STROM_GAMEDIR/Condemned"

    mkdir -p "$SAVE_DST" "$PUBLIC_DOCS"

    # Migrate any pre-existing real save dir (from a previous run before
    # this symlink existed) into $STROM_GAMEDIR, then replace it with a
    # symlink. After the first migration this is a no-op fast path.
    if [ -d "$SAVE_SRC" ] && [ ! -L "$SAVE_SRC" ]; then
      cp -an "$SAVE_SRC/." "$SAVE_DST/" 2>/dev/null || true
      rm -rf "$SAVE_SRC"
    fi
    ln -snf "$SAVE_DST" "$SAVE_SRC"

    if [ ! -f "$SAVE_DST/settings.cfg" ]; then
      cat > "$SAVE_DST/settings.cfg" <<'EOS'
    "ScreenWidth" "1920"
    "ScreenHeight" "1080"
    "BitDepth" "32"
    "Windowed" "1"
    "HardwareCursor" "0"
    "VSyncOnFlip" "1"
    "Gamma" "1.000000"
    EOS
    fi
  '';

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
    # Steam appid 4720 = Condemned: Criminal Origins. Mirrored via
    # umu-proton's protonfixes layer to apply per-title workarounds.
    STEAM_COMPAT_APP_ID = "4720";
    SteamAppId = "4720";
    # 32-bit Lithtech Jupiter EX binary; mirror the LAA / writecopy
    # workarounds other 32-bit DX9 titles in this repo apply (bioshock,
    # cryostasis) so the engine can address the full user-mode range
    # under wine and the MFC71/MSVCR71 thunks don't trip Wine's COW
    # tracking on hot-patched pages.
    WINE_LARGE_ADDRESS_AWARE = "1";
    STAGING_WRITECOPY = "1";
  };

  meta = {
    description = "Condemned: Criminal Origins (Monolith Productions 2005, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "condemned-criminal-origins";
  };
}
