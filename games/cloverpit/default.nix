{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmPre6GqGGi4WDoWLEn5PdTX1jNuWPqx7vVFMNMAeoc6n5";
    fallbackUrl = "https://ipfs.io/ipfs/QmPre6GqGGi4WDoWLEn5PdTX1jNuWPqx7vVFMNMAeoc6n5";
    hash = "sha256-hoTRiJirYfd+wiHj1pfuZAf7XyrvJ91HTlLfNY2sNV8=";
    name = "cloverpit-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cloverpit";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # AnkerGames zip layout: CloverPit/CloverPit.exe + CloverPit_Data/ +
  # MonoBleedingEdge/ + bundled steam_api64.dll. Drop the AnkerGames
  # advert URL shortcut.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/CloverPit/"* "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
  '';

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/Panik Arcade/CloverPit" ];
  executable = "CloverPit.exe";

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
    description = "Cloverpit (Panik Arcade 2025, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cloverpit";
  };
}
