{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  innoextract,
  cabextract,
}:

let
  # Hearts of Iron III and DLC Collection (2009 Paradox, GOG offline
  # installer, single-part Inno Setup v2.0.0.1). The archive.org zip wraps
  # one directory holding setup_hearts_of_iron_iii_2.0.0.1.exe. innoextract
  # --gog decodes the installer into the standard GOG "app/" layout: the
  # game tree (hoi3game.exe + hoi3.exe launcher, common/, gfx/, map/,
  # events/, history/, mod/, tfh/ and dh expansion data, etc.) sits under
  # app/, with installer bootstrap debris under tmp/.
  src = fetchIpfs {
    cid = "QmPKVTdXA7KrboCe9aK4GGKv2SjFpct8z9x7RDPcmVX7HM";
    fallbackUrl = "https://archive.org/download/hearts-of-iron-iii/Hearts%20of%20Iron%20III.zip";
    hash = "sha256-/SNTXZLm1fmWxKVIe0IiK0MOwKGqe91agndYuUu6TCI=";
    name = "hearts-of-iron-iii.zip";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # hoi3game.exe imports d3dx9_35.dll (the Aug-2007 DirectX SDK D3DX helper)
  # and loads its gfx/FX/*.fx effects via D3DXCreateEffectFromFile. Wine's
  # builtin d3dx9_35 delegates fx compilation to its vkd3d-based
  # d3dcompiler, whose HLSL backend cannot compile the legacy fx_2_0 shader
  # framework (aborts on "Writing fx_2_0 sampler objects initializers" and
  # "Write pass assignments" -- not implemented). D3DXCreateEffectFromFile
  # then returns NULL and the engine null-derefs the effect while "Loading
  # Map-Sprites" (access violation at hoi3game+0x95713e, `movl (%edi),%esi`).
  # Microsoft's native d3dx9_35.dll implements the fx_2_0 effect compiler
  # in-process, so shipping it (32-bit, out of the Jun 2010 redist) next to
  # hoi3game.exe and pinning it native (WINEDLLOVERRIDES below) makes the
  # effects compile and the game reaches its menu. Same fix shape as
  # age-of-empires-iii (d3dx9_25).
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hearts-of-iron-iii";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/Hearts.of.Iron.III.and.DLC.Collection-GOG/setup_hearts_of_iron_iii_2.0.0.1.exe"
    # The GOG "app/" subtree is the install root; tmp/ is installer debris.
    cp -r "$TMPDIR/iss/app"/. "$out"/
    # GOG Galaxy / installer cruft not needed at runtime.
    rm -rf "$out/__redist" "$out/commonappdata" "$out/webcache.zip"
    chmod -R u+w "$out"

    # Two-stage cabextract: outer SFX cabinet -> aug2007_d3dx9_35_x86.cab
    # -> d3dx9_35.dll. Dropped next to hoi3game.exe; the WINEDLLOVERRIDES
    # below binds it native so the D3DX fx_2_0 effect compiler works.
    mkdir -p "$TMPDIR/dx"
    cabextract -L -d "$TMPDIR/dx" -F 'aug2007_d3dx9_35_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx9_35.dll' \
      "$TMPDIR/dx/aug2007_d3dx9_35_x86.cab"
    # cabextract -L lowercases extracted filenames.
    install -m0644 "$TMPDIR/dx/d3dx9_35.dll" "$out/d3dx9_35.dll"
  '';

  runtime = "proton";

  # hoi3game.exe is the actual game binary. hoi3.exe is the 120 KB HTML
  # (launcher.html) Paradox launcher, which is unreliable under headless
  # gamescope+Proton; launching the game binary directly starts the base
  # game with the DLC enabled in settings.txt.
  executable = "hoi3game.exe";

  # HoI3 (Clausewitz engine) writes savegames, mods, logs and settings
  # under Documents/Paradox Interactive/Hearts of Iron III/. Relocate it
  # so user progress survives wineprefix wipes.
  saveLocations = [ "Documents/Paradox Interactive/Hearts of Iron III" ];

  env = {
    # Pin d3dx9_35 to the native Microsoft DLL shipped next to hoi3game.exe
    # (see directxJun2010 above). Wine's builtin d3dx9_35 can't compile
    # HoI3's fx_2_0 effects, which otherwise crashes the engine during
    # map-sprite load.
    WINEDLLOVERRIDES = "d3dx9_35=n,b";
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
    description = "Hearts of Iron III (2009 Paradox, GOG + DLC Collection, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hearts-of-iron-iii";
  };
}
