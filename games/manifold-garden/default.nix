{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Manifold Garden (William Chyr Studio, 2019). Unity first-person puzzle
  # game of recursive, Escher-esque architecture and rotatable gravity.
  # Windows / macOS / iOS only -- there is no native Linux build, so
  # runtime = "proton".
  #
  # SOURCE: SteamGG.NET pre-installed build v9427366 (pixeldrain mirror).
  # A plain zip of the already-installed IL2CPP game tree --
  # ManifoldGarden.exe + ManifoldGarden_Data/ + GameAssembly.dll +
  # UnityPlayer.dll, with the Steam DRM already stripped (gbe_fork
  # steam_api64.dll over the retail steam_api64.dll.bak, plus
  # steam_settings/ carrying appid 473950), so it starts without a running
  # Steam client. No installer step required.
  src = fetchIpfs {
    cid = "QmPu3YiQH3mFBBgPJu6BRXUD1c9X92ck8kYkpgU3LYDR4y";
    fallbackUrl = "https://pixeldrain.com/api/file/2S5vWK61?download";
    hash = "sha256-8WoekOzPlPRd5NGICKi3JjCca42W5bV82EHiPvjF/hU=";
    name = "manifold-garden-v9427366-steamgg.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "manifold-garden";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    # The SteamGG promo .url has a non-UTF-8 filename, which makes unzip
    # exit 1 (a non-fatal warning); tolerate that without tripping set -e.
    unzip -q "$src" -d "$TMPDIR/zip" || [ "$?" -le 1 ]

    # The zip ships the installed game tree inside one "Manifold.Garden...
    # - SteamGG.net" wrapper directory. Locate the dir that holds the .exe
    # and copy its contents to the install root.
    exe="$(find "$TMPDIR/zip" -maxdepth 3 -iname 'ManifoldGarden.exe' -print -quit)"
    if [ -z "$exe" ]; then
      echo "ManifoldGarden.exe not found in archive" >&2
      find "$TMPDIR/zip" -maxdepth 3 >&2
      exit 1
    fi
    cp -a "$(dirname "$exe")"/. "$out"/

    # Drop SteamGG promo junk and the unused redistributables installer dir.
    rm -f "$out"/*.url "$out"/Read_Me_Instructions.txt
    rm -rf "$out/_Redist" "$out/_CommonRedist"

    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. dredge/atomicrops).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "ManifoldGarden.exe";

  # Unity LocalLow tree (PCGamingWiki): AppData/LocalLow/William Chyr Studio/
  # Manifold Garden holds Saves/ + Settings.txt.
  saveLocations = [ "AppData/LocalLow/William Chyr Studio/Manifold Garden" ];

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
    description = "Manifold Garden (William Chyr Studio 2019, Unity recursive-gravity puzzle, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "manifold-garden";
  };
}
