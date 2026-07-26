{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  # Parasite Eve, original PlayStation release (Squaresoft 1998, USA), run
  # via RetroArch + SwanStation. Two-disc game; the .m3u drives
  # SwanStation's automatic disc-swapping between the two discs.
  base = "https://archive.org/download/playstation1_202404";

  disc1 = fetchIpfs {
    cid = "Qmc9ZmGJpUqQNu3ouWmHa5gAHHBzBQX2DgHujDuf6oGbt7";
    fallbackUrl = "${base}/Parasite%20Eve%20%28USA%29%20%28Disc%201%29.chd";
    hash = "sha256-ipWA8XqHB7t5CDWN1klLqL6e/rBK+Wu9yI12kszU7c0=";
    name = "parasite-eve-disc1.chd";
  };

  disc2 = fetchIpfs {
    cid = "QmcUohdTYKiRFZbDYZs6CX7Cbaq3Cf7cehacG7oeva1GPs";
    fallbackUrl = "${base}/Parasite%20Eve%20%28USA%29%20%28Disc%202%29.chd";
    hash = "sha256-N7y7ua7svwpo02zCoIlj8Byw38a7xcyWdbXM1ZPu3Es=";
    name = "parasite-eve-disc2.chd";
  };

  # SwanStation loads the .m3u and swaps discs from the entries below
  # (resolved relative to the playlist, i.e. alongside it in $out).
  m3u = writeText "parasite-eve.m3u" ''
    Parasite Eve (USA) (Disc 1).chd
    Parasite Eve (USA) (Disc 2).chd
  '';

  psxBios7z = fetchIpfs {
    cid = "bafkreibalsxl4jo23j4lgxoubseqbquwudj5nieni3jsoxszkc3aza6g7u";
    fallbackUrl = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  # SwanStation expects scph5501.bin; the upstream blob is named
  # scph1001.bin (both are the US v4.1 BIOS) so rename after extract.
  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ pkgs.p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "parasite-eve";
  src = disc1;
  ipfsSources = [
    disc1
    disc2
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc1} "$out/Parasite Eve (USA) (Disc 1).chd"
    ln -s ${disc2} "$out/Parasite Eve (USA) (Disc 2).chd"
    cp ${m3u} "$out/Parasite Eve (USA).m3u"
  '';

  runtime = "retroarch";
  executable = "Parasite Eve (USA).m3u";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Parasite Eve (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "parasite-eve";
    platforms = [ "x86_64-linux" ];
  };
}
