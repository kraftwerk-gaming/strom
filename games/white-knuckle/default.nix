{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # White Knuckle (Dark Machine Games 2025 Early Access). Source is the
  # repack-games "White.Knuckle.Build.23023450.zip" mirrored on
  # pixeldrain (sha256-7pgkcbck9GoUvA7eGB0FoI41tnLI27R4qiom0u+HZvs=,
  # 2.6 GiB). Pre-installed Steam build with bundled steam_api.dll;
  # plain Unity 6 IL2CPP layout, no Sentry/crashpad shenanigans.
  src = fetchIpfs {
    cid = "QmVYKSCB9HiSVZ3ujrhBSK6VVixgofuCh9tRccLLL7c88R";
    fallbackUrl = "https://pixeldrain.com/api/file/dYF1mtbM";
    hash = "sha256-7pgkcbck9GoUvA7eGB0FoI41tnLI27R4qiom0u+HZvs=";
    name = "white-knuckle.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "white-knuckle";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Repack zip layout: White.Knuckle.Build.23023450/{White Knuckle.exe,
  # White Knuckle_Data/, MonoBleedingEdge/, UnityPlayer.dll,
  # UnityCrashHandler64.exe, ...}. Drop the SKIDROWRELOADED.COM.txt
  # advert dropped by the repacker.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/White.Knuckle.Build.23023450/"* "$out"/
    rm -f "$out/SKIDROWRELOADED.COM.txt"
  '';

  runtime = "proton";
  executable = "White Knuckle.exe";

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
    description = "White Knuckle (Dark Machine Games 2025 Early Access, build 23023450, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "white-knuckle";
  };
}
