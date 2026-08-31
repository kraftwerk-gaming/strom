{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  src = fetchIpfs {
    cid = "QmcNc9smjop4rKYUooR1WtUiB54XwGuYqc4xBiXhxY1gjt";
    fallbackUrl = "https://ipfs.io/ipfs/QmcNc9smjop4rKYUooR1WtUiB54XwGuYqc4xBiXhxY1gjt";
    hash = "sha256-d1btw4gcVmU0nf2r0i/+b6zaau0p6AKEyUTEaUGXU3o=";
    name = "animal-well-ankergames.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "animal-well";

  inherit src;

  nativeBuildInputs = [ unar ];

  # AnkerGames RAR5 layout: Animal Well/Animal Well.exe + steam_api64*.dll
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/*/"Animal Well"/* "$out"/
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url" "$out/Read Me.txt"
  '';

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/Billy Basso/Animal Well" ];
  executable = "Animal Well.exe";

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

  # The extracted worktree, pinned as a directory CID: what the Android
  # client fetches, since it verifies a CAR into a UnixFS tree and has no
  # archive reader. Built by `nix build .#androidPayloads.animal-well`,
  # published with `tar -c . | curl --data-binary @- <the pin server>`.
  # The `src` above stays the desktop's artifact and this game's provenance.
  android.payload.cid = "bafybeifrlj54674zds5tazgywt76xjvuywfc2pkbz6pvaoaj5gmzmatzhu";

  meta = {
    description = "ANIMAL WELL (Billy Basso 2024, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "animal-well";
  };
}
