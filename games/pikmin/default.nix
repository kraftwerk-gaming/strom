{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Pikmin (USA). Verified redump GameCube dump, stored as a CISO
  # (compact ISO, 669024832 bytes / 638 MiB) which Dolphin loads
  # natively. The standard NTSC-U release (GPIE01).
  iso = fetchIpfs {
    cid = "Qmd1bP4XPoia96JkSFwpZ6UxoCMETLm1gLor4NcNocQAiC";
    fallbackUrl = "https://archive.org/download/pikmin-usa/Pikmin%20%28USA%29%20.ciso";
    hash = "sha256-sbrhkzaVEUPLdHd9FB3zvHbenYUQSpm81FvLIapawsM=";
    name = "pikmin.ciso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pikmin";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/pikmin.ciso"
  '';

  runtime = "dolphin";
  executable = "pikmin.ciso";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Pikmin (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pikmin";
  };
}
