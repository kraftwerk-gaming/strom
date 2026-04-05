# Proton with pfx_copy patched to symlink DLLs instead of copying.
# Saves ~600MB per game prefix.
{ proton-ge-bin }:

(proton-ge-bin.overrideAttrs {
  pname = "proton-symlink-pfx";
  dontUnpack = false;
  patches = [ ./proton-symlink-pfx.patch ];
  installPhase = ''
    runHook preInstall
    echo "proton-ge-bin should not be installed into environments." > $out
    mkdir $steamcompattool
    cp -r . $steamcompattool/
    runHook postInstall
  '';
}).steamcompattool
// {
  meta.mainProgram = "proton";
}
