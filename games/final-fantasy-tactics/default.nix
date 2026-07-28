{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Single-disc PS1 redump packed as a MAME CHD (SwanStation loads .chd
  # directly, no cue/bin split). Source: archive.org psxgames item
  # psx_ffantact ("Final Fantasy Tactics (USA)", serial SCUS-94221,
  # region NTSC-U, rev 1.0 - the sole US pressing; item sha1
  # aa42cf82878c52d9cb1d0f11a0e4edbd878836aa verified against the
  # archive.org file manifest). Original Square release: 1997-06-20 JP,
  # 1998-01-28 US. This is the PS1 disc, NOT the PSP "War of the Lions"
  # port and NOT the 2025 "Ivalice Chronicles" remaster.
  disc = fetchIpfs {
    cid = "QmRvMro7gieEdnthrsVKeorUoUDhJrk97bmYGC6JMq2xY1";
    fallbackUrl = "https://archive.org/download/psx_ffantact/playstationdisc.chd";
    hash = "sha256-QO6jm0ZV3seoJ+5qzVADnPGJIZLSRP3+z0eaSAkoqSs=";
    name = "final-fantasy-tactics.chd";
  };

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
  name = "final-fantasy-tactics";
  src = disc;
  ipfsSources = [
    disc
    psxBios7z
  ];

  buildScript = ''
    mkdir -p $out
    ln -s ${disc} "$out/Final Fantasy Tactics (USA).chd"
  '';

  runtime = "retroarch";
  executable = "Final Fantasy Tactics (USA).chd";

  retroarch = {
    cores = [ pkgs.libretro.swanstation ];
    settings.system_directory = toString biosDir;
  };

  meta = {
    description = "Final Fantasy Tactics (PSX 1997 USA, via RetroArch / SwanStation)";
    mainProgram = "final-fantasy-tactics";
    platforms = [ "x86_64-linux" ];
  };
}
