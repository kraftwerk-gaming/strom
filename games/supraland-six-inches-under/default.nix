{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Supraland Six Inches Under (Supra Games, 2022), standalone expansion,
  # Unreal Engine 4. Steam app 1522870.
  #
  # RUNTIME = proton (NOT native). Six Inches Under was Steam-only at
  # launch and has no GOG/DRM-free release. The RUNE scene release
  # (v1.2.3349, 2024-07-27) replaces steam_api64.dll with a Steam
  # emulator stub so the UE4 app starts without a live Steam client.
  # The source archive is a tar.zst of the cracked install tree with
  # the `Supraland Six Inches Under/` prefix stripped at extract time;
  # `SupralandSIU.exe` lands directly at the overlay root.
  # No fallbackUrl: a locally-repacked tar.zst with no public URL for these
  # exact bytes -- IPFS is the canonical source.
  src = fetchIpfs {
    cid = "QmYg4ALK7ahcJr59NoUX12iC8dcwrC54E8s4qQwStiiGhg";
    hash = "sha256-wnXtpjPd0WHJqx9buvcr385jstoSjubygB8j3pJwe60=";
    name = "supraland-six-inches-under.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "supraland-six-inches-under";

  inherit src;

  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --use-compress-program=zstd -xf "$src" -C "$out" --strip-components=1
  '';

  runtime = "proton";
  # UE4 launcher stub at the install root; re-execs the Win64 shipping exe.
  executable = "SupralandSIU.exe";

  # UE4 writes saves/config under %LOCALAPPDATA%\SupralandSIU\Saved.
  saveLocations = [ "AppData/Local/SupralandSIU/Saved" ];

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
    description = "Supraland Six Inches Under (Supra Games 2022, Unreal Engine 4, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "supraland-six-inches-under";
  };
}
