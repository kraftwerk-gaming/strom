{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Mystery Dungeon: Explorers of Darkness (2007 Chunsoft, published
  # by Nintendo; NA release April 2008). Nintendo DS card image, the USA
  # release.
  #
  # This is the *Darkness* half of the paired release: Explorers of Time and
  # Explorers of Darkness are the same game shipped on two carts with a
  # handful of version-exclusive recruits and dungeons, so the two packages
  # in this tree are deliberate near-twins that differ only in the asset
  # (game code YFYE here, POKEDUN YAMI internally — "yami" is darkness).
  # Explorers of Sky is the later expanded cut and has its own package.
  #
  # No-Intro "Pokemon Mystery Dungeon - Explorers of Darkness (USA).nds" —
  # an untrimmed 64 MiB / 67108864-byte cart image. Verified against the
  # cart header and the No-Intro DAT entry before pinning: internal title
  # "POKEDUN YAMI", game code YFYE (the USA serial NTR-YFYE-USA), maker code
  # 01 (Nintendo), CRC32 F2EE539E, MD5 caf4b6ec51576218225d93bd6005030c,
  # SHA-1 ee69bb80ff278851fb5074a118039bd4a86f01e0 — i.e. the verified USA
  # dump, not a trainer/intro hack.
  #
  # Note the cart header's used-ROM-size field reads 64898995 bytes, which
  # is exactly the size of the trimmed copies of this ROM that circulate
  # (e.g. the "DS/Explorers of Darkness.nds" in archive.org's awkwards-roms).
  # Those are the same data with the 0xFF pad cut off; this one is the full
  # untrimmed image the DAT describes, so it hashes as the No-Intro entry.
  #
  # The archive.org item serves the ROM as a No-Intro torrentzip, so the FOD
  # pins the zip and the build extracts the single member to a raw .nds
  # named after the slug. The byte-identical zip (same SHA-1
  # 101a63825d3e1cbf6efdfde10429af4e24f291b5) is served by two independent
  # items — DS-No-Intro-2024-Myrient and
  # 2024-nintendo-ds-hearto-1g1r-collection — which is what makes the
  # fallback worth having.
  #
  # The zip is pinned on IPFS; fallbackUrl is the archive.org direct
  # download of the same zip, used only if the gateways are down.
  romArchive = fetchIpfs {
    cid = "QmP5svHaaV2Laewp1Gt61SKyU7ioAe94LKWL6V7kgspf4p";
    fallbackUrl = "https://archive.org/download/DS-No-Intro-2024-Myrient/Pokemon%20Mystery%20Dungeon%20-%20Explorers%20of%20Darkness%20%28USA%29.zip";
    hash = "sha256-VW72IOSeVqwnBiZR2VRiL+Y8ymC1uZZBJRLk5ot+d5U=";
    name = "pokemon-mystery-dungeon-explorers-of-darkness.zip";
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
  name = "pokemon-mystery-dungeon-explorers-of-darkness";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-mystery-dungeon-explorers-of-darkness.nds";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon Mystery Dungeon - Explorers of Darkness (USA).nds' \
      > $out/pokemon-mystery-dungeon-explorers-of-darkness.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. This matches every other DS
    # title in the repo (pokemon-platinum, -heartgold, -soulsilver,
    # -diamond, -pearl, -black, -ranger, and the Mystery Dungeon siblings):
    # melonDS is the more accurate DS core, DeSmuME (`libretro.desmume`) is
    # only the fallback if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play, identical to the sibling DS packages.
    # Explorers of Darkness is fully playable on the hardware buttons — the
    # bottom screen only carries the dungeon map and optional shortcut
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
    # Explorers of Darkness keeps the dungeon map / team status permanently
    # on the bottom screen, so both screens have to stay legible at once:
    # Top/Bottom stacks them into one 256x384 framebuffer that gamescope
    # then upscales to the 1080p output (~2.8x, letterboxed) — a hybrid
    # layout would shrink the map to an unreadable corner inset, and
    # Left/Right wastes the 16:9 height. `melonds_screen_gap = "0"` removes
    # the emulated hinge gap so the pair scales as large as possible. Mouse
    # touch mode drives the stylus prompts with the pointer. Same block as
    # the Explorers of Sky sibling — the DS layout convention for this tree.
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
    description = "Pokémon Mystery Dungeon: Explorers of Darkness (2007 Chunsoft, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-mystery-dungeon-explorers-of-darkness";
    platforms = [ "x86_64-linux" ];
  };
}
