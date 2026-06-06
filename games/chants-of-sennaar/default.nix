{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Chants of Sennaar (Rundisc / Focus Entertainment, 2023). Language-
  # deciphering puzzle/adventure built on Unity. Windows-only on GOG (no
  # native Linux build is offered — the developer ships only the Windows
  # build and points Linux players at Proton), so runtime = "proton".
  #
  # SOURCE: GOG offline installer, slug "chants_of_sennaar", GOG game id
  # 1669000957, Windows build 1.0.0.9_r4 (64bit), GOG build 85665 — a
  # single-part Inno Setup 5.6.2 (unicode) installer, 556,917,352 bytes.
  # innoextract --gog yields the GOG `app/` layout with
  # "Chants Of Sennaar.exe" + "Chants Of Sennaar_Data/" + UnityPlayer.dll
  # at the install root.
  src = fetchIpfs {
    cid = "QmNR74MJe5Sjr7JiVVHsgZvidzzhL2aB9r8f9Gy2sFr3Sr";
    fallbackUrl = "magnet:?xt=urn:btih:92F00759561F3D969263973AF66B84E545EC1A73&dn=chants_of_sennaar";
    hash = "sha256-bQDCBW2+Ei8KKnnSvGUt1ofagFpRA3R7x9C/BMCxsKQ=";
    name = "setup_chants_of_sennaar_1.0.0.9_r4.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "chants-of-sennaar";

  ipfsSources = [ src ];
  inherit src;

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
    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. atomicrops). Unity runs
    # fine without it.
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  # Verified from the extracted GOG install tree (build 85665): the exe is
  # "Chants Of Sennaar.exe" (capital O) with a matching "Chants Of
  # Sennaar_Data/" Unity data dir + UnityPlayer.dll at the root.
  executable = "Chants Of Sennaar.exe";

  # Unity LocalLow tree: AppData/LocalLow/Rundisc/Chants Of Sennaar on
  # Windows (journal_X / places_X per save slot).
  saveLocations = [ "AppData/LocalLow/Rundisc/Chants Of Sennaar" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Chants of Sennaar (Rundisc 2023, Unity language-deciphering adventure, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "chants-of-sennaar";
  };
}
