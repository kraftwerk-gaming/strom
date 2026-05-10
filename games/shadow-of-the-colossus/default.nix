{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  gameSrc = fetchIpfs {
    cid = "QmfNb23JQhMmGoKzyU3b7otgJMt1tVUa2a3zsPwmX9wmoD";
    fallbackUrl = "https://archive.org/download/sotcps2usa/Shadow%20of%20the%20Colossus%20%28USA%29.zip";
    hash = "sha256-/GaNfOdOGOy0K9KekR93UVM9wYr0SyA2Loi9cOpRoiY=";
    name = "sotc-usa.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shadow-of-the-colossus";
  src = gameSrc;

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip "$src" -d $out
  '';

  runtime = "pcsx2";
  executable = "Shadow of the Colossus (USA).iso";

  meta = {
    description = "Shadow of the Colossus (via PCSX2)";
    mainProgram = "shadow-of-the-colossus";
    platforms = [ "x86_64-linux" ];
  };
}
