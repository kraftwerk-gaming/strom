{
  lib,
  pkgs,
  fetchIpfs,
  self,
  writeText,
}:

let
  disc1 = fetchIpfs {
    cid = "QmdZc6eT9LPvCeuG6Fi647L829LmAC2hSTzJY7kUjQ8VYZ";
    fallbackUrl = "https://archive.org/download/metal-gear-solid-usa-disc-1/Metal%20Gear%20Solid%20%28USA%29%20%28Disc%201%29.bin";
    hash = "sha256-r1nZskdInUu0vk2jC1zdHSNtDSBSt43TzRS4ZWV44UE=";
    name = "Metal Gear Solid (USA) (Disc 1).bin";
  };

  disc2 = fetchIpfs {
    cid = "QmUvdpnfso8VrNHCy4GKtruhMQC73fzCzm9Lsjr5xatSKc";
    fallbackUrl = "https://archive.org/download/metal-gear-solid-usa-disc-2/Metal%20Gear%20Solid%20%28USA%29%20%28Disc%202%29.bin";
    hash = "sha256-0hPqi+A3nII9F2yj0j1ZuaPh3v5N3yxV15pnU8qqupQ=";
    name = "Metal Gear Solid (USA) (Disc 2).bin";
  };

  # Same redump cue as the .bin's, regenerated to keep .cue out of fetchIpfs.
  disc1Cue = writeText "mgs-disc1.cue" ''
    FILE "Metal Gear Solid (USA) (Disc 1).bin" BINARY
      TRACK 01 MODE2/2352
        INDEX 01 00:00:00
  '';
  disc2Cue = writeText "mgs-disc2.cue" ''
    FILE "Metal Gear Solid (USA) (Disc 2).bin" BINARY
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
  name = "metal-gear-solid";
  src = disc1;
  ipfsSources = [
    disc1
    disc2
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc1} "$out/Metal Gear Solid (USA) (Disc 1).bin"
    ln -s ${disc2} "$out/Metal Gear Solid (USA) (Disc 2).bin"
    cp ${disc1Cue} "$out/Metal Gear Solid (USA) (Disc 1).cue"
    cp ${disc2Cue} "$out/Metal Gear Solid (USA) (Disc 2).cue"
  '';

  runtime = "retroarch";
  executable = "Metal Gear Solid (USA) (Disc 1).cue";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Metal Gear Solid (PSX 1998 USA, via RetroArch / SwanStation)";
    mainProgram = "metal-gear-solid";
    platforms = [ "x86_64-linux" ];
  };
}
