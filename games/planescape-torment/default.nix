{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  src = fetchIpfs {
    cid = "QmaqqPrfcQjzLyWmcAMMth42qRLwH7MWq32DnYMNehsmWm";
    fallbackUrl = "https://archive.org/download/planescape_202602/planescape.zip";
    hash = "sha256-8lXxzChr3wLlAPCbd4UUwhVvdSnLGuXQtfnCgR3Z6EY=";
    name = "planescape-torment.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "planescape-torment";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/planescape/setup_planescape_torment_1.01_(a)_(10597).exe"
    # GOG layout: .bif files + dialog.tlk live under app/, while the
    # actual Torment.exe + ini files (Torment.ini, beast.ini,
    # quests.ini, Keymap.ini, autonote.ini, layout.ini) live under
    # app/__support/app/. Copy both layers, then drop install-time
    # scaffolding so the resulting tree matches a real GOG install.
    cp -r "$TMPDIR/iss/app"/. "$out"/
    cp -r "$TMPDIR/iss/app/__support/app"/. "$out"/
    rm -rf "$out/__support" "$out/webcache.zip"
  '';

  # GemRB, the open-source Infinity Engine reimplementation. Reads the
  # GOG-shipped .bif/.tlk/.are/etc. files directly. Native Linux
  # binary, no Wine, no CD-prompt nonsense.
  runtime = "native";

  runScript = ''
    mkdir -p "$STROM_CACHEDIR/gemrb-cache" "$STROM_GAMEDIR/save"
    cat > "$STROM_GAMEDIR/GemRB.cfg" <<EOF
    GameType=pst
    GamePath=$GAMEDIR/
    SavePath=$STROM_GAMEDIR/save/
    CachePath=$STROM_CACHEDIR/gemrb-cache/
    GemRBPath=${pkgs.gemrb}/share/gemrb
    GUIScriptsPath=${pkgs.gemrb}/share/gemrb
    PluginsPath=${pkgs.gemrb}/lib/plugins
    GemRBOverridePath=${pkgs.gemrb}/share/gemrb
    GemRBUnhardcodedPath=${pkgs.gemrb}/share/gemrb
    Width=1920
    Height=1080
    Bpp=32
    Fullscreen=1
    EOF
    exec ${lib.getExe pkgs.gamescope} -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --expose-wayland -- \
      ${lib.getExe pkgs.gemrb} -c "$STROM_GAMEDIR/GemRB.cfg" "$@"
  '';

  meta = {
    description = "Planescape: Torment (1999, GOG 1.01a + GemRB engine)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "planescape-torment";
  };
}
