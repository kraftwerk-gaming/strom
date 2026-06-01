{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Arcanum: Of Steamworks and Magick Obscura (Troika 2001), GOG re-release
  # v1.0.7.4 hotfix build 24155, distributed as a single GOG Inno Setup
  # installer .exe (no .bin parts). innoextract --gog yields the game tree
  # with Arcanum.exe + Sierra/dnsd/modules at the root and GOG installer
  # debris under app/ tmp/ __redist/ commonappdata/. The 2D DirectDraw
  # engine is driven by Proton via DXVK.
  src = fetchIpfs {
    cid = "QmWtEG4aRWfkPC5z6ec5hNdAkxJLBHYL8V8eDMjS1pJyoq";
    fallbackUrl = "https://archive.org/download/setup_arcanum_-_of_steamworks_and_magick_obscura_1.0.7.4_hotfix_24155/setup_arcanum_-_of_steamworks_and_magick_obscura_1.0.7.4_hotfix_%2824155%29.exe";
    hash = "sha256-sl3T33X0dj86q2601SWe5OrbE2tPFE/DYthyana+qiE=";
    name = "setup_arcanum_1.0.7.4_hotfix_24155.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "arcanum-of-steamworks-and-magick-obscura";

  inherit src;

  nativeBuildInputs = [
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    rm -rf "$out/app" "$out/__redist" "$out/tmp" "$out/commonappdata"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf"
  '';

  runtime = "proton";

  # Arcanum writes saves next to its binary (modules/Arcanum/Save/), so
  # they persist via the per-game fuse-overlayfs upper rather than under
  # drive_c/users/steamuser/.
  saveLocations = [ ];
  executable = "Arcanum.exe";

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
    description = "Arcanum: Of Steamworks and Magick Obscura (Troika 2001, GOG v1.0.7.4 hotfix build 24155, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "arcanum-of-steamworks-and-magick-obscura";
  };
}
