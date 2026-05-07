{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  innoextract,
  stdenv,
}:

let
  # US 2007 release of S.T.A.L.K.E.R.: Shadow of Chernobyl, multilingual
  # (en-es-fr-it) DVD. The 7z bundles a verbatim ISO containing an Inno
  # Setup .exe + setup-1{a,b,c}.bin slices that innoextract handles. The
  # default localisation depends on the registry value
  # HKCU\Software\GSC Game World\STALKER-SHOC\language; we set it to
  # "eng" in preRun so the menus come up in English.
  src = fetchIpfs {
    cid = "QmVgQiiHfuWyfj3nj1oDse9KrXJKMLrsqvoNFHQEfM3Gjg";
    fallbackUrl = "https://archive.org/download/s.t.a.l.k.e.r.-shadow-of-chernobyl-us-2007-win-1.0/DVD_DIC.7z";
    hash = "sha256-VmfhQ1HAao1IncsFJU3m1UMyro5tNcP/Cw3/OvGHExk=";
    name = "stalker-shadow-of-chernobyl-en.7z";
  };

  gameData = stdenv.mkDerivation {
    pname = "stalker-shadow-of-chernobyl-data";
    version = "1.0006";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      innoextract
    ];

    buildPhase = ''
      runHook preBuild
      # Pull just the ISO out of the 7z; the rest of the archive is
      # disc-imaging metadata we don't need.
      mkdir -p iso7z
      7z x -y ${src} -oiso7z STALKER.iso
      iso="iso7z/STALKER.iso"
      mkdir -p "$TMPDIR/iso"
      7z x -y "$iso" setup.exe setup-1a.bin setup-1b.bin setup-1c.bin -o"$TMPDIR/iso"
      cd "$TMPDIR/iso"
      # The Inno Setup ships gamedata.db9 four times — once per UI
      # language (en, fr, it, sp). innoextract's `--language` flag only
      # filters installer-internal strings, not game data, so all four
      # collide on the same path; the last write (Spanish) wins by
      # default. Use `--collisions=rename` to keep all four with $0/$1/$2
      # suffixes, then promote the English one (db9$0) to gamedata.db9.
      innoextract --collisions=rename -d "$TMPDIR/iss" setup.exe
      mv "$TMPDIR/iss/app/gamedata.db9\$0" "$TMPDIR/iss/app/gamedata.db9"
      rm -f "$TMPDIR/iss/app/gamedata.db9\$1" "$TMPDIR/iss/app/gamedata.db9\$2"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "$TMPDIR/iss/app/." "$out"/

      # The shipped fsgame.ltx omits $app_data_root$ — the original
      # installer normally creates Documents/STALKER-SHOC/ on the user's
      # machine and the engine defaults there. We instead point
      # $app_data_root$ at $fs_root$/_appdata_ and pre-create the
      # subdirs the engine asserts on (logs/savedgames/screenshots).
      sed -i \
        '1i $app_data_root$         = true|  false| $fs_root$|       _appdata_\\' \
        "$out/fsgame.ltx"
      mkdir -p "$out/_appdata_/logs" "$out/_appdata_/savedgames" "$out/_appdata_/screenshots"
      # Seed user.ltx with the GOG/THC defaults from commondocs. The
      # path in the US release is commondocs/STALKER-SHOC/ (uppercase);
      # lowercase the destination so the engine finds it.
      if [ -d "$TMPDIR/iss/commondocs/STALKER-SHOC" ]; then
        cp -r "$TMPDIR/iss/commondocs/STALKER-SHOC/." "$out/_appdata_/"
      elif [ -d "$TMPDIR/iss/commondocs/stalker-shoc" ]; then
        cp -r "$TMPDIR/iss/commondocs/stalker-shoc/." "$out/_appdata_/"
      fi
      # Bump the bundled default resolution from 1024x768 to 1920x1080.
      if [ -f "$out/_appdata_/user.ltx" ]; then
        sed -i 's/^vid_mode .*/vid_mode 1920x1080/' "$out/_appdata_/user.ltx"
      fi
      runHook postInstall
    '';

    dontStrip = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stalker-shadow-of-chernobyl";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "bin/xr_3da.exe";

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

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    # 32-bit Wine binary needs /usr/lib32 visible so DXVK can dlopen
    # libvulkan.so.1.
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  # The engine reads the UI language from
  # HKCU\Software\GSC Game World\STALKER-SHOC\language and falls back to
  # the OS default (Spanish on this build's setup) if missing. Inject
  # "eng" before launch so menus/text come up in English.
  preRun = ''
    cat > "$GAMEDIR/stalker-lang.reg" <<'EOF'
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\Software\GSC Game World\STALKER-SHOC]
    "language"="eng"
    EOF
    setsid "$PROTON_RUN" regedit /S "$GAMEDIR/stalker-lang.reg" || true
  '';

  meta = {
    description = "S.T.A.L.K.E.R.: Shadow of Chernobyl (THC DVD English, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalker-shadow-of-chernobyl";
  };
}
