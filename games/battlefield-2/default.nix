{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # OldGamesDownload / elamigos pre-installed v1.50 Complete Collection
  # repack: vanilla Battlefield 2 + Special Forces expansion baked in,
  # patched to the final 1.50 retail level. The archive ships the
  # standard EA install layout (BF2.exe + mods/bf2 + mods/xpack) plus
  # the no-CD SD*.dll DLLs that bypass the SecuROM disc check, so the
  # game launches without a CD or a DRM activation server. Tree root:
  #   Battlefield_2_Complete_Collection_v1.50_Win_Preinstalled_EN/
  #     Game Files/                 (the actual install)
  #       BF2.exe
  #       mods/bf2 mods/xpack
  #       SD*.dll                   (no-CD)
  #     OldGamesDownload.url ReadMe.txt
  src = fetchIpfs {
    cid = "QmcaQ1SRUNpGvd7tAo1hLNbSZFPsJYK1nhf7KbhY28Ztpx";
    fallbackUrl = "https://archive.org/download/battlefield-2-complete-collection-v-1.50-win-preinstalled-en/Battlefield_2_Complete_Collection_v1.50_Win_Preinstalled_EN.zip";
    hash = "sha256-8kP202JukygAzpLQfd5bBIfNtRgpRDVxYbqX+A3zC5M=";
    name = "battlefield-2-complete-collection-v1.50.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "battlefield-2";

  inherit src;

  # p7zip extracts the archive even though it has trailing zero padding
  # that confuses info-zip's unzip (the EOCD record sits 22 bytes before
  # EOF, well within p7zip's scan window).
  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"

    # The zip wraps the actual install in a vendor-named top-level dir.
    # Extract only the "Game Files/" subtree and flatten it into $out so
    # BF2.exe lands at the package root next to mods/.
    7z x -y "$src" -o"$TMPDIR/bf2" \
      "Battlefield_2_Complete_Collection_v1.50_Win_Preinstalled_EN/Game Files/*"
    cp -r "$TMPDIR/bf2/Battlefield_2_Complete_Collection_v1.50_Win_Preinstalled_EN/Game Files"/. "$out"/
    rm -rf "$TMPDIR/bf2"
    chmod -R u+w "$out"

    # GameSpy-era online play (master server browser, account login)
    # depends on gamespy.com hosts that have been dead since 2014. The
    # community revival BF2Hub repoints those hostnames at its own
    # servers via a hosts override / client-side patch — out of scope
    # for the offline package; single-player and direct-connect LAN /
    # IP work without any patch. Multiplayer requires the user to
    # install BF2Hub (https://www.bf2hub.com/) into the prefix manually.

    # Default video config: bump the shipped 800x600 windowed fallback
    # to 1920x1080 fullscreen across the vanilla and xpack mods. The
    # engine reads these on first launch and clones them into the
    # per-profile Video.con; later edits via the in-game menu persist
    # to the prefix. The shipped Video.con uses LF endings so plain
    # sed without CRLF handling is fine.
    for mod in bf2 xpack; do
      f="$out/mods/$mod/Settings/Video.con"
      if [ -f "$f" ]; then
        sed -i \
          -e 's/^renderer.setScreenResolution .*/renderer.setScreenResolution 1920 1080 60/' \
          -e 's/^renderer.fullScreen .*/renderer.fullScreen 1/' \
          "$f" || true
      fi
    done
  '';

  runtime = "proton";
  executable = "BF2.exe";

  # +menu 1 forces the launcher menu (avoids the autorun "insert disc"
  # path); +fullscreen 1 ensures the engine picks the fullscreen mode
  # gamescope advertises rather than the 800x600 windowed default.
  # +szx/+szy match gamescope's nested resolution.
  executableArgs = [
    "+menu"
    "1"
    "+fullscreen"
    "1"
    "+szx"
    "1920"
    "+szy"
    "1080"
    "+ignoreAsserts"
    "1"
  ];

  # Profiles, key bindings, server favorites, demos and screenshots all
  # live under mods/<mod>/Profiles (or the Documents/Battlefield 2
  # tree under the user's home). Documents/ is handled by saveLocations
  # below; the Profiles dir under the install root needs copyGlobs so
  # it survives a fuse-overlayfs lower-layer wipe.
  copyGlobs = [
    "mods/bf2/Profiles/"
    "mods/bf2/Settings/"
    "mods/xpack/Profiles/"
    "mods/xpack/Settings/"
  ];

  # BF2 also writes the per-user profile tree to
  # %USERPROFILE%\Documents\Battlefield 2\Profiles, including the
  # Default account, controls, video config, and savegames. Relocate
  # to ~/.strom/battlefield-2/ so a compatdata wipe does not lose
  # progress or rebound keys.
  saveLocations = [ "Documents/Battlefield 2" ];

  env = {
    # Bink video (binkw32.dll) and the MFC7.x runtimes shipped in the
    # install tree must take precedence over wine's stubs; otherwise the
    # intro / loading videos hang and the launcher MFC dialog crashes on
    # startup. dbghelp is shipped by the repack as a debug-spew helper
    # the engine looks up by name; native-then-builtin matches Lutris.
    WINEDLLOVERRIDES = "binkw32=n,b;mfc70=n,b;mfc71=n,b;dbghelp=n,b";
    STAGING_WRITECOPY = "1";
  };

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

  meta = {
    description = "Battlefield 2 Complete Collection (DICE/EA 2005, v1.50 preinstalled repack, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "battlefield-2";
  };
}
