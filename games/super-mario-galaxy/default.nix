{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Super Mario Galaxy (Nintendo EAD Tokyo, 2007), Wii, USA release. Run via
  # Dolphin, the same runtime as the GameCube titles already in the tree
  # (pokemon-colosseum, pokemon-xd-gale-of-darkness) -- this is the first Wii
  # disc here, which matters for input; see WII REMOTE below.
  #
  # The disc image is the Redump USA dump, shipped in Dolphin's own RVZ
  # container rather than as a raw .iso: 3425535460 bytes of zstd-19 RVZ with
  # 128 KiB blocks, versus 4699979776 bytes uncompressed, and lib/dolphin.nix
  # accepts .rvz directly, so recompressing to .iso would only cost 1.2 GiB of
  # store and IPFS for no gain.
  #
  # Verified with dolphin-tool before pinning, not taken from the file name:
  #   header  Game ID RMGE01, internal name "SUPER MARIO GALAXY", revision 0,
  #           region NTSC-U, country USA
  #   verify  `dolphin-tool verify --algorithm=sha1` decompresses to sha1
  #           a36105c9fbfff6041dc5babf4318c6a216ad470a, which is exactly the
  #           Redump entry "Super Mario Galaxy (USA, Canada) (En,Fr,Es)"
  #           (size 4699979776, crc 1047de4c). So the RVZ is a lossless
  #           re-container of the verified Redump disc, not a scrubbed or
  #           trimmed image.
  # The archive.org item serves it inside a TorrentZip (3423970284 bytes, sha1
  # 5569f7f3292c93a4c34e53077822515d7a05cde7, matching the item's published
  # checksum), so the FOD pins the zip and the build extracts the single member.
  discArchive = fetchIpfs {
    cid = "QmU2Sfm3ji9nknoXUzgabuXpZrwJFAGEFWZDLPM9k8VxsH";
    fallbackUrl = "https://archive.org/download/super-mario-galaxy-usa-en-fr-es_202603/Super%20Mario%20Galaxy%20%28USA%29%20%28En%2CFr%2CEs%29.zip";
    hash = "sha256-Fr34owX4F/YoVeVnbSLYbtk5UmCNXdMJjnD/jVesI/4=";
    name = "super-mario-galaxy.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-mario-galaxy";

  ipfsSources = [ discArchive ];
  src = discArchive;

  nativeBuildInputs = [ pkgs.unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -p "$src" 'Super Mario Galaxy (USA) (En,Fr,Es).rvz' \
      > "$out/super-mario-galaxy.rvz"
  '';

  runtime = "dolphin";
  executable = "super-mario-galaxy.rvz";

  # WII REMOTE: both input paths work, and neither is Dolphin's stock default
  # alone. lib/dolphin.nix seeds GCPadNew.ini for GameCube and, since the
  # Wiimote seeder was added for this game, WiimoteNew.ini for Wii discs:
  # slot 1 gets the first SDL pad as its Device with the keyboard layered on
  # as a second binding, slots 2-4 get further pads, and the file is reseeded
  # if it names an SDL device that is no longer attached.
  #
  # The desk map is Dolphin's own stock profile, kept intact by that layering
  # and verified in game before the pad work: driven through gamescope's
  # nested Xwayland with xdotool, left+right click together cleared the
  # "Press both A and B" title gate, mouse motion moved the star cursor onto a
  # save planet and highlighted it, A there opened "Create a game file on this
  # planet?", and the run reached the Star Festival plaza with the full HUD
  # (Life 3, Mario x4). Holding W walked Mario up the path and picked up Star
  # Bits, so the Nunchuk half works too (Extension = Nunchuk).
  #   mouse            IR pointer (Star Bits, Launch Stars, the P2 cursor)
  #   left / right     A / B
  #   middle           shake, i.e. the spin attack
  #   W A S D          Nunchuk stick (movement)
  #   Control_L        Nunchuk C     Shift_L    Nunchuk Z
  #   1 2 Q E Return   Wiimote 1, 2, -, +, Home
  #
  # The pad map, from the same seeder:
  #   A / B            Wiimote A / B
  #   Shoulder R       shake, i.e. the spin attack
  #   right stick      IR pointer, ABSOLUTE (centre stick = centre screen)
  #   left stick       Nunchuk stick
  #   Trigger L        Nunchuk Z     Shoulder L   Nunchuk C
  #   Start Back Guide Wiimote + - Home
  #
  # Pointing is absolute rather than `IR/Relative Input = True` because that
  # setting is per-remote: turning it on for the stick would make the mouse
  # relative too and break the desk map above.
  #
  # Verified end to end on this title with a uinput virtual pad that SDL sees
  # as an Xbox 360 Controller: the seeded file bound SDL/0/Xbox 360 Controller
  # on slot 1, and synthetic A+B presses cleared the title gate and advanced
  # the game to the save-file planets with the Wiimote pointer centred.
  #
  # Wii saves land in Dolphin's NAND under the per-game data dir, verified:
  # ~/.strom/super-mario-galaxy/dolphin-user/Wii/title/00010000/524d4745/data/
  # GameData.bin ("RMGE" = the disc's title id) appeared the moment the file
  # was created, so progress survives store GC and rebuilds like the GameCube
  # memory cards do. No saveLocations entry is involved; that option is a
  # Proton-prefix concept and this runtime is not Proton.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Super Mario Galaxy (Nintendo 2007, Wii, via Dolphin)";
    mainProgram = "super-mario-galaxy";
    platforms = [ "x86_64-linux" ];
  };
}
