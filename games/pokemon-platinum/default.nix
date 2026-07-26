{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Platinum Version (2008 Game Freak / Nintendo). Nintendo DS card.
  # No-Intro "Pokemon - Platinum Version (USA).nds" — the base USA dump
  # (internal game code CPUE, full 128 MiB / 134217728-byte cart image).
  # The ROM is pinned on IPFS; fallbackUrl is the archive.org direct
  # download, used only if the gateways are down.
  rom = fetchIpfs {
    cid = "QmTk1mAWQf2ABaPZH5e8C8hVsmxGdJTQtUJqSEjdwpsvc6";
    fallbackUrl = "https://archive.org/download/pokemon-platinum-version-usa_202406/Pokemon%20-%20Platinum%20Version%20%28USA%29.nds";
    hash = "sha256-7eYikqp/cBT/J9Qgl+dpdTOAUxc5iJwpuWi2e4D4Bng=";
    name = "pokemon-platinum.nds";
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
  name = "pokemon-platinum";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-platinum.nds";

  # Source serves a bare .nds (not zipped), so just place it in $out.
  buildScript = ''
    mkdir -p $out
    cp "$src" $out/pokemon-platinum.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. DeSmuME
    # (`libretro.desmume`) is the alternative if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play. Pokémon Platinum is largely a
    # D-pad + button game; melonDS maps the touch screen to the mouse for
    # the few stylus prompts.
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
    description = "Pokémon Platinum Version (2008 Game Freak, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-platinum";
    platforms = [ "x86_64-linux" ];
  };
}
