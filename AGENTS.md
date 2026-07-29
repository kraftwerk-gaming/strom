# Rules for AI agents working on this repo

## Game naming

- Game directory names under `games/` and the `name =` field in `default.nix` **must** use the **Lutris slug** as the canonical identifier.
- Look up the slug at `https://lutris.net/api/games?search=<game>` or `https://lutris.net/api/games/<slug>` before adding a new game.
- The flake attribute name = directory name = Lutris slug. No exceptions.
- Internal variable names (nix let bindings, fetchurl `name =`) don't need to follow the slug — they describe the actual artifact.

## Formatting

- All `.nix` files must be `nixfmt`-clean. Run `nix fmt` before committing.
- `nix flake check` runs `checks.<system>.nixfmt` which fails on any tracked unformatted file.

## Metadata sync (sync-metadata.py)

- After adding or removing a game, run `python3 scripts/sync-metadata.py`.
- It reads flake metadata via `scripts/sync-metadata.nix` and writes each game's flake-projected build keys (`cids`, `description`, `runtime`) into `games/<slug>/metadata.json`, merged over hand-authored keys (which are left untouched). Do not hand-edit those build keys. It touches only per-game files -- there is no committed games list, README table, or `web/games.json` -- so concurrent game additions never clash on a shared file. The launcher and web GUI build the game list by reading the per-game files directly (the GUI from its local server or the public Radicle repo; the launcher from the `games/` dir), so there is no `catalog.json`.

## Game display metadata (steam.json + metadata.json)

- Per-game display metadata lives in two optional files under `games/<slug>/`:
  - `steam.json`: Steam-fetched fields (`name`, `short`, `long`, `genres`, player-mode `tags`, `year`, `developers`, `hero`, `screenshots`, `steam_appid`). Written by `scripts/fetch-steam-metadata.py`; treat it as a committed cache, do not hand-edit.
  - `metadata.json`: hand-maintained data. For a Steam game it holds only the corrected fields, overlaid over `steam.json` (lists replace, they do not append). For an off-Steam game it is the whole entry and there is no `steam.json`. Recognized display fields: `name`, `short`, `long`, `genres` (list), `tags` (list), `year` (int), `developers` (list), `hero` (URL), `screenshots` (list of URLs), `lutris` (URL). Plus a non-display `appid` directive (below). Keys starting with `_` are comments. See `games/battlefield-2/metadata.json`.
  - Generated build keys (`cids`, `description`, `runtime`) are also written into `metadata.json` by `sync-metadata.py` (flake projections of `default.nix`); they are not display fields (the launcher and web GUI ignore them when merging), and must not be hand-edited.
