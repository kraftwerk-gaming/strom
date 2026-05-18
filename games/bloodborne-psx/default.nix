{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Lilith "b0tster" Walther's fan demake of Bloodborne, free PSX-styled
  # standalone Unreal Engine 4 build v1.05 (2022-02-06). The zip wraps a
  # single BBPSX_Build_2022_02_06_1.05/WindowsNoEditor/ tree; we strip
  # the wrapper dirs and ship the WindowsNoEditor contents directly.
  src = fetchIpfs {
    cid = "QmTminqp4KC2yvPuKAit7CZuxdFXMV84FbFdJPamqLjS8X";
    fallbackUrl = "https://archive.org/download/bbpsx-1.05_202204/BBPSX_1.05.zip";
    hash = "sha256-vkg3R+2eKLopkhGuUSEbXa+vFcUrEQ/iYSpHN3ewPz8=";
    name = "BBPSX_1.05.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bloodborne-psx";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract"/*/WindowsNoEditor/. "$out"/
  '';

  runtime = "proton";
  # UE4 default save path lives under
  # %LOCALAPPDATA%\<ProjectName>\Saved (Saved/SaveGames + Saved/Config).
  saveLocations = [ "AppData/Local/BBPSX/Saved" ];
  executable = "BBPSX.exe";

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
    description = "Bloodborne PSX (Lilith Walther's PSX-styled fan demake v1.05, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bloodborne-psx";
  };
}
