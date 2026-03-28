{
  fetchzip,
  wineWow64Packages,
  writeShellApplication,
}:

let
  gameFiles = fetchzip {
    name = "lemmings95";
    url = "https://d1.xp.myabandonware.com/t/9fe7b6b6-4c91-48ae-9ba0-de6affcb0501/Lemmings-Oh-No-More-Lemmings_Win_EN.zip";
    hash = "sha256-08Fxuj96+6ALF7HFilBEVYxTbxIN4jvSf3eYaheotts=";
    stripRoot = false;
  };
in
writeShellApplication {
  name = "lemmings";

  runtimeInputs = [ wineWow64Packages.stable ];

  text = ''
    GAMEDIR="''${HOME:-.}/.strom/lemmings"
    mkdir -p "$GAMEDIR"
    cd "$GAMEDIR"

    # Symlink all game files into writable directory
    for f in "${gameFiles}"/lemmings95/*; do
      base="$(basename "$f")"
      # Skip files that need to be writable
      if [ ! -e "$base" ] || [ -L "$base" ]; then
        ln -sf "$f" "$base"
      fi
    done

    trap 'find . -type l -delete' EXIT

    wine ./LEMMINGS.EXE
  '';

  meta = {
    description = "Lemmings & Oh No! More Lemmings (Windows 95 edition)";
    homepage = "https://www.myabandonware.com/game/lemmings-oh-no-more-lemmings-3m2";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lemmings";
  };
}
