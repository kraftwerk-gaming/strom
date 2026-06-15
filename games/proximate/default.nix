{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # PROXIMATE (cain / Cain Maddox, 2024): a deep-sea-lab narrative horror
  # where you read the world through an image-recognition visor. Unity
  # 2022.2.17f1 Mono build for Windows x86-64; the repack ships the stock
  # Unity layout (PROXIMATE.exe + UnityPlayer.dll + MonoBleedingEdge/ +
  # PROXIMATE_Data/) nested under a wrapper dir. No installer.
  #
  # The build carries no Steamworks integration at all (no steam_api64.dll,
  # no Steamworks.NET, Assembly-CSharp has zero Steam references), so it
  # launches fine offline and needs no Goldberg/gbe_fork swap.
  src = fetchIpfs {
    cid = "QmbfvvcMU8J4YnCwtxYLDkvRe7H3nRowEu2zH9QpbXM1QX";
    fallbackUrl = "https://pixeldrain.com/api/file/WT7ZsCcw";
    hash = "sha256-Tj1r3++3Bq66zbbEs7QG1JjcLDX6rhLTHz+IZxg2OPY=";
    name = "PROXIMATE.Build.16328367.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "proximate";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Locate the dir that actually holds PROXIMATE.exe rather than guessing
  # the archive's wrapper-folder nesting with a glob.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/x"
    d=$(dirname "$(find "$TMPDIR/x" -name PROXIMATE.exe -print -quit)")
    cp -r "$d"/. "$out"/
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  executable = "PROXIMATE.exe";

  # Unity persistentDataPath AppData/LocalLow/<company>/<product>; company
  # and product are taken verbatim from PROXIMATE_Data/app.info
  # ("DefaultCompany", "PROXIMATE").
  saveLocations = [ "AppData/LocalLow/DefaultCompany/PROXIMATE" ];

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
    description = "PROXIMATE (Cain Maddox 2024, deep-sea visor horror, Unity Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "proximate";
  };
}
