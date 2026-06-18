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

  # GE-Proton's bundled 32-bit libavcodec.so.58 (gst-libav, the only
  # WMV/VC-1 decoder in Proton's gstreamer) is DT_NEEDED-linked against
  # libvpx.so.6 -- the libvpx 1.8 ABI. Current nixpkgs ships libvpx 1.16
  # (libvpx.so.9), so pin the old ABI here just for this game's FHS.
  libvpx6 = pkgs.pkgsi686Linux.libvpx.overrideAttrs (_: {
    version = "1.8.2";
    src = pkgs.fetchFromGitHub {
      owner = "webmproject";
      repo = "libvpx";
      rev = "v1.8.2";
      hash = "sha256-2VbLrN/Z1mcjpHahvaqWxJmZjd25p1pDPduJtqYj2D8=";
    };
  });
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

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # Saves/*.dat next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];

  executable = "Worms W.M.D.exe";

  # Render directly to the host display instead of nesting in gamescope.
  # This OpenGL engine drives its own fullscreen window and fills the
  # screen natively; under gamescope it renders into a small top-left
  # corner of the nest (gamescope composites its window at native size and
  # no nested/output/--force-windows-fullscreen/scaler combination makes it
  # fill). Verified on a 2880x1920 seat: gamescope -> ~1280x720 in the
  # corner; no-gamescope -> full-screen menu.
  enableGamescope = false;

  env = {
    STEAM_COMPAT_APP_ID = "327030";
    SteamAppId = "327030";
    SteamGameId = "327030";
  };

  # The .wmv intro/logo splashes (uidata/video/*.wmv) decode through
  # Proton's Media-Foundation -> gst-libav -> bundled ffmpeg path.
  # libgstlibav.so is dlopen'd RTLD_NOW and drags in libavcodec/format/util,
  # whose DT_NEEDED libs are absent from the base proton FHS; with any
  # missing the decoder fails to load and the intros render black. The game
  # is 32-bit (32-bit winegstreamer -> 32-bit gstreamer plugins), so only
  # the i686 libs are needed:
  #   libvpx.so.6 (libavcodec), libbz2.so.1.0 (libavformat),
  #   libva*.so.2 + libvdpau.so.1 (libavutil) and their libdrm.so.2 dep.
  targetPkgs = pkgs: [
    libvpx6
    pkgs.pkgsi686Linux.bzip2.out
    pkgs.pkgsi686Linux.libva
    pkgs.pkgsi686Linux.libvdpau
    pkgs.pkgsi686Linux.libdrm
  ];

  meta = {
    description = "Worms W.M.D (GOG build, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "worms-wmd";
  };
}
