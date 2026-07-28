{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Pokemon XD: Gale of Darkness (USA), GameCube game ID GXXE01, revision 0,
  # NTSC-U / internal name "POKeMON XD". Shipped as an RVZ (Dolphin's own
  # lossless container, Zstandard level 5, 128 KiB blocks, 971675340 bytes)
  # which Dolphin loads natively - no recompression, no conversion step.
  #
  # Provenance: `dolphin-tool verify` on this RVZ reproduces the full 1.46 GB
  # disc image with CRC32 c0f69d18 / SHA1
  # c1b5218f832403d15aa500ac4d6aacc8865c792d and reports "Problems Found: No".
  # That CRC32 is redump.org disc #1845 (Pokémon XD: Gale of Darkness, GC,
  # USA), i.e. this is a Redump-verified dump, just repacked as RVZ.
  iso = fetchIpfs {
    cid = "QmW6HrYrJ9FgVNpnQW3t8dy7RJ5AQsMq2gQZXvf6P8Ss1A";
    fallbackUrl = "https://archive.org/download/CentralArquivista-NintendoGameCube-US/Pokemon%20XD%20-%20Gale%20of%20Darkness%20%28US%29.rvz";
    hash = "sha256-J8nTaqQTImuN8fyb+30T2MP6E68ficzmlyeKj/mSN+I=";
    name = "pokemon-xd-gale-of-darkness.rvz";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-xd-gale-of-darkness";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/pokemon-xd-gale-of-darkness.rvz"
  '';

  runtime = "dolphin";
  executable = "pokemon-xd-gale-of-darkness.rvz";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Pokemon XD: Gale of Darkness (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pokemon-xd-gale-of-darkness";
  };
}
