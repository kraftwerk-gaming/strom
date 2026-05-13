# Rules for AI agents working on this repo

## Game naming

- Game directory names under `games/` and the `name =` field in `default.nix` **must** use the **Lutris slug** as the canonical identifier.
- Look up the slug at `https://lutris.net/api/games?search=<game>` or `https://lutris.net/api/games/<slug>` before adding a new game.
- The flake attribute name = directory name = Lutris slug. No exceptions.
- Internal variable names (nix let bindings, fetchurl `name =`) don't need to follow the slug — they describe the actual artifact.

## Formatting

- All `.nix` files must be `nixfmt`-clean. Run `nix fmt` before committing.
- `nix flake check` runs `checks.<system>.nixfmt` which fails on any tracked unformatted file.

## README and games.json

- After adding or removing a game, regenerate both the games table and the JSON metadata: `python3 scripts/generate-readme.py`
- The script reads flake metadata via `scripts/generate-readme.nix`, rewrites the block between the `<!-- BEGIN/END GENERATED GAMES -->` markers in `README.md`, and writes `web/games.json` (consumed by the static checker at `web/index.html`). Do not edit either generated file by hand.

## IPFS and fetchIpfs

- Game files are fetched via `fetchIpfs` (`lib/fetch-ipfs.nix`), which uses `ipget` to spawn a temporary IPFS node and fetch by CID from the DHT. Falls back to archive.org if IPFS fails.
- CIDs in this repo are generated with `ipfs add --raw-leaves`. A plain `ipfs add` without `--raw-leaves` produces a **different CID** for the same file. Always use `--raw-leaves` when adding files to match the CIDs in this repo. (`--nocopy` implies `--raw-leaves` and is fine too; it just additionally enables filestore in-place referencing.)
- To add a new game file to IPFS: place it on the operator's pin host. A pin watcher service auto-pins it (with `--nocopy`, so `--raw-leaves` is implied) and records the CID in the host's `cid-map.txt`.
- When adding a new game, get the CID from `cid-map.txt` and use `fetchIpfs { cid = "..."; fallbackUrl = "https://archive.org/..."; hash = "sha256-..."; name = "..."; }`.
- Files not yet pinned on a reachable node are not discoverable via IPFS. The file must be pinned on at least one reachable node.

## Packaging PS2 games (PCSX2)

- PS2 games use `lib/pcsx2.nix`, which provides the shared BIOS, a default
  PCSX2.ini (controller mappings, speedhacks, recompiler settings), and the
  launch wrapper.
- Import the helper and call `mkPcsx2Game`:

      mkPcsx2Game = self.lib.mkPcsx2Game { inherit lib pkgs; };

      mkPcsx2Game {
        name = "my-game";            # lutris slug
        src = fetchIpfs { ... };     # game source (fetchIpfs derivation)
        description = "My Game (via PCSX2)";
        # gamePath = "...";          # optional: override ISO path when src
        #                            # is not a direct ISO (e.g. zip)
        # extraIni = "...";          # optional: extra INI sections appended
      };

- `src` is the fetchIpfs derivation for the game. It is used for IPFS
  pinning (ipfsSources) and, by default, as the ISO path passed to PCSX2.
- If the source is a zip/archive, extract it with `runCommandLocal` and
  pass the extracted ISO path via `gamePath`.
- The PS2 BIOS and fetchIpfs are constructed internally by lib/pcsx2.nix.
  Do NOT duplicate the BIOS fetch or PCSX2 config in individual game files.
  Use `extraIni` for game-specific overrides only.
- See `games/burnout-3-takedown/default.nix` (direct ISO) and
  `games/shadow-of-the-colossus/default.nix` (zip -> extract -> ISO) for
  examples of both patterns.

## Windows compatibility runtime: Proton, never bare Wine

