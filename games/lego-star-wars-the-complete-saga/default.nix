{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  cabextract,
}:

let
  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # LEGOStarWarsSaga.exe imports d3dx9_35.dll (the Aug-2007 DirectX SDK
  # D3DX helper) directly in its IAT and loads every surface texture via
  # the D3DXCreateTextureFromFileInMemory family -- the engine ships no
  # loose texture files, the DDS bitmaps are appended inside the CHARS/ and
  # LEVELS/ GHG model containers and decoded at runtime by D3DX. Wine's
  # builtin d3dx9_NN (one shared dlls/d3dx9_36 source compiled into every
  # version) only partially implements that DDS-from-memory path, so under
  # Proton the texture loads silently return failure: geometry rasterises
  # but every surface stays untextured (flat/black), which earlier looked
  # like a brightness problem but is actually missing textures. Ship the
  # real Microsoft d3dx9_35.dll out of the standard redist (the same DLL
  # winetricks's `d3dx9_35` verb installs) and force-load it native.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };

  # LEGO Star Wars: The Complete Saga (TT Games / LucasArts, 2007 console
  # / 2009 PC re-release; PC build originally released as a SecuROM-7.40
  # protected retail DVD and later as a Steamworks build that was delisted
  # from Steam in April 2023 over expiring Disney/Lucasfilm licensing).
  # Neither edition is available for purchase any more; the official PC
  # build is de-facto abandonware.
  #
  # Bytes sourced from the community "Modern Overhaul" bundle on
  # archive.org (KnightLemon, 2024). The bundle ships the cracked retail
  # game directory (LEGOStarWarsSaga.exe + binkw32.dll + RELOADED rld.dll
  # no-DVD shim) with the engine-level mods layered in place: HD textures,
  # high-poly character meshes, restored unused content, the
  # "Modernizer"-style speed/animation/AI fixes, and assorted bug patches
  # the original engine never received. The crack is what lets the game
  # run at all outside of a physical retail DVD or a logged-in Steam
  # client; the Steam DRM check is gone with the executable rewrite.
  src = fetchIpfs {
    cid = "Qmd5fuTDVghgvRrbJnqSPyA2QEWXGed2B8nrBKdip6qjY9";
    fallbackUrl = "https://archive.org/download/lego-star-wars-the-complete-saga-modern-overhaul/Lego%20Star%20Wars%20The%20Complete%20Saga%20Modern%20Overhaul.zip";
    hash = "sha256-74X2coVz3DJlxGwPxHlqvp+Q/gaqILZXtUceX3LOfHg=";
    name = "lego-star-wars-the-complete-saga-modern-overhaul.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lego-star-wars-the-complete-saga";

  inherit src;

  nativeBuildInputs = [
    unzip
    cabextract
  ];

  # Zip wraps the install in a single top-level directory ("Lego Star
  # Wars The Complete Saga Modern Overhaul/") containing the executable
  # plus the engine asset trees (Audio/, CHARS/, CUT/, LEVELS/, Movies/,
  # PC/, SCRIPTS/, STUFF/) and the cracked DLLs. Strip the wrapper so
  # LEGOStarWarsSaga.exe sits at the overlay root.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/Lego Star Wars The Complete Saga Modern Overhaul"/. "$out"/
    test -f "$out/LEGOStarWarsSaga.exe" \
      || { echo "LEGOStarWarsSaga.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/rld.dll" \
      || { echo "rld.dll (RELOADED no-DVD shim) missing -- the retail exe will hit the SecuROM check and bail" >&2; exit 1; }

    # Two-stage cabextract of the native 32-bit d3dx9_35.dll from the
    # June 2010 DirectX redist (outer SFX cabinet -> aug2007_d3dx9_35_x86.cab
    # -> d3dx9_35.dll). Dropped next to the exe; WINEDLLOVERRIDES below binds
    # it native so the texture loads stop falling through Wine's incomplete
    # builtin. See the directxJun2010 comment for why.
    cabextract -L -d "$TMPDIR/dx" -F 'aug2007_d3dx9_35_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx9_35.dll' \
      "$TMPDIR/dx/aug2007_d3dx9_35_x86.cab"
    install -m0644 "$TMPDIR/dx/d3dx9_35.dll" "$out/d3dx9_35.dll"
  '';

  runtime = "proton";
  executable = "LEGOStarWarsSaga.exe";

  # Bind the native d3dx9_35.dll shipped into the overlay (n = native first,
  # b = fall back to builtin) so the engine's D3DX DDS texture decoding works
  # under Proton. Without this, surfaces render untextured. binkw32.dll has
  # no Wine builtin, so the loader picks the bundled native copy on its own
  # and needs no override.
  env = {
    WINEDLLOVERRIDES = "d3dx9_35=n,b";
  };

  # TT Games' 2007-era engine writes profiles, saves, and per-character
  # unlock state under My Documents/LEGO Star Wars The Complete Saga/
  # (the same path the retail Windows installer registers as
  # %USERPROFILE%\Documents\<game>). Relocate so wineprefix wipes don't
  # take save progress with them. Verify on the first interactive run.
  saveLocations = [ "Documents/LEGO Star Wars The Complete Saga" ];

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
    description = "LEGO Star Wars: The Complete Saga (Traveller's Tales / LucasArts 2007/2009, Modern Overhaul community bundle, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lego-star-wars-the-complete-saga";
  };
}
