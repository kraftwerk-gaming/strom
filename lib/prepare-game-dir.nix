{
  writeShellScript,
  gameFiles,
  copyGlobs ? [ ],
}:

let
  cleanGlobs = map (g: builtins.replaceStrings [ "/" ] [ "" ] g) copyGlobs;
  globTests = builtins.concatStringsSep "\n" (map (g: "          ${g}) return 0 ;;") cleanGlobs);
in
writeShellScript "prepare-game-dir" ''
    set -euo pipefail
    GAMEDIR="$1"
    SRC="${gameFiles}"

    should_copy() {
      local rel="$1"
      case "$rel" in
  ${globTests}
      esac
      return 1
    }

    # Replace destination with a symlink, removing whatever was there
    force_symlink() {
      local target="$1" dest="$2"
      if [ -d "$dest" ] && [ ! -L "$dest" ]; then
        rm -rf "$dest"
      fi
      ln -sfTn "$target" "$dest"
    }

    link_tree() {
      local src="$1" dst="$2" prefix="$3"
      mkdir -p "$dst"
      for f in "$src"/* "$src"/.[!.]* ; do
        [ -e "$f" ] || continue
        local base rel
        base="$(basename "$f")"
        if [ -n "$prefix" ]; then
          rel="$prefix/$base"
        else
          rel="$base"
        fi

        if should_copy "$rel"; then
          # Should be a writable copy
          if [ ! -e "$dst/$base" ] || [ -L "$dst/$base" ]; then
            rm -f "$dst/$base" 2>/dev/null || rm -rf "$dst/$base"
            cp -r "$f" "$dst/$base"
            chmod -R u+w "$dst/$base"
          fi
          # Existing real file/dir: preserve (user data)
        elif [ -d "$f" ] && [ ! -L "$f" ]; then
          # Source is a directory, not in copyGlobs → recurse
          if [ -L "$dst/$base" ]; then
            # Dest is a symlink (stale from previous config) → remove so we can recurse
            rm -f "$dst/$base"
          fi
          link_tree "$f" "$dst/$base" "$rel"
        else
          # Source is a file → symlink
          force_symlink "$f" "$dst/$base"
        fi
      done
    }

    link_tree "$SRC" "$GAMEDIR" ""
''
