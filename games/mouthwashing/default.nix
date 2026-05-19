{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "mouthwashing";

  # Mouthwashing (Wrong Organ 2024). Windows Unity Mono build; the rar
  # extracts to a "Mouthwashing (2024)/" wrapper dir at the archive
  # root containing Mouthwashing.exe + UnityPlayer.dll + the standard
  # MonoBleedingEdge runtime + Mouthwashing_Data/. We strip the
  # wrapper so the game files land at $out root.
  src = fetchIpfs {
    cid = "QmVJ8PQ5sm42bBVCEDqR2bxEaH1NdH877r7hc7hCuHdQTN";
    fallbackUrl = "https://archive.org/download/mouthwashing-2024_202508/Mouthwashing%20%282024%29.rar";
    hash = "sha256-zKb7WIyAxMT5DT3pBHHwpcTtRYJRGYLMfr7DnapL2Us=";
    name = "Mouthwashing.rar";
  };

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/x" "$src"
    cp -r "$TMPDIR/x/Mouthwashing (2024)"/. "$out"/
  '';

  runtime = "proton";
  executable = "Mouthwashing.exe";

  saveLocations = [ "AppData/LocalLow/Wrong Organ/Mouthwashing" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Mouthwashing (Wrong Organ 2024, Unity Mono horror via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mouthwashing";
  };
}
