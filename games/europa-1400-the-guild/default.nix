{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  pkgsi686Linux,
  runCommandLocal,
  wineWow64Packages,
  xvfb-run,
}:

let
  wine = wineWow64Packages.stable;

  gameISO = fetchIpfs {
    cid = "QmVGbehWtufnkvDbiUJa5wCo1CurPzsPJM74VLhqykZUWP";
    fallbackUrl = "https://archive.org/download/europa-1400-gold-edition/E1400_Gold_UK.iso";
    hash = "sha256-cZmqwy++R9ei19prp5qCZiJDeYPNHole/NugLOsE/Cs=";
    name = "europa1400gold.iso";
    };

  # Extract ISO and run the Wise installer with Wine to get game files
  gameData =
    runCommandLocal "europa-1400-the-guild-data"
      {
        nativeBuildInputs = [
          p7zip
          wine
          xvfb-run
        ];
      }
      ''
        # Extract ISO
        mkdir -p /tmp/iso
        7z x ${gameISO} -o/tmp/iso

        # Run the Wise installer silently with Wine
        export WINEPREFIX=/tmp/wineprefix
        export WINEDLLOVERRIDES="mscoree,mshtml="
        export WINEDEBUG=-all
        mkdir -p "$WINEPREFIX"

        xvfb-run -a wine /tmp/iso/setup.exe /S

        # Copy installed game files to output
        cp -r "$WINEPREFIX/drive_c/Program Files (x86)/JoWooD/Europa 1400 - Gold Edition" "$out"
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "europa-1400-the-guild";

  src = gameData;
  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";
  executable = "Europa1400Gold.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 1024 -h 768 --expose-wayland";

  env = {
    PROTON_NO_PROTONFIXES = "1";
    PROTON_USE_WINED3D = "1";
    PULSE_LATENCY_MSEC = "60";
    WINE_VD = "1024x768";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
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
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  meta = {
    description = "Europa 1400: The Guild - Gold Edition (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "europa-1400-the-guild";
  };
}
