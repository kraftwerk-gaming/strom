{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  # Cryptmaster (Paul Hart & Lee Williams / Akupara Games, 2024) — a
  # word-based first-person dungeon crawler on Unity (Mono, x86_64).
  # GOG Unlocked v1.0351 release: a single zip wrapping the DRM-free GOG
  # InnoSetup bundle (setup_cryptmaster_1.0351_(74440).exe + a paired
  # .bin chunk). The uploadhaven mirror serves the file behind a 15-second
  # JS timer and an expiring per-request download token, so there is no
  # stable direct URL to use as fallbackUrl — the zip is IPFS-only once
  # pinned.
  src = fetchIpfs {
    cid = "QmWjQzXRXQbWTBBTbMmuZoU4uR3AUjUd8UU73EcFpMPJJn";
    fallbackUrl = "";
    hash = "sha256-2GmUWMQK/3fXgCW7shKx0U8W/ylN080YL2wPZ08g9RY=";
    name = "cryptmaster-gog-1.0351.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cryptmaster";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  # The outer zip wraps a single dir (Cryptmaster.v1.0351/) holding the
  # GOG InnoSetup .exe + .bin. innoextract --gog decodes both into a flat
  # tree whose top level IS the game root (CryptMaster.exe + UnityPlayer.dll
  # + CryptMaster_Data/ + MonoBleedingEdge/ + the GOG Galaxy DLLs). The
  # installer also drops app/, commonappdata/, tmp/, __redist/ and
  # goggame-* metadata next to it; those are mostly Galaxy/installer
  # bootstrap junk the engine never reads, so strip them — BUT the GOG
  # installer stages one engine-critical file under app/:
  # `app/CryptMaster_Data/LocalSettings.txt` (a 0-byte seed copied next to
  # the binary at install time). SaveManager.CheckLocalSettings() does an
  # UNGUARDED File.OpenText(Application.dataPath + "/LocalSettings.txt") —
  # no File.Exists check — so if that file is absent the read throws
  # FileNotFoundException, which aborts the first-load coroutine. The load
  # then hangs (stuck ~90%), GameManager.Start() never reaches
  # `rewiredControl = ReInput.players.GetPlayer(...)`, and MenuManager.Update
  # NREs every frame in ControlManager.KeyboardStartKey() on the null
  # rewiredControl — i.e. ALL input (keyboard/mouse/gamepad) is dead, the
  # menu never finishes. Merge app/CryptMaster_Data/ into the top-level
  # CryptMaster_Data/ to restore the seed before deleting app/.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip" "$TMPDIR/iss"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/Cryptmaster.v1.0351/setup_cryptmaster_1.0351_(74440).exe"

    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"

    if [ -d "$out/app/CryptMaster_Data" ]; then
      cp -rn "$out/app/CryptMaster_Data"/. "$out/CryptMaster_Data"/
    fi
    test -f "$out/CryptMaster_Data/LocalSettings.txt" \
      || { echo "LocalSettings.txt missing — load coroutine will hang" >&2; exit 1; }

    rm -rf "$out/app" "$out/commonappdata" "$out/tmp" "$out/__redist"
    rm -f "$out/goggame-"*.dll "$out/goggame-"*.info "$out/goggame-"*.hashdb \
      "$out/goggame-"*.ico

    test -f "$out/CryptMaster.exe" \
      || { echo "CryptMaster.exe missing from extracted tree" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "CryptMaster.exe";

  # Unity Mono writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\, with
  # companyName/productName read from CryptMaster_Data/app.info
  # (PaulHartandLeeWilliams / CryptMaster, verified by reading the file
  # out of the extracted bundle).
  saveLocations = [ "AppData/LocalLow/PaulHartandLeeWilliams/CryptMaster" ];

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
    description = "Cryptmaster (Paul Hart & Lee Williams / Akupara Games 2024, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cryptmaster";
  };
}
