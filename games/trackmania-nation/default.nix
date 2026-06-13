{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
  innoextract,
  cabextract,
}:

let
  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # TmForever.exe imports d3dx9_30.dll (the Apr-2006 DirectX SDK D3DX helper)
  # and drives the in-game scene through the D3DX shader/effect path: its
  # import table pulls in D3DXCompileShader, D3DXAssembleShader,
  # D3DXGetShaderConstantTable and D3DXCreateTextureFromFileInMemoryEx. Wine's
  # builtin d3dx9 ships only a STUB shader compiler (D3DXCompileShader logs
  # "stub" and returns failure), so under Proton the road, stadium and terrain
  # shaders silently fail to compile and those surfaces render as flat black
  # silhouettes -- while the sky/clouds (drawn without those .fx shaders)
  # render fine. The bug is therefore backend-independent: it reproduces under
  # both DXVK and PROTON_USE_WINED3D because both forward the same failed D3DX
  # calls. Ship the real Microsoft d3dx9_30.dll and force-load it native. Same
  # class of fix as age-of-empires-iii (d3dx9_25) and
  # lego-star-wars-the-complete-saga (d3dx9_35); the winetricks d3dx9_30 verb
  # installs this exact DLL.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
  # TrackMania Nations Forever (Nadeo / Ubisoft, 2008) — the free, ad-funded
  # standalone Stadium-environment release of TrackMania. No online login is
  # required to reach the menu and play the solo/offline campaign.
  #
  # Source: archive.org "TrackMania Nations Forever" item, a 7z wrapping the
  # official Inno Setup installer `TmNationsForever_setup.exe` (v1.0.0.1, the
  # last full build). innoextract unpacks it into `app/`; `TmForever.exe` is
  # the game proper (the bundled TmForeverLauncher.exe is only a patch/config
  # front-end and is not needed to reach the menu).
  src = fetchIpfs {
    cid = "QmcnK2Y7DwFsc8Fc3kWkuAWHTMs8gPCcBEE2GP3KSQHbuc";
    fallbackUrl = "https://archive.org/download/trackmania-nations-forever/TrackMania%20Nations%20Forever.7z";
    hash = "sha256-h9h3pa1dbFIKcmnvWFiHHad3OOgAmRyRnTrgFF55vl4=";
    name = "trackmania-nations-forever.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "trackmania-nation";

  inherit src;

  nativeBuildInputs = [
    p7zip
    innoextract
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"

    # 7z wraps the Inno Setup installer exe; unpack that first.
    7z x "$src" -o"$PWD/installer"
    innoextract -d "$PWD/extract" "$PWD/installer/TmNationsForever_setup.exe"

    # Game tree lives under `app/`; the installer's DirectX/redist payload
    # under `tmp/` is irrelevant under Proton (dxvk provides d3d9).
    mv "$PWD/extract/app"/* "$out"/

    # Two-stage cabextract of the native 32-bit d3dx9_30.dll from the June 2010
    # DirectX redist (outer SFX cabinet -> apr2006_d3dx9_30_x86.cab ->
    # d3dx9_30.dll). Dropped next to TmForever.exe at the game root; the
    # WINEDLLOVERRIDES below binds it native so the D3DX shader compiler that
    # the engine drives its road/stadium/terrain shaders through is the real
    # Microsoft implementation rather than Wine's stub. See the directxJun2010
    # comment for why.
    cabextract -L -d "$PWD/dx" -F 'apr2006_d3dx9_30_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$PWD/dx" -F 'd3dx9_30.dll' \
      "$PWD/dx/apr2006_d3dx9_30_x86.cab"
    install -m0644 "$PWD/dx/d3dx9_30.dll" "$out/d3dx9_30.dll"
  '';

  runtime = "proton";
  executable = "TmForever.exe";

  env = {
    # Bind the native d3dx9_30.dll shipped next to TmForever.exe (n = native
    # first, b = fall back to builtin) so the engine's D3DX shader compiler is
    # the real Microsoft implementation. Without this, Wine's builtin d3dx9
    # stubs D3DXCompileShader and every road/stadium/terrain shader fails to
    # compile, leaving those surfaces black while the sky renders fine. See the
    # directxJun2010 comment for the import-table evidence.
    WINEDLLOVERRIDES = "d3dx9_30=n,b";
  };

  # Profiles, custom tracks and medal/score data live in Documents/TrackMania.
  saveLocations = [ "Documents/TrackMania" ];

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
    description = "TrackMania Nations Forever (Nadeo, free, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "trackmania-nation";
  };
}
