{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Super Smash Bros. Melee (USA) (En,Ja) (v1.02). GameCube ISO,
  # 1459978240 bytes (1.36 GiB), the standard verified NTSC-U release.
  iso = fetchIpfs {
    cid = "QmNchGZ9oPDdv9DZjtXLkDnvyGoMsPY8rUAwY5eknYCbzb";
    fallbackUrl = "https://archive.org/download/super-smash-bros.-melee-usa-en-ja-v-1.02/Super%20Smash%20Bros.%20Melee%20%28USA%29%20%28En%2CJa%29%20%28v1.02%29.iso";
    hash = "sha256-DeBZgaNBVrnO3O9zxz1CRKwFz2FJqzyc/tkXaYgZ5GQ=";
    name = "super-smash-bros-melee.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-smash-bros-melee";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/melee.iso"
  '';

  runtime = "dolphin";
  executable = "melee.iso";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Super Smash Bros. Melee (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "super-smash-bros-melee";
  };
}
