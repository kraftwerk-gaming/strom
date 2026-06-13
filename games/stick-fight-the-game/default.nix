{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
}:

let
  # gbe_fork: drop-in steam_api replacement that emulates SteamAPI_Init
  # offline. The repack ships a CreamAPI emulator (cream_api.ini +
  # steam_api_o.dll), but CreamAPI only unlocks DLC against a *live* Steam
  # client — with no Steam running under Proton its SteamAPI_Init returns
  # false and StickFight's Steamworks bootstrap (via CSteamworks.dll) never
  # reaches the main menu. StickFight.exe is 32-bit, so we need the regular
  # x86 build.
  gbeFork = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_30/emu-win-release.7z";
    hash = "sha256-ONDOgi949bIt0o2Uj0scmLxl9fw6hQt3dShnQ6YONRY=";
  };

  src = fetchIpfs {
    cid = "QmPUJ1qwyjKBw4B2NuSXqjy76VdARFzYWcwzeqRCBrbn1Z";
    fallbackUrl = "https://archive.org/download/stick.-fight.-the.-game.v-1.2.08.7z/Stick.Fight.The.Game.v1.2.08.7z";
    hash = "sha256-MJSow8r/PbSfkzES3iNQv4D/c7TAOR5nh9X2491hnBc=";
    name = "stick-fight-the-game.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stick-fight-the-game";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
        mkdir -p "$out"
        7z x -y "$src" -o"$TMPDIR/7z" > /dev/null
        cp -r "$TMPDIR/7z/Stick.Fight.The.Game.v23.11.2018"/. "$out"/
        chmod -R u+w "$out"

        # Drop the repack's human-facing readme.
        rm -f "$out/READ ME!.txt"

        # Swap the CreamAPI emulator for gbe_fork. The game loads the 32-bit
        # steam_api.dll through CSteamworks.dll; gbe_fork's regular x86 build
        # is a self-contained offline Steam emulator, so remove the CreamAPI
        # config and its original-dll backup that only matter to CreamAPI.
        7z x -bd -y -o"$TMPDIR/gbe" ${gbeFork} > /dev/null
        cp "$TMPDIR/gbe/release/regular/x86/steam_api.dll" \
          "$out/StickFight_Data/Plugins/steam_api.dll"
        rm -f "$out/StickFight_Data/Plugins/cream_api.ini" \
          "$out/StickFight_Data/Plugins/steam_api_o.dll"

        # AppId for gbe_fork's SteamAPI_Init. CSteamworks/steam_api read it
        # from steam_appid.txt next to the loaded dll (the Plugins dir) and,
        # as a fallback, the game root.
        echo 674940 > "$out/StickFight_Data/Plugins/steam_appid.txt"
        echo 674940 > "$out/steam_appid.txt"

        # Pin gbe_fork to the Steam SDK interface versions this 2017 build was
        # compiled against (extracted from the repack's steam_api_o.dll and
        # CSteamworks.dll). gbe_fork otherwise advertises only its newest
        # interfaces, and CSteamworks' QueryInterface for the older versions
        # returns null -> Steamworks init fails before the menu.
        cat > "$out/StickFight_Data/Plugins/steam_interfaces.txt" <<'EOF'
    SteamClient017
    SteamUser019
    SteamFriends015
    SteamUtils009
    SteamMatchMaking009
    SteamNetworking005
    SteamGameServer012
    SteamController005
    EOF
  '';

  runtime = "proton";
  executable = "StickFight.exe";

  # Unity 2017 writes prefs/logs under AppData/LocalLow/<Company>/<Product>.
  # Unity strips the ':' from the product name on disk. Keep this outside the
  # disposable wineprefix so settings survive prefix wipes.
  saveLocations = [
    "AppData/LocalLow/Landfall West/Stick Fight The Game"
    "AppData/LocalLow/Landfall West/Stick Fight_ The Game"
  ];

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
    description = "Stick Fight: The Game (Landfall 2017, physics brawler via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stick-fight-the-game";
  };
}
