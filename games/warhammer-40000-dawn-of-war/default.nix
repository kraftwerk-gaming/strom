{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  gnutar,
}:

let
  # Warhammer 40,000: Dawn of War (Relic, 2004) — base game, the GOG
  # "Game of the Year Edition" that ships inside the Master Collection.
  # Source: freegogpcgames magnet btih:37f6631139be6ae061dacb5b478faf4ca0e1a813
  # (Dawn of War Master Collection, ~11.81 GB total); the base GOTY files
  # live under "Warhammer 40,000 Dawn of War – Game of the Year Edition/":
  #   setup_warhammer_40000_dawn_of_war_0.19_(64626).exe  (831 KB)
  #   setup_warhammer_40000_dawn_of_war_0.19_(64626)-1.bin (2.11 GB)
  # Both parts are bundled into a flat tar so fetchIpfs can treat them as
  # one artifact. innoextract 1.7+ reassembles the split parts
  # automatically when both files are in the same directory. After
  # extraction, W40k.exe lands at the root (no app/ prefix).
  # No fallbackUrl: this tar is repacked locally from the magnet's installer
  # parts (above), so no public URL serves these exact bytes -- IPFS is the
  # canonical source. Rebuild from the magnet + `tar` if the pin is ever lost.
  src = fetchIpfs {
    cid = "QmWVBVaegsTkbezUYNk5f5tvS58toqeJx9Sca4yoiUUzvr";
    hash = "sha256-R9hp+IGq2iuD4nFfNdbgmUq5PlMOjA++tKmi2RTLO0o=";
    name = "dawn-of-war-goty-gog.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "warhammer-40000-dawn-of-war";

  inherit src;

  nativeBuildInputs = [
    gnutar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/installer"
    tar -xf "$src" -C "$TMPDIR/installer"
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/installer"/setup_warhammer_40000_dawn_of_war_*.exe
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    # The game lives at $out root (W40k.exe + data dirs + DLLs).
    rm -rf "$out/app" "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" 2>/dev/null || true
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf" 2>/dev/null || true
  '';

  runtime = "proton";

  # Saves/profiles persist via the per-game fuse-overlayfs upper. The
  # original engine writes player profiles and campaign saves into
  # Profiles/ next to W40k.exe (the GOG/retail layout — e.g.
  # Profiles/Profile1/w40k/singleplayer/campaign/), not under
  # drive_c/users/steamuser/..., so no relocation is required.
  saveLocations = [ ];

  # Base-game launcher. W40k.exe is the original Dawn of War executable;
  # the Master Collection's expansion launchers (WXP.exe / DarkCrusade.exe
  # / Soulstorm.exe) install into their own folders and are intentionally
  # not the target here.
  executable = "W40k.exe";

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
    description = "Warhammer 40,000: Dawn of War (Relic, 2004, GOG Game of the Year edition, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warhammer-40000-dawn-of-war";
  };
}
