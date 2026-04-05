{
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  self,
}:

let
  disc1 = fetchIpfs {
    cid = "QmRnafsnEmZgj6i2sJ7aJbns4y8bVSzrzgqdcJwXJFjsBj";
    fallbackUrl = "https://archive.org/download/xenogears-USA.-7z/Xenogears%20%28Disc%201%29.7z";
    hash = "sha256-36cmJhQcuXcGg7A/yvPaxuFEQEYi/BlbgpNqFxqfyik=";
    name = "xenogears-disc1.7z";
  };

  disc2 = fetchIpfs {
    cid = "QmSysVXQPdcJHsJnDTYxRiq7vF3PcGgFqobziHzp3EZaE8";
    fallbackUrl = "https://archive.org/download/xenogears-USA.-7z/Xenogears%20%28Disc%202%29.7z";
    hash = "sha256-kF513kDCTNAwVxpQwKFqwkSiU612qdfdB2oLfJMmOu4=";
    name = "xenogears-disc2.7z";
  };

  psxBios7z = fetchIpfs {
    cid = "bafkreibalsxl4jo23j4lgxoubseqbquwudj5nieni3jsoxszkc3aza6g7u";
    fallbackUrl = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  gameDiscs = pkgs.runCommandLocal "xenogears-discs" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p $out
    7z x ${disc1} -o$out -aoa
    7z x ${disc2} -o$out -aoa
    rm -f $out/readme.html
  '';

  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.swanstation ];
  settings.system_directory = toString biosDir;
  preHook = ''
    mkdir -p ~/.strom/xenogears/saves ~/.strom/xenogears/states
  '';
  settings.savefile_directory = "~/.strom/xenogears/saves";
  settings.savestate_directory = "~/.strom/xenogears/states";
  args = [ "${gameDiscs}/Xenogears (Disc 1).cue" ];
}).wrapper.overrideAttrs
  (_: {
    meta = {
      description = "Xenogears (via RetroArch / SwanStation)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [
        disc1
        disc2
        psxBios7z
      ];
    };
  })
