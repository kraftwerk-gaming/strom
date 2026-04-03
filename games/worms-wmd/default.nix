{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
}:

let
  fileMap = ./filemap.tsv;

  # Visual C++ 2012 x86 redistributable -- the game needs mfc110u.dll
  vcredist = fetchurl {
    url = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe";
    hash = "sha256-uSStgGLq9OcEN8i+UPphIWJ5X/CDlHlUbOkH/6jW44Y=";
    name = "vcredist_x86.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "worms-wmd";

  src = fetchIpfs {
    cid = "QmVk1Uvd1fHRMDq2MwYWphkWCicmC7MJeE9XGr4GSaewQK";
    fallbackUrl = "https://archive.org/download/setup_20230616_1422/Setup.exe";
    hash = "sha256-LeEgV6tCbN6A52LQOKDdYnuT8tWqjQiZAARpRHBDSPs=";
    name = "worms-wmd-setup.exe";
  };

  nativeBuildInputs = [
    pkgs.p7zip
    pkgs.cabextract
  ];

  buildScript = ''
    mkdir -p "$out" extracted

    # The SFX repack is a PE with an appended zip. 7z handles this
    # natively; unzip cannot.
    7z x -oextracted "$src" -y > /dev/null

    # Rename numbered entries according to the manifest.
    while IFS=$'\t' read -r idx path; do
      dest="$out/$path"
      mkdir -p "$(dirname "$dest")"
      mv "extracted/$idx" "$dest"
    done < ${fileMap}

    # Remove installer leftovers not in the manifest.
    rm -f extracted/uninstall.exe

    # Anything left over would indicate the manifest is stale.
    leftover=$(ls extracted)
    if [ -n "$leftover" ]; then
      echo "unmapped payload entries: $leftover" >&2
      exit 1
    fi

    # Extract Visual C++ 2012 runtime DLLs from the redistributable.
    # The vcredist is a cabinet containing MSIs and inner cabs.
    # a2 has atl110/msvcp110/msvcr110, a3 has mfc110u.
    cabextract -d vctemp "${vcredist}"
    cabextract -d "$out" vctemp/a2 -F 'F_CENTRAL_*'
    cabextract -d "$out" vctemp/a3 -F 'F_CENTRAL_mfc110u_x86'
    rm -rf vctemp

    # Rename extracted DLLs to their real names.
    for f in "$out"/F_CENTRAL_*_x86; do
      dll=$(basename "$f" | sed 's/^F_CENTRAL_//;s/_x86$/.dll/')
      mv "$f" "$out/$dll"
    done
  '';

  runtime = "proton";

  # OpenGL game -- gamescope causes a black screen with OGL rendering.
  # Run directly via proton without gamescope. Wine forks the game
  # into its own process group, so SIGKILL on the bwrap group won't
  # reach it. We background proton-run and kill wineserver on signal.
  runScript = ''
    exec "$PROTON_RUN" "$GAMEDIR/Worms W.M.D.exe"
  '';

  targetPkgs = pkgs: [ pkgs.winetricks ];

  preRun = ''
    # Install Visual C++ 2012 runtime (mfc110u.dll) on first run.
    # Derive wine path from PROTON_RUN which references the proton store path.
    if [ ! -f "$COMPATDATA/pfx/drive_c/windows/syswow64/mfc110u.dll" ]; then
      echo "Installing vcrun2012..."
      proton_dir=$(grep -oP '"\K/nix/store/[^/]+-proton-symlink-pfx' "$PROTON_RUN" | head -1)
      export WINE="$proton_dir/files/bin/wine"
      export WINESERVER="$proton_dir/files/bin/wineserver"
      export WINEPREFIX="$COMPATDATA/pfx"
      winetricks -q vcrun2012 || true
      unset WINE WINESERVER WINEPREFIX
    fi
  '';

  env = {
    STEAM_COMPAT_APP_ID = "327030";
    SteamAppId = "327030";
    SteamGameId = "327030";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Worms W.M.D (GOG build, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "worms-wmd";
  };
}
