{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  gnutar,
}:

let
  # Warhammer 40,000: Dawn of War - Soulstorm (Relic, 2008) — the final,
  # standalone expansion (all nine races; does not need the base game),
  # shipped as its own GOG installer inside the Master Collection. Source:
  # freegogpcgames magnet btih:37f6631139be6ae061dacb5b478faf4ca0e1a813 (Dawn
  # of War Master Collection); the Soulstorm files live under
  # "Warhammer 40,000 Dawn of War – Soulstorm/":
  #   setup_warhammer_40000_dawn_of_war_-_soulstorm_0.21_(64955).exe
  #   setup_warhammer_40000_dawn_of_war_-_soulstorm_0.21_(64955)-1.bin
  #   setup_warhammer_40000_dawn_of_war_-_soulstorm_0.21_(64955)-2.bin
  # All parts are bundled into a flat tar so fetchIpfs treats them as one
  # artifact; innoextract --gog reassembles the split parts (4.3 GB full
  # standalone install). After extraction, Soulstorm.exe lands at the root.
  # No fallbackUrl: locally-repacked tar with no public URL for these exact
  # bytes -- IPFS is the canonical source. Rebuild from the magnet + `tar`
  # if the pin is ever lost.
  src = fetchIpfs {
    cid = "QmPQB7v72d8pgKy8rX6TYD9EheuC9DbRKnSQQAS3upzTTG";
    hash = "sha256-39zrANRXqve+zI3hPIKQKC5yd9tU7JVomm5KpGSdTU8=";
    name = "dawn-of-war-soulstorm-gog.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "warhammer-40000-dawn-of-war-soulstorm";

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

  executable = "Soulstorm.exe";

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
    description = "Warhammer 40,000: Dawn of War - Soulstorm (Relic, 2008, GOG standalone, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warhammer-40000-dawn-of-war-soulstorm";
  };
}
