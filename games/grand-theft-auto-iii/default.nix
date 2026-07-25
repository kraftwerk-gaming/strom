{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
  unshield,
  unzip,
}:

let
  # GTA III PC v1.0 (2001 Rockstar). The archive is the retail two-CD
  # release packaged as raw disc images plus a no-CD executable, NOT a
  # pre-installed tree: "GTA3_INSTALL.iso" is an InstallShield installer
  # whose "App Executables" component holds the game tree (gta3.exe,
  # data/, models/, anim/, txd/, movies/, audio/sfx.*), and
  # "GTA3_AUDIO.iso" is the play disc carrying the streamed audio the
  # full install copies into audio/ (radio stations HEAD/CLASS/FLASH/
  # GAME/KJAH/LIPS/MSX/RISE + Chatterbox + ambient/speech). The
  # buildScript unshields the installer and merges the audio disc, so the
  # radio audio IS present (one archive.org reviewer reported silent
  # radio on a partial install; a full merge of GTA3_AUDIO.iso avoids
  # that). The stock gta3.exe is SafeDisc-wrapped and needs the secdrv
  # kernel driver, which won't load under Proton, so the buildScript
  # swaps in the no-CD gta3.exe bundled in the same archive.
  src = fetchIpfs {
    cid = "QmQdKNmBUMSA38Y95RETEEQAwXwVopr2nGGezGmsaYM8HT";
    fallbackUrl = "https://archive.org/download/grand-theft-auto-iii_202103/Grand%20Theft%20Auto%20III.zip";
    hash = "sha256-KcGz1U8H5ofKjGJnkL+3qOTi0PaUysT02mG+/OY+0w4=";
    name = "grand-theft-auto-iii.zip";
  };

  # ThirteenAG's WidescreenFixesPack for GTA III. Ships ThirteenAG's ASI
  # loader compiled as a d3d8-to-d3d9 proxy (d3d8.dll at the game root)
  # plus scripts/{global.ini, GTA3.WidescreenFix.asi, ini}. This is the
  # same loader family as the Ultimate ASI Loader used by San Andreas,
  # but bundled as the d3d8 proxy GTA III actually loads with D3D8to9
  # translation enabled (global.ini UseD3D8to9=1) -- required to render
  # on modern GPUs, exactly like the d3d8 shim in Vice City. Because the
  # loader is bundled here, no separate Ultimate-ASI-Loader.zip is
  # installed: a second proxy DLL would double-load every .asi and crash.
  # global.ini sets LoadFromScriptsOnly=1, so every .asi below lives in
  # scripts/. Pinned to the immutable "gta3" release tag.
  widescreenFix = fetchurl {
    url = "https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gta3/GTA3.WidescreenFix.zip";
    hash = "sha256-OL3rO5AaSVPx9jVoX72RNC3NO6TFpwxiGzerbwF4ieE=";
    name = "GTA3.WidescreenFix.zip";
  };

  # Widescreen frontend assets (menu/loadscreen .txd redrawn for 16:9+)
  # from the same release, merged over the stock models/ and txd/.
  widescreenFrontend = fetchurl {
    url = "https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gta3/GTA3.WidescreenFrontend.zip";
    hash = "sha256-mLis0X48ltdJ0tougO4OjNnPbZ8SnKeLZ2aTWWzTgDQ=";
    name = "GTA3.WidescreenFrontend.zip";
  };

  # SilentPatchIII (CookiePLMonster): the canonical bug-fix patch for the
  # v1.0/v1.1 binary. Fixes the Purple Nines glitch, clamps the mouse to
  # the game window, improves the frame limiter and high-FPS behaviour,
  # drops the DirectPlay dependency and the CD check once audio is on
  # disk. Loaded as an .asi from scripts/. Pinned to the immutable
  # 1.1-BUILD9.2-III release tag.
  silentPatch = fetchurl {
    url = "https://github.com/CookiePLMonster/SilentPatch/releases/download/1.1-BUILD9.2-III/SilentPatchIII.zip";
    hash = "sha256-f1f7WXB2SeKRaLAlwCl74oKkun2NxRCbdTbng6Nj2Uk=";
    name = "SilentPatchIII.zip";
  };

  # GInput III (Silent/CookiePLMonster) 1.11: GTA III's native pad support
  # is DirectInput-only with a broken fixed mapping. GInput rewrites
  # controls onto XInput so modern pads map like the console versions
  # (incl. vibration and the Start button). Loaded as an .asi from
  # scripts/; the button-prompt .txd models merge into models/. Blog-
  # hosted (no GitHub release / tag); pinned by hash -- 1.11 is the last
  # release and unchanged.
  ginput = fetchurl {
    url = "https://silent.rockstarvision.com/uploads/GInputIII.zip";
    hash = "sha256-Anj0EV94i4ePy4O5zIkS30xvG7oXT1w0tO19yMiW98I=";
    name = "GInputIII-1.11.zip";
  };

  # Proton's bundled 32-bit ffmpeg (libavcodec.so.58 -- the MPEG-1 decoder
  # behind winegstreamer's libav plugin) is DT_NEEDED-linked against
  # libbz2.so.1.0 and libvpx.so.6, which the Steam Linux Runtime container
  # normally supplies. strom runs Proton without the SLR, so those libs
  # are absent: libgstlibav fails to load, there is no MPEG decoder, and
  # the intro FMVs (movies/Logo.mpg, GTAtitles.mpg) hang on a black screen
  # before the main menu. Supplying both 32-bit libs via targetPkgs (into
  # the FHS /usr/lib32) lets Proton's own GStreamer decode the intro, with
  # no gstreamer-version juggling. vpx is only referenced for VP8/VP9,
  # which the MPEG-1 intro never exercises, but the soname is a hard
  # NEEDED; libvpx 1.9.0 is the release carrying the .so.6 soname.
  libvpx6 = pkgs.pkgsi686Linux.libvpx.overrideAttrs (old: {
    version = "1.9.0";
    src = pkgs.fetchzip {
      url = "https://github.com/webmproject/libvpx/archive/refs/tags/v1.9.0.tar.gz";
      hash = "sha256-PsN8AOHZalYaB9OCu1yS5vJTvN8BAx8gCU8gtqoyu5s=";
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "grand-theft-auto-iii";

  inherit src;

  nativeBuildInputs = [
    p7zip
    unshield
    unzip
  ];

  # See libvpx6 above: satisfy Proton's ffmpeg SONAME deps so
  # winegstreamer's libav plugin loads and the intro plays. Proton's
  # libavcodec.so.58 NEEDs libbz2.so.1.0, libvpx.so.6, libva{,-drm,-x11}
  # .so.2 and libvdpau.so.1 (all normally provided by the Steam Runtime).
  targetPkgs = p: [
    p.pkgsi686Linux.bzip2.out
    libvpx6
    p.pkgsi686Linux.libva
    p.pkgsi686Linux.libvdpau
  ];

  buildScript = ''
    mkdir -p "$out"

    # The archive holds the two retail CD images plus a no-CD gta3.exe.
    # Pull only those out (skip the manual/cover extras) to keep the
    # build's temp footprint down.
    unzip -q "$src" \
      "Grand Theft Auto III/Grand Theft Auto III - Disk Images/*" \
      "Grand Theft Auto III/GTA 3 Patch And NOCD/gta3.exe" \
      -d "$TMPDIR/zip"
    imgdir="$TMPDIR/zip/Grand Theft Auto III/Grand Theft Auto III - Disk Images"

    # Base game tree: the INSTALL disc is an InstallShield installer.
    # Extract its cabinet payload (data1.hdr indexes data1.cab/data2.cab)
    # from the ISO9660 image, then unshield the "App Executables"
    # component -- that group is the installed game directory.
    7z x -y -o"$TMPDIR/inst" "$imgdir/GTA3_INSTALL.iso" data1.hdr data1.cab data2.cab >/dev/null
    unshield -g "App Executables" -d "$TMPDIR/game" x "$TMPDIR/inst/data1.hdr" >/dev/null
    gamedir=$(dirname "$(find "$TMPDIR/game" -iname 'gta3.exe' -print | head -n1)")
    if [ -z "$gamedir" ]; then
      echo "gta3.exe not found after unshield" >&2
      exit 1
    fi
    cp -r "$gamedir"/. "$out"/
    chmod -R u+w "$out"

    # Radio + speech streams live on the AUDIO (play) disc under Audio/.
    # A full retail install copies them next to the installer's
    # audio/sfx.* so the in-game radio has content; merge them in.
    7z x -y -o"$TMPDIR/audiodisc" "$imgdir/GTA3_AUDIO.iso" Audio >/dev/null
    cp -rf "$TMPDIR/audiodisc/Audio"/. "$out/audio"/

    # Retail gta3.exe is SafeDisc-wrapped (needs the secdrv driver, which
    # Proton can't load). Swap in the no-CD executable from the archive.
    cp -f "$TMPDIR/zip/Grand Theft Auto III/GTA 3 Patch And NOCD/gta3.exe" "$out/gta3.exe"

    # WidescreenFix bundle = the d3d8-to-d3d9 ASI loader (d3d8.dll) plus
    # scripts/{global.ini, GTA3.WidescreenFix.asi, ini}. Unzip verbatim so
    # the shipped scripts/ layout (LoadFromScriptsOnly=1) is preserved.
    unzip -q -o ${widescreenFix} -d "$out"

    # Widescreen menu/loadscreen assets over the stock models/ and txd/.
    unzip -q -o ${widescreenFrontend} -d "$out"

    # SilentPatchIII + GInput III load as .asi from scripts/ (the loader
    # only scans scripts/); GInput's button-prompt .txd merge into models/.
    unzip -q -o ${silentPatch} SilentPatchIII.asi SilentPatchIII.ini -d "$out/scripts"
    unzip -q -o ${ginput} GInputIII.asi GInputIII.ini -d "$out/scripts"
    unzip -q -o ${ginput} 'models/*' -d "$out"
  '';

  runtime = "proton";
  executable = "gta3.exe";

  saveLocations = [ "Documents/GTA3 User Files" ];

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
    # d3d8 is the WidescreenFix's d3d8-to-d3d9 translator + ASI loader;
    # let the game-bundled DLL win over Wine's builtin (n,b).
    WINEDLLOVERRIDES = "d3d8=n,b";
  };

  meta = {
    description = "Grand Theft Auto III (2001 Rockstar, PC v1.0 + ThirteenAG Widescreen Fix + SilentPatch + GInput, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "grand-theft-auto-iii";
  };
}
