# Mounts game data via fuse-overlayfs.
#
# Layout:
#   ~/.strom/<game>/                     - upper layer (user saves/configs)
#   ~/.cache/strom/<game>/overlay        - overlay mount point (game runs here)
#   ~/.cache/strom/<game>/work           - overlayfs bookkeeping
#
# Uses patched fuse-overlayfs with squash_to_uid/gid so that nix store
# files (owned by root, 444/555) appear writable and trigger proper
# copy-up to the upper layer on write.
#
# copyGlobs: relative paths to pre-copy to upper layer before mounting.
#   Needed for files that Wine/Proton modifies via mmap or file locks,
#   which fuse-overlayfs can't intercept for copy-up.
#
{
  writeShellScript,
  fuse-overlayfs,
  gameFiles,
  copyGlobs ? [ ],
}:

let
  copyCommands = builtins.concatStringsSep "\n" (
    map (g: ''
      # Copy: ${g}
      if [ ! -e "$UPPER/${g}" ] && [ -e "$SRC/${g}" ]; then
        mkdir -p "$UPPER/$(dirname "${g}")"
        cp -r "$SRC/${g}" "$UPPER/${g}"
        chmod -R u+w "$UPPER/${g}"
      fi
    '') copyGlobs
  );
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

  ${copyCommands}

  # Mount overlay with uid/gid squashing for nix store copy-up
  if ! mountpoint -q "$MERGED" 2>/dev/null; then
    ${fuse-overlayfs}/bin/fuse-overlayfs \
      -o "lowerdir=$SRC,upperdir=$UPPER,workdir=$WORK,squash_to_uid=$(id -u),squash_to_gid=$(id -g)" \
      "$MERGED"
  fi

  echo "$MERGED"
''
