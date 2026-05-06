{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmcSQfYfra3Scgmj9drWygX4GgVEoVpMCxQibH8JUzCvue";
    fallbackUrl = "";
    hash = "sha256-Q8utMPSDnDcl6NnC/S88vzMsvhIEzzQ5pA2y48O7bAc=";
    name = "getting-over-it-with-bennett-foddy.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "getting-over-it-with-bennett-foddy";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # Standard unzip can't handle this archive (294/316 files use a
  # compression method it doesn't support); 7z handles it cleanly.
  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/goi"
    cp -r "$TMPDIR/goi/Getting Over It with Bennett Foddy"/. "$out"/
  '';

  runtime = "proton";
  executable = "GettingOverIt.exe";

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
  };

  meta = {
    description = "Getting Over It with Bennett Foddy (Unity, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "getting-over-it-with-bennett-foddy";
  };
}
