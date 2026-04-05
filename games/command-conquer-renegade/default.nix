{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let

  # Portable pre-installed English version (patched to 1.037)
  gameSrc = fetchIpfs {
    cid = "QmdPZubtKw9muhK6rnj49TiiNLsA8HrygUKbVvXzJaovwV";
    fallbackUrl = "https://archive.org/download/Command.And.Conquer.Renegade/Command%20And%20Conquer%20Renegade.7z";
    hash = "sha256-CuAR/nQw4MzL5vdVX0+5JedTGtHbq9lEojLIOqxhBjI=";
    name = "renegade.7z";
  };

  # Play disc ISO for campaign movies (BIK files)
  playIso = fetchIpfs {
    cid = "QmbLwmUmtfaZVZRxuyNBgpxBt4y9cGePys7EBEbu9rjDgV";
    fallbackUrl = "https://archive.org/download/renegade-install/RenegadePlay.iso";
    hash = "sha256-fUpsX+f0xlPgsu/rHbXyX/A/KZAvOdDBpQG9+GpO6hE=";
    name = "RenegadePlay.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "command-conquer-renegade";

  src = gameSrc;

  nativeBuildInputs = [ p7zip ];

  runtime = "proton";

  buildScript = ''
    mkdir -p "$out"

    # Extract portable game data
    7z x ${gameSrc} -o/tmp/ren -aoa
    cp -r "/tmp/ren/Command And Conquer Renegade/"* "$out/"
    rm -rf /tmp/ren

    # Extract campaign movies from play disc
    # Game hardcodes path DATA\MOVIES\ for BIK files
    mkdir -p "$out/Data/Movies"
    7z x ${playIso} -o/tmp/play -aoa '*.BIK'
    cp /tmp/play/*.BIK "$out/Data/Movies/"
    rm -rf /tmp/play

    # Lowercase DLL symlinks for case-sensitive filesystems
    cd "$out"
    for f in *.dll *.DLL; do
      [ -f "$f" ] || continue
      lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
      [ "$f" != "$lower" ] && [ ! -e "$lower" ] && ln -s "$f" "$lower"
    done
  '';

  copyGlobs = [
    "Data/config/"
    "server.ini"
  ];

  executable = "Game.exe";

  env = {
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    WINEDLLOVERRIDES = "binkw32=n,b";
  };
}
