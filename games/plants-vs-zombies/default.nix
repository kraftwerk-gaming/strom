{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Plants vs. Zombies: Game of the Year Edition (PopCap 2009), the
  # DRM-free GOG release. The archive.org "Full Installer" ships the GOG
  # Inno Setup installer wrapped in a WinRAR SFX exe; the inner setup.exe
  # (extracted once on the host) is a plain Inno Setup 5.5.7 installer, so
  # the build only needs innoextract --gog. The game tree lives under app/
  # (PlantsVsZombies.exe + main.pak + PlantsVsZombies.dat + bass.dll +
  # cached/sounds/).
  #
  # The PopCap framework opens two config XMLs at startup and shows a blocking
  # "Unable to open '<file>'" dialog (then quits) if either is missing:
  #   * properties\partner.xml — ProdName + the HKCU RegistryKey
  #   * drm.xml                — DisplayName, the PlantsVsZombies.dat GameDataFile
  #                              reference, and the window Width/Height
  # Despite the name, drm.xml is plain startup config on this DRM-free GOG
  # release, so both it and properties/ are kept. Only the GOG "buy now"
  # home-screen image set under drm/ (unused: drm.xml sets HasHomeScreen=false)
  # and Inno installer debris are discarded.
  src = fetchIpfs {
    cid = "QmVjy6i8g6JhSXcfLues1QYsQxeqr3s1JCvrCLdrzhCbft";
    fallbackUrl = "https://archive.org/download/PlantsvsZombiesGameoftheYear_FullInstaller/Plants%20vs%20Zombies%20Game%20of%20the%20Year%20Setup.exe";
    hash = "sha256-sw7fTT2sUUs+yeCkXKkGIEyQ/7aIzfdqL7y5K9bqLUQ=";
    name = "setup_plants_vs_zombies_goty.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "plants-vs-zombies";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    # Keep properties/ + drm.xml (+ .sig): the engine opens them on startup.
    # Drop only the GOG home-screen image set and Inno installer debris.
    rm -rf "$out/drm"
    rm -f "$out/Install.log" "$out/Install_props.xml" \
          "$out/updates.xml" "$out/liesmich.html" \
          "$out/goggame-"*
  '';

  runtime = "proton";
  executable = "PlantsVsZombies.exe";

  # On first launch the GOG exe's PopCap DRM layer extracts the real game
  # (popcapgame1.exe) into C:\ProgramData\PopCap Games\PlantsVsZombies\ and
  # relaunches it with `-changedir=<gamedir>`. That relaunched copy parses
  # its argv strictly and aborts with a blocking "Invalid command line
  # parameter: -changedir" dialog. Seeding a bare `-changedir` on the initial
  # command line satisfies the parser so the relaunch path runs cleanly — the
  # same workaround as Proton's bundled appid-3590 protonfix
  # (util.append_argument('-changedir')), which strom otherwise skips because
  # it runs without the Steam client (SteamAppId=0, PROTONFIXES_DISABLE=1).
  executableArgs = [ "-changedir" ];

  # PvZ writes its save data (userdata/) next to the binary, so progress
  # persists via the per-game fuse-overlayfs upper rather than under
  # drive_c/users/steamuser/.
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Plants vs. Zombies: Game of the Year Edition (PopCap 2009, GOG, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "plants-vs-zombies";
  };
}
