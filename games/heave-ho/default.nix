{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Heave Ho (Le Cartel Studio / Devolver Digital, 2019). Physics-based
  # co-op party game, up to four players. Windows-only Unity build; no
  # native Linux release. Source: IGG-Games mirror of v1.08 RAR
  # (Heave.Ho.v1.08.rar, 506,087,278 bytes). Double-wrapped layout:
  # Heave.Ho.v1.08/Heave.Ho.v1.08/{HeaveHo.exe,HeaveHo_Data/,...}.
  # Unity persistentDataPath: AppData/LocalLow/Le Cartel Studio/HeaveHo.
  src = fetchIpfs {
    cid = "QmXqCGP9bKyeLMYdFjujeMgXYv5Un9JqqTW1SMrdoXwPx4";
    fallbackUrl = "https://drive.usercontent.google.com/download?id=1lC-6j0-8bw8YXpyKwO4HFjYyInxJNXt7&export=download&confirm=t";
    hash = "sha256-KZMxvOYjmmVyPKcMaEWwW9215x89rZZYNzUcc18dKBQ=";
    name = "Heave.Ho.v1.08.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "heave-ho";

  inherit src;

  nativeBuildInputs = [ unar ];

  # RAR layout: Heave.Ho.v1.08/Heave.Ho.v1.08/HeaveHo.exe + HeaveHo_Data/
  # + MonoBleedingEdge/ + UnityPlayer.dll — double-wrapped by the
  # repack. unar creates the outer dir; we strip both levels.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/Heave.Ho.v1.08/Heave.Ho.v1.08/. "$out"/
    # Remove GOG metadata and launcher shortcut not needed at runtime.
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.ico "$out/gog.ico" "$out/EULA.txt" \
          "$out/"*.lnk
    # Unity crash handler spawns a background process that keeps the
    # proton waitforexitandrun loop alive after the game exits, preventing
    # clean teardown. Drop it (same fix as atomicrops).
    rm -f "$out/UnityCrashHandler64.exe" "$out/UnityCrashHandler32.exe"
  '';

  runtime = "proton";

  executable = "HeaveHo.exe";

  saveLocations = [ "AppData/LocalLow/Le Cartel Studio/HeaveHo" ];

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
    description = "Heave Ho (Le Cartel Studio 2019, Unity co-op party game, v1.08 via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "heave-ho";
  };
}
