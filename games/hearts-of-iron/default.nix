{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Hearts of Iron (2002 Paradox grand-strategy, Europa engine), GOG offline
  # installer (setup_hearts_of_iron_2.0.0.3.exe -- GOG build 2.0.0.3, the
  # English DRM-free release). innoextract --gog decodes it into the standard
  # GOG "app/" layout (HoI.exe + config/ db/ gfx/ map/ scenarios/ music/ ...).
  # This replaces the earlier Polish CD-Projekt disc, whose HoIENG.exe still
  # rendered a Polish UI; the GOG build is English throughout.
  src = fetchIpfs {
    cid = "QmXurtET5CQQMaz4QX72WbbhBt9wQcxAG3ydGqh2mXjeKh";
    fallbackUrl = "https://archive.org/download/setup_hearts_of_iron_2.0.0.3/setup_hearts_of_iron_2.0.0.3.exe";
    hash = "sha256-/BGYh0v5+g/SHOwhqasdRNMxnlAEEsBzrCV7p0WcxDY=";
    name = "hearts-of-iron.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hearts-of-iron";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    # The GOG "app/" subtree is the install root; tmp/ is installer debris.
    cp -r "$TMPDIR/iss/app"/. "$out"/
    # Strip GOG Galaxy / installer cruft not needed at runtime.
    rm -f "$out"/goggame-*.* "$out"/goggame.sdb "$out/GameuxInstallHelper.dll" \
      "$out"/Manual*.pdf "$out"/Readme*.txt 2>/dev/null || true
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  executable = "HoI.exe";

  # Europa-engine Hearts of Iron writes saved games and settings.cfg next
  # to its binary in the install dir (scenarios/save/*.eug), not under
  # drive_c/users/steamuser/... Those writes land in the per-game
  # fuse-overlayfs upper ($STROM_GAMEDIR/.strom-overlay/upper), which
  # survives wineprefix wipes, so no saveLocations are needed.
  saveLocations = [ ];

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
    description = "Hearts of Iron (2002 Paradox WWII grand-strategy, GOG English release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hearts-of-iron";
  };
}
