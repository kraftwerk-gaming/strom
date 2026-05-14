{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Mr Abandonware repack: 7z containing "Prey Installer.exe", an
  # InstallForge SFX that itself is just an LZMA-solid 7z archive whose
  # entry names are base64-of-UTF16LE-encoded (PREY/PREY.exe, PREY/base/
  # *.pk4 once decoded). 7z extracts the literal base64 names; we
  # rename them back to UTF-8 in buildScript.
  src = fetchIpfs {
    cid = "QmYEridBgpmaBEpp9tKmKaBnrvEnXssktr2USi5NVRFs8X";
    fallbackUrl = "https://archive.org/download/prey-mr-abandonware/Prey.7z";
    hash = "sha256-I+NGCmT4ImT81vpJuw9oX3XVq3IDBTBrwMzncADOmXk=";
    name = "prey-2006.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "prey-2006";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # Two-stage extraction: outer 7z yields "Prey Installer.exe"; the SFX
  # body is itself a 7z archive (offset 998421). 7z handles both. After
  # extraction every path component name is base64(UTF-16LE) of the
  # original Windows name; the installer also drops "empty.empty"
  # placeholders whose path components are joined with a literal
  # backslash (e.g. `UABSAEUAWQA=\empty.empty`) -- drop those first, then
  # walk the tree bottom-up and decode the remaining components.
  buildScript = ''
    mkdir -p "$TMPDIR/outer" "$TMPDIR/inner" "$out"
    7z x -y -o"$TMPDIR/outer" "$src" "Prey Installer.exe"
    7z x -y -o"$TMPDIR/inner" "$TMPDIR/outer/Prey Installer.exe"

    # Drop the installer's empty-directory placeholders. Their names
    # contain literal backslashes which break base64 decode.
    find "$TMPDIR/inner" -name '*empty.empty' -delete

    # Decode base64(UTF-16LE) names bottom-up so leaves are renamed
    # before their parent directories. All real filenames are ASCII so
    # UTF-16LE collapses to "char NUL char NUL ..." -- strip the NULs
    # with tr instead of pulling in iconv (not in stdenv's default
    # nativeBuildInputs). Only attempt rename when the basename is a
    # valid base64 token (matches [A-Za-z0-9+/=]+).
    find "$TMPDIR/inner" -depth -mindepth 1 | while IFS= read -r path; do
      dir=$(dirname "$path")
      base=$(basename "$path")
      case "$base" in
        *[!A-Za-z0-9+/=]*) continue ;;
      esac
      decoded=$(printf '%s' "$base" | base64 -d 2>/dev/null | tr -d '\0' || true)
      if [ -n "$decoded" ] && [ "$decoded" != "$base" ]; then
        mv "$path" "$dir/$decoded"
      fi
    done

    cp -r "$TMPDIR/inner/PREY"/. "$out"/
  '';

  runtime = "proton";
  executable = "PREY.exe";

  saveLocations = [ "Documents/My Games/PREY" ];

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
    description = "Prey (2006 Human Head Studios, id Tech 4, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "prey-2006";
  };
}
