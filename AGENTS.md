# Rules for AI agents working on this repo

## Game naming

- Game directory names under `games/` and the `name =` field in `default.nix` **must** use the **Lutris slug** as the canonical identifier.
- Look up the slug at `https://lutris.net/api/games?search=<game>` or `https://lutris.net/api/games/<slug>` before adding a new game.
- The flake attribute name = directory name = Lutris slug. No exceptions.
- Internal variable names (nix let bindings, fetchurl `name =`) don't need to follow the slug — they describe the actual artifact.

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
