{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  util-linux,
}:

let
  # Prototype (Radical Entertainment / Activision, 2009). 7z repack of a
  # pre-installed PC retail tree from archive.org/details/prototype-opti-juegos.-7z
  # ("OptiJuegos" Spanish-scene repack). The repack is NoCD-patched (the
  # original retail used SecuROM 7.x) and ships the community "PrototypeFix"
  # mod (prototype_fix.asi loaded via the binkw32Hooked.dll shim, which
  # replaces binkw32.dll in the launch path). ~5.46 GiB compressed,
  # ~7.5 GiB installed.
  #
  # Top-level directory inside the 7z is "Prototype Opti/" with a few
  # .bat helpers; the actual engine binary lives at
  # "Prototype Opti/gamedata/prototypef.exe". We promote that gamedata/
  # subdir to the output root so $STROM_OVERLAY/prototypef.exe is the
  # launcher (matches what the bundled "1-PROTOTYPE - NORMAL.bat"
  # ultimately runs: cd gamedata && start prototypef.exe).
  gameArchive = fetchIpfs {
    cid = "QmWRHVtwqmkafD5bzf7Nxprp7DsJuEeYfkxRr6ZqC7AQQa";
    fallbackUrl = "https://archive.org/download/prototype-opti-juegos.-7z/Prototype%20OptiJuegos.7z";
    hash = "sha256-2TTYrpAd3hOsniIQeqTF6DGA7cIAGXr3Ns4BWOhugw8=";
    name = "prototype-optijuegos.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prototype";

  src = gameArchive;
  ipfsSources = [ gameArchive ];

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"

    # Extract the 7z. Top-level dir is "Prototype Opti/" with a few
    # .bat helpers at the top; locate prototypef.exe (case-insensitive)
    # under it and promote that directory to the output root so
    # $STROM_OVERLAY/prototypef.exe resolves to the engine binary.
    7z x -o"$TMPDIR/game" "$src" >/dev/null
    exedir=$(find "$TMPDIR/game" -maxdepth 4 -iname 'prototypef.exe' -printf '%h\n' | head -n1)
    if [ -z "$exedir" ]; then
      echo "prototypef.exe not found in archive" >&2
      exit 1
    fi
    cp -r "$exedir"/. "$out"/
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  # prototypef.exe is the engine binary that ships in the repack
  # (NoCD-patched; the original SecuROM-wrapped retail .exe is gone).
  # The bundled .bat launchers just cd into gamedata/ and start this
  # exe, so we boot it directly.
  executable = "prototypef.exe";

  # The OptiJuegos repack's bundled PrototypeFix ASI (emoose) redirects
  # saves from Documents/Prototype to a `Prototype/` subdir of the game
  # install dir, so the per-game fuse-overlayfs upper persists them
  # automatically (verified: ~/.strom/prototype/Prototype/slot-A.bin
  # appears after first save). Leave empty — Documents/Prototype is
  # never written.
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
    # Pure3D was authored against a single hardware thread; on modern
    # high-core CPUs its worker pool spin-waits on a barrier that
    # never advances and the game crashes during the Radical / Activision
    # splash or hangs in the first cutscene. The community-canonical fix
    # (Nexus "PrototypeFix" mod, github.com/flexxxxer/prototype-fixes)
    # pins the process to one CPU via SetProcessAffinityMask; we do the
    # same one layer up via taskset on the proton parent (inherited by
    # every wineserver-spawned thread). Same engine family as Hit & Run,
    # same fix shape.
    #
    # The engine also has no internal FPS cap and ties physics/animation
    # to frame rate above ~62 FPS, producing "frame doubling" (cutscenes
    # play at 2x speed, mouse aim oversteers). DXVK_FRAME_RATE caps the
    # d3d9 swapchain at 60 which is what the engine's frame counter was
    # tuned for. Matches the Hit & Run treatment.
    DXVK_FRAME_RATE = "60";
  };

  # Lock the wineserver process tree to CPU 0 before exec. taskset
  # mutates the current shell pid; the immediately-following exec
  # preserves it and every fork/clone inherits the affinity mask,
  # so PROTOTYPE.exe and all its wineserver threads stay pinned.
  preRun = ''
    ${util-linux}/bin/taskset -pc 0 $$ >/dev/null
  '';

  meta = {
    description = "Prototype (Radical/Activision 2009, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prototype";
  };
}
