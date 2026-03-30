# Mounts game data via fuse-overlayfs with pre-copied writable files.
# Files matching copyGlobs are copied to the upper layer BEFORE mounting,
# so Wine/Proton can modify them (fuse-overlayfs doesn't support copy-up
# with mmap/file locks that Wine uses).
#
# Layout:
#   ~/.strom/<game>/        - overlay mount point (game runs here)
#   ~/.strom/<game>/.data/  - upper layer (writable files)
#   ~/.strom/<game>/.work/  - overlayfs bookkeeping
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
    GAMEDIR="$1"
    UPPER="$GAMEDIR/.data"
    WORK="$GAMEDIR/.work"
    SRC="${gameFiles}"
    mkdir -p "$UPPER" "$WORK"

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
      # Only copy if not already in upper (preserve user data)
      [ -e "$UPPER/$base" ] && continue
      cp -r "$f" "$UPPER/$base"
      chmod -R u+w "$UPPER/$base"
    done

    # Mount overlay
    if ! mountpoint -q "$GAMEDIR" 2>/dev/null; then
      ${fuse-overlayfs}/bin/fuse-overlayfs \
        -o lowerdir="$SRC",upperdir="$UPPER",workdir="$WORK" \
        "$GAMEDIR"
    fi
''
