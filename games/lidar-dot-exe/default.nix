{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # LiDAR Exploration Program (KenForest 2025), the full release that grew out
  # of the free LIDAR.EXE itch.io prototype. Build 18028959 repack: the Steam
  # DRM is already neutralised with a gbe_fork/Goldberg steam_api.dll plus a
  # populated steam_settings/ (the genuine dll is kept as steam_api.dll.bak),
  # so the game starts offline without any further swap. fallbackUrl points at
  # the canonical itch.io page; the source is pinned to IPFS (cid above).
  src = fetchIpfs {
    cid = "QmQn77sU6sU4MNZJfKQUQHX7Xmd641d8dZN9hpJdL5ZpND";
    fallbackUrl = "https://kenforest.itch.io/lidar-exe";
    hash = "sha256-35BgrSSh6Sf+KZNvaCW3ibw/g8u/MNOJ142LYwxRG/I=";
    name = "LiDAR.Exploration.Program.Build.18028959.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lidar-dot-exe";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Single wrapper folder at the zip root; flatten it into $out.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d /tmp/lep
    mv /tmp/lep/LiDAR.Exploration.Program.Build.18028959/* "$out"/
  '';

  runtime = "proton";

  executable = "LEP.exe";

  # Unity persistentDataPath; company/product taken from LEP_Data/app.info
  # ("KenForest" / "LEP").
  saveLocations = [ "AppData/LocalLow/KenForest/LEP" ];

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
    description = "LiDAR Exploration Program (KenForest 2025, first-person LIDAR-scanner horror, Unity via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lidar-dot-exe";
  };
}