- There is no `catalog.json`. The display catalog (steam.json overlaid by metadata.json's display fields, runtime from metadata.json) is assembled by reading the per-game files directly: the web GUI (`web/gui`, `nix run .#gui`) does it in the browser -- from its local server, or from a Radicle node's radicle-httpd API when served from one -- and the couch launcher (`pkgs/launcher`) reads the `games/` dir at startup.
- Steam matching is driven by `metadata.json`'s `appid`: an integer forces a specific Steam appid; `null` skips Steam entirely (GOG-only, fan ports, abandonware, delisted titles; no `steam.json` is written); absent means auto fuzzy-match by name. This replaces the old `scripts/steam-overrides.json`.
- `python3 scripts/fetch-steam-metadata.py` writes/refreshes per-game `steam.json`. It is incremental: a game that already has a `steam.json` is left alone. Pass explicit slugs or `--refresh` to re-fetch, `--offline` to never hit the network. A game with no Steam match and no hand-authored curation gets fallback display fields merged into its `metadata.json` (name from description, lutris banner); curated metadata and the generated build keys are preserved. Raw API responses cache under `web/.steam-cache/` (gitignored). It never writes `catalog.json`.
- When adding a game, run `python3 scripts/fetch-steam-metadata.py <slug>` (after `sync-metadata.py`) so it gets a `steam.json`, or hand-write a `metadata.json` for an off-Steam title.
- `tags` drive the Features filter (web GUI) and the couch launcher's filter bar. Use these exact Steam-category strings so a game lands in the right bucket:
  - Single-player: `Single-player`
  - Online multiplayer: `Multi-player`, `Online PvP`, `Cross-Platform Multiplayer`
  - Local multiplayer: `Shared/Split Screen`, `Shared/Split Screen PvP`, `LAN PvP`
  - Online co-op: `Online Co-op`
  - Local co-op: `Shared/Split Screen Co-op`, `LAN Co-op`
  - Remote Play Together: `Remote Play Together`
  - PvP: `PvP`, `Online PvP`, `Shared/Split Screen PvP`, `LAN PvP`
- `steam.json` / `metadata.json` are inert for the Nix build (`callPackage` imports `default.nix` only); they are read only by the catalog assembler and the fetch script.
- The GUI derives a data-source marker from `steam_appid`: entries with no Steam match render a community badge and can be filtered via the Metadata facet, so it is always visible which games are hand-curated vs. pulled from Steam. It follows automatically from whether the game matched Steam.

## IPFS and fetchIpfs

- Game files are fetched via `fetchIpfs` (`lib/fetch-ipfs.nix`), which uses `aria2c` to fetch the CIDs from public gateways.
- CIDs in this repo are generated with `ipfs add --raw-leaves`. A plain `ipfs add` without `--raw-leaves` produces a **different CID** for the same file. Always use `--raw-leaves` when adding files to match the CIDs in this repo. (`--nocopy` implies `--raw-leaves`; `--only-hash` does NOT, so it must be paired with `--raw-leaves` explicitly.)
- When adding a new game, get the CID from `ipfs add --only-hash --raw-leaves` and use `fetchIpfs { cid = "..."; fallbackUrl = "https://archive.org/..."; hash = "sha256-..."; name = "..."; }`.
- Files not yet pinned on a reachable node are not discoverable via IPFS. The file must be pinned on at least one reachable node.

## Packaging PS2 games (PCSX2)

- PS2 games use `lib/pcsx2.nix`, which provides the shared BIOS, a default
  PCSX2.ini (controller mappings, speedhacks, recompiler settings), and the
  launch wrapper. It is a wrapperModule, reached through `mkGame` as
  `runtime = "pcsx2"` -- there is no `mkPcsx2Game` function.
- Direct ISO (`games/burnout-3-takedown/default.nix`):

      self.lib.mkGame { inherit lib pkgs; } {
        name = "my-game";                 # lutris slug
        src = fetchIpfs { ... };
        runtime = "pcsx2";
        executable = "my-game.iso";       # path inside the overlay
        meta = { ... };
      }

- Archive source (`games/shadow-of-the-colossus/default.nix`): unpack in
  `buildScript` and point `executable` at the ISO the archive contained.

      nativeBuildInputs = [ pkgs.unzip ];
      buildScript = ''
        mkdir -p $out
        unzip "$src" -d $out
      '';
      executable = "Shadow of the Colossus (USA).iso";

- The PS2 BIOS and fetchIpfs are constructed internally by lib/pcsx2.nix,
  and the BIOS is added to `ipfsSources` automatically. Do NOT duplicate the
  BIOS fetch or PCSX2 config in individual game files. Use `pcsx2.extraIni`
  for game-specific INI overrides only.

## Packaging GameCube / Wii games (Dolphin)

- GC/Wii games use `lib/dolphin.nix` via `runtime = "dolphin"`. Same shape as
  pcsx2: the disc image is `executable` (a path inside the overlay), and the
  helper owns everything else. See `games/pikmin/default.nix` (`.ciso`) and
  `games/super-smash-bros-melee/default.nix` (`.iso`).
- Dolphin accepts `.iso`, `.gcm`, `.ciso`, `.rvz`, `.wbfs`. Package whatever
  container the verified dump ships as; don't recompress.
- The helper puts Dolphin's user dir at `$STROM_GAMEDIR/dolphin-user`, so
  memory cards, save states and Wii NAND live with the game rather than in
  the user's global `~/.local/share`. Nothing needs `saveLocations` (that
  option is proton-only).
