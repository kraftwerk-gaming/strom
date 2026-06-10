{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Nidhogg (Messhof 2014) Windows build from SteamRIP / Skidrow&Reloaded,
  # v7341652 (Steam depot build). GameMaker Studio engine: Nidhogg.exe +
  # data.win + sfx/music .ogg files. 152 MB zip. Steam API stub
  # (steam_api.dll) is present but Steamworks is a soft dependency; the
  # game runs offline fine (no SteamAPI_Init check that fails hard).
  # No native Linux build exists (Steam app 94400 is Windows-only).
  src = fetchIpfs {
    cid = "QmXpnfHL8bphczGSpi1m8JkNeJTcgH7KNEju6Bm9LAJxXP";
    fallbackUrl = "https://pixeldrain.com/api/file/DStFUEn1?download";
    hash = "sha256-9TjMfcluKdTd57rTPyoKuPyzxNUOG1zmC4cvd4TYxeE=";
    name = "nidhogg-v7341652.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "nidhogg";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Nidhogg.v7341652/." "$out"/
  '';

  runtime = "proton";
  executable = "Nidhogg.exe";

  # GameMaker Studio saves to %LOCALAPPDATA%\messhof\ (drive_c/users/
  # steamuser/AppData/Local/messhof) for options and match history.
  saveLocations = [ "AppData/Local/messhof" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Nidhogg (Messhof 2014 fencing game, v7341652, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "nidhogg";
  };
}
