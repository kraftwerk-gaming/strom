# Rules for AI agents working on this repo

## Game naming

- Game directory names under `games/` and the `name =` field in `default.nix` **must** use the **Lutris slug** as the canonical identifier.
- Look up the slug at `https://lutris.net/api/games?search=<game>` or `https://lutris.net/api/games/<slug>` before adding a new game.
- The flake attribute name = directory name = Lutris slug. No exceptions.
- Internal variable names (nix let bindings, fetchurl `name =`) don't need to follow the slug — they describe the actual artifact.

## README

- After adding or removing a game, regenerate the games table: `python3 scripts/generate-readme.py`
- The script reads flake metadata via `scripts/generate-readme.nix` and rewrites the block between the `<!-- BEGIN/END GENERATED GAMES -->` markers. Do not edit that block by hand.

## IPFS and fetchIpfs

- Game files are fetched via `fetchIpfs` (`lib/fetch-ipfs.nix`), which uses `ipget` to spawn a temporary IPFS node and fetch by CID from the DHT. Falls back to archive.org if IPFS fails.
- CIDs in this repo are generated with `ipfs add --nocopy` (which implies `--raw-leaves`). A plain `ipfs add` without `--raw-leaves` produces a **different CID** for the same file. Always use `--raw-leaves` (or `--nocopy`) when adding files to match the CIDs in this repo.
- To add a new game file to IPFS: place it in `/var/download/games/` on neoprism. The `ipfs-pin-watcher` service auto-pins it with `--nocopy` and records the CID in `/var/lib/ipfs/cid-map.txt`.
- When adding a new game, get the CID from `cid-map.txt` and use `fetchIpfs { cid = "..."; fallbackUrl = "https://archive.org/..."; hash = "sha256-..."; name = "..."; }`.
- Files not yet on neoprism are not discoverable via IPFS. The file must be pinned on at least one reachable node.

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

## Game data directories (~/.strom/<game>)

- **NEVER delete a game directory** (`rm -rf ~/.strom/<game>`). These contain user saves, profiles, and Wine prefixes that cannot be recovered.
- Game wrappers must be idempotent: re-running after a nix rebuild should update symlinks/configs without touching user data.
- When debugging, fix files in place (chmod, sed, etc.) instead of recreating the directory.
- If you must test with a clean state, back up `SAVEGAMES/`, `compatdata/`, and any user-created files first.
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
