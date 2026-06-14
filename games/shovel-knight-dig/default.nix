{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # Shovel Knight Dig (Yacht Club Games / Nitrome, 2022). Unity Mono
  # roguelike platformer; Windows-only Steam build (skDig64.exe +
  # skDig64_Data/, Steamworks.NET via com.rlabrecque.steamworks.net.dll),
  # so runtime = "proton".
  #
  # AnkerGames pre-installed repack. The repack already ships gbe_fork
  # (Goldberg fork) as the Steam DRM bypass: the 7.3 MB
  # skDig64_Data/Plugins/x86_64/steam_api64.dll is the gbe_fork shim,
  # the original retail dll is preserved alongside as steam_api64.dll.bak,
  # and steam_settings/ pins steam_appid.txt = 1416050 plus the emulated
  # user/overlay configs. Steamworks.NET dlopens steam_api64.dll, so the
  # emulator loads transparently when Unity boots - the game runs fully
  # offline without a steam_api swap of our own.
  #
  # The AnkerGames CDN serves the zip from an IP/time-signed tunnel URL
  # (tunnel5.dlproxy.uk/...?sig=...) that expires, so there is no stable
  # direct mirror to use as fallbackUrl; the file is IPFS-only once pinned.
  src = fetchIpfs {
    cid = "QmW5sbvthozq9QHC6ZvN1SJmKoLFm2wh6XNt1h1vEowMMf";
    fallbackUrl = "";
    hash = "sha256-xqc6Ws8GhZcXgmSflpj4QEXkLT6OtaNskCGJePV0C5c=";
    name = "shovel-knight-dig-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shovel-knight-dig";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # The zip is zstd-compressed (PKWARE method 93), which classic `unzip`
  # cannot inflate (it bails with exit 81 after only creating the empty
  # dir entries), so extract with 7-Zip (_7zz) which supports zstd zips.
  # The archive wraps everything under a single "Shovel Knight Dig/" dir.
  # Strip it so $out/skDig64.exe sits at the root next to skDig64_Data/
  # and MonoBleedingEdge/. Drop the AnkerGames advert/readme/bat cruft.
  buildScript = ''
    mkdir -p "$out"
    7zz x -bd -o"$TMPDIR/extract" "$src" >/dev/null
    cp -r "$TMPDIR/extract/Shovel Knight Dig/." "$out"/
    test -f "$out/skDig64.exe" \
      || { echo "skDig64.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/skDig64_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "gbe_fork steam_api64.dll missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "skDig64.exe";

  # Unity Mono writes saves under %USERPROFILE%\AppData\LocalLow\
  # <companyName>\<productName>\; app.info pins these as
  # "Yacht Club Games" / "Shovel Knight Dig".
  saveLocations = [ "AppData/LocalLow/Yacht Club Games/Shovel Knight Dig" ];

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
    # Match the Steam appid the bundled gbe_fork emulator expects
    # (steam_settings/steam_appid.txt).
    SteamAppId = "1416050";
    SteamGameId = "1416050";
  };

  meta = {
    description = "Shovel Knight Dig (Yacht Club Games / Nitrome 2022, Unity roguelike platformer, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shovel-knight-dig";
  };
}
