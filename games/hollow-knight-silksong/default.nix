{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmQV4uWyt7NbkMWX949SVsr2yNczDsoEbQbH9FgZR6X2jU";
    fallbackUrl = "https://archive.org/download/hollow-knight-silksong-portable.-7z/Hollow%20Knight%20Silksong%20%28Portable%29.7z";
    hash = "sha256-N50ksaurFfzYAYsxF9ulUEekiau0vKgeFa/4e6FxUJ4=";
    name = "hollow-knight-silksong.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hollow-knight-silksong";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/sk"
    cp -r "$TMPDIR/sk/Hollow Knight Silksong"/. "$out"/
  '';

  runtime = "proton";
  executable = "Hollow Knight Silksong.exe";

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
    description = "Hollow Knight: Silksong (Unity, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hollow-knight-silksong";
  };
}