- This project uses **Proton (GE-Proton10-34) exclusively**. The bundled binaries live at `${proton}/files/bin/` and are invoked through `lib/proton.nix` / `mk-game.nix`.
- **Never invoke bare `wine`, `wineboot`, `winecfg`, `winetricks`, `wineserver`** anywhere — including build-time tooling, preRun scripts, agent diagnostics, or one-off shell commands. Bare wine on a Proton-managed prefix produces UI popups (Mono/Gecko prompts, debugger dialogs) and corrupts wineserver lifecycle.
- **Never `pkgs.wine` / `pkgs.wineWowPackages.*` / `pkgs.wineWow64Packages.*`** in `default.nix` files. Use the project's Proton derivation: `proton = pkgs.callPackage ../../pkgs/proton.nix { };` then `${proton}/files/bin/wine`.
- For prefix registry tweaks: edit `system.reg` / `user.reg` files directly with `sed`/`cat` from preRun (after the prefix exists), NOT via `wine reg add`.
- For `winetricks`-style verb installs (vcrun, dotnet, dxvk, etc.): manually drop the DLLs into the prefix's `system32`/`syswow64` from buildScript or preRun. Don't shell out to winetricks.

## Radicle patch workflow for untested games

- The `rad` remote is the canonical destination for this repo. `github` is a mirror.
- Untested or in-progress packages live on a `patches/<slug>` branch pushed as a Radicle patch — never directly on `master`. Master is reserved for games that have been interactively tested AND have a real IPFS-pinned CID.
- Stage-commit subject: `<slug>: stage (untested, ...)` (or `stage (broken — <why>)`, `stage (tested, awaiting IPFS pin)`, etc.). The parenthetical describes the state.
- Master-commit subject: `<slug>: init`. Don't carry `stage` into master.
- **One commit per game on master.** After the test passes AND the CID has been pinned, rebase the patch commit onto master and amend its subject from `stage (…)` to `init`. Don't ship two commits (`init` with `PENDING_UPLOAD` + later `update CID`).
- Merge flow:
  1. On `patches/<slug>`: rebase on master, amend `stage (…)` → `init`.
  2. `rad patch update <patch-id>` — pushes the rebased+amended commit as a new revision of the patch.
  3. `rad patch ready <patch-id>` — moves the patch from draft to open (required for auto-merge detection).
  4. `git checkout master && git merge --ff-only patches/<slug>`.
  5. `git push rad master` — radicle sees the patch's HEAD reachable from master and auto-marks the patch **merged**, preserving review/comment history.
  6. `git branch -d patches/<slug>` (or `-D` if radicle's tracking ref is stale).
- **Never archive game patches.** Even broken-in-progress games keep their patch open so future-you (or another contributor) has the diff, diagnostic notes, and revision history in one place. `rad patch archive` is only appropriate for non-game patches (lib/infrastructure refactors, tooling experiments) that get abandoned without landing.
- Listing: `rad patch list` (open), `rad patch list --all` (all states), `rad patch show <id>` for revision history.
- `git reset --hard` without explicit user permission AND a backup of any uncommitted work is forbidden. Default to `--mixed`. Intent-to-add files (`git add -N`) leave no recoverable blob after `--hard`.

## IPFS pinning only after testing

- Game files must be IPFS-pinned (on at least one reachable node) before they're useful to other users. **Don't pin a multi-GB asset until interactive testing has confirmed the package works** — wasted bandwidth if the package never runs.
- Phase 1 (stage): download → hash → `nix store add-file --hash-algo sha256 --name <name> /path/to/file` (seeds the local store with the file under fetchIpfs's expected output path) → write `default.nix` with `cid = "PENDING_UPLOAD"`. Build verifies locally because the FOD output path is already realized.
- Phase 2 (test): user runs `nix run .#<game>` and confirms it works.
- Phase 3 (only after Phase 2 passes): pin the file on whatever IPFS node(s) the operator uses, get the CID, update `cid` in `default.nix`, rebuild. The exact pinning method is out of scope for this file — operator-specific.

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
- **Before committing a new proton game**, launch it once, play far enough to write a save, then check `find ~/.strom/.compatdata/<game>/0/pfx/drive_c/users/steamuser -mindepth 2 -newer <reference>` for any non-Microsoft directory the engine created. Add each one to `saveLocations`. Common locations:
  - `AppData/Roaming/<vendor>/<game>` — user settings, saves
  - `AppData/Local/<vendor>/<game>` — local-machine state, configs, mod data
  - `Documents/<game>` or `Documents/My Games/<game>` — savegames for older titles
- Verify by wiping `~/.strom/.compatdata/<game>` and re-launching: any prior settings/saves you confirmed should still be there.
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
