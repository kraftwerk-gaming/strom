# fuse-overlayfs wrapperModule (raw module source).
#
# Mounts game data via fuse-overlayfs with an overlay layout:
#   upperdir (user saves/configs) + lowerdir (nix store game data) -> merged
#
# Uses patched fuse-overlayfs with squash_to_uid/gid so nix store files
# (owned by root, 444/555) appear writable and trigger proper copy-up.
#
# Usage: the wrapped binary is called as: fuse-overlayfs <gamedir>
# It prints the merged mount path to stdout.
{ config, lib, ... }:
{
  _class = "wrapper";

  options = {
    gameFiles = lib.mkOption {
      type = lib.types.package;
      description = "Game data derivation used as the read-only lower layer.";
    };

    copyGlobs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Glob patterns for files to pre-copy to the upper layer before
        mounting (for files Wine/Proton modifies via mmap or file locks).
      '';
    };
  };

  config = {
    package = config.pkgs.callPackage ../pkgs/fuse-overlayfs.nix { };

    preHook =
      let
        copyCommands = builtins.concatStringsSep "\n" (
          map (g: ''
            if [ ! -e "$UPPER/${g}" ] && [ -e "$SRC/${g}" ]; then
              mkdir -p "$UPPER/$(dirname "${g}")"
              cp -r "$SRC/${g}" "$UPPER/${g}"
              chmod -R u+w "$UPPER/${g}"
            fi
          '') config.copyGlobs
        );
      in
      ''
        UPPER="$1"
        shift
        GAMENAME="$(basename "$UPPER")"
        CACHEDIR="''${HOME:-.}/.cache/strom/$GAMENAME"
        MERGED="$CACHEDIR/overlay"
        WORK="$CACHEDIR/work"
        SRC="${config.gameFiles}"
        mkdir -p "$UPPER" "$MERGED" "$WORK"

        # Defensive: sweep orphan overlayfs whiteouts from the upper layer.
        #
        # When something runs `rm -rf` against the merged mount (or against
        # the upper layer while still mounted), overlayfs masks lower-layer
        # entries by writing mode-0000 char-device 0,0 nodes into the upper
        # layer. After unmount those whiteouts persist and, on the next
        # mount, hide the lower layer so the game directory looks empty.
        # Strom state dirs never legitimately contain char devices, so it
        # is safe to delete any we find. We additionally require -perm 0
        # to avoid touching a hypothetical user-created device node.
        whiteout_count=$(find "$UPPER" -mindepth 1 -type c -perm 0 2>/dev/null | wc -l)
        if [ "$whiteout_count" -gt 0 ]; then
          echo "fuse-overlayfs: sweeping $whiteout_count orphan whiteout(s) from $UPPER" >&2
          find "$UPPER" -mindepth 1 -type c -perm 0 -delete 2>/dev/null || true
        fi

        ${copyCommands}

        if mountpoint -q "$MERGED" 2>/dev/null; then
          echo "$MERGED"
          exit 0
        fi

        # OVERLAYFS_ARGS: runtime-injected fuse-overlayfs flags, word-split
        # and spliced in just before the mount point. Useful for ad-hoc
        # debugging (e.g. OVERLAYFS_ARGS="-d") or extra mount options.
        read -ra _overlayfs_extra <<< "''${OVERLAYFS_ARGS:-}"

        set -- \
          -o "lowerdir=$SRC,upperdir=$UPPER,workdir=$WORK,squash_to_uid=$(id -u),squash_to_gid=$(id -g)" \
          "''${_overlayfs_extra[@]}" \
          "$MERGED"
      '';

    postHook = ''
      echo "$MERGED"
    '';
  };
}
