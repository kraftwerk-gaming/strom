{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "faith-the-unholy-trinity";

  # FAITH: The Unholy Trinity (Airdorf 2022). Three-chapter remastered
  # bundle of the original 8-bit-styled horror trilogy. GOG Inno setup
  # v1.4 build 68637 (64-bit); innoextract --gog yields app/FAITH.exe
  # at the install root plus a "goodies/" subtree of bonus content and
  # the FAITH Demon Siege side game.
  src = fetchIpfs {
    cid = "QmapahTD9VfSKG7LLMFeDsgdxzqrsad57CCprCfAA7tX9a";
    fallbackUrl = "https://archive.org/download/faithunholytrinity/setup_faith_the_unholy_trinity_1.4_%2864bit%29_%2868637%29.exe";
    hash = "sha256-gbNzLRZr6cLYQ5cDtzU8JNsKwAYCaCuth4qfexKtjj4=";
    name = "setup_faith_the_unholy_trinity_1.4.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$out" "$src"
    if [ -d "$out/app" ]; then
      cp -a "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi
    rm -rf "$out/tmp" "$out/commonappdata" "$out/__redist"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico
    # Drop the bonus "goodies/" tree (videos, screenshots, the side game
    # Demon Siege) -- it bloats the closure and is not loaded by FAITH.exe.
    # Keep the side game accessible via the bonuses dir if a future
    # contributor wants it as its own slug.
    rm -rf "$out/goodies"
  '';

  runtime = "proton";
  executable = "FAITH.exe";

  # FAITH writes saves into AppData/Local/FAITH on Windows.
  saveLocations = [ "AppData/Local/FAITH" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "FAITH: The Unholy Trinity (Airdorf 2022, retro-PC horror trilogy, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "faith-the-unholy-trinity";
  };
}
