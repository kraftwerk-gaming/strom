{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # Total Annihilation - Commander Pack (Cavedog 1997, GOG re-release).
  # The archive.org item ships "Total Annihilation.zip" wrapping the GOG
  # Inno Setup installer setup_total_annihilation_commander_pack.exe
  # alongside the soundtrack, manual and map-editor extras. innoextract
  # --gog unpacks the installer's app/ tree; TotalA.exe is the Win32
  # engine entry point, with the game data (.hpi/.ufo/.gp3) at the root.
  src = fetchIpfs {
    cid = "QmRPU9ZPykAtfCMEfbHQGzd2F66EWuAzEJM1PnASW9keQd";
    fallbackUrl = "https://archive.org/download/total-annihilation_202602/Total%20Annihilation.zip";
    hash = "sha256-pVkhfL9IAAfkAHXYtJYKtw0o/69MpvP6nYvoe5Y1YiA=";
    name = "total-annihilation.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "total-annihilation";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  # Outer .zip nests "Total Annihilation/setup_total_annihilation_commander_pack.exe"
  # plus extras (soundtrack/manual/map-editor zips we don't need at runtime).
  # innoextract spills the installer payload into ./app (the runtime tree),
  # ./tmp and ./commonappdata; only app/ matters. TotalA.exe (~1.4 MiB) is
  # the engine binary, with totala1.hpi/totala2.hpi and the rest of the
  # data files at the root.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    setup_exe=$(find "$TMPDIR/zip" -iname 'setup_total_annihilation*.exe' | head -1)
    innoextract --gog -d "$TMPDIR/inno" "$setup_exe"
    cp -r "$TMPDIR/inno/app"/. "$out"/
  '';

  runtime = "proton";

  # TA writes its config (TotalA.ini) and saved games (*.sav) next to the
  # engine binary rather than under drive_c/users/steamuser/..., so saves
  # persist through the per-game fuse-overlayfs upper.
  saveLocations = [ ];
  executable = "TotalA.exe";

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

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
    description = "Total Annihilation - Commander Pack (Cavedog 1997, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "total-annihilation";
  };
}
