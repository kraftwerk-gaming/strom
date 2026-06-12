{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Ultimate Chicken Horse (Clever Endeavour Games, 2016). Unity party
  # platformer. Windows-only on Steam; no GOG release. Source is v1.13.13
  # repack from repack-games.com, hosted on pixeldrain (BzsMoX3a).
  # Zip layout: Ultimate.Chicken.Horse.v1.13.13/UltimateChickenHorse.exe
  # + UltimateChickenHorse_Data/ + steam_api64.dll (Goldberg).
  src = fetchIpfs {
    cid = "QmdtHMaEgNNfiLfXdrJPJMUSmerwhysKaoPkcbA2WuHkht";
    fallbackUrl = "https://pixeldrain.com/api/file/BzsMoX3a";
    hash = "sha256-Bv5wy+0G9wJO53qOD9ndweqdcaJyr0mVGQ3a3VHJ1EU=";
    name = "Ultimate.Chicken.Horse.v1.13.13.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "ultimate-chicken-horse";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/uch"
    cp -r "$TMPDIR/uch/Ultimate.Chicken.Horse.v1.13.13"/. "$out"/
  '';

  runtime = "proton";
  executable = "UltimateChickenHorse.exe";

  # Unity saves under AppData/LocalLow on Windows.
  saveLocations = [ "AppData/LocalLow/Clever Endeavour Games/Ultimate Chicken Horse" ];

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
    description = "Ultimate Chicken Horse (Clever Endeavour Games 2016, Windows v1.13.13, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ultimate-chicken-horse";
  };
}
