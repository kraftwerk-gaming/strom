{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Official free Windows build from itch.io (lemaitre-bros.itch.io/babbdi),
  # BABBDI_WINDOWS_1.2.3.zip (646,575,077 bytes, itch upload 7142421). The
  # itch page is Cloudflare-gated, so the zip was pulled through the
  # pay-what-you-want $0 download flow; the signed R2 CDN URL is
  # time-limited, so fallbackUrl points at the canonical itch page. The
  # source is pinned to IPFS (cid above).
  src = fetchIpfs {
    cid = "QmcGUudkqnj5KUyMNwUchifDV8PvhLfK5jqeAcw1VvaoJj";
    fallbackUrl = "https://lemaitre-bros.itch.io/babbdi";
    hash = "sha256-Bqm8IaFBhCvVYuJL3iarst8NI1+k2EfX0yJfym5hkos=";
    name = "BABBDI_WINDOWS_1.2.3.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "babbdi";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Flat archive: Babbdi.exe + Babbdi_Data/ + UnityPlayer.dll +
  # MonoBleedingEdge/ + UnityCrashHandler64.exe sit at the zip root (no
  # wrapper folder), so extract straight into $out.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
  '';

  runtime = "proton";

  executable = "Babbdi.exe";

  # Unity persistentDataPath AppData/LocalLow/<company>/<product>; the
  # company string is taken verbatim from Babbdi_Data/app.info line 1
  # ("LemaitreBros", no space), product from line 2 ("Babbdi").
  saveLocations = [ "AppData/LocalLow/LemaitreBros/Babbdi" ];

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
    description = "Babbdi (Lemaitre Bros 2022, free first-person exploration, Unity Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "babbdi";
  };
}
