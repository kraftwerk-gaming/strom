{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  p7zip,
}:

let
  # The Talos Principle: Gold Edition (Croteam / Devolver Digital, 2014).
  # Serious Engine 4 puzzle game. Windows-only on GOG (GOG API reports
  # linux=false for this product); the native Linux build is Steam-only
  # (depots 257513/257514). Runtime = "proton".
  #
  # SOURCE: PROPHET scene release of the GOG offline installer, build 41435
  # (v1.0), 64-bit Windows. Archived at archive.org as The Talos Principle.7z
  # (6851995595 bytes; identifier the-talos-principle). The 7z wraps a single
  # UDF disc image (The Talos Principle.iso, ~6.4 GB) which contains the GOG
  # InnoSetup multi-part installer:
  #   setup.exe          (867 KB) - InnoSetup launcher header
  #   setup-1.bin       (~4 GB)  - primary data chunk
  #   setup-2.bin       (~2.4 GB) - secondary data chunk
  #
  # innoextract --gog on setup.exe (with .bin files alongside) drops the
  # install tree at the extraction ROOT (not under app/):
  #   Bin/x64/          <- game binaries (Talos.exe, DLLs)
  #   Content/          <- Serious Engine .gro content archives
  #   app/              <- GOG Galaxy metadata only (webcache.zip, goggame.ico)
  #   tmp/              <- installer bootstrap images (skip)
  #   commonappdata/    <- GOG support installer (skip)
  #
  # Exe: Bin/x64/Talos.exe (64-bit Serious Engine 4 binary).
  # Saves: %LOCALAPPDATA%\Talos\ (drive_c/users/steamuser/AppData/Local/Talos).
  src = fetchIpfs {
    cid = "PENDING_UPLOAD";
    fallbackUrl = "https://archive.org/download/the-talos-principle/The%20Talos%20Principle.7z";
    hash = "sha256-Qp3N3Sq3nL4aYvKGinvLHECNmho7sQKxszmP8Zgf4JM=";
    name = "the-talos-principle-gog-41435.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-talos-principle";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    innoextract
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iso" "$TMPDIR/installer" "$TMPDIR/iss"

    # The source 7z wraps a single UDF ISO (The Talos Principle.iso).
    # Unpack the 7z to get the ISO, then unpack the ISO to get the GOG
    # InnoSetup multi-part installer (setup.exe + setup-1.bin + setup-2.bin).
    7z x "$src" -o"$TMPDIR/iso" -y
    iso=$(find "$TMPDIR/iso" -name '*.iso' | head -1)

    # Extract the three installer files from the UDF ISO image into the
    # same directory so innoextract can find the .bin chunks alongside
    # the .exe header.
    7z e -y "$iso" -o"$TMPDIR/installer" "setup.exe" "setup-1.bin" "setup-2.bin"

    # innoextract --gog assembles the .exe header + .bin chunks. For this
    # Gold Edition installer, game data (Bin/, Content/, Support/, …) lands
    # at the extraction ROOT, while GOG metadata lives under app/ (app/
    # holds only webcache.zip + goggame-*.ico).
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/installer/setup.exe"

    # Copy the root tree (game data); skip the app/ subdirectory (GOG-only
    # metadata) and installer bootstrap directories.
    mkdir -p "$out"
    find "$TMPDIR/iss" -maxdepth 1 -mindepth 1 \
      ! -name app \
      ! -name tmp \
      ! -name __redist \
      ! -name __support \
      ! -name commonappdata \
      -exec cp -r {} "$out"/ \;
    chmod -R u+w "$out"

    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico
  '';

  runtime = "proton";

  # 64-bit Serious Engine 4 binary.
  executable = "Bin/x64/Talos.exe";

  # Force the Vulkan renderer at engine init via the command line. The
  # renderer is chosen by the STRING cvar gfx_strAPI ("VLK"), NOT the
  # const int gfx_iAPI -- writing gfx_iAPI errors ("Attempted to write to
  # a const variable"), which is why both a +gfx_iAPI arg and Croteam's
  # own SafeMode.cfg fail and the engine falls back to D3D11 (GfxD3D11.dll,
  # which then crashes under DXVK). Talos.exe's error text confirms the
  # mechanism: "Wrong graphics API selected; going with default. (See
  # 'gfx_strAPI' console variable.)". The command-line +cvar is applied
  # during init before the API locks, so it pins Vulkan before any D3D
  # path runs. seed-usercfg.sh also persists it in UserCfg.lua.
  executableArgs = [
    "+gfx_strAPI"
    "VLK"
  ];

  # Saves land under %LOCALAPPDATA%\Talos\ on Windows.
  # drive_c/users/steamuser/AppData/Local/Talos inside the wineprefix.
  saveLocations = [ "AppData/Local/Talos" ];

  # Persist the Vulkan renderer and clear the stale safe-mode marker
  # before launch. The engine reads UserCfg.lua from its working directory
  # (the strom overlay root = $STROM_GAMEDIR), NOT from %LOCALAPPDATA%, so
  # seed the root UserCfg.lua there. seed-usercfg.sh also removes the
  # leftover Temp/run.txt startup marker that a prior D3D11 crash leaves
  # behind (it would otherwise re-trigger the safe-mode dialog). See
  # seed-usercfg.sh for the full rationale.
  preRun = ''
    sh ${./seed-usercfg.sh} "$STROM_GAMEDIR"
  '';

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

  meta = {
    description = "The Talos Principle: Gold Edition (Croteam 2014, Serious Engine 4, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-talos-principle";
  };
}
