{
  self,
  lib,
  pkgs,
  pkgsi686Linux,
  p7zip,
}:

let
  src = pkgs.fetchurl {
    url = "https://archive.org/download/typing-of-the-dead-pc-game/%5BPC%5D%20The%20Typing%20of%20the%20Dead%20%28US%29.7z";
    hash = "sha256-JWoqkn0zBjkIywZuBBe5KQrF1goWfvFAqRFdtTYF5Jo=";
    name = "the-typing-of-the-dead.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-typing-of-the-dead";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -o/tmp/totd "$src"
    mv "/tmp/totd/The Typing of The Dead"/* "$out"/
    # hglCore.ini: CDCheckPass bypasses the disc verification dialog,
    # AllDevicePass accepts any D3D device (the game rejects modern adapters).
    cat > "$out/hglCore.ini" <<'EOINI'
[HGLCORE]
CDCheckPass=1
AllDevicePass=1
EOINI
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "Tod_e.exe";

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Old DirectDraw game -- use wined3d (OpenGL) instead of DXVK (Vulkan)
    PROTON_USE_WINED3D = "1";
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
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  preRun = ''
    # Pin to Windows XP for this era of game
    USERREG="$COMPATDATA/pfx/user.reg"
    if [ -f "$USERREG" ] && ! grep -q 'AppDefaults\\\\Tod_e.exe' "$USERREG"; then
      cat >> "$USERREG" <<'EOF'

[Software\\Wine\\AppDefaults\\Tod_e.exe]
"Version"="winxp"
EOF
    fi
  '';

  meta = {
    description = "The Typing of the Dead (2001 PC port, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-typing-of-the-dead";
  };
}
