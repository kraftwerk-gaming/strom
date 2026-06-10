{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Pikuniku v1.0.5-GOG1 (Sectordub / Devolver
  # Digital, 2019). InnoSetup installer; innoextract unpacks the game
  # tree (Pikuniku.exe + Pikuniku_Data/ + UnityPlayer.dll) to the
  # destination directory. Standard Unity 2018 Windows layout; the
  # GOG Galaxy SDK dlls (Galaxy64.dll, GalaxyCSharpGlue.dll) are
  # present but do nothing without an active Galaxy session.
  src = fetchIpfs {
    cid = "Qmb1oRLhCtE8oxPsDLVjykHbrZcMfPJwMDaehKHMfBrsWy";
    fallbackUrl = "";
    hash = "sha256-2MWsR3T/66G+uZuJTZX/JybRP93Y8+bsxhkWOv468V8=";
    name = "setup_pikuniku_1.0.5-gog1.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pikuniku";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$out" "$src"
    # innoextract --gog places icon/webcache in app/; game binaries
    # land at the root alongside Pikuniku_Data/.
    rm -rf "$out/__redist" "$out/app" "$out/tmp"
  '';

  runtime = "proton";
  executable = "Pikuniku.exe";

  saveLocations = [ "AppData/LocalLow/Sectordub/Pikuniku" ];

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
    description = "Pikuniku (Unity, GOG v1.0.5-GOG1, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pikuniku";
  };
}
