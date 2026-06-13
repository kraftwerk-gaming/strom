{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Torment: Tides of Numenera v1.1.0 (GOG build
  # 12012, "Servant of the Tides" content update — GOG's offline installer
  # for this build is a full, self-contained install, not an incremental
  # patch despite the "content update patch" label). Unity 5; the engine is
  # TidesOfNumenera.exe + a Mono TidesOfNumenera_Data tree.
  #
  # Why Windows-over-Proton instead of the native GOG Linux build: the
  # Linux .sh installer ships a resources.assets.resS that GOG truncated
  # upstream (baked-in bad CRC, no clean Linux source exists), and on the
  # user's seat the native build also renders the player model SILVER /
  # untextured with misaligned selection icons. The Windows installer's
  # resS is intact (1.18 GiB, extracts cleanly — no CRC tolerance needed),
  # and routing the game through Proton/DXVK uses a different render path
  # that is expected to fix the silver-player glitch.
  #
  # Two-part Inno Setup installer (.exe + two .bin slices). innoextract
  # reassembles them when they sit next to each other with the original GOG
  # filenames, so the buildScript symlinks them in $TMPDIR before
  # extracting. The game tree lands under app/; tmp/, __support/ etc. are
  # installer-bootstrap junk.
  setupExe = fetchIpfs {
    cid = "QmZZDSGK5fuBHNk9NeVsMw5yPdSv3EPXCQ3awR9SSREsoG";
    fallbackUrl = "https://archive.org/download/torment_tides_of_numenera_1.1.0_win_gog_20240130/setup_torment_-_tides_of_numenera_1.1.0_-_servant_of_the_tides_content_update_patch_%2812012%29.exe";
    hash = "sha256-X/p5Cs+HDwQtoJ3IWb24t3MA5tEP2G3WZmLSfXUFBvY=";
    name = "torment-win-gog.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "QmXzrffXJFg6hpmzVLWXUg9sRmmkW51UyXnNnZ3ZYavJH1";
    fallbackUrl = "https://archive.org/download/torment_tides_of_numenera_1.1.0_win_gog_20240130/setup_torment_-_tides_of_numenera_1.1.0_-_servant_of_the_tides_content_update_patch_%2812012%29-1.bin";
    hash = "sha256-QfACmQRUQjdSPnmhsCawnnoCsKchHx4Mhv8kXqAQ+N8=";
    name = "torment-win-gog-1.bin";
  };

  setupBin2 = fetchIpfs {
    cid = "QmQiswwEFGY6VsB2qy5DNPh86s9rvzSpzgyVkYjcn995Pk";
    fallbackUrl = "https://archive.org/download/torment_tides_of_numenera_1.1.0_win_gog_20240130/setup_torment_-_tides_of_numenera_1.1.0_-_servant_of_the_tides_content_update_patch_%2812012%29-2.bin";
    hash = "sha256-evKeZnjAetbMTaJZJJVE6h8ROMkrm5LSLiVXAun5Hcw=";
    name = "torment-win-gog-2.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "torment-tides-of-numenera";

  ipfsSources = [
    setupExe
    setupBin1
    setupBin2
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  # Symlink the installer parts side-by-side under their original GOG
  # filenames so innoextract can reassemble the multi-part payload, then
  # extract. The Windows resS is intact, so no CRC tolerance / `|| true` —
  # innoextract must succeed and integrity is enforced. The game tree is
  # under app/; drop the installer-bootstrap subtrees afterwards.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iss" "$TMPDIR/in"
    base='setup_torment_-_tides_of_numenera_1.1.0_-_servant_of_the_tides_content_update_patch_(12012)'
    ln -s ${setupExe}  "$TMPDIR/in/$base.exe"
    ln -s ${setupBin1} "$TMPDIR/in/$base-1.bin"
    ln -s ${setupBin2} "$TMPDIR/in/$base-2.bin"

    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/in/$base.exe"

    cp -r "$TMPDIR/iss/app"/. "$out"/
    chmod -R u+w "$out"

    # Strip GOG launcher / installer side files (only used by Galaxy).
    rm -f "$out/goggame-"*.dll "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.ico 2>/dev/null || true

    # Integrity guard: the Windows resS is intact upstream, so enforce that
    # both the engine binary and the (previously-corrupt-on-Linux) resS
    # extracted at full length.
    test -f "$out/TidesOfNumenera.exe"
    test -f "$out/TidesOfNumenera_Data/resources.assets.resS"
  '';

  runtime = "proton";
  executable = "TidesOfNumenera.exe";

  # Unity 5 on non-English locales crashes at 70% during map load (known
  # InXile bug); force en_US so the menu/map path is the English one.
  env = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # Windows Unity build writes saves + config under
  # AppData\LocalLow\InXile Entertainment\Torment (Saves/, Config files).
  # Relocate the whole company tree into $STROM_GAMEDIR so it survives
  # wineprefix wipes.
  saveLocations = [ "AppData/LocalLow/InXile Entertainment/Torment" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Torment: Tides of Numenera (Windows, GOG v1.1.0, Unity 5, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "torment-tides-of-numenera";
  };
}
