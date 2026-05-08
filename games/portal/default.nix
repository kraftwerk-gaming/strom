{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  src = fetchIpfs {
    cid = "QmbjX2XZdYpD9yxvPb14JZzuxaDqALDcmK8kLqTEH6oXkm";
    fallbackUrl = "https://ipfs.io/ipfs/QmbjX2XZdYpD9yxvPb14JZzuxaDqALDcmK8kLqTEH6oXkm";
    hash = "sha256-ctby8uHhRf/7hpanorANqnarqZLb5+114jgLYq27wMI=";
    name = "portal-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "portal";

  inherit src;

  # AnkerGames zip uses Zstd (deflate-zstd 93); needs 7zz, not unzip.
  nativeBuildInputs = [ _7zz ];

  # Layout: <root>/Portal/{Launcher.exe,hl2.exe,portal/,steam_settings/,...}
  # Launcher.exe is ColdClientLoader (Goldberg steam emu) and exec's
  # `hl2.exe -game portal -steam` with AppId 400. We launch hl2.exe
  # directly with the steam_settings/ alongside it.
  buildScript = ''
    mkdir -p "$out"
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Portal/"* "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
  '';

  runtime = "proton";
  # Launch hl2.exe directly rather than the Goldberg ColdClientLoader
  # Launcher.exe wrapper. ColdClientLoader's job is to inject the Goldberg
  # steamclient.dll into the target before launching it; under Wine that
  # injection step is unnecessary because WINEDLLOVERRIDES already pins
  # the loader to the native (bundled) steam DLLs. Skipping the loader
  # also avoids its CreateProcess/WaitForSingleObject/ExitProcess wait
  # chain hanging when the child exits abnormally.
  executable = "hl2.exe";
  executableArgs = [
    "-game"
    "portal"
    "-steam"
  ];

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
    SteamAppId = "400";
    SteamGameId = "400";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Force native (bundled Goldberg) steam_api.dll and steamclient*.dll
    # over Wine's builtin lsteamclient.dll proxy. Wine 10's lsteamclient
    # is missing legacy Source-engine entry points like
    # Steam_TerminateGameConnection: when launcher.dll's SteamAPI_Init
    # path resolves "steamclient.dll!Steam_TerminateGameConnection" Wine
    # would otherwise satisfy it from its lsteamclient stub and abort
    # with "unimplemented function lsteamclient.dll.Steam_TerminateGameConnection".
    # The bundled Goldberg steamclient.dll exports the full legacy ABI;
    # disable Wine's builtin lsteamclient outright so the loader does not
    # rewrite steamclient.dll references to it.
    WINEDLLOVERRIDES = "steam_api,steamclient,steamclient64=n,b;lsteamclient=";
  };

  meta = {
    description = "Portal (Valve 2007, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "portal";
  };
}
