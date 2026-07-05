{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
}:

let
  # S.T.A.L.K.E.R. G.A.M.M.A. v9.4.0 hotfix (GOG build 59216361630365095,
  # 2025-12-03) - Grok's 400+-mod hardcore overhaul of Anomaly, standalone
  # (no original games needed). GOG product 1595922314, free, though the
  # entitlement requires owning Call of Pripyat or STALKER 2.
  #
  # WHY A TAR OF THE GALAXY DEPOT AND NOT THE OFFLINE INSTALLER. This recipe
  # used to fetch GOG's 20-part Inno installer
  # (setup_stalker_gamma_9.4.0_hotfix_86994.exe + 19 .bin slices) and
  # innoextract it. Those bytes are GONE and cannot be re-acquired by anyone:
  # GOG only ever serves the CURRENT offline installer, and it rolled forward
  # to 9.5.0 RC2 on 2026-06-02, so build 86994's installer is no longer
  # offered even to a logged-in, entitled account. The old CIDs had zero
  # announced providers on the DHT (delegated routing returned an empty
  # provider set for every one), every fallbackUrl was empty, archive.org has
  # no copy, and the mirrors that claim to carry it are Cloudflare- or
  # captcha-gated. A package in that state is unbuildable for everyone
  # including its author.
  #
  # What IS still available is the Galaxy depot for the same build: GOG keeps
  # older builds installable through the content-system API long after their
  # offline installer is withdrawn. `lgogdownloader --galaxy-show-builds
  # 1595922314` still lists 9.4.0 hotfix as build index 1, and installing it
  # yields byte-identical game content to what the installer produced -- the
  # same "S.T.A.L.K.E.R. GAMMA/{Anomaly,GAMMA,__redist}" tree innoextract
  # unpacked, which is why the merge below is unchanged.
  #
  # That tree is 132 GB, so it is pinned as a tar split into nine ~15 GiB
  # parts rather than one object: the uploader takes a path, and no machine
  # here has 132 GB free to stage a single file. buildScript cats the parts
  # back together on stdin, so the tar is never materialised whole either.
  # Splitting also mirrors what the Inno installer did, for the same reason.
  #
  # fallbackUrl is empty and cannot be otherwise: GOG's depot endpoints are
  # account-gated, so there is no anonymous URL to name. The provenance that
  # replaces it is the build id above -- anyone entitled can reproduce these
  # bytes with `lgogdownloader --galaxy-install 1595922314/1`.
  srcTar0 = fetchIpfs {
    cid = "QmPf36pvP1sqsPmSKRCmUeEZDTrpMeXVyDEkKcxws3eqnE";
    fallbackUrl = "";
    hash = "sha256-Tkyr4HOT/aRGE7sLgYLmFXnlubKLIbk0c4avheMfr0g=";
    name = "stalker-gamma-9.4.0-hotfix.tar.00";
  };
  srcTar1 = fetchIpfs {
    cid = "QmRF8VBNzadUXePAN5D1Gw54NLdsg47LsVTK6prcRkLXde";
    fallbackUrl = "";
    hash = "sha256-+RCcdse+4BMkve6yWtgEkb4So0/Ce4TjL+lfdD95EDw=";
    name = "stalker-gamma-9.4.0-hotfix.tar.01";
  };
  srcTar2 = fetchIpfs {
    cid = "QmTTLYgWiXET6hBb5htSG48w3SgtyZyNueDdQbYvpsB2uN";
    fallbackUrl = "";
    hash = "sha256-GgMm2SM3GPdlb4C4qcNTSBjTPOwkDoF9aqwjo/DlXe8=";
    name = "stalker-gamma-9.4.0-hotfix.tar.02";
  };
  srcTar3 = fetchIpfs {
    cid = "Qmccz5Y6hfqPqu6ewvQE2Scac3xxgdMK6nZez76UgnhAZX";
    fallbackUrl = "";
    hash = "sha256-21BwG5SeKkP1VHA1rtwe/xza+/UeFk3nIk5dJkc8cFo=";
    name = "stalker-gamma-9.4.0-hotfix.tar.03";
  };
  srcTar4 = fetchIpfs {
    cid = "QmVFiSosJG4HguGBGGXuG8rhxD9FbHsQmcoEbRELW5Yx1m";
    fallbackUrl = "";
    hash = "sha256-zjHStik/FWv0vtbVeZZqGKkB2twCeNDJoMYSxI5HbDA=";
    name = "stalker-gamma-9.4.0-hotfix.tar.04";
  };
  srcTar5 = fetchIpfs {
    cid = "QmURxS9g68GhTXw3NJpBAdrTzL1KFWGCtok2qMqMntpNLw";
    fallbackUrl = "";
    hash = "sha256-aPcxdu4Cou6ljfLzn2nLIpeS7xi5fO1Ad66AU4Q0qRc=";
    name = "stalker-gamma-9.4.0-hotfix.tar.05";
  };
  srcTar6 = fetchIpfs {
    cid = "QmdcjKFiokWpYeB4PC4uuzBbQG1Ab2DjbT4b2ks1KZ6cnH";
    fallbackUrl = "";
    hash = "sha256-JIpVuYjX/MvSl4COYx+0kj/yY3rAQcdtdMLAnJKBIKA=";
    name = "stalker-gamma-9.4.0-hotfix.tar.06";
  };
  srcTar7 = fetchIpfs {
    cid = "QmfGfCrqLpi4DX17nyrBMbfS8G9CnfCfdZ5YZJDSsmW5XW";
    fallbackUrl = "";
    hash = "sha256-NOYXInHsbAPjxMElcn47UXAXfimdWetNjvVhIgDqbdY=";
    name = "stalker-gamma-9.4.0-hotfix.tar.07";
  };
  srcTar8 = fetchIpfs {
    cid = "QmZhunL7eh8oy2oDYdNm5h9VhVoCMz3qni2C6JYxc99xCu";
    fallbackUrl = "";
    hash = "sha256-gJ2v9Bmxk76tLLRK6+aEP4VDaLzXVFhcmYBERB3hHdk=";
    name = "stalker-gamma-9.4.0-hotfix.tar.08";
  };
  srcTarParts = [
    srcTar0
    srcTar1
    srcTar2
    srcTar3
    srcTar4
    srcTar5
    srcTar6
    srcTar7
    srcTar8
  ];

  # Microsoft DirectX 9.0c End-User Runtime (June 2010). GAMMA's
  # "Modded EXEs" engine binaries keep Anomaly's import set:
  # d3dx9_43.dll + d3dx11_43.dll + d3dcompiler_43.dll (64-bit). Wine's
  # builtin stubs are the documented "Shader compilation failed" crash;
  # ship the Microsoft DLLs like games/stalker-anomaly does.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
  d3dx9Cabs = {
    "d3dx9_43" = "Jun2010_d3dx9_43_x64.cab";
    "d3dx11_43" = "Jun2010_d3dx11_43_x64.cab";
    "d3dcompiler_43" = "Jun2010_D3DCompiler_43_x64.cab";
  };
  # NOTE on d3dcompiler_47: GAMMA's "Modded EXEs" engine imports
  # d3dcompiler_47 (stock Anomaly used _43). Neither Wine's vkd3d
  # builtin, the Win8.1-SDK _47, nor a modern Win10 _47 will do: the
  # first busy-spins, and ALL of them reject a float3*float4 in
  # combine_1.ps's dead static-sun branch (X3017). We instead ship
  # GAMMA's OWN d3dcompiler_47.dll (bundled at GAMMA/dlls/ in the
  # installer - the exact compiler the modpack validates and MO2
  # injects) for correct D3DReflect, and patch that one dead shader
  # line so the strict compiler accepts it (see buildScript).
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stalker-anomaly-gamma";

  # `src` is the first tar part; the other eight are consumed by the
  # buildScript via their store paths, in order.
  src = srcTar0;

  ipfsSources = srcTarParts;

  nativeBuildInputs = [
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"

    # Reassemble the split tar on stdin and unpack it. The parts are
    # concatenated with cat rather than materialised as one 141 GiB file,
    # and --strip-components drops the archive's "S.T.A.L.K.E.R. GAMMA/"
    # wrapper so the tree below is laid out exactly as innoextract used to
    # leave it: $TMPDIR/gog/{Anomaly,GAMMA,__redist}. Everything after this
    # point is unchanged from the installer-based recipe.
    mkdir -p "$TMPDIR/gog"
    cat ${lib.concatMapStringsSep " " (p: ''"${p}"'') srcTarParts} \
      | tar -x --strip-components=1 -C "$TMPDIR/gog"

    # GOG ships the community layout unmerged: Anomaly/ is a full
    # Anomaly install (its bin/ already carries GAMMA's patched
    # "Modded EXEs" engine binaries), GAMMA/ is a Mod Organizer 2
    # portable instance (ModOrganizer.exe + usvfs + mods/ + the
    # G.A.M.M.A profile), and gammaLauncher.bat starts Grok's updater
    # GUI. Instead of running MO2's usvfs DLL-injection VFS under
    # Proton, flatten the profile's load order into the Anomaly tree
    # at build time: iterate GAMMA/profiles/G.A.M.M.A/modlist.txt
    # bottom-to-top (MO2 lists highest priority FIRST, so later copies
    # in our loop overwrite earlier ones exactly like the VFS resolves
    # them), copying each enabled ("+") mod's tree onto the game root.
    # meta.ini (MO2-internal metadata, hidden from the VFS) and .git
    # trees are skipped. The result is a plain Anomaly-with-GAMMA
    # install that launches like games/stalker-anomaly - no MO2, no
    # usvfs, no launcher.
    cp -r "$TMPDIR/gog/Anomaly/." "$out/"
    chmod -R u+rwX "$out"

    modlist="$TMPDIR/gog/GAMMA/profiles/G.A.M.M.A/modlist.txt"
    mods="$TMPDIR/gog/GAMMA/mods"
    # modlist.txt is CRLF and one entry carries a stray trailing tab
    # (425- Dynamic News Manager...); strip \r and trailing blanks like
    # MO2's tolerant parse does, or those "$name" lookups fail. Of the
    # 557 enabled entries, 554 resolve; the remaining 3 are stale
    # modlist names pointing at renamed/absent mod dirs - inactive
    # under real MO2 with the shipped files too, so exact-name matching
    # reproduces the shipped state. The counter guard catches any
    # future silent mass-failure (wrong path, layout change).
    merged=0
    tr -d '\r' < "$modlist" | sed 's/[[:space:]]*$//' | tac > "$TMPDIR/modlist"
    while IFS= read -r line; do
      case "$line" in
        "+"*) ;;
        *) continue ;;
      esac
      name="''${line#+}"
      case "$name" in
        *_separator) continue ;;
      esac
      [ -d "$mods/$name" ] || continue
      cp -rf --no-preserve=mode "$mods/$name/." "$out/"
      merged=$((merged + 1))
    done < "$TMPDIR/modlist"
    echo "merged $merged mods"
    [ "$merged" -ge 500 ] || {
      echo "ERROR: only $merged mods merged (expected ~554)" >&2
      exit 1
    }
    # Every mod's root-level meta.ini (MO2-internal) collapses onto the
    # same $out/meta.ini; mods' .git trees merge into $out/.git. Drop both.
    rm -rf "$out/meta.ini" "$out/.git"
    chmod -R u+rwX "$out"

    # Native Microsoft D3DX/D3DCompiler (64-bit) next to the engine
    # exes; see games/stalker-anomaly for the full rationale.
    mkdir -p "$TMPDIR/dx"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dll: cab: ''
        cabextract -L -d "$TMPDIR/dx" -F '${cab}' ${directxJun2010}
        cabextract -L -d "$TMPDIR/dx" -F '${dll}.dll' "$TMPDIR/dx/${lib.toLower cab}"
        install -m0644 "$TMPDIR/dx/${dll}.dll" "$out/bin/${dll}.dll"
      '') d3dx9Cabs
    )}
    # GAMMA's own d3dcompiler_47.dll (bundled at GAMMA/dlls/) next to
    # the engine exe: the exact validated MS compiler, with the
    # D3DReflect interface the engine needs (a substituted _43 gives
    # E_NOINTERFACE on D3DReflectShader).
    install -m0644 "$TMPDIR/gog/GAMMA/dlls/d3dcompiler_47.dll" "$out/bin/d3dcompiler_47.dll"

    # appdata skeleton the engine writes into (logs, savedgames, and the
    # shader cache). GOG ships these as empty dirs under the installer's
    # app/Anomaly root (same split-root merge as games/stalker-anomaly).
    cp -rn "$TMPDIR/gog/app/Anomaly/." "$out/" 2>/dev/null || true
    mkdir -p "$out/appdata/logs" "$out/appdata/savedgames"

    # X-Ray recompiles its whole shader set on first launch (~5 min
    # black screen) and caches each blob to
    # appdata/shaders_cache/<rN>/<shader>/<hash>. It creates the
    # per-shader dir with a CreateDirectory that SUCCEEDS on plain ext4
    # but FAILS through the fuse-overlayfs mount ("Can't write file ...
    # No such file or directory") - so without help the cache never
    # persists and every launch pays the full recompile. fuse-overlayfs
    # also rejects a runtime symlink here (ENOMEM). Instead pre-create
    # every per-shader cache dir in the store: file WRITES into an
    # existing dir work fine over the overlay, so the engine then
    # populates the cache and a warm launch reaches the menu in ~30s.
    # shader-cache-dirs.txt is the exact r4 shader set the menu compiles
    # (harvested from a cold run's "Can't write file" log; regenerate by
    # grepping shaders_cache paths from appdata/logs/xray_*.log). In-game
    # levels may compile a few more shaders once per session.
    while IFS= read -r d; do
      [ -n "$d" ] && mkdir -p "$out/appdata/shaders_cache/$d"
    done < ${./shader-cache-dirs.txt}

    # Patch combine_1.ps: its USE_R2_STATIC_SUN branch (dead under
    # GAMMA's dynamic sun, but still precompiled at device init) adds a
    # float3 (SRGBToLinear) * float4 (plight_infinity) that every strict
    # d3dcompiler_47 rejects with X3017, aborting startup with "Shader
    # compilation failed". Wrap the float3 to float4 so the (unused)
    # branch compiles; runtime output is unchanged (dynamic sun).
    ${pkgs.python3}/bin/python3 - "$out/gamedata/shaders/r3/combine_1.ps" <<'PYEOF'
    import sys
    p = sys.argv[1]
    lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
    old = "SRGBToLinear(D.rgb * Ldynamic_color.rgb * sun_occ) *"
    new = "float4(SRGBToLinear(D.rgb * Ldynamic_color.rgb * sun_occ), 1.0) *"
    hits = 0
    for i, l in enumerate(lines):
        if old in l:
            lines[i] = l.replace(old, new); hits += 1
    assert hits == 1, f"combine_1.ps patch matched {hits} lines (expected 1)"
    open(p, "w").write("\n".join(lines))
    PYEOF

    # Seed appdata/user.ltx: dynamic sun (r2_sun_static off - GAMMA's
    # default; the static-sun shader path is the one we patched above)
    # plus borderless at the gamescope surface resolution.
    printf '%s\n' \
      'r2_sun_static off' \
      'rs_screenmode borderless' \
      'vid_mode 1920x1080' \
      > "$out/appdata/user.ltx"
    chmod -R u+rwX "$out"
  '';

  runtime = "proton";
  # GAMMA's patched DX11 AVX engine binary, directly (the MO2 chain is
  # flattened away at build time). CWD is the overlay root, where the
  # engine finds fsgame.ltx. -smap2048 comes from Anomaly's
  # commandline.txt (the launch args the launcher would pass).
  executable = "bin/AnomalyDX11AVX.exe";
  executableArgs = [ "-smap2048" ];

  # fsgame.ltx: $app_data_root$ = $fs_root$\appdata\ - fully portable,
  # all user state (user.ltx, savedgames/, shader caches) lives in
  # appdata/ in the install dir and rides the fuse-overlayfs upper;
  # nothing lands under drive_c/users/steamuser. Same contract as
  # games/stalker-anomaly (MO2 profile had LocalSaves=false, so even
  # under MO2 saves went to the game's appdata).
  saveLocations = [ ];

  copyGlobs = [
    "appdata"
    "bin/d3dx9_43.dll"
    "bin/d3dx11_43.dll"
    "bin/d3dcompiler_43.dll"
    "bin/d3dcompiler_47.dll"
  ];
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

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Native MS D3DX helpers (d3dx9_43/d3dx11_43/d3dcompiler_43 from the
    # Jun2010 redist) + GAMMA's own d3dcompiler_47 shipped into bin/.
    WINEDLLOVERRIDES = "d3dx9_43,d3dx11_43,d3dcompiler_43,d3dcompiler_47=n,b";
  };

  meta = {
    description = "S.T.A.L.K.E.R. G.A.M.M.A. 9.4.0 (Grok's modpack on Anomaly, GOG free release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalker-anomaly-gamma";
  };
}
