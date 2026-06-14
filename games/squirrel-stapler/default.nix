{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Squirrel Stapler (David Szymanski / DreadXP 2021, v1.11): a short
  # low-poly Unity 2019 hunting-horror FPS. Windows-only, so
  # runtime = "proton". The archive.org item ships a single RAR with the
  # standard Unity layout (Squirrel Stapler.exe + Squirrel Stapler_Data/).
  # The repack has already swapped the Steamworks DLL for gbe_fork
  # (16 MB steam_api64.dll + steam_settings/, original kept as .bak), so
  # it runs offline without the SteamFriends AV.
  src = fetchIpfs {
    cid = "QmX8wwU4JhQRGVZ4WVWcJYn2xEjq3Hetod6jDcYKEaLqTX";
    fallbackUrl = "https://archive.org/download/squirrel-stapler/Squirrel%20Stapler.rar";
    hash = "sha256-Nmi+doPLGt5GBZH7ULbZ00vARx4JFhAMtz4UBqogT2I=";
    name = "squirrel-stapler.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "squirrel-stapler";

  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract/Squirrel Stapler"/. "$out"/
  '';

  runtime = "proton";
  executable = "Squirrel Stapler.exe";

  # Unity PlayerPrefs / save data land in
  # AppData/LocalLow/<company>/<product> (app.info: David Szymanski /
  # Squirrel Stapler).
  saveLocations = [ "AppData/LocalLow/David Szymanski/Squirrel Stapler" ];

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
    description = "Squirrel Stapler (David Szymanski / DreadXP 2021, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "squirrel-stapler";
  };
}
