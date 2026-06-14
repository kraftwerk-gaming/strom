{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # AnkerGames pre-installed build of Rune Dice (Smart Raven Studio, Steam
  # app 3542380, Unity IL2CPP / Steamworks.NET). The zip already ships a
  # cracked steam_api64.dll (steam_emu.ini + steam_api64.dll.valve backup
  # of the Valve original alongside), so it runs offline without further
  # emu intervention. The AnkerGames download is gated behind a temporary
  # IP-bound signed proxy URL, so there is no stable fallbackUrl; IPFS-only
  # once the CID is pinned.
  src = fetchIpfs {
    cid = "QmWto77kLwyysUAQTGbQadxQj4uTZmctZjA8yyNxJGp5E2";
    fallbackUrl = "";
    hash = "sha256-UIju75UV8AD/CJV0m/s7ix6JDrKB8SKsgQ7QH/kNm+E=";
    name = "rune-dice-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rune-dice";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # AnkerGames zip layout: Rune Dice/Rune Dice.exe + Rune Dice_Data/ +
  # GameAssembly.dll + bundled steam_api64.dll. Drop the AnkerGames advert
  # shortcut and the redistributable installers we don't run under Proton.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Rune Dice/"* "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
  '';

  runtime = "proton";
  executable = "Rune Dice.exe";

  saveLocations = [ "AppData/LocalLow/Smart Raven Studio/Rune Dice" ];

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
    description = "Rune Dice (Smart Raven Studio 2026, dice roguelike deckbuilder, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rune-dice";
  };
}
