{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Croteam's 2001 retail Serious Sam: The First Encounter, repacked as
  # a portable zip with the v1.05 patch + GameSpy-replacement binaries
  # already applied. Drop-in install -- no setup.exe to run. Same uploader
  # / packaging as the TSE archive item; runtime is Proton (mirrors the
  # TSE package's choices). Directory name keeps the issue slug
  # "serious-sam"; Lutris canonical slug is
  # "serious-sam-the-first-encounter" (see workflow feedback).
  src = fetchIpfs {
    cid = "QmUauVkZopH2gW1yZhcaaWp428kisXUXdRsgKbdmAW4rmj";
    fallbackUrl = "https://archive.org/download/serious-sam-the-first-encounter_202512/Serious%20Sam%20-%20The%20First%20Encounter.zip";
    hash = "sha256-XR9qwxuyDr8Qy9YGhcJBVRJDvdomt9Aac1jyW8eZZQE=";
    name = "serious-sam-the-first-encounter.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "serious-sam";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/Serious Sam"/. "$out"/
    chmod -R u+w "$out"
    # Game_startup.ini is sourced by the engine on EVERY launch (after the
    # persisted PersistentSymbols.ini, so it wins). We pin the engine to a
    # 1920x1080 OpenGL fullscreen mode that matches the gamescope nest:
    #   * OpenGL (sam_iGfxAPI=0): the engine's Direct3D path black-screens
    #     under Proton; OpenGL is the only working renderer.
    #   * sam_bFullScreen=1 at the nest resolution: the engine's native
    #     fullscreen window is what gamescope shows; forcing the size here
    #     keeps it pinned to 1920x1080 regardless of persisted state.
    # Stock PersistentSymbols.ini is left untouched so the engine's other
    # defaults (input, gap_/ogl_ tuning) survive; the in-game options menu
    # still writes user changes back to it (persisted via copyGlobs).
    cat > "$out/Scripts/Game_startup.ini" <<'EOF'
    sam_iGfxAPI=0;
    sam_bFullScreen=1;
    sam_iScreenSizeI=1920;
    sam_iScreenSizeJ=1080;
    sam_iDisplayDepth=0;
    sam_iDisplayAdapter=0;
    EOF
  '';

  copyGlobs = [
    "Scripts/PersistentSymbols.ini"
    "ControlsConfig/"
    "SaveGame/"
  ];

  runtime = "proton";
  executable = "Bin/SeriousSam.exe";

  # Serious Engine writes savegames and config into SaveGame/,
  # ControlsConfig/ and Scripts/PersistentSymbols.ini next to the binary
  # in the install tree (mirrored by copyGlobs above), so they persist via
  # the per-game fuse-overlayfs upper. No wineprefix relocation needed.
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Serious Sam grabs the pointer for FPS mouse-look. Under gamescope
      # the grab doesn't propagate as relative motion unless we force it,
      # so without this the camera never turns.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Serious Sam: The First Encounter (Croteam 2001, retail v1.05, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "serious-sam";
  };
}
