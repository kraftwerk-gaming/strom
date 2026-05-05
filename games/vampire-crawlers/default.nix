{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmZ9gcmgjvXPF29qzvj3GanDyACRMK5oA24RF48tu7oGkL";
    fallbackUrl = "https://ipfs.io/ipfs/QmZ9gcmgjvXPF29qzvj3GanDyACRMK5oA24RF48tu7oGkL";
    hash = "sha256-Eho6LUpcU+Nh9j0BZ+JAhE+xbwZti00xtg5ZEFvLJes=";
    name = "vampire-crawlers.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vampire-crawlers";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x $src -o"$out" -aoa

    # Flatten if there's a single top-level directory
    if [ -d "$out/Vampire Crawlers" ]; then
      mv "$out/Vampire Crawlers"/* "$out"/
      rmdir "$out/Vampire Crawlers"
    fi
  '';

  runtime = "proton";
  executable = "Vampire Crawlers.exe";

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    PULSE_LATENCY_MSEC = "60";
    DXVK_ASYNC = "1";
  };

  preRun = "";

  meta = {
    description = "Vampire Crawlers (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vampire-crawlers";
  };
}
