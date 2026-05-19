{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # The shipped distributable for Buckshot Roulette is a single
  # all-in-one Godot 4 PE32+ binary -- no installer, no separate
  # .pck/data directory (the .pck is appended to the .exe). We treat
  # the binary itself as the asset and just place it in $out next to a
  # save dir under Proton's prefix.
  src = fetchIpfs {
    cid = "QmS8Z3bVhozDD993VGdRGsqA2kLUdoxQgv5cCCZWNiw7gp";
    hash = "sha256-Chf1Oqs2HFdRvWpKKDiXFxgnKkIBO5IUyRY3uhkgxN4=";
    name = "buckshot-roulette.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "buckshot-roulette";

  inherit src;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/buckshot-roulette.exe"
    chmod +w "$out/buckshot-roulette.exe"
  '';

  runtime = "proton";
  executable = "buckshot-roulette.exe";
  saveLocations = [ "AppData/Roaming/Buckshot Roulette" ];

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
    description = "Buckshot Roulette (2024 Mike Klubnika, Godot 4 / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "buckshot-roulette";
  };
}
