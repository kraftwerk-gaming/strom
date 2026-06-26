{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  # Redump NTSC-U dump (single track, MODE2/2352), shipped on archive.org as a
  # zip holding the .bin + .cue. The disc is pinned on IPFS; the archive.org
  # fallbackUrl is the non-IPFS fallback if the gateways are down.
  discZip = fetchIpfs {
    cid = "Qmade5Sep26jg7GiozNWgwVpY2aRnn5zpYgdwLM29C6Fe6";
    fallbackUrl = "https://archive.org/download/gran-turismo-usa-v-1.0/Gran%20Turismo%20%28USA%29%20%28v1.0%29.zip";
    hash = "sha256-KC6Uur+uBJ2xNUsGjwDD1+dJVz7zEgerBSax1BSE8h0=";
    name = "gran-turismo-usa-v10.zip";
  };

  # Same redump cue as the .bin's, regenerated to keep .cue handling simple.
  disc1Cue = writeText "gran-turismo.cue" ''
    FILE "Gran Turismo (USA).bin" BINARY
      TRACK 01 MODE2/2352
        INDEX 01 00:00:00
  '';

  psxBios7z = fetchIpfs {
    cid = "bafkreibalsxl4jo23j4lgxoubseqbquwudj5nieni3jsoxszkc3aza6g7u";
    fallbackUrl = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  # SwanStation expects scph5501.bin; the upstream blob is named
  # scph1001.bin so rename after extract.
  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ pkgs.p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gran-turismo";
  src = discZip;
  nativeBuildInputs = [ pkgs.unzip ];
  ipfsSources = [
    discZip
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    unzip -j -o $src -d "$TMPDIR/gt"
    cp "$TMPDIR/gt/Gran Turismo (USA) (v1.0).bin" "$out/Gran Turismo (USA).bin"
    cp ${disc1Cue} "$out/Gran Turismo (USA).cue"
  '';

  runtime = "retroarch";
  executable = "Gran Turismo (USA).cue";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Gran Turismo (PSX 1997 USA, via RetroArch / SwanStation)";
    mainProgram = "gran-turismo";
    platforms = [ "x86_64-linux" ];
  };
}
