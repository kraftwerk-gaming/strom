{
  self,
  lib,
  pkgs,
  fetchurl,
  fetchIpfs,
  unar,
  unzip,
  writeText,
}:

let

  # Official EA English freeware release (First Decade, includes Firestorm)
  gameEn = fetchIpfs {
    cid = "QmagHQjFDHYaRQ23jQXUWkeWSn4uB1BenjkG8ann8myxUk";
    fallbackUrl = "https://archive.org/download/command-and-conquer-tiberian-sun/OfficialCnCTiberianSun.rar";
    hash = "sha256-sEIZ5xVRHem6ov65gnATyOEG+Na5tWOTa4ovZQMF3sU=";
    name = "tibsun-en.rar";
    };

  # cnc-ddraw for DirectDraw compatibility
  cncDdraw = fetchurl {
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-CxOriaZMmRgYmx2t1EnvbtPLO3sZyr2W2K29lVBbuQg=";
    name = "cnc-ddraw.zip";
  };

  ddrawIni = writeText "ddraw.ini" ''
    [ddraw]
    renderer=opengl
    windowed=true
    fullscreen=false
    maintas=true
    adjmouse=true
    handlemouse=true
    maxfps=60
    singlecpu=true
    nonexclusive=true
  '';

  sunIni = writeText "SUN.INI" ''
    [Intro]
    PlaySide01=no
    PlaySide00=no

    [Options]
    NoCD=Yes
    SingleProcAffinity=Yes
    GameSpeed=3
    Difficulty=1
    ScrollMethod=0
    ScrollRate=3
    AutoScroll=yes
    DetailLevel=2
    SidebarCameoText=yes
    UnitActionLines=yes
    ToolTips=yes

    [Video]
    AllowHiResModes=yes
    UseGraphicsPatch=Yes
    ScreenWidth=1920
    ScreenHeight=1080
    StretchMovies=yes

    [Audio]
    SoundVolume=0.700000
    VoiceVolume=1.000000
    ScoreVolume=0.500000
    IsScoreRepeat=no
    IsScoreShuffle=no
    SoundLatency=9

    [MultiPlayer]
    PhoneIndex=-1
    Color=0
    Side=GDI
    Handle=Commander
    PreferredServer=Euro Server
    Locale=0

    [Network]
    Socket=65535
    NetCard=0
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "command-conquer-tiberian-sun";

  src = gameEn;

  nativeBuildInputs = [
    unar
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"

    # Extract English base game + Firestorm from EA freeware release
    unar -f -o /tmp/ts-en ${gameEn}
    cp -r "/tmp/ts-en/EA Games/Command & Conquer The First Decade/Command & Conquer(tm) Tiberian Sun(tm)/SUN/"* "$out/"
    rm -rf /tmp/ts-en

    # Install cnc-ddraw
    unzip -o ${cncDdraw} ddraw.dll -d "$out/"

    # Install config files
    cp ${ddrawIni} "$out/ddraw.ini"
    cp ${sunIni} "$out/SUN.INI"

    chmod -R u+w "$out"
  '';

  runtime = "proton";
  executable = "Game.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 1920 -h 1080 -r 60 --force-grab-cursor";

  preRun = ''
    export LD_LIBRARY_PATH="/usr/lib32''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export WINEDLLOVERRIDES="ddraw=n,b"
    export PROTON_USE_WINED3D="1"
  '';

  env = {
    STAGING_WRITECOPY = "1";
  };

  meta = {
    description = "Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-tiberian-sun";
  };
}
