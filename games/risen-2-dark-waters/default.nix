{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
  p7zip,
  cabextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "risen-2-dark-waters";

  # GOG offline installer "Risen 2 - Dark Waters" Gold Edition v1.0 build
  # 18732 (Piranha Bytes / Deep Silver 2012, Genome-engine pirate action RPG,
  # DRM-free). Distributed as a single zip wrapping the split GOG Inno Setup
  # payload (setup_..._-_dark_waters_1.0_(18732).exe + two .bin chunks); the
  # game tree lands under app/ after `innoextract --gog`.
  src = fetchIpfs {
    cid = "QmaDyzewYrCrhq2ykqffzdNxWfaum2LoPZ9gEqdApHok6p";
    fallbackUrl = "https://pixeldrain.com/api/file/cQjP5J77?download";
    hash = "sha256-VWx0jzwkk9/SjiriMSdxxUeZSlSn0fPNCGHxMeV4rF4=";
    name = "risen-2-dark-waters.zip";
  };

  nativeBuildInputs = [
    unzip
    innoextract
    p7zip
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip" "$TMPDIR/iss"

    # The download is a zip whose single top-level dir holds the GOG installer
    # stub + the two .bin data chunks. Unzip just the base-game installer (the
    # Gold-upgrade exe and the Bonus/ extras are not needed to launch).
    unzip -q "$src" \
      'Risen.2.Dark.Waters.Gold.Edition.v1.0/setup_risen_2_-_dark_waters_*' \
      -d "$TMPDIR/zip"
    iss_root="$TMPDIR/zip/Risen.2.Dark.Waters.Gold.Edition.v1.0"

    # innoextract --gog reads the GOG Inno Setup payload; the install root is
    # the app/ subdir (app/system/Risen.exe + app/data/...). The English
    # language filter drops the other six localisations' dialogue paks.
    innoextract --gog -d "$TMPDIR/iss" --language english \
      "$iss_root/setup_risen_2_-_dark_waters_1.0_(18732).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    chmod -R u+w "$out"

    # The GOG installer copies __support/app/* over the install root as a
    # post-install step; innoextract leaves __support/ in place untouched, so
    # the live tree is MISSING data/ini/ (ConfigDefault.xml + loc.ini +
    # mountlist_packed.ini). Without ConfigDefault.xml the engine has no
    # resolution/renderer config and never opens a window. Merge it in.
    if [ -d "$out/__support/app" ]; then
      cp -r "$out/__support/app"/. "$out"/
    fi

    # The shipped ConfigDefault.xml's <Window> block has RefreshRate="0".
    # The Genome engine feeds that 0 straight into the D3D9 present params /
    # display-mode enumeration; on modern hardware a 0 Hz mode is invalid and
    # the engine dereferences the failed enumeration result, crashing at
    # startup with a GENOME CRASH LOG (EXCEPTION_ACCESS_VIOLATION) before the
    # menu -- the well-documented Risen 2 "refreshrate 0 = crash on launch"
    # bug (community fix: set RefreshRate to your display's Hz). Pin it to 60.
    # Also widen the 1024x768 default window to 1920x1080 so the borderless
    # client fills the gamescope nested output (FullScreen is already "false"
    # in this GOG build, so no exclusive-fullscreen mode-set under the nested
    # compositor).
    config="$out/data/ini/ConfigDefault.xml"
    substituteInPlace "$config" \
      --replace-fail 'RefreshRate="0"' 'RefreshRate="60"' \
      --replace-fail 'Bottom="768"' 'Bottom="1080"' \
      --replace-fail 'Right="1024"' 'Right="1920"'

    # Install the AGEIA PhysX SDK 2.8.1 runtime. Risen.exe statically imports
    # PhysXLoader.dll (and NxCooking.dll via the engine), but the GOG app/ tree
    # ships NO PhysX DLLs -- the runtime lives only in the bundled redist
    # __support/add/PhysX_SystemSoftware.exe, which the GOG installer would
    # normally run to drop the DLLs into System32. Because we copy only app/,
    # that step never happens, so under Proton Risen.exe dies at loader_init
    # before it ever creates a window (import PhysXLoader.dll not found ->
    # c0000135). Same WISE-cabinet redist and same 2.8.1 GUID set as Risen 1.
    #
    # Risen 2's only PhysXLoader variant in the redist is the
    # EFBABE66... build, version-stamped 2.8.3.37; at NxCreatePhysicsSDK time
    # Risen.exe requests SDK v2.8.3, so the loader builds the path
    # syswow64\PhysX\v2.8.3\PhysXCore.dll (verified in the wine module trace).
    # The matching 2.8.3 core/cooking is GUID B475FE6B (the VS_FIXEDFILEINFO
    # of every redist DLL was parsed to map GUID -> version: B475FE6B = 2.8.3,
    # whereas 6CB22D51 = 2.8.1, the version Risen 1 uses). Installing a 2.8.1
    # core under this 2.8.3 loader fails the load at v2.8.3\PhysXCore.dll with
    # c0000135 and the engine calls LdrShutdownProcess immediately, never
    # reaching the menu.
    #
    #   system/      : PhysXLoader.dll + NxCooking.dll + PhysXDevice.dll
    #                  (Risen.exe's import dir + the engine's cooking import).
    #   $out root    : PhysXCore.dll + physxcudart_20.dll, staged for preRun to
    #                  install into the wineprefix at the registry-pointed path
    #                  (PhysXLoader appends \v2.8.3\PhysXCore.dll to the AGEIA
    #                  "PhysXCore Path" reg value).
    physx_redist="$out/__support/add/PhysX_SystemSoftware.exe"
    7z x -y -o"$TMPDIR/physx-pe" "$physx_redist" >/dev/null
    cabextract -d "$TMPDIR/physx" "$TMPDIR/physx-pe/.WISE" >/dev/null
    install -Dm755 \
      "$TMPDIR/physx/PhysXLoader.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/system/PhysXLoader.dll"
    install -Dm755 \
      "$TMPDIR/physx/NxCooking.dll.B475FE6B_CFD7_3DAD_AD27_058EDC10A03C" \
      "$out/system/NxCooking.dll"
    install -Dm755 \
      "$TMPDIR/physx/PhysXDevice.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/system/PhysXDevice.dll"
    install -Dm644 \
      "$TMPDIR/physx/PhysXCore.dll.B475FE6B_CFD7_3DAD_AD27_058EDC10A03C" \
      "$out/PhysXCore.dll"
    # The 2.8.3 PhysXCore's PE import table needs cudart32_30_9.dll (the CUDA
    # 3.0 runtime), NOT the physxcudart_20.dll that the 2.8.1 core uses --
    # without it PhysXCore fails to load (err:module:import_dll cudart32_30_9
    # not found) and the engine shuts down before the menu.
    install -Dm644 \
      "$TMPDIR/physx/cudart32_30_9.dll.3519F62D_1F72_101B_B1DB_834CDCF298A9" \
      "$out/cudart32_30_9.dll"

    # Stage native (Microsoft) d3dx9_43.dll + D3DCompiler_43.dll for preRun to
    # install into the wineprefix's syswow64. Risen 2's renderer compiles its
    # .fx effect shaders through d3dx9_43's fx_2_0 path, which delegates to
    # d3dcompiler. Wine's builtin d3dcompiler routes that through vkd3d's HLSL
    # compiler, which does NOT implement the legacy effect framework:
    #   err:d3dcompiler:D3DCompile2 Failed to compile shader, vkd3d result -5
    #   E5017: ... Writing fx_2_0 sampler objects initializers is not implemented
    #   E5017: ... Write pass assignments
    # Every effect fails to compile, the engine gets NULL shader/material
    # objects, and the render init dereferences them -> GENOME CRASH LOG
    # (EXCEPTION_ACCESS_VIOLATION, the IGNAVIA crash) before the menu. The
    # genuine MS d3dx9_43 + d3dcompiler_43 carry the complete fx_2_0 effect
    # compiler; both ship in Risen 2's own bundled DirectX redist
    # (tmp/directx_Jun2010_redist.exe -> the Jun2010_d3dx9_43_x86 +
    # Jun2010_D3DCompiler_43_x86 inner cabs). preRun drops them into syswow64
    # and env pins them native (WINEDLLOVERRIDES).
    dx_redist="$TMPDIR/iss/tmp/directx_Jun2010_redist.exe"
    7z e -y -o"$TMPDIR/dxcabs" "$dx_redist" \
      Jun2010_d3dx9_43_x86.cab Jun2010_D3DCompiler_43_x86.cab >/dev/null
    cabextract -d "$TMPDIR/dxdll" -F 'd3dx9_43.dll' \
      "$TMPDIR/dxcabs/Jun2010_d3dx9_43_x86.cab" >/dev/null
    cabextract -d "$TMPDIR/dxdll" -F 'D3DCompiler_43.dll' \
      "$TMPDIR/dxcabs/Jun2010_D3DCompiler_43_x86.cab" >/dev/null
    install -Dm644 "$TMPDIR/dxdll/d3dx9_43.dll" "$out/d3dx9_43.dll"
    install -Dm644 "$TMPDIR/dxdll/D3DCompiler_43.dll" "$out/d3dcompiler_43.dll"

    # Pre-menu publisher logos (Deep Silver / Piranha Bytes / Ubisoft). These
    # are Bink .vid files; under DXVK Bink video renders pitch-black (dxvk
    # issue #4614) but still consumes its full playback time before the menu
    # loads, stalling the launch on three black screens. Truncate them to
    # empty so the engine treats each as a zero-length clip and skips straight
    # to the main menu. The menu's own video backdrop (menu*.vid) is left
    # intact -- the 2D menu UI composites on top of it, so a black backdrop
    # still shows the (functional) menu buttons.
    for __v in logo_ds logo_pb logo_ubi; do
      : > "$out/data/extern/videos/$__v.vid"
    done

    # Strip GOG-launcher / installer side files not needed at runtime.
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.ico "$out"/goggame-*.script "$out"/*.url 2>/dev/null || true
    rm -rf "$out/__support" "$out/tmp" 2>/dev/null || true
  '';

  runtime = "proton";

  # The Genome engine binary. app/system/Risen.exe is the game executable;
  # Settings.exe (in app/) is just the standalone config tool.
  executable = "system/Risen.exe";

  preRun = ''
    # Install the PhysX 2.8.1 PhysXCore.dll into the wineprefix and stamp the
    # AGEIA registry key so PhysXLoader can find it. Engine PhysX init
    # (NxCreatePhysicsSDK via PhysXLoader.dll) otherwise returns NULL and the
    # engine aborts before the menu. PhysXLoader's lookup appends
    # \v<SDK_VERSION>\PhysXCore.dll to the AGEIA "PhysXCore Path" reg value
    # (a DIRECTORY), so lay that layout down under syswow64\PhysX\ and point
    # the reg key at it. Mirrors games/risen and games/arcania.
    pfx="$STROM_COMPATDATA/0/pfx"
    physxdir="$pfx/drive_c/windows/syswow64/PhysX"
    if [ -d "$pfx/drive_c/windows/syswow64" ] && [ -f "$STROM_OVERLAY/PhysXCore.dll" ]; then
      mkdir -p "$physxdir/v2.8.3"
      install -m0644 "$STROM_OVERLAY/PhysXCore.dll" "$physxdir/v2.8.3/PhysXCore.dll"
      # The 2.8.3 PhysXCore.dll's PE IAT imports cudart32_30_9.dll; co-locate
      # it next to the core and in syswow64 so both the import resolver and any
      # short-name LoadLibrary from PhysXCore's startup resolve.
      if [ -f "$STROM_OVERLAY/cudart32_30_9.dll" ]; then
        install -m0644 "$STROM_OVERLAY/cudart32_30_9.dll" "$physxdir/v2.8.3/cudart32_30_9.dll"
        install -m0644 "$STROM_OVERLAY/cudart32_30_9.dll" "$pfx/drive_c/windows/syswow64/cudart32_30_9.dll"
      fi
    fi
    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -qF 'syswow64\\PhysX"' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wow6432Node\\\\Ageia Technologies] %s\n' "$(date +%s)"
        printf '"PhysXCore Path"="C:\\\\windows\\\\syswow64\\\\PhysX"\n'
        printf '"enableLocalPhysXCore"=dword:00000001\n'
      } >> "$SYSREG"
    fi

    # Drop native MS d3dx9_43.dll + d3dcompiler_43.dll into syswow64 so the
    # WINEDLLOVERRIDES native pin (see env) has real DLLs to bind. These carry
    # the fx_2_0 effect compiler that wine's vkd3d-backed d3dcompiler lacks;
    # without them Risen 2's .fx shaders fail to compile and the render init
    # dereferences the NULL effects, crashing before the main menu.
    if [ -d "$pfx/drive_c/windows/syswow64" ]; then
      for __dx in d3dx9_43.dll d3dcompiler_43.dll; do
        [ -f "$STROM_OVERLAY/$__dx" ] \
          && install -m0644 "$STROM_OVERLAY/$__dx" "$pfx/drive_c/windows/syswow64/$__dx"
      done
    fi

    # Force windowed mode. On a fresh prefix the engine writes its own
    # ConfigUser.xml with FullScreen="true" (its hardcoded user default,
    # independent of ConfigDefault.xml's "false"), then attempts a D3D9
    # exclusive-fullscreen mode-set. Under the nested gamescope compositor
    # that mode-set fails and the engine dies with a GENOME CRASH LOG
    # (EXCEPTION_ACCESS_VIOLATION) before the menu. Seed a minimal
    # ConfigUser.xml with FullScreen="false" BEFORE launch so the engine
    # reads windowed mode and composes a borderless 1920x1080 client into the
    # gamescope output instead. Only seed when absent so the player's own
    # settings (written on exit) win on later launches.
    cfgdir="$pfx/drive_c/users/steamuser/AppData/Local/Risen2/Config"
    if [ ! -f "$cfgdir/ConfigUser.xml" ]; then
      mkdir -p "$cfgdir"
      printf '%s\n' \
        '<options>' \
        '	<Engine>' \
        '		<Window Right="1920" FullScreen="false" Bottom="1080">' \
        '		</Window>' \
        '	</Engine>' \
        '</options>' > "$cfgdir/ConfigUser.xml"
    fi

    # Risen.exe statically imports binkw32 / fmodex / libexpat / PhysXLoader /
    # NxCooking, all shipped as its SIBLINGS in system/. strom's inner script
    # execs proton with cwd = $STROM_OVERLAY (the install root), NOT system/.
    # The Genome loader resolves those imports against the CURRENT DIRECTORY,
    # so from the root it finds none of them and dies at loader_init
    # (c0000135). cd into system/ so the import DLLs sit in the current
    # directory; the engine still locates ../data via the exe path, so the
    # menu and game assets load from the root.
    cd "$STROM_OVERLAY/system"
  '';

  # Risen 2 writes savegames under "Saved Games\Risen 2" (with a space) and
  # its per-user config/profile under LOCALAPPDATA "Risen2" (NO space --
  # verified at runtime: the engine creates AppData\Local\Risen2\Config\
  # ConfigUser.xml). Both live under the Wine user profile
  # (drive_c/users/steamuser/), so relocate them into $STROM_GAMEDIR to
  # survive wineprefix wipes. LOCALAPPDATA maps to AppData/Local under Wine.
  saveLocations = [
    "Saved Games/Risen 2"
    "AppData/Local/Risen2"
  ];

  env = {
    # Piranha Bytes' Genome engine spawns one worker thread per logical CPU
    # and races them through its renderer/physics init. On a modern many-core
    # host (here 127 engine threads) that race hits an unsynchronised pointer
    # and the engine dies at startup with a GENOME CRASH LOG
    # (EXCEPTION_ACCESS_VIOLATION, empty stack) before the main menu -- the
    # well-documented Risen 2 "crashes on modern multi-core CPUs" bug.
    # WINE_CPU_TOPOLOGY=1:0 makes ntdll report a single processor, so the
    # engine spawns one worker and the race window closes. Same lever as
    # games/empire-earth and games/spellforce-2-anniversary-edition.
    WINE_CPU_TOPOLOGY = "1:0";

    # Pin native (Microsoft) d3dx9_43 + d3dcompiler_43 -- preRun installs both
    # into syswow64. The native pair compiles Risen 2's fx_2_0 effect shaders;
    # wine's builtin d3dcompiler delegates to vkd3d's HLSL compiler, which
    # aborts on the legacy effect framework ("Writing fx_2_0 sampler objects
    # initializers is not implemented" / "Write pass assignments"), so the
    # render init crashes before the main menu. Same lever as games/risen.
    WINEDLLOVERRIDES = "d3dx9_43,d3dcompiler_43=n";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # The engine runs WINDOWED (ConfigUser.xml FullScreen="false", seeded in
      # preRun to dodge the exclusive-fullscreen mode-set crash). A windowed
      # game under the nested gamescope compositor does NOT confine the pointer
      # to its window, so the OS cursor moves freely and the Genome engine
      # never sees the relative mouse-motion it needs for mouse-look / cursor
      # control -- in-game mouse input appears dead. Grab the pointer into the
      # window (relative mouse mode) so motion feeds the engine. Same lever as
      # the strategy games here (spellforce-2 et al.).
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Risen 2: Dark Waters (Piranha Bytes 2012, GOG Gold Edition v1.0, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risen-2-dark-waters";
  };
}
