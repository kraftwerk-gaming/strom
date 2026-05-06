{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  pkgsi686Linux,
}:

let
  # Original freeware Cave Story (Doukutsu Monogatari), Linux port v1.01.
  archive = fetchIpfs {
    cid = "QmeFchAHBeMMeUjQSDV5Jb9hUsZQvkBcMToHPnfJZWv55z";
    fallbackUrl = "https://archive.org/download/CavestorydoukutsuForLinuxV1.01/linuxdoukutsu-1.01.tar.bz2";
    hash = "sha256-dkZvwbGQHOJeMBpOyEUKztgGydSZ1mcH1vezjv68JME=";
    name = "linuxdoukutsu-1.01.tar.bz2";
  };

  # The bundled doukutsu.bin is a 32-bit i386 ELF from 2005 with an
  # absolute interpreter path (/lib/ld-linux.so.2). Build under
  # pkgsi686Linux so autoPatchelf picks the i686 ld-linux as its
  # interpreter target; that lets it patch a 32-bit ELF on a 64-bit host.
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "cave-story-data";
    version = "1.01";

    src = archive;

    nativeBuildInputs = [
      autoPatchelfHook
      pkgsi686Linux.stdenv.cc.cc.lib
    ];

    buildInputs = [ pkgsi686Linux.SDL ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"/
      chmod +x "$out/doukutsu.bin"
      # The bundled libSDL-1.2 from 2005 dlopens libX11 without an RPATH;
      # delete it so autoPatchelf links to pkgsi686Linux.SDL (which has the
      # right deps wired up for X11/audio).
      rm -f "$out/libSDL-1.2.so.0"
      runHook postInstall
    '';
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cave-story--1";

  ipfsSources = [ archive ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "doukutsu.bin";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    LD_LIBRARY_PATH = "$GAMEDIR";
  };

  meta = {
    description = "Cave Story / Doukutsu Monogatari (1.01 Linux freeware)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cave-story--1";
  };
}
