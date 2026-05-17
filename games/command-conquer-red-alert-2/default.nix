{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
  p7zip,
  unzip,
  writeText,
}:

let

  # Portable pre-installed English version with RA2 + Yuri's Revenge
  gameSrc = fetchIpfs {
    cid = "QmeuAn5K7qBARybPwJhKLyF7ziGEbNgcAVkJ6vKMopKj1F";
    fallbackUrl = "https://archive.org/download/command-and-conquer-red-alert-2-v-2.0.-7z/Command%20and%20Conquer%20Red%20Alert%202%20%28v2.0%29.7z";
    hash = "sha256-WJ3pL868aPxc2yonyIMLdNRXZyDklV4GZT+P1GXIrAM=";
    name = "ra2-portable.7z";
  };

  # cnc-ddraw for DirectDraw compatibility
  cncDdraw = fetchurl {
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-CxOriaZMmRgYmx2t1EnvbtPLO3sZyr2W2K29lVBbuQg=";
    name = "cnc-ddraw.zip";
  };

  ddrawIni = writeText "ddraw.ini" ''
    [ddraw]
    renderer=opengl
    windowed=true
    fullscreen=false
    maintas=true
    adjmouse=true
    handlemouse=true
    maxfps=60
    singlecpu=true
    nonexclusive=true
  '';

  setupRegistry = ./setup-registry.sh;
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "command-conquer-red-alert-2";

  src = gameSrc;

  nativeBuildInputs = [
    p7zip
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"

    # Extract game data (skip ISOs and extras)
    7z x ${gameSrc} -o/tmp/ra2 -aoa
    cp -r "/tmp/ra2/Command and Conquer Red Alert 2/Game/"* "$out/"
    rm -rf /tmp/ra2

    # Replace bundled aqrit ddraw with cnc-ddraw
    unzip -o ${cncDdraw} ddraw.dll -d "$out/"
    cp ${ddrawIni} "$out/ddraw.ini"

    # Fix case-sensitivity: game.exe imports lowercase DLL names
    # but archive has uppercase. Create lowercase symlinks.
    cd "$out"
    for f in *.DLL; do
      lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
      if [ "$f" != "$lower" ] && [ ! -e "$lower" ]; then
        ln -s "$f" "$lower"
      fi
    done
    cd -

    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # *.SAV + ra2.ini next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  # Ra2.exe is the official Westwood launcher (Play / Yuri's Revenge /
  # Quit menu). game.exe and gamemd.exe crash on the current proton at
  # startup before opening a window; the launcher route works.
  executable = "Ra2.exe";

  env = {
    # cnc-ddraw replaces wine's built-in ddraw; force native-then-builtin.
    WINEDLLOVERRIDES = "ddraw=n,b";
    STAGING_WRITECOPY = "1";
  };

  # Seed Westwood\Red Alert 2 + Yuri's Revenge registry keys directly so
  # the launcher doesn't prompt for a serial. Runs once after proton has
  # bootstrapped the prefix.
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -q 'Westwood\\\\Red Alert 2' "$SYSREG"; then
      sh ${setupRegistry} "$SYSREG" "$GAMEDIR"
    fi
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--force-grab-cursor" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-red-alert-2";
  };
}
