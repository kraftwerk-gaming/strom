{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # SteamGG.NET pre-installed Dungeon Clawler v1.0 / Build-22864793 (Stray
  # Fawn Studio 2025), a claw-machine deckbuilder roguelike. Unity Mono
  # build (UnityPlayer.dll + DungeonClawler_Data/Managed/*.dll), links
  # Steamworks.NET (com.rlabrecque.steamworks.net.dll). The repack ships a
  # RUNE Steam emulator (Plugins/x86_64/steam_api64.dll + steam_api64.rne +
  # steam_emu.ini, AppId=2356780) in place of the retail steam_api64.dll,
  # so the game runs offline without a Steam client.
  #
  # Source: repack-games.com links a pixeldrain mirror that exposes a
  # stable direct-download API URL (no JS token / countdown / captcha),
  # unlike the gofile/megadb primaries - that's the fallbackUrl below.
  src = fetchIpfs {
    cid = "QmS2f4TY3LxxZVoJnDKMzAg4AP9nzryhotTjDwPe3ZnNa6";
    fallbackUrl = "https://pixeldrain.com/api/file/oAwpi9v5";
    hash = "sha256-nt6bJmlAfHD3bsb2OcN5zso+R6kInE6Nswu73aIS1bM=";
    name = "dungeon-clawler.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dungeon-clawler";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # The zip wraps everything in a single top-level dir
  # ("Dungeon Clawler - SteamGG.NET/"). Strip it so DungeonClawler.exe
  # sits at the root next to UnityPlayer.dll, DungeonClawler_Data/, and
  # the D3D12/ Agility-SDK subdir. The SteamGG advert .url shortcut has a
  # non-UTF8 en-dash in its filename that makes unzip exit non-zero, so
  # exclude it at extraction time (-x) rather than deleting it after.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" -x "*.url"
    cp -r "$TMPDIR/extract/Dungeon Clawler - SteamGG.NET/." "$out"/
    test -f "$out/DungeonClawler.exe" \
      || { echo "DungeonClawler.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/DungeonClawler_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (RUNE emu) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "DungeonClawler.exe";

  # Unity Mono writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\, with
  # companyName/productName read from DungeonClawler_Data/app.info
  # ("Stray Fawn Studio" / "Dungeon Clawler", verified out of the zip).
  saveLocations = [ "AppData/LocalLow/Stray Fawn Studio/Dungeon Clawler" ];

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
    # Match the Steam appid the RUNE emu shim expects (steam_emu.ini).
    SteamAppId = "2356780";
    SteamGameId = "2356780";
  };

  meta = {
    description = "Dungeon Clawler (Stray Fawn Studio 2025, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-clawler";
  };
}
