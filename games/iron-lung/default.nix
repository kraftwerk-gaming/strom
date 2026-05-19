{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Iron Lung (David Szymanski 2022): claustrophobic underwater horror
  # in a Unity 2018 build. The archive.org item ships the full Steam
  # build tree (Iron Lung/Iron Lung.exe + Iron Lung_Data/ + Mono
  # runtime) plus the item's own metadata XMLs / thumbnail images at
  # the zip root, which we strip during install.
  src = fetchIpfs {
    cid = "QmY5gwRVK9HpnG5mufRmDPK7cx9bxgGPx7xPz2MnTsq9RE";
    fallbackUrl = "https://archive.org/compress/iron-lung_202404";
    hash = "sha256-QTjU8yRodpSVc5fh5CveNxPK0436ITV0mMo6ACEsnfo=";
    name = "iron-lung_202404.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "iron-lung";

  ipfsSources = [ src ];

  src =
    pkgs.runCommandLocal "iron-lung-data"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -q ${src} -d "$TMPDIR/x"
        cp -r "$TMPDIR/x/Iron Lung/." "$out"/
      '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "Iron Lung.exe";

  # Iron Lung saves to AppData/LocalLow per the Unity convention.
  saveLocations = [ "AppData/LocalLow/David Szymanski/Iron Lung" ];

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
    description = "Iron Lung (David Szymanski 2022, Unity 2018 horror via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "iron-lung";
  };
}
