{
  dosbox-x,
  fetchurl,
  gamescope,
  runCommandLocal,
  unzip,
  writeShellApplication,
  writeText,
}:

let
  gameArchive = fetchurl {
    url = "https://archive.org/download/msdos_Game_of_Robot_The_1988/Game_of_Robot_The_1988.zip";
    hash = "sha256-pLxedXsPIVmk3tmkWUv+i5zHewin1QTJ7TfecDlk2n0=";
    name = "game-of-robot.zip";
  };

  gameFiles =
    runCommandLocal "game-of-robot-data"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -o ${gameArchive} -d /tmp/robot
        cp -r /tmp/robot/TheGameo/* "$out"/
      '';

  dosboxConf = writeText "game-of-robot.conf" ''
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
writeShellApplication {
  name = "game-of-robot";
  runtimeInputs = [ gamescope ];
  text = ''
    GAMEDIR="''${HOME:-.}/.strom/game-of-robot"
    mkdir -p "$GAMEDIR"

    # Symlink game files
    for f in ${gameFiles}/*; do
      base=$(basename "$f")
      if [ ! -e "$GAMEDIR/$base" ] || [ -L "$GAMEDIR/$base" ]; then
        ln -sf "$f" "$GAMEDIR/$base"
      fi
    done

    cd "$GAMEDIR"
    exec gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --expose-wayland -- \
      ${dosbox-x}/bin/dosbox-x -conf ${dosboxConf}
  '';
}
