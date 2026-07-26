{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Black Version (2010 Game Freak / Nintendo). Nintendo DS card.
  #
  # No-Intro USA dump: "Pokemon - Black Version (USA, Europe) (NDSi Enhanced)"
  # — header title "POKEMON B", game code TWL-IRBO-USA, full 256 MiB card.
  # The Gen-5 Black/White titles are DSi-enhanced, so No-Intro merges the
  # byte-identical USA and Europe carts into one "(USA, Europe) (NDSi
  # Enhanced)" entry; there is no separate plain "(USA)" dump. The source
  # was verified to answer HTTP 206 range requests at staging time.
  #
  # The ROM is pinned on IPFS; `fallbackUrl` is the non-IPFS archive.org
  # direct URL, used only if the gateways are down. The flat outputHash
  # gates correctness either way.
  rom = fetchIpfs {
    cid = "QmaZwVwaooGdanm5hzDnkuUnS5FjPvZzQteeEHtQVRFXkn";
    fallbackUrl = "https://archive.org/download/pokemon-black-version-usa-europe-ndsi-enhanced_202511/Pokemon%20-%20Black%20Version%20%28USA%2C%20Europe%29%20%28NDSi%20Enhanced%29.nds";
    hash = "sha256-uZeRidKZoCMdAciIXA0FS3Bpdv/HVCfKWdhODOFJMDQ=";
    name = "pokemon-black.nds";
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
  name = "pokemon-black";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-black.nds";

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. DeSmuME
    # (`libretro.desmume`) is the alternative if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play. Pokémon Black is mostly button-driven
    # (D-pad + A/B navigate the whole main game); melonDS maps the touch
    # screen to the mouse for the few stylus prompts (C-Gear, menus).
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
    description = "Pokemon Black Version (Game Freak/Nintendo, 2010 Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-black";
    platforms = [ "x86_64-linux" ];
  };
}
