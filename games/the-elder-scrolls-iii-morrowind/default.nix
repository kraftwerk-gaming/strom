{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unar,
  openmw,
}:

let
  # The Elder Scrolls III: Morrowind GOTY (Bethesda 2002 + Tribunal 2002
  # + Bloodmoon 2003 expansions), GOG re-release v2.0.0.7. The archive.org
  # item ships a single .rar containing the GOG installer EXE
  # (setup_tes_morrowind_goty_2.0.0.7.exe). The EXE is Inno Setup 5.5.0,
  # so unar -> innoextract reveals `app/Data Files/` which holds the
  # original Bethesda ESM/BSA tree (Morrowind.esm, Tribunal.esm,
  # Bloodmoon.esm + matching BSAs + meshes/textures/sound).
  #
  # Engine: OpenMW (open-source reimplementation, nixpkgs `openmw`).
  # OpenMW only needs the data tree; the original Morrowind.exe is
  # discarded. This avoids the broken Proton path entirely (pink DDS
  # textures, pink cursor, broken mouse look) and matches the
  # daggerfall-unity pattern: ship the assets, run a native open-source
  # engine over them.
  src = fetchIpfs {
    cid = "QmcSsqF5WPsx5eg8RbXA4P7EmyLaJDiaSqeboJtfTa8y81";
    fallbackUrl = "https://archive.org/download/the-elder-scrolls-iii-morrowind-goty/The%20Elder%20Scrolls%20III%20Morrowind%20GOTY.rar";
    hash = "sha256-TY9odYrVyqXN4m9lG4311iVJBhG7eahSNmQnVvY6BnE=";
    name = "morrowind-goty-gog.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-elder-scrolls-iii-morrowind";

  inherit src;

  nativeBuildInputs = [
    innoextract
    unar
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/rar" "$TMPDIR/inno"
    # Layer 1: the archive.org rar -> directory with the GOG installer EXE.
    unar -q -o "$TMPDIR/rar" "$src"
    setup_exe=$(find "$TMPDIR/rar" -iname 'setup_tes_morrowind_goty*.exe' | head -1)
    # Layer 2: GOG installer is Inno Setup; innoextract pulls out app/.
    innoextract -s -d "$TMPDIR/inno" "$setup_exe"
    # Only the Data Files subtree is needed by OpenMW. Drop the original
    # Bethesda binaries, GOG launcher metadata, manual PDFs, etc.
    cp -r "$TMPDIR/inno/app/Data Files" "$out/Data Files"
    chmod -R u+w "$out"
  '';

  runtime = "native";

  # OpenMW is a properly RPATH'd nix derivation, so the bare `native`
  # runtime is enough — no FHS shim needed. The strom native runtime
  # binds $STROM_GAMEDIR over $HOME, so XDG paths
  # (~/.config/openmw/openmw.cfg, ~/.local/share/openmw/saves/) land
  # under ~/.strom/the-elder-scrolls-iii-morrowind/ on the host.
  #
  # runScript pre-cooks the minimal user openmw.cfg every launch:
  #   - data="..."        — asset tree root
  #   - fallback-archive= — register each Bethesda BSA so the engine can
  #                         resolve menu textures, meshes, fonts, etc.
  #                         (without these, the title screen logs
  #                         `Failed to open image: textures/menu_morrowind.dds`
  #                         and a host of similar misses)
  #   - content=          — active masters/plugins
  # The rest of the cfg surface (resolution, controls, the giant
  # `fallback=<lighting/inventory/...>` block) is supplied by openmw's
  # global /etc/openmw/openmw.cfg and the in-game options menu — OpenMW
  # merges the two. BSA and content lines are gated on file existence
  # so a non-GOTY data drop (no Tribunal / Bloodmoon) still boots into
  # base Morrowind.
  runScript = ''
    mkdir -p "$HOME/.config/openmw"
    DF="$GAMEDIR/Data Files"
    {
      echo "data=\"$DF\""
      [ -f "$DF/Morrowind.bsa" ] && echo "fallback-archive=Morrowind.bsa"
      [ -f "$DF/Tribunal.bsa" ]  && echo "fallback-archive=Tribunal.bsa"
      [ -f "$DF/Bloodmoon.bsa" ] && echo "fallback-archive=Bloodmoon.bsa"
      echo "content=Morrowind.esm"
      [ -f "$DF/Tribunal.esm" ]  && echo "content=Tribunal.esm"
      [ -f "$DF/Bloodmoon.esm" ] && echo "content=Bloodmoon.esm"
    } > "$HOME/.config/openmw/openmw.cfg"

    # First-run only: seed settings.cfg with [Video] 1920x1080 fullscreen
    # so OpenMW doesn't default to its built-in 800x600 window on the
    # very first launch. Subsequent runs leave settings.cfg alone so the
    # user's in-game Options changes (controls, audio, post-processing,
    # …) survive rebuilds.
    if [ ! -f "$HOME/.config/openmw/settings.cfg" ]; then
      cat > "$HOME/.config/openmw/settings.cfg" <<'CFG'
    [Video]
    resolution x = 1920
    resolution y = 1080
    window mode = 0
    CFG
    fi
    exec ${lib.getExe' openmw "openmw"} "$@"
  '';

  # mk-game's native runtime wraps the inner command in gamescope
  # automatically (see lib/mk-game.nix `runtime == "native"` branch);
  # no need to spawn gamescope from runScript. 1080p60 to match the
  # other native-runtime games.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Force gamescope to grab the cursor for relative-motion (FPS-style
      # mouse look). Without this, OpenMW's SDL_SetRelativeMouseMode call
      # only takes effect in menus; in-game mouse look stays stuck because
      # Xwayland keeps delivering absolute positions under gamescope's
      # nested compositor.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "The Elder Scrolls III: Morrowind GOTY (Bethesda 2002 GOG data, via OpenMW)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-elder-scrolls-iii-morrowind";
  };
}
