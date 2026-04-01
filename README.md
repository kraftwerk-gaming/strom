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

| Game | Runtime | Lutris | Run |
| --- | --- | --- | --- |
| Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide) | `custom` | [archimedean-dynasty](https://lutris.net/games/archimedean-dynasty/) | `nix run github:kraftwerk-gaming/strom#archimedean-dynasty` |
| Command & Conquer: Tiberian Dawn (Vanilla Conquer, native) | `native` | [command-conquer](https://lutris.net/games/command-conquer/) | `nix run github:kraftwerk-gaming/strom#command-conquer` |
| Command & Conquer: Red Alert (Vanilla Conquer, native) | `native` | [command-conquer-red-alert](https://lutris.net/games/command-conquer-red-alert/) | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert` |
| Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw) | `proton` | [command-conquer-red-alert-2](https://lutris.net/games/command-conquer-red-alert-2/) | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert-2` |
| command-conquer-renegade | `proton` | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `nix run github:kraftwerk-gaming/strom#command-conquer-renegade` |
| Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw) | `proton` | [command-conquer-tiberian-sun](https://lutris.net/games/command-conquer-tiberian-sun/) | `nix run github:kraftwerk-gaming/strom#command-conquer-tiberian-sun` |
| Dungeon Keeper (KeeperFX, via Proton and gamescope) | `proton` | [dungeon-keeper](https://lutris.net/games/dungeon-keeper/) | `nix run github:kraftwerk-gaming/strom#dungeon-keeper` |
| Europa 1400: The Guild - Gold Edition (via Proton and gamescope) | `proton` | [europa-1400-the-guild](https://lutris.net/games/europa-1400-the-guild/) | `nix run github:kraftwerk-gaming/strom#europa-1400-the-guild` |
| frog-fractions | `native` | [frog-fractions](https://lutris.net/games/frog-fractions/) | `nix run github:kraftwerk-gaming/strom#frog-fractions` |
| The Game of Robot (1988, via DOSBox-X) | `native` | [game-of-robot](https://lutris.net/games/game-of-robot/) | `nix run github:kraftwerk-gaming/strom#game-of-robot` |
| Heroes of Might & Magic II Gold (via fheroes2) | `native` | [heroes-of-might-and-magic-2-gold](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `nix run github:kraftwerk-gaming/strom#heroes-of-might-and-magic-2-gold` |
| [Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)](https://github.com/deathkiller/jazz2-native) | `native` | [jazz-jackrabbit-2](https://lutris.net/games/jazz-jackrabbit-2/) | `nix run github:kraftwerk-gaming/strom#jazz-jackrabbit-2` |
| Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope) | `proton` | [legacy-of-kain-soul-reaver](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `nix run github:kraftwerk-gaming/strom#legacy-of-kain-soul-reaver` |
| Lemmings (DOS CD version with CD audio, via DOSBox-X) | `native` | [lemmings](https://lutris.net/games/lemmings/) | `nix run github:kraftwerk-gaming/strom#lemmings` |
| Need for Speed: Underground 2 (via Proton and gamescope) | `proton` | [need-for-speed-underground-2](https://lutris.net/games/need-for-speed-underground-2/) | `nix run github:kraftwerk-gaming/strom#need-for-speed-underground-2` |
| Shadow of the Colossus (via PCSX2) | `pcsx2` | [shadow-of-the-colossus](https://lutris.net/games/shadow-of-the-colossus/) | `nix run github:kraftwerk-gaming/strom#shadow-of-the-colossus` |
| StarCraft + Brood War (via Proton and gamescope) | `proton` | [starcraft](https://lutris.net/games/starcraft/) | `nix run github:kraftwerk-gaming/strom#starcraft` |
| Stronghold HD (via Proton and gamescope) | `proton` | [stronghold-hd](https://lutris.net/games/stronghold-hd/) | `nix run github:kraftwerk-gaming/strom#stronghold-hd` |
| Syndicate (via FreeSynd engine) | `native` | [syndicate](https://lutris.net/games/syndicate/) | `nix run github:kraftwerk-gaming/strom#syndicate` |
| The Settlers II Gold (via Return to the Roots) | `native` | [the-settlers-ii-gold-edition](https://lutris.net/games/the-settlers-ii-gold-edition/) | `nix run github:kraftwerk-gaming/strom#the-settlers-ii-gold-edition` |
| Thief II: The Metal Age (NewDark engine, via Proton and gamescope) | `proton` | [thief-2](https://lutris.net/games/thief-2/) | `nix run github:kraftwerk-gaming/strom#thief-2` |
| Thief Gold with TFix (NewDark engine, via Proton and gamescope) | `proton` | [thief-gold](https://lutris.net/games/thief-gold/) | `nix run github:kraftwerk-gaming/strom#thief-gold` |
| Untitled Goose Game (via Proton and gamescope) | `proton` | [untitled-goose-game](https://lutris.net/games/untitled-goose-game/) | `nix run github:kraftwerk-gaming/strom#untitled-goose-game` |
| Xenogears (via RetroArch / SwanStation) | `retroarch` | [xenogears](https://lutris.net/games/xenogears/) | `nix run github:kraftwerk-gaming/strom#xenogears` |

_24 games_

<!-- END GENERATED GAMES -->

## Adding a game

1. Look up the Lutris slug: `https://lutris.net/api/games?search=<name>`
2. Create `games/<slug>/default.nix` (directory name = slug = `name` field)
3. Run `python3 scripts/generate-readme.py` to update this file
