{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  mono,
  unar,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmUo4XGU6BYAwt1AFsEueLhdUKmNmpXq9ogAY8YWTbyHUk";
    fallbackUrl = "https://pixeldrain.com/api/file/BGMc18wp";
    hash = "sha256-OF7ZyGEoGl8blLhN2XjC+6NPJ1ccxrt1RclWi+dwP4I=";
    name = "ROUNDS-SteamGG.rar";
  };

  # BepInEx 5 preconfigured for ROUNDS (Unity Mono backend). Loads via
  # the winhttp.dll proxy DLL, which is independent of the OnlineFix
  # winmm.dll proxy that already ships in the repack so they coexist.
  bepinexPack = fetchurl {
    url = "https://gcdn.thunderstore.io/live/repository/packages/BepInEx-BepInExPack_ROUNDS-5.4.1900.zip";
    hash = "sha256-bsY1GZI5KEyiHbOaoKbQ758gTWDBAsVL2GbzCaOyoWQ=";
  };

  # MonoMod runtime hooks pregenerated for ROUNDS' Assembly-CSharp;
  # required by UnboundLib.
  mmhook = fetchurl {
    url = "https://gcdn.thunderstore.io/live/repository/packages/willis81808-MMHook-1.0.0.zip";
    hash = "sha256-D5jAQP/5n4kAqdNWkflnl9+y0gPROkZCiXq+MG4SAp8=";
  };

  # UnboundLib: the BepInEx-based mod framework most ROUNDS plugins
  # (including ControllerSupport) depend on for menu and lifecycle
  # hooks.
  unboundlib = fetchurl {
    url = "https://gcdn.thunderstore.io/live/repository/packages/willis81808-UnboundLib-3.2.14.zip";
    hash = "sha256-DB+Hz94Qpnv7K4AupK4iL5u5it/CD9XWidhHxMRdOD8=";
  };

  # ControllerSupport: community plugin that re-implements an
  # in-match cursor driver fed by the player's InControl aim stick.
  # It only activates inside an active round (its setup runs in
  # UnboundLib's GameStart coroutine) — the title and lobby menus
  # are still Unity UI keyboard/mouse, since ROUNDS' menus rely on
  # Steam Input to translate pad → virtual mouse and we don't have
  # the Steam Input runtime here. KB+M for menus, pad for shooting.
  controllerSupport = fetchurl {
    url = "https://gcdn.thunderstore.io/live/repository/packages/AncientKoala-ControllerSupport-1.0.4.zip";
    hash = "sha256-bzDPbw7Gx/3CWIxzKb5IVO7e+kK6bsGqFjkOazFHY9M=";
  };

  # ModdingUtils: undeclared transitive dependency of
  # ControllerSupport. The Thunderstore manifest only lists
  # UnboundLib, but the compiled DLL's assembly externs reference
  # `ModdingUtils 1.0.0.0` (CharacterDataExtension /
  # AIMinion.Extensions). Without it loaded the JIT silently fails
  # to resolve those types on first use — the plugin's in-match
  # SetupSupport never reaches its mouse cursor coroutine.
  moddingUtils = fetchurl {
    url = "https://gcdn.thunderstore.io/live/repository/packages/Pykess-ModdingUtils-0.4.8.zip";
    hash = "sha256-vjc04TjFo1D+xV1cZKHDnL3p02dCw1xJaf69UEtJnoQ=";
  };

  # RoundsMultiPad: in-tree BepInEx Harmony plugin that fixes
  # multi-pad lobby join under Proton/wine. InControl's
  # NativeInputDeviceManager succeeds at Enable() but never
  # enumerates pads, suppressing the UnityInputDeviceManager
  # fallback that DOES work via Unity's joystick API. The plugin
  # postfixes InputManager.SetupInternal and force-adds the Unity
  # manager so InputManager.ActiveDevices populates and the lobby's
  # existing pad-join loop (PlayerAssigner.LateUpdate) can spawn
  # one player per attached pad. Compiled at build time from
  # ./multipad-plugin/RoundsMultiPad.cs against the same managed
  # DLLs the runtime loads.
  multipadPluginSrc = ./multipad-plugin/RoundsMultiPad.cs;
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rounds";

  inherit src;

  nativeBuildInputs = [
    mono
    unar
    unzip
  ];

  # SteamGG RAR5 layout: ROUNDS.SteamGG.net/{Rounds.exe, Rounds_Data/,
  # UnityPlayer.dll, MonoBleedingEdge/, steam_api64.dll under
  # Rounds_Data/Plugins/, plus a bundled OnlineFix winmm.dll proxy
  # (OnlineFix64.dll + SteamOverlay64.dll + OnlineFix.ini) that spoofs
  # SteamAPI for AppId 1557740 via FakeAppId=480. Drop the SteamGG advert
  # shortcut and the human-facing readme at the root.
  buildScript = ''
    mkdir -p "$out"
    unar -q -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract/ROUNDS.SteamGG.net/"* "$out"/
    # Drop SteamGG advert .url shortcut (filename contains a non-ASCII
    # en dash), the human-facing readme, and the repack dll list.
    rm -f "$out"/SteamGG*.url \
      "$out/Read_Me_Instructions.txt" \
      "$out/dlllist.txt"

    # Lay down BepInEx 5 next to Rounds.exe. The pack archives a
    # single BepInExPack_ROUNDS/ top-level directory; everything
    # under it (winhttp.dll, BepInEx/, corlibs/, doorstop_config.ini)
    # belongs at the game root so wine's winhttp.dll proxy fires on
    # exe load and the doorstop init reads its config from cwd.
    unzip -q "${bepinexPack}" -d "$TMPDIR/bepinex"
    cp -r "$TMPDIR/bepinex/BepInExPack_ROUNDS/"* "$out"/
    chmod -R u+w "$out/BepInEx"

    # Slot every plugin into BepInEx/plugins/. Some Thunderstore
    # zips nest the dll under plugins/ (mmhook, UnboundLib,
    # ControllerSupport); others ship the dll at the zip root
    # (ModdingUtils). Detect either layout and copy the .dll(s) into
    # the shared plugin tree BepInEx scans at startup.
    mkdir -p "$out/BepInEx/plugins"
    for mod in ${mmhook} ${unboundlib} ${controllerSupport} ${moddingUtils}; do
      tmp=$(mktemp -d)
      unzip -q "$mod" -d "$tmp"
      if [ -d "$tmp/plugins" ]; then
        cp -r "$tmp/plugins/"* "$out/BepInEx/plugins/"
      else
        find "$tmp" -maxdepth 1 -name '*.dll' -exec cp -t "$out/BepInEx/plugins/" {} +
      fi
      rm -rf "$tmp"
    done
    chmod -R u+w "$out/BepInEx/plugins"

    # Compile in-tree RoundsMultiPad Harmony plugin against the
    # managed DLLs we just laid down. mcs from mono in
    # nativeBuildInputs; -nostdlib forces use of the game's own
    # mscorlib/netstandard so the plugin loads against Unity's
    # Mono runtime without version skew.
    managed="$out/Rounds_Data/Managed"
    core="$out/BepInEx/core"
    mcs \
      -target:library \
      -out:"$out/BepInEx/plugins/RoundsMultiPad.dll" \
      -nostdlib \
      -r:"$managed/mscorlib.dll" \
      -r:"$managed/netstandard.dll" \
      -r:"$managed/System.dll" \
      -r:"$managed/System.Core.dll" \
      -r:"$managed/UnityEngine.dll" \
      -r:"$managed/UnityEngine.CoreModule.dll" \
      -r:"$managed/UnityEngine.InputModule.dll" \
      -r:"$managed/InControl.dll" \
      -r:"$core/BepInEx.dll" \
      -r:"$core/0Harmony.dll" \
      "${multipadPluginSrc}"
  '';

  runtime = "proton";
  executable = "Rounds.exe";

  # Unity 2019 writes player prefs / logs under
  # AppData/LocalLow/<Company>/<Product> (Landfall / ROUNDS). Keep those
  # outside the disposable wineprefix so settings and unlocked card
  # progress survive prefix wipes.
  saveLocations = [
    "AppData/LocalLow/Landfall/ROUNDS"
    "AppData/LocalLow/Landfall Games/ROUNDS"
  ];

  # Pin SteamAppId=480 so the bundled OnlineFix winmm proxy and any
  # Steamworks.NET probes see the FakeAppId from OnlineFix.ini rather
  # than the real 1557740 (no Steam client behind Proton).
  env = {
    SteamAppId = "480";
    SteamGameId = "480";

    # Force wine to load the native (BepInEx-supplied) winhttp.dll
    # ahead of its own builtin stub. BepInEx 5's preloader rides on
    # winhttp's DllMain so the override has to fire before any wine
    # builtin can claim the name. Format is `name=n,b` — native then
    # builtin fallback. The OnlineFix proxy uses winmm and isn't
    # affected.
    WINEDLLOVERRIDES = "winhttp=n,b";

    # Gamepad routing safety belt. ROUNDS' Unity InControl already
    # reads the pad via wine's XInputInterface64 native; the BepInEx
    # ControllerSupport plugin then maps that aim stick into a
    # Win32 mouse cursor for the in-match shooting view. The menu
    # is unaffected and still needs keyboard/mouse: ROUNDS' menus
    # depend on Steam Input to translate pads into virtual KB/mouse
    # and that runtime isn't available outside Steam.
    # SDL_JOYSTICK_HIDAPI=0 keeps SDL from racing winebus's evdev
    # probe via the libusb hidapi backend; without it, wine can
    # latch onto a phantom hidraw device that never delivers state.
    SDL_JOYSTICK_HIDAPI = "0";
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

  # Menu-navigation profile. ROUNDS' Unity menus rely on Steam Input
  # to translate pads into virtual KB/mouse, which we don't have, so
  # players can't even reach a lobby without a real keyboard. With
  # padToKb the pad synthesizes a uinput keyboard the menus do
  # respond to. passthrough=true keeps the native XInput route alive
  # so InControl + ControllerSupport still drive the in-match
  # aim/shoot cursor unchanged.
  #
  # Lobby join path (Round 5 decompile, PlayerAssigner.LateUpdate at
  # Assembly-CSharp.dll offset 14368): Space keydown spawns a
  # keyboard player when no existing player has Device == null, AND
  # a separate loop over InControl's InputManager.ActiveDevices
  # spawns a distinct pad player on Action1..Action4.WasPressed.
  # Under wine InControl's NativeInputDeviceManager succeeds at
  # Enable() but never enumerates pads, suppressing the
  # UnityInputDeviceManager fallback that DOES read pads via Unity's
  # joystick API. The in-tree RoundsMultiPad Harmony plugin (see
  # ./multipad-plugin/) postfixes InputManager.SetupInternal to
  # force-add the Unity manager alongside the native one, so
  # ActiveDevices populates and pads can each spawn their own player
  # slot via the engine's existing path.
  #
  # padToKb stays enabled so a pad can drive the title screen and
  # keyboard-only menus via arrow keys. With the multipad plugin in
  # place, pad-player lobby join is handled by InControl directly:
  # any pad button surfaces to InControl.InputManager.ActiveDevices
  # and PlayerAssigner spawns a pad-bound player slot. So padToKb
  # must NOT synthesize any keyboard key that overlaps a keyboard
  # PlayerAction binding (Space=Jump, WASD=movement, Return=Start,
  # mouse=Fire/Block) — otherwise every in-match pad press would
  # also drive the keyboard player. Unity's UI Submit axis defaults
  # to joystick button 0 ("Fire1"), so the pad's face A button
  # already advances menus natively; padToKb only needs to cover
  # cancel and d-pad navigation.
  padToKb = {
    enable = true;
    passthrough = true;
    bindings = {
      # Select → Esc for menu cancel. Face buttons + Start are
      # intentionally absent: the multipad plugin surfaces them to
      # InControl directly so the pad joins as its own player slot
      # and drives gameplay actions without any synthesized
      # keyboard crosstalk. Unity's UI Submit axis already covers
      # menu activation via joystick button 0.
      "btn:select" = "key:esc";

      # Shoulder buttons → tab cycling for any tabbed UI. Right
      # shoulder is plain Tab; left shoulder gets a separate hook
      # below for Shift+Tab.
      "btn:tr" = "key:tab";

      # D-pad → arrow keys.
      "abs:hat0x:-1" = "key:left";
      "abs:hat0x:1" = "key:right";
      "abs:hat0y:-1" = "key:up";
      "abs:hat0y:1" = "key:down";

      # Left analog stick → arrow keys via outer-half thresholds.
      # evsieve evaluates each range independently with built-in
      # hysteresis on the boundary so a stick held at the threshold
      # doesn't auto-repeat.
      "abs:x:-32768..-16384" = "key:left";
      "abs:x:16384..32767" = "key:right";
      "abs:y:-32768..-16384" = "key:up";
      "abs:y:16384..32767" = "key:down";
    };
    # Multi-destination output for the Shift+Tab chord. evsieve
    # fires each DEST in argv order on every SOURCE event, which is
    # exactly the chord semantics we want.
    extraArgs = [
      "--copy"
      "btn:tl"
      "key:leftshift"
      "key:tab"
    ];
  };

  meta = {
    description = "ROUNDS (Landfall 2021, 1v1 rounds-based shooter via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rounds";
  };
}
