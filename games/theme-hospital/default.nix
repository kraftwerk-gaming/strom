{
  self,
  lib,
  pkgs,
  fetchurl,
  unzip,
  corsix-th,
}:

let
  gameArchive = fetchurl {
    url = "https://archive.org/download/msdos_Theme_Hospital_1997/Theme_Hospital_1997.zip";
    hash = "sha256-3PIZC+eiWS0knH3PZAtlQgvRhrnwYzuR5JsiYa886Us=";
    name = "theme-hospital-original.zip";
  };

  gameData =
    pkgs.runCommandLocal "theme-hospital-data"
      { nativeBuildInputs = [ unzip ]; }
      ''
        mkdir -p $out
        unzip -o ${gameArchive} -d /tmp/th

        # CorsixTH expects the data directory with lowercase names
        copy_lower() {
          local src="$1" dst="$2"
          mkdir -p "$dst"
          for f in "$src"/*; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            lower="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
            if [ -d "$f" ]; then
              copy_lower "$f" "$dst/$lower"
            else
              cp "$f" "$dst/$lower"
            fi
          done
        }

        copy_lower /tmp/th/ThemHosp/HOSPITAL "$out"
      '';

  # Template with GAMEDIR placeholder, replaced at runtime
  configTemplate = pkgs.writeText "corsixth-config.txt" ''
    theme_hospital_install = [[GAMEDIR_PLACEHOLDER]]
    fullscreen = true
    width = 1920
    height = 1080
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "theme-hospital";

  src = gameData;
  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";

  executable = "${corsix-th}/bin/corsix-th";

  preRun = ''
    CFG_DIR="$STROM_GAMEDIR/.config/CorsixTH"
    mkdir -p "$CFG_DIR"
    CFG="$CFG_DIR/config.txt"

    if [ ! -f "$CFG" ]; then
      sed "s|GAMEDIR_PLACEHOLDER|$GAMEDIR|" ${configTemplate} > "$CFG"
    else
      sed -i "s|theme_hospital_install = .*|theme_hospital_install = [[$GAMEDIR]]|" "$CFG"
    fi

    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
  '';

  meta = {
    description = "Theme Hospital (via CorsixTH engine)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "theme-hospital";
  };
}