- Config seeding is **write-if-absent**, not overwrite-per-launch: Dolphin
  owns these files at runtime and rewrites them on exit, and remapping a pad
  through its GUI is how a couch setup gets adjusted. On first run the helper
  writes an analytics opt-out `Dolphin.ini` and, when an SDL gamepad is
  present, a `GCPadNew.ini` mirroring Dolphin's bundled "SDL Gamepad" profile
  plus keyboard fallback.
- Options: `dolphin.extraIni` (extra Dolphin.ini fragments, first-run only --
  section headers MUST start at column 0, Dolphin's IniFile::Load does not
  strip leading whitespace) and `dolphin.seedGamepad` (set false for a game
  shipping its own mapping).

## Windows compatibility runtime: Proton, never bare Wine

- This project uses **Proton (GE-Proton10-34) exclusively**. The bundled binaries live at `${proton}/files/bin/` and are invoked through `lib/proton.nix` / `mk-game.nix`.
- **Never invoke bare `wine`, `wineboot`, `winecfg`, `winetricks`, `wineserver`** anywhere — including build-time tooling, preRun scripts, agent diagnostics, or one-off shell commands. Bare wine on a Proton-managed prefix produces UI popups (Mono/Gecko prompts, debugger dialogs) and corrupts wineserver lifecycle.
- **Never `pkgs.wine` / `pkgs.wineWowPackages.*` / `pkgs.wineWow64Packages.*`** in `default.nix` files. Use the project's Proton derivation: `proton = pkgs.callPackage ../../pkgs/proton.nix { };` then `${proton}/files/bin/wine`.
- For prefix registry tweaks: edit `system.reg` / `user.reg` files directly with `sed`/`cat` from preRun (after the prefix exists), NOT via `wine reg add`.
- For `winetricks`-style verb installs (vcrun, dotnet, dxvk, etc.): manually drop the DLLs into the prefix's `system32`/`syswow64` from buildScript or preRun. Don't shell out to winetricks.

## Verify headless; never fullscreen or non-gamescope GUIs on `DISPLAY=:0`

- **Normal package verification runs gamescope HEADLESS**, not on the operator's seat: launch the game with gamescope's headless backend plus the screenshot sidecar (`STROM_AGENT_DEBUG=1`, see `lib/screenshot.nix` / `lib/screenshot-sidecar.sh`). gamescope renders offscreen and the sidecar captures PNG frames from the nested `gamescope-*` wayland socket — the operator's `DISPLAY=:0` session is never touched.
- **`WLR_BACKENDS=headless` alone is NOT sufficient** (measured on gamescope 3.16.25): wlserver comes up headless but the output backend still opens `/dev/dri/card1` and dies with "Could not open KMS device". Pass `--backend headless` (e.g. via `GAMESCOPE_ARGS`) — that is the knob that works. Unset the host `WAYLAND_DISPLAY` / `DISPLAY` as well.
- The agent MAY run gamescope nested on `DISPLAY=:0` when necessary, but it is not the default, and then: **NEVER fullscreen** — no `-f` / `--fullscreen` or any flag that grabs the whole output; fullscreen takes over the operator's display and input and locks them out of the machine. Keep it a windowed nested surface.
- **NEVER run any non-gamescope GUI on `:0`.** No bare `proton` / `wine` / `steam-run` GUI binary, no raw installer (e.g. InstallShield `Setup.exe`), nothing that opens a window outside gamescope. Such a window grabs input on the operator's real desktop. This happened once (a HoI2 `Setup.exe` run under Proton + steam-run straight on `:0`); it must never happen again.
- If a package can only be advanced by a real interactive GUI step (e.g. an InstallShield wizard prompting for a serial), that step is **out of scope for the agent**: stage it `broken`, document the blocker, and leave it for the operator.
- Headless build steps (nix builds, archive extraction, autopatchelf) open no window and are always fine.

## Audio measurement: isolate on your own null sink, never touch the operator's streams

- The operator is usually sitting at this machine with audio playing. A test run that
  reaches their speakers, or that hijacks their streams, is a defect in the harness --
  it has happened twice: a Mass Effect 2 test instance played through their speakers for
  15 minutes, and a name-matching "sink guard" loop moved the operator's Firefox stream
  onto a test null sink, killing their audio mid-session.
