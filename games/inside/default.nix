{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  innoextract,
}:

let
  # INSIDE (Playdead, 2016). Windows-only on GOG (no Linux build). GOG
  # offline installer v10 (build 16955); Inno Setup split into two parts:
  # setup_inside_10_(16955).exe (894 KiB header) and
  # setup_inside_10_(16955)-1.bin (~1.57 GiB data). Both parts are bundled
  # into a single tarball so fetchIpfs can treat them as one artifact.
  # innoextract --gog reassembles the parts automatically when the .bin is
  # in the same directory as the .exe.
  src = fetchIpfs {
    cid = "QmavAbnNuAu4EoCiPxDwbec5S9V4Q6dVY68qncg2ao1J6R";
    fallbackUrl = "https://archive.org/download/inside-playdead-gog/inside-gog-v10-16955.tar";
    hash = "sha256-l5QoIYwXx8+alFc4p94VUtZ09AEdBEplETbOaILd2+E=";
    name = "inside-gog-v10-16955.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "inside";

  inherit src;

  nativeBuildInputs = [
    gnutar
    innoextract
  ];

  # Untar the two installer parts into a staging dir (innoextract needs the
  # .exe and .bin side-by-side), then extract the app tree. The install root
  # contains: INSIDE.exe (16 MiB Unity executable), INSIDE_Data/, plus GOG
  # helpers and bundled msvcp/msvcr DLLs.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/gog"
    tar -xf "$src" -C "$TMPDIR/gog"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/gog/setup_inside_10_(16955).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    rm -rf "$out/__redist" "$out/__support" "$out/webcache.zip"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/goggame-"*.dll
  '';

  runtime = "proton";

  executable = "INSIDE.exe";

  # %APPDATA%\Playdead\Inside (confirmed via PCGamingWiki — Roaming, not
  # LocalLow). Holds Game2.sav and Steam cloud saves on Windows.
  saveLocations = [ "AppData/Roaming/Playdead/Inside" ];

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
    description = "INSIDE (Playdead 2016, puzzle-platformer via Proton, GOG v10 build 16955)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "inside";
  };
}
