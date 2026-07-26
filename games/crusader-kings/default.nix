{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  # Crusader Kings: Complete (2004 Paradox; the "Complete" edition bundles
  # the base game patched to 1.05 plus the Deus Vult expansion -- the
  # config/deus_vult.csv payload confirms the expansion is present). The
  # archive.org item is a zip wrapping a GOG offline Inno Setup installer
  # (setup_crusader_kings_complete_2.1.0.2.exe) plus a _Redist/ folder of
  # VC/DX/XNA runtimes we don't need. innoextract --gog yields the game
  # tree under app/ with Crusaders.exe at its root. DRM-free (GOG).
  src = fetchIpfs {
    cid = "QmaD2KfHgiPRRMYZwgE68CPrDVQ7bcBEbZo126JH9YqaWP";
    fallbackUrl = "https://archive.org/download/crusader.-kings.-complete/Crusader.Kings.Complete.zip";
    hash = "sha256-jVu65ArAzqGrPqpg5gkv47NXmOyg2YArVKB4ZJkrPrg=";
    name = "crusader-kings.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "crusader-kings";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/Crusader.Kings.Complete/setup_crusader_kings_complete_2.1.0.2.exe"
    # --gog keeps the installer's app/ prefix; that dir is the game root
    # (Crusaders.exe + db/ gfx/ map/ scenarios/ config/ ...).
    cp -r "$TMPDIR/iss/app"/. "$out"/
    # GOG Galaxy support + installer debris: not needed to run the game.
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.hashdb "$out"/goggame-*.ico \
      "$out"/goggame-*.info "$out"/goggame_ati.sdb "$out"/GameuxInstallHelper.dll
  '';

  runtime = "proton";
  executable = "Crusaders.exe";

  # Clausewitz-era Paradox titles (CK1/EU2/HoI2/Vic1) write savegames next
  # to the binary, into the game's own scenarios/save games/ directory
  # (settings.txt lives there too). Under strom that directory is the
  # read-write fuse-overlay whose upper is $STROM_GAMEDIR/.strom-overlay
  # (persistent across prefix wipes), so nothing needs relocating out of
  # the disposable wineprefix -- saves survive in the overlay upper.
  saveLocations = [ ];

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
    description = "Crusader Kings: Complete (2004 Paradox, base 1.05 + Deus Vult, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "crusader-kings";
  };
}
