{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  innoextract,
  unzip,
}:

let
  # 2004 People Can Fly / DreamCatcher horror-FPS, GOG "Black Edition"
  # offline installer v1.64 build 24538 (English-only). The rar holds
  # the GOG InnoSetup installer pair under ENG/ at the rar's top level
  # (no Painkiller/ wrapper dir):
  #   ENG/setup_painkiller_black_1.64_lang_update_(24538).exe
  #   ENG/setup_painkiller_black_1.64_lang_update_(24538)-1.bin
  # Bonus content (artworks/avatars/manual/soundtrack/wallpapers zips)
  # also sits at the top level and is ignored at extract time.
  src = fetchIpfs {
    cid = "QmZbeXCa8N3iWv7aoNMJTceV1743tKhgYmNV5maB85voYC";
    fallbackUrl = "https://archive.org/download/painkiller-black-edition/Painkiller%20-%20Black%20Edition.rar";
    hash = "sha256-B1tmgvh5ZuH1BSchuK0m6QE8EGEaqDk3QaCUvwTo50s=";
    name = "painkiller-black-edition.rar";
  };

  # ThirteenAG's d3d9-wrapper: open-source (Unlicense) d3d9.dll proxy
  # that intercepts IDirect3D9::CreateDevice, rewrites the host
  # window's size with SetWindowPos, and rewrites the
  # D3DPRESENT_PARAMETERS BackBufferWidth/Height to match. This is the
  # canonical community workaround for Painkiller's hardcoded 640x480
  # client-area issue under DXVK (see DXVK issue #3762, which the
  # dxvk contributor WinterSnowfall resolves with this same wrapper +
  # ForceWindowedMode = 1:
  # https://github.com/doitsujin/dxvk/issues/3762 ). The wrapper
  # internally GetSystemDirectory()-loads the real d3d9.dll (DXVK's,
  # under Proton), so it composes cleanly: engine -> wrapper (resizes
  # window via SetWindowPos before CreateDevice returns) -> DXVK
  # (builds Vulkan swapchain at the resized window's client area) ->
  # gamescope. Painkiller is a 32-bit binary (verified via the
  # Bin/Painkiller.exe header), so we only need the 32-bit d3d9.zip;
  # d3d9_x64.zip is for 64-bit games.
  d3d9Wrapper = fetchurl {
    url = "https://github.com/ThirteenAG/d3d9-wrapper/releases/download/d3d9-wrapper-v1.63/d3d9.zip";
    hash = "sha256-gneNvdn4iwVLlM/xr12NSsiWN/1WMilWPai0a+JEzlw=";
    name = "d3d9-wrapper-v1.63.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "painkiller";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
    unzip
  ];

  # GOG InnoSetup multi-part installer (Inno 5.6.2 unicode, GOG ID
  # 1207658715). innoextract reads the multi-part installer when the
  # .exe and -1.bin sit side-by-side. Unlike most GOG installers, this
  # one does NOT place the game payload under {app}/. Instead the
  # InnoSetup script extracts Bin/, Data/, Docs/ and Exporters/ at the
  # install root and reserves app/ for two empty stub dirs (SaveGames/,
  # Screenshots/). The full layout innoextract produces:
  #   Bin/Painkiller.exe    -- single engine binary that handles both
  #                            the original Painkiller campaign and the
  #                            bundled Battle Out Of Hell expansion
  #                            (selected from in-game menu)
  #   Bin/Engine.dll, D3Dev.dll, binkw32.dll, mss32.dll, Miles/...
  #   Bin/config.ini        -- default config (rewritten on first run
  #                            with Cfg.Resolution etc.)
  #   Bin/Editor/PainEditor.exe (level editor; we keep it but don't run it)
  #   Bin/goggame-1207658715.dll -- GOG-info shim, NOT statically
  #                            imported by Painkiller.exe (verified via
  #                            objdump -p), so no Galaxy stub required.
  #   Data/   *.pak / *.pkm -- single-player + DM/MP pak archives
  #   Docs/   ReadMe, manuals
  #   app/SaveGames, app/Screenshots -- writable runtime dirs (engine
  #                            looks for them next to Bin/, see preRun)
  # Skipped: __redist (DirectX/VC redist installers), commonappdata
  # (uninstall.dll), tmp (slideshow assets shown only by the Inno
  # installer GUI), webcache.zip and goggame-1207658715.{ico,info,
  # script,hashdb} (Galaxy-side metadata, not used at runtime).
  buildScript = ''
    mkdir -p "$TMPDIR/rar"
    # -D suppresses unar's auto-wrapper dir for multi-top-level archives.
    # The rar has ENG/ + bonus zips at root, so without -D unar would
    # bundle them under "$TMPDIR/rar/<src-basename>/".
    unar -D -o "$TMPDIR/rar" "$src"
    # Top-level inside the rar is just ENG/ (no Painkiller/ wrapper).
    INSTALLER_DIR="$TMPDIR/rar/ENG"
    cd "$INSTALLER_DIR"
    mkdir -p "$TMPDIR/iss"
    innoextract --gog -d "$TMPDIR/iss" \
      'setup_painkiller_black_1.64_lang_update_(24538).exe'
    mkdir -p "$out"
    # Game payload sits at the install root, not under {app}/. Copy the
    # known-good top-level dirs and merge app/ (SaveGames/, Screenshots/)
    # into it so the engine finds its writable runtime dirs next to Bin/.
    cp -r "$TMPDIR/iss/Bin"  "$out/Bin"
    cp -r "$TMPDIR/iss/Data" "$out/Data"
    cp -r "$TMPDIR/iss/Docs" "$out/Docs"
    cp -r "$TMPDIR/iss/app/." "$out"/
    chmod -R u+w "$out"

    # Drop ThirteenAG's d3d9.dll proxy next to Painkiller.exe so the
    # Windows DLL search order (.exe dir before system32) loads it
    # ahead of DXVK's d3d9.dll. The wrapper itself then loads DXVK's
    # d3d9.dll via GetSystemDirectoryA() to forward calls; we just
    # interpose to fix the window size at CreateDevice time. The
    # WINEDLLOVERRIDES env entry below ensures Wine treats the
    # exe-dir d3d9.dll as native (not stub-replaced by builtin).
    unzip -o ${d3d9Wrapper} -d "$out/Bin"

    # Configure the wrapper. Background: ThirteenAG's d3d9-wrapper
    # exposes only HWND-side knobs (window style/size); it does NOT
    # have a knob to rewrite D3DPRESENT_PARAMETERS::BackBufferWidth/
    # Height (verified by reading source/dllmain.cpp -- only [MAIN]
    # and [FORCEWINDOWED] keys are consumed). With ForceWindowStyle=1
    # the wrapper SetWindowPos's the HWND to the full monitor size
    # (1920x1080 inside our gamescope nested viewport), but leaves
    # the engine-chosen BackBufferWidth/Height untouched. If those
    # don't match the HWND client area, DXVK builds a swapchain at
    # the engine's BackBuffer size and the result either upper-left-
    # anchors or stretches depending on the engine's Present() flags.
    # Painkiller's engine probes the requested Cfg.Resolution; values
    # like 1920x1080 may be rejected by the probe and silently
    # demoted to a smaller mode (or to its hardcoded 640x480
    # default), which is what produced the "upper-left quarter"
    # symptom previously observed with ForceWindowStyle=1.
    #
    # Strategy:
    #   - ForceWindowedMode = 1: rewrite presentation params to
    #     windowed; without this DXVK cannot stretch the engine's
    #     exclusive-fullscreen request to the gamescope monitor.
    #   - ForceWindowStyle = 4 ("borderless window, no monitor
    #     stretch"): from dllmain.cpp lines 314-321 the wrapper
    #     sizes the HWND to pPresentationParameters->
    #     BackBufferWidth/Height (i.e. the engine's chosen mode,
    #     1024x768 per Cfg.Resolution in preRun) and strips chrome.
    #     HWND now matches BackBuffer -> DXVK swapchain, HWND, and
    #     BackBuffer all agree at 1024x768; no upper-left anchoring
    #     possible. Compare with ForceWindowStyle=1, where the
    #     wrapper SetWindowPos's HWND to monitor size while leaving
    #     BackBufferWidth/Height at the engine's smaller value -- the
    #     mismatch is what produced the upper-left-quarter symptom.
    #   - The 1024x768 -> 1920x1080 upscale is moved to gamescope
    #     (nested viewport set to 1024x768 below); gamescope handles
    #     pillarboxing cleanly into the 1920x1080 output (Painkiller
    #     2004 has only 4:3 mode probes accepted; we know 1024x768
    #     and 800x600 work).
    sed -i \
      -e 's/^ForceWindowedMode = 0/ForceWindowedMode = 1/' \
      -e 's/^ForceWindowStyle = 0/ForceWindowStyle = 4/' \
      "$out/Bin/d3d9.ini"
  '';

  runtime = "proton";
  # Bin/Painkiller.exe is the only game-side launcher in the GOG Black
  # Edition build. It handles both the original campaign and the BOOH
  # expansion via in-engine menu selection.
  executable = "Bin/Painkiller.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    # The d3d9 wrapper (ForceWindowStyle = 4 in d3d9.ini) sizes the
    # HWND to the engine's BackBufferWidth/Height instead of stretching
    # to the monitor, so HWND/swapchain/BackBuffer all agree at the
    # engine-chosen mode (1024x768, the largest 4:3 mode the engine's
    # mode probe accepts -- see preRun's Cfg.Resolution seed).
    # gamescope nested-viewport matches that 1024x768 backbuffer so the
    # engine fills the nested viewport with no upper-left anchoring,
    # then gamescope upscales (with pillarboxing) 1024x768 -> 1920x1080.
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    # Painkiller ships its own RAD Game Tools binkw32 + RAD Miles Sound
    # System mss32 next to the engine. Wine has builtins for both
    # (winewinmm/devenum-style stubs) that don't implement enough of
    # the Bink/Miles APIs the engine calls, so we have to mark them
    # native-first. "n,b" = native first, builtin fallback. Engine.dll
    # statically imports both (verified via objdump -p), so without
    # these overrides Wine quietly hands the engine the builtin entries
    # and the engine SEH-faults a few frames into intro playback.
    #
    # d3d9 = native-first too: this points Wine at the ThirteenAG
    # wrapper d3d9.dll we drop into Bin/ (next to Painkiller.exe) in
    # the buildScript, ahead of DXVK's d3d9.dll in system32. The
    # wrapper itself then loads the system d3d9.dll (DXVK) via
    # GetSystemDirectoryA(), so we still get DXVK's Vulkan backend --
    # the wrapper only intercepts CreateDevice to fix the engine's
    # 640x480 HWND.
    WINEDLLOVERRIDES = "binkw32,mss32,d3d9=n,b";
  };

  preRun = ''
    # Painkiller's engine resolves all of its data paths as ../Data/...
    # relative to its cwd (verified via strings on Engine.dll: the
    # binary contains literal `../Data/Models/`, `../Data/Sounds/%s.wav`,
    # `../Data/Movies/right.bik` etc.). The launcher therefore must cd
    # into Bin/ before invoking Painkiller.exe; otherwise the engine
    # silently exits when it fails to open Data/Levels.pak relative to
    # its cwd of $GAMEDIR/.
    cd "$GAMEDIR/Bin"

    # Seed Cfg.Resolution to a mode the engine's mode probe actually
    # accepts. Empirically Painkiller 1.64 only accepts 4:3 modes
    # from the InitVideoMode probe -- 1024x768 and 800x600 verified;
    # 1920x1080 is rejected and silently demoted, which produced the
    # upper-left-quarter render symptom. 1024x768 is the largest
    # accepted mode and gives the cleanest gamescope upscale to the
    # 1920x1080 output (pillarboxed). The d3d9 wrapper's
    # ForceWindowStyle=4 sizes the HWND to BackBufferWidth/Height
    # (i.e. 1024x768) so DXVK's swapchain, the HWND, and the engine's
    # BackBuffer all agree -- no anchoring/scaling mismatch in the
    # D3D9 -> Vulkan -> Xwayland path. Cfg.Fullscreen = false because
    # the wrapper forces borderless-windowed (ForceWindowedMode = 1
    # in d3d9.ini); leaving Cfg.Fullscreen = true would have the
    # engine ask DXVK for an exclusive-fullscreen mode which the
    # wrapper would then have to demote to windowed inside CreateDevice
    # -- works, but the windowed path is the cleaner code path.
    #
    # The cfg file has to be read-only at engine-exit time, or the
    # engine writes its actual rendered backbuffer size back into
    # Cfg.Resolution. chmod 0444 after seeding makes the engine's
    # exit-time rewrite silently fail, so our seed survives across
    # launches. Same pattern as games/journey/default.nix.
    #
    # Regex tolerates both quoted ("1920X1080") and unquoted forms,
    # capital-X and lowercase-x, and any whitespace around the `=`,
    # so it still matches whatever string the engine wrote on a
    # previous broken run.
    cfg="$STROM_GAMEDIR/Bin/config.ini"
    mkdir -p "$STROM_GAMEDIR/Bin"
    if [ ! -f "$cfg" ] || [ ! -w "$cfg" ]; then
      install -m 0644 "$GAMEDIR/Bin/config.ini" "$cfg"
    fi
    sed -i \
      -e 's/^Cfg\.Resolution[[:space:]]*=.*/Cfg.Resolution = "1024X768"/' \
      -e 's/^Cfg\.Fullscreen[[:space:]]*=.*/Cfg.Fullscreen = false/' \
      "$cfg"
    chmod 0444 "$cfg"
  '';

  meta = {
    description = "Painkiller: Black Edition (People Can Fly 2004, GOG v1.64, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "painkiller";
  };
}
