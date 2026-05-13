{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # NOLF Complete Edition repack: WinRAR SFX bundling NOLF v1.004 GOTY
  # + Modernizer Patch v1.006 + widescreen rez + dgVoodoo2 D3D7/DDraw
  # wrappers + No-CD patch. NOLF's rights are in legal limbo (Monolith
  # 2000 -> WB / 20th Century / Activision unresolved), so no digital
  # storefront sells it; distribution here follows the de-facto
  # abandonware bundle maintained by the NOLF community.
  src = fetchIpfs {
    cid = "QmNNopwiiZ9daLJQ7Z2fT6emAxKeVnFwkWiYWAp4oHC1KH";
    fallbackUrl = "https://archive.org/download/no-one-lives-forever-complete-edition/NOLF_Complete_Edition.exe";
    hash = "sha256-Xw3OtRnI7cC6wgWn/emivFIqqaGA5fSBu5da3Q07LK8=";
    name = "no-one-lives-forever.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "no-one-lives-forever";

  inherit src;

  nativeBuildInputs = [ unar ];

  # WinRAR SFX. unar -o <dir> creates <dir>/<archive-stem>/, which for
  # a /nix/store/<hash>-no-one-lives-forever.exe input is the full
  # store-name stem (sans .exe). Glob it instead of hard-coding.
  # Drop the hosts-file injector and stickykeys reg-tweak that target
  # native Windows installs; they have no business inside a wineprefix.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/. "$out"/
    rm -f "$out/hosts" "$out/disable_stickykeys.reg" "$out/NOLF_POST_INSTALL.bat"
  '';

  runtime = "proton";
  # NOLF.exe is the launcher front-end: it writes the chosen renderer /
  # rez / display config into the registry, then execs lithtech.exe.
  # Under proton+bwrap that exec chain breaks (the launcher exits and
  # `waitforexitandrun` returns before the child lithtech.exe is wrapped),
  # so the game vanishes after the launcher closes. Sidestep the
  # launcher entirely and start lithtech.exe with the exact arg set the
  # launcher would otherwise pass — taken from nolfcmds.txt (GOTY repack
  # default) plus Custom/MODERNIZER.REZ to enable the v1.006 Modernizer
  # mod that the repack ships. The data drop has no ogl.ren so the
  # engine stays on the default D3D renderer (d3d.ren), which talks to
  # the wine builtin ddraw via WineD3D -> Vulkan/DXVK.
  #
  # The shipped defaults.cfg sets screenwidth/height to 640/480 and
  # autoexec.cfg has no screen-size keys: the launcher normally rewrites
  # those before the engine starts. Without the launcher the engine
  # boots at 640x480 inside a 1920x1080 surface (LithTech 1.x's
  # canonical "black screen with cursor" failure mode). Force size +
  # 32-bit + disable flash via +convars on the cmdline.
  executable = "lithtech.exe";
  executableArgs = [
    "-windowtitle"
    "No One Lives Forever"
    "-rez"
    "NOLF.rez"
    "-rez"
    "NOLF2.rez"
    "-rez"
    "nolfu003.rez"
    "-rez"
    "NOLFCRES003.REZ"
    "-rez"
    "NOLFGOTY.rez"
    "-rez"
    "Custom/MODERNIZER.REZ"
    "-rez"
    "Custom/WidescreenGOTY.rez"
    "-rez"
    "Custom/FontSizeFix_03.REZ"
    "-rez"
    "Custom/FOX.REZ"
    "-rez"
    "Custom/NOLFC001.REZ"
    "-rez"
    "Custom/NOLFC002.rez"
    "+multiplayer"
    "0"
    "+DisableMusic"
    "0"
    "+DisableSound"
    "0"
    "+DisableTripBuf"
    "0"
    "+DisableHardwareCursor"
    "0"
    "+screenwidth"
    "1920"
    "+screenheight"
    "1080"
    "+bitdepth"
    "32"
    "+disableflashscreen"
    "1"
  ];

  # The data drop ships dgVoodoo2's DDraw/D3DImm wrappers next to
  # lithtech.exe. An earlier attempt force-loaded them via
  # WINEDLLOVERRIDES=ddraw,d3dim,d3dim700,dinput=n,b but with those
  # overrides lithtech crashes inside dgVoodoo's ddraw on the first
  # D3D7 surface call (page fault in ddraw+0x30dcf, called from d3d.ren
  # — dgVoodoo dereferences an uninitialised pointer when its host-side
  # D3D11 path can't reach a real Windows ID3D11Device through proton).
  # Leave WINEDLLOVERRIDES unset so wine's builtin ddraw handles the
  # D3D7 path via the WineD3D -> Vulkan bridge; the dgVoodoo .dll files
  # in the gamedir are ignored because Wine prefers the builtin for
  # known system DLL names when no n,b override is in effect.

  # NOLF writes saves and profiles next to the game .exe (Save/ +
  # cfg files at the install root). With proton + the strom overlayfs
  # the game dir is read-only so those writes land in the upper layer
  # at $STROM_GAMEDIR. No AppData-style paths to relocate for this
  # engine; saveLocations stays empty.

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
    description = "The Operative: No One Lives Forever (Monolith 2000, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "no-one-lives-forever";
  };
}
