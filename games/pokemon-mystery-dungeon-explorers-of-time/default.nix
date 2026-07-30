{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Mystery Dungeon: Explorers of Time (2007 Chunsoft, published by
  # Nintendo). Nintendo DS card image, the USA release.
  #
  # Explorers of Time and Explorers of Darkness are the paired release of
  # this generation (Explorers of Sky, already in the tree, is the 2009
  # expanded re-release). Unlike the Rescue Team pair, which split across
  # two consoles (Red = GBA, Blue = DS), both Explorers halves are DS carts
  # with their own game code, so this package and the Darkness sibling are
  # structurally identical and differ only in the ROM they pin.
  #
  # No-Intro "Pokemon Mystery Dungeon - Explorers of Time (USA).nds" — an
  # untrimmed 64 MiB / 67108864-byte cart image. Verified against the cart
  # header and the No-Intro DAT before pinning: internal title
  # "POKEDUN TOKI", game code YFTE (the USA serial NTR-YFTE-USA), maker
  # code 01 (Nintendo), cart-capacity byte 0x09 (128 KiB << 9 = 64 MiB,
  # i.e. the header agrees with the file size), CRC32 D4F9C8E7, MD5
  # 0dfbbcf065e017c95750dd3a532523c4, SHA-1
  # 19763f0065a6b32f7b5c2a936404a65eafb0238a. Those four hashes are an
  # exact match for the "Pokemon Mystery Dungeon - Explorers of Time (USA)"
  # entry in libretro-database's No-Intro `Nintendo - Nintendo DS.dat`
  # (serial YFTE, size 67108864) — so this is the verified USA dump, not a
  # trimmed image or a trainer/intro hack.
  #
  # Provenance of the bytes: archive.org item `DS-No-Intro-2024-Myrient`,
  # a Myrient mirror of the No-Intro DS set that serves one TorrentZip per
  # game (31687785-byte zip, SHA-1
  # b5395fa5252cf7cc3261755d12973da21e3e183b, matching the item's own
  # published checksum). The identical zip — same SHA-1, so byte-for-byte
  # the same TorrentZip — is also served by the unrelated item
  # `2024-nintendo-ds-hearto-1g1r-collection`, which is a second
  # independent source for the same archive should the first item go away.
  #
  # The archive serves the ROM zipped, so the FOD pins the zip and the
  # build extracts the single member to a raw .nds named after the slug —
  # same shape as the Blue Rescue Team sibling.
  #
  # The ROM is pinned on IPFS; fallbackUrl is the archive.org direct
  # download of the same zip, used only if the gateways are down.
  romArchive = fetchIpfs {
    cid = "QmWiE474VJZKhGLQ5d472PND5orypbPHokfBj752WjfB5D";
    fallbackUrl = "https://archive.org/download/DS-No-Intro-2024-Myrient/Pokemon%20Mystery%20Dungeon%20-%20Explorers%20of%20Time%20%28USA%29.zip";
    hash = "sha256-WXiny4p6vjTTQp9ZQvP7Dcid1pmL1XT/yxZLUFgmP2g=";
    name = "pokemon-mystery-dungeon-explorers-of-time.zip";
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
  name = "pokemon-mystery-dungeon-explorers-of-time";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-mystery-dungeon-explorers-of-time.nds";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon Mystery Dungeon - Explorers of Time (USA).nds' \
      > $out/pokemon-mystery-dungeon-explorers-of-time.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. This matches every other DS
    # title in the repo (pokemon-platinum, -heartgold, -soulsilver,
    # -diamond, -pearl, -black, -ranger, and the Explorers of Sky and Blue
    # Rescue Team siblings): melonDS is the more accurate DS core, DeSmuME
    # (`libretro.desmume`) is only the fallback if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play, identical to the sibling DS packages.
    # Explorers of Time is fully playable on the hardware buttons — the
    # bottom screen only carries the dungeon map and the optional shortcut
    # icons — and melonDS maps the touch screen to the mouse for the stylus
    # prompts (the Wonder Mail password keyboard).
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
    # Explorers of Time keeps the dungeon map / team status permanently on
    # the bottom screen, so both screens have to stay legible at once:
    # Top/Bottom stacks them into one 256x384 framebuffer that gamescope
    # then upscales to the 1080p output (~2.8x, letterboxed) — a hybrid
    # layout would shrink the map to an unreadable corner inset, and
    # Left/Right wastes the 16:9 height. `melonds_screen_gap = "0"`
    # removes the emulated hinge gap so the pair scales as large as
    # possible. Mouse touch mode drives the stylus prompts (menu shortcuts,
    # the Wonder Mail keyboard) with the pointer. Same block as the
    # Explorers of Sky sibling — the DS layout convention for this tree.
    coreOptions = {
      melonds_screen_layout = "Top/Bottom";
      melonds_screen_gap = "0";
      melonds_touch_mode = "Mouse";
      melonds_threaded_renderer = "enabled";
    };
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Pokémon Mystery Dungeon: Explorers of Time (2007 Chunsoft, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-mystery-dungeon-explorers-of-time";
    platforms = [ "x86_64-linux" ];
  };
}
