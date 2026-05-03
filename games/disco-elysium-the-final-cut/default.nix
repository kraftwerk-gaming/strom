{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "disco-elysium-the-final-cut";

  src = fetchIpfs {
    cid = "QmS6uizMSR652viMi4N9qmQdKBD548Q7FdJkAPdm3iE1LL";
    fallbackUrl = "";
    hash = "sha256-sCFnWOEfvhFUnuK3TVFR6SO70OSrZ8EKa01C/VV0IKg=";
    name = "disco-elysium-the-final-cut.zip";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y $src -o"$out"

    game_dir="$out/Disco Elysium"
    if [ -d "$game_dir" ]; then
      mv "$game_dir"/* "$out"/
      rmdir "$game_dir"
    fi
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "disco.exe";

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
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    DXVK_ASYNC = "1";
    PULSE_LATENCY_MSEC = "60";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  preRun = "";

  meta = {
    description = "Disco Elysium: The Final Cut (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "disco-elysium-the-final-cut";
  };
}
