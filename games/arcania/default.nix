{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  unar,
  innoextract,
}:

let
  # GOG ArcaniA v2.0.0.2 (Spellbound Entertainment / JoWooD 2010 action
  # RPG, "Gothic 4"). Distributed as a single zip wrapping the InnoSetup
  # bundle (setup_arcania_2.0.0.2.exe + two RAR-formatted .bin chunks).
  # The 2.0.0.2 build folds in the Fall of Setarrif content via
  # Data/xpatch_data_efgis.pak and a single Arcania.exe entry point.
  src = fetchIpfs {
    cid = "QmQQGAo8PBAb75FaWVA1oWjBDgZ4hJ5RExpAPNKShDN2HW";
    fallbackUrl = "https://archive.org/download/gothic-4-arcania-pl-multilanguage-dla-masochistow.v-2.0.0.2-gog/Gothic%204%20Arcania%20PL%20MULTILANGUAGE%20DLA%20MASOCHISTOW.v2.0.0.2-GOG.zip";
    hash = "sha256-EITCXC1QwwS1w1M5awJXqd3/eUQaX6ZxQCY/oZO2Dbw=";
    name = "arcania-the-complete-tale.zip";
  };

  # Round-6: round-5's "CPU core count cap" theory was wrong. The
  # round-5 EIP `0x00AD97E6` lives inside `Spellbound::
  # PhysicsManagerNx::Init` (PhysicsManagerNx.cpp), NOT inside
  # `Spellbound::ProcessManagerImpl::StartFromXml`. The disassembled
  # function shows:
  #
  #   call PhysXLoader.dll!NxCreatePhysicsSDK
  #   mov  [this+0xd0], eax          ; store SDK ptr
  #   cmp  [this+0xd0], 0
  #   jne  ok                        ; skip "PhysX not installed" log
  #   <SBERROR: PhysX drivers does not compatibel or Installed.\n
  #    Please install the latest PhysX drivers.\n
  #    http://www.nvidia.com/Download/index.aspx?lang=en-us\n
  #    Other Drivers -> NVIDIA PhysX System Software>
  # ok:
  #   mov  eax, [this+0xd0]          ; eax = NULL on this path too
  #   mov  edx, [eax]                ; <- crash (page fault read 0)
  #
  # i.e. NxCreatePhysicsSDK returned NULL, the engine "logged" the
  # warning (silently, into a sink that's discarded under proton),
  # then fell through into a code path that derefs the SDK pointer
  # without re-checking. Round-5 dinput8 shim was a silentgameplays
  # *gameplay* multicore-affinity workaround unrelated to startup.
  #
  # PhysXLoader.dll's lookup order (verified via `strings`):
  #   1. HKLM\Software\Ageia Technologies -> "PhysXCore Path" (dir)
  #   2. enableLocalPhysXCore == 1 -> <exe_dir>\PhysXCore.dll
  #   3. system search path -> system32\PhysXCore.dll
  # Wine ships none of these by default. preRun (below) installs
  # PhysXCore.dll at the registry-pointed path and stamps the reg key.
  #
  # Round-7: pin a *genuine* PhysX SDK 2.8.1 PhysXCore.dll. Round-6
  # reused games/cryostasis's bundled PhysXCore.dll, but `strings` on
  # that binary showed every source path as `g:\scm\release\
  # PhysX_2.7.3\...` -- it's the 2.7.3 build, not 2.8.1. Arcania's
  # PhysXLoader.dll and NxCooking.dll are SDK 2.8.1 (verified via the
  # `c:\SDK\NVIDIA PhysX SDK\v2.8.1\Bin\win32\*.pdb` strings in the
  # game's own DLL string tables). When 2.8.1 PhysXLoader tried to
  # bind 2.7.3 PhysXCore's `Np*` entry points, it got a partial
  # export set, failed the internal version handshake inside
  # `NpCreatePhysicsSDK`, and returned NULL to Arcania's
  # `PhysicsManagerNx::Init` -- producing the same null-deref crash
  # at EIP=AD97E6. The round-6 build correctly *loaded* PhysXCore.dll
  # (confirmed in the `module:load_dll` trace), proving the failure
  # was the SDK version mismatch, not module resolution.
  #
  # NVIDIA's PhysX System Software 9.09.0428 redist is the canonical
  # 2.8.1 source: an InstallShield cab payload (extract with
  # `cabextract`) ships one PhysXCore.dll per supported SDK
  # generation, GUID-suffixed by InstallShield component ID. The
  # 4416792-byte variant
  # (physxcore.dll.6cb22d51_bf57_36a9_b82b_d8b0f0f46d53) has
  # `f:\scmvista\experimental\PhysX_2.8.1_GPU\...` source paths --
  # the genuine 2.8.1 GPU build that pairs with Arcania's
  # PhysXLoader. NVIDIA still serves the original 41 MiB redist from
  # us.download.nvidia.com on a stable URL, so a plain fetchurl
  # avoids a redundant IPFS pin for a publicly archived NVIDIA
  # release binary.
  arcaniaPhysXRedist = fetchurl {
    url = "https://us.download.nvidia.com/Windows/9.09.0428/PhysX_9.09.0428_SystemSoftware.exe";
    hash = "sha256-eAvEdsR23htAFKJ2Addu/ztgVeWLtl5wubRxUaVzIAw=";
    name = "PhysX_9.09.0428_SystemSoftware.exe";
  };

  # Round-16: pre-baked Windows Media Player 11 overlay tarball. Contains
  # 15 native MS WMP11/WMF11 DLLs (wmvcore, wmasf, wmadmod, wmvdmod,
  # wmvdecod, wmsdmod, wmsdmoe2, mfplat, wmp, wmpnssci, qasf, msnetobj,
  # wmnetmgr, wmpband, wmidx) extracted from the x86 wmp11-windowsxp-
  # x86-enu.exe installer's wmfdist11.exe + wmp11.exe inner cabs, plus
  # a captured system.reg snapshot (1125 sections, CLSID / Interface /
  # DirectShow MediaObjects / ProxyStubClsid for the COM-publishable
  # set). preRun drops the DLLs into syswow64 and appends the .reg
  # snapshot to system.reg (freelancer-style).
  #
  # Why a baked tarball: on-the-fly `winetricks wmp11` against proton's
  # wine binary fails because winetricks's wmp11 verb is a moving
  # target (the upstream x64 installer is the only one with a working
  # extraction path), and even when it runs the FHS chroot setup for
  # downloading + extracting + regsvr32-ing requires steam-run on the
  # host. Bake once host-side, ship the captured DLLs + .reg, lay them
  # down at first launch via the standard freelancer overlay idiom.
  arcaniaWmp11Overlay = fetchIpfs {
    cid = "QmU7egxTUWfC3mySHRwCtcnW3LXDBtbM2qxMnPziTAesEY";
    hash = "sha256-tO6xLyNCXmcflNwZa5o12Dnaijf1ZUYZf4YavtzMlCo=";
    name = "arcania-wmp11-overlay.tar.zst";
  };

  # Round-10: round-9's VideoSettings.xml seed was a no-op.
  # `postprocessing=false` and `fullscreen=true` are NOT attributes of
  # the VideoSettings::eSettings enum -- they belong to a different
  # enum (`Spellbound::SBRendererProcess::eEngineSettings`) that loads
  # from `Configuration\EngineSettings.xml` (baked inside data0.pak,
  # not user-overridable from Documents). VideoSettings.xml's parser
  # silently drops unknown keys, so the user file we shipped did
  # nothing. The round-9 "tested smoke" observation only proved the
  # exe still survives -- it never proved postprocessing was off,
  # because we were writing to the wrong attribute namespace.
  #
  # The full set of VideoSettings::eSettings attribute names, extracted
  # from Arcania.exe's string table (offsets 10770248-10770808, the
  # cluster preceding `Spellbound::AttributeTable<enum VideoSettings::
  # eSettings>::AddTypedValue` and the `Configuration\VideoSettings.xml`
  # path literal at 10771336), is:
  #
  #   sky_detail, view_distance, exposure_control, shadow_objects_main,
  #   shadow_objects, dynamic_light_shadows, ssao_detail, lighting_detail,
  #   character_detail, building_detail, texture_detail,
  #   particle_detail_level, clear_commandbuffer_on_render,
  #   brightness_max, brightness_min, disapearing_foliage, skin_shader,
  #   character, secondary_light, primary_light, rim_light,
  #   detail_normalmap, sun_glares, ambient_occlusion_only,
  #   ambient_occlusion_blur, ambient_occlusion, performance_preset,
  #   saturation, contrast, brightness, shadow_resolution_index,
  #   shadows, tonemap, adapter
  #
  # Resolution_x/y/fullscreen are in the OTHER (engine) enum -- we keep
  # them in the seed because the GOG-installed default already had
  # them there and the parser tolerates unknown keys without warning;
  # they're effectively cosmetic, since gamescope (`output-width
  # 1920`/`nested-width 1920`) provides the actual surface, and the
  # engine will fall through to its baked default if its own parser
  # ignores them.
  #
  # Disable every effect the VideoSettings parser actually recognises
  # that could cause the "menu/world black, cursor visible" symptom:
  # tonemap (HDR composite that magos-linux specifically calls out as
  # the silentgameplays Windows workaround), ambient_occlusion (the
  # SSAO composite pass), sun_glares (post-process lens flare),
  # dynamic_light_shadows (per-light shadow accumulation; Vision Engine
  # bug-2 under DXVK), skin_shader (subsurface compositing on faces --
  # magos-linux noted "red eyes" needing this disabled). Drop quality
  # presets to 0 (low). performance_preset=0 is the engine's "lowest"
  # tier which the in-game menu's "low" label maps to (the i18n key
  # `menu_0110_*_quality.low` appears in the same string segment).
  # Round-12: revert round-11's dxvk.conf approach. The SM2 clamp +
  # GTX 460 spoof + 2 GiB VRAM cap regressed: round-10 reached the
  # MainMenu (world black, cursor visible); round-11 exits on startup
  # under interactive test (the 22 s smoke can't see it because the
  # render thread doesn't actually compose a frame until after the
  # menu loop spins up — module loads alone keep the .exe alive for
  # the smoke window). The most likely cause is that the Vision
  # Engine's caps probe requires SM3 to even initialise the renderer;
  # clamping it to SM2 makes the probe fail and the engine aborts.
  #
  # Pivot: bypass DXVK's d3d9 entirely via wined3d. Proton GE injects
  # DXVK as `c:\windows\syswow64\d3d9.dll` (~6 MiB DXVK build, not
  # wine's ~600 KiB builtin). With `WINEDLLOVERRIDES="d3d9=b"` the
  # loader pins wine's own builtin d3d9.dll, which is a wined3d
  # frontend that translates Direct3D 9 calls to OpenGL. Different
  # code path: no DXVK shader-model gating, no DXVK render-target
  # composite. Older Vision Engine titles often work on wined3d where
  # DXVK's d3d9 fights the engine's caps probe.
  #
  # Round-13: both DXVK (r10/r11) and wined3d (r12) produced the same
  # "world black, cursor visible" symptom — so the renderer isn't the
  # bug. Round-10's VideoSettings.xml seed disabled too many knobs at
  # once. The pitch-dark world is exactly what you'd expect when:
  #   * view_distance=0 culls every world prop
  #   * character/primary_light/secondary_light/rim_light=false turns
  #     the lights off literally
  #   * exposure_control=false leaves linear HDR values way too dark
  #     to see anything (no auto-tonemap to bring midtones into view)
  #   * shadows=false + every detail=0 may also push the engine onto
  #     a fallback path that never composes a frame
  # i.e. the round-10 "post-process disable" hypothesis cast too wide
  # a net: instead of disabling the suspect composite pass alone, it
  # also killed all illumination and exposure. Round-13 strips the
  # seed down to resolution + fullscreen ONLY, letting the engine
  # write its own defaults for every effect attribute. If interactive
  # test still shows a black world we know it's not the seed at all,
  # and round-14 layers attributes back one at a time:
  #   * Iteration B: + tonemap=false   (round-9's narrow hypothesis)
  #   * Iteration C: + shadows=false / dynamic_light_shadows=false
  # See the AttributeTable comment in arcaniaVideoSettingsText for
  # the full list of recognised eSettings names.

  arcaniaVideoSettingsText = ''
    <AttributeTable >
    <Attribute name="resolution_x" type="ulong" value="1920" />
    <Attribute name="resolution_y" type="ulong" value="1080" />
    <Attribute name="fullscreen" type="bool" value="true" />
    </AttributeTable>
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "arcania";

  inherit src;

  ipfsSources = [
    src
    arcaniaWmp11Overlay
  ];

  # zstd needed at runtime by preRun for the wmp11 overlay tarball.
  targetPkgs = p: [ p.zstd ];

  nativeBuildInputs = [
    unzip
    unar
    innoextract
    pkgs.cabextract
    pkgs.binutils-unwrapped
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip" "$TMPDIR/iss"

    # Unpack the archive.org zip (top-level dir
    # `ArcaniA.v2.0.0.2-GOG/`). unzip skips its container without
    # leaving a stray dir level inside $out.
    unzip -q "$src" -d "$TMPDIR/zip"

    # innoextract --gog reads the .exe header + paired .bin RAR chunks
    # via unar. The `game/` subdir is the install root; `app/`,
    # `__unpacker/`, `tmp/` are installer-bootstrap junk.
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/ArcaniA.v2.0.0.2-GOG/setup_arcania_2.0.0.2.exe"
    cp -r "$TMPDIR/iss/game"/. "$out"/
    chmod -R u+w "$out"

    # language_setup.ini documents that the installer normally copies
    # one of Data/configuration/locale.<lang> over Data/configuration/
    # locale.xml at install time (the engine reads `locale.xml` to pick
    # subtitle/UI strings). The unpacked bundle doesn't ship locale.xml;
    # default to English so Arcania.exe doesn't fall back to a stub.
    install -m644 "$out/Data/configuration/locale.en" \
      "$out/Data/configuration/locale.xml"

    # Round-7: stage a genuine PhysX SDK 2.8.1 PhysXCore.dll so preRun
    # can install it into the wineprefix's syswow64. The round-5 dinput8
    # multicore-affinity shim is dropped: the crash was never about CPU
    # cores (the actual EIP=AD97E6 sits inside `Spellbound::
    # PhysicsManagerNx::Init`, not ProcessManagerImpl::StartFromXml as
    # round-5 assumed), and the dinput8 shim was a silentgameplays
    # addon for unrelated multicore *gameplay* issues. ProcessManager.
    # xml keeps its shipped `cores="1"` -- never the blocker.
    #
    # Disassembly of Arcania.exe at +0x6D9776 calls
    # `PhysXLoader.dll!NxCreatePhysicsSDK`, then dereferences the
    # returned interface at +0x6D97E6 (`mov edx, [eax]`) -- the
    # SDK pointer is NULL because PhysXLoader can't bind a compatible
    # PhysXCore. `strings PhysXLoader.dll` shows it looks up
    # `HKLM\Software\Ageia Technologies\PhysXCore Path` and falls back
    # to `enableLocalPhysXCore` next to the .exe. Wine ships neither
    # the registry key nor a builtin PhysXCore.dll. Round-6 staged the
    # cryostasis (2.7.3) PhysXCore which loaded but failed the SDK
    # version handshake. Round-7 extracts the correct 2.8.1 build from
    # NVIDIA's 9.09.0428 System Software redist.
    #
    # The 9.09.0428 redist is a self-extracting cab payload that ships
    # one PhysXCore.dll per supported SDK generation, each suffixed by
    # an InstallShield component GUID. We grab every variant, then
    # pick the one whose string table contains `PhysX_2.8.1_GPU` (the
    # canonical 2.8.1 GPU build that pairs with Arcania's 2.8.1
    # PhysXLoader). cabextract is non-fatal-quiet on the cert section;
    # use `cabextract -F` to limit the dump to physxcore variants.
    # Round-8: in addition to the 2.8.1 PhysXCore.dll, we must also ship
    # `physxcudart_20.dll`. PhysXCore's PE IAT statically imports
    # `physxcudart_20.dll!cudaMalloc/cudaFree/cudaStreamCreate/...` --
    # the round-7 launch died with:
    #   err:module:import_dll Library physxcudart_20.dll (which is needed
    #       by L"C:\\windows\\syswow64\\PhysX\\v2.8.1\\PhysXCore.dll") not found
    #   warn:module:load_dll Failed to load ... PhysXCore.dll; status=c0000135
    # which made PhysXLoader fall back to LoadLibrary failure -> NULL
    # SDK pointer -> the same EIP=AD97E6 deref crash from rounds 5-7.
    # physxcudart_20.dll itself only statically imports KERNEL32; it
    # LoadLibrary's nvcuda.dll lazily, so it loads cleanly under proton
    # on hardware without an NVIDIA GPU -- the actual physics work then
    # runs on the bundled CPU dispatcher inside PhysXCore.
    mkdir -p "$TMPDIR/physx"
    cabextract -q -L -F 'physxcore.dll.*' \
      -d "$TMPDIR/physx" "${arcaniaPhysXRedist}"
    cabextract -q -L -F 'physxcudart_20.dll.*' \
      -d "$TMPDIR/physx" "${arcaniaPhysXRedist}"
    physxcore_281=""
    for cand in "$TMPDIR/physx"/physxcore.dll.*; do
      if strings -a "$cand" | grep -q 'PhysX_2\.8\.1'; then
        physxcore_281="$cand"
        break
      fi
    done
    if [ -z "$physxcore_281" ]; then
      echo "ERROR: no PhysX 2.8.1 PhysXCore.dll found in redist" >&2
      exit 1
    fi
    physxcudart=""
    for cand in "$TMPDIR/physx"/physxcudart_20.dll.*; do
      [ -f "$cand" ] || continue
      physxcudart="$cand"
      break
    done
    if [ -z "$physxcudart" ]; then
      echo "ERROR: no physxcudart_20.dll found in redist" >&2
      exit 1
    fi
    install -m0644 "$physxcore_281" "$out/PhysXCore.dll"
    install -m0644 "$physxcudart" "$out/physxcudart_20.dll"

    # Round-4: Arcania.exe has WMVCore.dll as a hard PE import (winedump
    # -j import confirms it in the IAT alongside d3d9, DINPUT8, etc.).
    # Wine resolves PE imports BEFORE main() runs; with the round-2
    # `WINEDLLOVERRIDES=wmvcore=d` override, wmvcore.dll fails to load at
    # static-link time, the whole process bails with STATUS_DLL_NOT_FOUND
    # (0xc0000135), and nothing is logged because Arcania never reached
    # its own entry point. The launch.log shows exactly:
    #   err:module:import_dll Library WMVCore.DLL ... not found
    #   err:module:loader_init Importing dlls for Arcania.exe failed, c0000135
    # The fix has two parts: (1) drop the wmvcore/quartz override (below
    # in `env`) so wine's builtin wmvcore stub loads -- it returns OK on
    # init, which is all the static import resolver needs; (2) replace
    # the three startup-logo WMVs with a tiny valid ASF stub so wmvcore's
    # decode path never has to actually demux a real movie. WIP.wmv
    # (19 KiB, already shipped) is a known-good ASF file the engine
    # plays without complaint. We keep the bestiary B_*.wmv and the
    # cinematic dummy/fmv*.wmv files untouched -- those play later, by
    # which point the engine is already running and can survive a
    # codec failure without a silent process-wide abort.
    for v in JWD_Logo.wmv Nvidia.wmv SB_Logo.wmv; do
      cp -f "$out/Data/Video/WIP.wmv" "$out/Data/Video/$v"
    done

    # Round-9: stub the two ambient ".dream" videos that the engine
    # references during the Tutorial / dream sequence. Proton issue 770
    # comments (4164696f73, magos-linux) document that ArcaniA crashes
    # without `shine_glowing.wmv` + `shine_turning.wmv`; the GOG v2.0.0.2
    # bundle ships neither (verified `ls Data/Video/`). They live in the
    # Steam build's xpatch but the Complete Tale .pak doesn't expose
    # them as loose files. Reuse the same WIP.wmv ASF stub: wmvcore's
    # decode path opens it cleanly and returns end-of-stream
    # immediately, which the engine treats as "shot finished".
    for v in shine_glowing.wmv shine_turning.wmv; do
      cp -f "$out/Data/Video/WIP.wmv" "$out/Data/Video/$v"
    done

    # Round-9: ship a baseline VideoSettings.xml under the data tree as a
    # build-time source for preRun. preRun seeds it into the user's
    # Documents directories the first time the new build runs (it also
    # compares with the previous build's seed and re-applies on mismatch,
    # so round-8 testers get the postprocessing fix automatically).
    install -m0644 "${pkgs.writeText "arcania-videosettings.xml" arcaniaVideoSettingsText}" \
      "$out/VideoSettings.xml"

    # Round-14: drop a loose Data/configuration/EngineSettings.xml that
    # overrides the pak-baked copy with postprocessing=false. Rounds
    # 10-13 mistargeted the user-side VideoSettings.xml; the engine's
    # `postprocessing` knob is an attribute of
    # Spellbound::SBRendererProcess::eEngineSettings, parsed out of
    # `Configuration\EngineSettings.xml`, NOT VideoSettings::eSettings
    # (which silently drops unknown attribute names). Extracted the
    # original pak-baked EngineSettings.xml by decoding data0.pak's
    # body XOR-0xb6 (SBPAK V1.0 obfuscation -- the leading 64-byte
    # header is plaintext, everything after is a single-byte XOR
    # stream cipher with key 0xb6).
    #
    # Round-15: Conclusive diagnostics show the loose
    # `Data/configuration/EngineSettings.xml` IS read with priority
    # over the pak. Test method: ship a deliberately malformed
    # `<SpellboundApp root-memory="DIAG... ` (broken root attribute
    # quoting) -> startup crashes within 5 s ("Primary child shut
    # down"), proving the engine parses the loose file. A milder
    # break (`<<<garbage>>>` before the root element) survived,
    # because the engine's XML parser tolerates noise before the
    # document root.
    #
    # However, full reverse-engineering of the eEngineSettings enum
    # via Arcania.exe's `Spellbound::Converter<...eEngineSettings>::
    # SetString` string table (offsets 10762380-10762472) shows the
    # enum has only NINE attribute names:
    #   log_files, log_level, gamma, shadow_entity, postprocessing,
    #   fullscreen, resolution_y, resolution_x
    # i.e. there is NO `tonemap`, NO `ssao`, NO `view_distance`, NO
    # `hdr` knob in EngineSettings -- those live in VideoSettings (a
    # different enum), and rounds 10-13 already exhausted that
    # surface. `postprocessing=false` (verified to be parsed) does
    # NOT fix the "world black, cursor visible" symptom: round 14
    # interactive test still shows the bug. shadow_entity is a slong
    # count (not a bool); flipping it won't unbreak rendering.
    #
    # Conclusion: EngineSettings.xml as a fix surface is exhausted.
    # The actual root cause -- per Proton issue #770 (kisak-valve:
    # "this game would benefit from support for wmvcore maturing";
    # `fixme:wmvcore:WMSyncReader_Open ... sb_logo.wmv: stub!`) and
    # the merged GloriousEggroll/protonfixes PR #42
    # (https://github.com/GloriousEggroll/protonfixes/pull/42) which
    # ships `wmp11` via protontricks for AppID 39690 -- is that the
    # MainMenu plays a WMV background through `WMSyncReader`, and
    # wine's builtin wmvcore.dll is a returns-OK-but-decodes-nothing
    # stub. The menu video silently fails -> black plate + cursor.
    # magos-linux's working recipe was Proton 3.7 + `winetricks
    # d3dx9_43 xact physx wmp10`. Round-7 already covers physx;
    # d3dx9_43 is satisfied by proton's bundled d3dx9; xact is
    # satisfied by ge-proton's xactengine. wmp10/wmp11 is what's
    # missing.
    #
    # Round-16 plan: pre-bake a wineprefix with `winetricks wmp11`
    # (mirrors games/magicka's prefix-tarball approach -- preRun
    # runs OUTSIDE proton's FHS chroot so on-the-fly winetricks
    # against proton's wine binary fails on `/lib/ld-linux.so.2`,
    # per games/freelancer/default.nix line 137-139). The bake also
    # needs to register the DirectShow + WMP COM components into
    # system.reg so the engine's CoCreateInstance for
    # CLSID_WMSyncReader resolves.
    #
    # Round-15 keeps the loose EngineSettings.xml in place (it is
    # parsed, it is harmless, it documents that the override
    # mechanism works for future rounds), but the file is no longer
    # claimed as the fix.
    install -m0644 ${./EngineSettings.xml} \
      "$out/Data/configuration/EngineSettings.xml"

    # Strip GOG-launcher / installer side files. The game does not query
    # them at runtime; they only show up in Galaxy.
    rm -f "$out/goggame-"*.dll "$out/goggame-"*.info "$out/goggame-"*.hashdb
  '';

  runtime = "proton";
  executable = "Arcania.exe";

  # Arcania writes savegames + per-user settings under
  # `Documents/ArcaniA - Gothic 4/` (the en-dash U+2013 is part of the
  # path the engine writes -- documented on PCGamingWiki, savegame.pro,
  # and savegameworld). The standalone Fall of Setarrif build wrote to
  # `Documents/ArcaniA - AddOn/` instead; the v2.0.0.2 Complete Tale
  # build keeps both directories alive depending on which campaign the
  # player loads, so relocate both into $STROM_GAMEDIR to survive
  # wineprefix wipes.
  saveLocations = [
    "Documents/ArcaniA – Gothic 4"
    "Documents/ArcaniA – AddOn"
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

  preRun = ''
    # Round-7: install PhysX 2.8.1 PhysXCore.dll into the wineprefix and register
    # the AGEIA root-dir registry key. PhysXLoader.dll's load sequence
    # (verified via `strings PhysXLoader.dll` + a first-pass smoke run
    # which printed `load_dll looking for "C:\windows\syswow64\
    # PhysXCore.dll\v2.8.1\PhysXCore.dll"`) is:
    #   load(<PhysXCore Path>\v<SDK_VERSION>\PhysXCore.dll)
    # The registry value is a DIRECTORY, not a file; PhysXLoader
    # appends `\v<sdk>\PhysXCore.dll` itself. Provide that layout
    # under syswow64\PhysX\. Mirrors the syswow64+system.reg approach
    # in games/bully-scholarship-edition/default.nix.
    pfx="$STROM_COMPATDATA/0/pfx"
    physxdir="$pfx/drive_c/windows/syswow64/PhysX"
    if [ -d "$pfx/drive_c/windows/syswow64" ] && [ -f "$STROM_OVERLAY/PhysXCore.dll" ]; then
      mkdir -p "$physxdir/v2.8.1"
      install -m0644 "$STROM_OVERLAY/PhysXCore.dll" \
        "$physxdir/v2.8.1/PhysXCore.dll"
      # Round-8: PhysXCore.dll's PE imports physxcudart_20.dll. Wine's
      # loader resolves PE import DLLs from the same directory as the
      # importer first, then the system search path. Co-locate it.
      # Also drop a copy into syswow64\ itself so any LoadLibrary by
      # short name from PhysXCore's startup code still resolves.
      if [ -f "$STROM_OVERLAY/physxcudart_20.dll" ]; then
        install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" \
          "$physxdir/v2.8.1/physxcudart_20.dll"
        install -m0644 "$STROM_OVERLAY/physxcudart_20.dll" \
          "$pfx/drive_c/windows/syswow64/physxcudart_20.dll"
      fi
    fi
    SYSREG="$pfx/system.reg"
    # Look for our specific value path. The .reg uses escaped double-
    # backslashes; grep with -F fixed-string matches the exact text.
    # Idempotent: appending a later section with the same key
    # overrides earlier values when wine merges system.reg on startup.
    if [ -f "$SYSREG" ] && ! grep -qF 'syswow64\\PhysX"' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wow6432Node\\\\Ageia Technologies] %s\n' "$(date +%s)"
        printf '"PhysXCore Path"="C:\\\\windows\\\\syswow64\\\\PhysX"\n'
        printf '"enableLocalPhysXCore"=dword:00000001\n'
      } >> "$SYSREG"
    fi

    # Round-16: drop the pre-baked WMP11 / WMF11 native DLL set into
    # syswow64 + append the captured COM registration snapshot to
    # system.reg. Mirrors games/freelancer/default.nix:140-167's
    # directplay overlay pattern.
    #
    # Why: arcania's MainMenu plays a WMV background through
    # WMSyncReader. Wine's builtin wmvcore.dll is a returns-OK-but-
    # decodes-nothing stub (Proton issue #770, magos-linux Proton 3.7
    # recipe, GloriousEggroll/protonfixes PR #42 ships `winetricks
    # wmp11`). With the stub the menu draws a black plate behind the
    # cursor; with the native MS DLLs the codec actually decodes and
    # the background renders.
    #
    # Overlay layout (built host-side by the bake script, see
    # _strom/wmp11/overlay-bake-notes -- not in repo):
    #   syswow64/  - 15 native MS DLLs from wmp11-windowsxp-x86-enu.exe's
    #                inner wmfdist11.exe + wmp11.exe cabs:
    #                  wmvcore wmasf wmadmod wmvdmod wmvdecod wmsdmod
    #                  wmsdmoe2 mfplat wmp wmpnssci qasf msnetobj
    #                  wmnetmgr wmpband wmidx
    #   wmp11.reg  - 1125 sections captured by diffing system.reg after
    #                a regsvr32 pass on the COM-publishable set in a
    #                throwaway wineprefix using the same GE-Proton
    #                wine binary.
    #
    # Sentinel-gated so the drop happens once per prefix bootstrap.
    # Move wine's builtin aside as <name>.builtin first so a future
    # autoWipePrefix or manual winetricks pass can recover. Append the
    # .reg snapshot to system.reg (wine merges duplicate sections on
    # next startup).
    WMP_SENTINEL="$pfx/.strom-wmp11-overlay-installed"
    SYSWOW64="$pfx/drive_c/windows/syswow64"
    if [ -d "$SYSWOW64" ] && [ ! -e "$WMP_SENTINEL" ]; then
      echo "[strom] arcania: dropping native WMP11 / WMF11 overlay" >&2
      __wmp_tmp="$STROM_COMPATDATA/0/.strom-wmp11-stage"
      rm -rf "$__wmp_tmp"
      mkdir -p "$__wmp_tmp"
      tar --zstd -xf ${arcaniaWmp11Overlay} -C "$__wmp_tmp"
      for f in "$__wmp_tmp"/syswow64/*; do
        b=$(basename "$f")
        if [ -e "$SYSWOW64/$b" ] || [ -L "$SYSWOW64/$b" ]; then
          mv -f "$SYSWOW64/$b" "$SYSWOW64/$b.builtin" 2>/dev/null || true
        fi
        cp "$f" "$SYSWOW64/$b"
      done
      if [ -f "$__wmp_tmp/wmp11.reg" ] && [ -f "$SYSREG" ]; then
        # wmp11.reg is already in wine's native system.reg format
        # (section headers + value lines, no WINE REGISTRY header).
        # Append directly; wine merges duplicate sections on startup.
        cat "$__wmp_tmp/wmp11.reg" >> "$SYSREG"
      fi
      rm -rf "$__wmp_tmp"
      touch "$WMP_SENTINEL"
    fi

    # Round-9: seed VideoSettings.xml into both Documents/ArcaniA -
    # Gothic 4/ and Documents/ArcaniA - AddOn/. saveLocations relocates
    # both directories to $STROM_GAMEDIR, so seeding there is what the
    # in-prefix symlinks resolve to.
    #
    # Unlike rounds 5-8 (which seeded only on first launch via
    # `[ ! -f ]`), this round must force-replace stale user copies of
    # the resolution-only seed -- round-8 testers will already have one
    # without the `postprocessing=false` knob, and skipping the seed
    # leaves them stuck on the black-world bug. Gate with a sentinel
    # file holding the seed's content hash; reapply only when the
    # shipped seed itself changes, so user in-game edits survive
    # subsequent launches once they've stamped their own choice. Saves
    # under `*-Gothic 4/Save/` are untouched.
    __strom_arc_seed="$STROM_OVERLAY/VideoSettings.xml"
    __strom_arc_seed_hash=$(sha256sum "$__strom_arc_seed" | cut -d' ' -f1)
    for __strom_arc_dir in \
        "$STROM_GAMEDIR/ArcaniA – Gothic 4" \
        "$STROM_GAMEDIR/ArcaniA – AddOn"; do
      mkdir -p "$__strom_arc_dir"
      __strom_arc_stamp="$__strom_arc_dir/.strom-videosettings-seed.sha256"
      if [ ! -f "$__strom_arc_stamp" ] \
          || [ "$(cat "$__strom_arc_stamp" 2>/dev/null)" \
                != "$__strom_arc_seed_hash" ]; then
        install -m644 "$__strom_arc_seed" \
          "$__strom_arc_dir/VideoSettings.xml"
        printf '%s\n' "$__strom_arc_seed_hash" > "$__strom_arc_stamp"
      fi
    done
  '';

  env = {
    # 32-bit Vision engine title; the 4 GiB-aware flag lets the LAA
    # patched build (GOG v2.0.0.2 ships with /LARGEADDRESSAWARE set in
    # the PE header) actually use the full 4 GiB user-mode VA window
    # under wine.
    WINE_LARGE_ADDRESS_AWARE = "1";

    # Round-12: force wine's builtin d3d9 (wined3d -> OpenGL) instead
    # of Proton's DXVK d3d9. Round-11's dxvk.conf SM2 clamp + 2 GiB
    # cap + GTX 460 spoof regressed from "menu reaches, world black"
    # to "exits on startup interactively" — the Vision Engine likely
    # needs SM3 to even initialise its renderer. wined3d is a
    # different translation layer (D3D9 -> OpenGL via wine's builtin
    # d3d9.dll) that bypasses DXVK entirely; on older d3d9 titles
    # where DXVK's frontend fights the engine's caps probe this often
    # works without altering the engine's shader caps. Proton ships
    # DXVK as `c:\windows\syswow64\d3d9.dll`; `=b` pins the builtin.
    #
    # Round-16: force native for the WMP11 / WMF11 DLL set the preRun
    # overlay drops into syswow64. Without `=n` wine's loader can
    # still pick the builtin stub when both are present (the override
    # is the loader-level switch; the DllRegisterServer pass we did
    # in the bake only writes the COM CLSID->path entries to
    # system.reg). The native set must win for WMSyncReader_Open to
    # actually demux the MainMenu's WMV background instead of
    # returning OK-but-decoding-nothing.
    WINEDLLOVERRIDES = lib.concatStringsSep ";" [
      "d3d9=b"
      "wmvcore,wmasf,wmadmod,wmvdmod,wmvdecod,wmsdmod,wmsdmoe2,mfplat,wmp,wmpnssci,qasf,msnetobj,wmnetmgr,wmpband,wmidx=n"
    ];

    # Round-4: NO WINEDLLOVERRIDES for wmvcore/quartz. The round-2
    # attempt to disable wmvcore (=d) silently killed startup because
    # Arcania.exe imports WMVCore.dll statically -- wine's loader
    # refuses to bind the IAT when the dll is overridden to "disabled",
    # and the process exits with c0000135 before main() runs. The
    # startup-video issue round-2 was trying to dodge is instead
    # handled at build time by swapping the three intro logos for a
    # known-good tiny ASF stub (see buildScript above); wine's builtin
    # wmvcore loads happily and plays the stub in milliseconds.
  };

  meta = {
    description = "ArcaniA: Gothic 4 -- The Complete Tale (Spellbound 2010, GOG v2.0.0.2, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "arcania";
  };
}
