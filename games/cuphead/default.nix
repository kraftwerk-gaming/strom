{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  innoextract,
}:

let
  src = fetchIpfs {
    cid = "QmNjJThUd5NxEAY7LSYXjDjLZjwdZdUa6hDhGLFds8Zxm9";
    fallbackUrl = "https://archive.org/download/cuphead-legacy-gog.-7z/Cuphead%20Legacy%20GOG.7z";
    hash = "sha256-4V4+Af3HWgMLcQ2Q6Sp3BSSaQsRx6mvUiA5YPRYmUlo=";
    name = "cuphead-legacy-gog-2017-09-29.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cuphead";

  inherit src;

  nativeBuildInputs = [
    p7zip
    innoextract
  ];

  # Cuphead Legacy GOG 7z holds a two-part GOG installer (.exe + .bin
  # slice). Extract the 7z, then innoextract the .exe (which uses the
  # adjacent .bin slice) into the GOG layout.
  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/7z"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/7z/Cuphead Legacy GOG/setup_cuphead_20170929_(15295).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    rm -rf "$out/__redist" "$out/__support" "$out/webcache.zip"
  '';

  runtime = "proton";
  executable = "Cuphead.exe";

  saveLocations = [ "AppData/Roaming/Cuphead" ];

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
    description = "Cuphead Legacy (Studio MDHR, GOG 2017-09-29 v15295, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cuphead";
  };
}
