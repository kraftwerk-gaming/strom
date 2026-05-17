{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # archive.org "mdk95" item: pre-installed, no-CD patched Windows 95 build
  # with cnc-ddraw bundled (ddraw.dll + ddraw.ini at the game root). The
  # ISO is a filesystem image of the ready-to-run game folder, not the
  # original CD-ROM. mdk95.exe is the Windows entry point; the bundled
  # nocd.sh documents the launch invocation:
  #   ./mdk95.exe -iamapirate
  src = fetchIpfs {
    cid = "Qmc8qopswLHRB2UHGtY2oiNezWUsgBHxdfbVxhExuYPH8G";
    fallbackUrl = "https://archive.org/download/mdk95/MDK95Patched.iso";
    hash = "sha256-V0uuFvvK3fsXaTeYmZVX412JrBlrt/OpBZTVRpX5aXs=";
    name = "mdk.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mdk";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -bso0 -bsp0 "$src" -o"$out"
    chmod -R u+w "$out"

    # The shipped mdk.cfg hard-codes the original Win95 install layout
    # (hddata=C:\SHINY\MDK, cddata=D:\). With the game running from a
    # fuse-overlay rooted at our extracted tree, those Windows paths
    # don't exist and mdk95.exe silently exits after failing to open
    # MISC\MDKFONT.FTI. The engine concatenates the prefix verbatim
    # (`sprintf("%sMISC\\…", hddata)`), so we need the trailing
    # backslash to land on `.\MISC\MDKFONT.FTI` (= cwd-relative).
    sed -i \
      -e 's|^cddata\s*=.*|cddata = .\\|' \
      -e 's|^hddata\s*=.*|hddata = .\\|' \
      "$out/mdk.cfg"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # mdk.cfg + ddraw.ini next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "mdk95.exe";
  # -iamapirate disables the CD-presence check (the ISO is a pre-installed
  # tree, not a mountable game CD).
  executableArgs = [ "-iamapirate" ];

  # cnc-ddraw is bundled in the archive and pinned via its own ddraw.ini.
  # Force the Wine loader to prefer the native ddraw.dll alongside
  # mdk95.exe over Proton's builtin DirectDraw, so the 1997 DirectDraw
  # paths actually render under Vulkan.
  env = {
    WINEDLLOVERRIDES = "ddraw=n,b";
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
    description = "MDK (Shiny Entertainment 1997, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mdk";
  };
}
