{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  msitools,
  unar,
  runCommandLocal,
}:

let
  # Retail UK CD-ROM rip from archive.org/details/pirates_202510. The disc
  # ships an InstallShield/Windows Installer payload (.msi + matching CABs)
  # plus a loose Pirates!.exe at program files/Firaxis Games/Sid Meier's
  # Pirates!/. msiextract handles the CABs cleanly; we copy that tree out
  # and overlay the no-CD patch on top.
  gameISO = fetchIpfs {
    cid = "Qma2AyXzbaDPJq2Ztx2ahETHESGt8DHDBv2sFoUrdC8mzE";
    fallbackUrl = "https://archive.org/download/pirates_202510/PIRATES.iso";
    hash = "sha256-/d2LBFCHq3Wys8ictSUo5+ZWyJcVLMbAg2RzJcr9dPM=";
    name = "pirates.iso";
  };

  # gamecopyworld.com Pirates! v1.02 [MULTI] No-CD/Fixed EXE (BarryB,
  # 2005-09-18). Solid RAR with a single Pirates!.exe replacement that
  # bypasses the SafeDisc disc check; sized identical to the patched
  # Firaxis 1.02 exe (3325952 bytes).
  noCdArchive = fetchIpfs {
    cid = "Qma9Kf3XB5HwjpAedVfgWW2K6AprpufG2PTDJ3mZsP38DA";
    fallbackUrl = "https://ipfs.io/ipfs/Qma9Kf3XB5HwjpAedVfgWW2K6AprpufG2PTDJ3mZsP38DA";
    hash = "sha256-ypTMMJk/lVbNjaLBQd97ts7+1C3Fmp26Dn/Vebtasu0=";
    name = "pirates-nocd.rar";
  };

  gameData =
    runCommandLocal "sid-meiers-pirates-data"
      {
        nativeBuildInputs = [
          p7zip
          msitools
          unar
        ];
      }
      ''
        mkdir -p /tmp/iso /tmp/msi-work
        7z x -y ${gameISO} -o/tmp/iso \
          "Sid Meier's Pirates!.msi" \
          'Progra~1.cab' \
          'Disk2A~1.cab' \
          'Language.cab' \
          "program files/Firaxis Games/Sid Meier's Pirates!/Pirates!.exe"

        # msiextract resolves CAB references relative to the MSI's directory
        cp "/tmp/iso/Sid Meier's Pirates!.msi" \
           /tmp/iso/Progra~1.cab \
           '/tmp/iso/Disk2A~1.cab' \
           /tmp/iso/Language.cab \
           /tmp/msi-work/

        cd /tmp/msi-work
        msiextract -C extracted "Sid Meier's Pirates!.msi"

        cp -r "extracted/Program Files/Firaxis Games/Sid Meier's Pirates!"/. "$out"/
        chmod -R u+w "$out"

        # The MSI doesn't ship the engine executable — it's loose on the
        # disc. Drop in the retail v1.0.2.0 binary from the ISO so the
        # no-CD overlay below replaces a complete install.
        install -m 0644 \
          "/tmp/iso/program files/Firaxis Games/Sid Meier's Pirates!/Pirates!.exe" \
          "$out/Pirates!.exe"

        # Overlay the no-CD patched Pirates!.exe + readme. unar handles the
        # solid RAR cleanly without the unfree-licensed unrar binary; it
        # creates a wrapper directory derived from the input filename so we
        # glob for the extracted folder rather than hardcoding the prefix.
        mkdir -p /tmp/nocd
        unar -o /tmp/nocd ${noCdArchive}
        nocd_dir=$(echo /tmp/nocd/*/)
        install -m 0644 "$nocd_dir/Pirates!.exe" "$out/Pirates!.exe"
        install -m 0644 "$nocd_dir/readme.txt"   "$out/nocd-readme.txt"

        rm -rf /tmp/iso /tmp/msi-work /tmp/nocd
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sid-meiers-pirates";

  ipfsSources = [
    gameISO
    noCdArchive
  ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "Pirates!.exe";

  saveLocations = [ "Documents/My Games" ];

  copyGlobs = [
    "Saves/"
    "custom/"
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Sid Meier's Pirates! (Firaxis 2004 retail v1.02 with no-CD patch, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sid-meiers-pirates";
  };
}
