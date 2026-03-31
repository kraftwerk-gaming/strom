{
  lib,
  pkgs,
  fetchurl,
  p7zip,
  rsync,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };

  vanillara = pkgs.vanillara;

  alliedIso = fetchurl {
    url = "https://archive.org/download/cnc-red-alert/redalert_allied.iso";
    hash = "sha256-Npx6hSTJetFlcb/Fi3UQEGuP0iLk9LIrRmAI7WgEtdw=";
    name = "redalert-allied.iso";
  };

  sovietIso = fetchurl {
    url = "https://archive.org/download/cnc-red-alert/redalert_soviets.iso";
    hash = "sha256-aJGr+w1BaGaLwX/pU0lMmu6Cgn9pZ2D/aVafBdtds2Q=";
    name = "redalert-soviet.iso";
  };

  # Build a combined binary+data tree so vanillara finds data at ../share/vanillara/
  vanillaraWithData = pkgs.runCommandLocal "vanillara-with-data" {
    nativeBuildInputs = [
      p7zip
      rsync
    ];
  } ''
    # Copy vanillara binary (needs to be real file, not symlink, for realpath resolution)
    rsync --archive --mkpath --chmod=a+w ${vanillara}/ $out/

    # Extract game data
    mkdir -p /tmp/allied /tmp/soviet
    cd /tmp/allied && 7z x ${alliedIso} MAIN.MIX INSTALL/REDALERT.MIX -aoa
    cd /tmp/soviet && 7z x ${sovietIso} MAIN.MIX -aoa

    # Install to share/vanillara/ (default Data_Path)
    mkdir -p $out/share/vanillara/allied $out/share/vanillara/soviet
    cp /tmp/allied/INSTALL/REDALERT.MIX $out/share/vanillara/redalert.mix
    cp /tmp/allied/MAIN.MIX $out/share/vanillara/allied/main.mix
    cp /tmp/soviet/MAIN.MIX $out/share/vanillara/soviet/main.mix

    chmod 755 $out
  '';
in
mkGame {
  name = "command-conquer-red-alert";

  src = vanillaraWithData;
  buildScript = ''
    mkdir -p "$out"
    echo "command-conquer-red-alert" > "$out/.placeholder"
  '';

  runtime = "native";

  runScript = ''
    export XDG_CONFIG_HOME="$GAMEDIR/.config"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --force-grab-cursor -s 0.5 --expose-wayland -- \
      ${vanillaraWithData}/bin/vanillara
  '';

  meta = {
    description = "Command & Conquer: Red Alert (Vanilla Conquer, native)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "command-conquer-red-alert";
  };
}
