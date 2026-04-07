{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmbkGxa7sxm2udcEzivSpXZ3ZjRvXprgtjF3vph3TiyfrA";
    fallbackUrl = "https://archive.org/download/diablo-ii.-7z/Diablo%20II.7z";
    hash = "sha256-clFRUZ9z5IbyjvJZR2YILwi537ijo1XvHbz5bEkM0O8=";
    name = "diablo-ii-lod-portable.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "diablo-ii-lord-of-destruction";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -o/tmp/d2 "$src"
    # Flatten: Game/* becomes the game root so CWD matches Game.exe's expectations
    mv "/tmp/d2/Diablo II/Game"/* "$out"/
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "Game.exe";
  # -dxnocompatmodefix: D2DX's compat-mode detector misfires under Wine/Proton
  # even with no AppCompatFlags set; skip the check.
  executableArgs = [ "-3dfx" "-dxnocompatmodefix" ];

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  preRun = ''
    # CJ_Strife portable layout expects HKCU\Software\Blizzard Entertainment\Diablo II
    # to point at the install path. Inject keys into the prefix's user.reg.
    USERREG="$COMPATDATA/pfx/user.reg"
    GAMEPATH_W="Z:''${GAMEDIR//\//\\\\}"
    SAVEPATH_W="$GAMEPATH_W\\\\save"
    mkdir -p "$GAMEDIR/save"
    if [ -f "$USERREG" ] && ! grep -q 'Blizzard Entertainment\\\\Diablo II' "$USERREG"; then
      cat >> "$USERREG" <<EOF

[Software\\\\Blizzard Entertainment\\\\Diablo II]
"InstallPath"="$GAMEPATH_W"
"NewSavePath"="$SAVEPATH_W"
"Save Path"="$SAVEPATH_W"
"Program"="Diablo II"
EOF
    fi
    # Pin both D2 exes to win10 and strip any AppCompatFlags\Layers entries
    # so D2DX doesn't detect Windows compatibility mode.
    if [ -f "$USERREG" ] && ! grep -q 'AppDefaults\\\\Game.exe' "$USERREG"; then
      cat >> "$USERREG" <<'EOF'

[Software\\Wine\\AppDefaults\\Game.exe]
"Version"="win10"

[Software\\Wine\\AppDefaults\\Diablo II.exe]
"Version"="win10"
EOF
    fi
    SYSREG="$COMPATDATA/pfx/system.reg"
    for f in "$USERREG" "$SYSREG"; do
      [ -f "$f" ] || continue
      sed -i -E '/AppCompatFlags\\\\Layers/,/^\[/ { /Game\.exe|Diablo II\.exe/d; }' "$f"
    done
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Diablo II + Lord of Destruction (CJ_Strife portable, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "diablo-ii-lord-of-destruction";
  };
}
