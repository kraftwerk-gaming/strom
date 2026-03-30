{
  fetchurl,
  gamescope,
  ruffle,
  writeShellApplication,
}:

let
  swf = fetchurl {
    url = "https://archive.org/download/frog-fractions/FrogFractions.swf";
    hash = "sha256-HYVbtOttB7PfEXhPbWXDFlE4q8I5ZSwNRo5aZDH55t0=";
    name = "FrogFractions.swf";
  };
in
writeShellApplication {
  name = "frog-fractions";
  runtimeInputs = [
    gamescope
    ruffle
  ];
  text = ''
    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -- \
      ruffle --no-gui ${swf}
  '';
}
