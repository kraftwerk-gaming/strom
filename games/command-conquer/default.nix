{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gamescope,
  p7zip,
}:

let

  vanillatd = pkgs.vanillatd;

  gdiIso = fetchIpfs {
    cid = "Qme6kRZLgxGMEDaNUwCis9Wp7j6DWys4EWoDX8ePSiPh5N";
    fallbackUrl = "https://archive.org/download/cnc-dos-eng-v-1.22/C%26C%20DOS%20ENG%20v1.22%20Disk%201%20-%20GDI.iso";
    hash = "sha256-kp12oZiKs2Z4c97LTRd1ORnIwvil1Me/3jhSWj+naUs=";
    name = "cnc-gdi.iso";
  };

  nodIso = fetchIpfs {
    cid = "QmSob3MrZzftZrvXRotQgGpgyqPdvMCXLnBQWWoKgXZyem";
    fallbackUrl = "https://archive.org/download/cnc-dos-eng-v-1.22/C%26C%20DOS%20ENG%20v1.22%20Disk%202%20-%20Nod.iso";
    hash = "sha256-cH/ob8JqcT/0VjrS1WObClNHbMLrZWr5d5thFALwxdA=";
    name = "cnc-nod.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "command-conquer";

  ipfsSources = [
    gdiIso
    nodIso
  ];
  src = gdiIso;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"

    # Extract MIX files from both discs
    cd /tmp
    mkdir -p gdi nod
    cd gdi && 7z x ${gdiIso} -aoa && cd ..
    cd nod && 7z x ${nodIso} -aoa && cd ..

    # Copy all MIX files (lowercase for vanillatd)
    for f in gdi/*.MIX; do
      name=$(basename "$f" | tr '[:upper:]' '[:lower:]')
      cp "$f" "$out/$name"
    done

    # Copy Nod movies (different from GDI)
    cp nod/MOVIES.MIX "$out/movies_nod.mix"

    # Copy speech from subdirectory
    cp gdi/AUD1/SPEECH.MIX "$out/speech.mix"

    # Copy transit and local from install dir
    cp gdi/INSTALL/TRANSIT.MIX "$out/transit.mix"
    cp gdi/INSTALL/LOCAL.MIX "$out/local.mix"

    rm -rf gdi nod
  '';

  runtime = "native";

  runScript = ''
    export XDG_CONFIG_HOME="$GAMEDIR/.config"

    # Write vanillatd.ini so it finds data in the overlay and saves to GAMEDIR
    cat > "$GAMEDIR/vanillatd.ini" <<EOF
    [Paths]
    DataPath=$GAMEDIR
    UserPath=$GAMEDIR
    EOF

    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --force-grab-cursor -s 0.5 --expose-wayland -- \
      ${vanillatd}/bin/vanillatd -cd"$GAMEDIR"
  '';

  meta = {
    description = "Command & Conquer: Tiberian Dawn (Vanilla Conquer, native)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer";
  };
}
