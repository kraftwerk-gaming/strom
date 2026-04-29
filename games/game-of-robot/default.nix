{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  gamescope,
  unzip,
}:

let

  dosboxConf = pkgs.writeText "game-of-robot.conf" ''
    [sdl]
    fullscreen=false
    output=surface
    windowposition=0,0
    showmenu=false

    [dosbox]
    machine=svga_s3
    memsize=16

    [render]
    aspect=true

    [cpu]
    core=auto
    cputype=auto
    cycles=auto

    [autoexec]
    mount c .
    c:
    robot1.exe
    exit
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "game-of-robot";

  src = fetchIpfs {
    cid = "bafkreifexrphk6ypefm2jxwzurmux7ulttdxwcfh2ucmt3jx3zydszg2pu";
    fallbackUrl = "https://archive.org/download/msdos_Game_of_Robot_The_1988/Game_of_Robot_The_1988.zip";
    hash = "sha256-pLxedXsPIVmk3tmkWUv+i5zHewin1QTJ7TfecDlk2n0=";
    name = "game-of-robot.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -o $src -d /tmp/robot
    cp -r /tmp/robot/TheGameo/* "$out"/
  '';

  runtime = "native";

  runScript = ''
    export XDG_CONFIG_HOME="$GAMEDIR/.config"

    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --expose-wayland -- \
      ${dosbox-x}/bin/dosbox-x -nomenu -conf ${dosboxConf}
  '';

  meta = {
    description = "The Game of Robot (1988, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "game-of-robot";
  };
}
