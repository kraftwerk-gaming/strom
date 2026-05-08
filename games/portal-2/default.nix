{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  src = fetchIpfs {
    cid = "QmZekbNAWY6JUsJGJPCzHJouSjaJshbydniqhg85yThX7w";
    fallbackUrl = "https://ipfs.io/ipfs/QmZekbNAWY6JUsJGJPCzHJouSjaJshbydniqhg85yThX7w";
    hash = "sha256-thtdRcIZG3c5PsNh67ziFa2tG97pRbUwbOGgqLyIsjk=";
    name = "portal-2-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "portal-2";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  buildScript = ''
    mkdir -p "$out"
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract"
    # AnkerGames Portal-2 zip layout: <root>/Portal 2/portal2.exe etc.
    cp -r "$TMPDIR/extract/Portal 2"/. "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
  '';

  runtime = "proton";
  executable = "portal2.exe";

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
    SteamAppId = "620";
    SteamGameId = "620";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Same lsteamclient bypass as games/portal: force the bundled
    # Goldberg steam DLLs and disable Wine's lsteamclient proxy whose
    # legacy Source ABI is incomplete.
    WINEDLLOVERRIDES = "steam_api,steamclient,steamclient64=n,b;lsteamclient=";
  };

  meta = {
    description = "Portal 2 (Valve 2011, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "portal-2";
  };
}
