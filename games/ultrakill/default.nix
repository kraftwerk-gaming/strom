{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # ULTRAKILL (New Blood Interactive / Hakita, 2020 Early Access). Repack
  # via ankergames Ultrakill-AnkerGames.zip — a ULTRAKILL/ tree pre-built
  # from clean Steam files plus a Goldberg steam_api64.dll for offline
  # play. The Redist/ tree (DirectX/PhysX/VC) is bundled by the repacker
  # and is unnecessary under Proton.
  src = fetchIpfs {
    cid = "PLACEHOLDER_CID";
    fallbackUrl = "https://ipfs.io/ipfs/PLACEHOLDER_CID";
    hash = "sha256-n+SoIWksjWnFtkBFQ0ey/SHaVW4OaaM/TrVupn87Pf4=";
    name = "ultrakill-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "ultrakill";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # ankergames zip layout: ULTRAKILL/ULTRAKILL.exe + ULTRAKILL_Data/ +
  # MonoBleedingEdge/ + UnityPlayer.dll + bundled Goldberg steam_api64.dll.
  # Drop the AnkerGames advert URL and the Redist/ pre-installer tree.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/ULTRAKILL/"* "$out"/
    rm -f "$TMPDIR/extract/AnkerGames - Free Pre-installed PC Games.url" 2>/dev/null || true
  '';

  runtime = "proton";
  executable = "ULTRAKILL.exe";

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
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "ULTRAKILL (New Blood / Hakita 2020 Early Access, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ultrakill";
  };
}
