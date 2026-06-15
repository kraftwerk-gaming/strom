{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Samurai Gunn (Teknopants / Maxistentialism, 2013) — the original
  # lightning-fast local-versus Bushido brawler (Steam app 239090), NOT
  # Samurai Gunn 2. GameMaker: Studio engine: SamuraiGunn.exe + a 290 MB
  # data.win bundle, plus SDL.dll / joydll.dll / D3DX9_43.dll and a
  # community steam_api.dll stub. Steamworks is a soft dependency — the
  # GameMaker Steam extension logs a failed init and continues, so the
  # game runs offline and reaches the main menu without a Steam client.
  # No native Linux build exists, so runtime = "proton".
  #
  # SOURCE: STEAMUNLOCKED pre-installed build (Samurai.Gunn.zip, 269 MB),
  # mirrored on uploadhaven. Outer zip layout:
  #   Samurai.Gunn/Samurai.Gunn/SamuraiGunn.exe + data.win + *.dll + *.ogg
  #   Samurai.Gunn/_Redist/   (vcredist / dotnet / xna / openal installers)
  #   Samurai.Gunn/*.txt|*.url (installer cruft)
  # The _Redist runtimes are unnecessary under Proton (it bundles its own
  # CRT / d3d / OpenAL stack); we ship only the inner game tree.
  src = fetchIpfs {
    cid = "QmY91zCdfq89VwWnfSdziBofhEL8wHeyzV2exY2BndtGWs";
    fallbackUrl = "";
    hash = "sha256-RboJAEsLGP26DjB4j/lC1m0cvnHmWI15pYO6f4RP4l8=";
    name = "samurai-gunn.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "samurai-gunn";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Samurai.Gunn/Samurai.Gunn/." "$out"/
  '';

  runtime = "proton";
  executable = "SamuraiGunn.exe";

  # GameMaker: Studio writes its options / unlocks to
  # %LOCALAPPDATA%\SamuraiGunn (drive_c/users/steamuser/AppData/Local/
  # SamuraiGunn under Proton). Verify the exact dir name on first launch.
  saveLocations = [ "AppData/Local/SamuraiGunn" ];

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
    description = "Samurai Gunn (Teknopants 2013, GameMaker local-versus brawler, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "samurai-gunn";
  };
}
