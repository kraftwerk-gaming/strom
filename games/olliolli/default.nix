{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  innoextract,
}:

let
  # 2014 OlliOlli (Roll7) Windows IndieBox / disc release. Image is a
  # FAT16 disc dump (.iso) holding an InnoSetup installer that ships
  # both OlliOlli (1) and OlliOlli2 binaries side by side; we package
  # only the original, which advertises itself as DRM-free in its title
  # screen. The bundle predates the SDL2 Linux ports of the series, so
  # there is no native Linux build to use.
  src = fetchIpfs {
    cid = "QmcrW3kqUQ1xRpVCacFMZGvJr5jTSxS3JQnAQVzJM4GBjE";
    fallbackUrl = "https://archive.org/download/olliolli/OOOLLIWOOD.ISO";
    hash = "sha256-ZhCFeUZFKyVee/Rk5/C/12fGUqE0fiPe/kdnplKCjRw=";
    name = "olliolli2-welcome-to-olliwood-pc.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "olliolli";

  inherit src;

  nativeBuildInputs = [
    p7zip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    # 7z handles the FAT16 disc image: pulls out setup.exe + setup-1a.bin.
    7z x -y "$src" -o"$TMPDIR/iso"
    # InnoSetup 5.5; --gog flag is irrelevant here (no GOG ID) but sets
    # the layout to "app/<gamedir>/...". Both OlliOlli and OlliOlli2
    # land under app/.
    innoextract -d "$TMPDIR/iss" "$TMPDIR/iso/setup.exe"
    # Take only the original OlliOlli; the bundled OlliOlli2 still
    # depends on steam_api.dll for online ranking and we are not
    # shipping that integration here.
    cp -r "$TMPDIR/iss/app/OlliOlli"/. "$out"/
  '';

  runtime = "proton";
  executable = "olliolli.exe";

  saveLocations = [ "AppData/Roaming/olliolli" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "OlliOlli (2014 Roll7, IndieBox PC build, DRM-free, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "olliolli";
  };
}
