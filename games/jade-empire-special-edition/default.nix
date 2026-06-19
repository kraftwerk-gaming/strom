{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # Jade Empire: Special Edition (BioWare 2007 PC port of the 2005 Xbox
  # original), GOG re-release v1.00 build 15538, repacked as a single RAR
  # by an archive.org uploader. The RAR contains the Inno Setup GOG
  # installer (setup_jade_empire_1.00_(15538).exe + .bin disks) plus a
  # Goodies/ tree of zipped extras (artbook, manual, soundtrack, etc.)
  # which we drop. innoextract --gog produces the game tree with
  # JadeEmpire.exe + JadeEmpireConfig.exe + data subdirs at the top
  # level. The engine is BioWare's Aurora variant (same lineage as KotOR
  # and Neverwinter Nights), runs DRM-free under Proton.
  src = fetchIpfs {
    cid = "QmUjDgq9FLYBR3bYZsKRZPNfMzXK2Hppv9pgEgyjisTgA2";
    fallbackUrl = "https://archive.org/download/jade.-empire.-special.-edition/Jade.Empire.Special.Edition.rar";
    hash = "sha256-1vppem0lCe4HZRYa9B2LlPWJLsnfNPjIgqh0VJHjUSE=";
    name = "jade-empire-special-edition.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "jade-empire-special-edition";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rar/Jade.Empire.Special.Edition/setup_jade_empire_1.00_(15538).exe"
    # GOG Inno layout: game files live at the root of the extract dir.
    # The optional app/ subdir is GOG's pre-1.2 installer convention; cover
    # both layouts so we don't depend on which Inno wrapper version was used.
    if [ -d "$TMPDIR/iss/app" ]; then
      cp -r "$TMPDIR/iss/app"/. "$out"/
    else
      cp -r "$TMPDIR/iss"/. "$out"/
    fi
    # Strip GOG installer scaffolding + Galaxy redists; the Aurora engine
    # has no runtime dependency on any of this.
    rm -rf "$out/app" "$out/__redist" "$out/tmp" "$out/commonappdata" \
           "$out/__support"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf" \
          "$out/EULA.txt" "$out/webcache.zip"
  '';

  runtime = "proton";
  executable = "JadeEmpire.exe";

  # The Aurora engine writes savegames binary-adjacent, into a Save/
  # subdir of the install folder (PCGamingWiki: "{{p|game}}\Save\"),
  # NOT into Documents/ or AppData/LocalLow. The install dir is the
  # fuse-overlayfs game overlay whose writable upper IS $STROM_GAMEDIR
  # (= ~/.strom/<slug>/ on plain btrfs; see lib/bwrap.nix), so writes
  # to Save/ land there and persist across prefix/overlay wipes with no
  # relocation needed — hence saveLocations is empty. (The lib's
  # steamuser-rooted migration in lib/proton.nix only handles
  # drive_c/users/steamuser paths and does not apply here.) Verified at
  # build time: the fresh tree has no Save/ dir; the engine creates it
  # on first save, and a prior test run already produced a persisted
  # ~/.strom/jade-empire-special-edition/Save/.
  saveLocations = [ ];

  # Force 1920x1080 widescreen on every launch. The Aurora engine reads
  # JadeEmpire.ini from the install dir (the merged overlay); the file is
  # created lazily by JadeEmpireConfig.exe on first launch with 640x480
  # Widescreen=0, which is what the user sees. Patch in place if the ini
  # already exists, otherwise seed a minimal [Render] block so the engine
  # picks up the resolution from the very first run. Widescreen=1 is
  # mandatory: the engine crashes on a widescreen ScrW/ScrH with Widescreen=0.
  #
  # The edit is done with a temp file under $STROM_GAMEDIR (the overlay's
  # real btrfs upper) plus `cat >` back into place rather than `sed -i`:
  # sed -i renames its temp over the target, and on the fuse-overlayfs
  # merged mount that rename crosses a device boundary ("Invalid
  # cross-device link") and aborts the launch (bwrap exit 4).
  preRun = ''
        __ini="$STROM_OVERLAY/JadeEmpire.ini"
        if [ ! -f "$__ini" ]; then
          cat > "$__ini" <<'EOF'
    [Render]
    D3DAdapter=0
    Widescreen=1
    ScrW=1920
    ScrH=1080
    DispFmt=1
    Windowed=0
    RefreshRate=60
    ClampFPS=0
    EOF
        else
          __tmp="$STROM_GAMEDIR/.JadeEmpire.ini.tmp"
          sed \
            -e 's/^ScrW=.*/ScrW=1920/' \
            -e 's/^ScrH=.*/ScrH=1080/' \
            -e 's/^Widescreen=.*/Widescreen=1/' \
            "$__ini" > "$__tmp"
          cat "$__tmp" > "$__ini"
          rm -f "$__tmp"
        fi
  '';

  env = {
    # GOG store appid for SteamPlay shader/runtime selection. Jade Empire
    # is not on Steam; Proton's per-appid config falls back to defaults,
    # which is what we want for an Aurora-era D3D9 title.
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    PULSE_LATENCY_MSEC = "40";
  };

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
    description = "Jade Empire: Special Edition (BioWare 2007 Aurora-engine PC port, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "jade-empire-special-edition";
  };
}
