# Proton with pfx_copy patched to symlink DLLs instead of copying.
# Saves ~600MB per game prefix.
{
  proton-ge-bin,
  runCommandLocal,
}:

let
  proton = proton-ge-bin.steamcompattool;
in
runCommandLocal "proton-symlink-pfx" { } ''
  mkdir -p $out
  for f in "${proton}"/*; do
    ln -s "$f" "$out/$(basename "$f")"
  done
  rm "$out/proton"
  cp "${proton}/proton" "$out/proton"
  chmod +wx "$out/proton"
  patch "$out/proton" ${./proton-symlink-pfx.patch}
''
