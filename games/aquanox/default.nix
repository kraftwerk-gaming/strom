{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  src = fetchIpfs {
    cid = "QmdyH6yPQixyf5viA3ht3maMkdbU25n6r9QJPAmH9sgJJW";
    fallbackUrl = "https://archive.org/download/aqua-nox-1.18-19599-win-gog/AquaNox_1.18_%2819599%29_win_gog.zip";
    hash = "sha256-SaTbAgnUdQR3zcggWnbmd5Aesa6rXNw21FN6tGq7v/M=";
    name = "aquanox.zip";
  };

  # Cookie's SilentPatchAqua: ASI mod + dinput8 ASI-loader stub. Fixes
  # stuttery/dropped input when mice/keyboards with high polling rate
  # are used (the exact symptom that makes vanilla AquaNox unplayable
  # on Wine + modern hardware).
  silentpatch = fetchIpfs {
    cid = "QmPaDr75c1JLZq4Gcbce1hS1nUjEpbJ5L793kx8y7myTi4";
    fallbackUrl = "https://github.com/CookiePLMonster/SilentPatchAqua/releases/download/BUILD-2/SilentPatchAqua.zip";
    hash = "sha256-c0R3elY/6GSvma1AZLMwg02sWgfakIqfQ49/8Z1JU0g=";
    name = "silentpatch-aqua-build2.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "aquanox";

  ipfsSources = [
    src
    silentpatch
  ];
  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/AquaNox_1.18_(19599)_win_gog/setup_aquanox_1.18_(19599).exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata" "$out/app" "$out/wise"
    if [ -d "$out/__support" ]; then
      mv "$out/__support/AquaNox" "$out/_supportprofile"
      rm -rf "$out/__support"
    fi
    if [ -f "$out/_supportprofile/config_1_18.txt" ]; then
      sed -i \
        -e '/Name = "dsp_width"/,/^}/ s/Value = .*/Value = 1920/' \
        -e '/Name = "dsp_height"/,/^}/ s/Value = .*/Value = 1080/' \
        "$out/_supportprofile/config_1_18.txt"
    fi
    # Drop SilentPatchAqua next to Aqua.exe. The bundled dinput8.dll
    # is an ASI loader that forwards dinput8 calls AND loads
    # SilentPatchAqua.asi, which fixes high-polling-rate mouse drops.
    unzip -q -j ${silentpatch} dinput8.dll SilentPatchAqua.asi -d "$out"
  '';

  runtime = "proton";
  executable = "Aqua.exe";

  saveLocations = [ "AppData/Roaming/AquaNox" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Force relative mouse mode so gamescope sends pure deltas to
      # Xwayland; without this the absolute Wayland coordinates leak
      # through and the in-ship view spins on every micro-movement.
      "--force-grab-cursor" = true;
    };
  };

  env = {
    # Tell Wine to load the bundled dinput8.dll (which is the ASI
    # loader for SilentPatchAqua) before its built-in implementation.
    WINEDLLOVERRIDES = "dinput8=n,b";
  };

  # First-run registry seeding. AquaNox reads its install paths from
  # HKLM\Software\Massive Development\AquaNox\Installation (PathDat/PathExe);
  # without them the engine cannot locate its data and fails to start.
  #
  # Appended directly as Wine registry text (no regedit / PROTON_RUN, which is
  # not exported at preRun time). proton creates the prefix on first launch, so
  # on a truly fresh prefix system.reg does not exist yet and that first launch
  # comes up without the keys; they land on the next launch once proton has
  # bootstrapped the prefix, and persist. GAMEDIR_WIN is the in-prefix Z: path
  # mapping to the fuse-overlayfs $GAMEDIR. Aqua.exe is a 32-bit PE in a win64
  # prefix, so its HKLM\Software reads are redirected to Wow6432Node; the key is
  # written to both the plain and Wow6432Node views so it resolves regardless.
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    if [ -f "$SYSREG" ] \
        && ! grep -q 'Massive Development\\\\AquaNox\\\\Installation' "$SYSREG"; then
      echo "[strom] first-run setup: seeding AquaNox install-path registry"
      GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
      TS=$(date +%s)
      for base in \
        'Software\\Massive Development\\AquaNox\\Installation' \
        'Software\\Wow6432Node\\Massive Development\\AquaNox\\Installation'; do
        {
          printf '\n[%s] %s\n' "$base" "$TS"
          printf '"PathDat"="%s"\n' "$GAMEDIR_WIN"
          printf '"PathExe"="%s\\\\Aqua.exe"\n' "$GAMEDIR_WIN"
          printf '"Version"="1.18eoem"\n'
          printf '"Inst"="Yes"\n'
        } >>"$SYSREG"
      done
    fi

    appdata="$STROM_COMPATDATA/0/pfx/drive_c/users/steamuser/AppData/Roaming/AquaNox"
    if [ ! -f "$appdata/playerm.des" ] && [ -d "$GAMEDIR/_supportprofile" ]; then
      mkdir -p "$appdata"
      cp -n "$GAMEDIR/_supportprofile"/* "$appdata"/
    fi
  '';

  meta = {
    description = "AquaNox (2001 Massive Development, GOG v1.18 + SilentPatch, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "aquanox";
  };
}
