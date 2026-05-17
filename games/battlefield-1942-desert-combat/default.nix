{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Same "Battlefield 1942 HD" repack as the vanilla package: a full
  # pre-installed BF1942 Complete Collection with the Desert Combat
  # mods bundled in Mods/. We launch BF1942.exe with `+game DC_Final`
  # so the engine boots straight into the Desert Combat mod instead
  # of the WWII campaign.
  src = fetchIpfs {
    cid = "QmSnWcj6uRHNp1Mi7Xanhthx1AnBtzSu8Q2eRgGehYH2HT";
    fallbackUrl = "https://archive.org/download/battlefield-1942-hd.-7z/Battlefield%201942%20HD.7z";
    hash = "sha256-tp3CkNzSgxRyT8j9Tew9n4NI07hl+roISOFSkfqmz4g=";
    name = "battlefield-1942-hd.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "battlefield-1942-desert-combat";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/7z"
    cp -r "$TMPDIR/7z/Battlefield 1942 HD"/. "$out"/
    chmod -R u+w "$out"
  '';

  copyGlobs = [
    "Mods/DC_Final/Settings/"
    "Mods/DC_Final/Save/"
  ];

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # profile + settings under Mods/bf1942/Settings/Profiles/, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "BF1942.exe";
  executableArgs = [
    "+game"
    "DC_Final"
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

  meta = {
    description = "Battlefield 1942: Desert Combat (Trauma Studios mod v0.8 final, bundled with BF1942 base, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "battlefield-1942-desert-combat";
  };
}
