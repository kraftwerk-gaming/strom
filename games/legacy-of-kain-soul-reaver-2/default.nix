{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "legacy-of-kain-soul-reaver-2";

  # Legacy of Kain: Soul Reaver 2 (Crystal Dynamics / Eidos 2001), GOG re-release
  # build 1.0.0.10. archive.org distributes it as a single ZIP holding the GOG
  # Inno Setup installer setup_legacy_of_kain_soul_reaver_2_1.0.0.10.exe (plus
  # Bonus Content we ignore). innoextract --gog yields the game tree under app/:
  # sr2.exe (the native Win32 / Direct3D8 binary), bigfile.dat (the game data
  # archive), binkw32.dll (Bink video), movie3.dat/movie4.dat (FMV) and
  # defaults.cfg. Unlike the sibling Soul Reaver 1 (DirectDraw7, needs a dxwrapper
  # shim) SR2 targets Direct3D8, which DXVK's d3d8 -> d3d9 -> Vulkan path handles
  # under Proton, so no DLL shim is required.
  src = fetchIpfs {
    cid = "QmP79DyEL5jj9B1yujMQz8HPG1r3Fjaf3NCHnQ245erEFs";
    fallbackUrl = "https://archive.org/download/legacy-of-kain-soul-reaver-2-gog/Legacy%20of%20Kain%20Soul%20Reaver%202%20%5BGOG%5D.zip";
    hash = "sha256-r7QSzZEqeJog4q1wHNx0GSHVQ+34Vccak22Oda+TXsI=";
    name = "soul-reaver-2-gog.zip";
  };

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -j "$src" "*/setup_legacy_of_kain_soul_reaver_2_*.exe" -d "$TMPDIR/sr2"
    innoextract --gog -d "$TMPDIR/sr2-extract" \
      "$TMPDIR/sr2"/setup_legacy_of_kain_soul_reaver_2_*.exe
    cp -r "$TMPDIR/sr2-extract/app"/. "$out"/

    # GOG debris not needed at runtime.
    rm -f "$out"/goggame.dll "$out"/gfw_high.ico "$out"/Support.ico \
          "$out"/innosetup_license.txt || true

    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # The GOG build writes its save next to sr2.exe (kain2.sav), persisted by the
  # per-game fuse-overlayfs upper.
  saveLocations = [ ];
  executable = "sr2.exe";

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
    STEAM_COMPAT_CONFIG = "sdlinput";
  };

  meta = {
    description = "Legacy of Kain: Soul Reaver 2 (Crystal Dynamics / Eidos 2001, GOG, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "legacy-of-kain-soul-reaver-2";
  };
}