- To measure a game's audio: create a dedicated null sink
  (`pactl load-module module-null-sink sink_name=stromtest_<slug> ...`), route only your
  own game to it, and record from `stromtest_<slug>.monitor` with `parec`/`sox`. Report
  peak and RMS dBFS. Unload the module when you are done -- do not leave `stromtest_*`
  sinks loaded.
- **`PULSE_SINK` alone does NOT isolate ANY runtime -- not just Proton.** Two independent
  measurements: a Proton game reaches the server through pipewire-alsa (streams appear as
  `PipeWire ALSA [wine64-preloader]`), and a fully NATIVE game (dhewm3, no wine anywhere)
  escaped it too because openal-soft 1.24.3 uses its native PipeWire backend. Neither path
  consults libpulse, so the `PULSE_SINK` hint is never read. Treat it as
  necessary-but-not-sufficient everywhere.
- **`PIPEWIRE_NODE=<sink-name>` is the knob that works**, and it is an unconditional
  override rather than a fallback: pipewire's `src/pipewire/stream.c` sets
  `PW_KEY_TARGET_OBJECT` from it unguarded, AFTER stream.rules matching, so it beats what
  the app itself asked for; `pipewire-alsa/alsa-plugins/pcm_pipewire.c` has the identical
  line, which is why it also covers wine. It accepts a `node.name`, so the null-sink name
  works directly. Set BOTH `PIPEWIRE_NODE` and `PULSE_SINK` at launch (belt and braces
  across backends), then gate measurement on reading back the sink-input's Sink index.
- If a run does NOT need an audio measurement, the strongest isolation is to make the sink
  unreachable rather than merely retargeted: point `PULSE_SERVER` / `PIPEWIRE_REMOTE` at
  nonexistent sockets. Nothing to move, nothing to clean up, and the operator's sink cannot
  be reached even by a misconfigured client.
- **NEVER `pactl set-default-sink`, and never move a stream you do not own.** If you move
  streams at all, select them by verifying the sink-input's client PID is a descendant of
  the process you launched (walk `/proc`). Never select by `application.name`, by a
  wine/game-name regex, or by "the newest N" -- names are not identity, and the operator's
  browser is not your game.
- Before measuring, assert isolation: every sink-input on your test sink is yours, and no
  stream of yours is on the hardware sink.
- If isolation cannot be achieved with confidence, the correct outcome is to report
  "audio not measured, isolation not achievable by mechanism X" and move on. An honest
  non-measurement beats both a fabricated number and a disturbed operator.

## Stage-branch workflow for untested games

- The `rad` remote is the canonical destination for this repo. `github` is a mirror.
- Untested or in-progress packages live on a `stage/<slug>` branch pushed to `rad` as a plain git branch — never directly on `master`. Master is reserved for games that have been interactively tested AND have a real IPFS-pinned CID.
- We do **not** use `rad patch` for game staging. Push the branch with `git push rad stage/<slug>` and link it from the issue. The patch flow added overhead (draft/open/ready state, revision-update commands, auto-merge detection) without buying anything we needed. See `docs/request-game-workflow.md` for the full procedure.
- Stage-commit subject: `<slug>: stage (untested, awaiting IPFS pin)` (or `stage (broken - <why>)`, `stage (tested, awaiting IPFS pin)`, etc.). The parenthetical describes the state.
- Stage-commit body MUST contain `Issue: <id>` as a Git trailer so the commit ties back to the original `package-request` issue without needing rad-issue search. Recommended template:

      <slug>: stage (untested, awaiting IPFS pin)

      Issue: <full-or-short-issue-id>
      Source: <fetch URL the FOD points at>
      Runtime: <native|proton|pcsx2|retroarch+swanstation|dolphin|...>

