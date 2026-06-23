{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unar,
}:

let
  # Sid Meier's Civilization IV: The Complete Edition (Firaxis 2005-2008,
  # DRM-free GOG build 2.0.0.4) -- base game + Warlords + Beyond the Sword +
  # Colonization. Two-part GOG Inno Setup installer (.exe stub + a single
  # -1.bin payload slice). innoextract reads them together when they sit
  # next to each other with the original GOG filenames; we symlink them in
  # $TMPDIR before extracting with `innoextract --gog`.
  #
  # The Gamebryo engine renders through Direct3D9 (DXVK handles it under
  # Proton). Beyond the Sword (game/Civ4/Beyond the Sword/Civ4BeyondSword.exe)
  # is the canonical launch target -- it is the final, most-patched
  # expansion and includes the Warlords content.
  setupExe = fetchIpfs {
    cid = "Qme5gCJd65fFqtYwq1tA1k7igvsNyZJMQQLfkNdys2ZkQK";
    fallbackUrl = "https://archive.org/download/sid-meiers-civilization-iv-complete-gog/Sid%20Meier%27s%20Civilization%20IV%20Complete%20%5BGOG%5D/setup_civilization4_complete_2.0.0.4.exe";
    hash = "sha256-C5bNwWNekxHbk+zA8spHjAxKdLXSewYm0e2Z+Dau6ho=";
    name = "sid-meiers-civilization-iv-complete-2.0.0.4.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "QmQQnubn2XRTGZtyjbv2NrdZVsNZ9NPfevwKDvwsDZw7Ls";
    fallbackUrl = "https://archive.org/download/sid-meiers-civilization-iv-complete-gog/Sid%20Meier%27s%20Civilization%20IV%20Complete%20%5BGOG%5D/setup_civilization4_complete_2.0.0.4-1.bin";
    hash = "sha256-lzYTN8rp0a8sG2iHzGuS/xb2t/vkQXSnhYIH2kKYEX4=";
    name = "sid-meiers-civilization-iv-complete-2.0.0.4-1.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sid-meiers-civilization-iv";

  ipfsSources = [
    setupExe
    setupBin1
  ];

  src = setupExe;

  # innoextract shells out to `unar` to decompress the RAR-compressed GOG
  # payload slices inside the .bin, so unar must be on PATH.
  nativeBuildInputs = [
    innoextract
    unar
  ];

  # innoextract --gog lays the GOG install tree under a game/ subdir:
  # game/Civ4/Civilization4.exe, game/Civ4/Warlords/Civ4Warlords.exe,
  # game/Civ4/Beyond the Sword/Civ4BeyondSword.exe, game/Civ4Colonization/.
  # Alongside it the installer drops setup-only trees we don't ship:
  #   support/, DirectXpackage/, __unpacker/, userappdata/  (installer debris)
  #   userdocs/  -- the GOG seed copies of My Games/<title>/CivilizationIV.ini
  #                that the installer would place in the user's Documents.
  # We keep the whole game/ tree at $out, plus userdocs/ (preRun seeds the
  # per-game ini from it), and strip the rest of the installer debris.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/gog"
    ln -s ${setupExe}  "$TMPDIR/gog/setup_civilization4_complete_2.0.0.4.exe"
    ln -s ${setupBin1} "$TMPDIR/gog/setup_civilization4_complete_2.0.0.4-1.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/gog/setup_civilization4_complete_2.0.0.4.exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"

    rm -rf "$out/support" "$out/DirectXpackage" "$out/__unpacker" \
           "$out/userappdata" "$out/__redist" "$out/__support" \
           "$out/tmp" "$out/commonappdata" "$out/app" 2>/dev/null || true
    rm -f "$out"/game/goggame-*.dll "$out"/game/goggame-*.info \
          "$out"/game/goggame-*.hashdb "$out"/game/goggame-*.ico \
          "$out"/game/goggame-*.script "$out"/galaxy_*.exe \
          "$out"/*.url "$out"/autorun.exe "$out"/autorun.inf \
          "$out"/game/*.pdf 2>/dev/null || true
  '';

  runtime = "proton";

  # Beyond the Sword is the canonical launch target for the Complete Edition
  # (the final, most-patched expansion; it carries the Warlords content too).
  # The GOG payload nests every game under game/.
  executable = "game/Civ4/Beyond the Sword/Civ4BeyondSword.exe";

  preRun = ''
    # Civ4 reads its per-game config from Documents/My Games/<title>/
    # CivilizationIV.ini and creates the file (with sensible defaults) on
    # first run. The GOG installer ships seed copies of those inis under
    # userdocs/My Games/ -- seed them into the wineprefix Documents on first
    # launch and add NoIntroMovie=1 so the engine skips the pre-menu Bink
    # intro/publisher movies (a common Proton hang point for the Gamebryo
    # intro player) and goes straight to the main menu. The verified GOG
    # 2.0.0.4 subfolder names are: "Beyond The Sword", "Civ4", "Warlords",
    # "Civ4Colonization".
    docs="$STROM_COMPATDATA/0/pfx/drive_c/users/steamuser/Documents"
    seed="$STROM_OVERLAY/userdocs/My Games"
    if [ -d "$seed" ] && [ ! -d "$docs/My Games/Beyond The Sword" ]; then
      mkdir -p "$docs/My Games"
      cp -rn "$seed"/. "$docs/My Games"/ 2>/dev/null || true
      chmod -R u+w "$docs/My Games" 2>/dev/null || true
      for __t in "Beyond The Sword" "Civ4" "Warlords" "Civ4Colonization"; do
        ini="$docs/My Games/$__t/CivilizationIV.ini"
        if [ -f "$ini" ] && ! grep -qi "NoIntroMovie" "$ini"; then
          printf '\nNoIntroMovie = 1\n' >> "$ini"
        fi
      done
    fi
  '';

  # Civ4 writes savegames + config under Documents/My Games/<title>/, one
  # subfolder per game. The verified GOG 2.0.0.4 folder names (from the
  # installer's userdocs/ seed tree) are below. Relocate them into
  # $STROM_GAMEDIR so they survive wineprefix wipes.
  saveLocations = [
    "Documents/My Games/Beyond The Sword"
    "Documents/My Games/Civ4"
    "Documents/My Games/Warlords"
    "Documents/My Games/Civ4Colonization"
  ];

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
    description = "Sid Meier's Civilization IV: The Complete Edition (Firaxis 2005, GOG build 2.0.0.4, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sid-meiers-civilization-iv";
  };
}
