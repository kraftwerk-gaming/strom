{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Mystery Dungeon: Blue Rescue Team (2006 Chunsoft, published by
  # Nintendo). Nintendo DS card image, the USA release.
  #
  # No-Intro "Pokemon Mystery Dungeon - Blue Rescue Team (USA, Australia).nds"
  # — an untrimmed 32 MiB / 33554432-byte cart image. Verified against the
  # cart header and the No-Intro DAT entry before pinning: internal title
  # "POKE DUNGEON", game code APHE (the USA serial NTR-APHE-USA), maker code
  # 01 (Nintendo), CRC32 B6C4143E, MD5 61373235da72064e8c058fae3c646916,
  # SHA-1 503edef4fe6088bca00616efcac3b13da90cd105 — i.e. the verified USA
  # dump, not a trainer/intro hack or a trimmed image.
  #
  # The archive.org item serves the ROM zipped under its Advanscene release
  # name ("0566 - ... (U)(Legacy)"), so the FOD pins the zip and the build
  # extracts the single member to a raw .nds named after the slug.
  #
  # The ROM is pinned on IPFS; fallbackUrl is the archive.org direct
  # download of the same zip, used only if the gateways are down.
  romArchive = fetchIpfs {
    cid = "QmdSFv99fidedvW31n6fVyiz2RF1r3H3oLGjunfWcERC4x";
    fallbackUrl = "https://archive.org/download/pokemon-mystery-dungeon-blue-rescue-team/Pokemon%20Mystery%20Dungeon%20-%20Blue%20Rescue%20Team%20%28U%29%28Legacy%29.zip";
    hash = "sha256-a0T+e+aZ7ckSIGfHYHcOm+WisUHZ1v1CRseGq799Ga4=";
    name = "pokemon-mystery-dungeon-blue-rescue-team.zip";
  };

  # The nixpkgs melonDS core ships its ARM-JIT dispatcher assembled from
  # a hand-written object that lacks a `.note.GNU-stack` section, so the
  # linker stamps the whole .so with an executable stack (PT_GNU_STACK
  # flags RWE). RetroArch dlopen()s the core, glibc then tries to remap
  # the main thread stack PROT_EXEC, and on a hardened kernel that mmap
  # is refused:
  #   melonds_libretro.so: cannot enable executable stack as shared
  #   object requires: Invalid argument
  # The core never loads, RetroArch falls back to its menu, and the game
  # "does nothing". The exec-stack request is spurious — the JIT runs
  # from mmap(PROT_EXEC) heap pages, never the stack — so clearing the
  # flag with `execstack -c` is safe and lets the core load.
  melonds = pkgs.libretro.melonds.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.prelink ];
    postFixup = (old.postFixup or "") + ''
      execstack -c "$out"/lib/retroarch/cores/melonds_libretro.so
    '';
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-mystery-dungeon-blue-rescue-team";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-mystery-dungeon-blue-rescue-team.nds";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" '0566 - Pokemon Mystery Dungeon - Blue Rescue Team (U)(Legacy).nds' \
      > $out/pokemon-mystery-dungeon-blue-rescue-team.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. This matches every other DS
    # title in the repo (pokemon-platinum, -heartgold, -soulsilver,
    # -diamond, -pearl, -black, -ranger, and the Explorers of Sky sibling):
    # melonDS is the more accurate DS core, DeSmuME (`libretro.desmume`) is
    # only the fallback if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play, identical to the sibling DS packages.
    # Blue Rescue Team is fully playable on the hardware buttons — the
    # bottom screen carries the dungeon map and the optional touch command
    # bar — and melonDS maps the touch screen to the mouse for the stylus
    # prompts (the Wonder Mail / friend-rescue keyboards).
    #   arrows     D-pad
    #   z          B
    #   x          A
    #   a          Y
    #   s          X
    #   q / e      L / R
    #   enter      Start
    #   rshift     Select
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

    # Dual-screen layout, pinned explicitly rather than inherited from the
    # core default so a core update can't silently reshape the couch view.
    # Blue Rescue Team keeps the dungeon map and team status permanently on
    # the bottom screen, so both screens have to stay legible at once:
    # Top/Bottom stacks them into one 256x384 framebuffer that gamescope
    # then upscales to the output, where a hybrid layout would shrink the
    # map to an unreadable corner inset and Left/Right wastes the 16:9
    # height. `melonds_screen_gap = "0"` removes the emulated hinge gap so
    # the pair scales as large as possible. Mouse touch mode drives the
    # stylus prompts with the pointer. Same block as the Explorers of Sky
    # sibling — the DS layout convention for this tree.
    coreOptions = {
      melonds_screen_layout = "Top/Bottom";
      melonds_screen_gap = "0";
      melonds_touch_mode = "Mouse";
      melonds_threaded_renderer = "enabled";
    };
  };

  meta = {
    description = "Pokémon Mystery Dungeon: Blue Rescue Team (2006 Chunsoft, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-mystery-dungeon-blue-rescue-team";
    platforms = [ "x86_64-linux" ];
  };
}
