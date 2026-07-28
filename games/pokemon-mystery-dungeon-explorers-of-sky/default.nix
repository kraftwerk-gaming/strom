{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Mystery Dungeon: Explorers of Sky (2009 Chunsoft / Spike
  # Chunsoft, published by Nintendo). Nintendo DS card image.
  #
  # No-Intro "Pokemon Mystery Dungeon - Explorers of Sky (USA).nds" — the
  # base USA dump, full 128 MiB / 134217728-byte cart image. Verified
  # against the cart header before pinning: internal title "POKEDUN SORA",
  # game code C2SE (the USA serial NTR-C2SE-USA), maker code 01
  # (Nintendo), CRC32 22DDE080, SHA-1
  # 5fa96ca8d8dd6405d6cd2bad73ed68bc73a9d152 — i.e. an untrimmed,
  # unpatched No-Intro-named dump, not a trainer/intro hack.
  #
  # The ROM is pinned on IPFS; fallbackUrl is the archive.org direct
  # download of the same item, used only if the gateways are down.
  #
  # No build step: the source serves a bare .nds, so mk-game's default
  # buildScript just copies it into $out under `src.name`.
  rom = fetchIpfs {
    cid = "QmdWRMvrRHcmngeddKYPtC1EdqoMb7tR9PvwUoefoXx9uo";
    fallbackUrl = "https://archive.org/download/pokemon-mystery-dungeon-explorers-of-sky/Pokemon%20Mystery%20Dungeon%20-%20Explorers%20of%20Sky%20%28USA%29.nds";
    hash = "sha256-kRYcsifESj55+ipiIGA4WBX1ZWRzVwYteIfxP0nVkeI=";
    name = "pokemon-mystery-dungeon-explorers-of-sky.nds";
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
  name = "pokemon-mystery-dungeon-explorers-of-sky";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-mystery-dungeon-explorers-of-sky.nds";

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. This matches the other
    # seven DS titles in the repo (pokemon-platinum, -heartgold,
    # -soulsilver, -diamond, -pearl, -black, -ranger): melonDS is the more
    # accurate DS core, DeSmuME (`libretro.desmume`) is only the fallback
    # if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play, identical to the sibling DS packages.
    # Explorers of Sky is fully playable on the hardware buttons — the
    # bottom screen only carries the dungeon map and optional shortcut
    # icons — and melonDS maps the touch screen to the mouse for those.
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
    # Explorers of Sky keeps the dungeon map / team status permanently on
    # the bottom screen, so both screens have to stay legible at once:
    # Top/Bottom stacks them into one 256x384 framebuffer that gamescope
    # then upscales to the 1080p output (~2.8x, letterboxed) — a hybrid
    # layout would shrink the map to an unreadable corner inset, and
    # Left/Right wastes the 16:9 height. `melonds_screen_gap = "0"`
    # removes the emulated hinge gap so the pair scales as large as
    # possible. Mouse touch mode drives the stylus prompts (menu shortcuts,
    # the Wonder Mail keyboard) with the pointer.
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
    description = "Pokémon Mystery Dungeon: Explorers of Sky (2009 Chunsoft, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-mystery-dungeon-explorers-of-sky";
    platforms = [ "x86_64-linux" ];
  };
}
