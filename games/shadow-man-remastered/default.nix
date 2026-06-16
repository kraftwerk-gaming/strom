{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # Shadow Man Remastered (Nightdive Studios 2021, KEX engine). A modern
  # 64-bit Vulkan/D3D11 remaster of the 1999 Acclaim action-adventure.
  # Windows-only (no native Linux build on GOG), so runtime = "proton".
  # The pixeldrain mirror is a zip wrapping the GOG offline installer
  # v1.5 (Inno Setup: setup_shadow_man_remastered_*.exe + a single
  # .bin chunk). innoextract --gog yields the game under app/ with the
  # KEX entry point thoth_x64.exe at the install root.
  src = fetchIpfs {
    cid = "QmWZHqBRM2R8mDmpn64hBMXK2QM8fgBX1myCBxpissvzTz";
    fallbackUrl = "https://pixeldrain.com/api/file/B15zSrEM?download";
    hash = "sha256-IA6OxFB36uN5AmsZ4MfEKvpP4njJWUbss5vBoNrkDk0=";
    name = "shadow-man-remastered-v1.5-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "shadow-man-remastered";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$TMPDIR/zip" "$out"
    unzip -q "$src" -d "$TMPDIR/zip"

    # The zip holds the GOG Inno Setup installer (the .exe stub plus its
    # .bin payload sit side by side). innoextract reads both from the
    # same directory; point it at the setup .exe.
    setupExe=$(find "$TMPDIR/zip" -iname 'setup_shadow_man_remastered*.exe' | head -n1)
    if [ -z "$setupExe" ]; then
      echo "ERROR: GOG setup .exe not found in archive" >&2
      find "$TMPDIR/zip" -maxdepth 3 -type f >&2
      exit 1
    fi
    innoextract --gog -d "$out" "$setupExe"

    if [ -d "$out/app" ]; then
      cp -a "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi
    rm -rf "$out/tmp" "$out/commonappdata" "$out/__redist" "$out/__support"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico "$out/goggame-galaxyFileList.web"

    [ -f "$out/thoth_x64.exe" ] || {
      echo "ERROR: thoth_x64.exe missing after extraction" >&2
      find "$out" -maxdepth 2 -iname '*.exe' >&2
      exit 1
    }
  '';

  runtime = "proton";
  executable = "thoth_x64.exe";

  # GOG/DRM-free build writes saves to
  # %USERPROFILE%\Saved Games\Nightdive Studios\Shadowman EX\saves
  # which under the Proton prefix is
  # drive_c/users/steamuser/Saved Games/Nightdive Studios/Shadowman EX.
  saveLocations = [ "Saved Games/Nightdive Studios/Shadowman EX" ];

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
    description = "Shadow Man Remastered (Nightdive Studios 2021, KEX engine, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadow-man-remastered";
  };
}
