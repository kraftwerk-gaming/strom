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
    cid = "QmXZ7mW2peZtDmdY4SWqKXHMUyqEZje7if6kjanHe6gCLY";
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

  saveLocations = [ "Documents/Command and Conquer Generals Data" ];

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

  # First-run registry seeding. The Generals launcher reads its install
  # location and metadata from HKLM\Software\Electronic Arts\EA Games\Generals
  # (InstallPath, Language, UserDataLeafName, MapPackVersion, Version, plus the
  # ergc serial). Without these the engine cannot locate its install tree and
  # exits. generals.exe is 32-bit, so on the win64 prefix its HKLM\Software
  # reads redirect to Software\Wow6432Node; the keys are written to BOTH views.
  #
  # These are appended directly as Wine registry text (no regedit / PROTON_RUN,
  # which is not exported at preRun time). proton creates the prefix on first
  # launch, so on a truly fresh prefix system.reg does not exist yet and that
  # first launch comes up without the keys; they land on the next launch once
  # proton has bootstrapped the prefix, and persist. WINEPATH is the in-prefix
  # Z: path mapping to the fuse-overlayfs $GAMEDIR (doubled backslashes, with a
  # trailing backslash, the convention the Generals launcher expects).
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    DOCS="$STROM_COMPATDATA/0/pfx/drive_c/users/steamuser/Documents"
    SEED="$GAMEDIR/_seed/Command and Conquer Generals Data"

    if [ -f "$SYSREG" ] \
        && ! grep -q 'EA Games\\\\Generals' "$SYSREG"; then
      echo "[strom] first-run setup: seeding install registry"
      WINEPATH="Z:''${GAMEDIR//\//\\\\}\\\\"
      TS=$(date +%s)
      for base in \
        'Software\\Electronic Arts\\EA Games\\Generals' \
        'Software\\Wow6432Node\\Electronic Arts\\EA Games\\Generals'; do
        {
          printf '\n[%s] %s\n' "$base" "$TS"
          printf '"Language"="english"\n'
          printf '"InstallPath"="%s"\n' "$WINEPATH"
          printf '"MapPackVersion"=dword:00010000\n'
          printf '"Version"=dword:00010007\n'
          printf '"UserDataLeafName"="Command and Conquer Generals Data"\n'
          printf '\n[%s\\\\ergc] %s\n' "$base" "$TS"
          printf '@="5412001460717777331746"\n'
        } >>"$SYSREG"
      done
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
    # binkw32 (bink video) and mss32 (Miles Sound System) must be native;
    # wine's stub mss32 crashes after the post-mission stats screen.
    # d3d8 comes from DXVK (bundled GenTool d3d8.dll dropped in buildScript).
    WINEDLLOVERRIDES = "binkw32=n,b;mss32=n,b";
  };

  meta = {
    description = "Command & Conquer: Generals (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-generals";
  };
}
