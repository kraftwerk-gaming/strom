{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  gameSrc = fetchIpfs {
    cid = "QmXd9RfJ3RU367weYAqgABPND21CReDApUMWqxCgDNVr8p";
    fallbackUrl = "https://archive.org/download/forbidden-siren-collection/Forbidden%20Siren%20%282004%29.zip";
    hash = "sha256-6bfe5PUKvgdj9hrAv7BQkj2cM1p0KTGVa2h6rWxQLh4=";
    name = "ForbiddenSiren.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "forbidden-siren";
  src = gameSrc;

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/x"
    cp "$TMPDIR/x/Forbidden Siren (2004)/Forbidden Siren (Europe).iso" "$out/forbidden-siren.iso"
  '';

  runtime = "pcsx2";
  executable = "forbidden-siren.iso";

  meta = {
    description = "Forbidden Siren (Sony 2003, PAL PS2, via PCSX2)";
    mainProgram = "forbidden-siren";
    platforms = [ "x86_64-linux" ];
  };
}
