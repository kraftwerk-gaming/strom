{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

# The only PC upload of Worms W.M.D on archive.org is a third-party SFX
# repack of the GOG build. The installer stub stores the payload as a
# plain ZIP archive appended at a fixed offset, with files named by
# integer index. A CSV manifest in the stub maps index -> install path.
# We extracted that manifest into filemap.tsv at packaging time so the
# build does not need to parse the PE.

let
  fileMap = ./filemap.tsv;
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "worms-wmd";

  src = fetchIpfs {
    cid = "QmVk1Uvd1fHRMDq2MwYWphkWCicmC7MJeE9XGr4GSaewQK";
    fallbackUrl = "https://archive.org/download/setup_20230616_1422/Setup.exe";
    hash = "sha256-LeEgV6tCbN6A52LQOKDdYnuT8tWqjQiZAARpRHBDSPs=";
    name = "worms-wmd-setup.exe";
  };

  nativeBuildInputs = [ pkgs.p7zip ];

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

    # The repack ships a steam_api.dll stub. Keep it: the GOG executable
    # links against it and refuses to start without it present.
  '';

  runtime = "proton";
  executable = "Worms W.M.D.exe";
  gamescopeArgs = "-W 1920 -H 1080 -r 60 --force-grab-cursor --expose-wayland";

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
    # Real Steam app id lets protonfixes pick up known workarounds.
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
