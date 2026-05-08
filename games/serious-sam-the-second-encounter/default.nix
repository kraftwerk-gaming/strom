{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Croteam's 2002 retail Serious Sam: The Second Encounter, repacked
  # as a portable zip with the v1.07 patch + GameSpy-replacement
  # binaries already applied. Drop-in install — no setup.exe to run.
  src = fetchIpfs {
    cid = "Qmc1kVGaJCmJRAXEY1jPvXrTvsPFUZWG54th4fqpfY1TF9";
    fallbackUrl = "https://archive.org/download/serious-sam-the-second-encounter_202512/Serious%20Sam%20-%20The%20Second%20Encounter.zip";
    hash = "sha256-p9ywAgrUAZeRRhWWwMPC0n7n0AVoWdo0nQ/1LS/GbVo=";
    name = "serious-sam-the-second-encounter.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "serious-sam-the-second-encounter";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/Serious Sam - The Second Encounter"/. "$out"/
    chmod -R u+w "$out"
    # Seed PersistentSymbols.ini with a 1920x1080 fullscreen default.
    # The engine writes back to this file on every save, so user
    # changes from the in-game options menu (when they don't crash the
    # engine — switching modes mid-run sometimes does) persist.
    cat > "$out/Scripts/PersistentSymbols.ini" <<'EOF'
    persistent extern INDEX sam_iScreenSizeI=(INDEX)1920;
    persistent extern INDEX sam_iScreenSizeJ=(INDEX)1080;
    persistent extern INDEX sam_iDisplayDepth=(INDEX)0;
    persistent extern INDEX sam_iWindowMode=(INDEX)0;
    persistent extern INDEX sam_iGfxAPI=(INDEX)0;
    EOF
  '';

  copyGlobs = [
    "Scripts/PersistentSymbols.ini"
    "ControlsConfig/"
    "SaveGame/"
  ];

  runtime = "proton";
  executable = "Bin/SeriousSam.exe";

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
    description = "Serious Sam: The Second Encounter (Croteam 2002, retail v1.07, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "serious-sam-the-second-encounter";
  };
}
