{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

let
  src = fetchIpfs {
    cid = "QmSLdTZSiCJcguj7FaKcFC2PMQiSahAe4UvoDDWwM89gAv";
    fallbackUrl = "https://archive.org/download/populous-the-beginning-pc-game-rts-wine/setup_populous_the_beginning_2.0.0.5.exe";
    hash = "sha256-xdOtKhs2nmNt+FpgYbgywY8twzUmoDOD9hq9e1UYxS0=";
    name = "setup_populous_the_beginning_2.0.0.5.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "populous-the-beginning";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog --exclude-temp -d "$TMPDIR/iss" "$src"
    # GOG Inno installers usually drop the playable game under app/; some
    # put it at the extract root. Copy whichever holds the game files.
    if [ -d "$TMPDIR/iss/app" ]; then
      cp -r "$TMPDIR/iss/app"/. "$out"/
    else
      cp -r "$TMPDIR/iss"/. "$out"/
    fi
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata"
  '';

  runtime = "proton";

  # popTB.exe is the software renderer; it runs cleanly on Wine/Proton.
  # The D3D launcher (D3DPopTB.exe) is the documented crash path on Wine,
  # so we target the software renderer directly.
  executable = "popTB.exe";

  # The engine writes saves into the SAVE/ folder next to its binary, so
  # they persist via the per-game fuse-overlayfs upper.
  saveLocations = [ ];

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

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
    pkgs.systemd
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
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Populous: The Beginning (1998 Bullfrog, GOG v2.0.0.5 + Undiscovered Worlds, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "populous-the-beginning";
  };
}
