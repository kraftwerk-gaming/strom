# Proton with pfx_copy patched to always use symlinks instead of copies.
# This saves ~600MB per game prefix since DLLs stay as symlinks to the
# nix store instead of being copied.
{
  proton-ge-bin,
  runCommandLocal,
  python3,
}:

let
  proton = proton-ge-bin.steamcompattool;
in
runCommandLocal "proton-symlink-pfx"
  {
    nativeBuildInputs = [ python3 ];
  }
  ''
    mkdir -p $out

    # Symlink everything from original proton
    for f in "${proton}"/*; do
      ln -s "$f" "$out/$(basename "$f")"
    done

    # Replace the proton script with our patched version
    rm "$out/proton"
    cp "${proton}/proton" "$out/proton"
    chmod +w "$out/proton"
    python3 ${./patch-proton-pfx-copy.py} "$out/proton"
    chmod +x "$out/proton"
  ''
