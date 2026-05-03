{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG installer split into two parts (InnoSetup 5.6.2).
  setupExe = fetchIpfs {
    cid = "QmP7T7DrPTfmUqv7VzgKRqe38JaQNCsnv7gNiZmNqGaDMb";
    hash = "sha256-jTsLXA0efu1nTt6yWrUqhytLsnOXI7MNQBROoVveF0c=";
    name = "setup_paquerette_down_the_bunburrows_1.1.2_(88290).exe";
  };
  setupBin = fetchIpfs {
    cid = "QmTjftj3F8JLxRFS59scJY8SRbvuWvAVQMvgsQ2jjQLxVy";
    hash = "sha256-kK3spbS9EQI5IApwNjUeAc5tVUNM8EGBf6n9Wffl+DM=";
    name = "setup_paquerette_down_the_bunburrows_1.1.2_(88290)-1.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "paquerette-down-the-bunburrows";

  ipfsSources = [
    setupExe
    setupBin
  ];
  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    # innoextract needs both files in the same directory
    mkdir -p /tmp/gog-install
    ln -s ${setupExe} "/tmp/gog-install/setup_paquerette_down_the_bunburrows_1.1.2_(88290).exe"
    ln -s ${setupBin} "/tmp/gog-install/setup_paquerette_down_the_bunburrows_1.1.2_(88290)-1.bin"

    mkdir -p "$out"
    innoextract --exclude-temp -d "$out" \
      "/tmp/gog-install/setup_paquerette_down_the_bunburrows_1.1.2_(88290).exe"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
    rm -rf "$out/__redist" "$out/commonappdata"
    rm -f "$out"/goggame-*
  '';

  runtime = "proton";
  executable = "Paquerette Down the Bunburrows.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Paquerette Down the Bunburrows v1.1.2 (GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "paquerette-down-the-bunburrows";
  };
}
