{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  mkPcsx2Game = self.lib.mkPcsx2Game { inherit lib pkgs; };

  gameSrc = fetchIpfs {
    cid = "QmfNb23JQhMmGoKzyU3b7otgJMt1tVUa2a3zsPwmX9wmoD";
    fallbackUrl = "https://archive.org/download/sotcps2usa/Shadow%20of%20the%20Colossus%20%28USA%29.zip";
    hash = "sha256-/GaNfOdOGOy0K9KekR93UVM9wYr0SyA2Loi9cOpRoiY=";
    name = "sotc-usa.zip";
  };

  gameIso = pkgs.runCommandLocal "sotc-iso" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    mkdir -p $out
    unzip ${gameSrc} -d $out
  '';
in
mkPcsx2Game {
  name = "shadow-of-the-colossus";
  src = gameSrc;
  gamePath = "${gameIso}/Shadow of the Colossus (USA).iso";
  description = "Shadow of the Colossus (via PCSX2)";
}
