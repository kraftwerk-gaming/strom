{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  innoextract,
}:

let
  # Stubbs the Zombie in Rebel Without a Pulse (Wideload Games / Aspyr,
  # GOG 2021 re-release v1.0 build 45609). DRM-free Inno Setup 5.6.2
  # installer, distributed as a two-part GOG bundle: a small dispatch
  # .exe alongside a 2.1 GiB ".bin" payload slug. innoextract handles
  # the pair natively when both files live in the same directory.
  #
  # The 2005 retail DVD release was originally packaged here, but its
  # SecuROM v4 disc-authenticity check (raw sector reads + twin-sector
  # signature) walls the game even after the GetDriveType() shim --
  # not faithful to fake on a mounted ISO. The GOG build is a 64-bit
  # remaster with SDL2 + xaudio2 (no OpenAL, no EAX), so the OpenAL
  # bundling and the fake-CD dosdevices setup from the retail recipe
  # are both gone.
  src = fetchIpfs {
    cid = "QmPVRFPrCMh1CiK5FaHUMuq7qBMtF689x9Nw88kEedMfin";
    fallbackUrl = "https://archive.org/details/setup_stubbs_the_zombie_in_rebel_without_a_pulse_1.0_45609-1";
    hash = "sha256-xKVb1358WPvX+L5EteP3ye2v/IhKyTdW6xGnUGeboD4=";
    name = "stubbs-the-zombie-in-rebel-without-a-pulse-gog.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stubbs-the-zombie-in-rebel-without-a-pulse";

  inherit src;

  nativeBuildInputs = [
    p7zip
    innoextract
  ];

  # GOG ships the installer as a .exe + .bin pair inside a directory.
  # The 7z archive preserves that directory; innoextract --gog auto-
  # discovers the .bin slug as long as both files sit next to each
  # other. Most payload entries are tagged with the [en-US] language
  # selector, so an explicit --language=en-US is needed to include
  # them. The engine and all assets land at the extraction root.
  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/7z"
    innoextract --gog --language=en-US -d "$out" \
      "$TMPDIR/7z/Stubbs the Zombie GOG/setup_stubbs_the_zombie_in_rebel_without_a_pulse_1.0_(45609).exe"

    # Drop the GOG.com support shell and any leftover installer
    # scaffolding -- the engine never touches them and they bloat the
    # output store path.
    rm -rf "$out/__redist" "$out/__support" "$out/app" \
      "$out/commonappdata" "$out/tmp" "$out/webcache.zip" 2>/dev/null || true

    test -f "$out/StubbsTheZombie.exe" \
      || { echo "StubbsTheZombie.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/bink2w64.dll" \
      || { echo "bink2w64.dll missing from extracted tree" >&2; exit 1; }
    test -f "$out/SDL2.dll" \
      || { echo "SDL2.dll missing from extracted tree" >&2; exit 1; }
    test -f "$out/maps64/a10_plaza.map" \
      || { echo "maps64/a10_plaza.map missing from extracted tree" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "StubbsTheZombie.exe";

  # The GOG remaster writes saves and config under the user's Documents
  # folder, same path as the retail release.
  saveLocations = [ "Documents/Stubbs The Zombie" ];

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
    description = "Stubbs the Zombie in Rebel Without a Pulse (Wideload Games / Aspyr, GOG 2021 re-release v1.0 build 45609, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stubbs-the-zombie-in-rebel-without-a-pulse";
  };
}
