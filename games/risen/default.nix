{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  p7zip,
  cabextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "risen";

  # GOG offline installer setup_risen_2.0.0.6.exe (Piranha Bytes 2009 action
  # RPG, DRM-free). Single-file Inno Setup payload (no split .bin); the game
  # tree lands under app/ after `innoextract --gog`. Sourced from the
  # "Risen (GOG)" torrent and pinned to IPFS.
  src = fetchIpfs {
    cid = "QmV2FoMcwjyxqyBM65cLSBpjXRY2rXBkTXZoTCbJNaLLkY";
    fallbackUrl = "magnet:?xt=urn:btih:44c30223668efe04cb0b3e662ba7e929e9d25704&dn=Risen+(GOG)&tr=udp://tracker.opentrackr.org:1337/announce&tr=udp://open.stealth.si:80/announce&tr=udp://exodus.desync.com:6969/announce";
    hash = "sha256-lVBA8p6n/LfDbDlpbZgvNqSiZH2eq0Nx8S0FTodSnTM=";
    name = "setup_risen_2.0.0.6.exe";
  };

  nativeBuildInputs = [
    innoextract
    p7zip
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iss"

    # innoextract --gog reads the GOG Inno Setup payload; the install root is
    # the app/ subdir (app/bin/Risen.exe + app/data/...). __redist, tmp/ and
    # the GOG launcher debris stay behind.
    innoextract --gog -d "$TMPDIR/iss" "$src"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    chmod -R u+w "$out"

    # Strip GOG-launcher / installer side files not needed at runtime.
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.ico "$out"/*.url 2>/dev/null || true

    # Install the AGEIA PhysX SDK 2.8.1 runtime. Risen's Engine.dll statically
    # imports PhysXLoader.dll and calls NxGetCookingLib (from NxCooking.dll),
    # but the GOG app/ tree ships NO PhysX DLLs -- the runtime lives only in
    # the bundled redist tmp/PhysX_9.09.0408_SystemSoftware.exe, which the GOG
    # installer would normally run to drop the DLLs into System32. Because we
    # copy only app/, that step never happens, so under Proton Risen.exe dies
    # at loader_init before it ever creates a window:
    #   err:module:import_dll Library PhysXLoader.dll ... not found  (-> Engine.dll)
    #   err:module:loader_init Importing dlls for ...\bin\Risen.exe failed,
    #     status c0000135
    # (the lingering wineserver/xalia helpers are why the launch looked like a
    # 200s "running but blank" hang rather than an instant exit).
    #
    # The redist is a WISE self-extractor: innoextract pulls it out of the GOG
    # payload, 7z splits the PE sections, and cabextract unpacks the WISE
    # cabinet in its .WISE section. The cabinet carries one copy of each shipped
    # PhysX version with a GUID suffix. Risen's bundled PhysXLoader.dll is
    # SDK 2.8.1 (the `PhysX_2.8.1_GPU\...\PhysXLoader.pdb` string in its table),
    # so PhysXCore.dll and NxCooking.dll MUST also be the 2.8.1 build (GUID
    # 6CB22D51 -- the only `PhysX_2.8.1_GPU` core/cooking in the cabinet).
    # Mixing a 2.7.3 core under a 2.8.1 loader makes NxCreatePhysicsSDK return
    # NULL at runtime ("failed to Create Physics SDK!", ge_physics_scene.cpp).
    #
    #   bin/         : PhysXLoader.dll + NxCooking.dll (Engine.dll's direct
    #                  imports) + PhysXDevice.dll.
    #   $out root    : PhysXCore.dll + physxcudart_20.dll, staged for preRun to
    #                  install into the wineprefix at the registry-pointed path
    #                  (PhysXLoader appends \v2.8.1\PhysXCore.dll to the AGEIA
    #                  "PhysXCore Path" reg value -- see preRun, mirrors arcania).
    physx_redist="$TMPDIR/iss/tmp/PhysX_9.09.0408_SystemSoftware.exe"
    7z x -y -o"$TMPDIR/physx-pe" "$physx_redist" >/dev/null
    cabextract -d "$TMPDIR/physx" "$TMPDIR/physx-pe/.WISE" >/dev/null
    install -Dm755 \
      "$TMPDIR/physx/PhysXLoader.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/bin/PhysXLoader.dll"
    install -Dm755 \
      "$TMPDIR/physx/NxCooking.dll.6CB22D51_BF57_36A9_B82B_D8B0F0F46D53" \
      "$out/bin/NxCooking.dll"
    install -Dm755 \
      "$TMPDIR/physx/PhysXDevice.dll.EFBABE66_E43C_474F_A6F1_F0312317E9E1" \
      "$out/bin/PhysXDevice.dll"
    install -Dm644 \
      "$TMPDIR/physx/PhysXCore.dll.6CB22D51_BF57_36A9_B82B_D8B0F0F46D53" \
      "$out/PhysXCore.dll"
    install -Dm644 \
      "$TMPDIR/physx/physxcudart_20.dll.8411CAB1_77D8_41F8_B107_07F845725F8D" \
      "$out/physxcudart_20.dll"

    # Stage native (Microsoft) d3dx9_29.dll + D3DCompiler_43.dll for preRun to
    # install into the wineprefix's syswow64. Risen's renderer compiles its
    # .fx effect shaders through d3dx9_29's fx_2_0 path, which delegates to
    # d3dcompiler. Wine's builtin d3dcompiler routes that through vkd3d's HLSL
    # compiler, which does NOT implement the legacy effect framework:
    #   err:d3dcompiler:D3DCompile2 Failed to compile shader, vkd3d result -5
    #   E5017: ... Writing fx_2_0 sampler objects initializers is not implemented
    #   E5017: ... Write pass assignments
    # Every effect fails to compile, so the engine wedges at the title splash
    # and never reaches the main menu. The genuine MS d3dx9_29 + d3dcompiler_43
    # carry the complete fx_2_0 effect compiler; both ship in Risen's own
    # bundled DirectX redist (tmp/directx_Jun2010_redist.exe -> the
    # Feb2006_d3dx9_29_x86 + Jun2010_D3DCompiler_43_x86 inner cabs). preRun
    # drops them into syswow64 and env pins them native (WINEDLLOVERRIDES).
    dx_redist="$TMPDIR/iss/tmp/directx_Jun2010_redist.exe"
    7z e -y -o"$TMPDIR/dxcabs" "$dx_redist" \
      Feb2006_d3dx9_29_x86.cab Jun2010_D3DCompiler_43_x86.cab >/dev/null
    cabextract -d "$TMPDIR/dxdll" -F 'd3dx9_29.dll' \
      "$TMPDIR/dxcabs/Feb2006_d3dx9_29_x86.cab" >/dev/null
    cabextract -d "$TMPDIR/dxdll" -F 'D3DCompiler_43.dll' \
      "$TMPDIR/dxcabs/Jun2010_D3DCompiler_43_x86.cab" >/dev/null
    install -Dm644 "$TMPDIR/dxdll/d3dx9_29.dll" "$out/d3dx9_29.dll"
    install -Dm644 "$TMPDIR/dxdll/D3DCompiler_43.dll" "$out/d3dcompiler_43.dll"

    # Start windowed at the gamescope nested resolution instead of the engine's
    # default exclusive fullscreen. The GOG ConfigDefault.xml ships
    # FullScreen="true" with a 1024x768 window rect; gamescope owns the real
    # 1920x1080 output, so a borderless 1920x1080 client window fills it and
    # avoids a D3D9 exclusive-fullscreen mode-set under the nested compositor.
    # The engine only writes a user config override once the menu is reached,
    # so patching the shipped default is the seam that applies on first run.
    config="$out/data/ini/ConfigDefault.xml"
    substituteInPlace "$config" \
      --replace-fail 'FullScreen="true"' 'FullScreen="false"' \
      --replace-fail 'Bottom="768"' 'Bottom="1080"' \
      --replace-fail 'Right="1024"' 'Right="1920"'

    # logo.ini lists the pre-menu publisher logos (logo_01/02/03.bik) but this
    # GOG build ships only logo_01/logo_02 -- logo_03.bik is absent. Empty the
    # playlist so the engine skips straight to the main menu and never blocks
    # on the missing third logo. Risen tolerates an empty intro list.
    : > "$out/data/extern/videos/logo.ini"
  '';

  runtime = "proton";

  # Risen's engine binary. The GOG tree ships the launcher and the engine
  # under bin/; bin/Risen.exe is the actual game executable (the D3D9 engine),
  # not the GOG splash launcher.
  executable = "bin/Risen.exe";

  preRun = ''
    # Install the PhysX 2.8.1 PhysXCore.dll into the wineprefix and stamp the
    # AGEIA registry key so PhysXLoader can find it. Engine.dll's PhysX init
    # (NxCreatePhysicsSDK via PhysXLoader.dll) otherwise returns NULL and the
    # engine aborts with "failed to Create Physics SDK!". PhysXLoader's lookup
    # (verified via `strings`: "PhysXCore Path", "enableLocalPhysXCore"):
    #   load(<AGEIA "PhysXCore Path"> + \v<SDK_VERSION>\PhysXCore.dll)
    # The registry value is a DIRECTORY; PhysXLoader appends \v2.8.1\... itself.
    # Lay that layout down under syswow64\PhysX\ and point the reg key at it.
    # Mirrors games/arcania (same redist, same 2.8.1 loader).
    pfx="$STROM_COMPATDATA/0/pfx"
    physxdir="$pfx/drive_c/windows/syswow64/PhysX"
    if [ -d "$pfx/drive_c/windows/syswow64" ] && [ -f "$STROM_OVERLAY/PhysXCore.dll" ]; then
      mkdir -p "$physxdir/v2.8.1"
      install -m0644 "$STROM_OVERLAY/PhysXCore.dll" "$physxdir/v2.8.1/PhysXCore.dll"
      # PhysXCore.dll's PE IAT imports physxcudart_20.dll; co-locate it next to
      # the core and in syswow64 so both the import resolver and any short-name
      # LoadLibrary from PhysXCore's startup resolve.
      if [ -f "$STROM_OVERLAY/physxcudart_20.dll" ]; then
        install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" "$physxdir/v2.8.1/physxcudart_20.dll"
        install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" "$pfx/drive_c/windows/syswow64/physxcudart_20.dll"
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

    # Drop native MS d3dx9_29.dll + d3dcompiler_43.dll into syswow64 so the
    # WINEDLLOVERRIDES native pin (see env) has real DLLs to bind. These carry
    # the fx_2_0 effect compiler that wine's vkd3d-backed d3dcompiler lacks;
    # without them Risen's .fx shaders fail to compile and it wedges at the
    # title splash short of the main menu.
    if [ -d "$pfx/drive_c/windows/syswow64" ]; then
      for __dx in d3dx9_29.dll d3dcompiler_43.dll; do
        [ -f "$STROM_OVERLAY/$__dx" ] \
          && install -m0644 "$STROM_OVERLAY/$__dx" "$pfx/drive_c/windows/syswow64/$__dx"
      done
    fi

    # Risen.exe statically imports Engine.dll / Game.dll / Importer.dll and a
    # dozen other engine DLLs that ship as its SIBLINGS in bin/. strom's inner
    # script execs proton with cwd = $STROM_OVERLAY (the install root), so the
    # process's current directory is the GOG root, NOT bin/. Risen's loader
    # resolves those engine imports against the CURRENT DIRECTORY rather than
    # the exe's own directory, so from the root it finds none of them and dies
    # at loader_init with STATUS_DLL_NOT_FOUND (c0000135). cd into bin/ so the
    # engine DLLs (incl. PhysXLoader.dll / NxCooking.dll) sit in the current
    # directory and the static imports resolve; the engine still locates ../data
    # via the exe path, so the menu and game assets load from the root.
    cd "$STROM_OVERLAY/bin"
  '';

  # Risen writes savegames under "Saved Games\Risen\SaveGames" and its
  # per-user config/profile under "Documents\Risen". Both live under the
  # Wine user profile (drive_c/users/steamuser/), so relocate them into
  # $STROM_GAMEDIR to survive wineprefix wipes.
  saveLocations = [
    "Saved Games/Risen"
    "Documents/Risen"
  ];

  env = {
    # Pin native (Microsoft) d3dx9_29 + d3dcompiler_43 -- preRun installs both
    # into syswow64. The native pair compiles Risen's fx_2_0 effect shaders;
    # wine's builtin d3dcompiler delegates to vkd3d's HLSL compiler, which
    # aborts on the legacy effect framework ("Writing fx_2_0 sampler objects
    # initializers is not implemented" / "Write pass assignments"), wedging
    # the engine at the title splash before the main menu.
    WINEDLLOVERRIDES = "d3dx9_29,d3dcompiler_43=n";
  };

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
    description = "Risen (Piranha Bytes 2009, GOG v2.0.0.6, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risen";
  };
}
