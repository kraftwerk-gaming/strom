{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # Boomerang Fu (Cranky Watermelon, 2020). Frantic couch-PvP physics party
  # game built on Unity. Windows / Switch / Xbox / PS only — the developer
  # confirms there is NO native Linux build and points Linux players at
  # Proton, so runtime = "proton".
  #
  # SOURCE: SKIDROW repack "Boomerang.Fu.Build.20430461" (pixeldrain mirror
  # via repack-games). A wrapper zip containing an Inno Setup 5.5 installer
  # (setup.exe + setup-1.bin) plus a `crack/` overlay (gbe_fork Goldberg
  # steam_api64.dll + steam_settings/). innoextract yields the standard
  # Unity `app/` layout: "Boomerang Fu.exe" + "Boomerang Fu_Data/" +
  # UnityPlayer.dll. The crack's steam_api64.dll replaces the retail stub
  # so the game starts without a running Steam client.
  src = fetchIpfs {
    cid = "QmPDpQsXaTKKiKpRzQhpWVbJCKpH9keJb7waC8saMywMg3";
    fallbackUrl = "https://pixeldrain.com/api/file/2LCVyNhu?download";
    hash = "sha256-TZCPbqHn6MYevWOc9cEuqB+2kefLBBVTraCQiFvMoaA=";
    name = "Boomerang.Fu.Build.20430461.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "boomerang-fu";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    repack="$TMPDIR/zip/Boomerang.Fu.Build.20430461"

    # Extract the Inno installer's game tree (lands under app/).
    innoextract -d "$TMPDIR/inno" "$repack/setup.exe"
    cp -a "$TMPDIR/inno/app"/. "$out"/

    # Overlay the gbe_fork Goldberg crack (steam_api64.dll + steam_settings)
    # over the retail Unity Plugins dir so the game runs without Steam.
    cp -a "$repack/crack/Boomerang Fu_Data"/. "$out/Boomerang Fu_Data"/

    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit.
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "Boomerang Fu.exe";

  # Unity LocalLow tree (company / product from app.info).
  saveLocations = [ "AppData/LocalLow/Cranky Watermelon/Boomerang Fu" ];

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
    description = "Boomerang Fu (Cranky Watermelon 2020, Unity couch-PvP party game, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "boomerang-fu";
  };
}
