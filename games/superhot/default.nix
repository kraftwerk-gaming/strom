{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # SUPERHOT (SUPERHOT Team, 2016 PC release). Windows build packed as a
  # plain 7z; no installer, just unpack and run SH.exe under Proton.
  src = fetchIpfs {
    cid = "QmReaYyJTGGy1QSgoJnmJPnVAdDuE4tfTNYBdgR8jjdwjL";
    fallbackUrl = "https://archive.org/download/superhot1/SuperHot_2016_Unity5.7z";
    hash = "sha256-LK7XU85FjV79FdTc1sdxAVO9bXi1+hRvfZgIyINNCV0=";
    name = "superhot-2016-unity5.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "superhot";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$out"
    # The repacker shipped an ancient wine-staging d3d11.dll/dxgi.dll/
    # wined3d.dll trio next to SH.exe. Wine's loader picks these up
    # before its own builtins, and the bundled wined3d is missing
    # exports the bundled d3d11 calls (e.g. wined3d_get_adapter_identifier,
    # wined3d_get_output_desc) which aborts the process. Drop them so
    # Proton's DXVK d3d11/dxgi take over cleanly.
    rm -f "$out"/d3d11.dll "$out"/dxgi.dll "$out"/wined3d.dll
  '';

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/SUPERHOT_Team/SUPERHOT" ];
  executable = "SH.exe";
  # Unity 5 standalone player flags. -force-d3d11 routes through DXVK
  # instead of Unity's default D3D9 path (whose wined3d adapter
  # enumeration is unreliable on modern Proton). The screen flags
  # mirror SH.bat from the bundle.
  executableArgs = [
    "-adapter"
    "0"
    "-screen-fullscreen"
    "1"
    "-force-d3d11"
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
    description = "SUPERHOT (SUPERHOT Team, 2016 Unity5 release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "superhot";
  };
}
