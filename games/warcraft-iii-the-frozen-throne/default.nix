{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
}:

let
  gameSrc = fetchIpfs {
    cid = "QmSPPz3Nm75XfhNcQKPUugdhJ7eADRGBetDMP4W96Wmg56";
    fallbackUrl = "https://archive.org/download/warcraft-iii-1.26a-iccup/Warcraft%20III%20%281.26a%20%2B%20ICCup%29.rar";
    hash = "sha256-NLBToTPBZjq+RprY3JGnWSLhfcnsFK8INS0riSQxTrw=";
    name = "warcraft-iii-1.26a.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "warcraft-iii-the-frozen-throne";

  src = gameSrc;
  ipfsSources = [ gameSrc ];

  nativeBuildInputs = [ libarchive ];

  buildScript = ''
    mkdir -p "$out"
    bsdtar xf ${gameSrc} -C /tmp
    cp -r "/tmp/Warcraft III/"* "$out/"
    rm -rf /tmp/Warcraft\ III

    # Remove ICCup launcher and BNet updater
    rm -rf "$out/ICCup"
    rm -f "$out/BNUpdate.exe"

    # Remove movie files (Wine can't render WC3 cinematics, known limitation)
    rm -f "$out/Movies"/*.mpq

    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # save/<Profile>/Campaigns.w3{p,v} + *.w3z replays next to its binary,
  # not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "war3.exe";

  env = {
    PROTON_USE_WINED3D = "1";
  };

  preRun = ''
    # Write 1920x1080 resolution directly to user.reg
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    if [ -f "$USERREG" ] && ! grep -q 'reswidth' "$USERREG"; then
      cat >> "$USERREG" <<'EOF'

    [Software\\Blizzard Entertainment\\Warcraft III\\Video]
    "reswidth"=dword:00000780
    "resheight"=dword:00000438
    EOF
    fi
  '';

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
    description = "Warcraft III: Reign of Chaos + The Frozen Throne v1.26a (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "warcraft-iii-the-frozen-throne";
  };
}
