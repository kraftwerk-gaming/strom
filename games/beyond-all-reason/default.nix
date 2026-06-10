{
  self,
  lib,
  pkgs,
  fetchurl,
  autoPatchelfHook,
  stdenv,
}:

let
  version = "1.2988.0";

  # Engine version pinned to match launcher-config.beyondallreason.dev/config.json
  # (manual-linux setup as of 2026-06-09). Update engine* together with poolInit
  # whenever BAR cuts a new stable release.
  engineVersion = "2025.06.24";

  # Pinned rapid package MD5 digests (versions.gz as of 2026-06-09):
  #   byar:test       -> 5b77e64bb0c5e6e793cee9f669a52423
  #   byar-chobby:test -> 380a340c36bab59b2dc0a150abe88afc
  # These change when BAR pushes a new game update; update together with poolInit.

  # Beyond All Reason ships its launcher (BYAR-Chobby, an Electron app) as a
  # type-2 AppImage. The AppImage's own runtime can't self-mount (no FUSE in the
  # userns), so the embedded squashfs is unpacked at build time and the Electron
  # binary is run directly. Free software / free-to-play; fetched from GitHub.
  launcher = fetchurl {
    url = "https://github.com/beyond-all-reason/BYAR-Chobby/releases/download/v${version}/Beyond-All-Reason-${version}.AppImage";
    hash = "sha256-ZJW5BdxxqyrM2TJTO0SBp4BXt3ILyi77EZx73X8hqJE=";
    name = "beyond-all-reason-${version}.AppImage";
  };

  # Recoil engine binaries for Linux (spring, spring-headless, AI, libunitsync).
  # Extracted at build time into barData so the launcher's engine-presence check
  # (fs.existsSync(writePath/engine/<engineVersion>/)) skips the download.
  engineTarball = fetchurl {
    url = "https://github.com/beyond-all-reason/RecoilEngine/releases/download/${engineVersion}/recoil_${engineVersion}_amd64-linux.7z";
    hash = "sha256-w/TrHGMotvkhvmI/HwZChr7pvQMCxxcoO+jZLbkw25g=";
  };

  # Rapid pool bootstrap archive (Method=Copy; files are already .gz-compressed
  # pool entries in xx/yyyyyy.gz layout). This is the same file the launcher
  # downloads optionally as the "pool" resource. It covers 99.9% of byar:test
  # (18138/18230 files, 3212/3215 MB) and 100% of byar-chobby:test by file count.
  # The remaining ~2.4 MB delta is fetched by pr-downloader on first launch.
  # Update this hash together with engineVersion when BAR makes a major release
  # (pool-init changes weekly; the date below tracks when this hash was computed).
  # Last updated: 2026-06-09.
  poolInit = fetchurl {
    url = "https://pool-init.beyondallreason.dev/data.7z";
    hash = "sha256-yw9vgT0Xa9vjO3fOdd0jKt9FVugkoyGFWHioCk9gjXc=";
  };

  # Rapid package descriptors for the two main packages. Each .sdp is a gzip
  # binary listing (1-byte name-len + name + 16-byte MD5 + 4-byte crc32 +
  # 4-byte compressed-size) of pool files required for that package version.
  # The filename is the md5 from versions.gz for that tag.
  byarSdp = fetchurl {
    url = "https://repos-cdn.beyondallreason.dev/byar/packages/5b77e64bb0c5e6e793cee9f669a52423.sdp";
    hash = "sha256-CBfgHIY4K0Y0UH9uP/uAlPB5pyBeQ9sT1ft7CrxBo+A=";
  };
  byarChobbySdp = fetchurl {
    url = "https://repos-cdn.beyondallreason.dev/byar-chobby/packages/380a340c36bab59b2dc0a150abe88afc.sdp";
    hash = "sha256-yAq0dAbXWn4mQ/dB/svZhB1dwdmlq3fxtQzEtuAU5a0=";
  };

  # Rapid repo metadata (versions.gz for each repo + master repos.gz).
  # pr-downloader always tries to refresh these via ETag (REPO_RECHECK_TIME=0),
  # so it makes a quick conditional GET on startup. If server returns 304 the
  # cached copy is used and no pool download follows. If the network call fails
  # pr-downloader exits non-zero, but since the data is already present the
  # engine itself loads fine and the Electron launcher shows a warning rather
  # than blocking.
  reposGz = fetchurl {
    url = "https://repos-cdn.beyondallreason.dev/repos.gz";
    hash = "sha256-1BFHoAhyE3xAXaFMW6eG1f0WpqAv0L4rEde2JAv0oi0=";
  };
  byarVersionsGz = fetchurl {
    url = "https://repos-cdn.beyondallreason.dev/byar/versions.gz";
    hash = "sha256-fLBuGzzRwFP270jlUsVjrNAhKAEizvqzpH+PCWIOc1c=";
  };
  byarChobbyVersionsGz = fetchurl {
    url = "https://repos-cdn.beyondallreason.dev/byar-chobby/versions.gz";
    hash = "sha256-U38StpI2gvadNw35VWMgJCkVc4rUVjhdYJauwLX3/c8=";
  };

  # Runtime libs the bundled Electron dlopens by bare soname.
  electronLibs = with pkgs; [
    glib
    nss
    nspr
    nss_latest
    dbus
    atk
    at-spi2-atk
    at-spi2-core
    cups
    libdrm
    gtk3
    pango
    cairo
    expat
    libxkbcommon
    alsa-lib
    libgbm
    libGL
    libglvnd
    libpulseaudio
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libXScrnSaver
    xorg.libxcb
    xorg.libxshmfence
  ];

  # Pre-populated Spring data directory. Layout mirrors what the Chobby launcher
  # downloads on first run so that every directory-existence check skips the
  # network fetch:
  #
  #   engine/<engineVersion>/  <- fs.existsSync check in http_downloader.js
  #   pool/                    <- fs.existsSync("pool") skips pool-init.7z download
  #   packages/<md5>.sdp       <- pr-downloader uses cached SDP, skips download
  #   rapid/.../versions.gz    <- pr-downloader uses ETag; 304 = no pool download
  #
  # Uses pkgs.p7zip (17.05) which handles pool-init.7z's older 7z header format.
  # Newer 7zip (≥ 22.x) rejects pool-init.7z with "Headers Error".
  barData = stdenv.mkDerivation {
    pname = "beyond-all-reason-data";
    version = "${version}-engine-${engineVersion}";

    dontUnpack = true;

    nativeBuildInputs = [
      pkgs.p7zip
      autoPatchelfHook
    ];

    # Recoil/Spring engine ELFs (spring, spring-headless, spring-dedicated,
    # pr-downloader, libunitsync.so, AI libs) ship with a /lib64 interpreter and
    # bare-soname DT_NEEDED entries. autoPatchelfHook rewrites the interpreter +
    # RPATH into the nix store so the engine runs on NixOS. The portable Recoil
    # release statically links most deps; the only dynamic externals are these.
    buildInputs = [
      stdenv.cc.cc.lib
      pkgs.SDL2
      pkgs.openal
      pkgs.libGL
      pkgs.libglvnd
      pkgs.xorg.libX11
      pkgs.xorg.libXcursor
      pkgs.xorg.libXext
      pkgs.xorg.libXrandr
    ];

    buildPhase = ''
      runHook preBuild

      # Engine: extract into engine/recoil_<engineVersion>/ (the name used in
      # launcher-config.beyondallreason.dev/config.json → launch.engine field).
      mkdir -p "engine/recoil_${engineVersion}"
      7z x ${engineTarball} -o"engine/recoil_${engineVersion}" -y >/dev/null

      # Pool: extract pool-init.7z directly; files are already xx/rest.gz layout
      mkdir -p pool
      7z x ${poolInit} -o"pool" -y >/dev/null

      # Rapid package descriptors
      mkdir -p packages
      cp ${byarSdp}       packages/5b77e64bb0c5e6e793cee9f669a52423.sdp
      cp ${byarChobbySdp} packages/380a340c36bab59b2dc0a150abe88afc.sdp

      # Rapid repo metadata (CDN domain used by the launcher config)
      mkdir -p rapid/repos-cdn.beyondallreason.dev/byar
      mkdir -p rapid/repos-cdn.beyondallreason.dev/byar-chobby
      cp ${reposGz}              rapid/repos-cdn.beyondallreason.dev/repos.gz
      cp ${byarVersionsGz}       rapid/repos-cdn.beyondallreason.dev/byar/versions.gz
      cp ${byarChobbyVersionsGz} rapid/repos-cdn.beyondallreason.dev/byar-chobby/versions.gz

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r engine packages pool rapid "$out"/
      runHook postInstall
    '';

    dontStrip = true;
  };

  gameData = stdenv.mkDerivation {
    pname = "beyond-all-reason-launcher";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [
      autoPatchelfHook
      pkgs.squashfsTools
    ];

    buildInputs = [ stdenv.cc.cc.lib ] ++ electronLibs;

    # The launcher's own usr/lib ships legacy GTK2 tray-icon/notify libs
    # (appindicator/gconf/indicator) that pull in dead GTK2 deps. Electron only
    # dlopens them for a system-tray icon, which strom doesn't need; let
    # autoPatchelf skip the unsatisfiable transitive sonames instead of failing.
    autoPatchelfIgnoreMissingDeps = [
      "libffmpeg.so"
      "libdbusmenu-gtk.so.4"
      "libdbusmenu-glib.so.4"
      "libdbus-glib-1.so.2"
      "libgtk-x11-2.0.so.0"
    ];

    buildPhase = ''
      runHook preBuild
      # AppImage = small ELF runtime + appended squashfs. The squashfs
      # superblock sits at a fixed offset for this release; locate it by the
      # 'hsqs' magic and unpack from there.
      offset="$(grep -a -b -o hsqs ${launcher} | awk -F: '$1>40000{print $1; exit}')"
      unsquashfs -o "$offset" -d squashfs-root ${launcher}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r squashfs-root/. "$out"/
      runHook postInstall
    '';

    # Electron binaries embed an ELF interpreter and crash if stripped/altered
    # beyond rpath.
    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "beyond-all-reason";

  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "custom";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (electronLibs ++ [ pkgs.stdenv.cc.cc.lib ]);
  };

  # Pre-populate the Spring write directory on first launch so the Chobby
  # launcher finds engine + pool + packages already present and skips its
  # network downloads. The write directory is:
  #   $HOME/.local/state/Beyond All Reason/
  # where $HOME = $STROM_GAMEDIR = ~/.strom/beyond-all-reason/ in strom.
  #
  # The "pool" sentinel check in http_downloader.js skips pool-init.7z if
  # pool/ already exists. The engine-dir check skips the engine download.
  # pr-downloader still runs for games (byar:test / byar-chobby:test) but
  # finds 99.9% of pool files present (only ~2.4 MB delta to fetch).
  preRun = ''
    BAR_DATADIR="$HOME/.local/state/Beyond All Reason"
    if [ ! -f "$BAR_DATADIR/.strom-init" ]; then
      echo "beyond-all-reason: populating Spring data directory from Nix store..." >&2
      mkdir -p "$BAR_DATADIR"
      cp -r --no-preserve=mode,ownership ${barData}/. "$BAR_DATADIR"/
      chmod -R u+w "$BAR_DATADIR"
      touch "$BAR_DATADIR/.strom-init"
      echo "beyond-all-reason: Spring data directory ready." >&2
    fi
    # Restore exec bit on engine ELFs (idempotent; fixes --no-preserve=mode strip)
    chmod +x "$BAR_DATADIR"/engine/recoil_*/spring \
             "$BAR_DATADIR"/engine/recoil_*/spring-headless \
             "$BAR_DATADIR"/engine/recoil_*/spring-dedicated \
             "$BAR_DATADIR"/engine/recoil_*/pr-downloader \
      2>/dev/null || true
    mkdir -p "$HOME/.config" "$HOME/.local/share"
  '';

  # GAMEDIR is the read-write overlay over the unpacked launcher; $HOME is the
  # persistent ~/.strom/beyond-all-reason where the launcher downloads engine +
  # assets and writes its Spring config.
  runScript = ''
    export APPDIR="$GAMEDIR"
    export PATH="$GAMEDIR/bin:$GAMEDIR/usr/sbin:$PATH"
    export LD_LIBRARY_PATH="$GAMEDIR/usr/lib:''${LD_LIBRARY_PATH:-}"

    # chrome-sandbox needs a setuid root helper, unavailable in the bwrap
    # userns; run Electron without its own sandbox (we are already sandboxed).
    exec "$GAMEDIR/beyond-all-reason" --no-sandbox "$@"
  '';

  meta = {
    description = "Beyond All Reason (free RTS on the Recoil/Spring engine; engine+assets pre-fetched at build time)";
    homepage = "https://www.beyondallreason.info/";
    platforms = [ "x86_64-linux" ];
    mainProgram = "beyond-all-reason";
  };
}
