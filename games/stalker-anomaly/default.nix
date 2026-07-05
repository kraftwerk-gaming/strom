{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  innoextract,
  cabextract,
}:

let
  # Official free GOG release of S.T.A.L.K.E.R. Anomaly v1.5.3
  # (build 84683). Anomaly is the free, standalone total conversion on
  # the community 64-bit "Monolith" X-Ray engine; it needs none of the
  # original S.T.A.L.K.E.R. games. The GOG edition is the same 1.5.3
  # content as the classic ModDB 1.5.1+updates chain, but curated into a
  # single 5-part Inno Setup installer (a small .exe stub plus four .bin
  # slices) that innoextract reassembles.
  #
  # Store names are sanitized (no "()" - invalid in store paths); the
  # buildScript re-links the parts under one consistent basename, which
  # is all innoextract needs to find the slices.
  srcExe = fetchIpfs {
    cid = "QmbpLg263Ptx7K1f99W2vM8GMekEHuqszqkefQ4U89s8Pr";
    fallbackUrl = "";
    hash = "sha256-LrYjVMijTxPm9J4SH6OrCD3+Hayu4+CxXlRT7R2+2io=";
    name = "setup_stalker_anomaly_1.5.3_gog_84683.exe";
  };
  srcBin1 = fetchIpfs {
    cid = "QmYiaTUkE4cpkeXe75yQcXTuyHSGQHTyiuGqyoTsqNghKt";
    fallbackUrl = "";
    hash = "sha256-j0EoLi901xwzN68NQ7KC2obcxqXVdnuK7nmcqbvJcfw=";
    name = "setup_stalker_anomaly_1.5.3_gog_84683-1.bin";
  };
  srcBin2 = fetchIpfs {
    cid = "QmYEJdhR22Wyfx3i257KjkvxBcSH6RwJXVAFSDWQVLiwWu";
    fallbackUrl = "";
    hash = "sha256-16Jcj1A7mlNd1SzUrphlCXwkn4E5ZEgu2+DG2E+8vGk=";
    name = "setup_stalker_anomaly_1.5.3_gog_84683-2.bin";
  };
  srcBin3 = fetchIpfs {
    cid = "QmWyF13MW2DBrbmo3hCqDj1L9GKuoWZu9qU6T99LYAawG3";
    fallbackUrl = "";
    hash = "sha256-vU4gaBXml4r+yWwECwb1d343TZwnO5EV5sq4TvdwsYU=";
    name = "setup_stalker_anomaly_1.5.3_gog_84683-3.bin";
  };
  srcBin4 = fetchIpfs {
    cid = "QmPaseLkGYNgA6TQabe5131mZozZ3H6ExtnFt6357EnRqq";
    fallbackUrl = "";
    hash = "sha256-+43tZ9kGZUXTW43WH6beuft8MWYc8UryJAy8b815z/w=";
    name = "setup_stalker_anomaly_1.5.3_gog_84683-4.bin";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # AnomalyDX11AVX.exe's import table pulls exactly d3dx9_43.dll,
  # d3dx11_43.dll and d3dcompiler_43.dll (64-bit; verified by scanning
  # the PE). Wine's builtin d3dx/d3dcompiler stubs are the documented
  # "Shader compilation failed" crash on Anomaly under Proton; the
  # community fix (winetricks d3dx9_43 d3dx11_43 d3dcompiler_43) installs
  # exactly these Microsoft DLLs. Same redist + pattern as
  # age-of-empires-iii / dark-souls-prepare-to-die-edition, but the
  # _x64 inner cabs since the engine is 64-bit.
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
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stalker-anomaly";

  # `src` is the Inno stub; the four .bin slices are consumed by the
  # buildScript via their store paths.
  src = srcExe;

  ipfsSources = [
    srcExe
    srcBin1
    srcBin2
    srcBin3
    srcBin4
  ];

  nativeBuildInputs = [
    innoextract
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"

    # Reassemble the 5-part GOG Inno installer under one consistent
    # basename (innoextract locates the -N.bin slices by the stub's
    # name) and extract.
    mkdir -p "$TMPDIR/inst"
    ln -s "$src"       "$TMPDIR/inst/setup_stalker_anomaly.exe"
    ln -s "${srcBin1}" "$TMPDIR/inst/setup_stalker_anomaly-1.bin"
    ln -s "${srcBin2}" "$TMPDIR/inst/setup_stalker_anomaly-2.bin"
    ln -s "${srcBin3}" "$TMPDIR/inst/setup_stalker_anomaly-3.bin"
    ln -s "${srcBin4}" "$TMPDIR/inst/setup_stalker_anomaly-4.bin"
    innoextract -e -s -d "$TMPDIR/gog" "$TMPDIR/inst/setup_stalker_anomaly.exe"

    # This installer spreads its payload over two Inno path roots:
    # the game tree proper lands at the extraction root (bin/, db/,
    # tools/, fsgame.ltx, AnomalyLauncher.exe, ...) while a small
    # `app/` holds the appdata/db/gamedata directory skeletons plus
    # the GOG icon. Merge both into $out; drop the installer-only
    # payloads: tmp/ (slideshow), commonappdata/ (GOG support
    # installer), __redist/ (dotNet35 for AnomalyLauncher.exe, which
    # we do not use - see `executable` below).
    cp -r "$TMPDIR/gog/." "$out/"
    chmod -R u+rwX "$out"
    rm -rf "$out/tmp" "$out/commonappdata" "$out/__redist" "$out/app"
    cp -rn "$TMPDIR/gog/app/." "$out/"
    chmod -R u+rwX "$out"

    # Native Microsoft D3DX/D3DCompiler (64-bit) next to the engine
    # exes; two-stage cabextract out of the Jun 2010 redist (outer SFX
    # cabinet -> per-DLL inner cab -> DLL). WINEDLLOVERRIDES below
    # binds them native so the engine's shader compilation runs
    # through the real implementations instead of Wine's stubs.
    mkdir -p "$TMPDIR/dx"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dll: cab: ''
        cabextract -L -d "$TMPDIR/dx" -F '${cab}' ${directxJun2010}
        cabextract -L -d "$TMPDIR/dx" -F '${dll}.dll' "$TMPDIR/dx/${lib.toLower cab}"
        install -m0644 "$TMPDIR/dx/${dll}.dll" "$out/bin/${dll}.dll"
      '') d3dx9Cabs
    )}

    # Seed appdata/user.ltx with the gamescope surface resolution and
    # borderless mode so the first launch comes up at the right size
    # (the engine appends everything else on first write; borderless
    # avoids the exclusive-fullscreen modeswitch path under nested
    # gamescope). rs_screenmode is an Anomaly 1.5.2+ option.
    mkdir -p "$out/appdata"
    printf '%s\n' \
      'rs_screenmode borderless' \
      'vid_mode 1920x1080' \
      > "$out/appdata/user.ltx"
    chmod -R u+rwX "$out"
  '';

  runtime = "proton";
  # Run the DX11 AVX engine binary directly instead of
  # AnomalyLauncher.exe: the launcher is a .NET 3.5 renderer/AVX picker
  # (that's what __redist/dotNet35 was for) and community practice on
  # Proton is to launch the engine exe itself. CWD is the overlay root
  # (mk-game does `cd "$GAMEDIR"`), where the engine finds fsgame.ltx.
  executable = "bin/AnomalyDX11AVX.exe";

  # fsgame.ltx: $app_data_root$ = $fs_root$\appdata\ - the engine is
  # fully portable and writes ALL user state (user.ltx, savedgames/,
  # screenshots/, logs/, shaders_cache/) into appdata/ in the install
  # dir, which persists via the per-game fuse-overlayfs upper. Nothing
  # is written under drive_c/users/steamuser/, so a prefix wipe cannot
  # lose progress.
  saveLocations = [ ];

  # Materialize into the writable upper before the merge mount:
  # appdata/ (the engine's state root, including the seeded user.ltx)
  # and the three app-local Microsoft DLLs (Wine's loader resolves an
  # app-local native DLL over the builtin reliably only when the file
  # is present in the upper - see games/company-of-heroes).
  copyGlobs = [
    "appdata"
    "bin/d3dx9_43.dll"
    "bin/d3dx11_43.dll"
    "bin/d3dcompiler_43.dll"
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
    # Bind the native Microsoft D3DX helpers + shader compiler shipped
    # into bin/ (n = native first, b = builtin fallback). Wine's
    # builtins stub enough of D3DX/fx that Anomaly dies with "Shader
    # compilation failed" at load without them.
    WINEDLLOVERRIDES = "d3dx9_43,d3dx11_43,d3dcompiler_43=n,b";
  };

  meta = {
    description = "S.T.A.L.K.E.R. Anomaly 1.5.3 (standalone total conversion, GOG free release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stalker-anomaly";
  };
}
