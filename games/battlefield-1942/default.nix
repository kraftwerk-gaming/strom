{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # "Battlefield 1942 HD" community repack: pre-installed Complete
  # Collection (vanilla + Road to Rome + Secret Weapons of WWII) with
  # the Desert Combat / DCF / DCX / DCFX mods bundled under Mods/. We
  # extract the whole tree and launch BF1942.exe for the vanilla
  # campaign; the desert-combat package reuses the same archive and
  # passes "+game DC_Final" to the same binary.
  src = fetchIpfs {
    cid = "QmSnWcj6uRHNp1Mi7Xanhthx1AnBtzSu8Q2eRgGehYH2HT";
    fallbackUrl = "https://archive.org/download/battlefield-1942-hd.-7z/Battlefield%201942%20HD.7z";
    hash = "sha256-tp3CkNzSgxRyT8j9Tew9n4NI07hl+roISOFSkfqmz4g=";
    name = "battlefield-1942-hd.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "battlefield-1942";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/7z"
    cp -r "$TMPDIR/7z/Battlefield 1942 HD"/. "$out"/
    chmod -R u+w "$out"
    # Bump the shipped default video mode from 800x600 to 1920x1080 in
    # both Profiles/Custom and Profiles/Default Video.con files.
    for p in Custom Default; do
      f="$out/Mods/bf1942/Settings/Profiles/$p/Video.con"
      if [ -f "$f" ]; then
        sed -i 's/^game\.setGameDisplayMode .*/game.setGameDisplayMode 1920 1080 32 0/' "$f"
      fi
    done
  '';

  copyGlobs = [
    "Mods/bf1942/Settings/"
    "Mods/bf1942/Save/"
  ];

  runtime = "proton";
  executable = "BF1942.exe";

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
    description = "Battlefield 1942 Complete Collection (DICE 2002, community HD repack, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "battlefield-1942";
  };
}
