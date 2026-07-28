{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Mass Effect (BioWare 2008, the original PC release -- NOT the 2021
  # Legendary Edition remaster). Unreal Engine 3, Windows-only, so
  # runtime = "proton".
  #
  # SOURCE: archive.org item `RusMassEffect` ("Mass Effect (Russian)"),
  # a zip of an already-INSTALLED game tree from the 1C/Snowball "Mass
  # Effect Gold" DVD release: Binaries/ (MassEffect.exe plus the
  # bundled PhysX 2.7, Bink and OpenAL runtimes), BioGame/, Engine/ and
  # the DLC_UNC add-on ("Bring Down the Sky"). No installer runs at
  # build time -- unzip plus a config swap is the whole build.
  #
  # WHY NOT the retail disc images. The packaging request pointed at
  # archive.org `mass-effect-1_202510` ("Mass Effect (PC) Denmark").
  # Its MassEffect.7z is not a game tree: it wraps the two retail DVD
  # ISOs. Those discs do install from plain RAR payloads (data/*.rar,
  # enumerated by data/installmanifest_en.ini), so a headless
  # build-time extraction would be possible -- but the MassEffect.exe
  # they install is SecuROM 7 with Product Activation. It authenticates
  # against pa01.sonyvfactory.com, which Sony retired years ago, and
  # SecuROM's ring-0 tricks do not work under Wine/Proton regardless.
  # The other reachable dumps (`czlevel192dvd`, `me-install`) are the
  # same retail discs and hit the same wall.
  #
  # This tree does not: its Binaries/MassEffect.exe is already
  # DRM-neutralised (DOS stub reads "Crack:RELOADED,fix:RUS
  # Guy,Eddd,Gniarf"; the SecuROM activation call at file offset
  # 0x1F61BD is replaced with `mov eax,0` and the three checks on its
  # result are NOPped), so the engine starts with no activation server.
  #
  # LANGUAGE: the 1C release ships each localisation twice --
  # BioGame/CookedPC holds both *_LOC_int (English) and *_LOC_RA
  # (Russian) packages -- and BioGame/Config/DefaultEngine.ini is
  # seeded with Language=RA. The 1C launcher switched that by copying
  # data/config1 (RA) or data/Config2 (INT) over BioGame/Config; the
  # build does the INT copy itself, then drops data/, the launcher and
  # the 1C uninstaller / advert catalog.
  src = fetchIpfs {
    cid = "Qmai8dcSmBgTA7p32wLKb3rqyx7oXy5mr9UbySBYXPvaud";
    fallbackUrl = "https://archive.org/download/RusMassEffect/Mass%20Effect.zip";
    hash = "sha256-2rKbqFKSf8NDsi88bNSR2OY8qlsdU39214geIBGz+ZQ=";
    name = "mass-effect-1c-gold-preinstalled.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mass-effect";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
    chmod -R u+w "$out"

    # Switch the shipped config set from Russian to English (see the
    # LANGUAGE note above), then drop the swap sets themselves.
    cp -f "$out"/data/Config2/*.ini "$out/BioGame/Config/"
    grep -q '^Language=INT' "$out/BioGame/Config/DefaultEngine.ini"

    # UE3 seeds Documents\BioWare\Mass Effect\Config\BIOEngine.ini from
    # this file on first run, so the startup resolution has to be right
    # here -- once the user config exists the default is never read
    # again. 1024x768 is the shipped value; gamescope renders 1080p.
    # The .ini set is CRLF, so the replacements carry their own \r.
    sed -i -e 's/^StartupResolutionX=.*/StartupResolutionX=1920\r/' \
           -e 's/^StartupResolutionY=.*/StartupResolutionY=1080\r/' \
      "$out/BioGame/Config/DefaultEngine.ini"

    # 1C shell: the launcher (which only picked a language and then
    # ran Binaries/MassEffect.exe), the InstallShield uninstaller, and
    # the "catalog" advert bundle of mp3s / .url shortcuts.
    rm -rf "$out/data" "$out/catalog" "$out/catalogt" "$out/URL"
    rm -f "$out/MassEffectLauncher.exe" "$out/MassEffectLauncher.dll" \
          "$out/me_gold_remove.dll" "$out/uninstall.exe" \
          "$out/uninstall.cmd" "$out/DeIsL1.isu"
  '';

  runtime = "proton";
  executable = "Binaries/MassEffect.exe";

  # Verified by launching once and diffing the prefix: the ONLY
  # non-Microsoft tree the engine writes under
  # drive_c/users/steamuser is Documents\BioWare\Mass Effect, and it
  # holds everything that matters --
  #   Save\      Profile.MassEffectProfile plus the per-career .Sav set
  #   Config\    the BIO*.ini the engine generates from BioGame/Config
  #              on first run (BIOEngine/BIOGame/BIOInput/...)
  #   Published\CookedPC\LocalShaderCache-PC-D3D-SM3.upk
  #   Logs\
  # Relocating the parent therefore also spares a full shader
  # recompile after a prefix wipe. Ignore the SavePath=..\BioGame\Save
  # line in the generated BIOEngine.ini: that is UE3's stock legacy
  # path, and BIOGame.ini's m_bUseNewSaveSystem=TRUE means ME1 uses the
  # Documents tree instead -- nothing is ever created under
  # BioGame\Save. The only other write is Proton's own regenerable
  # AppData\Local\dxvk shader cache.
  saveLocations = [ "Documents/BioWare/Mass Effect" ];

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
    description = "Mass Effect (BioWare 2008 original + Bring Down the Sky, 1C Gold preinstalled tree, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mass-effect";
  };
}