- Master-commit subject: `<slug>: init`. Don't carry `stage` into master. The `Issue:` trailer survives the amend.
- **One commit per game on master.** After the test passes AND the CID has been pinned, rebase the stage commit onto master and amend its subject from `stage (...)` to `init`. Don't ship two commits (`init` with `PENDING_UPLOAD` + later `update CID`).
- **`saveLocations` is required for every `runtime = "proton"` game before its commit lands on master.** Proton's `$HOME` is tmpfs'd in the bwrap sandbox — anything the engine writes into `drive_c/users/steamuser/...` evaporates with the wineprefix. Without `saveLocations`, user progress dies on the next prefix wipe (which the launcher does automatically when the proton-version pointer is GC'd, or which the iterative test loop does between fix attempts). The only legitimate empty-or-absent case is a game that writes saves *next to its binary in the install dir* — those persist via the per-game fuse-overlayfs upper. If that's the case, leave a comment in `default.nix` explaining it (search `games/portal/default.nix`, `games/magicka/default.nix` for the pattern). The discovery procedure is in `## Save preservation across prefix wipes` below; the canonical paths to check are `AppData/LocalLow/<vendor>/<game>`, `AppData/Roaming/<game>`, `Documents/<game>`, and `Documents/My Games/<game>`.
- Merge flow:
  1. On `stage/<slug>`: rebase on master, amend subject `stage (...)` -> `init`.
  3. `git checkout master && git merge --ff-only stage/<slug>`.
  4. `rad issue comment <issue-id> --message "merged to master as <sha>."`.
  5. `git worktree remove ~/tmp/strom/<slug>`, then `git branch -d stage/<slug>`, then `git push rad :stage/<slug>`. (Worktree before branch — `git branch -d` errors otherwise.)
- The operator pushes `rad master` themselves; the agent never runs `git push rad master`.
- **Never delete unmerged stage branches.** Even broken-in-progress games keep their `stage/<slug>` branch on rad so future-you (or another contributor) has the diff, diagnostic notes, and history in one place. Delete only after merge or after the issue is explicitly abandoned.
- Listing: `git branch -r | grep stage/` (all in-flight stage branches), `git log rad/master..rad/stage/<slug>` (the diff a particular stage adds), `rad issue show <id>` for the request context.
- `git reset --hard` without explicit user permission AND a backup of any uncommitted work is forbidden. Default to `--mixed`. Intent-to-add files (`git add -N`) leave no recoverable blob after `--hard`.

## IPFS pinning only after testing

- Game files must be IPFS-pinned (on at least one reachable node) before they're useful to other users. **Don't pin a multi-GB asset to a remote/public node until interactive testing has confirmed the package works** - wasted bandwidth if the package never runs.
- Phase 1 (stage): download -> hash -> `nix store add-file --hash-algo sha256 --name <name> /path/to/file` (seeds the local store with the file under fetchIpfs's expected output path) -> write `default.nix` with `cid = "$HASH"` a real CID you can get by `ipfs add --only-hash --raw-leaves`. Build verifies locally because the FOD output path is already realized.
- Phase 2 (test): user runs `nix run .#<game>` and confirms it works.
- Phase 3 (only after Phase 2 passes): pin the file on whatever IPFS node(s) the operator uses (public/pin host), update `cid` if it was still `PENDING_UPLOAD`, rebuild. The exact pinning method is out of scope for this file - operator-specific.

## fetchIpfs fallbackUrl must NOT be an IPFS gateway

- `fetchIpfs` already races multiple IPFS gateways (`ipfs.io`, `dweb.link`, `gateway.pinata.cloud`, `w3s.link`, `nftstorage.link`) in parallel via aria2c Range requests, plus any private mirror injected via `STROM_IPFS_GATEWAYS`. `fallbackUrl` exists for the curl-based escape hatch when the IPFS retrieval pipeline is broken.
- **Never set `fallbackUrl` to `https://ipfs.io/ipfs/<CID>` / `https://dweb.link/ipfs/<CID>` / any IPFS gateway URL.** Same CID + same gateway pool = no recovery value when the IPFS path fails.
- `fallbackUrl` should always point at a non-IPFS source: archive.org item, GOG/publisher CDN, project's own release URL. If no equivalent non-IPFS URL exists with matching bytes, leave `fallbackUrl = ""` (empty) OR document the upstream archive item even if the bytes differ (zip vs 7z) — the URL doubles as documentation.

## Game data directories (~/.strom/<game>)

- **NEVER delete a game directory** (`rm -rf ~/.strom/<game>`). These contain user saves, profiles, and Wine prefixes that cannot be recovered.
- Game wrappers must be idempotent: re-running after a nix rebuild should update symlinks/configs without touching user data.
- When debugging, fix files in place (chmod, sed, etc.) instead of recreating the directory.
- If you must test with a clean state, back up `SAVEGAMES/`, `compatdata/`, and any user-created files first.

## Save preservation across prefix wipes

- `~/.strom/.compatdata/<game>` (the wineprefix) is treated as **disposable**. The launcher's auto-wipe blows it away when DLL symlinks point at a garbage-collected proton store path, and the iterative test loop wipes it freely between fix attempts.
- Anything the game writes under the wineprefix (saves, profiles, settings, shader caches) MUST be relocated to `~/.strom/<game>` so a wipe doesn't take user progress with it. Use the `saveLocations` option on `mkGame` — see `lib/mk-game.nix` for the contract. Each entry is a path relative to `drive_c/users/steamuser/`.
- **This is enforced by `lib/mk-game.nix`.** `runtime = "proton"` without an explicit `saveLocations` throws at eval time. The legitimate empty case (saves go next to the binary in the overlay) requires writing `saveLocations = [ ]` explicitly, with a `# ...` comment explaining why.
- **Before committing a new proton game**, launch it once, play far enough to write a save, then check `find ~/.strom/.compatdata/<game>/0/pfx/drive_c/users/steamuser -mindepth 2 -newer <reference>` for any non-Microsoft directory the engine created. Add each one to `saveLocations`. Common locations:
  - `AppData/Roaming/<vendor>/<game>` — user settings, saves
  - `AppData/Local/<vendor>/<game>` — local-machine state, configs, mod data
  - `Documents/<game>` or `Documents/My Games/<game>` — savegames for older titles
- Verify by wiping `~/.strom/.compatdata/<game>` and re-launching: any prior settings/saves you confirmed should still be there.

## Customizing a game (mods, flag overrides)

- `flake.modules.<arch>.<slug>` IS the wrapperModule built by `lib/mk-game.nix` — the same object `packages.<arch>.<slug>` is derived from via `.outputs.wrapper`. Use `.apply { ... }.outputs.wrapper` to derive a customized build without forking the game's `default.nix`:

      strom.modules.x86_64-linux.balatro.apply {
        gamescope.flags."--immediate-flips" = lib.mkForce false;
        targetPkgs = p: [ p.some-mod-runtime-lib ];
        preRun = ''
          cp -r ${mods}/. "$STROM_OVERLAY/Mods/"
        '';
      }.outputs.wrapper

  Use `lib.mkForce` when overriding a value the game's `default.nix` already sets (`gamescope.flags`, `env`, etc.) — otherwise the module system reports a definition conflict.

- Top-level options (`name`, `src`, `executable`, `executableArgs`, `runtime`, `buildScript`, `preRun`, `runScript`, `saveLocations`, `copyGlobs`, `targetPkgs`, `ipfsSources`, `env`, `padToKb`, ...) are defined in `lib/mk-game.nix`.
- Sub-wrapper options live under `gamescope.*`, `proton.*`, `fhs.*`, `bwrap.*`, `pcsx2.*`, `retroarch.*`, `fuseOverlayfs.*`, `padToKb.*`. Their schema is the `lib/<name>.nix` file of the matching wrapper.
- `flake.packages.<arch>.<slug>` is unchanged: still the default-args derivation, still what `nix run .#<game>` builds.

- Think before acting. Read existing files before writing code.
- Be concise in responses but thorough in reasoning.
- Prefer editing over rewriting whole files.
- Do not re-read files you have already read.
- No sycophantic openers or closing fluff.
- No em dashes, smart quotes, or Unicode characters. ASCII only.
- Keep solutions simple and direct. No over-engineering.
- If unsure: say so. Never guess or invent file paths and function names.
- If a user corrects a factual claim: treat it as ground truth. Never re-assert the original.
- User instructions always override this file.
