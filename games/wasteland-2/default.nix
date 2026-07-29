{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dwarfs,
}:

let
  # Wasteland 2: Director's Cut (inXile Entertainment, 2015). Unity 5,
  # 64-bit Windows build, driven by this repo's Proton.
  #
  # SOURCE: archive.org item `wasteland-2-dc-linux`, single file
  # `Wasteland-2-DC.flatimage`, 10623337615 bytes. Verified against the
  # item's published checksums (md5 f0336b583c6419a7b7c807ecd24c233f,
  # sha1 7eae0d743c112eb15cfb4ae380c5e003e3d7b930).
  #
  # Despite the item title and the `-linux` identifier this is NOT a
  # native Linux build. The uploader (beokos.kovac@gmail.com, ~70 similar
  # "<title> - LINUX" items) packs WINDOWS games into GameImage FlatImage
  # containers that bundle their own wine-tkg. We keep only the Windows
  # game tree and discard the bundled wine, its prefix and the Arch
  # rootfs; Proton drives the game, per AGENTS.md. The container format
  # and the other titles reachable the same way are written up in
  # docs/flatimage-sources.md.
  #
  # The tree inside is the STEAM build, not GOG: it ships a genuine Valve
  # steam_api64.dll and carries none of GOG's goggame-*.info /
  # goggame-*.hashdb files. A native GOG Linux build
  # (gog_wasteland_2_director_s_cut_*.sh) exists upstream but has no
  # public HTTP mirror (Myrient shut down 2026-03-31 and archive.org's
  # phoenix-games-lab collection has no Wasteland item), so
  # `runtime = "native"` is not reachable from any source found.
  flatimage = fetchIpfs {
    cid = "QmdZ9taVcD6UxC4bXb8vna4SivC9muCMkqJRqdKoXAcUjU";
    fallbackUrl = "https://archive.org/download/wasteland-2-dc-linux/Wasteland-2-DC.flatimage";
    hash = "sha256-fhByexD3ot4YXzF3isb4TqXmCL+S04tPZsGw72ncmrk=";
    name = "Wasteland-2-DC.flatimage";
  };

  # FlatImage layout: the ELF launcher plus its embedded tools come first,
  # then the DwarFS layers, each stored as [uint64 LE size][DwarFS image].
  # For these exact bytes the chain starts at 17030844 and walks to EOF in
  # five layers: Arch base rootfs, a unionfs overlay of extra system
  # packages, wine-tkg, the game, and the fim config. Only the game is
  # wanted. See docs/flatimage-sources.md to re-derive these numbers.
  gameLayerOffset = 880377898;
  gameLayerSize = 9741489424;
  gameDir = "opt/gameimage-games/Wasteland-2-DC/wine/drive_c/Wasteland 2 Director's Cut";
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "wasteland-2";

  ipfsSources = [ flatimage ];

  src = flatimage;

  nativeBuildInputs = [ dwarfs ];

  buildScript = ''
    mkdir -p "$out"

    # dwarfsextract parses sections until end-of-file, so it cannot read a
    # layer in place: the bytes right after the game layer are the next
    # layer's size prefix, which it reads as a section header and aborts
    # on ("truncated section header"). Carve the layer out first, and drop
    # the copy before the game tree is written so peak build disk stays
    # near one payload rather than two.
    dd if="$src" of="$TMPDIR/game.dwarfs" bs=8M status=none \
      iflag=skip_bytes,count_bytes \
      skip=${toString gameLayerOffset} count=${toString gameLayerSize}

    magic=$(dd if="$TMPDIR/game.dwarfs" bs=6 count=1 status=none)
    if [ "$magic" != "DWARFS" ]; then
      echo "no DwarFS magic at offset ${toString gameLayerOffset};" \
        "FlatImage layer layout changed" >&2
      exit 1
    fi

    # dwarfsextract chdirs into -o, so the directory has to exist already.
    mkdir -p "$TMPDIR/tree"
    dwarfsextract -i "$TMPDIR/game.dwarfs" -o "$TMPDIR/tree" \
      --pattern "${gameDir}/**"
    rm -f "$TMPDIR/game.dwarfs"

    cp -r "$TMPDIR/tree/${gameDir}"/. "$out"/
    chmod -R u+w "$out"

    # Windows shortcut pointing at C:\...\WL2.exe; meaningless here.
    rm -f "$out/Launch Wasteland 2 - Director's Cut.lnk"
  '';

  runtime = "proton";
  executable = "WL2.exe";
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  # Derived empirically: launched headless, reached the main menu, then listed
  # everything the engine created under drive_c/users/steamuser. Exactly these
  # two directories appear. Note the save tree is "Wasteland2DC", NOT
  # "Wasteland2" -- the shorter name is the non-Director's-Cut game and using
  # it silently persists an empty directory while real saves stay in the
  # disposable prefix.
  #
  # CAVEAT, deliberately not fixable here: this is a Unity title and its
  # settings are PlayerPrefs, which Unity stores in the REGISTRY under
  # HKCU\Software\inXile Entertainment\Wasteland 2: Director's Cut (verified
  # in the prefix user.reg: Brightness, AntiAliasing, AnisotropicFiltering,
  # AmbientMusicVolume, cInput_* keybinds). saveLocations only relocates
  # directories, so graphics/audio/keybind settings still die with a prefix
  # wipe. Savegames and characters survive, which is what matters.
  saveLocations = [
    "Documents/My Games/Wasteland2DC"
    "AppData/LocalLow/inXile entertainment/Wasteland 2"
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

  meta = {
    description = "Wasteland 2: Director's Cut (inXile Entertainment 2015, Windows build via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "wasteland-2";
  };
}
