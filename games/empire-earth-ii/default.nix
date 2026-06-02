{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # Empire Earth II Gold (Mad Doc / Vivendi 2005), DRM-free GOG release.
  # The archive.org GOG mirror ships the offline installer wrapped in a
  # zip alongside a stray .url file; the only payload we want is the
  # InnoSetup installer setup_empire_earth2_2.0.0.17.exe.
  src = fetchIpfs {
    cid = "QmNhH3tSdDNcWaBYnN5ZARd2XNR4qwVL9avBcCEkKVMxbK";
    fallbackUrl = "https://archive.org/download/empire-earth-2-gold-edition-gog-version/Empire.Earth.2.Gold.Edition.zip";
    hash = "sha256-dVkmehRju/zBH6IWd1H61rxcNcMZULB6OprADw1E2Oc=";
    name = "empire-earth-2-gold-edition-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "empire-earth-ii";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  # unzip the GOG installer out of the archive.org wrapper, then
  # innoextract its InnoSetup payload. GOG InnoSetup lays the game
  # tree out under app/; flatten that to $out.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip"
    unzip -q "$src" -d "$TMPDIR/zip"
    inst="$(find "$TMPDIR/zip" -iname 'setup_empire_earth2*.exe' | head -n1)"
    innoextract -d "$out" "$inst"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
  '';

  runtime = "proton";

  # EE2 and the Art of Supremacy expansion write savegames under
  # Documents/Empire Earth II/ (savegame_SP, profiles, settings).
  saveLocations = [ "Documents/Empire Earth II" ];
  # GOG Gold ships both EE2.exe (base) and EE2X.exe (The Art of
  # Supremacy). EE2X is the expansion entry point and exposes all
  # base + expansion content, so it's the Gold default.
  executable = "EE2X.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Empire Earth II Gold (Mad Doc/Vivendi 2005, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "empire-earth-ii";
  };
}
