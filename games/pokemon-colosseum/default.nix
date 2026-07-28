{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Pokemon Colosseum (USA). Full GameCube disc image, 1459978240 bytes
  # (1.36 GiB), disc ID GC6E01, disc 0 / revision 0 (the only NTSC-U
  # revision). Hashes match the verified Redump dump of the USA release
  # (crc32 0704554f, md5 e3f389dc5662b9f941769e370195ec90,
  # sha1 96b2b686d202a13dd15261fb7cffbcb2f08c0a77) and are byte-identical
  # across two independent archive.org uploads. Packaged as the plain .iso
  # the dump ships as - no recompression to CISO/RVZ.
  iso = fetchIpfs {
    cid = "QmeQ8NRoudiJQaReZBj7Py1StCVVE9hokQKTkzsPrxjtTz";
    fallbackUrl = "https://archive.org/download/pokemon-colosseum-usa/Pokemon%20Colosseum%20%28USA%29.iso";
    hash = "sha256-eMQHRCn6WYuXv6wpa/jg9+k/XLbYZ5+NJlPKkCgg9sU=";
    name = "pokemon-colosseum.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-colosseum";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/pokemon-colosseum.iso"
  '';

  runtime = "dolphin";
  executable = "pokemon-colosseum.iso";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Pokemon Colosseum (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pokemon-colosseum";
  };
}
