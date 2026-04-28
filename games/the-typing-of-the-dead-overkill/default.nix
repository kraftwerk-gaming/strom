{
  self,
  lib,
  pkgs,
  fetchIpfs,
  pkgsi686Linux,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "the-typing-of-the-dead-overkill";

  src = fetchIpfs {
    cid = "QmZPyBkFumfgoTHLvVbJUjsJCNAhgaquvGtkFLYb6xN93A";
    # fallbackUrl = "";
    hash = "sha256-waL7G7lU2/aIaRYnju49/vuOM+/TeQu5MX8XgEPHl8M=";
    name = "The.Typing.of.the.Dead.Overkill.v1.3.Incl.DLC-GGn.7z";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -o/tmp/totdo "$src"
    mv "/tmp/totdo/Typing of the Dead Overkill"/* "$out"/
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "HOTD_NG.exe";

  env = {
    SteamAppId = "246580";
    SteamGameId = "246580";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  targetPkgs = p: [
    p.freetype
    p.glibc
    p.mesa
    p.vulkan-loader
    p.libGL
    p.libx11
    p.libxext
    p.libxcb
    p.libxcursor
    p.libxrandr
    p.libxi
    p.libxfixes
    p.libxrender
    p.libxcomposite
    p.libxinerama
    p.libxxf86vm
    p.alsa-lib
    p.libpulseaudio
    p.openal
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    # Game internally renders at 1280x720 regardless of settings
    nested-width = 1280;
    nested-height = 720;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "The Typing of the Dead: Overkill (Steam, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-typing-of-the-dead-overkill";
  };
}
