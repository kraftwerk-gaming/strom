{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Overcooked! 2 (Ghost Town Games / Team17, 2018; Unity 2017.3, 32-bit x86).
  # Sourced from the "Overcooked 2-PLAZA" pre-cracked ISO (Steam build,
  # AppId 728880). The ISO is an Inno Setup 5.5 loader (setup.exe) plus a
  # 2.3 GiB FreeArc payload (setup-1.bin) that only decodes through the
  # Win32 ISDone.dll/unarc.dll codec stack at install time, so the
  # sandboxed FOD can't unpack it. Following the strom convention for
  # FreeArc/ISDone repacks (see far-cry-2, magicka): install once silently
  # on the build host under wine (setup.exe /VERYSILENT), apply the Steamworks
  # emulator swap below, drop the uninstaller, and pin the result as a
  # deterministic tar.zst -- consumers just fetchIpfs + tar. Runs through Proton.
  #
  # Steamworks emu: the game loads its Steamworks layer through the Unity
  # native plugin Overcooked2_Data/Plugins/CSteamworks.dll, which imports
  # steam_api.dll. The ISO's PLAZA/CODEX crack is a DLL chain
  # (steam_api.dll -> CODEX.dll -> GameOverlayRenderer.dll + steamclient.dll)
  # whose GameOverlayRenderer.dll (Steam's D3D overlay injector) faults under
  # Wine/Proton: Unity reports "Plugins: Failed to load CSteamworks.dll with
  # error 'No access to memory location'" (an access violation in the overlay
  # hook) and Overcooked2.exe exits before the main menu. So we replace the
  # whole CODEX chain with gbe_fork (the maintained Goldberg fork) -- its
  # self-contained 32-bit steam_api.dll + steamclient.dll fake SteamAPI_Init
  # synchronously with no overlay/injection and no live Steam process. The
  # game-expected interface versions (SteamClient017/SteamUser019/... extracted
  # from the original PLAZA steam_api.dll) are pinned in steam_interfaces.txt so
  # gbe_fork's CreateInterface dispatcher resolves CSteamworks' requests. The
  # emu DLLs + steam_settings/ live in BOTH the game root and Plugins/.
  src = fetchIpfs {
    cid = "QmcVBZrRcaxjjUgzRSviiXo7bQ1CFpdG4sehFDcfV2QPdp";
    fallbackUrl = "";
    hash = "sha256-J0F3qw6eaYvugtGWUUobXssf6koxmTOO1iGQroxvKsY=";
    name = "overcooked-2.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "overcooked-2";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";
  executable = "Overcooked2.exe";

  # gbe_fork stores its emulated Steam state under
  # AppData/Roaming/GSE Saves/ (settings + per-app remote storage). Overcooked
  # 2 persists progress via Steam Cloud (ISteamRemoteStorage), which gbe_fork
  # redirects into GSE Saves/728880/remote, so relocating that single tree
  # preserves the savegame across prefix wipes. The path is steamuser-rooted,
  # so the standard lib/proton.nix migration handles it.
  saveLocations = [ "AppData/Roaming/GSE Saves" ];

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
    SteamAppId = "728880";
    SteamGameId = "728880";
    # Load the gbe_fork Steamworks emu DLLs native (never Wine's builtin stubs).
    WINEDLLOVERRIDES = "steam_api,steamclient=n,b";
  };

  meta = {
    description = "Overcooked! 2 (Ghost Town Games / Team17 2018, Unity, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "overcooked-2";
  };
}
