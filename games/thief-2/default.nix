{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let

  darkBnd = pkgs.writeText "DARK.BND" ''
    auto_equip 1
    bow_zoom 1
    mouse_invert 0
    lookspring 0
    freelook 1
    mouse_sensitivity 3.0
    bind shift +creepon
    bind ctrl +slideon
    bind w +walkfast
    bind s +backfast
    bind a +moveleftfast
    bind d +moverightfast
    bind up +walkfast
    bind down +backfast
    bind left +moveleftfast
    bind right +moverightfast
    bind q +leanleft
    bind e +leanright
    bind r +leanforward
    bind c crouch
    bind space +jumpblock
    bind mouse1 +use_weapon
    bind mouse2 +use_item
    bind mouse3 +block
    bind mouse_axisx mturn
    bind mouse_axisy mlook
    bind f drop_item
    bind tab "cycle_item 1"
    bind tab+shift "cycle_item -1"
    bind ] "cycle_item 1"
    bind [ "cycle_item -1"
    bind backspace clear_item
    bind ` clear_weapon
    bind ~ clear_weapon
    bind 1 "inv_select sword"
    bind 2 "inv_select blackjack"
    bind 3 "inv_select broadhead"
    bind 4 "inv_select water"
    bind 5 "inv_select firearr"
    bind 6 "inv_select EarthArrow"
    bind 7 "inv_select GasArrow"
    bind 8 "inv_select RopeArrow"
    bind 9 "inv_select noise"
    bind F5  quick_save
    bind F9  quick_load
    bind F10 screen_dump
    bind m automap
    bind o objectives
    bind ESC sim_menu
    bind - "gamma_delta 0.025"
    bind + "gamma_delta -0.025"
    bind = "gamma_delta -0.025"
  '';

  installCfg = pkgs.writeText "install.cfg" ''
    install_path .\
    language english
    resname_base .\RES
    load_path .\
    script_module_path .\
    movie_path .\MOVIES
  '';

  camExtCfg = pkgs.writeText "cam_ext.cfg" ''
    use_d3d_display
    force_windowed
    force_32bit
    force_32bit_textures
    skip_starting_checks
    new_mantle
    enhanced_sky 1
    z_far 512
    game_screen_size 1920 1080
    mipmap_mode 2
    lm_mipmap_mode 0
    lm_init_texmem 2
    lm_filter_margin 1
    tex_edge_padding 2
    alpha_test_as_opaque
    d3d_disp_no_rgb10_buf
    wr_render_zcomp
    render_weapon_particles
    dark_zcomp_arm
    ObjTextures16
    MeshTextures16
    framerate_cap 60.0
    phys_freq 60
    min_frame_time 1
    d3d_disp_limit_gpu_frames 1 1
    sfx_device 2
    sfx_channels 32
    sfx_eax 1
    eax_environment 1
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "thief-2";

  src = fetchIpfs {
    cid = "QmdUGBjjNmc1q1uEeS7yHCJFivK1x4zj2szzRmNkyosYhm";
    fallbackUrl = "https://archive.org/download/thief-2-hdmod-1.0_202404/Thief.2.The.Metal.Age.v1.26nd.21946-GOG/ENG/setup_thief_2_-_the_metal_age_1.26_nd_%2821946%29.exe";
    hash = "sha256-X1/n/GkqpVLw+kp3wqCv9DOjLaHLwUv5fqOjHfnrELI=";
    name = "setup_thief2.exe";
    };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" $src

    # innoextract puts game files both in app/ and at top level
    # Move app/ contents if any
    if [ -d "$out/app" ]; then
      cp -rn "$out/app"/* "$out"/ || true
      rm -rf "$out/app"
    fi

    # Clean up non-game dirs
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata"

    # Symlink case variants
    ln -sf MOVIES "$out/movies" || true
    ln -sf RES "$out/res" || true

    # Install our configs
    cp ${darkBnd} "$out/DARK.BND"
    cp ${installCfg} "$out/install.cfg"
    cp ${camExtCfg} "$out/cam_ext.cfg"
  '';

  copyGlobs = [ ];

  runtime = "proton";

  env = {
    STEAM_COMPAT_APP_ID = "211740";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    DXVK_ASYNC = "1";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    PULSE_LATENCY_MSEC = "40";
  };

  runScript = ''
    # DXVK config
    cat > "$GAMEDIR/dxvk.conf" <<DXVKCONF
    d3d9.floatEmulation = strict
    d3d9.invariantPosition = True
    d3d9.memoryTrackTest = True
    DXVKCONF
    export DXVK_CONFIG_FILE="$GAMEDIR/dxvk.conf"
    export DXVK_STATE_CACHE_PATH="$GAMEDIR"

    # OpenAL config
    mkdir -p "$GAMEDIR/openal"
    cat > "$GAMEDIR/openal/alsoft.conf" <<ALCONF
    [general]
    drivers = pulse,alsa
    period-size = 1024
    periods = 4
    stereo-mode = speakers
    [pulse]
    allow-moves = true
    ALCONF
    export ALSOFT_CONF="$GAMEDIR/openal/alsoft.conf"

    gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      "$PROTON_RUN" "$GAMEDIR/Thief2.exe"
  '';

  meta = {
    description = "Thief II: The Metal Age (NewDark engine, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "thief-2";
  };
}
