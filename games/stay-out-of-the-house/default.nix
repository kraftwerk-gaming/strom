{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # itch.io / GOG backup of the full retail v1.1.7 Windows build (Puppet
  # Combo, 2022), mirrored on archive.org under the open_source_software
  # collection and flagged "checked for malware" by an IA validator. This
  # is the GOG DRM-free release: the *_Data/Plugins/x86_64 tree ships
  # GOG's Galaxy64.dll + GalaxyCSharpGlue.dll alongside a vanilla
  # steam_api64.dll, and there is no steam_appid.txt. Unity's
  # Steamworks.NET / Galaxy plugins both degrade gracefully when no client
  # is running, so the engine boots offline with no Goldberg/gbe_fork swap
  # needed. The single zip wraps everything in a top-level
  # "STAY OUT OF THE HOUSE (WINDOWS) 1.1.7/" dir.
  src = fetchIpfs {
    cid = "QmeYYsBsxj68RyCSGSK2BaSaY18QTB3rY96TVXDNrZrP2d";
    fallbackUrl = "https://archive.org/download/stay-out-of-the-house-windows-1.1.7/STAY%20OUT%20OF%20THE%20HOUSE%20%28WINDOWS%29%201.1.7.zip";
    hash = "sha256-kvtRstcQFeWdEjEG56xd2spez88HZe0D8YR5dHw0sRA=";
    name = "stay-out-of-the-house-1.1.7.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stay-out-of-the-house";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Strip the single wrapping dir so $out/Stay out of the House.exe sits at
  # the root next to the Unity *_Data dir, UnityPlayer.dll and
  # MonoBleedingEdge/. Quote the glob: the tree is riddled with spaces.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/STAY OUT OF THE HOUSE (WINDOWS) 1.1.7/." "$out"/
    test -f "$out/Stay out of the House.exe" \
      || { echo "Stay out of the House.exe missing from extracted tree" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "Stay out of the House.exe";

  # Unity (Mono) writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\. app.info
  # in the build pins those as "PuppetCombo" / "Stay out of the House".
  saveLocations = [ "AppData/LocalLow/PuppetCombo/Stay out of the House" ];

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
    description = "Stay Out of the House (Puppet Combo 2022, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stay-out-of-the-house";
  };
}
