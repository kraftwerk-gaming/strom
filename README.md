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

| | Game | Runtime | Run |
| --- | --- | --- | --- |
| <a href="https://lutris.net/games/archimedean-dynasty/"><img src="https://lutris.net/games/banner/archimedean-dynasty.jpg" height="40" alt="archimedean-dynasty"></a> | [Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide)](https://lutris.net/games/archimedean-dynasty/) | `custom` | `nix run github:kraftwerk-gaming/strom#archimedean-dynasty` |
| <a href="https://lutris.net/games/command-conquer/"><img src="https://lutris.net/games/banner/command-conquer.jpg" height="40" alt="command-conquer"></a> | [Command & Conquer: Tiberian Dawn (Vanilla Conquer, native)](https://lutris.net/games/command-conquer/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer` |
| <a href="https://lutris.net/games/command-conquer-red-alert/"><img src="https://lutris.net/games/banner/command-conquer-red-alert.jpg" height="40" alt="command-conquer-red-alert"></a> | [Command & Conquer: Red Alert (Vanilla Conquer, native)](https://lutris.net/games/command-conquer-red-alert/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert` |
| <a href="https://lutris.net/games/command-conquer-red-alert-2/"><img src="https://lutris.net/games/banner/command-conquer-red-alert-2.jpg" height="40" alt="command-conquer-red-alert-2"></a> | [Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-red-alert-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert-2` |
| <a href="https://lutris.net/games/command-conquer-renegade/"><img src="https://lutris.net/games/banner/command-conquer-renegade.jpg" height="40" alt="command-conquer-renegade"></a> | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-renegade` |
| <a href="https://lutris.net/games/command-conquer-tiberian-sun/"><img src="https://lutris.net/games/banner/command-conquer-tiberian-sun.jpg" height="40" alt="command-conquer-tiberian-sun"></a> | [Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-tiberian-sun/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-tiberian-sun` |
| <a href="https://lutris.net/games/dungeon-keeper/"><img src="https://lutris.net/games/banner/dungeon-keeper.jpg" height="40" alt="dungeon-keeper"></a> | [Dungeon Keeper (KeeperFX, via Proton and gamescope)](https://lutris.net/games/dungeon-keeper/) | `proton` | `nix run github:kraftwerk-gaming/strom#dungeon-keeper` |
| <a href="https://lutris.net/games/europa-1400-the-guild/"><img src="https://lutris.net/games/banner/europa-1400-the-guild.jpg" height="40" alt="europa-1400-the-guild"></a> | [Europa 1400: The Guild - Gold Edition (via Proton and gamescope)](https://lutris.net/games/europa-1400-the-guild/) | `proton` | `nix run github:kraftwerk-gaming/strom#europa-1400-the-guild` |
| <a href="https://lutris.net/games/frog-fractions/"><img src="https://lutris.net/games/banner/frog-fractions.jpg" height="40" alt="frog-fractions"></a> | [frog-fractions](https://lutris.net/games/frog-fractions/) | `native` | `nix run github:kraftwerk-gaming/strom#frog-fractions` |
| <a href="https://lutris.net/games/game-of-robot/"><img src="https://lutris.net/games/banner/game-of-robot.jpg" height="40" alt="game-of-robot"></a> | [The Game of Robot (1988, via DOSBox-X)](https://lutris.net/games/game-of-robot/) | `native` | `nix run github:kraftwerk-gaming/strom#game-of-robot` |
| <a href="https://lutris.net/games/heroes-of-might-and-magic-2-gold/"><img src="https://lutris.net/games/banner/heroes-of-might-and-magic-2-gold.jpg" height="40" alt="heroes-of-might-and-magic-2-gold"></a> | [Heroes of Might & Magic II Gold (via fheroes2)](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `native` | `nix run github:kraftwerk-gaming/strom#heroes-of-might-and-magic-2-gold` |
| <a href="https://lutris.net/games/jazz-jackrabbit-2/"><img src="https://lutris.net/games/banner/jazz-jackrabbit-2.jpg" height="40" alt="jazz-jackrabbit-2"></a> | [Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)](https://lutris.net/games/jazz-jackrabbit-2/) | `native` | `nix run github:kraftwerk-gaming/strom#jazz-jackrabbit-2` |
| <a href="https://lutris.net/games/legacy-of-kain-soul-reaver/"><img src="https://lutris.net/games/banner/legacy-of-kain-soul-reaver.jpg" height="40" alt="legacy-of-kain-soul-reaver"></a> | [Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope)](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `proton` | `nix run github:kraftwerk-gaming/strom#legacy-of-kain-soul-reaver` |
| <a href="https://lutris.net/games/lemmings/"><img src="https://lutris.net/games/banner/lemmings.jpg" height="40" alt="lemmings"></a> | [Lemmings (DOS CD version with CD audio, via DOSBox-X)](https://lutris.net/games/lemmings/) | `native` | `nix run github:kraftwerk-gaming/strom#lemmings` |
| <a href="https://lutris.net/games/need-for-speed-underground-2/"><img src="https://lutris.net/games/banner/need-for-speed-underground-2.jpg" height="40" alt="need-for-speed-underground-2"></a> | [Need for Speed: Underground 2 (via Proton and gamescope)](https://lutris.net/games/need-for-speed-underground-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#need-for-speed-underground-2` |
| <a href="https://lutris.net/games/shadow-of-the-colossus/"><img src="https://lutris.net/games/banner/shadow-of-the-colossus.jpg" height="40" alt="shadow-of-the-colossus"></a> | [Shadow of the Colossus (via PCSX2)](https://lutris.net/games/shadow-of-the-colossus/) | `pcsx2` | `nix run github:kraftwerk-gaming/strom#shadow-of-the-colossus` |
| <a href="https://lutris.net/games/starcraft/"><img src="https://lutris.net/games/banner/starcraft.jpg" height="40" alt="starcraft"></a> | [StarCraft + Brood War (via Proton and gamescope)](https://lutris.net/games/starcraft/) | `proton` | `nix run github:kraftwerk-gaming/strom#starcraft` |
| <a href="https://lutris.net/games/stronghold-hd/"><img src="https://lutris.net/games/banner/stronghold-hd.jpg" height="40" alt="stronghold-hd"></a> | [Stronghold HD (via Proton and gamescope)](https://lutris.net/games/stronghold-hd/) | `proton` | `nix run github:kraftwerk-gaming/strom#stronghold-hd` |
| <a href="https://lutris.net/games/syndicate/"><img src="https://lutris.net/games/banner/syndicate.jpg" height="40" alt="syndicate"></a> | [Syndicate (via FreeSynd engine)](https://lutris.net/games/syndicate/) | `native` | `nix run github:kraftwerk-gaming/strom#syndicate` |
| <a href="https://lutris.net/games/the-settlers-ii-gold-edition/"><img src="https://lutris.net/games/banner/the-settlers-ii-gold-edition.jpg" height="40" alt="the-settlers-ii-gold-edition"></a> | [The Settlers II Gold (via Return to the Roots)](https://lutris.net/games/the-settlers-ii-gold-edition/) | `native` | `nix run github:kraftwerk-gaming/strom#the-settlers-ii-gold-edition` |
| <a href="https://lutris.net/games/theme-hospital/"><img src="https://lutris.net/games/banner/theme-hospital.jpg" height="40" alt="theme-hospital"></a> | [Theme Hospital (via CorsixTH engine)](https://lutris.net/games/theme-hospital/) | `native` | `nix run github:kraftwerk-gaming/strom#theme-hospital` |
| <a href="https://lutris.net/games/thief-2/"><img src="https://lutris.net/games/banner/thief-2.jpg" height="40" alt="thief-2"></a> | [Thief II: The Metal Age (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-2` |
| <a href="https://lutris.net/games/thief-gold/"><img src="https://lutris.net/games/banner/thief-gold.jpg" height="40" alt="thief-gold"></a> | [Thief Gold with TFix (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-gold/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-gold` |
| <a href="https://lutris.net/games/untitled-goose-game/"><img src="https://lutris.net/games/banner/untitled-goose-game.jpg" height="40" alt="untitled-goose-game"></a> | [Untitled Goose Game (via Proton and gamescope)](https://lutris.net/games/untitled-goose-game/) | `proton` | `nix run github:kraftwerk-gaming/strom#untitled-goose-game` |
| <a href="https://lutris.net/games/worms-wmd/"><img src="https://lutris.net/games/banner/worms-wmd.jpg" height="40" alt="worms-wmd"></a> | [Worms W.M.D (GOG build, via Proton and gamescope)](https://lutris.net/games/worms-wmd/) | `proton` | `nix run github:kraftwerk-gaming/strom#worms-wmd` |
| <a href="https://lutris.net/games/xenogears/"><img src="https://lutris.net/games/banner/xenogears.jpg" height="40" alt="xenogears"></a> | [Xenogears (via RetroArch / SwanStation)](https://lutris.net/games/xenogears/) | `retroarch` | `nix run github:kraftwerk-gaming/strom#xenogears` |

_26 games_

<!-- END GENERATED GAMES -->

## Adding a game

1. Look up the Lutris slug: `https://lutris.net/api/games?search=<name>`
2. Create `games/<slug>/default.nix` (directory name = slug = `name` field)
3. Run `python3 scripts/generate-readme.py` to update this file
