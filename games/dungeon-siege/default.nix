{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Dungeon Siege v1.11.1 (GOG build 52932) with
  # the AMD RDNA fix bundled. Two-part Inno Setup installer (.exe + .bin
  # slice). innoextract reads them together when they sit next to each
  # other with the original GOG filenames; we symlink them in $TMPDIR
  # before extracting.
  #
  # Note: this is the base-game GOG product (rootGameId 1185868626).
  # GOG ships Legends of Aranna only as a separate listing; the expansion
  # is not included here.
  setupExe = fetchIpfs {
    cid = "QmXnPuv75FK5EshQ8CCyEuDjoU6Ta9hHuvZZ7LNNE38LH1";
    fallbackUrl = "https://archive.org/download/setup_dungeon_siege_1.11.1_amd_rdna_fix_52932-1/Dungeon%20Siege%20I%20%282002%29/setup_dungeon_siege_1.11.1_amd_rdna_fix_%2852932%29.exe";
    hash = "sha256-PivdeBcE/GUhtYi0A4mhw5aNBvQULDUjs+aymXBYqQo=";
    name = "dungeon-siege-gog-1.11.1-rdna.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "Qmd1iATRQFXwpXUijY84BTAYHxMAd4WcPPKcVvfV58b8yi";
    fallbackUrl = "https://archive.org/download/setup_dungeon_siege_1.11.1_amd_rdna_fix_52932-1/Dungeon%20Siege%20I%20%282002%29/setup_dungeon_siege_1.11.1_amd_rdna_fix_%2852932%29-1.bin";
    hash = "sha256-7kPcuPtSfDcmY1rrXZ/HLp85Hn6sNpQ0vKM04360DMg=";
    name = "dungeon-siege-gog-1.11.1-rdna.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dungeon-siege";

  ipfsSources = [
    setupExe
    setupBin1
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  # GOG's installer puts game files at the installer root (DungeonSiege.exe,
  # Maps/, Resources/, Mss32.dll, etc.). app/ contains only the launcher
  # icon + webcache and is dropped along with the other installer metadata
  # subtrees (__redist, __support, tmp, commonappdata).
  #
  # The install ships per-LCID resource subdirs (1028/1031/1033/1036/1040/
  # 1041/1042/3082) each containing dwintl.dll + dir.lqd20 — the engine
  # calls GetUserDefaultLangID() at startup and loads strings from the
  # matching folder. The GOG French-locale installer leaves all eight in
  # place; under Proton's default user locale the engine has historically
  # landed on 1041 (Japanese). Strip every non-English LCID dir at build
  # time so the engine has only 1033 to pick from regardless of what
  # GetUserDefaultLangID returns inside the wineprefix.
  #
  # Round 2 — the LCID strip alone wasn't enough; the user still saw
  # Japanese menus and Japanese subtitles. goggame-1185868626.info
  # declares `"language": "French"` / `"languages": ["fr-FR"]`, but this
  # build ships *Japanese* localization assets at the install root (the
  # kind of mixup the GOG repacker apparently never caught):
  #
  #   - language.dll                — Japanese loader (Shift-JIS / CP932
  #                                   byte patterns visible in `strings`)
  #   - Resources/Language.dsres    — localized menu + subtitle bundle
  #   - Resources/Voices.dsres      — localized VO (left in place for
  #                                   now; round 3 if user reports JP
  #                                   audio)
  #
  # Per community guidance (DS1 Troubleshooting Guide, Dungeon Siege
  # Heaven forum, the GOG/Steam DS1 language threads): the *English*
  # release of Dungeon Siege simply does not ship language.dll or
  # Resources/Language.dsres — the engine reads localizable strings
  # from those files when they exist and falls back to the English
  # defaults compiled into Logic.dsres / the executable when they're
  # absent. Drop the two known-Japanese files so the engine takes the
  # English fallback path. Leave Voices.dsres and Sound.dsres in place;
  # removing Sound.dsres would silence ambient/music, and Voices.dsres
  # may turn out to be English VO with localization only in
  # Language.dsres (otherwise bump to round 3).
  buildScript = ''
    mkdir -p "$out"
    mkdir -p "$TMPDIR/ds"
    ln -s ${setupExe}  "$TMPDIR/ds/setup_dungeon_siege_1.11.1_amd_rdna_fix_(52932).exe"
    ln -s ${setupBin1} "$TMPDIR/ds/setup_dungeon_siege_1.11.1_amd_rdna_fix_(52932)-1.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/ds/setup_dungeon_siege_1.11.1_amd_rdna_fix_(52932).exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    rm -rf "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" "$out/app" 2>/dev/null || true
    for lcid in 1028 1031 1036 1040 1041 1042 3082; do
      rm -rf "$out/$lcid"
    done
    rm -f "$out/language.dll" "$out/Resources/Language.dsres"
  '';

  runtime = "proton";
  executable = "DungeonSiege.exe";

  # Belt-and-suspenders: pin the wineprefix locale to US English so the
  # engine's GetUserDefaultLangID() returns 0x0409 (1033) and resolves
  # to the only LCID subdir still present.
  env = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # Dungeon Siege writes user data under My Documents/Dungeon Siege/
  # (Save/, Maps/, characters, options). Relocate so wineprefix wipes
  # don't take saves with them.
  saveLocations = [ "Documents/Dungeon Siege" ];

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
    description = "Dungeon Siege (Gas Powered Games 2002, GOG v1.11.1 + AMD RDNA fix, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeon-siege";
  };
}
