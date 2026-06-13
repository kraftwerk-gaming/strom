{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  gnutar,
}:

let
  # Warhammer 40,000: Dawn of War - Dark Crusade (Relic, 2006) — the second,
  # standalone expansion (does not need the base game), shipped as its own
  # GOG installer inside the Master Collection. Source: freegogpcgames magnet
  # btih:37f6631139be6ae061dacb5b478faf4ca0e1a813 (Dawn of War Master
  # Collection); the Dark Crusade files live under
  # "Warhammer 40,000 Dawn of War – Dark Crusade/":
  #   setup_warhammer_40000_dawn_of_war_-_dark_crusade_0.19_(64626).exe
  #   setup_warhammer_40000_dawn_of_war_-_dark_crusade_0.19_(64626)-1.bin
  # Both parts are bundled into a flat tar so fetchIpfs treats them as one
  # artifact; innoextract --gog reassembles the split parts (3.5 GB full
  # standalone install). After extraction, darkcrusade.exe lands at the root.
  # No fallbackUrl: locally-repacked tar with no public URL for these exact
  # bytes -- IPFS is the canonical source. Rebuild from the magnet + `tar`
  # if the pin is ever lost.
  src = fetchIpfs {
    cid = "QmQpodxcCWcFQMUjMbvc1YwuzzETD41ktcJB2J3ra46CzG";
    hash = "sha256-1ikh/BpGLcEpPLkTkm49wT9pgP3Clsk08S5IUdbH8/A=";
    name = "dawn-of-war-dark-crusade-gog.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "warhammer-40000-dawn-of-war-dark-crusade";

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

  executable = "darkcrusade.exe";

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
    description = "Warhammer 40,000: Dawn of War - Dark Crusade (Relic, 2006, GOG standalone, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warhammer-40000-dawn-of-war-dark-crusade";
  };
}
