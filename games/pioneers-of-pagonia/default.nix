{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # SteamGG pre-installed crack (build ~21132237 / ~v1.0, 2025-12-11).
  # Custom (non-Unity) engine: a ~467 MB "Pioneers of Pagonia.exe" at the root
  # alongside a "pak/" asset tree, fmod, D3D12, and EOS/Galaxy SDK stubs,
  # bundled with a cracked steam emu (steam_api64.dll + steam_emu.ini).
  src = fetchIpfs {
    cid = "QmS5RZD8tD9r2cXg3Rr8NRgy33ufp4dyRa5QjLCbHQBVpq";
    fallbackUrl = "https://pixeldrain.com/api/file/w4DADniZ";
    hash = "sha256-MsGZO9cUPPjnWXoa0AEL/jiV6XL0r6WyLk1+cYjAYqg=";
    name = "pioneers-of-pagonia-steamgg.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pioneers-of-pagonia";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Archive root is "Pioneers of Pagonia-SteamGG.NET/". Lift its contents to
  # $out and drop the repack's ~1.3 GB of bonus content (soundtrack, wallpaper,
  # PDF guide) the game itself never needs. unzip returns exit 1 on a benign
  # warning (one .url entry has a non-UTF-8 "local" filename that mismatches its
  # central-directory name); `|| true` swallows it, then we assert the
  # executable actually extracted.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" || true
    cp -r "$TMPDIR/extract/Pioneers of Pagonia-SteamGG.NET/"* "$out"/
    chmod -R u+w "$out"
    rm -rf \
      "$out/Pioneers of Pagonia Original Soundtrack" \
      "$out/Supporter Edition Wallpaper" \
      "$out/Official Guide"
    rm -f "$out"/*.url "$out"/*.txt
    test -f "$out/Pioneers of Pagonia.exe"
  '';

  runtime = "proton";
  executable = "Pioneers of Pagonia.exe";

  # Best-guess save path (vendor: Envision Entertainment). The engine is custom,
  # not Unity, so the real location is unconfirmed — verify during the
  # interactive test (find newer files under the prefix's steamuser dir) and
  # correct this before the game lands on master.
  saveLocations = [ "AppData/LocalLow/Envision Entertainment GmbH/Pioneers of Pagonia" ];

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the nest so edge-scrolling the camera works:
      # without grabbing the cursor, pushing to the screen edge slides it out
      # of the gamescope window instead of scrolling (same as the RTS games
      # here, e.g. company-of-heroes / command-conquer).
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Pioneers of Pagonia (Envision Entertainment 2023, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pioneers-of-pagonia";
  };
}
