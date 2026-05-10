{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
  p7zip,
}:

let
  # Pre-installed Gold Edition (base game + Venice expansion), No-CD patched.
  src = fetchIpfs {
    cid = "QmX4XBLMuKUgZn1G18igyJPLwcVASKTH7V9YJ6Kf78Stwz";
    fallbackUrl = "https://archive.org/download/CA-WINDOWS-Anno-1404/Anno%201404%20-%20Gold%20Edition.7z";
    hash = "sha256-DgOK4l6OLnoO0Pu1WY7iPjoW+lyAFWRYRdPFZa5Iw44=";
    name = "anno-1404-gold-edition.7z";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # Anno4.exe / Addon.exe is a D3D10 game (`strings` shows D3D10CreateDevice,
  # D3DX10CreateEffectFromMemory) with d3d9 only used for the launcher and
  # font/texture helpers. The water surface goes through the D3D10 effects
  # framework, which on a Proton prefix means Wine's builtin d3dx10_40.dll
  # — a partial reimplementation. The engine's water .fxo loads, the shader
  # compiles to *something*, but the linked technique passes don't bind the
  # planar-reflection RT and screen-space-refraction sampler the engine
  # expects, so the water surface samples uninitialised memory and draws
  # solid black. Ship Microsoft's native d3dx10_40.dll + D3DCompiler_40.dll
  # (both bundled in the same Nov 2008 cab) and the d3dx9_40.dll
  # the launcher pulls in, all out of the Jun 2010 redist.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anno-1404";

  ipfsSources = [ src ];

  src = pkgs.runCommandLocal "anno-1404-data" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p "$out"
    7z x -o"$out" ${src}
    mv "$out/Anno 1404 - Gold Edition/"* "$out/"
    rmdir "$out/Anno 1404 - Gold Edition"
  '';

  nativeBuildInputs = [ cabextract ];

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
    chmod -R u+w "$out"

    # Two-stage cabextract: outer SFX cabinet -> per-version cab, then
    # inner cab -> the actual DLL. nov2008_d3dx10_40_x86.cab bundles both
    # d3dx10_40.dll and D3DCompiler_40.dll; nov2008_d3dx9_40_x86.cab has
    # d3dx9_40.dll. Drop all three next to Addon.exe; the WINEDLLOVERRIDES
    # below pin the loader to native instead of Wine's stubs.
    mkdir -p "$TMPDIR/dx"
    cabextract -L -d "$TMPDIR/dx" \
      -F 'nov2008_d3dx10_40_x86.cab' \
      -F 'nov2008_d3dx9_40_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx10_40.dll' \
      "$TMPDIR/dx/nov2008_d3dx10_40_x86.cab"
    cabextract -L -d "$TMPDIR/dx" -F 'D3DCompiler_40.dll' \
      "$TMPDIR/dx/nov2008_d3dx10_40_x86.cab"
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx9_40.dll' \
      "$TMPDIR/dx/nov2008_d3dx9_40_x86.cab"
    # cabextract -L lowercases extracted filenames.
    install -m0644 "$TMPDIR/dx/d3dx10_40.dll" "$out/d3dx10_40.dll"
    install -m0644 "$TMPDIR/dx/d3dcompiler_40.dll" "$out/d3dcompiler_40.dll"
    install -m0644 "$TMPDIR/dx/d3dx9_40.dll" "$out/d3dx9_40.dll"
  '';

  runtime = "proton";
  # Addon.exe is the Gold Edition entry point (base game + Venice expansion).
  executable = "Addon.exe";

  saveLocations = [ "AppData/Roaming/Ubisoft/Anno1404Addon" ];

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
    SteamAppId = "0";
    SteamGameId = "0";
    PROTONFIXES_DISABLE = "1";
    DXVK_ASYNC = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Pin the three D3DX helpers to the native (Microsoft) DLLs we ship
    # next to Addon.exe. Wine's d3dx10/d3dx9/d3dcompiler builtins are
    # partial stubs and Anno's water effect doesn't render through them.
    WINEDLLOVERRIDES = "d3dx10_40,d3dx9_40,d3dcompiler_40=n,b";
  };

  meta = {
    description = "Anno 1404 Gold Edition (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anno-1404";
  };
}
