{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # SteamUnlocked pre-installed Time Flies v1.0.4 (Playables / Panic, 2023),
  # a tiny hand-drawn narrative game about the short life of a fly. Unity Mono
  # build (UnityPlayer.dll + MonoBleedingEdge). This is a RUNE release: the
  # Plugins/x86_64/ dir ships steam_api.dll / steam_api64.dll (RUNE's Steam
  # emulator shims) alongside the renamed originals steam_api.rne /
  # steam_api64.rne, so the Steam DRM is satisfied entirely offline by the
  # shipped crack — no gbe_fork/Goldberg swap is needed.
  #
  # Zip layout: Time.Flies/Time Flies/Time Flies.exe + Time Flies_Data/ +
  # MonoBleedingEdge/, plus a sibling _Redist/ (vcredist/dxwebsetup we don't
  # need under Proton) and steamunlocked advert files.
  #
  # Source: steamunlocked.org/time-flies-free-download/ -> uploadhaven.com
  # mirror (Time.Flies.zip, 198,610,182 bytes). The uploadhaven free-tier link
  # is countdown- and recaptcha-walled with an expiring per-session token, so
  # there is no stable direct fallbackUrl; IPFS-only once pinned.
  src = fetchIpfs {
    cid = "QmepDyeoMCh1xbqrgWX7QiVA3m6AdHZmCsakCC1U83zzaN";
    fallbackUrl = "";
    hash = "sha256-MdHYu5yH9SeoYflpW74uP3Xy+k++Ev2KHHrQHpEz9cA=";
    name = "time-flies-steamunlocked.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "time-flies";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Time.Flies/Time Flies/." "$out"/
    test -f "$out/Time Flies.exe" \
      || { echo "Time Flies.exe missing from extracted tree" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "Time Flies.exe";

  # Unity persistentDataPath on Windows:
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\, with
  # companyName/productName read from Time Flies_Data/app.info -> "Playables"
  # / "Time Flies" (verified by reading the file out of the source zip).
  saveLocations = [ "AppData/LocalLow/Playables/Time Flies" ];

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
    description = "Time Flies (Playables / Panic 2023, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "time-flies";
  };
}
