{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
}:

let
  # AnkerGames pre-installed Easy Delivery Co. (Sam C. / Oro Interactive,
  # 2025). A Unity Mono build (not IL2CPP): the game code lives in
  # EasyDeliveryCo_Data/Managed/Assembly-CSharp.dll and it links Steam via
  # Steamworks.NET (com.rlabrecque.steamworks.net.dll ->
  # Plugins/x86_64/steam_api64.dll). The repack ships a pre-cracked Steam
  # emulator in place of the Valve steam_api64.dll: the bundled DLL is
  # 1958912 bytes whereas Plugins/Steamworks.NET.txt records the genuine
  # Valve DLL as 319584 bytes, so the emu is already loaded transparently
  # when Steamworks.NET boots - no offline-AV swap needed at stage time.
  #
  # The AnkerGames zip uses Zstd-compressed entries, which info-zip's
  # unzip and p7zip 17.05 cannot inflate; libarchive's bsdtar handles
  # them (libzstd built in).
  #
  # Source: ankergames.net /game/easy-delivery-co -> signed dlproxy.uk
  # tunnel URL (Easy-Delivery-Co-AnkerGames.zip, 411640999 bytes). That
  # URL is short-lived/IP-bound, so no stable fallbackUrl; IPFS-only once
  # pinned.
  src = fetchIpfs {
    cid = "QmcLPetJ1bDALGMUnspzJSsB4aTwob58537ic2fm8uiDWv";
    fallbackUrl = "";
    hash = "sha256-YMjpGQ0KHr419OCGEUZ3ZBxIEHidOuyGu+W5SjE0GBs=";
    name = "easy-delivery-co-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "easy-delivery-co";

  inherit src;

  nativeBuildInputs = [ libarchive ];

  # The zip wraps a single top-level "Easy Delivery Co/" dir. Strip it so
  # $out/EasyDeliveryCo.exe sits at the root next to EasyDeliveryCo_Data/,
  # the D3D12/ Agility-SDK runtime dir and MonoBleedingEdge/. Drop the
  # AnkerGames marketing shortcut.
  buildScript = ''
    mkdir -p "$out"
    bsdtar -xf "$src" -C "$TMPDIR"
    cp -a "$TMPDIR/Easy Delivery Co/." "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url"
    test -f "$out/EasyDeliveryCo.exe" \
      || { echo "EasyDeliveryCo.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/EasyDeliveryCo_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (Steam emu) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "EasyDeliveryCo.exe";

  # Unity Mono writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\.
  # EasyDeliveryCo_Data/app.info pins these as "SamC" / "EasyDeliveryCo"
  # (read out of the source zip).
  saveLocations = [ "AppData/LocalLow/SamC/EasyDeliveryCo" ];

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
    description = "Easy Delivery Co. (Sam C. / Oro Interactive 2025, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "easy-delivery-co";
  };
}
