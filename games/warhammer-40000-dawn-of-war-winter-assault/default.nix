{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  gnutar,
}:

let
  # Warhammer 40,000: Dawn of War - Winter Assault (Relic, 2005) — the first
  # expansion, shipped as a standalone GOG installer inside the Master
  # Collection. Source: freegogpcgames magnet
  # btih:37f6631139be6ae061dacb5b478faf4ca0e1a813 (Dawn of War Master
  # Collection); the Winter Assault files live under
  # "Warhammer 40,000 Dawn of War – Winter Assault/":
  #   setup_warhammer_40000_dawn_of_war_-_winter_assault_0.19_(64626).exe
  #   setup_warhammer_40000_dawn_of_war_-_winter_assault_0.19_(64626)-1.bin
  # Both parts are bundled into a flat tar so fetchIpfs treats them as one
  # artifact; innoextract --gog reassembles the split parts. The GOG
  # installer is the full standalone game (2.1 GB), so no base-game data is
  # required. After extraction, W40kWA.exe lands at the root.
  # No fallbackUrl: locally-repacked tar with no public URL for these exact
  # bytes -- IPFS is the canonical source. Rebuild from the magnet + `tar`
  # if the pin is ever lost.
  src = fetchIpfs {
    cid = "Qmd4Nrec6TXLY1VDA3T46zWU9RrHMZSrKfb7C4V5XCLW2d";
    hash = "sha256-GCxlJHaPlqfKd1U+s7zJ/eZ1XGMRZOOyu7tHm3Ye9I8=";
    name = "dawn-of-war-winter-assault-gog.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "warhammer-40000-dawn-of-war-winter-assault";

  inherit src;

  nativeBuildInputs = [
    gnutar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/installer"
    tar -xf "$src" -C "$TMPDIR/installer"
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/installer"/setup_*.exe
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    rm -rf "$out/app" "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" 2>/dev/null || true
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf" 2>/dev/null || true
  '';

  runtime = "proton";

  # The engine writes player profiles + campaign saves into Profiles/ next
  # to the executable (GOG/retail layout), not under drive_c/users/..., so
  # no relocation is required; the per-game fuse-overlayfs upper persists it.
  saveLocations = [ ];

  executable = "W40kWA.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the window (relative mouse mode) so RTS
      # screen-edge scrolling doesn't go erratic when the cursor leaves
      # the game window -- same as the other strategy games here.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Warhammer 40,000: Dawn of War - Winter Assault (Relic, 2005, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warhammer-40000-dawn-of-war-winter-assault";
  };
}
