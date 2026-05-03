{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "paquerette-down-the-bunburrows";

  src = fetchIpfs {
    cid = "QmTgYbvTYLCC8pCPJFNBnJehXfg3zUicnuat7zBtkgEtqF";
    fallbackUrl = "";
    hash = "sha256-Y57euC70tDY19pYVenPb0bF+f4xK/vdMj+HZr5VVE6g=";
    name = "paquerette-down-the-bunburrows.zip";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y $src -o"$out"
    shopt -s dotglob
    mv "$out/Build16Windows"/* "$out"/
    rmdir "$out/Build16Windows"
  '';

  runtime = "proton";
  executable = "Paquerette Down the Bunburrow.exe";

  meta = {
    description = "Paquerette Down the Bunburrows (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "paquerette-down-the-bunburrows";
  };
}
