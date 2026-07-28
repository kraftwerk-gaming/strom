{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Shin Megami Tensei: Persona 4, NTSC-U (USA) PS2 retail disc,
  # serial SLUS-21782, Atlus 2008. This is the original PlayStation 2
  # release, NOT Persona 4 Golden (the Vita/PC enhanced port, packaged
  # separately as `persona-4-golden`).
  #
  # Redump-verified dump (redump.org disc 5576): the ISO inside the zip
  # is 4405952512 bytes, md5 7419b3f9c1d68585960c8c32aab5c758,
  # sha1 179381f67a412dc56e9b7ae40dbc1c00a0beea59, all three matching
  # Redump's entry exactly. Serial read back from the disc's SYSTEM.CNF
  # (BOOT2 = cdrom0:\SLUS_217.82).
  #
  # The archive item ships the ISO zipped together with three artwork
  # PNGs (boxart/snap/title); the build extracts only the ISO so the
  # store path holds just the 4.4 GB disc image.
  gameSrc = fetchIpfs {
    cid = "QmbQwSoKHQ8QxLpXoDoqWtVjYuZCuCAH5anBM5oB7KRCn5";
    fallbackUrl = "https://archive.org/download/2008-atlus-shin-megami-tensei-persona-4-usa/Shin%20Megami%20Tensei%20-%20Persona%204%20%28USA%29.zip";
    hash = "sha256-qaHUJHY3rcneMLSPfOF/vgNU8UEOpPtoRvvqRdS7jOU=";
    name = "persona-4-usa.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shin-megami-tensei-persona-4";
  src = gameSrc;

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" "*.iso" -d "$out"
  '';

  runtime = "pcsx2";
  executable = "Shin Megami Tensei - Persona 4 (USA).iso";

  meta = {
    description = "Shin Megami Tensei: Persona 4 (PS2 NTSC-U, via PCSX2)";
    mainProgram = "shin-megami-tensei-persona-4";
    platforms = [ "x86_64-linux" ];
  };
}
