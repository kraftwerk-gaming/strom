{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Risk of Rain (2013, Hopoo Games) v1.2.2 Windows build. The original
  # GameMaker Studio executable plus its bundled DirectX/GameMaker DLLs.
  # No Linux native build was ever shipped on archive.org, so this runs
  # via Proton. The bundled steam_api.dll is a stub: the steamclient-stub
  # provided by lib/proton.nix satisfies its few imports.
  src = fetchIpfs {
    cid = "QmUiGfcZ9zbgubBA8RZCwGvMhz4drAKztWZr3eKZ9s4C3m";
    fallbackUrl = "https://archive.org/download/RiskOfRain1.2.2.7z/Risk%20of%20Rain%201.2.2.7z";
    hash = "sha256-RYgpHHML5samslHIl6etmYAAiLfGKj1k98hMmbU07xs=";
    name = "risk-of-rain-1.2.2.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "risk-of-rain";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Risk of Rain"/. "$out"/
  '';

  runtime = "proton";
  executable = "Risk of Rain.exe";

  saveLocations = [ "AppData/Local/ROR_GMS_controller" ];

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
    description = "Risk of Rain (2013 Hopoo Games, original v1.2.2 Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "risk-of-rain";
  };
}
