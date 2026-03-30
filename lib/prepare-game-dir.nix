# Mounts game data via fuse-overlayfs.
#
# Layout:
#   ~/.strom/<game>/                     - upper layer (user saves/configs)
#   ~/.cache/strom/<game>/overlay        - overlay mount point (game runs here)
#   ~/.cache/strom/<game>/work           - overlayfs bookkeeping
#
# copyGlobs: files pre-copied to upper layer (Wine can't copy-up via fuse)
#
{
  writeShellScript,
  fuse-overlayfs,
  gameFiles,
  copyGlobs ? [ ],
}:

let
  cleanGlobs = map (g: builtins.replaceStrings [ "/" ] [ "" ] g) copyGlobs;
  globTests = builtins.concatStringsSep "\n" (map (g: "        ${g}) return 0 ;;") cleanGlobs);
in
writeShellScript "prepare-game-dir" ''
    set -euo pipefail
    GAMENAME="$(basename "$1")"
    UPPER="$1"
    CACHEDIR="''${HOME:-.}/.cache/strom/$GAMENAME"
    MERGED="$CACHEDIR/overlay"
    WORK="$CACHEDIR/work"
    SRC="${gameFiles}"
    mkdir -p "$UPPER" "$MERGED" "$WORK"

    should_copy() {
      case "$1" in
  ${globTests}
      esac
      return 1
    }

    # Pre-copy files matching copyGlobs into upper layer
    for f in "$SRC"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      should_copy "$base" || continue
      [ -e "$UPPER/$base" ] && continue
      cp -r "$f" "$UPPER/$base"
      chmod -R u+w "$UPPER/$base"
    done

    # Mount overlay
    if ! mountpoint -q "$MERGED" 2>/dev/null; then
      ${fuse-overlayfs}/bin/fuse-overlayfs \
        -o lowerdir="$SRC",upperdir="$UPPER",workdir="$WORK" \
        "$MERGED"
    fi

    echo "$MERGED"
''
