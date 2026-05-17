{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "system-shock-2";

  src = fetchIpfs {
    cid = "QmYDAEVndJxfs5qwGfyantkhvimYKyEdA9ZYq3XXJoCYb4";
    fallbackUrl = "https://archive.org/download/system_shock_2_gog/setup_system_shocktm_2_2.48_%2831077%29.exe";
    hash = "sha256-RZdW/Ag1VYQ/J4CDYQc9nLOn0owx3SL6nEttxtobe3s=";
    name = "system-shock-2.exe";
  };

  nativeBuildInputs = [ innoextract ];

  # GOG installer is an Inno Setup wrapper around the NewDark v2.48 build.
  # Game files extract to top level (no app/ subdir). Strip GOG redist and
  # commonappdata cruft.
  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" $src

    if [ -d "$out/app" ]; then
      cp -rn "$out/app"/* "$out"/ || true
      rm -rf "$out/app"
    fi

    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata"

    # Symlink case variants for the Dark Engine resname_base / movie_path
    # references (install.cfg uses .\Data, but mission files reference
    # MOVIES/RES/etc. by other cases on case-sensitive filesystems).
    ln -sf Data "$out/data" || true

    # Default to 1920x1080 fullscreen. NewDark's cam_ext.cfg already enables
    # the D3D9 display path (`use_d3d_display`) and fullscreen double
    # buffering (`single_display_mode 2`); only the resolution value in
    # CAM.CFG (`game_screen_size`) still defaults to GOG's shipping 800x600.
    # The fuse-overlayfs upper layer captures any in-game Options change, so
    # this is purely the default on a fresh ~/.strom/system-shock-2/.
    # CAM.CFG ships with CRLF line endings; the regex preserves the trailing
    # \r so the rest of the file stays byte-identical to the shipped layout.
    chmod u+w "$out/CAM.CFG"
    sed -i -E 's/^(game_screen_size)[[:space:]]+[0-9]+[[:space:]]+[0-9]+(\r?)$/\1 1920 1080\2/' "$out/CAM.CFG"
    grep -q '^game_screen_size 1920 1080' "$out/CAM.CFG"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # save_*/ + current/ + cam.cfg + user.bnd next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "SS2.exe";

  env = {
    STEAM_COMPAT_APP_ID = "238210";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    PULSE_LATENCY_MSEC = "40";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "System Shock 2 (NewDark engine, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "system-shock-2";
  };
}
