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
  executable = "game.exe";

  runScript = ''
    export LD_LIBRARY_PATH="/usr/lib32''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export WINEDLLOVERRIDES="ddraw=n,b"
    export PROTON_USE_WINED3D="1"

    # First run: let Ra2.exe (launcher) set up registry and serial,
    # then use game.exe directly on subsequent runs.
    SYSREG="$COMPATDATA/pfx/system.reg"
    if [ ! -f "$SYSREG" ] || ! grep -q 'Westwood' "$SYSREG"; then
      # Run Ra2.exe once to initialize - it creates prefix and sets registry
      gamescope -W 800 -H 600 -- "$PROTON_RUN" "$GAMEDIR/Ra2.exe" 2>/dev/null || true
      sleep 5
    fi

    gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --force-grab-cursor -- \
      "$PROTON_RUN" "$GAMEDIR/game.exe" -speedcontrol
  '';

  env = {
    STAGING_WRITECOPY = "1";
  };

  meta = {
    description = "Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-red-alert-2";
  };
}
