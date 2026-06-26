{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Colony Ship: A Post-Earth Role Playing Game (Iron Tower Studio 2024,
  # Unreal Engine 4 turn-based CRPG). GOG offline installer v1.0.171 build
  # 81688 (64bit), DRM-free. Split InnoSetup bundle, four parts:
  #   setup_..._(81688).exe    --  ~980 KiB InnoSetup stub
  #   setup_..._(81688)-1.bin  --  ~4.0 GiB game-data slice
  #   setup_..._(81688)-2.bin  --  ~4.0 GiB game-data slice
  #   setup_..._(81688)-3.bin  --  ~765 MiB game-data slice
  # innoextract --gog reads the .exe stub header and pulls the data out of the
  # paired .bin slices; all parts must sit in the same directory with matching
  # base names (stub base == bin base minus "-N").
  #
  # nix store path names forbid parentheses, so the fetchIpfs `name` drops the
  # "(81688)" build tag; the buildScript re-creates the real GOG basenames
  # (with the parens) as symlinks before innoextract, so --gog still pairs the
  # stub with its .bin slices.
  #
  # No stable single-file public HTTP mirror exists for this exact GOG build;
  # the gog-games.to page is Cloudflare-gated and archive.org carries only an
  # early-access repack. fallbackUrl therefore points at the freegogpcgames
  # magnet (the four parts above); seed via IPFS after the game is tested.
  magnet = "magnet:?xt=urn:btih:B36DEAD86981530DA0B2B27845E1042B90AB3360&dn=game-colony.ship.a.postearth.role.playing.game-(81688)";

  setupExe = fetchIpfs {
    cid = "QmWJR5bs9Xy3HptFyEE6BmKSTEbaXMWeUUqP6yzobTyxmk";
    fallbackUrl = magnet;
    hash = "sha256-UemWyWm1dOnsLZgLxjNSrQyZS13SPd8KYLEmfj2ANQw=";
    name = "setup_colony_ship_1.0.171_81688.exe";
  };

  bin1 = fetchIpfs {
    cid = "QmSxAfANyXbQ3MkqPcNdXaquDCe8jiHTMwXLQ43SzXAPsA";
    fallbackUrl = magnet;
    hash = "sha256-6DMIGrE0vxGupTC0WXe2qp8tzPdlNPbXbKZdfyBn85M=";
    name = "setup_colony_ship_1.0.171_81688-1.bin";
  };

  bin2 = fetchIpfs {
    cid = "QmQNP3fLs4hEe8fQej6GjYXzd4zcZGb4DfhEA9j8jEiRBo";
    fallbackUrl = magnet;
    hash = "sha256-FipuQ7z85vCa4aZ6yBJE348xT3A0J0T/QBhSIDUTTa0=";
    name = "setup_colony_ship_1.0.171_81688-2.bin";
  };

  bin3 = fetchIpfs {
    cid = "QmUu9RwHT7x66kDXErts8gRgeu3VWdH279zdw2B2DkHJoB";
    fallbackUrl = magnet;
    hash = "sha256-AWGe51zU4UPQVOTwL6G+0ZlS5wlQaBrD8wb3bealfpM=";
    name = "setup_colony_ship_1.0.171_81688-3.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "colony-ship-a-post-earth-role-playing-game";

  src = setupExe;
  ipfsSources = [
    setupExe
    bin1
    bin2
    bin3
  ];

  nativeBuildInputs = [
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/inno" "$TMPDIR/iss"

    # Re-pair the split installer under matching base names so innoextract
    # --gog can locate the .bin slices from the .exe stub header.
    base="setup_colony_ship_a_post-earth_role_playing_game_1.0.171_(64bit)_(81688)"
    ln -s "${setupExe}" "$TMPDIR/inno/$base.exe"
    ln -s "${bin1}"     "$TMPDIR/inno/$base-1.bin"
    ln -s "${bin2}"     "$TMPDIR/inno/$base-2.bin"
    ln -s "${bin3}"     "$TMPDIR/inno/$base-3.bin"
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/inno/$base.exe"

    # innoextract --gog strips the installer's app/ constant prefix, so the UE4
    # game tree (ColonyShipGame/, Engine/, the top-level ColonyShipGame.exe
    # launcher shim) lands at the extraction ROOT.
    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"

    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    rm -rf "$out/app" "$out/tmp" "$out/__redist" "$out/__support" \
           "$out/commonappdata"
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.ico "$out"/*.url \
          "$out"/galaxy_*.exe "$out"/autorun.* 2>/dev/null || true
  '';

  runtime = "proton";

  # The real binary is the UE4 shipping build nested under
  # ColonyShipGame/Binaries/Win64/. A top-level ColonyShipGame.exe launcher
  # shim also exists, but the shipping exe is the one to drive.
  executable = "ColonyShipGame/Binaries/Win64/ColonyShipGame-Win64-Shipping.exe";

  # UE4 writes saves/config under %LOCALAPPDATA%\ColonyShipGame\Saved, i.e.
  # drive_c/users/steamuser/AppData/Local/ColonyShipGame/Saved -- the standard
  # relocation path, so the generic saveLocations handling applies.
  saveLocations = [
    "AppData/Local/ColonyShipGame/Saved"
  ];

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
    description = "Colony Ship: A Post-Earth Role Playing Game (Iron Tower Studio 2024, UE4, GOG v1.0.171 build 81688, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "colony-ship-a-post-earth-role-playing-game";
  };
}
