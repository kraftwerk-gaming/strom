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
  # GOG release of "KKND2: Krossfire" (Beam Software / Melbourne House 1998,
  # the sequel to KKnD). The archive.org item ships a .zip wrapping the GOG
  # Inno Setup installer setup_kknd2_2.0.0.7.exe (plus a manual PDF and
  # bonus single/multiplayer maps). innoextract unpacks the installer's
  # "app/" tree, whose KKND2.exe is the Win32 engine entry point.
  src = fetchIpfs {
    cid = "QmYsaybnh1rqpPwiCo6Aa349TZCGuGqUcuiE4uuHCDA5Rg";
    fallbackUrl = "https://archive.org/download/kknd-2-krossfire-krush-kill-n-destroy-gog_202601/KKND2%20Krossfire%20-%20Krush%20Kill%20n%20Destroy%20%5BGOG%5D.zip";
    hash = "sha256-XriCVHrMI6shcvO5uEr56qsu023DYBZ4/pUG7n+eU98=";
    name = "kknd2-krossfire.zip";
  };

  # FunkyFr3sh's cnc-ddraw wraps the legacy DirectDraw API. cnc-ddraw ships
  # a per-game compatibility profile for KKND2 (matched by the window
  # title), so `renderer=auto` lets it pick the right backend without the
  # OpenGL-under-gamescope-nested-Wayland fragility. This is the
  # community-recommended fix for KKND2 on modern systems (PCGamingWiki /
  # ModDB), mirroring the sibling `kknd` package.
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
  name = "kknd2-krossfire";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  # Outer .zip wraps "KKND2 Krossfire - Krush Kill n Destroy [GOG]/
  # setup_kknd2_2.0.0.7.exe" plus a manual and bonus maps. innoextract
  # spills installer payload into ./app, ./tmp, and ./commonappdata; only
  # app/ is the runtime tree. KKND2.exe is the Win32 engine binary; the
  # fmv/ briefing FMVs, Campaign/, Savegame/ and UCONFIG/ dirs sit
  # alongside.
  #
  # The .vbc FMVs in fmv/ stay in the tree: the engine references them by
  # the relative path fmv/<name>.vbc from its cwd (GAMEDIR), so no registry
  # drive-letter hack is needed (unlike the KKnD-Xtreme predecessor).
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    setup_exe=$(find "$TMPDIR/zip" -name 'setup_kknd2*.exe' | head -1)
    innoextract -d "$TMPDIR/inno" "$setup_exe"
    cp -r "$TMPDIR/inno/app"/. "$out"/

    unzip -o ${cncDdraw} ddraw.dll -d "$out/"
    cp ${ddrawIni} "$out/ddraw.ini"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper: the engine writes
  # into Savegame/ next to its binary (and ddraw.ini in the same dir), not
  # under drive_c/users/steamuser/...
  saveLocations = [ ];
  executable = "KKND2.exe";

  # `n,b` makes wine load the bundled native ddraw.dll first (cnc-ddraw)
  # then fall back to builtin.
  env = {
    WINEDLLOVERRIDES = "ddraw=n,b";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Seed ddraw.ini fresh every launch — cnc-ddraw mutates the file in place
  # (posX/posY/savesettings), so a stale copy would shadow any change here.
  #
  # Write straight into the overlay's writable UPPER layer ($STROM_GAMEDIR),
  # NOT the merged mount ($GAMEDIR=$STROM_OVERLAY). The build output ships a
  # ddraw.ini in the nix-store LOWER layer, so any write through the merged
  # mount (install/cp-rename OR a plain `cat >` redirect) triggers a
  # fuse-overlayfs copy-up, which crosses a device boundary ("Invalid
  # cross-device link") and aborts the launch (bwrap exit). Writing the file
  # directly in the upper is a normal btrfs file create — no copy-up — and
  # the overlay then merges it over the lower. The engine's cwd is the
  # merged mount, so it reads this upper copy; cnc-ddraw's later in-place
  # edits are plain upper-layer writes.
  preRun = ''
    cat > "$STROM_GAMEDIR/ddraw.ini" <<'EOF'
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
    EOF
    chmod 644 "$STROM_GAMEDIR/ddraw.ini"
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
    description = "KKND2: Krossfire (Beam Software 1998, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "kknd2-krossfire";
  };
}
