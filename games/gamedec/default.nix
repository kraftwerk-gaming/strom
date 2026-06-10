{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Gamedec - Definitive Edition (Anshar Studios 2021/2022). Isometric
  # cyberpunk detective RPG on Unreal Engine 4.27 (64-bit shipping build
  # "GameDEC-Win64-Shipping"). GOG DRM-free, distributed as a four-part
  # Inno Setup 5.6.2 offline installer (setup_..._(64bit)_(60562).exe plus
  # three GOG-Galaxy .bin data slobs). Windows-only on GOG, so
  # runtime = "proton". innoextract --gog reassembles the .exe header with
  # the paired .bin chunks (they must sit in the same directory under their
  # original names); the install tree lands under the `app/` prefix with
  # Engine/ + GameDEC/ subtrees. UE4 -> DXVK handles d3d11 natively.
  #
  # archive.org stores the four parts as separate files. Nix store names
  # cannot contain parens, so each part is fetched under a sanitised name
  # and the buildScript re-links them under the exact original installer
  # names so innoextract pairs them. fetchIpfs's `name` is the store-path
  # name (parens stripped); fallbackUrl points at the archive.org original.
  base = "https://archive.org/download/gamedec_pc/setup_gamedec_-_definitive_edition_20221128_1.7.1.r70100_shipping_%2864bit%29_%2860562%29";

  exe = fetchIpfs {
    cid = "QmcSXNFgdp491vKjsXkcs1Qc4RbS7nQ4Qfh7WwMsfNcrVQ";
    fallbackUrl = "${base}.exe";
    hash = "sha256-lWimwM0iPtMUBdtSbBsbn7lBZQ9WQ4LFOAUVH9BRE8o=";
    name = "setup_gamedec_definitive_edition_1.7.1_60562.exe";
  };
  bin1 = fetchIpfs {
    cid = "QmYpapEoXumkidm99Cd3RWFx2zdoqSaAS9SFsCfwQfAvLd";
    fallbackUrl = "${base}-1.bin";
    hash = "sha256-QfJqmfsVioCDvIcE0fT+jC2O3nR6JBY5313+oLyyjPY=";
    name = "setup_gamedec_definitive_edition_1.7.1_60562-1.bin";
  };
  bin2 = fetchIpfs {
    cid = "QmRKZ8dPEiZzmoSgDHe6MrkquL3xgCFGyFDF5C8QCoQQ4F";
    fallbackUrl = "${base}-2.bin";
    hash = "sha256-GJBaBdvkKrgYovjbWAGGa6iqgoLKfAvc7IxSyLkua9Y=";
    name = "setup_gamedec_definitive_edition_1.7.1_60562-2.bin";
  };
  bin3 = fetchIpfs {
    cid = "QmTWgvBJRpM9XMBC6Vi5NzBCnFGip66nPPyKKXKgcrnE9T";
    fallbackUrl = "${base}-3.bin";
    hash = "sha256-eAyTGx3rSlX5Ly+w1tgkoa6T17ZDT2iAxA/xiD+E0bA=";
    name = "setup_gamedec_definitive_edition_1.7.1_60562-3.bin";
  };

  installerPrefix = "setup_gamedec_-_definitive_edition_20221128_1.7.1.r70100_shipping_(64bit)_(60562)";
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gamedec";

  # The buildScript co-locates all four parts itself; `src` only feeds the
  # required option (its `$src` env var is unused by the custom script).
  src = exe;

  ipfsSources = [
    exe
    bin1
    bin2
    bin3
  ];

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/parts" "$TMPDIR/iss"

    # innoextract reads the GOG split parts by their on-disk names: the
    # .exe header records the `-1.bin`...`-3.bin` siblings by the original
    # installer prefix, so re-link the parens-stripped store paths back to
    # the exact names before extracting.
    ln -s "${exe}" "$TMPDIR/parts/${installerPrefix}.exe"
    ln -s "${bin1}" "$TMPDIR/parts/${installerPrefix}-1.bin"
    ln -s "${bin2}" "$TMPDIR/parts/${installerPrefix}-2.bin"
    ln -s "${bin3}" "$TMPDIR/parts/${installerPrefix}-3.bin"

    # --gog reassembles the split data; restricting to English keeps the
    # install lean (the localisation paks for the other 10 languages are
    # not needed to boot). The game tree (Engine/, GameDEC/) extracts at
    # the top level; `app/` only holds the GOG launcher icon + webcache.
    innoextract --gog --language en-US -d "$TMPDIR/iss" \
      "$TMPDIR/parts/${installerPrefix}.exe"

    cp -a "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"

    # Strip GOG launcher metadata + the bundled Windows redistributables
    # (DirectX/VCRedist/UE4 prereqs); Proton already provides the runtime.
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata" "$out/app" \
           "$out/Gamedec - Definitive Edition"
    rm -f "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.ico \
          "$out"/goggame-*.dll
  '';

  runtime = "proton";
  executable = "GameDEC/Binaries/Win64/GameDEC-Win64-Shipping.exe";

  # UE4 writes saves + config under the LocalAppData game tree
  # (AppData/Local/GameDEC/Saved/{SaveGames,Config} on Windows).
  saveLocations = [ "AppData/Local/GameDEC/Saved" ];

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
    description = "Gamedec - Definitive Edition (Anshar Studios 2021, UE4 isometric cyberpunk RPG, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gamedec";
  };
}
