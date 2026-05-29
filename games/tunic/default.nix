{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "tunic";

  # TUNIC (Andrew Shouldice / Finji 2022). Isometric action-adventure on
  # Unity (IL2CPP); no native Linux build, so it runs through Proton (Steam
  # Deck Verified). Source is an "AnkerGames" pre-installed/DRM-free repack:
  # a RAR5 archive containing a ready-to-run game folder TUNIC/ (Tunic.exe +
  # Tunic_Data/ + UnityPlayer.dll + GameAssembly.dll), alongside two junk
  # files (Read Me.txt, AnkerGames .url) that we drop on extraction.
  # cid-only: the repack is distributed via rotating torrent magnets, so
  # there is no stable direct mirror URL to use as a fallback.
  src = fetchIpfs {
    cid = "QmYSZpUkTM1fjVhy9krrjAJwgZdkPhtYGFx8SbevwHxd4b";
    hash = "sha256-Lix/z/67IHS/oRDnNHXtTnspsAzBezcncEh2acBSt9M=";
    name = "TUNIC-AnkerGames.rar";
  };

  # bsdtar (libarchive) reads RAR5 fine and is free, unlike unrar; using it
  # keeps allowUnfree out of the flake.
  nativeBuildInputs = [ libarchive ];

  buildScript = ''
    mkdir -p "$out"
    # Extract only the game folder; skip the repack's junk metadata files.
    bsdtar -xf "$src" -C "$out" TUNIC
    # Flatten the single TUNIC/ wrapper dir so executable= resolves.
    cp -a "$out/TUNIC"/. "$out"/
    rm -rf "$out/TUNIC"
  '';

  runtime = "proton";
  executable = "Tunic.exe";

  # Unity persistentDataPath; the working title "Secret Legend" survives
  # as the product folder under the Andrew Shouldice company dir.
  saveLocations = [ "AppData/LocalLow/Andrew Shouldice/Secret Legend" ];

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
    description = "TUNIC (Andrew Shouldice / Finji 2022, isometric action-adventure, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "tunic";
  };
}
