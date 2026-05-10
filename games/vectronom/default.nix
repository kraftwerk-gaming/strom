{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmTnxWwDgKSjffrCxmSmiaxxt5MmdxqqA5PY4BTip76aVe";
    fallbackUrl = "https://ipfs.io/ipfs/QmTnxWwDgKSjffrCxmSmiaxxt5MmdxqqA5PY4BTip76aVe";
    hash = "sha256-Xxp7uF6Oqjwjvr3uoUMZkeJPIX3mRbmcX/kX0VADAYs=";
    name = "vectronom-repackgames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vectronom";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Vectronom.v1.1.4.2182.2322/"* "$out"/
  '';

  runtime = "proton";
  executable = "Vectronom.exe";

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
    description = "Vectronom (Ludopium 2019 rhythm puzzle, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vectronom";
  };
}
