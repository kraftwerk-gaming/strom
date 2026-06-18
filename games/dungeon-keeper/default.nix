{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
  p7zip,
  unzip,
}:

let

  originalData = fetchIpfs {
    cid = "Qmez7AYzB1fAm129WEkUafvBnshvSfM5hPozpjQcZV8m3y";
    fallbackUrl = "https://archive.org/download/msdos_Dungeon_Keeper_1997/Dungeon_Keeper_1997.zip";
    hash = "sha256-7/DKaLonPKI6uH0a0vwesqM4d4AGIvoC2/ZPVRnFXJo=";
    name = "dk1-original.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dungeon-keeper";

  ipfsSources = [ originalData ];
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

  copyGlobs = [ ];

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # save/*.sav + settings.dat next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "keeperfx.exe";
  env = {
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # KeeperFX writes saves into save/ next to its binary; create it before
  # launch so the first save doesn't fail on a missing directory. (The
  # framework supplies the outer gamescope nest and a dedicated DXVK state
  # cache, so neither is set here.)
  preRun = ''
    mkdir -p "$GAMEDIR/save"
  '';

  meta = {
    description = "Dungeon Keeper (KeeperFX, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-keeper";
  };
}
