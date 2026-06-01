{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "the-cat-lady";

  src = fetchIpfs {
    cid = "QmTqn8YPyiBbN4WVF4tar46mnyTx8KGU3PZNUF4zBzV4ip";
    fallbackUrl = "https://archive.org/download/the_cat_lady_1.7_20820_win_gog_20240216/setup_the_cat_lady_1.7_%2820820%29.exe";
    hash = "sha256-1GTK+Jfkdziu+IDAs0tDtY90+Cgf2Lz5gpcDC/YVqCI=";
    name = "setup_the_cat_lady_1.7.exe";
  };

  nativeBuildInputs = [ innoextract ];

  # The Cat Lady (Harvester Games 2012). GOG Inno installer v1.7
  # (build 20820); innoextract --gog yields the game tree under app/.
  # The runtime is a Windows AGS engine binary (~1 GiB unpacked) plus
  # the Wadjet Eye-style data files (audio, sprites). We discard GOG's
  # installer scaffolding (`tmp/`, `commonappdata/`, `__redist/`).
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
  '';

  runtime = "proton";
  executable = "TheCatLady.exe";

  # AGS games typically write saves alongside the binary; the engine
  # checks AppData/Roaming first on modern Windows. Cover both: install
  # dir is in the per-game fuse-overlayfs upper, AppData is preserved
  # via saveLocations.
  saveLocations = [ "AppData/Roaming/Harvester Games/The Cat Lady" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "The Cat Lady (Harvester Games 2012 AGS adventure, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-cat-lady";
  };
}
