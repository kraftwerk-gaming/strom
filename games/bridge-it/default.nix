{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Bridge It Plus v1.32 full English version.
  # Source: Rutracker P2P repack (2016, ENG game / RU installer UI).
  # Inno Setup 5.5.7 single-file installer.  Game content is 100 %
  # English: 40 levels (3 tutorial + 6 easy + 7 medium + 8 hard +
  # 8 complex + 8 extra), no -Demo=true flag in BridgeIt.exe, no
  # Cyrillic or Polish bytes in Data.ja.
  #
  # Obtained via the Rutracker torrent (magnet btih
  # A29623EDC13F5BBA2296883A4D31A68065BCE94F) and pinned to IPFS.
  src = fetchIpfs {
    cid = "QmTFNcg4GcaXtrC4cNYQy98A9oFNyzZZ9PQ25Hiz6fTV6i";
    fallbackUrl = "magnet:?xt=urn:btih:A29623EDC13F5BBA2296883A4D31A68065BCE94F";
    hash = "sha256-uFgyfR+rwkdBlVQwkjjoQMAEWJ4OWAM8vs5nM0id/qA=";
    name = "setup_BridgeIt.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bridge-it";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" "$src"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
    # Full installer ships Data.ja already capitalised; guard handles
    # the lowercase variant from older demo builds.
    [ -f "$out/data.ja" ] && mv "$out/data.ja" "$out/Data.ja" || true
    # Remove Steam/installer metadata not needed at runtime.
    rm -f "$out/installscript.vdf"
    # Drop Inno Setup bookkeeping subdirectory if present.
    rm -rf "$out/tmp"
  '';

  runtime = "proton";
  executable = "BridgeIt.exe";

  saveLocations = [ "Documents/Chronic Logic" ];

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
    description = "Bridge It Plus v1.32 (Chronic Logic, EN full, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bridge-it";
  };
}
