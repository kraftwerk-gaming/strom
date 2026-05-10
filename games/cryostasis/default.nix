{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  physxSrc = fetchIpfs {
    cid = "QmYv1ZHRo2ZQsyDeDFYw1ahrBadDVHULyBzWt4HaoyAjtw";
    fallbackUrl = "";
    hash = "sha256-A2EIqiI9C2XdoFx1YLvWBKCjakI6QpDESWXMotHkF0E=";
    name = "physx-cryostasis.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "cryostasis";

  src = fetchIpfs {
    cid = "QmdbyRwrQNTHKiyYX7fVST18y394fzKuAkqKbThSMqkaXS";
    fallbackUrl = "";
    hash = "sha256-1YQ8WD3sT/yeT5xdOrYjCPysAOf0QVHaDMPHb8BgX78=";
    name = "Cryostasis_Win_EN_Setup.zip";
  };

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p /tmp/cryo-setup "$out"
    unzip -q "$src" -d /tmp/cryo-setup
    setup_exe=$(find /tmp/cryo-setup -name 'setup_cryostasis_*.exe' | head -1)
    innoextract -d "$out" "$setup_exe"
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
    rm -rf "$out/tmp" "$out/commonappdata" /tmp/cryo-setup

    # Add PhysX runtime DLLs
    unzip -qj "${physxSrc}" -d "$out"


    # Set default resolution to 1080p
    sed -i 's/@v.sx = 1024/@v.sx = 1920/; s/@v.sy = 768/@v.sy = 1080/' "$out/config.cfg"
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "cryostasis.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    STEAM_COMPAT_APP_ID = "6780";
    SteamAppId = "6780";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Cryostasis: Sleep of Reason (GOG v2.0.0.13, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "cryostasis";
  };
}
