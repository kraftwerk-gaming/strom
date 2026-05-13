{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # Anachronox (Ion Storm 2001), GOG re-release v1.02 build 22258, repacked
  # as a single RAR by the gog_collection archive. The RAR holds exactly
  # one entry, setup_anachronox_1.02_(22258).exe, a GOG Inno Setup
  # installer: unar yields the installer, innoextract --gog yields the
  # game tree (anox.exe + anoxdata/ + renderer DLLs at the root, with
  # GOG installer debris under app/ tmp/ __redist/ commonappdata/).
  # Engine is a modified Quake II; the bundled OpenGL renderer (ref_gl.dll
  # + metagl.dll) is the path Proton drives via DXVK/Mesa.
  src = fetchIpfs {
    cid = "Qma31wDiB337AYUrJqQmJfeuc7RoZCWDUtVdeWbQnLrojD";
    fallbackUrl = "https://archive.org/download/gog_collection/anachronox.rar";
    hash = "sha256-Sx09L1qkzEeXeOu7RfgD6cXQfrcED/4zFkJ1nobMUbE=";
    name = "anachronox.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anachronox";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/rar/setup_anachronox_1.02_(22258).exe"
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    # The actual game lives at $out root (anox.exe + anoxdata/ + DLLs).
    rm -rf "$out/app" "$out/__redist" "$out/tmp" "$out/commonappdata" \
           "$out/wise"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/galaxy_anachronox_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf"
  '';

  runtime = "proton";
  executable = "anox.exe";
  # Mirror anox_1280gl.bat (gl_mode 8 = 1280x1024, opengl32 renderer,
  # fullscreen via gamescope-nested). Without these the engine picks
  # gl_mode 3 (640x480) and various sound providers, which is the
  # combination that dies during the first map load under Proton.
  executableArgs = [
    "+set" "gl_driver" "opengl32"
    "+set" "gl_mode" "8"
    "+set" "u_gl_mode" "8"
    "+set" "vid_fullscreen" "1"
    "+set" "u_vid_fullscreen" "1"
    "+set" "s_initsound" "0"
  ];

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
    description = "Anachronox (Ion Storm 2001, GOG v1.02 build 22258, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anachronox";
  };
}
