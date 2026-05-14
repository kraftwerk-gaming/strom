{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Homeworld Remastered Collection v2.1 (build
  # 3877). Three-part GOG installer (.exe + 2 .bin slices). innoextract
  # reads them together when they sit next to each other; we symlink
  # them in $TMPDIR with the original filenames before extracting.
  setupExe = fetchIpfs {
    cid = "Qmep6UP4xtHUnupwGSV4mfs96M9Eh7ie7MaHLxMxSyWFn5";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29.exe";
    hash = "sha256-G5xedp7ALYkNvhfF0hU1UnTGxwwxflBAlgFTZo7Cijs=";
    name = "homeworld-remastered-gog-2.1.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "Qmce73FoZAZnWoceHUbqh66N4QW59VxbN9GUWvwNnw1pMS";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-1.bin";
    hash = "sha256-V82oiqkkQGMPEv1iohZ0d2ZiwK7PvUWKzkqU/m04aHM=";
    name = "homeworld-remastered-gog-2.1-1.bin";
  };

  setupBin2 = fetchIpfs {
    cid = "Qmdrjc6pmPqfT2z6CQi1938gXbRES7kRNK3VK2MNP4AAfC";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-2.bin";
    hash = "sha256-CjcrK21uVNwbC0Pz8/JNsviaSHwNKKfh9zt6JFd9XyQ=";
    name = "homeworld-remastered-gog-2.1-2.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "homeworld-2";

  ipfsSources = [
    setupExe
    setupBin1
    setupBin2
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    mkdir -p "$TMPDIR/hw"
    ln -s ${setupExe}  "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    ln -s ${setupBin1} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-1.bin"
    ln -s ${setupBin2} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-2.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    rm -rf "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" "$out/webcache.zip" 2>/dev/null || true
  '';

  runtime = "proton";
  # The original 2003 Homeworld 2 binary preserved alongside the
  # Remastered build. Uses its own DSOUND/Lua-based engine and has
  # zero dependency on Galaxy.dll, lsteamclient, or the launcher's
  # WPF/.NET stack — verified via objdump on Homeworld2.exe's import
  # table. Runs cleanly under Proton on AMD Mesa.
  executable = "Homeworld2Classic/Bin/Release/Homeworld2.exe";

  # 32-bit systemd → /usr/lib32/libudev.so.1 for the 32-bit winepulse.drv
  # so it doesn't fall back to ELFCLASS64 /usr/lib/libudev.so.1.
  #
  # pipewire (32+64-bit) ships the ALSA bridge plugin
  # `libasound_module_pcm_pipewire.so`. NixOS sets
  # `pcm.!default { type pipewire }` in
  # /etc/alsa/conf.d/99-pipewire-default.conf (the chroot symlinks
  # /etc/alsa from the host), so without the plugin in
  # /usr/lib(32)/alsa-lib/, winealsa's open of "default" landed on a
  # codepath pipewire never saw — `pactl list sink-inputs` and
  # `pw-cli ls Client` showed zero wine client while +dsound was
  # actively mixing into the secondary buffer. With the plugin
  # available wine registers as `PipeWire ALSA [wine-preloader]`
  # and routes to the user's default pipewire sink (verified live:
  # mute=no, vol=~57%, sink=bluez_output).
  targetPkgs = p: [
    p.pkgsi686Linux.systemd
    p.pipewire
    p.pkgsi686Linux.pipewire
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
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # Homeworld 2's renderer (DCWindow.dll) queries OpenGL caps via
    # GL.dll. On Mesa drivers (Intel/AMD) the default 4.x core
    # profile is rejected by the engine's GL probe. Forcing a 3.3
    # compatibility profile satisfies the probe and lets the engine
    # build its GL context.
    MESA_GL_VERSION_OVERRIDE = "3.3COMPAT";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LANG = "en_US.UTF-8";
    # winepulse defaults to a very short target latency that, combined
    # with HW2's small dsound buffers and the proton 32-bit stack, causes
    # the output stream to underrun and be torn down (visible in
    # +pulse,+dsound trace as the playback stream landing in state 4 = TERMINATED
    # shortly after the engine starts mixing). Raise the pulse client
    # target latency to 60ms so the kernel/server has slack to keep the
    # stream alive and audio remains audible.
    PULSE_LATENCY_MSEC = "60";
    # The GOG release does NOT bundle DSOAL (verified: no dsound.dll in
    # Homeworld2Classic/Bin/Release). Wine always uses its builtin
    # dsound. Bink intro audio works (binkw32 has its own path), but
    # the post-intro engine (seDXAudio/seFDAudio + Homeworld2.exe all
    # import DSOUND.dll by name) routes through dsound → wine MMDevAPI
    # → winepulse, which underruns on this host's pipewire-pulse under
    # proton 32-bit even with PULSE_LATENCY_MSEC=60. Force wine to use
    # the ALSA driver instead — bypasses pipewire-pulse's 32-bit
    # stream-cycling bug, talks directly to pipewire's ALSA shim.
    WINEDLLOVERRIDES = "dsound=b;winepulse.drv=;winealsa.drv=b";
  };

  preRun = ''
    # Homeworld2.exe resolves its `data:` filepath alias relative to
    # its game subdir (Homeworld2Classic/), not the GOG install root.
    # Without this cd, FilePathArchive can't find any of the .big
    # archives, the engine prints HW2BOX init then returns from
    # Initialize() in <5ms.
    cd "$GAMEDIR/Homeworld2Classic"
  '';

  meta = {
    description = "Homeworld 2 (Relic, 2003 classic, GOG v2.1 build 3877, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "homeworld-2";
  };
}
