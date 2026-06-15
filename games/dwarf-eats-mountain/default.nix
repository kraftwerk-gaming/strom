{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # SteamRIP pre-installed build 23312961. RAR5 archive whose top level
  # holds a "Dwarf Eat Mountain" folder (repack typo) next to the
  # _CommonRedist installers and a SteamRIP .url. The game itself is a
  # GameMaker title (data.win + Dwarf Eats Mountain.exe), already cracked
  # with gbe_fork: steam_api64.dll is the emulator, steam_api64.BAK the
  # original, and steam_settings/ + steam_appid.txt (4078200) ship the
  # offline config, so no further Goldberg swap is needed.
  src = fetchIpfs {
    cid = "QmYJrkgroH1NRewj7X8aJA3oq2tFGfamZP2YBUkxTuKZdh";
    fallbackUrl = "";
    hash = "sha256-ZyHpPlYTOhysUlZGiYWO9Ahl+CcxAAaiDSPYwX7NAi4=";
    name = "dwarf-eats-mountain-steamrip.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dwarf-eats-mountain";

  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/"Dwarf Eat Mountain"/* "$out"/
  '';

  runtime = "proton";
  executable = "Dwarf Eats Mountain.exe";

  # GameMaker writes its save under %LOCALAPPDATA%\Mountain_Eaters (the
  # internal project name, confirmed by the "C:\Users\USER\AppData\Local\
  # Mountain_Eat..." and literal "Mountain_Eaters" strings in data.win),
  # not under the display name.
  saveLocations = [ "AppData/Local/Mountain_Eaters" ];

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
    description = "Dwarf Eats Mountain (Green Wizard 2026, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dwarf-eats-mountain";
  };
}
