{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "outer-wilds-alpha";

  # 32-bit Unity 4 game; wine's i386-unix winex11.so needs to find
  # 32-bit libXext.so.6 etc., which live under /usr/lib32 in the FHS.
  env = {
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  src = fetchIpfs {
    cid = "QmbPABWqByuFiwvfxwoMsWLexnqd9PjxdqAfj4azWKwHG1";
    fallbackUrl = "https://archive.org/download/outer-wilds-alpha-1-2-pc/OuterWilds_Alpha_1_2_PC.zip";
    hash = "sha256-ZnBQZCq8cF8zHF9MFue/NspDm7Gx0MkQwPfu1nt9QcM=";
    name = "outer-wilds-alpha.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
  '';

  runtime = "proton";
  executable = "OuterWilds_Alpha_1_2.exe";
  # Skip the Unity 4 configuration dialog (ScreenSelector) and force fullscreen.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];
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

  meta = {
    description = "Outer Wilds Alpha 1.2 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "outer-wilds-alpha";
  };
}
