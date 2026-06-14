{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Lunacid (Kira / KIRA LLC, 2023). First-person dungeon-crawler RPG
  # inspired by FromSoftware's King's Field / Shadow Tower, built on Unity
  # (Mono, not IL2CPP). Windows-only; no native Linux build, so
  # runtime = "proton".
  #
  # SOURCE: "Lunacid v2.1.4-P2P" repack — a single RAR5 archive with the
  # layout Lunacid/{LUNACID.exe, LUNACID_Data/, UnityPlayer.dll,
  # MonoBleedingEdge/}. The Steam build is cracked with a RUNE/
  # SmartSteamEmu-family emulator (LUNACID_Data/Plugins/x86_64/
  # steam_emu.ini + steam_api64.dll, Steam AppId 1745510) baked into the
  # repack, so it runs offline with no extra steam_api swap.
  src = fetchIpfs {
    cid = "QmPC94pgFSKLU22yk9LjDEafKaF8pTPyDjcQYecv4xzotZ";
    fallbackUrl = "https://pixeldrain.com/api/file/AR6JiFjq?download";
    hash = "sha256-cypNkOmaMk9MjiwM+JWUCTwMFLKj3yfN+cA78BWcEDQ=";
    name = "Lunacid.v2.1.4-P2P.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lunacid";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unar ];

  # RAR5 repack: everything lives under a single top-level "Lunacid/" dir.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract/Lunacid/"* "$out"/
    rm -f "$out/SKIDROWRELOADED.COM.txt"
    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. atomicrops). Unity runs
    # fine without it.
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"

    # WASD scramble fix. Lunacid's keybind loader (Player_Control_scr.LOAD)
    # parses Resources/BINDINGS.txt and re-applies each '|'-separated token
    # to the action's bindings array POSITIONALLY, by index
    # (ApplyBindingOverride(action, n++, token)). The repack ships a stale
    # BINDINGS.txt whose Move line is out of sync with this build's
    # InputActionAsset: the asset's Move "WASD" 2DVector composite now also
    # carries numpad part-bindings (up:numpad5, down:numpad2, left:numpad1,
    # right:numpad3) that the shipped file omits. Every keyboard token
    # therefore lands one-or-more slots early — W stays on "up" by luck but
    # S overrides the up part (S->forward), A overrides down (A->back), D
    # overrides left (D->strafe-left), exactly the reported scramble. It is
    # deterministic and OS-independent (not a layout/Proton bug).
    #
    # Fix: drop the stale template. On first focus Lunacid sees the file
    # absent, calls RemoveAllBindingOverrides + SAVE(), and regenerates
    # BINDINGS.txt straight from the live asset in correct binding-index
    # order (numpad slots included), so the WASD parts line up. The
    # regenerated file persists in the overlay upper.
    rm -f "$out/LUNACID_Data/Resources/BINDINGS.txt"
  '';

  runtime = "proton";
  executable = "LUNACID.exe";

  # Unity LocalLow tree: AppData/LocalLow/KIRA LLC/LUNACID on Windows.
  saveLocations = [ "AppData/LocalLow/KIRA LLC/LUNACID" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Lunacid (Kira 2023, Unity King's Field-style first-person dungeon crawler, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lunacid";
  };
}
