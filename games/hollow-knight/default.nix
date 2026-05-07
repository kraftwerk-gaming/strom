{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmZL7FnWxJ7qk1mrrine4wT8TeShT2RAoiEYpFaBjTY4t6";
    fallbackUrl = "https://archive.org/download/hollow-knight.-7z/Hollow-Knight.7z";
    hash = "sha256-9VFQn//i/d8lrL6R4SbWQ2Tunb0FII9GZD/QUiNv8OI=";
    name = "hollow-knight-1.5.78.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hollow-knight";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/hk"
    cp -r "$TMPDIR/hk/Hollow Knight v1.5.78.11833"/. "$out"/
  '';

  runtime = "proton";
  executable = "Hollow Knight.exe";

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
    description = "Hollow Knight (Unity, GOG v1.5.78, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hollow-knight";
  };
}
