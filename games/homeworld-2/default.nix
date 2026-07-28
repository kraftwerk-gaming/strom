{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Homeworld 2 (Relic, 2003). GOG never sold the 2003 game standalone:
  # the only DRM-free distribution of the original engine is the copy
  # bundled inside the GOG Homeworld Remastered Collection installer as
  # `Homeworld2Classic/` — the unmodified 2003 Relic build, shipped next
  # to (and independent of) the 2015 HomeworldRM remaster. The retail
  # 2003 CD (archive.org `homeworld-2`, HOMEWORLD2.iso) is not usable
  # here: it is an InstallShield install that prompts for a CD key, i.e.
  # an interactive GUI step.
  #
  # Same three-part GOG installer as `games/homeworld` (which runs the
  # bundled Homeworld1Classic); CIDs and hashes are shared with it on
  # purpose so one pin covers both games — these are the repinned
  # `ipfs add --raw-leaves` CIDs from 1eb4497, re-derived from the bytes
  # and verified here. innoextract reads the .exe and its two .bin
  # slices together when they sit next to each other under their
  # original filenames, so we symlink them into $TMPDIR first.
  setupExe = fetchIpfs {
    cid = "QmNZii5dEietiWJ3XWamoXtZVJ4G8uWoMokCFXjg38puiQ";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29.exe";
    hash = "sha256-G5xedp7ALYkNvhfF0hU1UnTGxwwxflBAlgFTZo7Cijs=";
    name = "homeworld-remastered-gog-2.1.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "QmcAz3HugvgxsXrqUjSpoz2pKDQKiMi9bee8fbKDcz9nV4";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-1.bin";
    hash = "sha256-V82oiqkkQGMPEv1iohZ0d2ZiwK7PvUWKzkqU/m04aHM=";
    name = "homeworld-remastered-gog-2.1-1.bin";
  };

  setupBin2 = fetchIpfs {
    cid = "QmWNTi4bwTDXjQRmsu2ua4z6nvPvYBK5kEBPWWyC8RxPYy";
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

  # `-I app/Homeworld2Classic` keeps only the 2003 engine tree (51 files,
  # ~1.6 GiB) out of the ~12 GiB collection. The HomeworldRM remaster,
  # Homeworld1Classic and the .NET HWLauncher are separate top-level
  # dirs and none of them is referenced by Homeworld2.exe.
  #
  # THE se*Audio.dll COPY IS THE AUDIO FIX. SoundInitDriver discovers its
  # sound backends by globbing `se*.dll` in the PROCESS WORKING
  # DIRECTORY — not in the exe's directory — then LoadLibrary()s each hit
  # and calls its InspectDLL export to get a driver name, which it
  # matches against SoundDriver from Data:soundscripts/SoundEngine.lua
  # ("FDAudio" in this build). GOG ships seFDAudio.dll/seDXAudio.dll in
  # Bin/Release/ next to the exe, but preRun has to cd to
  # Homeworld2Classic/ for the `data:` alias (see below), so the glob
  # runs one level up from the DLLs and matches nothing. A wine
  # +file,+loaddll trace shows exactly that: FindFirstFileExW
  # L"...\Homeworld2Classic/se*.dll" enumerates ., .., Bin, Data,
  # Hw2.log, readme.txt, write.txt and reports `mask L"se*.dll" found 0
  # files`, and the strings "seFDAudio"/"seDXAudio" never appear again in
  # the trace — the glob is the only discovery path, so with zero hits
  # there is no LoadLibrary, no CreateDevice, no destinations, and every
  # later Sound_* call dies with "Sound Manager could not create a handle
  # to play ..." in Hw2.log. There is no error message for the empty
  # glob, so the failure is silent. Copying the two driver DLLs to the
  # game root puts them where the glob actually looks; the originals stay
  # in Bin/Release/, which is the app directory and therefore still
  # resolves their Memory.dll import.
  #
  # WARNING for future edits: anything that changes the working directory
  # silently re-breaks audio. The tell is Hw2.log with no "SOUND --
  # created destination" lines.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/hw"
    ln -s ${setupExe}  "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    ln -s ${setupBin1} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-1.bin"
    ln -s ${setupBin2} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-2.bin"
    innoextract --gog -I app/Homeworld2Classic -d "$TMPDIR/iss" \
      "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    cp "$out/Homeworld2Classic/Bin/Release"/se*Audio.dll "$out/Homeworld2Classic/"
  '';

  runtime = "proton";

  # The engine keeps everything user-owned inside the install tree, so
  # the per-game fuse-overlayfs upper already persists it and there is
  # nothing under drive_c/users/steamuser to list. Verified empirically
  # after a launch that reached the main menu: the overlay gained
  # Profiles/ (the profile dir the engine reports as "..profiles\"),
  # CACHE/, STATS/, LOGFILES/, SCREENSHOTS/, GAMERULES/, PATCH/,
  # SYNCERROR/ and tempCursor.cur at the install root, plus
  # Homeworld2Classic/Hw2.log; the only thing written under steamuser
  # was AppData/{Local/Temp,*/Microsoft}.
  saveLocations = [ ];

  # The original 2003 Homeworld 2 binary preserved alongside the
  # Remastered build. Its own DSOUND/Lua-based engine, with zero
  # dependency on Galaxy.dll, lsteamclient or the launcher's WPF/.NET
  # stack (verified via Homeworld2.exe's import table), so unlike
  # HomeworldRM.exe it needs no Galaxy client to get past Init().
  executable = "Homeworld2Classic/Bin/Release/Homeworld2.exe";

  preRun = ''
    # Homeworld2.exe resolves its `data:` filepath alias relative to its
    # game subdir (Homeworld2Classic/), not the GOG install root.
    # Without this cd, FilePathArchive finds none of the .big archives:
    # the engine writes only its write.txt permission probe and returns
    # from Initialize() in a few ms, before it can even create Hw2.log.
    #
    # This cwd is also where the engine globs se*.dll for its sound
    # drivers, which is why buildScript copies them here. Move this cd
    # and audio dies silently.
    cd "$GAMEDIR/Homeworld2Classic"
  '';

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
    # Homeworld 2's renderer (DCWindow.dll) queries OpenGL caps via
    # GL.dll. On Mesa the default 4.x core profile is rejected by the
    # engine's GL probe. Forcing a 3.3 compatibility profile satisfies
    # it and lets the engine build its GL context — Hw2.log then reports
    # "Using AMD's 3.3 (Compatibility Profile) Mesa ... renderer". This
    # is the GL path, not D3D9, so no wined3d/PROTON_USE_WINED3D is
    # involved.
    MESA_GL_VERSION_OVERRIDE = "3.3COMPAT";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LANG = "en_US.UTF-8";
    # Audio: wine's builtin dsound, and nothing else. DSOAL is NOT
    # needed here — once the engine can find its own driver DLLs (see
    # buildScript) it creates all four destinations against wine's
    # dsound, which Hw2.log confirms:
    #   SOUND -- created destination [ fdaudio ] ... [ 48 ] channels
    #   SOUND -- created destination [ fda streamer ] ... [ 8 ] channels
    #   SOUND -- created destination [ dxa streamer ] ... [ 8 ] channels
    #   SOUND -- created destination [ dxaudio ] ... [ 48 ] channels
    # i.e. the DirectSound3D providers named in SoundEngine.lua resolve
    # fine on wine's software mixer, so there is no zero-hardware-buffer
    # problem to wrap. The GOG tree ships no dsound.dll of its own; this
    # override pins that and keeps a future DSOAL drop-in from silently
    # taking over.
    #
    # mmdevapi picks winepulse (Preferred) on its own and it is stable —
    # three DSOUND_PerformMix underruns in the first 0.5% of a 1.6M-line
    # +pulse,+dsound trace, none afterwards through menu and gameplay.
    # It needs the 32-bit libudev that lib/proton.nix puts in the FHS
    # chroot; without that winepulse cannot dlopen its unix half and
    # mmdevapi silently falls back.
    WINEDLLOVERRIDES = "dsound=b";
  };

  meta = {
    description = "Homeworld 2 (Relic, 2003 classic engine, GOG Remastered Collection v2.1 build 3877, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "homeworld-2";
  };
}
