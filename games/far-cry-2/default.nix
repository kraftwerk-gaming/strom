{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Pre-baked Far Cry 2: Fortune's Edition (Ubisoft Montreal, 2008; Dunia
  # engine) install tree with the community "Realism Plus Redux" overhaul
  # applied. Sourced from the ElAmigos "Far Cry 2 RealismRedux" RAR
  # (archive.org item far-cry-2-realism-redux): an Inno Setup 5.5 loader
  # (setup.exe) plus a single 3.1 GiB FreeArc payload (elamigos-1.bin) that
  # decodes only through the Win32 ISDone.dll/unarc.dll codec stack at run
  # time -- innoextract refuses it (encrypted entries + customised Inno
  # variant). The repack installs /VERYSILENT end-to-end under proton's wine
  # in ~3.5 min, well within budget, but the sandboxed FOD path would need a
  # 32-bit FHS plus an Xvfb stub for the installer's progress dialog. To keep
  # the recipe tight we bake the install once on the host (silent flags, no
  # user interaction), overlay the Realism Plus Redux bin/ + Data_Win32/
  # patch (per its R+R instructions), prune the install-time redistributables
  # (installers/, unins000.*), and pin the result as a deterministic tar.zst
  # -- consumers just fetchIpfs + tar. Runs through Proton (Steam Deck).
  src = fetchIpfs {
    cid = "QmYRVdmUSPFjWzfCLPTiUmhLQ9n4VxycFE8s4oiB7GosnY";
    hash = "sha256-gPpcpYuHHu7Uf+GvJ+//2iHadRwu+/au/kD3trpYnfQ=";
    name = "far-cry-2-realism-redux.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "far-cry-2";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";

  # Launch the Dunia game binary (bin/farcry2game.exe) DIRECTLY rather than
  # through the Realism Plus Redux "Multi-Fixer" loader (bin/FarCry2.exe, by
  # FoxAhead). The loader renders its window and locates the game binary via
  # FindFirstFile, but then aborts with "Game exe file
  # Z:\...\bin\farcry2game.exe does not exist (FarCry2.exe not found)": its
  # Delphi FileExists()/GetFileAttributes probe for the binary returns false
  # under this Proton/Wine even though the file is on disk. The probe fails
  # whether the tree is on the fuse-overlayfs mount OR on plain btrfs, so it
  # is NOT the overlay case-resolution issue of
  # reference_overlay_save_case_insensitivity -- it is a loader/Wine
  # incompatibility, and the loader never reaches the engine.
  #
  # farcry2game.exe is the real game; launched directly it boots straight to
  # the Far Cry 2 main menu (verified headless: title -> menu reads "Far Cry
  # 2 REALISM+ REDUX"). The Realism Plus Redux overhaul lives in Data_Win32/
  # (BigTinz's Redux + Buggalug's Realism+ + Soulrach's Functional Outposts,
  # all data/script-level), so the Redux content, difficulties ("Hardcore
  # Redux"/"Infamous Redux") and branding are all still present. Dropping the
  # loader drops ONLY the Multi-Fixer's binary-injection extras (FarCry2MF.dll
  # memory patches: Jackal-tape accounting, machete unlock, FarCry2.ini
  # FOV/no-blink); the engine-flag fixes it would have appended are passed
  # directly below. FC2Launcher.exe (the GOG front-end) is likewise bypassed.
  executable = "bin/farcry2game.exe";

  # Engine command-line flags -- the same ones the Multi-Fixer loader appends
  # to farcry2game.exe, so passing them directly recovers its launch-time
  # behaviour without the loader:
  #   -GameProfile_SkipIntroMovies 1  skip the Ubisoft/Dunia logos.
  #   -GameProfile_FrameRateLimit 60  the Dunia engine ties physics/animation
  #     to frame rate; above ~62 FPS it desyncs (people "jump around", the
  #     hotel-shootout crash), so clamp it (DXVK_FRAME_RATE backstops at the
  #     swapchain level).
  executableArgs = [
    "-GameProfile_SkipIntroMovies"
    "1"
    "-GameProfile_FrameRateLimit"
    "60"
  ];

  # Saves + profile config land in the user profile, not next to the binary.
  saveLocations = [
    "Documents/My Games/Far Cry 2"
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
    STEAM_COMPAT_APP_ID = "19900";
    SteamAppId = "19900";
    # Dunia desyncs at high frame rates; clamp the d3d swapchain to 60.
    DXVK_FRAME_RATE = "60";
  };

  meta = {
    description = "Far Cry 2: Fortune's Edition + Realism Plus Redux (Ubisoft 2008, Dunia, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "far-cry-2";
  };
}
