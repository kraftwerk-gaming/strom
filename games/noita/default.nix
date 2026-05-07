{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmRhHG2AMa5Q2GpJeBnSzcFDoFEVXShFoR8CKvFFQ8jRxD";
    fallbackUrl = "https://archive.org/download/Noita/Noita.zip";
    hash = "sha256-PirtPxVKCeLBAJpg50A5hV+P0S3f40QMH8NXZPH/zBs=";
    name = "noita-gog-1.0.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "noita";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/noita"
    cp -r "$TMPDIR/noita/Noita"/. "$out"/
  '';

  runtime = "proton";
  executable = "noita.exe";

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

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Noita (GOG v1.0, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "noita";
  };
}
