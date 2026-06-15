{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # SteamGG.net pre-installed Anemoiapolis: Chapter 1 v1.2 (Andrew Quist /
  # "Gular Production", 2023). Unity (Mono, HDRP) build cracked by TENOKE:
  # the Steam DRM bypass is a drop-in steam_api64.dll emulator plus a
  # tenoke.ini sitting next to it in AnemoiapolisChapter1_Data/Plugins/x86_64/.
  # The game links Steamworks.NET (com.rlabrecque.steamworks.net.dll), and
  # the emulated steam_api64.dll satisfies it transparently offline. tenoke.ini
  # pins appid=1522960, user="TENOKE", language="english", so no gbe_fork swap
  # is needed - the bundled emu reaches the main menu without a real Steam.
  #
  # Source: the SteamGG mirror serves a direct, scriptable pixeldrain zip
  # (no JS token / captcha gate), unlike the gofile/mega/1fichier mirrors
  # the other repack sites use. That direct URL is the fetchIpfs fallback.
  src = fetchIpfs {
    cid = "QmdFDwC6TXWJwNf7T9rAumNgg9ermgrFuRK37guyhX4tFW";
    fallbackUrl = "https://pixeldrain.com/api/file/h3cAiQJs";
    hash = "sha256-R+rowKlQcmHD0phrp/BFjyKZYNAPMaF4mLWZW/qjzfc=";
    name = "anemoiapolis-steamgg.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anemoiapolis";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # The zip wraps a single top-level dir
  # ("Anemoiapolis.Chapter.1.v1.2 - SteamGG.net/"). Strip it so
  # $out/AnemoiapolisChapter1.exe sits at the root next to the Unity
  # *_Data dir and MonoBleedingEdge/. Drop the SteamGG advert files.
  #
  # The zip's advert .url entries carry a non-ASCII en-dash in their
  # filename whose "local" and "central" directory records disagree, so
  # unzip prints a "mismatching local filename" warning and exits 1 even
  # though every file extracts correctly. Tolerate exit code <= 1 (1 is
  # unzip's "warning, extraction succeeded" code) so set -e doesn't abort.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" || [ "$?" -le 1 ]
    cp -r "$TMPDIR/extract/Anemoiapolis.Chapter.1.v1.2 - SteamGG.net/." "$out"/
    rm -f "$out/Read_Me_Instructions.txt"
    find "$out" -maxdepth 2 -iname '*.url' -delete
    test -f "$out/AnemoiapolisChapter1.exe" \
      || { echo "AnemoiapolisChapter1.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/AnemoiapolisChapter1_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (TENOKE emu) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "AnemoiapolisChapter1.exe";

  # Unity Mono writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\, with the
  # names read from AnemoiapolisChapter1_Data/app.info, which pins them as
  # "AndrewQuistGames" / "AnemoiapolisChapter1" (verified by reading the
  # file out of the source zip).
  saveLocations = [ "AppData/LocalLow/AndrewQuistGames/AnemoiapolisChapter1" ];

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

  env = {
    # Match the Steam appid the TENOKE emu expects (tenoke.ini id=1522960).
    SteamAppId = "1522960";
    SteamGameId = "1522960";
  };

  meta = {
    description = "Anemoiapolis: Chapter 1 (Andrew Quist 2023, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anemoiapolis";
  };
}
