{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  src = fetchIpfs {
    cid = "QmUHtxVXCPD2X7p7NG4sxNNewt3V8vEoyYCRw2tuzwryF7";
    fallbackUrl = "https://ipfs.io/ipfs/QmUHtxVXCPD2X7p7NG4sxNNewt3V8vEoyYCRw2tuzwryF7";
    hash = "sha256-CsduiV52QwQ6MFI4nK0ROKWmvq/AhOTciYwg+Q/xHs0=";
    name = "slay-the-spire-2-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "slay-the-spire-2";

  inherit src;

  # AnkerGames zip uses Zstd; needs 7zz, not unzip.
  nativeBuildInputs = [ _7zz ];

  # Layout: <root>/Slay the Spire 2/{SlayTheSpire2.exe,SlayTheSpire2.pck,
  # OnlineFix64.dll,data_sts2_windows_x86_64/,...}.  Bundled OnlineFix
  # winmm proxy spoofs SteamAPI for AppId 2868840 (FakeAppId 480 in the
  # ini → SteamAppId=480 to keep ColdClientLoader/OnlineFix happy under
  # Proton).
  buildScript = ''
    mkdir -p "$out"
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Slay the Spire 2/"* "$out"/
  '';

  runtime = "proton";
  executable = "SlayTheSpire2.exe";

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
    SteamAppId = "480";
    SteamGameId = "480";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Slay the Spire 2 (MegaCrit 2025, Early Access v0.103.2, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "slay-the-spire-2";
  };
}
