{
  self,
  lib,
  pkgs,
  fetchIpfs,
  callPackage,
  gnutar,
  zstd,
}:

let
  # GE-Proton with the symlink-pfx patch (same build the runtime uses).
  # We only need it at build time to lift out its bundled FAudio DLL.
  proton = callPackage ../../pkgs/proton.nix { };
  # Proton's builtin xaudio2_9 is FAudio (PE32+), routes audio out
  # through SDL2 -> PipeWire/Pulse. We overwrite the game's bundled
  # Microsoft redist with this so UE4's LoadLibrary-by-path picks it up.
  faudioDll = "${proton}/files/lib/wine/x86_64-windows/xaudio2_9.dll";
  # Supraland (Supra Games 2019), v1.23.7, P2P pre-installed build.
  #
  # Source: Supraland.v1.23.7-P2P scene release, pre-installed Windows tree.
  # Mirror: https://pixeldrain.com/u/b1rrAKSh (Supraland.v1.23.7-P2P.zip, 4325982020 B)
  # Repackaged as tar.zst from the zip root (Supraland/ tree contents).
  src = fetchIpfs {
    cid = "QmbxzpQNY8RPAG6t2DhGSah5nT6dWRzi1128rMtZx5BRDS";
    fallbackUrl = "https://pixeldrain.com/api/file/b1rrAKSh";
    hash = "sha256-lxesdc/RlFNu2ZF5zo+5eSfmT8wgBerxDy44iq0IK6c=";
    name = "supraland.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "supraland";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    gnutar
    zstd
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --use-compress-program=zstd -xf "$src" -C "$out"
    chmod -R u+w "$out"
    rm -f "$out/SKIDROWRELOADED.COM.txt"

    # No-audio fix. UE 4.22+ ships Microsoft's redistributable XAudio 2.9
    # (Engine/Binaries/ThirdParty/Windows/XAudio2_9/x64/xaudio2_9redist.dll)
    # and LoadLibrary's it BY PATH at startup. That redist PE talks to the
    # real Windows audio stack and is NOT wine's FAudio-backed builtin, so
    # under Proton it opens no device and the game is silent.
    #
    # Merely deleting the redist (tried first) failed: UE4 hard-loads that
    # exact path and, finding nothing, never falls through to the prefix
    # xaudio2_9. So instead we OVERWRITE the redist with Proton's builtin
    # FAudio xaudio2_9.dll under the same filename — UE4's by-path load now
    # gets FAudio, which routes audio out through SDL2 -> PipeWire/Pulse.
    install -Dm644 ${faudioDll} \
      "$out/Engine/Binaries/ThirdParty/Windows/XAudio2_9/x64/xaudio2_9redist.dll"
  '';

  runtime = "proton";
  # UE4 launcher stub at the install root; internally re-execs
  # Supraland/Binaries/Win64/Supraland-Win64-Shipping.exe.
  executable = "Supraland.exe";

  # UE4 writes saves/config under %LOCALAPPDATA%\Supraland\Saved.
  saveLocations = [ "AppData/Local/Supraland/Saved" ];

  env = {
    # Belt-and-braces: pin the in-prefix xaudio2_9 to wine's builtin
    # (FAudio) too, in case any code path resolves it from the prefix
    # rather than the bundled redist path we swapped above.
    WINEDLLOVERRIDES = "xaudio2_9=b";
    # FAudio opens its output through SDL2's audio subsystem. SDL2
    # auto-probes its backends; the pulse socket is reachable in the
    # sandbox (PipeWire's pulse server, symlinked into the per-launch
    # XDG_RUNTIME_DIR by lib/gamescope.nix), so let SDL pick it.
    PULSE_LATENCY_MSEC = "60";
  };

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
    description = "Supraland (Supra Games 2019, v1.23.7 P2P pre-installed, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "supraland";
  };
}
