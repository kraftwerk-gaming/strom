{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unar,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "detention";

  # Detention (Red Candle Games 2017). The archive.org item ships a
  # Windows .iso wrapper; inside is a single setup_Detention.exe which
  # is a RAR self-extracting archive (despite the "setup_*" name -- not
  # Inno). unar handles the RAR SFX directly. Result: Detention/
  # subtree at the archive root with Detention.exe + Unity Mono runtime
  # + Detention_Data/.
  src = fetchIpfs {
    cid = "QmTJWi1w8iBVv9jpecNCTeFJ5Lou7W4JM4ubJve5XnxVKY";
    fallbackUrl = "https://archive.org/download/detention-x32-x64/Detention.iso";
    hash = "sha256-TP0KZXbY07AkOgdxmZX4I9hSCudLk1/bk/f28H4sV50=";
    name = "Detention.iso";
  };

  nativeBuildInputs = [
    p7zip
    unar
  ];

  buildScript = ''
    mkdir -p "$out"
    # Pull just the setup_Detention.exe out of the iso (the rest is
    # cover/trailer fluff).
    7z x "$src" setup_Detention.exe -o"$TMPDIR/iso" > /dev/null
    unar -o "$TMPDIR/extract" "$TMPDIR/iso/setup_Detention.exe"
    cp -r "$TMPDIR/extract/Detention"/. "$out"/
  '';

  runtime = "proton";
  executable = "Detention.exe";

  # Unity Mono game; saves under AppData/LocalLow per Unity convention.
  saveLocations = [ "AppData/LocalLow/Red Candle Games/Detention" ];

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
    description = "Detention (Red Candle Games 2017, Taiwanese-school horror, Unity / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "detention";
  };
}
