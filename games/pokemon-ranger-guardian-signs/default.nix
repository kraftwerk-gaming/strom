{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Ranger: Guardian Signs (2010 Creatures Inc. / Nintendo). Nintendo DS
  # card, third and last entry in the Ranger series. USA release: 134217728
  # bytes (128 MiB, untrimmed), internal title "POKE RANGER3", game code B3RE
  # (trailing E = USA), maker code 01 (Nintendo), sha1
  # 4a59c624ec69c5fc4eb76b7653af47047e106567. Region confirmed from the ROM
  # header game code, not the archive filename. The archive.org item stores the
  # dump as a plain file inside a same-named directory (not a zip), so it is
  # fetched raw and needs no unpack step — same as the other six DS titles here.
  #
  # STYLUS-DRIVEN TITLE — NEEDS melonds_touch_mode = "Joystick".
  # The Ranger games' core mechanic is the Capture Styler: you draw loops
  # around a wild Pokémon on the touch screen, continuously, under time
  # pressure. Every capture, every Poké Assist and every Ranger Sign is a
  # touch-screen gesture; the hardware buttons only drive menus. Even the
  # title screen is a touch gate — it renders "Please tap the Touch Screen!"
  # and nothing else advances it.
  #
  # So the tree-wide DS default of `melonds_touch_mode = "Mouse"` makes this
  # game literally unstartable on a gamepad-only couch setup: Mouse mode
  # feeds the touch position from RETRO_DEVICE_MOUSE deltas and the touch
  # press from RETRO_DEVICE_ID_MOUSE_LEFT, neither of which a pad produces.
  # "Joystick" mode is melonDS's built-in answer. From the core's own source
  # (libretro.melonds.src, src/libretro/input.cpp, update_input()):
  #   case TouchMode::Joystick:
  #      int16_t joystick_x = input_state_cb(0, RETRO_DEVICE_ANALOG,
  #         RETRO_DEVICE_INDEX_ANALOG_RIGHT, RETRO_DEVICE_ID_ANALOG_X) / 2048;
  #      int16_t joystick_y = ... RETRO_DEVICE_ID_ANALOG_Y) / 2048;
  #      state->touch_x = Clamp(state->touch_x + joystick_x, 0, VIDEO_WIDTH - 1);
  #      state->touch_y = Clamp(state->touch_y + joystick_y, 0, VIDEO_HEIGHT - 1);
  #      state->touching = !!input_state_cb(0, RETRO_DEVICE_JOYPAD, 0,
  #         RETRO_DEVICE_ID_JOYPAD_R3);
  # So: RIGHT stick = stylus motion, R3 (right-stick click) = stylus down.
  # Note the motion is RELATIVE and accumulates into a clamped position, so
  # the stick is a cursor velocity, not a position — a tap only lands where
  # the cursor currently happens to be. `cursor_enabled()` returns true for
  # Mouse and Joystick, so the core also draws a small visible cursor.
  #
  # This deviates from the three other DS core options, which are the
  # batch-wide defaults. It is deliberate and title-specific: only a
  # stylus-driven game needs it, and the alternative is shipping a game
  # that cannot leave its title screen. Hoisting a shared
  # `touchMode`-style option into lib/retroarch.nix (default Mouse,
  # stylus titles opting into Joystick) is the right long-term fix and
  # wants all 9 DS titles re-tested in one go — see issue a63db51
  # ("balatro is missing touch support"), the same underlying gap.
  #
  # VERIFIED (headless gamescope, single virtual uinput Xbox 360 pad
  # enumerated as player 1, nothing else on /dev/input): the whole opening
  # was driven from the pad alone — R3 tap cleared the "Please tap the
  # Touch Screen!" attract gate, right stick moved the cursor onto
  # "New Game", R3 selected it, then stick+R3 answered the "Are you a boy?"
  # character select and its YES/NO confirm, reaching the in-game intro
  # ("The Oblivia Region / High in the Sky", then the Pokémon Pincher
  # cutscene). So this title IS pad-playable for menus and discrete taps.
  #
  # The one gotcha, which is why an earlier attempt read as a failure:
  # because motion is relative and Clamp()ed at the screen edge, deflecting
  # the stick toward an edge parks the cursor there, and taps then land on
  # empty screen. Steer onto the target first; a long hard deflection into
  # a corner is a reliable way to re-zero the cursor.
  #
  # Still genuinely awkward, and honestly so: the Capture Styler wants fast
  # continuous loops drawn around a moving target, which a velocity-based
  # stick cursor makes clumsy even though it is now possible. Menus are
  # fine; captures will feel bad compared to a mouse.
  rom = fetchIpfs {
    cid = "Qmepet2CFBi6Swe6XfQfHSpvNHVyu7hWCc1LeewJueKxDS";
    fallbackUrl = "https://archive.org/download/scxnds_202207/Pokemon_Ranger_Guardian_Signs_USA.nds/5253%20-%20Pokemon_Ranger_Guardian_Signs_USA.nds";
    hash = "sha256-iql++w5wctTW2MpAA/lXjYeK6jNkp7fzfXSv4TceR+c=";
    name = "pokemon-ranger-guardian-signs.nds";
  };

  # The nixpkgs melonDS core ships its ARM-JIT dispatcher assembled from a
  # hand-written object that lacks a `.note.GNU-stack` section, so the linker
  # stamps the whole .so with an executable stack (PT_GNU_STACK flags RWE).
  # RetroArch dlopen()s the core, glibc then tries to remap the main thread
  # stack PROT_EXEC, and on a hardened kernel that mmap is refused:
  #   melonds_libretro.so: cannot enable executable stack as shared
  #   object requires: Invalid argument
  # The core never loads, RetroArch falls back to its menu, and the game
  # "does nothing". The exec-stack request is spurious — the JIT runs from
  # mmap(PROT_EXEC) heap pages, never the stack — so clearing the flag with
  # `execstack -c` is safe and lets the core load.
  melonds = pkgs.libretro.melonds.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.prelink ];
    postFixup = (old.postFixup or "") + ''
      execstack -c "$out"/lib/retroarch/cores/melonds_libretro.so
    '';
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-ranger-guardian-signs";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-ranger-guardian-signs.nds";

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/, so
    # retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above.
    cores = [ melonds ];

    # Layout: the batch-wide DS defaults — both screens stacked and touching,
    # so the always-on bottom-screen Styler/map stays full width and legible
    # (a hybrid layout shrinks it to a corner inset).
    #
    # Touch mode is chosen by the input device actually attached, because
    # melonDS's two modes are mutually exclusive and this title is
    # stylus-driven end to end (its title screen is a touch gate):
    #   no pad -> "Mouse": the pointer drives the stylus, which is what a
    #             desktop user has. Shipping Joystick unconditionally left
    #             the DS lower screen dead under a mouse.
    #   pad    -> "Joystick": right stick moves the stylus, R3 taps, and the
    #             core draws a visible cursor, which is the only way to play
    #             this on a pad-only couch setup.
    # lib/retroarch.nix merges coreOptionsWithPad over coreOptions when
    # sdl2-jstest finds a gamepad at launch.
    coreOptions = {
      melonds_screen_layout = "Top/Bottom";
      melonds_screen_gap = "0";
      melonds_touch_mode = "Mouse";
      melonds_threaded_renderer = "enabled";
    };

    coreOptionsWithPad = {
      melonds_touch_mode = "Joystick";
    };

    # Keyboard layout for solo play. Guardian Signs only uses the hardware
    # buttons for menus and dialogue; all capture gameplay is the stylus.
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
    description = "Pokémon Ranger: Guardian Signs (2010 Creatures Inc., Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-ranger-guardian-signs";
    platforms = [ "x86_64-linux" ];
  };
}
