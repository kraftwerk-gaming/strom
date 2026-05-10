{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "need-for-speed-most-wanted";

  src = fetchIpfs {
    cid = "QmbeRJkSiVupPcbNp6vGpMpNBUwYEUuS3fPiqgpP1Eadfs";
    fallbackUrl = "https://archive.org/download/need-for-speed-most-wanted-black-edition_202507/Need%20For%20Speed%20Most%20Wanted%20Black%20Edition.zip";
    hash = "sha256-0flSvhwpQ5rK/qPhcG/snZWpRs5ahm60Azm/+5qu364=";
    name = "nfsmw-black-edition.zip";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y $src -o"$out"

    game_dir="$out/Need For Speed Most Wanted Black Edition"
    if [ -d "$game_dir" ]; then
      mv "$game_dir"/* "$out"/
      rmdir "$game_dir"
    fi
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "speed.exe";
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    STEAM_COMPAT_CONFIG = "sdlinput";
    PULSE_LATENCY_MSEC = "60";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  preRun = "";

  meta = {
    description = "Need for Speed: Most Wanted (2005) (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "need-for-speed-most-wanted";
  };
}
