{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  util-linux,
}:

let
  # The Simpsons: Hit & Run (Vivendi / Radical, 2003 PC port). RAR5
  # archive of a fully-installed retail tree from
  # archive.org/details/the-simpsons-hit-run_202202. Top-level directory
  # inside the rar is `The Simpsons - Hit & Run/`, containing Simpsons.exe
  # (the engine), Lucas' Simpsons Hit & Run Mod Launcher.exe (Donut Team's
  # compatibility launcher for modern systems / mods), the .ini, bink/eax
  # DLLs and the full art/scripts/sound trees. No-CD already applied (the
  # binary in this rip launches without the disc).
  gameArchive = fetchIpfs {
    cid = "QmT1cgcUcMbBXMaUif8aT6oed9BGHno9tRp3ySbUE2JiSo";
    fallbackUrl = "https://archive.org/download/the-simpsons-hit-run_202202/The%20Simpsons%20-%20Hit%20%26%20Run.rar";
    hash = "sha256-RcevvMX8SWOMtR4HFube+gJLFM6dEIDIyj2fnj5/NBQ=";
    name = "the-simpsons-hit-run.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-simpsons-hit-run";

  src = gameArchive;
  ipfsSources = [ gameArchive ];

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"

    # Extract the RAR5 archive. unar handles RAR5 cleanly and is
    # license-clean (vs. the unfree unrar binary). The archive contains
    # one top-level folder "The Simpsons - Hit & Run/"; locate
    # Simpsons.exe and promote that directory to the output root.
    unar -f -q -o "$TMPDIR/game" "$src"
    exedir=$(find "$TMPDIR/game" -maxdepth 4 -iname 'Simpsons.exe' -printf '%h\n' | head -n1)
    if [ -z "$exedir" ]; then
      echo "Simpsons.exe not found in archive" >&2
      exit 1
    fi
    cp -r "$exedir"/. "$out"/
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  # Original Radical engine binary. The bundled "Lucas Simpsons Hit &
  # Run Mod Launcher.exe" is a community compatibility/mod tool kept in
  # the tree for users who want it; we boot the vanilla engine to keep
  # the launch path free of third-party patchers.
  executable = "Simpsons.exe";

  # The engine writes savegames and the runtime simpsons.ini config
  # next to Simpsons.exe (engine strings only reference "SaveGame\\"
  # and ".\\simpsons.ini"). The fuse-overlayfs upper already persists
  # those at ~/.strom/<game>/, so no Documents/AppData relocation is
  # needed. Verified 2026-05-18: Save1 + simpsons.ini land at
  # ~/.strom/the-simpsons-hit-run/ and survive prefix wipes.
  saveLocations = [ ];

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
    # binkw32.dll: RAD Game Tools Bink Video decoder, called by the
    # engine for intro/cutscene FMV playback. Wine's builtin stub
    # doesn't implement the BinkOpen/BinkDoFrame surface the engine
    # uses, so it must load the shipped native DLL.
    # eax.dll: Creative EAX 2.0 wrapper for DirectSound3D effects.
    # The shipped DLL is the original Creative redist; Wine has no
    # builtin. "n,b" = native first, builtin fallback.
    WINEDLLOVERRIDES = "binkw32,eax=n,b";

    # Hit & Run's Pure3D engine ties its tick loop to whatever core
    # it's first scheduled on; on multi-core CPUs threads migrate
    # mid-frame and the engine spin-loops on a barrier that never
    # advances -> infinite loading screen. The community-canonical
    # fix is to lock the process to a single core. Lucas' Mod
    # Launcher does this via SetProcessAffinityMask; we do the same
    # one layer up via taskset on the proton parent (inherited by
    # every wineserver-spawned thread).
    #
    # Same engine has no internal FPS cap and runs physics + loading
    # transitions at frame-rate-coupled rates; >60 FPS reproduces
    # the same hang. DXVK_FRAME_RATE caps the d3d9 swapchain to 60
    # which is enough to keep the loader's frame counter linear.
    DXVK_FRAME_RATE = "60";
  };

  # Lock the wineserver process tree to CPU 0 before exec. taskset
  # mutates the current shell pid; the immediately-following exec
  # preserves it and every fork/clone inherits the affinity mask,
  # so Simpsons.exe and all its wineserver threads stay pinned.
  preRun = ''
    ${util-linux}/bin/taskset -pc 0 $$ >/dev/null
  '';

  meta = {
    description = "The Simpsons: Hit & Run (Vivendi/Radical 2003 PC port, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-simpsons-hit-run";
  };
}
