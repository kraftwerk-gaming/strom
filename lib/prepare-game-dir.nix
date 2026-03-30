# Creates a script that symlinks game data from the nix store into a
# writable game directory. Files/dirs matching copyGlobs are copied
# (writable), everything else is symlinked (read-only, saves space).
#
# copyGlobs are matched against the relative path from the game root.
# Use shell glob patterns: "*.ini" "*.cfg" "saves" "data/config"
#
# Usage in a game's default.nix:
#   linkGameFiles = callPackage ../../lib/prepare-game-dir.nix {
#     gameFiles = myGameData;
#     copyGlobs = [ "*.ini" "*.cfg" "saves" ];
#   };
#
# Then in the wrapper script:
#   ${linkGameFiles} "$GAMEDIR"
#
{
  writeShellScript,
  gameFiles,
  copyGlobs ? [ ],
}:

let
  # Strip trailing / from patterns (used for readability to indicate dirs)
  cleanGlobs = map (g: builtins.replaceStrings [ "/" ] [ "" ] g) copyGlobs;
  globTests = builtins.concatStringsSep "\n" (map (g: "${g}) return 0 ;;") cleanGlobs);
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

    for f in "$SRC"/* "$SRC"/.[!.]* ; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"

      if should_copy "$base"; then
        # Copy: only if not already a real file/dir (preserve user data)
        if [ ! -e "$GAMEDIR/$base" ] || [ -L "$GAMEDIR/$base" ]; then
          rm -f "$GAMEDIR/$base"
          cp -r "$f" "$GAMEDIR/$base"
          chmod -R u+w "$GAMEDIR/$base"
        fi
      else
        # Symlink: create or replace (including old copies that should now be symlinks)
        ln -sfn "$f" "$GAMEDIR/$base"
      fi
    done
''
