{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  p7zip,
}:

let
  # Metal Slug Tactics (Leikir Studio / Dotemu, 2024). Tactical-RPG
  # roguelike on Unity (IL2CPP). Windows-only, so runtime = "proton".
  #
  # SOURCE: a repack-games.com pre-installed Windows release of build
  # 16631148, shipped as a plain zip (no installer to run). The repack
  # already ships a gbe_fork steam emu in place of the real Steamworks dll
  # (Metal Slug Tactics_Data/Plugins/x86_64/steam_api64.dll, with the
  # original backed up as steam_api64.dll.bak and a steam_settings/ tree
  # carrying configs.*.ini + steam_appid.txt next to it), so it boots
  # offline under Proton without an extra dll swap. The other steamrip
  # mirrors are not reachable from headless agents (megadb gates the
  # download behind a recaptcha, gog-games.to behind Cloudflare); the
  # pixeldrain mirror serves the same zip over a clean CDN API with no
  # captcha.
  src = fetchIpfs {
    cid = "QmNbqY58iVsj3FCchrg5xHQSe6yZFG4cPA7aVWJUhxa94N";
    fallbackUrl = "https://pixeldrain.com/api/file/nvwrfCAb";
    hash = "sha256-vO+5UtV+pXar2z5dKm1Rb5aRzcrWHxRn94hyn+GfhDI=";
    name = "metal-slug-tactics-build-16631148.zip";
  };

  # GE-Proton bundles ffmpeg 4.x (libavcodec.so.58) for winegstreamer, but
  # that libavcodec is NEEDED-linked against libvpx.so.6 (libvpx 1.9.x) --
  # a soname nixpkgs no longer ships (current libvpx is .so.12). Pin 1.9.0
  # so Proton's bundled libavcodec/libgstlibav can resolve it in the FHS,
  # which lets Media Foundation build an H.264 pipeline for the intro
  # videos instead of black-screening at launch.
  libvpx6 = pkgs.libvpx.overrideAttrs (old: {
    version = "1.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "webmproject";
      repo = "libvpx";
      rev = "v1.9.0";
      hash = "sha256-PsN8AOHZalYaB9OCu1yS5vJTvN8BAx8gCU8gtqoyu5s=";
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "metal-slug-tactics";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    unzip
    p7zip
  ];

  # The zip wraps a single top-level dir
  # ("Metal.Slug.Tactics.Build.16631148/"). Strip it so $out/Metal Slug
  # Tactics.exe sits at the root next to the Unity *_Data dir. The repack's
  # gbe_fork emu and steam_settings/ are kept exactly as shipped.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -a "$TMPDIR/extract/Metal.Slug.Tactics.Build.16631148/." "$out"/
    test -f "$out/Metal Slug Tactics.exe" \
      || { echo "Metal Slug Tactics.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/Metal Slug Tactics_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (gbe_fork emu) missing" >&2; exit 1; }

    # repack-games clutter (readme/url/diagnostic batch + any redist
    # installers Proton's FHS already provides).
    rm -f "$out"/*.url "$out"/*.txt "$out"/*.bat 2>/dev/null || true
    rm -rf "$out/_Redist" "$out/Redist" "$out/__redist" 2>/dev/null || true

    # Drop any Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. atomicrops/moving-out).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe" 2>/dev/null || true
  '';

  runtime = "proton";
  executable = "Metal Slug Tactics.exe";

  # Unity IL2CPP writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\; app.info
  # pins those to "Leikir Studio" / "Metal Slug Tactics". gbe_fork also
  # keeps its emulated Steam remote-storage saves under
  # AppData/Roaming/Goldberg SteamEmu Saves/<appid>/.
  saveLocations = [
    "AppData/LocalLow/Leikir Studio/Metal Slug Tactics"
    "AppData/Roaming/Goldberg SteamEmu Saves"
  ];

  # Fix the startup black-screen hang. Unity plays the studio/intro movies
  # through Wine's Media Foundation, which Proton implements on top of
  # winegstreamer using its bundled gstreamer plugin tree. The H.264
  # decoder there (libgstlibav.so -> libavcodec.so.58) is NEEDED-linked
  # against a chain of host libraries GE-Proton expects from the Steam
  # Linux Runtime container -- libbz2.so.1.0, libvpx.so.6, libva.so.2,
  # libvdpau.so.1 -- which strom's FHS doesn't carry. Supplying those libs
  # lets the bundled decoder load, the intro plays, and the menu appears.
  targetPkgs = p: [
    p.bzip2
    p.libva
    p.libvdpau
    libvpx6
  ];

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Metal Slug Tactics (Leikir Studio / Dotemu 2024, Unity tactical-RPG roguelike, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "metal-slug-tactics";
  };
}
