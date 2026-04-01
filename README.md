# strom

Nix-packaged games. Each game is a self-contained derivation that fetches
its assets, sets up a sandboxed prefix under `~/.strom/<slug>`, and launches
via the appropriate runtime (Proton, native engine reimplementations,
DOSBox, emulators, etc).

## Usage

```bash
nix run github:kraftwerk-gaming/strom#<slug>
```

Game state (saves, wine prefixes) lives in `~/.strom/<slug>` and survives
rebuilds.

## Games

<!-- BEGIN GENERATED GAMES -->

| Game | Runtime | Run |
| --- | --- | --- |
| [Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide)](https://lutris.net/games/archimedean-dynasty/) | `custom` | `nix run github:kraftwerk-gaming/strom#archimedean-dynasty` |
| [Command & Conquer: Tiberian Dawn (Vanilla Conquer, native)](https://lutris.net/games/command-conquer/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer` |
| [Command & Conquer: Red Alert (Vanilla Conquer, native)](https://lutris.net/games/command-conquer-red-alert/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert` |
| [Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-red-alert-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert-2` |
| [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-renegade` |
| [Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-tiberian-sun/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-tiberian-sun` |
| [Dungeon Keeper (KeeperFX, via Proton and gamescope)](https://lutris.net/games/dungeon-keeper/) | `proton` | `nix run github:kraftwerk-gaming/strom#dungeon-keeper` |
| [Europa 1400: The Guild - Gold Edition (via Proton and gamescope)](https://lutris.net/games/europa-1400-the-guild/) | `proton` | `nix run github:kraftwerk-gaming/strom#europa-1400-the-guild` |
| [frog-fractions](https://lutris.net/games/frog-fractions/) | `native` | `nix run github:kraftwerk-gaming/strom#frog-fractions` |
| [The Game of Robot (1988, via DOSBox-X)](https://lutris.net/games/game-of-robot/) | `native` | `nix run github:kraftwerk-gaming/strom#game-of-robot` |
| [Heroes of Might & Magic II Gold (via fheroes2)](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `native` | `nix run github:kraftwerk-gaming/strom#heroes-of-might-and-magic-2-gold` |
| [Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)](https://lutris.net/games/jazz-jackrabbit-2/) | `native` | `nix run github:kraftwerk-gaming/strom#jazz-jackrabbit-2` |
| [Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope)](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `proton` | `nix run github:kraftwerk-gaming/strom#legacy-of-kain-soul-reaver` |
| [Lemmings (DOS CD version with CD audio, via DOSBox-X)](https://lutris.net/games/lemmings/) | `native` | `nix run github:kraftwerk-gaming/strom#lemmings` |
| [Need for Speed: Underground 2 (via Proton and gamescope)](https://lutris.net/games/need-for-speed-underground-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#need-for-speed-underground-2` |
| [Shadow of the Colossus (via PCSX2)](https://lutris.net/games/shadow-of-the-colossus/) | `pcsx2` | `nix run github:kraftwerk-gaming/strom#shadow-of-the-colossus` |
| [StarCraft + Brood War (via Proton and gamescope)](https://lutris.net/games/starcraft/) | `proton` | `nix run github:kraftwerk-gaming/strom#starcraft` |
| [Stronghold HD (via Proton and gamescope)](https://lutris.net/games/stronghold-hd/) | `proton` | `nix run github:kraftwerk-gaming/strom#stronghold-hd` |
| [Syndicate (via FreeSynd engine)](https://lutris.net/games/syndicate/) | `native` | `nix run github:kraftwerk-gaming/strom#syndicate` |
| [The Settlers II Gold (via Return to the Roots)](https://lutris.net/games/the-settlers-ii-gold-edition/) | `native` | `nix run github:kraftwerk-gaming/strom#the-settlers-ii-gold-edition` |
| [Thief II: The Metal Age (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-2` |
| [Thief Gold with TFix (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-gold/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-gold` |
| [Untitled Goose Game (via Proton and gamescope)](https://lutris.net/games/untitled-goose-game/) | `proton` | `nix run github:kraftwerk-gaming/strom#untitled-goose-game` |
| [Xenogears (via RetroArch / SwanStation)](https://lutris.net/games/xenogears/) | `retroarch` | `nix run github:kraftwerk-gaming/strom#xenogears` |

_24 games_

<!-- END GENERATED GAMES -->

## Adding a game

1. Look up the Lutris slug: `https://lutris.net/api/games?search=<name>`
2. Create `games/<slug>/default.nix` (directory name = slug = `name` field)
3. Run `python3 scripts/generate-readme.py` to update this file
