{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchzip,
  unar,
  wineWow64Packages,
}:

let
  # Build-time wine for the Steamless unpacker pass. Proton's bundled
  # wine binary is a 32-bit ELF that lives in the steam-runtime FHS
  # sandbox (interpreter `/lib/ld-linux.so.2`); it cannot run inside the
  # Nix build sandbox. Plain nixpkgs wineWow64 boots under stdenv with
  # no extra runtime, which is sufficient for Steamless.CLI.exe — a
  # .NET Framework 4.x app that just rewrites the PE header.
  buildWine = wineWow64Packages.stableFull;

  # BioShock (2007 Irrational, original — NOT the 2016 Remastered).
  # The rar is a snapshot of a Steam installation directory: a top-level
  # `BioShock/` wrapper that holds Steam's `depotcache/` and `steamapps/`
  # (appmanifest_7670.acf is the BioShock appid). The actual game lives
  # at `BioShock/steamapps/common/Bioshock/`, with the Vengeance Engine
  # 1 (Unreal 2.5 derivative) executable at `Builds/Release/Bioshock.exe`
  # plus the bundled DLLs (binkw32, d3dx9_33, d3dx10_33, xinput1_3,
  # unicows) and the .U script packages (Engine.U, ShockGame.U,
  # ShockAI.U, ...). Bink movies live under `Content/BinkMovies/`.
  # buildScript flattens the `BioShock/steamapps/common/Bioshock/` tree
  # to $out so the executable path is `Builds/Release/Bioshock.exe`
  # relative to the overlay root.
  src = fetchIpfs {
    cid = "QmV5fHnd19vCdrwEKB99BnV5t8pTAZoJrkAxRwarsDcNFp";
    fallbackUrl = "https://archive.org/download/bioshock_202204/Bioshock.rar";
    hash = "sha256-mSfuMPCjDdJIQmkhNy1lpt9eiBDZJ4lBgl3K2NqzYTk=";
    name = "bioshock-2007-steam.rar";
  };

  # atom0s's Steamless v3.1.0.5 — community SteamStub unpacker. The 2007
  # Bioshock Steam build is wrapped in SteamStub v2.0 DRM: the EXE entry
  # point lives in a tiny `.bind` section that LoadLibraryW's Steam.dll
  # and Authenticode-verifies it via wintrust before dispatching to the
  # real entry point in `.text`. A self-built mingw Steam.dll stub
  # cannot satisfy the wintrust check, so the only reliable workaround
  # is to strip the SteamStub wrapper entirely. Steamless.CLI.exe loads
  # the Variant20 unpacker plugin (Plugins/Steamless.Unpacker.Variant20.
  # x86.dll), locates the OEP (0x004a1e75 for this build), restores the
  # original entry, and writes `<exe>.unpacked.exe` next to the input.
  # The CLI is .NET Framework 4.x — nixpkgs wineWow64 (with its bundled
  # wine-mono) runs it at build time without any extra runtime.
  steamless = fetchzip {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-XCRHmutPspE/7RgUZmMmUwzTf2pzdhcMaLY0hzytszU=";
    stripRoot = false;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bioshock";

  inherit src;

  nativeBuildInputs = [
    unar
    buildWine
  ];

  # The rar wraps the Steam install. We only keep the game payload
  # under `BioShock/steamapps/common/Bioshock/` and drop the Steam
  # depotcache + appmanifest metadata (not consumed at runtime —
  # protonfixes / umu handles the steam compat layer). Drop the bundled
  # `directx/` (~55 MiB of DirectX redist cabs from Apr2005 .. Nov2007)
  # and `vcredist/` (the VC++ 2005 installer) too: under Proton, DXVK
  # supplies d3d9/d3dx9/d3dx10 and the Proton prefix bootstraps the VC++
  # runtimes via protonfixes; the cab installers only ran at first launch
  # on Windows and never get touched by the engine.
  buildScript = ''
        mkdir -p "$TMPDIR/rar" "$out"
        unar -D -o "$TMPDIR/rar" "$src"
        cp -r "$TMPDIR/rar/BioShock/steamapps/common/Bioshock"/. "$out"/
        chmod -R u+w "$out"
        rm -rf "$out/directx" "$out/vcredist" "$out/instscript.vdf"

        # Strip the SteamStub v2.0 wrapper from Bioshock.exe at build time
        # using atom0s's Steamless. Steamless.CLI.exe is a .NET Framework
        # 4.5.2 app; wineWow64.stableFull bundles the wine-mono msi and
        # runs it without any extra runtime.
        #
        # Two non-obvious build setup steps:
        #
        #   - Wine-mono needs to be msiexec-installed up front. Wine's auto
        #     install dialog requires a DISPLAY (which the Nix sandbox does
        #     not have); without DISPLAY the dialog is silently skipped and
        #     the .NET app then fails to launch with rc=255. `msiexec /quiet`
        #     reads the msi from share/wine/mono/ and stages mono-2.0 into
        #     drive_c/windows/.
        #
        #   - Steamless.CLI.exe's AssemblyResolve handler looks in Plugins/
        #     for Steamless.API.dll, but the resolver fires only after Main
        #     starts. The Program type's static cctor contains lambda
        #     closures (`<>c:<>9__3_0`) whose TypeLoad needs the API
        #     assembly already on the probing path. Copy Steamless.API.dll
        #     next to the CLI exe so the standard probe finds it first.
        #
        # The unpacker writes <exe>.unpacked.exe next to the input. We move
        # it on top of the original. A throwaway WINEPREFIX under $TMPDIR
        # is created fresh per realize. WINEDLLOVERRIDES="mshtml=" disables
        # the gecko (wine-mshtml) install prompt — we never touch mscoree
        # because the .NET runtime needs it.
        echo "running Steamless against Bioshock.exe ..."
        export WINEPREFIX="$TMPDIR/steamless-prefix"
        export WINEARCH=win64
        export WINEDLLOVERRIDES="mshtml="
        export WINEDEBUG=-all
        export HOME="$TMPDIR/home"
        mkdir -p "$WINEPREFIX" "$HOME"

        # Stage Steamless writable so Steamless.API.dll sits next to the
        # CLI exe (see comment above re: AssemblyResolve timing).
        cp -r ${steamless} "$TMPDIR/steamless"
        chmod -R u+w "$TMPDIR/steamless"
        cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"

        # Install wine-mono into the throwaway prefix.
        monoMsi=$(echo ${buildWine}/share/wine/mono/wine-mono-*.msi)
        wine msiexec /i "$monoMsi" /quiet

        wine "$TMPDIR/steamless/Steamless.CLI.exe" \
          "$out/Builds/Release/Bioshock.exe"
        wineserver -w 2>/dev/null || true
        [ -f "$out/Builds/Release/Bioshock.exe.unpacked.exe" ] || {
          echo "ERROR: Steamless did not produce Bioshock.exe.unpacked.exe" >&2
          exit 1
        }
        mv "$out/Builds/Release/Bioshock.exe.unpacked.exe" \
           "$out/Builds/Release/Bioshock.exe"
        chmod 0644 "$out/Builds/Release/Bioshock.exe"

        # Patch Default.ini's [Engine.RenderConfig] block to disable the
        # Vengeance Engine post-processing pipeline that produces the
        # round-2..round-4 "black world, UI visible" regression. The
        # engine renders the 3D scene into an off-screen render target,
        # then composites it onto the backbuffer through PostProcessing
        # (bloom + HDR tonemap + distortion). Under both DXVK and wined3d
        # the composite step silently fails — backbuffer stays clear black
        # — while the HUD/UI overlays (separate D3D9 draw pass on top of
        # the composite) render normally. Disabling the composite path
        # entirely makes the engine present the raw scene RT.
        #
        # The supported [Engine.RenderConfig] knobs (per PCGamingWiki +
        # the BioShock Fandom INI tweak page) are PostProcessing,
        # HighDetailShaders, RealTimeReflection, UseDistortion,
        # UseSpecCubeMap, UseRippleSystem, UseHighDetailSoftParticles,
        # Shadows. We turn off the bloom/HDR/distortion composite knobs
        # while keeping Shadows + HighDetailShaders so the scene RT itself
        # is still drawn at full quality.
        sed -i \
          -e 's/^PostProcessing=True/PostProcessing=False/' \
          -e 's/^RealTimeReflection=True/RealTimeReflection=False/' \
          -e 's/^UseDistortion=True;/UseDistortion=False;/' \
          -e 's/^UseSpecCubeMap=True;/UseSpecCubeMap=False;/' \
          -e 's/^UseHighDetailSoftParticles=True/UseHighDetailSoftParticles=False/' \
          -e 's/^UseRippleSystem=True/UseRippleSystem=False/' \
          "$out/Builds/Release/Default.ini"

        # Verify the substitutions fired — fail loud if upstream ever
        # capitalises differently or ships a different default.
        grep -q '^PostProcessing=False' "$out/Builds/Release/Default.ini"
        grep -q '^UseDistortion=False;' "$out/Builds/Release/Default.ini"

        # Round-8: fix the "freeze on save" hang. Two layered tweaks in
        # the [Havok] and [SaveGame] sections of Default.ini, both
        # community-documented save-crash mitigations:
        #
        #   - HavokNumThreads=2 -> 1.  The Vengeance Engine's save path
        #     pauses the simulation, drains every Havok worker, then
        #     serialises rigid-body state. On hosts with >4 cores (here:
        #     12) Havok dispatches save-time joblets to multiple workers
        #     in parallel and the join is racy under Proton's
        #     futex/eventfd scheduling — the engine main thread blocks
        #     forever waiting for a worker that has already exited.
        #     Multiple PCGamingWiki / Steam community guides for both
        #     Bioshock 1 and Bioshock 2 cite "set HavokNumThreads=1" as
        #     the canonical save-crash/save-freeze fix on multi-core
        #     hosts. WineHQ AppDB likewise notes "CPUs with more than 4
        #     cores: saving and loading can crash the game and corrupt
        #     save files".
        #
        #   - ThumbnailFilename=game:\System\savegame.png ->
        #     ThumbnailFilename= (empty).  The save thumbnail is
        #     captured by reading back the D3D9 backbuffer, encoding it
        #     to PNG, and writing it next to the save slot. Under DXVK
        #     the backbuffer readback path stalls when the swapchain is
        #     in the middle of a deferred present (we have
        #     deferSurfaceCreation=True + maxFrameLatency=1, which makes
        #     the present queue extremely short). Clearing the path
        #     skips the readback entirely — the save still writes, it
        #     just has no preview image in the load menu.
        #
        # Both edits target the build-time Default.ini; preRun re-stamps
        # Default.ini into $STROM_GAMEDIR/Bioshock/ on every launch, so
        # the engine sees the patched values when it regenerates
        # Bioshock.ini after the next launch.
        # Default.ini uses CRLF line endings — keep the `\r` on the
        # replacement side and avoid `$` anchors that would refuse to
        # match before the carriage return.
        sed -i \
          -e 's/^HavokNumThreads=2\r$/HavokNumThreads=1\r/' \
          -e 's|^ThumbnailFilename=game:\\System\\savegame.png\r$|ThumbnailFilename=\r|' \
          "$out/Builds/Release/Default.ini"
        grep -q '^HavokNumThreads=1' "$out/Builds/Release/Default.ini"
        # ThumbnailFilename should now be the bare key with just the
        # CRLF after the equals sign. Match the empty value via a
        # negated character class so we don't have to embed \r in a BRE.
        grep -qE '^ThumbnailFilename=[^a-zA-Z]*$' "$out/Builds/Release/Default.ini"

        # Drop a dxvk.conf next to the exe. With the engine's post-processing
        # composite path disabled above, switch the render backend back to
        # DXVK (the Proton default). Round-2..round-3 wined3d experiments
        # and round-4 DLL-mask experiments all reproduced the same composite
        # RT regression, so the composite is the real bug — not the d3d9
        # backend. DXVK with a conservative dxvk.conf gives the best
        # performance on the scene RT itself. The dxgi/d3d10 overrides in
        # env{} below are kept as a belt-and-suspenders pin to D3D9.
        #
        # Round-6: bump shaderModel back to 3 — round-5's SM2 clamp
        # correlated with the new "mouse cursor missing from main menu"
        # symptom. The Vengeance Engine's UI sprite shaders (HUD, cursor,
        # billboards) compile to vs_3_0/ps_3_0 in the ShaderCache.pcs that
        # ships with the build; clamping DXVK to SM2 forces the engine to
        # silently fall back to a no-op draw for any sprite that needs SM3,
        # which matches the cursor-gone, world-black symptom (world also
        # uses sprite particles for steam/water/specks).
        #
        # Round-6: spoof a GTX 460 (10de:0e22, 2010, 1 GiB VRAM, SM4-capable)
        # to push the Vengeance Engine's adapter probe down the "low-end
        # GPU" code path. The 2007 engine queries
        # IDirect3D9::GetAdapterIdentifier and treats reported VRAM as a
        # signed int32; on modern adapters reporting >2 GiB the value
        # underflows and the engine picks an over-sized RT pool that DXVK
        # then can't satisfy. A 2010-era mid-range card has well-defined
        # behaviour in the engine's lookup tables.
        #
        # d3d9.shaderModel = 3 — round-6 (was 2 in round-5).
        # d3d9.customVendorId/customDeviceId — GTX 460 spoof.
        # d3d9.maxAvailableMemory = 2048 — cap reported VRAM.
        # d3d9.evictManagedOnUnlock = True — flush managed-pool RTs.
        # d3d9.deferSurfaceCreation = True — defer back-buffer alloc
        #   until the engine actually presents, avoiding a startup-time
        #   RT format mismatch with the engine's pre-allocated sprite atlas.
        # d3d9.presentInterval = 1 — vsync.
        # dxvk.maxFrameLatency = 1 — keep present queue in lock-step.
        cat > "$out/Builds/Release/dxvk.conf" <<'DXVKCONF'
    d3d9.shaderModel = 3
    d3d9.customVendorId = 10de
    d3d9.customDeviceId = 0e22
    d3d9.maxAvailableMemory = 2048
    d3d9.evictManagedOnUnlock = True
    d3d9.deferSurfaceCreation = True
    d3d9.presentInterval = 1
    dxvk.maxFrameLatency = 1
    DXVKCONF
  '';

  runtime = "proton";
  executable = "Builds/Release/Bioshock.exe";

  # Force the Vengeance Engine's D3D9 render path.
  #
  # The 2007 Bioshock binary ships TWO render device backends and picks
  # between them at startup based on adapter capability detection:
  #
  #     [Engine.Engine]
  #     RenderDevice=D3DDrv.D3DRenderDevice          ; D3D9 (default)
  #     ...
  #     [D3DDrv10.D3DRenderDevice10]                 ; D3D10 (promoted to)
  #
  # On Windows Vista/7 with a DX10 adapter the engine silently promotes
  # itself to the D3D10 path regardless of the INI default. Under
  # Proton+DXVK and under wined3d the D3D10 path renders the 3D world
  # off-screen but never composites it to the swapchain — UI and HUD
  # paint via a separate (D3D9) path on top of the black scene. This
  # exactly matches the round-2/round-3 symptom (intro slides, plane Bink,
  # UI all visible; world black post-bathysphere).
  #
  # The well-documented fix (PCGamingWiki "Run BioShock in DX9 mode",
  # 2K's own Vista patch readme, every Lutris install script) is the
  # `-dx9` command-line argument. The Vengeance Engine bootstrap reads
  # argv early and skips the D3D10 capability probe entirely, locking
  # `RenderDevice=D3DDrv.D3DRenderDevice`. With `-dx9` the engine never
  # touches d3d10.dll/dxgi.dll at all, sidestepping both the DXVK d3d10
  # RTT regression and wined3d's d3d10 GL translation regressions.
  # Sources: PCGamingWiki BioShock; doitsujin/dxvk#655 (DX10 main-menu
  # crash); WineHQ AppDB Bioshock Steam Version notes.
  executableArgs = [ "-dx9" ];

  # Two preRun fixups required to get past the engine's first-read crash:
  #
  # 1. CD into Builds/Release.  The Vengeance Engine reads its Startup.ini
  #    / Default.ini / *.U script files using paths relative to the CWD
  #    (Startup.ini contains `FilePath=..\..\Content\System` etc.). On
  #    Windows the game was launched with CWD=Builds/Release, so the
  #    relative paths reach back to the game root's `Content/` tree. The
  #    strom inner wrapper CDs to the overlay root before exec, so we
  #    have to CD again to the exe's own directory or the engine resolves
  #    `..\..\Content` to the parent of $GAMEDIR (= ~/.cache/strom/Content)
  #    and crashes on missing INIs.
  #
  # 2. Seed Documents\Bioshock\ with the engine's template INIs. The
  #    engine ships Startup.ini / Default.ini / DefUser*.ini next to the
  #    exe and on a clean Windows install copies them into the user
  #    Documents folder before reading. Under Proton with a fresh prefix
  #    that bootstrap path doesn't fire (the user dir is empty), and the
  #    engine SIGSEGVs on the first missing-INI read. We seed
  #    $STROM_GAMEDIR/Bioshock/ (which the saveLocations symlink points
  #    Documents\Bioshock\ at) with the templates. Idempotent — `cp -n`
  #    keeps whatever the user wrote on subsequent launches.
  preRun = ''
    cd "$GAMEDIR/Builds/Release"
    mkdir -p "$STROM_GAMEDIR/Bioshock"
    cp -n "$GAMEDIR/Builds/Release/Startup.ini" \
          "$GAMEDIR/Builds/Release/Default.ini" \
          "$GAMEDIR/Builds/Release/DefUser.ini" \
          "$GAMEDIR/Builds/Release/Version.ini" \
          "$GAMEDIR/Builds/Release/lang.ini" \
          "$STROM_GAMEDIR/Bioshock/" 2>/dev/null || true

    # Round-6: scrub the auto-generated Bioshock.ini from EVERY location
    # the 2007 Vengeance Engine ever writes it to. On Vista+ (which Proton
    # emulates) the engine writes user config to
    #   %APPDATA%\Bioshock\Bioshock.ini
    # = pfx/drive_c/users/steamuser/AppData/Roaming/Bioshock/Bioshock.ini —
    # NOT Documents\Bioshock\ (the XP path). Round-5's cleanup ran against
    # $STROM_GAMEDIR/Bioshock (the symlink target of Documents\Bioshock),
    # so it silently no-op'd while the engine kept reading the stale
    # Bioshock.ini in AppData (with PostProcessing=True). The new
    # `AppData/Roaming/Bioshock` saveLocation below maps that path to the
    # same $STROM_GAMEDIR/Bioshock dir (basenames collide — fine, Bioshock
    # uses a single config dir), so a single rm hits both paths.
    rm -f "$STROM_GAMEDIR/Bioshock/Bioshock.ini"

    # Re-stamp the patched Default.ini into the user config dir on every
    # launch so [Engine.RenderConfig] PostProcessing=False / UseDistortion=
    # False is what the engine sees when it regenerates Bioshock.ini.
    # `cp -f` over-writes whatever stale copy a previous round left.
    cp -f "$GAMEDIR/Builds/Release/Default.ini" \
          "$STROM_GAMEDIR/Bioshock/Default.ini"
  '';

  saveLocations = [
    # Legacy Windows-XP path. Kept for saves left over from previous
    # rounds and because the engine still touches it during first-launch.
    "Documents/Bioshock"
    # Vista+ path — where the live Bioshock.ini, User.ini and save slots
    # actually live in the 2007 engine. saveLocations relocation in
    # lib/proton.nix uses $(basename) for the target, so this maps to the
    # SAME $STROM_GAMEDIR/Bioshock as the Documents/Bioshock entry above.
    # The collision is deliberate: BioShock's config is a single shared
    # directory, the engine just probes both paths.
    "AppData/Roaming/Bioshock"
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
    # SteamAppId 7670 == BioShock (original, 2007) on Steam. The dropped
    # depotcache/appmanifest_7670.acf confirms this is the Steam build.
    STEAM_COMPAT_APP_ID = "7670";
    SteamAppId = "7670";
    # Vengeance Engine is 32-bit; large-address-aware helps on
    # memory-heavy levels.
    WINE_LARGE_ADDRESS_AWARE = "1";
    # Round-5: revert d3d9 to DXVK (Proton default — drop the `d3d9=b`
    # wined3d override). Round-2..round-4 cycled between DXVK, wined3d,
    # and DLL-masked d3d10 paths and all three reproduced the same
    # "black world, UI visible" symptom — proving the d3d9 backend is
    # not the culprit. The real bug is the Vengeance Engine's
    # PostProcessing composite step (now disabled at build time in the
    # patched Default.ini). With the composite gone, DXVK is the right
    # choice for the underlying scene RT — it has stable D3D9 RTT
    # support and ships in Proton.
    #
    # d3d10/d3d10_1/d3d10core/dxgi remain disabled as a belt-and-braces
    # pin to the D3D9 path so the engine cannot silently re-promote
    # itself onto D3D10 even if `-dx9` argv parsing breaks. Matches the
    # Lutris BioShock-Humble installer's
    # HKCU\Software\Wine\DllOverrides\dxgi="" entry.
    #
    # Round-9: force the WINE BUILTIN xinput1_3 (`xinput1_3=b`) instead
    # of the native stub that ships in `Builds/Release/`. The 2007
    # BioShock save-confirmation overlay is a Flash/Scaleform widget;
    # while it is on screen the engine's input thread polls XInputGetState
    # every frame to detect controller-driven UI navigation. The shipped
    # `xinput1_3.dll` is a 2007-era Microsoft redist that, when no
    # XUSB device is enumerated (we have no XInput-class controller in
    # the bwrap sandbox — only the X11 mouse/keyboard pass-through), can
    # take ~30 s per call before timing out and returning
    # ERROR_DEVICE_NOT_CONNECTED. Wine's builtin xinput1_3 short-circuits
    # the enumeration via `udev` and returns instantly, unblocking the
    # save-confirmation dialog's input pump. Matches the symptom: save
    # FILE writes successfully, but the UI hangs because the dialog
    # never receives the "Save complete, press A/Enter" event.
    WINEDLLOVERRIDES = "d3d10=;d3d10_1=;d3d10core=;dxgi=;xinput1_3=b";

    # Round-5: PROTON_NO_ESYNC=1 — reported on ValveSoftware/Proton#388
    # to improve BioShock textures + loadtime by disabling the eventfd
    # synchronisation path. The Vengeance Engine's render thread
    # blocks on a tight present-event loop; esync's eventfd round-trip
    # adds latency that, combined with maxFrameLatency=1 in dxvk.conf,
    # can starve the composite present.
    PROTON_NO_ESYNC = "1";

    # Round-9: PROTON_NO_FSYNC=1 — disable Proton's fsync (futex2)
    # synchronisation path on top of the existing esync disable. With
    # both disabled, wine falls back to the server-mediated wait path,
    # which is the slowest but most deterministic. The Vengeance Engine
    # save flow spawns a worker thread for the .bsb serialise pass and
    # the main UI thread waits on a CreateEvent+WaitForSingleObject
    # handle for completion. Under fsync the wake-up futex2 op races
    # with the engine's own thread-priority manipulation (the save
    # thread re-pins itself to a high priority right before signalling),
    # and the main thread can miss the wake on some host kernels —
    # producing the exact symptom we see (save file persists on disk
    # because the worker completed, but the UI never resumes). With
    # both esync+fsync off the server-side wait queue is authoritative.
    PROTON_NO_FSYNC = "1";
  };

  meta = {
    description = "BioShock (2007 Irrational, Vengeance Engine, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bioshock";
  };
}
