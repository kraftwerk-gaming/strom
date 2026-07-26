{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # The Black Mirror (2003 Future Games / cdv / The Adventure Company),
  # the original point-and-click adventure on the AGDS engine -- NOT the
  # 2017 reboot. archive.org "2003-the-black-mirror" ships a pre-installed
  # copy as a single RAR5 whose top-level "The Black Mirror/" directory is
  # the ready-to-run game tree (agds.exe engine + BMirror.exe front-end,
  # BMirror.dll resources, data.adb/patch.adb, gfx1-6.grp asset packs). No
  # installer step is needed; the buildScript just flattens the tree.
  src = fetchIpfs {
    cid = "QmV8whLp7FnitCV1AjZ5f9brdaHDqM117XM7u4AWHKNGvY";
    fallbackUrl = "https://archive.org/download/2003-the-black-mirror/2003%20-%20The%20Black%20Mirror.rar";
    hash = "sha256-Czfm8UmT2NFSCUkNQgqhHRoMnNe+r7JppvCLiCCngq4=";
    name = "the-black-mirror.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-black-mirror";

  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" -f "$src"
    # The RAR nests everything under a single "The Black Mirror/" dir;
    # flatten it so agds.cfg / gfx*.grp sit next to the exe (the engine
    # reads them relative to the executable's working directory).
    cp -r "$TMPDIR/rar/The Black Mirror"/. "$out"/
  '';

  runtime = "proton";

  # BMirror.exe is the branded retail front-end (the Start Menu shortcut
  # target) paired with BMirror.dll; it drives the AGDS engine (agds.exe)
  # and reads agds.cfg + the gfx*.grp packs from its own directory.
  executable = "BMirror.exe";

  # AGDS-engine adventures save next to the binary in the install dir
  # (the pre-installed tree already ships savnames.txt plus grabNNNN.BMP
  # save thumbnails there), not under drive_c/users/steamuser/... . Those
  # writes persist via the per-game fuse-overlayfs upper, so no
  # relocation is required. UNTESTED: if a save probe shows the engine
  # writing under the wineprefix instead, add that path here.
  saveLocations = [ ];

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
    description = "The Black Mirror (2003 Future Games / The Adventure Company point-and-click adventure, AGDS engine, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-black-mirror";
  };
}
