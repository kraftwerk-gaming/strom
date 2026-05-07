# strom

Nix-packaged games. Each game is a self-contained derivation that fetches
its assets, sets up a sandboxed prefix under `~/.strom/<slug>`, and launches
via the appropriate runtime (Proton, native engine reimplementations,
DOSBox, emulators, etc).

> **Help keep game assets available!**
> Pin CIDs on your IPFS node. More pins means faster, more reliable downloads for everyone.
>
> ```bash
> # Pin all game CIDs
> nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001
>
> # Pin specific games only
> nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001 xenogears thief-gold
> ```

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
| <a href="https://lutris.net/games/age-of-empires-ii-the-conquerors/"><img src="https://lutris.net/games/banner/age-of-empires-ii-the-conquerors.jpg" height="40" alt="age-of-empires-ii-the-conquerors"></a> | [Age of Empires II: The Conquerors](https://lutris.net/games/age-of-empires-ii-the-conquerors/) | `proton` | `nix run .#age-of-empires-ii-the-conquerors` |
| <a href="https://lutris.net/games/anno-1404/"><img src="https://lutris.net/games/banner/anno-1404.jpg" height="40" alt="anno-1404"></a> | [Anno 1404 Gold Edition](https://lutris.net/games/anno-1404/) | `proton` | `nix run .#anno-1404` |
| <a href="https://lutris.net/games/anno-1503/"><img src="https://lutris.net/games/banner/anno-1503.jpg" height="40" alt="anno-1503"></a> | [Anno 1503 A.D.](https://lutris.net/games/anno-1503/) | `proton` | `nix run .#anno-1503` |
| <a href="https://lutris.net/games/anno-1602-ad/"><img src="https://lutris.net/games/banner/anno-1602-ad.jpg" height="40" alt="anno-1602-ad"></a> | [Anno 1602 A.D. Gold Edition](https://lutris.net/games/anno-1602-ad/) | `proton` | `nix run .#anno-1602-ad` |
| <a href="https://lutris.net/games/anno-1701/"><img src="https://lutris.net/games/banner/anno-1701.jpg" height="40" alt="anno-1701"></a> | [Anno 1701 + Sunken Treasure](https://lutris.net/games/anno-1701/) | `proton` | `nix run .#anno-1701` |
| <a href="https://lutris.net/games/aquanox/"><img src="https://lutris.net/games/banner/aquanox.jpg" height="40" alt="aquanox"></a> | [AquaNox](https://lutris.net/games/aquanox/) | `proton` | `nix run .#aquanox` |
| <a href="https://lutris.net/games/archimedean-dynasty/"><img src="https://lutris.net/games/banner/archimedean-dynasty.jpg" height="40" alt="archimedean-dynasty"></a> | [Archimedean Dynasty / Schleichfahrt](https://lutris.net/games/archimedean-dynasty/) | `custom` | `nix run .#archimedean-dynasty` |
| <a href="https://lutris.net/games/baba-is-you/"><img src="https://lutris.net/games/banner/baba-is-you.jpg" height="40" alt="baba-is-you"></a> | [Baba Is You](https://lutris.net/games/baba-is-you/) | `native` | `nix run .#baba-is-you` |
| <a href="https://lutris.net/games/balatro/"><img src="https://lutris.net/games/banner/balatro.jpg" height="40" alt="balatro"></a> | [Balatro](https://lutris.net/games/balatro/) | `proton` | `nix run .#balatro` |
| <a href="https://lutris.net/games/beamng-dot-drive/"><img src="https://lutris.net/games/banner/beamng-dot-drive.jpg" height="40" alt="beamng-dot-drive"></a> | [BeamNG.drive](https://lutris.net/games/beamng-dot-drive/) | `native` | `nix run .#beamng-dot-drive` |
| <a href="https://lutris.net/games/braid/"><img src="https://lutris.net/games/banner/braid.jpg" height="40" alt="braid"></a> | [Braid](https://lutris.net/games/braid/) | `native` | `nix run .#braid` |
| <a href="https://lutris.net/games/burnout-3-takedown/"><img src="https://lutris.net/games/banner/burnout-3-takedown.jpg" height="40" alt="burnout-3-takedown"></a> | [Burnout 3: Takedown](https://lutris.net/games/burnout-3-takedown/) | `pcsx2` | `nix run .#burnout-3-takedown` |
| <a href="https://lutris.net/games/burntime/"><img src="https://lutris.net/games/banner/burntime.jpg" height="40" alt="burntime"></a> | [Burntime](https://lutris.net/games/burntime/) | `custom` | `nix run .#burntime` |
| <a href="https://lutris.net/games/cave-story--1/"><img src="https://lutris.net/games/banner/cave-story--1.jpg" height="40" alt="cave-story--1"></a> | [Cave Story / Doukutsu Monogatari](https://lutris.net/games/cave-story--1/) | `native` | `nix run .#cave-story--1` |
| <a href="https://lutris.net/games/clonk-4/"><img src="https://lutris.net/games/banner/clonk-4.jpg" height="40" alt="clonk-4"></a> | [Clonk 4](https://lutris.net/games/clonk-4/) | `proton` | `nix run .#clonk-4` |
| <a href="https://lutris.net/games/command-conquer/"><img src="https://lutris.net/games/banner/command-conquer.jpg" height="40" alt="command-conquer"></a> | [Command & Conquer: Tiberian Dawn](https://lutris.net/games/command-conquer/) | `native` | `nix run .#command-conquer` |
| <a href="https://lutris.net/games/command-conquer-generals/"><img src="https://lutris.net/games/banner/command-conquer-generals.jpg" height="40" alt="command-conquer-generals"></a> | [Command & Conquer: Generals](https://lutris.net/games/command-conquer-generals/) | `proton` | `nix run .#command-conquer-generals` |
| <a href="https://lutris.net/games/command-conquer-red-alert/"><img src="https://lutris.net/games/banner/command-conquer-red-alert.jpg" height="40" alt="command-conquer-red-alert"></a> | [Command & Conquer: Red Alert](https://lutris.net/games/command-conquer-red-alert/) | `native` | `nix run .#command-conquer-red-alert` |
| <a href="https://lutris.net/games/command-conquer-red-alert-2/"><img src="https://lutris.net/games/banner/command-conquer-red-alert-2.jpg" height="40" alt="command-conquer-red-alert-2"></a> | [Command & Conquer: Red Alert 2 + Yuri's Revenge](https://lutris.net/games/command-conquer-red-alert-2/) | `proton` | `nix run .#command-conquer-red-alert-2` |
| <a href="https://lutris.net/games/command-conquer-renegade/"><img src="https://lutris.net/games/banner/command-conquer-renegade.jpg" height="40" alt="command-conquer-renegade"></a> | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `proton` | `nix run .#command-conquer-renegade` |
| <a href="https://lutris.net/games/command-conquer-tiberian-sun/"><img src="https://lutris.net/games/banner/command-conquer-tiberian-sun.jpg" height="40" alt="command-conquer-tiberian-sun"></a> | [Command & Conquer: Tiberian Sun + Firestorm](https://lutris.net/games/command-conquer-tiberian-sun/) | `proton` | `nix run .#command-conquer-tiberian-sun` |
| <a href="https://lutris.net/games/commandos-behind-enemy-lines/"><img src="https://lutris.net/games/banner/commandos-behind-enemy-lines.jpg" height="40" alt="commandos-behind-enemy-lines"></a> | [Commandos: Behind Enemy Lines](https://lutris.net/games/commandos-behind-enemy-lines/) | `proton` | `nix run .#commandos-behind-enemy-lines` |
| <a href="https://lutris.net/games/cryostasis/"><img src="https://lutris.net/games/banner/cryostasis.jpg" height="40" alt="cryostasis"></a> | [Cryostasis: Sleep of Reason](https://lutris.net/games/cryostasis/) | `proton` | `nix run .#cryostasis` |
| <a href="https://lutris.net/games/cuphead/"><img src="https://lutris.net/games/banner/cuphead.jpg" height="40" alt="cuphead"></a> | [Cuphead Legacy](https://lutris.net/games/cuphead/) | `proton` | `nix run .#cuphead` |
| <a href="https://lutris.net/games/dead-cells/"><img src="https://lutris.net/games/banner/dead-cells.jpg" height="40" alt="dead-cells"></a> | [Dead Cells](https://lutris.net/games/dead-cells/) | `custom` | `nix run .#dead-cells` |
| <a href="https://lutris.net/games/demon-lord-just-a-block/"><img src="https://lutris.net/games/banner/demon-lord-just-a-block.jpg" height="40" alt="demon-lord-just-a-block"></a> | [Demon Lord Just A Block](https://lutris.net/games/demon-lord-just-a-block/) | `proton` | `nix run .#demon-lord-just-a-block` |
| <a href="https://lutris.net/games/deus-ex/"><img src="https://lutris.net/games/banner/deus-ex.jpg" height="40" alt="deus-ex"></a> | [Deus Ex GOTY](https://lutris.net/games/deus-ex/) | `proton` | `nix run .#deus-ex` |
| <a href="https://lutris.net/games/diablo-ii-lord-of-destruction/"><img src="https://lutris.net/games/banner/diablo-ii-lord-of-destruction.jpg" height="40" alt="diablo-ii-lord-of-destruction"></a> | [Diablo II + Lord of Destruction](https://lutris.net/games/diablo-ii-lord-of-destruction/) | `proton` | `nix run .#diablo-ii-lord-of-destruction` |
| <a href="https://lutris.net/games/disco-elysium-game-boy-edition/"><img src="https://lutris.net/games/banner/disco-elysium-game-boy-edition.jpg" height="40" alt="disco-elysium-game-boy-edition"></a> | [Disco Elysium: Game Boy Edition](https://lutris.net/games/disco-elysium-game-boy-edition/) | `retroarch` | `nix run .#disco-elysium-game-boy-edition` |
| <a href="https://lutris.net/games/disco-elysium-the-final-cut/"><img src="https://lutris.net/games/banner/disco-elysium-the-final-cut.jpg" height="40" alt="disco-elysium-the-final-cut"></a> | [Disco Elysium: The Final Cut](https://lutris.net/games/disco-elysium-the-final-cut/) | `proton` | `nix run .#disco-elysium-the-final-cut` |
| <a href="https://lutris.net/games/dungeon-keeper/"><img src="https://lutris.net/games/banner/dungeon-keeper.jpg" height="40" alt="dungeon-keeper"></a> | [Dungeon Keeper](https://lutris.net/games/dungeon-keeper/) | `proton` | `nix run .#dungeon-keeper` |
| <a href="https://lutris.net/games/europa-1400-the-guild/"><img src="https://lutris.net/games/banner/europa-1400-the-guild.jpg" height="40" alt="europa-1400-the-guild"></a> | [Europa 1400: The Guild - Gold Edition](https://lutris.net/games/europa-1400-the-guild/) | `proton` | `nix run .#europa-1400-the-guild` |
| <a href="https://lutris.net/games/factorio/"><img src="https://lutris.net/games/banner/factorio.jpg" height="40" alt="factorio"></a> | [Factorio](https://lutris.net/games/factorio/) | `native` | `nix run .#factorio` |
| <a href="https://lutris.net/games/fallout/"><img src="https://lutris.net/games/banner/fallout.jpg" height="40" alt="fallout"></a> | [Fallout](https://lutris.net/games/fallout/) | `proton` | `nix run .#fallout` |
| <a href="https://lutris.net/games/fallout-2/"><img src="https://lutris.net/games/banner/fallout-2.jpg" height="40" alt="fallout-2"></a> | [Fallout 2](https://lutris.net/games/fallout-2/) | `proton` | `nix run .#fallout-2` |
| <a href="https://lutris.net/games/fez/"><img src="https://lutris.net/games/banner/fez.jpg" height="40" alt="fez"></a> | [FEZ](https://lutris.net/games/fez/) | `native` | `nix run .#fez` |
| <a href="https://lutris.net/games/frog-fractions/"><img src="https://lutris.net/games/banner/frog-fractions.jpg" height="40" alt="frog-fractions"></a> | [frog-fractions](https://lutris.net/games/frog-fractions/) | `native` | `nix run .#frog-fractions` |
| <a href="https://lutris.net/games/ftl-faster-than-light/"><img src="https://lutris.net/games/banner/ftl-faster-than-light.jpg" height="40" alt="ftl-faster-than-light"></a> | [FTL: Faster Than Light Advanced Edition](https://lutris.net/games/ftl-faster-than-light/) | `native` | `nix run .#ftl-faster-than-light` |
| <a href="https://lutris.net/games/game-of-robot/"><img src="https://lutris.net/games/banner/game-of-robot.jpg" height="40" alt="game-of-robot"></a> | [The Game of Robot](https://lutris.net/games/game-of-robot/) | `native` | `nix run .#game-of-robot` |
| <a href="https://lutris.net/games/getting-over-it-with-bennett-foddy/"><img src="https://lutris.net/games/banner/getting-over-it-with-bennett-foddy.jpg" height="40" alt="getting-over-it-with-bennett-foddy"></a> | [Getting Over It with Bennett Foddy](https://lutris.net/games/getting-over-it-with-bennett-foddy/) | `proton` | `nix run .#getting-over-it-with-bennett-foddy` |
| <a href="https://lutris.net/games/half-life/"><img src="https://lutris.net/games/banner/half-life.jpg" height="40" alt="half-life"></a> | [Half-Life](https://lutris.net/games/half-life/) | `proton` | `nix run .#half-life` |
| <a href="https://lutris.net/games/heroes-of-might-and-magic-2-gold/"><img src="https://lutris.net/games/banner/heroes-of-might-and-magic-2-gold.jpg" height="40" alt="heroes-of-might-and-magic-2-gold"></a> | [Heroes of Might & Magic II Gold](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `native` | `nix run .#heroes-of-might-and-magic-2-gold` |
| <a href="https://lutris.net/games/hollow-knight/"><img src="https://lutris.net/games/banner/hollow-knight.jpg" height="40" alt="hollow-knight"></a> | [Hollow Knight](https://lutris.net/games/hollow-knight/) | `proton` | `nix run .#hollow-knight` |
| <a href="https://lutris.net/games/hollow-knight-silksong/"><img src="https://lutris.net/games/banner/hollow-knight-silksong.jpg" height="40" alt="hollow-knight-silksong"></a> | [Hollow Knight: Silksong](https://lutris.net/games/hollow-knight-silksong/) | `proton` | `nix run .#hollow-knight-silksong` |
| <a href="https://lutris.net/games/hotline-miami/"><img src="https://lutris.net/games/banner/hotline-miami.jpg" height="40" alt="hotline-miami"></a> | [Hotline Miami](https://lutris.net/games/hotline-miami/) | `native` | `nix run .#hotline-miami` |
| <a href="https://lutris.net/games/jazz-jackrabbit-2/"><img src="https://lutris.net/games/banner/jazz-jackrabbit-2.jpg" height="40" alt="jazz-jackrabbit-2"></a> | [Jazz Jackrabbit 2](https://lutris.net/games/jazz-jackrabbit-2/) | `native` | `nix run .#jazz-jackrabbit-2` |
| <a href="https://lutris.net/games/legacy-of-kain-soul-reaver/"><img src="https://lutris.net/games/banner/legacy-of-kain-soul-reaver.jpg" height="40" alt="legacy-of-kain-soul-reaver"></a> | [Legacy of Kain: Soul Reaver](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `proton` | `nix run .#legacy-of-kain-soul-reaver` |
| <a href="https://lutris.net/games/lemmings/"><img src="https://lutris.net/games/banner/lemmings.jpg" height="40" alt="lemmings"></a> | [Lemmings](https://lutris.net/games/lemmings/) | `native` | `nix run .#lemmings` |
| <a href="https://lutris.net/games/lemmings-95/"><img src="https://lutris.net/games/banner/lemmings-95.jpg" height="40" alt="lemmings-95"></a> | [Lemmings 95](https://lutris.net/games/lemmings-95/) | `native` | `nix run .#lemmings-95` |
| <a href="https://lutris.net/games/lorns-lure/"><img src="https://lutris.net/games/banner/lorns-lure.jpg" height="40" alt="lorns-lure"></a> | [Lorn's Lure](https://lutris.net/games/lorns-lure/) | `proton` | `nix run .#lorns-lure` |
| <a href="https://lutris.net/games/metal-gear-solid/"><img src="https://lutris.net/games/banner/metal-gear-solid.jpg" height="40" alt="metal-gear-solid"></a> | [Metal Gear Solid](https://lutris.net/games/metal-gear-solid/) | `retroarch` | `nix run .#metal-gear-solid` |
| <a href="https://lutris.net/games/metal-gear-solid-2-substance/"><img src="https://lutris.net/games/banner/metal-gear-solid-2-substance.jpg" height="40" alt="metal-gear-solid-2-substance"></a> | [Metal Gear Solid 2: Substance](https://lutris.net/games/metal-gear-solid-2-substance/) | `pcsx2` | `nix run .#metal-gear-solid-2-substance` |
| <a href="https://lutris.net/games/need-for-speed-most-wanted/"><img src="https://lutris.net/games/banner/need-for-speed-most-wanted.jpg" height="40" alt="need-for-speed-most-wanted"></a> | [Need for Speed: Most Wanted (2005)](https://lutris.net/games/need-for-speed-most-wanted/) | `proton` | `nix run .#need-for-speed-most-wanted` |
| <a href="https://lutris.net/games/need-for-speed-underground-2/"><img src="https://lutris.net/games/banner/need-for-speed-underground-2.jpg" height="40" alt="need-for-speed-underground-2"></a> | [Need for Speed: Underground 2](https://lutris.net/games/need-for-speed-underground-2/) | `proton` | `nix run .#need-for-speed-underground-2` |
| <a href="https://lutris.net/games/noita/"><img src="https://lutris.net/games/banner/noita.jpg" height="40" alt="noita"></a> | [Noita](https://lutris.net/games/noita/) | `proton` | `nix run .#noita` |
| <a href="https://lutris.net/games/osmos/"><img src="https://lutris.net/games/banner/osmos.jpg" height="40" alt="osmos"></a> | [Osmos](https://lutris.net/games/osmos/) | `native` | `nix run .#osmos` |
| <a href="https://lutris.net/games/outer-wilds/"><img src="https://lutris.net/games/banner/outer-wilds.jpg" height="40" alt="outer-wilds"></a> | [Outer Wilds](https://lutris.net/games/outer-wilds/) | `proton` | `nix run .#outer-wilds` |
| <a href="https://lutris.net/games/outer-wilds-alpha/"><img src="https://lutris.net/games/banner/outer-wilds-alpha.jpg" height="40" alt="outer-wilds-alpha"></a> | [Outer Wilds Alpha 1.2](https://lutris.net/games/outer-wilds-alpha/) | `proton` | `nix run .#outer-wilds-alpha` |
| <a href="https://lutris.net/games/papers-please/"><img src="https://lutris.net/games/banner/papers-please.jpg" height="40" alt="papers-please"></a> | [Papers, Please](https://lutris.net/games/papers-please/) | `native` | `nix run .#papers-please` |
| <a href="https://lutris.net/games/paquerette-down-the-bunburrows/"><img src="https://lutris.net/games/banner/paquerette-down-the-bunburrows.jpg" height="40" alt="paquerette-down-the-bunburrows"></a> | [Paquerette Down the Bunburrows v1.1.2](https://lutris.net/games/paquerette-down-the-bunburrows/) | `proton` | `nix run .#paquerette-down-the-bunburrows` |
| <a href="https://lutris.net/games/planescape-torment/"><img src="https://lutris.net/games/banner/planescape-torment.jpg" height="40" alt="planescape-torment"></a> | [Planescape: Torment](https://lutris.net/games/planescape-torment/) | `native` | `nix run .#planescape-torment` |
| <a href="https://lutris.net/games/psychonauts/"><img src="https://lutris.net/games/banner/psychonauts.jpg" height="40" alt="psychonauts"></a> | [Psychonauts](https://lutris.net/games/psychonauts/) | `proton` | `nix run .#psychonauts` |
| <a href="https://lutris.net/games/return-of-the-obra-dinn/"><img src="https://lutris.net/games/banner/return-of-the-obra-dinn.jpg" height="40" alt="return-of-the-obra-dinn"></a> | [Return of the Obra Dinn](https://lutris.net/games/return-of-the-obra-dinn/) | `proton` | `nix run .#return-of-the-obra-dinn` |
| <a href="https://lutris.net/games/roketz--1/"><img src="https://lutris.net/games/banner/roketz--1.jpg" height="40" alt="roketz--1"></a> | [Roketz](https://lutris.net/games/roketz--1/) | `custom` | `nix run .#roketz--1` |
| <a href="https://lutris.net/games/rollercoaster-tycoon/"><img src="https://lutris.net/games/banner/rollercoaster-tycoon.jpg" height="40" alt="rollercoaster-tycoon"></a> | [RollerCoaster Tycoon Deluxe](https://lutris.net/games/rollercoaster-tycoon/) | `proton` | `nix run .#rollercoaster-tycoon` |
| <a href="https://lutris.net/games/shadow-of-the-colossus/"><img src="https://lutris.net/games/banner/shadow-of-the-colossus.jpg" height="40" alt="shadow-of-the-colossus"></a> | [Shadow of the Colossus](https://lutris.net/games/shadow-of-the-colossus/) | `pcsx2` | `nix run .#shadow-of-the-colossus` |
| <a href="https://lutris.net/games/stalker-shadow-of-chernobyl/"><img src="https://lutris.net/games/banner/stalker-shadow-of-chernobyl.jpg" height="40" alt="stalker-shadow-of-chernobyl"></a> | [S.T.A.L.K.E.R.: Shadow of Chernobyl](https://lutris.net/games/stalker-shadow-of-chernobyl/) | `proton` | `nix run .#stalker-shadow-of-chernobyl` |
| <a href="https://lutris.net/games/star-wars-battlefront-2/"><img src="https://lutris.net/games/banner/star-wars-battlefront-2.jpg" height="40" alt="star-wars-battlefront-2"></a> | [Star Wars: Battlefront II (2005) v1.1 Rerelease via Proton and gamescope](https://lutris.net/games/star-wars-battlefront-2/) | `proton` | `nix run .#star-wars-battlefront-2` |
| <a href="https://lutris.net/games/starcraft/"><img src="https://lutris.net/games/banner/starcraft.jpg" height="40" alt="starcraft"></a> | [StarCraft + Brood War](https://lutris.net/games/starcraft/) | `proton` | `nix run .#starcraft` |
| <a href="https://lutris.net/games/stronghold-hd/"><img src="https://lutris.net/games/banner/stronghold-hd.jpg" height="40" alt="stronghold-hd"></a> | [Stronghold HD](https://lutris.net/games/stronghold-hd/) | `proton` | `nix run .#stronghold-hd` |
| <a href="https://lutris.net/games/super-hexagon/"><img src="https://lutris.net/games/banner/super-hexagon.jpg" height="40" alt="super-hexagon"></a> | [Super Hexagon](https://lutris.net/games/super-hexagon/) | `native` | `nix run .#super-hexagon` |
| <a href="https://lutris.net/games/syndicate/"><img src="https://lutris.net/games/banner/syndicate.jpg" height="40" alt="syndicate"></a> | [Syndicate](https://lutris.net/games/syndicate/) | `native` | `nix run .#syndicate` |
| <a href="https://lutris.net/games/the-legend-of-zelda-a-link-to-the-past/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-a-link-to-the-past.jpg" height="40" alt="the-legend-of-zelda-a-link-to-the-past"></a> | [The Legend of Zelda: A Link to the Past](https://lutris.net/games/the-legend-of-zelda-a-link-to-the-past/) | `retroarch` | `nix run .#the-legend-of-zelda-a-link-to-the-past` |
| <a href="https://lutris.net/games/the-legend-of-zelda-majoras-mask/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-majoras-mask.jpg" height="40" alt="the-legend-of-zelda-majoras-mask"></a> | [The Legend of Zelda: Majora's Mask](https://lutris.net/games/the-legend-of-zelda-majoras-mask/) | `retroarch` | `nix run .#the-legend-of-zelda-majoras-mask` |
| <a href="https://lutris.net/games/the-legend-of-zelda-ocarina-of-time/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-ocarina-of-time.jpg" height="40" alt="the-legend-of-zelda-ocarina-of-time"></a> | [The Legend of Zelda: Ocarina of Time](https://lutris.net/games/the-legend-of-zelda-ocarina-of-time/) | `retroarch` | `nix run .#the-legend-of-zelda-ocarina-of-time` |
| <a href="https://lutris.net/games/the-settlers-ii-gold-edition/"><img src="https://lutris.net/games/banner/the-settlers-ii-gold-edition.jpg" height="40" alt="the-settlers-ii-gold-edition"></a> | [The Settlers II Gold](https://lutris.net/games/the-settlers-ii-gold-edition/) | `native` | `nix run .#the-settlers-ii-gold-edition` |
| <a href="https://lutris.net/games/the-typing-of-the-dead/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead.jpg" height="40" alt="the-typing-of-the-dead"></a> | [The Typing of the Dead](https://lutris.net/games/the-typing-of-the-dead/) | `proton` | `nix run .#the-typing-of-the-dead` |
| <a href="https://lutris.net/games/the-typing-of-the-dead-overkill/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead-overkill.jpg" height="40" alt="the-typing-of-the-dead-overkill"></a> | [The Typing of the Dead: Overkill](https://lutris.net/games/the-typing-of-the-dead-overkill/) | `proton` | `nix run .#the-typing-of-the-dead-overkill` |
| <a href="https://lutris.net/games/theme-hospital/"><img src="https://lutris.net/games/banner/theme-hospital.jpg" height="40" alt="theme-hospital"></a> | [Theme Hospital](https://lutris.net/games/theme-hospital/) | `native` | `nix run .#theme-hospital` |
| <a href="https://lutris.net/games/thief-2/"><img src="https://lutris.net/games/banner/thief-2.jpg" height="40" alt="thief-2"></a> | [Thief II: The Metal Age](https://lutris.net/games/thief-2/) | `proton` | `nix run .#thief-2` |
| <a href="https://lutris.net/games/thief-gold/"><img src="https://lutris.net/games/banner/thief-gold.jpg" height="40" alt="thief-gold"></a> | [Thief Gold with TFix](https://lutris.net/games/thief-gold/) | `proton` | `nix run .#thief-gold` |
| <a href="https://lutris.net/games/unreal-tournament-2004/"><img src="https://lutris.net/games/banner/unreal-tournament-2004.jpg" height="40" alt="unreal-tournament-2004"></a> | [Unreal Tournament 2004](https://lutris.net/games/unreal-tournament-2004/) | `native` | `nix run .#unreal-tournament-2004` |
| <a href="https://lutris.net/games/untitled-goose-game/"><img src="https://lutris.net/games/banner/untitled-goose-game.jpg" height="40" alt="untitled-goose-game"></a> | [Untitled Goose Game](https://lutris.net/games/untitled-goose-game/) | `proton` | `nix run .#untitled-goose-game` |
| <a href="https://lutris.net/games/uplink/"><img src="https://lutris.net/games/banner/uplink.jpg" height="40" alt="uplink"></a> | [Uplink: Hacker Elite v1.6](https://lutris.net/games/uplink/) | `proton` | `nix run .#uplink` |
| <a href="https://lutris.net/games/vampire-crawlers/"><img src="https://lutris.net/games/banner/vampire-crawlers.jpg" height="40" alt="vampire-crawlers"></a> | [Vampire Crawlers](https://lutris.net/games/vampire-crawlers/) | `proton` | `nix run .#vampire-crawlers` |
| <a href="https://lutris.net/games/vampire-the-masquerade-bloodlines/"><img src="https://lutris.net/games/banner/vampire-the-masquerade-bloodlines.jpg" height="40" alt="vampire-the-masquerade-bloodlines"></a> | [Vampire: The Masquerade — Bloodlines](https://lutris.net/games/vampire-the-masquerade-bloodlines/) | `proton` | `nix run .#vampire-the-masquerade-bloodlines` |
| <a href="https://lutris.net/games/void-stranger/"><img src="https://lutris.net/games/banner/void-stranger.jpg" height="40" alt="void-stranger"></a> | [Void Stranger](https://lutris.net/games/void-stranger/) | `proton` | `nix run .#void-stranger` |
| <a href="https://lutris.net/games/vvvvvv/"><img src="https://lutris.net/games/banner/vvvvvv.jpg" height="40" alt="vvvvvv"></a> | [VVVVVV](https://lutris.net/games/vvvvvv/) | `native` | `nix run .#vvvvvv` |
| <a href="https://lutris.net/games/warcraft-iii-the-frozen-throne/"><img src="https://lutris.net/games/banner/warcraft-iii-the-frozen-throne.jpg" height="40" alt="warcraft-iii-the-frozen-throne"></a> | [Warcraft III: Reign of Chaos + The Frozen Throne v1.26a](https://lutris.net/games/warcraft-iii-the-frozen-throne/) | `proton` | `nix run .#warcraft-iii-the-frozen-throne` |
| <a href="https://lutris.net/games/worms-wmd/"><img src="https://lutris.net/games/banner/worms-wmd.jpg" height="40" alt="worms-wmd"></a> | [Worms W.M.D](https://lutris.net/games/worms-wmd/) | `proton` | `nix run .#worms-wmd` |
| <a href="https://lutris.net/games/xenogears/"><img src="https://lutris.net/games/banner/xenogears.jpg" height="40" alt="xenogears"></a> | [Xenogears](https://lutris.net/games/xenogears/) | `retroarch` | `nix run .#xenogears` |

_91 games_

<!-- END GENERATED GAMES -->

## IPFS

Game files are fetched from IPFS via `fetchIpfs` (see `lib/fetch-ipfs.nix`).
Each game carries an IPFS CID and an archive.org fallback URL. At build time,
lassie fetches the CID from the IPFS network (DHT + HTTP gateways in
parallel), and falls back to the archive.org URL if IPFS fails. The nix
output hash ensures integrity regardless of source.

### Setting up an IPFS node with kubo

In order to mirror or add new CIDs you need a running [kubo](https://github.com/ipfs/kubo) daemon. On NixOS, add to your configuration:

```nix
services.kubo = {
  enable = true;
  settings = {
    # filestore lets ipfs add --nocopy reference files in place
    # instead of copying them into the blockstore
    Experimental.FilestoreEnabled = true;
    Datastore.StorageMax = "100GB";
  };
};

# open swarm port so other nodes can reach you
networking.firewall.allowedTCPPorts = [ 4001 ];
networking.firewall.allowedUDPPorts = [ 4001 ]; # QUIC
```

Rebuild, then verify the daemon is running:

```bash
sudo -u ipfs ipfs id
```

### Adding a game file to IPFS

Always pass `--raw-leaves`. All CIDs in this repo are computed with that
flag set. A plain `ipfs add` without `--raw-leaves` produces a **different
CID** for the same file -- do not use it.

`--nocopy` is optional and implies `--raw-leaves`. It avoids duplicating
multi-GB files into the blockstore by referencing them in place via the
filestore; use it when you want the optimization, but the CID is the same
either way.

Example: adding The Typing of the Dead: Overkill (7.4 GB):

```bash
# place the file somewhere the ipfs user can read (important!)
# if you have file share set up between daemons, ensure that ipfs
# is in a common group (e.g. "download")

# add to IPFS (as the ipfs user, since the daemon owns the repo)
sudo -u ipfs ipfs add --raw-leaves --progress \
  '/media/download/torrents/The.Typing.of.the.Dead.Overkill.7z'
# output: added QmZPyB... The.Typing.of.the.Dead.Overkill.7z
```

Note the CID from the output (`QmZPyBk...` in this case). If you used
`--nocopy`, the blockstore references the file at its current path -- do
not move or delete it while it is pinned.

### Verifying the file is retrievable

From a different machine (or after clearing your local cache), confirm the
CID resolves via a public gateway:

```bash
# HEAD request -- checks the CID is known without downloading the file
curl -sI 'https://ipfs.io/ipfs/QmZPyB...' | head -5
# HTTP/2 200
# content-type: application/x-7z-compressed
# content-length: 7412276595
```

To test the full fetch path that `fetchIpfs` uses at build time (lassie +
go-car), use the lassie binary from this flake:

```bash
nix run github:kraftwerk-gaming/strom#lassie -- fetch \
  --progress \
  --providers 'https://ipfs.io,https://dweb.link' \
  -o /tmp/test.7z \
  'QmZPyB...'

# extract the file from the CAR archive
nix shell nixpkgs#go-car -c car extract -f /tmp/test.car /tmp/test.7z

# verify the nix hash matches what fetchIpfs expects
nix hash file --sri /tmp/test.7z
# sha256-waL7G7lU2/aIaRYnju49/vuOM+/TeQu5MX8XgEPHl8M=
```

If the file is large, give it a few minutes after `ipfs add` for the DHT
provider records to propagate. You can force immediate announcement:

```bash
sudo -u ipfs ipfs routing provide 'QmZPyB'
```

### Pinning all strom CIDs

To mirror every game file in this repo on your node:

```bash
nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001
```

This calls `ipfs pin add` for every CID listed in `passthru.ipfsSources`
across all game packages. You can also pin specific games:

```bash
nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001 xenogears thief-gold
```

### Using the NixOS mirror module

For a hands-off mirror that automatically tracks new games, this repo ships
a NixOS module that periodically resolves the strom IPNS name and pins its
contents:

```nix
{
  imports = [ strom.nixosModules.ipfs-mirror ];

  services.strom-ipfs-mirror = {
    enable = true;
    # optional: override the poll interval (default: hourly)
    # interval = "daily";
  };
}
```

The module enables kubo with sane defaults, opens the swarm ports, and
creates a systemd timer (`strom-ipfs-pin`) that resolves the IPNS name and
recursively pins everything underneath it.

### Using a CID in a game package

Once the file is on IPFS, reference it with `fetchIpfs` in the game's
`default.nix`:

```nix
src = fetchIpfs {
  cid = "QmZPyB...";
  fallbackUrl = "https://www.gog.com/game/the_typing_of_the_dead_overkill";
  hash = "sha256-waL7G7lU2/aIaRYnju49/vuOM+/TeQu5MX8XgEPHl8M=";
  name = "The.Typing.of.the.Dead.Overkill.7z";
};
```

To get the `hash`, set it to `""` on first build, let nix fail, and copy the
`got:` hash from the error message.

## Adding a game

1. Look up the Lutris slug: `https://lutris.net/api/games?search=<name>`
2. Create `games/<slug>/default.nix` (directory name = slug = `name` field)
3. Run `python3 scripts/generate-readme.py` to update this file
