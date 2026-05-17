{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  innoextract,
  unzip,
  writeText,
}:

let
  # GOG release of "KKnD Xtreme" (Beam Software / Melbourne House 1997, the
  # 1998 re-release bundling Krossfire's predecessor with the Krush Kill 'n
  # Destroy Xtreme expansion). Archive.org item ships a .zip containing the
  # GOG Inno Setup installer setup_kknd_xtreme_2.0.0.9.exe plus a manual PDF.
  # innoextract unpacks the installer's "app/" tree which has KKNDgame.exe
  # as the engine entry point.
  src = fetchIpfs {
    cid = "QmU7RfUrkdx3sMV2h1wUExwrs1SngP81rkHKBQFzVAPLXW";
    fallbackUrl = "https://archive.org/download/kkn-d-xtreme-krush-kill-n-destroy-gog/KKnD%20Xtreme%20-%20Krush%20Kill%20n%20Destroy%20%5BGOG%5D.zip";
    hash = "sha256-TP90RXEwdZqKuP2uPyBX7fiYfh34C1fctTt4sZEG+IY=";
    name = "kknd.zip";
  };

  # FunkyFr3sh's cnc-ddraw wraps the legacy DirectDraw API. cnc-ddraw ships
  # a per-game compatibility profile for "KKND Xtreme" (matched by the
  # window title), so `renderer=auto` lets it pick the right backend
  # without the OpenGL-under-gamescope-nested-Wayland fragility.
  cncDdraw = fetchurl {
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-CxOriaZMmRgYmx2t1EnvbtPLO3sZyr2W2K29lVBbuQg=";
    name = "cnc-ddraw.zip";
  };

  ddrawIni = writeText "ddraw.ini" ''
    [ddraw]
    renderer=auto
    windowed=true
    fullscreen=false
    maintas=true
    adjmouse=true
    handlemouse=true
    maxfps=60
    singlecpu=true
    nonexclusive=true
    no_compat_warning=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "kknd";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  # Outer .zip wraps "KKnD Xtreme - Krush Kill n Destroy [GOG]/setup_kknd_xtreme_*.exe"
  # plus a manual. innoextract spills installer payload into ./app, ./tmp,
  # and ./commonappdata; only app/ is the runtime tree. KKNDgame.exe is the
  # Win32 engine binary (~475 KiB); the FMV/ and other dirs sit alongside.
  #
  # The .vbc briefing FMVs in FMV/ stay in the tree: the campaign-select
  # screen previews each mission's briefing head-shot and crashes/hangs on
  # missing files (a previous strip-the-FMVs workaround broke the
  # campaign menu entirely). GamePath gets pinned via the wine registry
  # in preRun, so the game can actually find FMV/*.vbc at runtime.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    setup_exe=$(find "$TMPDIR/zip" -name 'setup_kknd_xtreme*.exe' | head -1)
    innoextract -d "$TMPDIR/inno" "$setup_exe"
    cp -r "$TMPDIR/inno/app"/. "$out"/

    unzip -o ${cncDdraw} ddraw.dll -d "$out/"
    cp ${ddrawIni} "$out/ddraw.ini"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # *.sav + save.lst + ddraw.ini next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "KKNDgame.exe";

  # `n,b` makes wine load the bundled native ddraw.dll first (cnc-ddraw)
  # then fall back to builtin.
  env = {
    WINEDLLOVERRIDES = "ddraw=n,b";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Overwrite ddraw.ini in the overlay every launch — cnc-ddraw mutates
  # the file in place (posX/posY/savesettings), so a stale upper-layer
  # ini would shadow any change we make in the nix-store lower. The .sve
  # save file is untouched.
  #
  # Set HKLM\SOFTWARE\Melbourne House\Krush, Kill 'n' Destroy Xtreme\
  # 1.00.000\{DriveLetter,GamePath}. KKNDgame.exe (reverse-engineered)
  # reads DriveLetter, takes the FIRST BYTE, sprintfs it with "%c" into
  # a buffer, then uses that buffer as the `%s` in path format
  # "%s\FMV\<name>.vbc". Default byte is 'C' (the engine's hard-coded
  # default), producing `C\FMV\headm01.vbc` — an invalid Windows path.
  # Setting DriveLetter to "." makes the first byte '.', so the engine
  # opens `.\FMV\headm01.vbc` relative to cwd, which is GAMEDIR.
  # KKND is 32-bit so writes go under Wow6432Node; mirror under the
  # plain key as belt-and-braces.
  preRun = ''
    install -m 644 ${ddrawIni} "$GAMEDIR/ddraw.ini"

    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
    if [ -f "$SYSREG" ]; then
      APOS="'"
      TS="$(date +%s)"
      {
        printf '\n[Software\\\\Wow6432Node\\\\Melbourne House\\\\Krush, Kill %sn%s Destroy Xtreme\\\\1.00.000] %d\n' \
          "$APOS" "$APOS" "$TS"
        printf '"DriveLetter"="."\n'
        printf '"GamePath"="%s"\n' "$GAMEDIR_WIN"
        printf '"MinimumInstall"=dword:00000000\n'
        printf '\n[Software\\\\Melbourne House\\\\Krush, Kill %sn%s Destroy Xtreme\\\\1.00.000] %d\n' \
          "$APOS" "$APOS" "$TS"
        printf '"DriveLetter"="."\n'
        printf '"GamePath"="%s"\n' "$GAMEDIR_WIN"
        printf '"MinimumInstall"=dword:00000000\n'
      } >> "$SYSREG"
    fi
  '';

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

  meta = {
    description = "KKnD Xtreme / Krush Kill 'n Destroy (Beam Software 1997, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "kknd";
  };
}
