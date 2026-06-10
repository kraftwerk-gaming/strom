{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  unar,
}:

let
  # The Witness (Thekla / Jonathan Blow, 2016). First-person open-world
  # puzzle game on Thekla's in-house engine (Direct3D 11). Windows-only on
  # GOG (the Linux build was never shipped to GOG), so runtime = "proton".
  # The D3D11 renderer maps cleanly onto DXVK -- do NOT force wined3d.
  #
  # SOURCE: GOG offline installer, slug "the_witness", GOG version 2.0.0.3.
  # Inno Setup 5.5.0 (unicode), three parts:
  #   setup_the_witness_2.0.0.3.exe        (   30,570,848 bytes)
  #   setup_the_witness_2.0.0.3-1.bin      (4,194,304,000 bytes)
  #   setup_the_witness_2.0.0.3-2.bin      (  161,227,709 bytes)
  # (The later "21-12-2017" build was only ever mirrored as a corrupt repack
  # whose .bin slices fail innoextract's zlib stream; 2.0.0.3 is the genuine
  # GOG offline installer.) innoextract reassembles the split installer only
  # when the .exe and its -N.bin slices sit in the same directory, so all
  # three parts are bundled into one tarball (cf. arx-fatalis) that fetchIpfs
  # treats as a single artifact. This installer stores the payload as
  # RAR-compressed GOG-Galaxy chunks, so innoextract needs `unar` on PATH to
  # reassemble them; it then drops the game under `game/` (witness64_d3d11.exe
  # + data/ + data-pc.zip + the engine DLLs).
  src = fetchIpfs {
    cid = "QmZVcwjeVerNMGy4MtNxKT4m2bwkusjTi6yWgfF66uq5dW";
    fallbackUrl = "magnet:?xt=urn:btih:464f4e04852921cb6922ddb0442fbb375bb0138b&dn=The.Witness-GOG";
    hash = "sha256-GiRFtaJWhnoKUhbtt5hR2JfwNq4IbJLK7qZ97EI/RwA=";
    name = "the-witness-gog-2.0.0.3.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-witness";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    pkgs.gnutar
    innoextract
    unar
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/inst" "$TMPDIR/ext"
    # Unpack the bundled installer parts side by side; innoextract then reads
    # the .exe header and pulls the payload from the adjacent -1.bin / -2.bin
    # slices in the same directory. The torrent nests the installer under
    # the_witness/, so flatten via --strip-components. `unar` (on PATH via
    # nativeBuildInputs) lets innoextract decompress the RAR Galaxy chunks.
    tar -xf "$src" -C "$TMPDIR/inst" --strip-components=1 \
      'the_witness/setup_the_witness_2.0.0.3.exe' \
      'the_witness/setup_the_witness_2.0.0.3-1.bin' \
      'the_witness/setup_the_witness_2.0.0.3-2.bin'
    innoextract --gog -d "$TMPDIR/ext" "$TMPDIR/inst/setup_the_witness_2.0.0.3.exe"

    # 2.0.0.3 lays the game out under game/ (app/ holds only the GOG installer
    # helper DLL). Promote game/ to the install root and drop GOG/redist cruft.
    # KEEP steam_api{,64}.dll: witness64_d3d11.exe has a *static* import of
    # steam_api64.dll in its PE import table (GOG ships a no-op stub of it),
    # so removing it makes wine's loader_init fail every import with
    # STATUS_DLL_NOT_FOUND (c0000135) and the process exits before DXVK ever
    # produces a frame -- no menu, ~3s after fsync init.
    cp -a "$TMPDIR/ext/game"/. "$out"/
    rm -f "$out/goggame-"* "$out/webcache.zip" \
          "$out/language_setup.ini" "$out/language_setup.png"
  '';

  runtime = "proton";

  # GOG ships two binaries: witness64_d3d11.exe (D3D11, the default) and a
  # legacy witness_d3d11.exe (32-bit). The 64-bit D3D11 build is the one the
  # launcher runs; DXVK translates its D3D11 calls.
  executable = "witness64_d3d11.exe";

  # PCGamingWiki / community: the engine writes saves + settings under the
  # Windows LocalLow tree (AppData/LocalLow/The Witness), separate from the
  # binary, so they persist via $STROM_GAMEDIR without an overlay redirect.
  saveLocations = [ "AppData/LocalLow/The Witness" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "The Witness (Thekla 2016, first-person puzzle, D3D11/DXVK, GOG via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-witness";
  };
}
