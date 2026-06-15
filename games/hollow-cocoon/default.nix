{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  p7zip,
}:

let
  # Hollow Cocoon (Nayuta Studio / Gimar, 2023). 1980s J-horror; despite the
  # "Unreal" hint this is a Unity build -- the SteamGG repack ships the
  # standard Unity layout (Hollow Cocoon.exe + Hollow Cocoon_Data/ with
  # globalgamemanagers + MonoBleedingEdge/) under a single
  # `Hollow Cocoon - SteamGG.net/` wrapper dir. No installer. Steam app 2414630.
  src = fetchIpfs {
    cid = "QmRt3rQvc722RtpQAUDvK4HydgEtF4kst42a1zEX7YRvui";
    fallbackUrl = "https://pixeldrain.com/api/file/BCqg3Afy";
    hash = "sha256-7rbNsTz3tbd4MENkyLgS8BPKCmECRZg/1vvNGCpKeus=";
    name = "hollow-cocoon-steamgg.rar";
  };

  # gbe_fork (Goldberg fork): drop-in steam_api64.dll that fakes
  # SteamAPI_Init() without a running Steam client. Unity games linking
  # Steamworks.NET call SteamAPI.Init() at boot; under GE-Proton with no
  # Steam install that fails and the game quits before the menu. Static DLL
  # replacement, works under proton. Same vendored build as outer-wilds /
  # signalis (release-2026_04_25, x64 release/regular/x64/steam_api64.dll).
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hollow-cocoon";

  inherit src;

  nativeBuildInputs = [
    unar
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/x" "$src"
    # Locate the dir that actually holds the exe rather than guessing the
    # archive's nesting level with a glob.
    d=$(dirname "$(find "$TMPDIR/x" -name 'Hollow Cocoon.exe' -print -quit)")
    cp -r "$d"/. "$out"/
    chmod -R u+w "$out"

    # Swap the Valve steam_api64.dll for gbe_fork and point it at the Hollow
    # Cocoon appid. Steamworks.NET resolves steam_api64.dll from the EXE dir
    # (game root) first, then the Unity Plugins dir -- place it (and
    # steam_settings) in both so SteamAPI_Init hits Goldberg either way.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    gbdll="$TMPDIR/goldberg/release/regular/x64/steam_api64.dll"
    for plugins in "$out/Hollow Cocoon_Data/Plugins/x86_64" "$out"; do
      mkdir -p "$plugins"
      cp "$gbdll" "$plugins/steam_api64.dll"
      mkdir -p "$plugins/steam_settings"
      echo -n 2414630 > "$plugins/steam_settings/steam_appid.txt"
    done
    echo -n 2414630 > "$out/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "Hollow Cocoon.exe";

  env = {
    SteamAppId = "2414630";
    SteamGameId = "2414630";
  };

  # Unity writes saves to %USERPROFILE%\AppData\LocalLow\<Company>\<Product>.
  saveLocations = [ "AppData/LocalLow/Nayuta Studio/Hollow Cocoon" ];

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
    description = "Hollow Cocoon (Nayuta Studio 2023, Unity J-horror via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hollow-cocoon";
  };
}
