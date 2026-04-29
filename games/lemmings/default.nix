{
  self,
  bchunk,
  dosbox-x,
  fetchIpfs,
  gamescope,
  lib,
  p7zip,
  pkgs,
}:

let

  cdBin = fetchIpfs {
    cid = "QmWtMqf1RBi8RR56W9AQi2WFxB6Qt5rjuULkQCPaTB8nKb";
    fallbackUrl = "https://archive.org/download/az-2246/AZ_2246.bin";
    hash = "sha256-o3EUjEYRVXxNP4XL1Bjx0ERiEpJAvMky7RWBbUw4/Pw=";
    name = "lemmings-cd.bin";
  };

  cdCue = fetchIpfs {
    cid = "bafkreid26dvrfmojvwr6zpmop5z6yxyc2f42gi7fpoxreqglscrx6nbrry";
    fallbackUrl = "https://archive.org/download/az-2246/AZ_2246.cue";
    hash = "sha256-evDrErHJraPsvY5/c+xfAtF5oyPle68SQMuQo380MY4=";
    name = "lemmings-cd.cue";
  };

  dosboxConf = pkgs.writeText "lemmings.conf" ''
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
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lemmings";

  ipfsSources = [
    cdBin
    cdCue
  ];
  src = cdBin;

  nativeBuildInputs = [
    bchunk
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out"

    # Extract data track from CD image
    cd /tmp
    bchunk $src ${cdCue} track
    7z x track01.iso -o"$out/"

    # Keep the CUE/BIN for DOSBox CD audio mounting
    cp $src "$out/lemmings.bin"
    # Create a cue file pointing to the local bin
    {
      echo 'FILE "lemmings.bin" BINARY'
      tail -n +2 ${cdCue}
    } > "$out/lemmings.cue"
  '';

  runtime = "native";

  runScript = ''
    export XDG_CONFIG_HOME="$GAMEDIR/.config"

    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --expose-wayland -- \
      ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "imgmount d \"$GAMEDIR/lemmings.cue\" -t cdrom" \
      -c "d:" \
      -c "cd lemmings" \
      -c "vgalemmi.exe" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Lemmings (DOS CD version with CD audio, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lemmings";
  };
}
