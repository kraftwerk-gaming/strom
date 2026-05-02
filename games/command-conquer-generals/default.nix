{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let

  # Portable pre-installed English version with Generals + Zero Hour.
  # We only ship the base Generals install here; Zero Hour will be a
  # separate package using the same source.
  gameSrc = fetchIpfs {
    # TODO: pin on the pin host and replace with real CID
    cid = "bafkREPLACEME";
    fallbackUrl = "https://archive.org/download/zerohour.7z/zerohour.7z";
    hash = "sha256-S6aTqXYrIDh4kcOfzFjpaCeT/DeU5TSg+9WoFx8BGcQ=";
    name = "generals-zh-portable.7z";
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "command-conquer-generals";

  src = gameSrc;

  nativeBuildInputs = [ p7zip ];

  runtime = "proton";

  buildScript = ''
    mkdir -p "$out"

    7z x ${gameSrc} -o/tmp/gen -aoa \
      "Command and Conquer Generals/*" \
      "Command and Conquer Generals Data/*"

    cp -r "/tmp/gen/Command and Conquer Generals/"* "$out/"

    # Drop the bundled d3d8.dll (GenTool wrapper). It crashes under modern
    # Proton/DXVK; let DXVK provide d3d8 itself.
    rm -f "$out/d3d8.dll" "$out/D3D8.dll"

    # Ship the seed user-data dir alongside the install so preRun can
    # copy it into the prefix's Documents on first run.
    mkdir -p "$out/_seed"
    cp -r "/tmp/gen/Command and Conquer Generals Data" "$out/_seed/"

    # Default to 1080p to match gamescope output.
    sed -i 's|^Resolution = .*|Resolution = 1920 1080|' \
      "$out/_seed/Command and Conquer Generals Data/options.ini"

    rm -rf /tmp/gen

    # Lowercase DLL symlinks for case-sensitive lookups
    cd "$out"
    for f in *.dll *.DLL; do
      [ -f "$f" ] || continue
      lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
      [ "$f" != "$lower" ] && [ ! -e "$lower" ] && ln -s "$f" "$lower"
    done

    chmod -R u+w "$out"
  '';

  # User-modifiable game data lives in Documents inside the prefix,
  # which is part of compatdata, not GAMEDIR. Nothing to persist via
  # copyGlobs for the install tree itself.
  copyGlobs = [ ];

  executable = "generals.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    # Generals' edge-scroll is mouse-position-based. Without grab,
    # gamescope's cursor mapping during fast motion produces jumpy/
    # phantom edge events.
    flags."--force-grab-cursor" = true;
  };

  preRun = ''
    SYSREG="$COMPATDATA/pfx/system.reg"
    DOCS="$COMPATDATA/pfx/drive_c/users/steamuser/Documents"
    SEED="$GAMEDIR/_seed/Command and Conquer Generals Data"

    if ! grep -q 'EA Games\\\\Generals' "$SYSREG" 2>/dev/null; then
      echo "[strom] first-run setup: importing registry"
      REGFILE="$COMPATDATA/install.reg"
      WINEPATH="Z:$(echo "$GAMEDIR" | sed 's|/|\\\\|g')\\\\"
      python3 -c 'import sys; sys.stdout.write(open(sys.argv[1]).read().replace("@WINEPATH@", sys.argv[2]))' \
        ${./install.reg.template} "$WINEPATH" > "$REGFILE"
      # Run proton in a new session so its postHook 'kill -9 0' does not
      # kill this preRun shell.
      setsid -w "$PROTON_RUN" regedit /S "$REGFILE" || true
      sleep 2
    fi

    if [ ! -d "$DOCS/Command and Conquer Generals Data" ] && [ -d "$SEED" ]; then
      echo "[strom] first-run setup: seeding user data"
      mkdir -p "$DOCS"
      cp -r "$SEED" "$DOCS/"
      chmod -R u+w "$DOCS/Command and Conquer Generals Data"
    fi
  '';

  env = {
    STAGING_WRITECOPY = "1";
    # binkw32 must be native for movie playback. d3d8 comes from DXVK
    # (the bundled GenTool d3d8.dll is dropped in buildScript).
    WINEDLLOVERRIDES = "binkw32=n,b";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Command & Conquer: Generals (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-generals";
  };
}
