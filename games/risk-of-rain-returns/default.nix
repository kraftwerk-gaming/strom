{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Risk of Rain Returns (Hopoo Games / Gearbox 2023, GameMaker Studio 2).
  # Windows-only Steam release; no native Linux build exists. Source is a
  # pre-installed v1.0.4 SteamUnlocked/TENOKE zip (tenoke.ini present)
  # uploaded to archive.org on 2024-01-02 (archive.org malware-checked).
  # Includes a Goldberg-style steam_api64.dll stub so the game runs without
  # a Steam client. Runs under Proton (GE-Proton).
  #
  # Zip double-nests the game: outer wrapper dir contains a _Redist folder
  # (Windows redistributables, not needed) and the inner game dir which holds
  # Risk of Rain Returns.exe, data.win, and all .ogg music files.
  src = fetchIpfs {
    cid = "QmNiTVVP7VDELisTdURfps3UitHddSLPQ45RLj63whApd7";
    fallbackUrl = "https://archive.org/download/risk.of.-rain.-returns.v-1.0.4/Risk.of.Rain.Returns.v1.0.4.zip";
    hash = "sha256-W/74h6eey84pL6F6L0xvhA22lKFfdQZPr4vd9GV11gg=";
    name = "Risk.of.Rain.Returns.v1.0.4.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "risk-of-rain-returns";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    # The zip double-nests the game data:
    #   Risk.of.Rain.Returns.v1.0.4/               ← outer wrapper
    #     _Redist/                                  ← Windows redistributables (skip)
    #     HOW TO RUN GAME!!.txt                     ← skip
    #     STEAMUNLOCKED...url                       ← skip
    #     Risk.of.Rain.Returns.v1.0.4/              ← inner game dir
    #       Risk of Rain Returns.exe
    #       data.win, steam_api64.dll, ...
    # Flatten the inner game dir directly into $out.
    inner="$TMPDIR/extract/Risk.of.Rain.Returns.v1.0.4/Risk.of.Rain.Returns.v1.0.4"
    cp -r "$inner"/. "$out"/
  '';

  runtime = "proton";

  executable = "Risk of Rain Returns.exe";

  # GMS2 writes local save data to %LOCALAPPDATA%\Risk_of_Rain_Returns
  # (PCGamingWiki). The Steam-cloud path (userdata/1337520/remote/save.json)
  # is not used with the bundled Goldberg emu; the engine falls back to the
  # local AppData path. Preserving this across prefix wipes keeps unlocks and
  # run history.
  saveLocations = [ "AppData/Local/Risk_of_Rain_Returns" ];

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
    description = "Risk of Rain Returns (Hopoo Games / Gearbox 2023, GameMaker Studio 2 Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risk-of-rain-returns";
  };
}
