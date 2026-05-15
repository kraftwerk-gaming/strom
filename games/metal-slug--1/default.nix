{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Metal Slug - Super Vehicle-001 (Nazca / SNK, 1996). Neo Geo MVS
  # arcade run-and-gun. The ROM set is the FBNeo-compatible parent
  # `mslug.zip`: the per-cart program/graphics/sound chips plus the
  # Neo Geo BIOS files (sfix.sfix, sp-*.sp1, sm1.sm1, ...) FBNeo expects
  # to find inside the same zip. The retroarch fbneo core loads it
  # directly without a separate neogeo.zip BIOS.
  #
  # FBNeo identifies romsets by *zip filename* — the recognised short
  # name for Metal Slug 1 is `mslug` (see fbneo_libretro.so symbol
  # table). Naming the fetched archive anything else (e.g.
  # `metal-slug.zip`) makes the core report "romset is unknown" at
  # startup. Keep the on-disk filename as `mslug.zip`.
  rom = fetchIpfs {
    cid = "Qmangoooph9xBwKUPEJoTrhEaQFZXtCroL9ikFTKJhrEY6";
    fallbackUrl = "https://archive.org/download/RetroArch_FBN_roms_metalslug/mslug.zip";
    hash = "sha256-+23VQsjIfTxBj2qv/Sk10hqalp7KcqwpmSP8ITGV5Vc=";
    name = "mslug.zip";
  };

  # FBNeo is marked `unfreeRedistributable` in nixpkgs (the source is
  # GPL-licensed, but the license metadata reflects that some arcade
  # ROM dumps the core can run are non-redistributable). The core itself
  # is freely redistributable; override the meta so the build proceeds
  # without an --impure NIXPKGS_ALLOW_UNFREE=1 invocation.
  fbneo = pkgs.libretro.fbneo.overrideAttrs (old: {
    meta = old.meta // {
      license = lib.licenses.gpl2Plus;
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "metal-slug--1";
  src = rom;
  runtime = "retroarch";
  executable = "mslug.zip";

  retroarch = {
    cores = [ fbneo ];

    # Keyboard layout for solo play on a Neo Geo arcade stick layout.
    # Metal Slug uses A (shoot), B (jump), C (grenade), D (unused on MVS
    # but mapped for completeness). Coin/Start are Select/Start. Arrows
    # for the joystick.
    #   arrows     joystick
    #   z          A (shoot)
    #   x          B (jump)
    #   a          C (grenade)
    #   s          D
    #   q / e      L / R (shoulder, unused by Metal Slug but standard)
    #   enter      Start (P1 start)
    #   rshift     Select (P1 coin)
    settings = {
      input_player1_up = "up";
      input_player1_down = "down";
      input_player1_left = "left";
      input_player1_right = "right";
      input_player1_b = "z";
      input_player1_a = "x";
      input_player1_y = "a";
      input_player1_x = "s";
      input_player1_l = "q";
      input_player1_r = "e";
      input_player1_start = "enter";
      input_player1_select = "rshift";
    };
  };

  meta = {
    description = "Metal Slug - Super Vehicle-001 (Nazca/SNK 1996 Neo Geo MVS, via RetroArch / FBNeo)";
    mainProgram = "metal-slug--1";
    platforms = [ "x86_64-linux" ];
  };
}
