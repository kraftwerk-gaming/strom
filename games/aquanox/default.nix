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
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Tell Wine to load the bundled dinput8.dll (which is the ASI
    # loader for SilentPatchAqua) before its built-in implementation.
    WINEDLLOVERRIDES = "dinput8=n,b";
  };

  preRun = ''
    GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
    {
      cat <<'EOF'
    Windows Registry Editor Version 5.00

    [HKEY_LOCAL_MACHINE\Software\Massive Development\AquaNox\Installation]
    EOF
      printf '"PathDat"="%s"\n' "$GAMEDIR_WIN"
      printf '"PathExe"="%s\\\\Aqua.exe"\n' "$GAMEDIR_WIN"
      printf '"Version"="1.18eoem"\n'
      printf '"Inst"="Yes"\n'
    } > "$GAMEDIR/aquanox-install.reg"
    setsid "$PROTON_RUN" regedit /S "$GAMEDIR/aquanox-install.reg" || true

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
