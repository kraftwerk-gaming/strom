{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Sun Haven (Pixel Sprout Studios 2023) is a Unity farming RPG, Windows
  # only (no native Linux build) -> runtime = "proton".
  #
  # No official DRM-free build exists: the game is Steam-only (not on GOG;
  # only a GOG Dreamlist). The DRM-free source is a GoldBerg-cracked Steam
  # build (repack), shipped as a single archive whose top-level folder is
  # "Sun Haven/" holding "Sun Haven.exe" + "Sun Haven_Data/" +
  # MonoBleedingEdge/ + bundled steam_api64.dll (plain Unity Mono layout).
  #
  # Skidrow repack of Sun Haven v3.0.2 (Build 21250750); pixeldrain mirror
  # kept as the genuinely-different fallback source.
  src = fetchIpfs {
    cid = "QmY8oHub4D9nTTUtPBEyt8qGPfhQAFYRSDQFDpFynwAw3u";
    fallbackUrl = "https://pixeldrain.com/api/file/96sKSrLY";
    hash = "sha256-TMiCflqXTc7wuhdPRGuqgwju3WC9PTV7K+cLCfJYjDQ=";
    name = "sun-haven.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sun-haven";

  inherit src;

  nativeBuildInputs = [ unar ];

  # Repack layout (Skidrow v3.0.2 zip): Sun.Haven.v3.0.2/{Sun Haven.exe,
  # Sun Haven_Data/,MonoBleedingEdge/,steam_api64.dll,*.mp3,...}. unar
  # handles zip archives; copy the versioned folder's contents to $out and
  # drop the OST mp3s and burst-debug folder which are not needed at runtime.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/Sun.Haven.v3.0.2/. "$out"/
    rm -f "$out/"*.mp3 "$out/"*.txt
    rm -rf "$out/Sun Haven_BurstDebugInformation_DoNotShip"
  '';

  runtime = "proton";

  # Unity persistentDataPath: %USERPROFILE%/AppData/LocalLow/<company>/
  # <product>. Confirmed save tree (Saves/ + Backups/) under
  # "Pixel Sprout Studios/Sun Haven".
  saveLocations = [ "AppData/LocalLow/Pixel Sprout Studios/Sun Haven" ];
  executable = "Sun Haven.exe";

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
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Sun Haven (Pixel Sprout Studios 2023, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sun-haven";
  };
}
