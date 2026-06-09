{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
}:

let
  # gbe_fork: drop-in steam_api64.dll replacement that fakes SteamAPI_Init
  # and ISteamFriends. The bundled Goldberg v8.33.9.23 returns a null
  # ISteamFriends pointer, causing Amplitude's Bootloader.Start() to crash
  # with a Marshal.PtrToStringAnsi(0) access violation before the main menu.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };

  src = fetchIpfs {
    cid = "QmVoD5P94HyrKAjz4vRAZCujtfgUc3NiPSvE4b7dKhvkGZ";
    fallbackUrl = "https://pixeldrain.com/api/file/rKaBqGzV?download";
    hash = "sha256-73Rx8PyxzgRbw6+WBPuNmOLTlCWsbkZxsJru7+SfvNM=";
    name = "endless-legend.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "endless-legend";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
        mkdir -p "$out"
        7z x -y "$src" -o"$TMPDIR/7z"
        cp -r "$TMPDIR/7z/Endless.Legend.Build.19641020"/. "$out"/
        chmod -R u+w "$out"

        # Replace bundled Goldberg (v8.33.9.23) with gbe_fork. The old build
        # returns a null ISteamFriends causing an access violation in
        # Amplitude's Bootloader before the main menu loads.
        mkdir -p "$TMPDIR/goldberg"
        7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
        cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
          "$out/steam_api64.dll"

        # steam_api_dotnetwrapper64.dll was compiled against the Steam SDK that
        # shipped ISteamFriends015 / SteamUser018 / SteamClient017. gbe_fork
        # defaults to the latest interfaces (018+), causing vtable mismatches
        # where GetFriendPersonaName hits the wrong slot and returns 1 instead
        # of a const char*, crashing Marshal.PtrToStringAnsi. Lock the
        # interfaces to the versions the game's own Goldberg reported.
        cat > "$out/steam_interfaces.txt" <<'EOF'
    SteamClient017
    SteamGameServer012
    SteamGameServerStats001
    SteamUser018
    SteamFriends015
    SteamUtils007
    SteamMatchMaking009
    SteamMatchMakingServers002
    STEAMUSERSTATS_INTERFACE_VERSION011
    STEAMAPPS_INTERFACE_VERSION007
    SteamNetworking005
    STEAMREMOTESTORAGE_INTERFACE_VERSION012
    STEAMSCREENSHOTS_INTERFACE_VERSION002
    STEAMHTTP_INTERFACE_VERSION002
    STEAMUNIFIEDMESSAGES_INTERFACE_VERSION001
    STEAMCONTROLLER_INTERFACE_VERSION
    STEAMUGC_INTERFACE_VERSION007
    STEAMAPPLIST_INTERFACE_VERSION001
    STEAMMUSIC_INTERFACE_VERSION001
    STEAMMUSICREMOTE_INTERFACE_VERSION001
    STEAMHTMLSURFACE_INTERFACE_VERSION_003
    STEAMINVENTORY_INTERFACE_V001
    STEAMVIDEO_INTERFACE_V001
    EOF
  '';

  runtime = "proton";
  executable = "EndlessLegend.exe";
  # Skip the embedded news/store WebView that hangs under Proton.
  executableArgs = [ "-useembedded" ];

  # Saves are ZIPs under Documents/Endless Legend/Save Files; settings
  # live alongside under the same Documents/Endless Legend tree. Relocate
  # the whole folder so progress survives wineprefix wipes.
  saveLocations = [ "Documents/Endless Legend" ];

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
    description = "Endless Legend (Amplitude Studios 2014, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "endless-legend";
  };
}
