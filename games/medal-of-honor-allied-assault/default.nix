{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unshield,
}:

let
  openmohaa = pkgs.callPackage ./openmohaa.nix { };

  # Original 2002 EA retail release on 2 CDs (2015 Inc., Quake III engine).
  # Each ISO is an ISO9660 filesystem holding the InstallShield 6 setup
  # plus a few loose files. The setup is split across data1.hdr / data1.cab
  # (disc1) / data2.cab (disc1) / data3.cab (disc2); unshield walks the .hdr
  # and pulls files out of all three cabs once they're co-located.
  # Disc2 also carries main/Pak2.pk3 outside the InstallShield set
  # (it ships loose at the disc root because it's needed at install end).
  disc1 = fetchIpfs {
    cid = "QmcmhYLPYFi32ifs5iqnuiPgoLiAHgFRCbr6zEaXfroZDt";
    fallbackUrl = "https://archive.org/download/medal_of_honor_allied_assault_disc1/MOHAA_DISK1.ISO";
    hash = "sha256-Rot8cRWhMi5Us5Hn2NuQciHdmrer9zlzVytrgec3slQ=";
    name = "medal-of-honor-allied-assault-disc1.iso";
  };

  disc2 = fetchIpfs {
    cid = "QmUUKZ2GuYgKPgSfv8qA9gRAzng3gz5Cwcg4Xj3ZjJGXgF";
    fallbackUrl = "https://archive.org/download/medal_of_honor_allied_assault_disc2/MOHAA_DISK2.ISO";
    hash = "sha256-IoOhnANdb6en4dxMA3zjEEvpkj50mTyQxXmye1zuyW8=";
    name = "medal-of-honor-allied-assault-disc2.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "medal-of-honor-allied-assault";

  ipfsSources = [
    disc1
    disc2
  ];
  src = disc1;

  nativeBuildInputs = [
    p7zip
    unshield
  ];

  # Retail MOHAA.exe is SafeDisc 2 protected — the wrapper exits silently
  # under modern Wine/Proton (its kernel-mode `secdrv.sys` callback can't
  # be satisfied, and the CD-presence check follows). We sidestep the
  # original Windows binary entirely and use OpenMoHAA, a native Linux
  # ioquake3-based source port of the MoH:AA engine that loads the
  # retail pak0..pak5 + sound/ + video/ directly. The buildScript still
  # extracts the full retail data tree from the InstallShield cabs (and
  # disc2's loose Pak2.pk3) — only the Windows .exe / Bink / Miles DLLs
  # at the root are dropped, since the source port has its own engine.
  #
  # InstallShield component → install path mapping (unshield groups in
  # the left column; install paths chosen by the original retail setup):
  #   Data_Files_Minimal/*.pk3         -> $out/main/
  #   Music_Files/                     -> $out/main/sound/music/
  #   Sound_Amb_Files/                 -> $out/main/sound/amb/
  #   Sound_AmbStereo_Files/           -> $out/main/sound/amb_stereo/
  #   Sound_Dialogue_Files/            -> $out/main/sound/dialogue/
  #   Sound_Mechanics_Files/           -> $out/main/sound/mechanics/
  #   Sound_Vehicle_Files/             -> $out/main/sound/vehicle/
  #   Sound_Weapons_Files/             -> $out/main/sound/weapons/
  #   Video_Files/                     -> $out/main/video/
  # The cgamex86.dll / gamex86.dll engine modules at disc2's root are
  # MoHAA-Windows-specific and aren't needed: OpenMoHAA ships its own
  # `cgame.so` / `game.so`. Program_Executable_Files (MOHAA.exe + the
  # SafeDisc loader DLLs), SoundDriver_Files (Miles), and the
  # _Engine_*/_Support_*/InstallShield Kernel components are install-time
  # only and dropped.
  buildScript = ''
    mkdir -p "$out/main"

    # Co-locate data1.hdr + data1.cab + data2.cab (disc1) with data3.cab
    # (disc2) so unshield sees a single InstallShield set.
    7z x -y -o"$TMPDIR/iso1" ${disc1} data1.hdr data1.cab data2.cab
    7z x -y -o"$TMPDIR/iso2" ${disc2} data3.cab 'main/Pak2.pk3'
    cp "$TMPDIR/iso2/data3.cab" "$TMPDIR/iso1/"

    unshield -d "$TMPDIR/un" x "$TMPDIR/iso1/data1.hdr"

    # main/ - retail paks (Pak0,1,3,4,5 from unshield; Pak2 loose on disc2).
    cp "$TMPDIR/un/Data_Files_Minimal"/Pak[0-9].pk3 "$out/main"/
    cp "$TMPDIR/iso2/main/Pak2.pk3" "$out/main"/

    # Sound + music + video subtrees under main/.
    mkdir -p "$out/main/sound/music" "$out/main/sound/amb" \
             "$out/main/sound/amb_stereo" "$out/main/sound/dialogue" \
             "$out/main/sound/mechanics" "$out/main/sound/vehicle" \
             "$out/main/sound/weapons" "$out/main/video"
    cp -r "$TMPDIR/un/Music_Files"/. "$out/main/sound/music"/
    cp -r "$TMPDIR/un/Sound_Amb_Files"/. "$out/main/sound/amb"/
    cp -r "$TMPDIR/un/Sound_AmbStereo_Files"/. "$out/main/sound/amb_stereo"/
    cp -r "$TMPDIR/un/Sound_Dialogue_Files"/. "$out/main/sound/dialogue"/
    cp -r "$TMPDIR/un/Sound_Mechanics_Files"/. "$out/main/sound/mechanics"/
    cp -r "$TMPDIR/un/Sound_Vehicle_Files"/. "$out/main/sound/vehicle"/
    cp -r "$TMPDIR/un/Sound_Weapons_Files"/. "$out/main/sound/weapons"/
    cp -r "$TMPDIR/un/Video_Files"/. "$out/main/video"/

    # OpenMoHAA dlopens game.so/cgame.so from fs_basepath at runtime;
    # the engine's GetGameAPI() searches CWD first, so place the two
    # .so's alongside main/ here (the runtime cds into the overlay,
    # which mirrors $out at launch). Copy rather than symlink so the
    # chmod below doesn't have to chase symlinks into the read-only
    # openmohaa store path.
    cp ${openmohaa}/share/openmohaa/game.so "$out/game.so"
    cp ${openmohaa}/share/openmohaa/cgame.so "$out/cgame.so"

    chmod -R u+w "$out"
  '';

  runtime = "native";

  # OpenMoHAA reads `main/pak*.pk3` relative to fs_basepath; the strom
  # native runtime chdirs to the rw overlay before invoking the script,
  # so we hand it $GAMEDIR explicitly. fs_homepath redirects writes
  # (configs, savegames, console history) to $STROM_GAMEDIR so they
  # survive overlay rebuilds. com_target_game 0 selects the base game
  # (Spearhead = 1, Breakthrough = 2 — neither is installed here).
  #
  # libopenal.so.1 and libcurl.so.4 are dlopened by basename rather than
  # linked NEEDED, so autoPatchelf can't see them; we drop the bundled
  # libs in openmohaa.nix and provide nixpkgs builds on LD_LIBRARY_PATH.
  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      pkgs.openal
      pkgs.curl
    ];
  };

  runScript = ''
    exec ${lib.getExe openmohaa} \
      +set fs_basepath "$GAMEDIR" \
      +set fs_homepath "$STROM_GAMEDIR" \
      +set com_target_game 0 \
      "$@"
  '';

  # fs_homepath under $STROM_GAMEDIR keeps every persistent file there:
  # OpenMoHAA writes its `main/configs/`, `main/save/`, `main/players/`,
  # and a top-level `mohconfig.cfg` into fs_homepath, so the overlay
  # itself only needs the (read-only) retail data tree.
  copyGlobs = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Medal of Honor: Allied Assault (2015 Inc. / EA 2002, retail v1.00 data, via OpenMoHAA source port)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "medal-of-honor-allied-assault";
  };
}
