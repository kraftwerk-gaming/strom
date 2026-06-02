{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # The Floor is Jelly (Ian/Auren Snyder 2014, music by Disasterpeace).
  # No native Linux build exists; the game ships as a 32-bit Adobe AIR
  # desktop app with a bundled captive AIR runtime (Adobe AIR/Versions/
  # 1.0/Adobe AIR.dll), launched via jelly.exe -> jelly.swf. Runs under
  # Proton like any other Win32 app.
  src = fetchIpfs {
    cid = "QmR2g2EaFsJLXRW37mVgJyTXwD9KnXSH9PtJxUMG6dTRZB";
    fallbackUrl = "";
    hash = "sha256-sKZXz+43aPt3qztcdYVBeqq01uZg2A1pc4F+4wwwdZQ=";
    name = "the-floor-is-jelly.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-floor-is-jelly";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Single top-level "The.Floor.is.Jelly.v2018/" dir; drop the scene
  # release note so only the AIR app tree ships.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/tfij"
    cp -r "$TMPDIR/tfij"/*/. "$out"/
    rm -f "$out"/SKIDROWRELOADED.COM.txt
  '';

  runtime = "proton";
  executable = "jelly.exe";

  # Adobe AIR persists progress via File.applicationStorageDirectory,
  # which on Windows is %APPDATA%\<appID>\Local Store. The app id is
  # "jelly" (see META-INF/AIR/application.xml).
  saveLocations = [ "AppData/Roaming/jelly/Local Store" ];

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
    description = "The Floor is Jelly (Ian Snyder 2014, Adobe AIR / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-floor-is-jelly";
  };
}
