{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "empire-earth-iii";

  # GOG offline installer (DRM-free) mirrored on archive.org as a zip
  # wrapping the InnoSetup setup .exe + two .bin slices. The zip itself
  # isn't the game data; the buildScript unzips it, then innoextracts
  # the InnoSetup installer (no wine at build time).
  src = fetchIpfs {
    cid = "QmebEL9cUfCPqTMJNTBxWfsBeZ3Fikk5bDctSpwqLSGUQi";
    fallbackUrl = "https://archive.org/download/empire-earth-3-gog-version/Empire.Earth.3.v1.0.zip";
    hash = "sha256-sgyvM9MHIqJXDiCqG3yzxDmtEyF8k9ucw8DXewYAWMs=";
    name = "empire-earth-iii-gog.zip";
  };

  nativeBuildInputs = [
    innoextract
    unzip
    p7zip
  ];

  # zip -> setup_empire_earth_iii_1.0_(22018).exe + -1/-2.bin, then
  # innoextract the installer. GOG InnoSetup lays the install tree under
  # app/; flatten it to $out.
  #
  # EE3.exe statically imports PhysXLoader.dll (PhysX SDK 2.8.x). The GOG
  # tree ships only the NVIDIA PhysX *installer*
  # (__redist/PHYSX/PhysX-9.17.0524-SystemSoftware.exe), never the runtime
  # DLLs, so the exe dies with STATUS_DLL_NOT_FOUND before rendering. That
  # installer is a plain 7z self-extractor; pull the 32-bit runtime out of
  # it and drop it next to EE3.exe. PhysXLoader.dll's local-core path
  # (enableLocalPhysXCore) resolves PhysXCore.dll/PhysXCooking.dll from its
  # own directory, so no NVIDIA-System-Software registry install is needed.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip"
    unzip -q "$src" -d "$TMPDIR/zip"
    setup=$(find "$TMPDIR/zip" -iname 'setup_empire_earth_iii*.exe' | head -1)
    innoextract -d "$out" "$setup"
    if [ -d "$out/app" ]; then
      cp -r "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi
    chmod -R u+w "$out"

    # Harvest the PhysX 9.17.0524 runtime DLLs next to EE3.exe.
    physx="$out/__redist/PHYSX/PhysX-9.17.0524-SystemSoftware.exe"
    7z x -y -o"$TMPDIR/physx" "$physx" \
      'PhysX/files/Common/PhysXLoader.dll' \
      'PhysX/files/Common/PhysXDevice.dll' \
      'PhysX/files/Engine/v2.8.3/PhysXCore.dll' \
      'PhysX/files/Engine/v2.8.3/PhysXCooking.dll' >/dev/null
    install -m644 \
      "$TMPDIR/physx/PhysX/files/Common/PhysXLoader.dll" \
      "$TMPDIR/physx/PhysX/files/Common/PhysXDevice.dll" \
      "$TMPDIR/physx/PhysX/files/Engine/v2.8.3/PhysXCore.dll" \
      "$TMPDIR/physx/PhysX/files/Engine/v2.8.3/PhysXCooking.dll" \
      "$out/"
  '';

  runtime = "proton";

  # The Mad Doc engine writes profiles, savegames and config under
  # %USERPROFILE%\Documents\Empire Earth III\ (profiles/<user-id>/...).
  # Relocate the whole dir so progress survives prefix wipes.
  saveLocations = [ "Documents/Empire Earth III" ];
  executable = "EE3.exe";

  env = {
    # 32-bit Direct3D 9 engine; LAA lets it address >2 GiB.
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

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
    description = "Empire Earth III (Mad Doc 2007, GOG offline installer, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "empire-earth-iii";
  };
}
