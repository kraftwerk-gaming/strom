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

| Game | Runtime | Lutris | Nix |
| --- | --- | --- | --- |
| Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide) | `custom` | [archimedean-dynasty](https://lutris.net/games/archimedean-dynasty/) | [games/archimedean-dynasty](games/archimedean-dynasty/default.nix) |
| Command & Conquer: Tiberian Dawn (Vanilla Conquer, native) | `native` | [command-conquer](https://lutris.net/games/command-conquer/) | [games/command-conquer](games/command-conquer/default.nix) |
| Command & Conquer: Red Alert (Vanilla Conquer, native) | `native` | [command-conquer-red-alert](https://lutris.net/games/command-conquer-red-alert/) | [games/command-conquer-red-alert](games/command-conquer-red-alert/default.nix) |
| Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw) | `proton` | [command-conquer-red-alert-2](https://lutris.net/games/command-conquer-red-alert-2/) | [games/command-conquer-red-alert-2](games/command-conquer-red-alert-2/default.nix) |
| command-conquer-renegade | `proton` | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | [games/command-conquer-renegade](games/command-conquer-renegade/default.nix) |
| Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw) | `proton` | [command-conquer-tiberian-sun](https://lutris.net/games/command-conquer-tiberian-sun/) | [games/command-conquer-tiberian-sun](games/command-conquer-tiberian-sun/default.nix) |
| Dungeon Keeper (KeeperFX, via Proton and gamescope) | `proton` | [dungeon-keeper](https://lutris.net/games/dungeon-keeper/) | [games/dungeon-keeper](games/dungeon-keeper/default.nix) |
| Europa 1400: The Guild - Gold Edition (via Proton and gamescope) | `proton` | [europa-1400-the-guild](https://lutris.net/games/europa-1400-the-guild/) | [games/europa-1400-the-guild](games/europa-1400-the-guild/default.nix) |
| frog-fractions | `native` | [frog-fractions](https://lutris.net/games/frog-fractions/) | [games/frog-fractions](games/frog-fractions/default.nix) |
| The Game of Robot (1988, via DOSBox-X) | `native` | [game-of-robot](https://lutris.net/games/game-of-robot/) | [games/game-of-robot](games/game-of-robot/default.nix) |
| Heroes of Might & Magic II Gold (via fheroes2) | `native` | [heroes-of-might-and-magic-2-gold](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | [games/heroes-of-might-and-magic-2-gold](games/heroes-of-might-and-magic-2-gold/default.nix) |
| [Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)](https://github.com/deathkiller/jazz2-native) | `native` | [jazz-jackrabbit-2](https://lutris.net/games/jazz-jackrabbit-2/) | [games/jazz-jackrabbit-2](games/jazz-jackrabbit-2/default.nix) |
| Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope) | `proton` | [legacy-of-kain-soul-reaver](https://lutris.net/games/legacy-of-kain-soul-reaver/) | [games/legacy-of-kain-soul-reaver](games/legacy-of-kain-soul-reaver/default.nix) |
| Lemmings (DOS CD version with CD audio, via DOSBox-X) | `native` | [lemmings](https://lutris.net/games/lemmings/) | [games/lemmings](games/lemmings/default.nix) |
| Need for Speed: Underground 2 (via Proton and gamescope) | `proton` | [need-for-speed-underground-2](https://lutris.net/games/need-for-speed-underground-2/) | [games/need-for-speed-underground-2](games/need-for-speed-underground-2/default.nix) |
| Shadow of the Colossus (via PCSX2) | `pcsx2` | [shadow-of-the-colossus](https://lutris.net/games/shadow-of-the-colossus/) | [games/shadow-of-the-colossus](games/shadow-of-the-colossus/default.nix) |
| StarCraft + Brood War (via Proton and gamescope) | `proton` | [starcraft](https://lutris.net/games/starcraft/) | [games/starcraft](games/starcraft/default.nix) |
| Stronghold HD (via Proton and gamescope) | `proton` | [stronghold-hd](https://lutris.net/games/stronghold-hd/) | [games/stronghold-hd](games/stronghold-hd/default.nix) |
| Syndicate (via FreeSynd engine) | `native` | [syndicate](https://lutris.net/games/syndicate/) | [games/syndicate](games/syndicate/default.nix) |
| The Settlers II Gold (via Return to the Roots) | `native` | [the-settlers-ii-gold-edition](https://lutris.net/games/the-settlers-ii-gold-edition/) | [games/the-settlers-ii-gold-edition](games/the-settlers-ii-gold-edition/default.nix) |
| Thief II: The Metal Age (NewDark engine, via Proton and gamescope) | `proton` | [thief-2](https://lutris.net/games/thief-2/) | [games/thief-2](games/thief-2/default.nix) |
| Thief Gold with TFix (NewDark engine, via Proton and gamescope) | `proton` | [thief-gold](https://lutris.net/games/thief-gold/) | [games/thief-gold](games/thief-gold/default.nix) |
| Untitled Goose Game (via Proton and gamescope) | `proton` | [untitled-goose-game](https://lutris.net/games/untitled-goose-game/) | [games/untitled-goose-game](games/untitled-goose-game/default.nix) |
| Xenogears (via RetroArch / SwanStation) | `retroarch` | [xenogears](https://lutris.net/games/xenogears/) | [games/xenogears](games/xenogears/default.nix) |

_24 games_

<!-- END GENERATED GAMES -->

## Adding a game

1. Look up the Lutris slug: `https://lutris.net/api/games?search=<name>`
2. Create `games/<slug>/default.nix` (directory name = slug = `name` field)
3. Run `python3 scripts/generate-readme.py` to update this file
