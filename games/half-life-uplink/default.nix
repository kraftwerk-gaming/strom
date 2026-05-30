{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  runCommandLocal,
}:

let
  # Valve's genuine 1999 standalone Half-Life: Uplink demo gamedir,
  # as distributed on the OEM CD / shareware bundles (file dates
  # 1999-02-01). This is a SELF-CONTAINED GoldSrc gamedir, not a data
  # mod: it ships its OWN engine DLLs built against the early-1999
  # GoldSrc client/server API —
  #   - dlls/hl.dll        (849408 B, sha256 1a9679ee…)  game DLL
  #   - cl_dlls/client.dll ( 90112 B, sha256 ba6e8881…)  client DLL
  #   - pak0.pak           (89 MB; maps/hldemo{1,2,3}.bsp + the
  #                         t0a0* training maps, all sprites incl.
  #                         sprites/hud.txt + 640hud*.spr, models,
  #                         sounds, gfx)
  #   - liblist.gam, valve.rc, *.cfg, gfx.wad/decals.wad/cached.wad,
  #     media/ (intro AVIs, launcher audio), titles.txt.
  #
  # These DLLs differ COMPLETELY from retail/WON HL's (retail
  # hl.dll=966729 B c170957a…, client.dll=552960 B 0ce69b0f…). The
  # retail client.dll is the much later VGUI2-era build; running
  # Uplink's 1999 content through it deref-crashes on the very first
  # rendered frame (engine-side AV 0xc0000005 at 0x01D229D4). WON
  # GoldSrc resolves `gamedll`/client.dll STRICTLY under the active
  # `-game <mod>` dir (no valve/ fallthrough for engine DLLs — unlike
  # packfiles/textures/sounds), so the mod gamedir MUST carry its own
  # matching DLL pair. Shipping Valve's original Uplink gamedir as
  # `hlulsl/` gives the 1999 DLLs their matching 1999 content and
  # boots New Game cleanly — which is exactly the end-to-end proof the
  # half-life `mods`/`mod` overlay mechanism is wired correctly.
  #
  # Source: archive.org `hl_shareware_data` item, `valve/uplink.zip`
  # (the original standalone, no installer — extracts straight to a
  # gamedir). 49 MB.
  src = fetchIpfs {
    cid = "QmYZmQwo9Mf47S5nzLm8gSqcfXuYcKJtL8TADCEfh3J69X";
    fallbackUrl = "https://archive.org/download/hl_shareware_data/valve%2Fuplink.zip";
    hash = "sha256-CmSpL4kD6TrUNUPYpJSjsEDEExMmIVb4gRoysh29UpA=";
    name = "uplink.zip";
  };

  # Mod-data tree shipped as an overlay lower above half-life's
  # _gameData (via the `mods` option from the half-life recipe).
  # Layout produced:
  #   $out/Half-Life/hlulsl/dlls/hl.dll
  #   $out/Half-Life/hlulsl/cl_dlls/client.dll
  #   $out/Half-Life/hlulsl/pak0.pak
  #   $out/Half-Life/hlulsl/liblist.gam
  #   $out/Half-Life/hlulsl/{gfx,decals,cached}.wad
  #   $out/Half-Life/hlulsl/*.cfg, valve.rc, titles.txt
  #   $out/Half-Life/hlulsl/media/...
  #
  # uplink.zip's entries are the gamedir content at the zip root; we
  # extract them into `hlulsl/` so the overlay places the tree at
  # Half-Life/hlulsl/, matching `-game hlulsl` on hl.exe's cmdline.
  # liblist.gam is rewritten: the 1999 original points `gamedll` at an
  # absolute `d:\quiver\valve\dlls\hl.dll` install path and titles the
  # game "Half-Life"; we replace it with a relative `gamedll` + the
  # Uplink title + `startmap "hldemo1"` so New Game / the autostart
  # both resolve the right level. (The single-map demo's start level
  # is hldemo1.)
  # Vanilla retail/WON Half-Life game data (the half-life base recipe's
  # extracted Half-Life.zip), used as the source of the engine-matched
  # game/client DLLs — see modData below.
  baseGameData = self.modules.${pkgs.system}.half-life._gameData;

  modData =
    runCommandLocal "half-life-uplink-mod-data"
      {
        nativeBuildInputs = [ unzip ];
        inherit src baseGameData;
      }
      ''
        mkdir -p "$out/Half-Life/hlulsl"
        unzip -q "$src" -d "$out/Half-Life/hlulsl"

        # Rewrite the 1999 liblist.gam: drop the absolute
        # d:\quiver\valve\dlls\hl.dll gamedll path (which WON GoldSrc
        # can't resolve under -game hlulsl) for a relative one, give
        # the demo its own title, and declare the start map so New
        # Game loads hldemo1.
        # NO `fallback_dir "valve"`: the fallback_dir approach was
        # disproven — under `-game <mod>` the WON engine cannot read
        # packed assets out of valve/pak0.pak (the doubled-gamedir
        # pak-handle bug; c0a0.bsp comes back as version-0 zeroes), so
        # fallback_dir only reaches valve's *loose* files and the real
        # first-frame crash was Con_CheckResize driven by `-w/-h` under
        # `-game` (fixed in the base recipe). Uplink ships its OWN
        # complete pak0.pak, so it resolves everything from a single
        # gamedir and needs no fallback.
        printf '%s\n' \
          'game         "Half-Life: Uplink"' \
          'startmap     "hldemo1"' \
          'trainmap     "t0a0"' \
          'gamedll      "dlls/hl.dll"' \
          'type         "singleplayer_only"' \
          > "$out/Half-Life/hlulsl/liblist.gam"

        # Replace the 1999 game/client DLLs with the engine-matched
        # retail pair. The strom half-life base ships the 2002 WON
        # engine (hl.exe build 2056, protocol 46); Uplink's original
        # 1999 DLLs are protocol-incompatible with it:
        #   - the 1999 cl_dlls/client.dll predates the HUD_PlayerMove
        #     export the 2002 engine requires ("could not link
        #     client.dll function HUD_PlayerMove"), and
        #   - mixing the 1999 dlls/hl.dll (server) with a 2002
        #     client.dll desyncs the netchannel (svc_bad flood ->
        #     Host_Error).
        # Uplink is a cut Half-Life chapter, so the retail game DLLs
        # spawn its maps/entities natively; pairing them with Uplink's
        # own pak0.pak (which carries hldemo*.bsp + every HUD sprite /
        # model / sound the demo precaches) gives the engine-matched
        # DLLs the content they expect. This is exactly how the HL!UL!SL
        # repack runs Uplink on a modern Steam Half-Life.
        cp -f "$baseGameData/Half-Life/valve/dlls/hl.dll" \
          "$out/Half-Life/hlulsl/dlls/hl.dll"
        cp -f "$baseGameData/Half-Life/valve/cl_dlls/client.dll" \
          "$out/Half-Life/hlulsl/cl_dlls/client.dll"
      '';

  # Extend the half-life wrapper module. We inherit src/buildScript/
  # preRun/runtime/gamescope/... from the base recipe and override
  # only the pieces specific to Uplink: `name` (own ~/.strom/
  # half-life-uplink/ savedir + compatdata), `mods` (overlay lower
  # carrying the extracted mod tree), and `mod` (engine's
  # `-game hlulsl`). The half-life recipe's executableArgs builder
  # already prepends `-game <mod>` when `mod != "valve"`, so we
  # don't need to mkForce it.
  uplink = self.modules.${pkgs.system}.half-life.apply (
    { lib, ... }:
    {
      config = {
        name = lib.mkForce "half-life-uplink";

        # Record uplink.zip's CID for games.json / pin-tracking. It's fetched
        # by modData, not the inherited game `src` (= base Half-Life.zip), so
        # list it explicitly or its pin would go untracked.
        ipfsSources = [ src ];

        mods = [ modData ];
        mod = "hlulsl";

        # Autostart straight into the demo level instead of relying on the
        # WON menu's New Game. In WON 1.1.1.0 the GameUI "New Game" command
        # does NOT honour the mod liblist's `startmap` — it resolves to the
        # base campaign's hardcoded first map (c0a0, the tram ride), which is
        # exactly what the operator saw despite `startmap "hldemo1"` in
        # hlulsl/liblist.gam. (We also swap in the retail base-campaign game
        # DLLs for engine compat, reinforcing that the menu New-Game path
        # heads for c0a0.) Uplink is a single-map demo, so booting straight
        # into hldemo1 via `+map` is the correct UX — and the `+map`
        # autostart path is NOT the menu->map resolution-switch path, so it
        # never trips the Con_CheckResize crash. Combined with the base
        # recipe's 1080p EngineMode* registry seed, the engine comes up at
        # native 1920x1080 directly on hldemo1.
        #
        # mkForce overrides the base executableArgs builder; we keep its flags
        # (`-gl` OpenGL renderer — Uplink defaults to the 320p software
        # renderer otherwise; `-windowed` so input works and no Con_CheckResize
        # crash; `-lw 1920 -lh 1080` to size the launcher window so the engine
        # renders natively at 1920x1080 rather than a 640x480 upscale — see the
        # base recipe) and append `+map hldemo1` to autostart the demo level
        # (see comment above for why autostart, not the menu New Game).
        executableArgs = lib.mkForce [
          "-game"
          "hlulsl"
          "-gl"
          "-windowed"
          "-nojoy"
          "-w"
          "1920"
          "-h"
          "1080"
          "-lw"
          "1920"
          "-lh"
          "1080"
          "+map"
          "hldemo1"
        ];
      };
    }
  );
in
# Preserve the module-config shape `self.modules.<sys>.<game>` so
# flake.nix's `m.outputs.wrapper` lookup still works. The base
# half-life recipe attaches its meta + pname inside mkGame's final
# overrideAttrs, so we re-wrap `outputs.wrapper` here to swap in
# Uplink's identity.
uplink
// {
  outputs = uplink.outputs // {
    wrapper = uplink.outputs.wrapper.overrideAttrs (old: {
      pname = "half-life-uplink";
      meta = (old.meta or { }) // {
        description = "Half-Life: Uplink (Valve 1999 free demo campaign, via WON Half-Life + Proton)";
        platforms = [ "x86_64-linux" ];
        mainProgram = "half-life-uplink";
      };
    });
  };
}
