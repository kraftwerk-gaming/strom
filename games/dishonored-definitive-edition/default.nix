{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Pre-decoded Dishonored: Definitive Edition install tree (Arkane
  # Studios 2013 remaster of the 2012 original + all DLC: Knife of
  # Dunwall, Brigmore Witches, Dunwall City Trials, Void Walker's
  # Arsenal; GOG build, game ID 1701063787).
  #
  # The upstream R.G. Catalyst repack ships the game payload as
  # encrypted FreeArc Data-*.catalyst blobs ("tor:7:256mb+aes-256/ctr"
  # chain) behind an Inno Setup 5.5.0.1 installer; the AES key is
  # embedded in the .exe and only the bundled Win32 CLS-* decompressors
  # (cls-srep/cls-lolz/cls-uelr) can produce plaintext, so there is no
  # build-time Linux decoder. We ran that installer once under the
  # project's Proton (GE-Proton via umu) on the build host — the CLS-*
  # decompressors run fine under Proton — and archived the resulting
  # install tree (Binaries/Win32/Dishonored.exe + DishonoredGame/ +
  # Engine/, ~12 GiB) as this tar.zst. Same one-time-host-install
  # pattern as freelancer/magicka, just decoding a catalyst payload
  # rather than a retail CD.
  #
  src = fetchIpfs {
    cid = "QmXupcbMi8gY16HFez7vYdKS48M5n6Hwjoe2BU1cc1NJ6r";
    hash = "sha256-XzExaRbLnlI6RAujlCx3uEZpeiVaF+wNjK0G+vQ9+EU=";
    name = "dishonored-definitive-edition.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dishonored-definitive-edition";

  inherit src;

  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  # The tar's top level is the install root (Binaries/, DishonoredGame/,
  # Engine/), so extracting straight into $out lands Dishonored.exe at
  # Binaries/Win32/Dishonored.exe.
  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";
  executable = "Binaries/Win32/Dishonored.exe";

  # Dishonored writes savegames + per-user .ini config under
  # Documents/My Games/Dishonored/ (standard older-Bethesda/idTech
  # layout shared with Wolfenstein TNO etc.). Relocating the whole
  # "My Games" parent into $STROM_GAMEDIR survives prefix wipes and
  # keeps room for other Bethesda titles to coexist.
  saveLocations = [ "Documents/My Games" ];

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
    description = "Dishonored: Definitive Edition (Arkane Studios 2013, all DLC, R.G. Catalyst repack pre-decoded to a real install tree, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dishonored-definitive-edition";
  };
}
