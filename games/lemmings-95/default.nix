{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  wine = pkgs.wine;
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lemmings-95";

  src = fetchIpfs {
    cid = "QmUumu4xqgz8xSkqKMtxSXDqGc3fKhztSJWGXeyZJR93hq";
    fallbackUrl = "https://archive.org/download/WINLEM/WINLEMM.zip";
    hash = "sha256-5HkazEJWOyAxvruxQMWHkOMH6Q99bTj1P26xdipjNhk=";
    name = "lemmings-95.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -o $src -d /tmp/lem
    mv /tmp/lem/WINLEMM/WINLEMM/* "$out"/

    # Remove manuals/acrobat installers
    rm -rf "$out/MANUALS"
  '';

  runtime = "native";

  executable = "${pkgs.writeShellScript "wine-lemmings" ''
    export WINEPREFIX="$STROM_CACHEDIR/wineprefix"
    mkdir -p "$WINEPREFIX"
    ${wine}/bin/wineboot -i 2>/dev/null || true
    ${wine}/bin/wine "$GAMEDIR/LEMMINGS.EXE"
    ${wine}/bin/wineserver -k 2>/dev/null || true
  ''}";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Lemmings 95 (Windows 95 version via Wine)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lemmings-95";
  };
}
