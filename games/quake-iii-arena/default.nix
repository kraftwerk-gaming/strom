{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Original 1999 id Software retail CD ISO. Already includes a fully
  # extracted Quake3/ tree alongside the InstallShield installer, so we
  # can copy that folder verbatim and skip running setup.
  src = fetchIpfs {
    cid = "QmQqGY8a1xXKaeybvdS4uJ2mHrX4bbqBhxqq8NEDjBFyep";
    fallbackUrl = "https://archive.org/download/quake-3_202509/QUAKE3.ISO";
    hash = "sha256-J/9RoIVCtabIwtkocM2qJF6N8JnlIiHk5OLkGuq7yXo=";
    name = "quake-3-arena.iso";
  };

  # Official Q3 1.32 point release. Adds pak2.pk3 through pak8.pk3,
  # which ioquake3 requires (the CD only ships pak0/pak1). Freely
  # redistributable. Self-extracting Makeself shell archive — we
  # invoke its `--target/--noexec` flags to dump the tree without
  # running the bundled installer.
  pointRelease = fetchIpfs {
    cid = "QmWWyL7DD4H8wg43q2taTCPBF26CY81ELDbpp68LkcQFiD";
    fallbackUrl = "https://archive.org/download/quake-3-patches/Files%2FPatches%2FPoint%20Release%201.32%2Flinuxq3apoint-1.32.x86.run";
    hash = "sha256-akAYu5OMcbRW6nhWMAGkOehORjCFIDHZJ7K6qA66lCI=";
    name = "quake-3-arena-point-release-1.32.run";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "quake-iii-arena";

  ipfsSources = [
    src
    pointRelease
  ];
  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/iso" 'Quake3/*'
    cp -r "$TMPDIR/iso/Quake3"/. "$out"/
    chmod -R u+w "$out"
    # Lay the 1.32 point release pak2..8 over baseq3/ and the missionpack
    # paks over missionpack/ so ioquake3 sees a complete Quake3 1.32
    # install. Run Makeself's self-extract into TMPDIR — its bundled
    # setup.sh exits non-zero on Nix because it tries gtk-update-icon-cache,
    # but the data is already unpacked by then.
    cp ${pointRelease} "$TMPDIR/q3pr.run"
    chmod +x "$TMPDIR/q3pr.run"
    "$TMPDIR/q3pr.run" --target "$TMPDIR/q3pr" --keep --noexec || true
    cp -f "$TMPDIR/q3pr/baseq3"/pak[2-8].pk3 "$out/baseq3"/
    if [ -d "$out/missionpack" ]; then
      cp -f "$TMPDIR/q3pr/missionpack"/pak[1-9].pk3 "$out/missionpack"/ 2>/dev/null || true
    fi
    # Patch defaults into the shipped q3config.cfg. The engine only
    # reads this when the user's per-home config doesn't exist yet, so
    # any change made in-game (which writes to fs_homepath) wins on
    # subsequent launches. Sets the placeholder cl_cdkey (the engine
    # doesn't validate, just that it's non-empty) and pins the default
    # renderer to 1920x1080 fullscreen.
    {
      printf 'seta cl_cdkey "AAAAAAAAAAAAAAAA"\n'
      printf 'seta r_mode "-1"\n'
      printf 'seta r_customwidth "1920"\n'
      printf 'seta r_customheight "1080"\n'
      printf 'seta r_fullscreen "1"\n'
    } >> "$out/baseq3/q3config.cfg"
  '';

  copyGlobs = [
    "baseq3/q3config.cfg"
  ];

  # Use the open-source ioquake3 engine instead of the original
  # quake3.exe — ioquake3 skips the CD check that triggers on single
  # player start, fixes the high-resolution renderer, and removes the
  # need for Proton entirely. It still loads the retail pak0.pk3 +
  # config we ship in baseq3/.
  runtime = "native";
  executable = lib.getExe pkgs.ioquake3;
  # mk-game.nix `cd "$GAMEDIR"` before launch, so a relative
  # fs_basepath of "." points the engine at our overlaid install dir
  # (where pak0..pak8.pk3 live). fs_homepath is left at ioquake3's
  # ~/.q3a default — ioquake3 doesn't take an env var for it and
  # mk-game.nix shell-escapes executableArgs (so a literal
  # `$STROM_GAMEDIR` would not expand).
  executableArgs = [
    "+set"
    "fs_basepath"
    "."
  ];

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
    description = "Quake III Arena (id Software 1999, retail CD v1.11, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "quake-iii-arena";
  };
}
