{
  callPackage,
  lib,
  pkgs,
  fetchurl,
  p7zip,
  unzip,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
  proton = callPackage ../../lib/patched-proton.nix { };

  originalData = fetchurl {
    url = "https://archive.org/download/msdos_Dungeon_Keeper_1997/Dungeon_Keeper_1997.zip";
    hash = "sha256-7/DKaLonPKI6uH0a0vwesqM4d4AGIvoC2/ZPVRnFXJo=";
    name = "dk1-original.zip";
  };
in
mkGame {
  name = "dungeon-keeper";

  src = fetchurl {
    url = "https://github.com/dkfans/keeperfx/releases/download/v1.3.1/keeperfx_1_3_1_complete.7z";
    hash = "sha256-j61vNUnRpp0bhpa1I0x8SuzEzDNBhwMz79GNiBzmYoo=";
    name = "keeperfx.7z";
  };

  nativeBuildInputs = [
    p7zip
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    7z x $src -o"$out"

    # Extract original DK data and overlay with lowercase names
    unzip -o ${originalData} -d /tmp/dk1

    copy_lower() {
      local src="$1" dst="$2"
      mkdir -p "$dst"
      for f in "$src"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        lower="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
        if [ -d "$f" ]; then
          copy_lower "$f" "$dst/$lower"
        elif [ ! -e "$dst/$lower" ]; then
          cp "$f" "$dst/$lower"
        fi
      done
    }

    for dir in DATA LDATA SOUND LEVELS; do
      if [ -d "/tmp/dk1/dungkeep/$dir" ]; then
        lower="$(echo "$dir" | tr '[:upper:]' '[:lower:]')"
        copy_lower "/tmp/dk1/dungkeep/$dir" "$out/$lower"
      fi
    done
  '';

  copyGlobs = [
    "save/"
    "*.cfg"
    "*.ini"
    "*.log"
  ];

  runtime = "proton";

  env = {
    PROTON_NO_GAME_FIXES = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    DXVK_ASYNC = "1";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  runScript = ''
    mkdir -p "$GAMEDIR/save"
    export DXVK_STATE_CACHE_PATH="$GAMEDIR"

    gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/keeperfx.exe"
  '';

  meta = {
    description = "Dungeon Keeper (KeeperFX, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-keeper";
  };
}
