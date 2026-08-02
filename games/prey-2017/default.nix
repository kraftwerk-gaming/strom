{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unzip,
}:

let
  # Prey (2017, Arkane Austin / Bethesda — the immersive sim, NOT the 2006
  # 3D Realms shooter). CryEngine. DRM-free on GOG, so no Steam/Goldberg
  # emulation is needed; runtime = "proton" (no native Linux build exists,
  # ProtonDB Platinum).
  #
  # SOURCE: the GOG "Prey Digital Deluxe Edition" offline installer set,
  # build 10966486 (GOG installer tag 38551), mirrored on archive.org as a
  # single 43.6 GiB zip. Inside, the base game lives under
  #   Prey Digital Deluxe Edition/Setup/setup_prey_10966486_(64bit)_(38551).exe
  #   + setup_prey_..._(38551)-{1..7}.bin   (GOG-Galaxy data slobs)
  # and the Mooncrash DLC under Setup/DLC/. innoextract reassembles the
  # base .exe from its sibling .bin shards. We only unzip + extract the
  # base Setup/ tree (the DLC is a separate ~10 GiB installer we skip).
  libvpx6 = pkgs.libvpx.overrideAttrs (old: {
    version = "1.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "webmproject";
      repo = "libvpx";
      rev = "v1.9.0";
      hash = "sha256-PsN8AOHZalYaB9OCu1yS5vJTvN8BAx8gCU8gtqoyu5s=";
    };
  });

  src = fetchIpfs {
    cid = "QmP66yV8tTvXaM9Wh4YaRBTGCMhtRzaoTyqsMDyMWXTy1W";
    fallbackUrl = "https://archive.org/download/prey-digital-deluxe-edition/Prey%20Digital%20Deluxe%20Edition.zip";
    hash = "sha256-cjSosp+Wy2IIzoEQXzq/XZFiih+OS3I6fWKt5PZ6fCc=";
    name = "prey-digital-deluxe-edition-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prey-2017";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unzip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/gog"

    # Pull only the base-game installer (the Setup/ tree, not Setup/DLC/)
    # out of the archive.org zip. -j flattens the paths so the .exe and its
    # .bin shards land side-by-side, which is what innoextract needs to
    # reassemble the GOG-Galaxy data slobs.
    unzip -j "$src" \
      "Prey Digital Deluxe Edition/Setup/setup_prey_*" \
      -x "Prey Digital Deluxe Edition/Setup/DLC/*" \
      -d "$TMPDIR/gog"

    # Reassemble + extract the base installer. innoextract pulls bytes from
    # the setup_prey_*-{1..7}.bin slobs in the same directory.
    innoextract -d "$TMPDIR/extract" -e "$TMPDIR/gog"/setup_prey_*.exe
    cp -r "$TMPDIR/extract"/. "$out"/
    chmod -R u+w "$out"

    # GOG installers stage the payload under app/ for some titles; flatten
    # if present.
    if [ -d "$out/app" ]; then
      cp -a "$out/app"/. "$out"/
      rm -rf "$out/app"
    fi

    # Drop GOG/Windows-only cruft (launcher metadata, redist installers).
    rm -rf "$out/__redist" "$out/commonappdata" "$out/tmp" "$out/__support"
    rm -f "$out"/goggame-*.{hashdb,info,script,ico} "$out/webcache.zip"
  '';

  runtime = "proton";
  # CryEngine ships Prey.exe deep under Binaries/<codename>/x64/Release/
  # ("Danielle" is Arkane's internal codename for Prey). The engine resolves
  # its asset roots (GameSDK/, Engine/, Localization/, system.cfg) relative
  # to the current working directory, which the strom wrapper sets to the
  # overlay root, so the deep exe path still finds the data tree.
  executable = "Binaries/Danielle/x64/Release/Prey.exe";

  # CryEngine writes saves + config under the Windows "Saved Games" known
  # folder: Saved Games\Arkane Studios\Prey\ (savegame.net / PCGamingWiki).
  # That lives under the Wine user profile, so relocate it to survive
  # wineprefix wipes.
  saveLocations = [ "Saved Games/Arkane Studios/Prey" ];

  # Prey's startup logo/intro movies play through Media Foundation, which
  # GE-Proton services with bundled gstreamer + libgstlibav. That H.264
  # decoder (libavcodec.so.58) is NEEDED-linked against host libs the Steam
  # Linux Runtime container would normally supply — libbz2, libvpx.so.6,
  # libva, libvdpau — which strom's FHS doesn't carry. Without them the
  # dlopen fails, no decoder registers, and the engine can black-screen on
  # the intro before the menu. Supply them in the FHS (cf. moving-out).
  targetPkgs = p: [
    p.bzip2
    p.libva
    p.libvdpau
    libvpx6
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
    description = "Prey (2017 Arkane Austin, CryEngine immersive sim, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prey-2017";
  };
}
