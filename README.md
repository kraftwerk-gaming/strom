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

## Cloning via Radicle

This repo is also hosted on [Radicle](https://radicle.xyz/). To clone via
the Radicle p2p network:

```bash
rad clone rad:zaCSBVa8UbKNEWBcmRTW1m9fZXhu
```

## Games

<!-- BEGIN GENERATED GAMES -->

| | Game | Runtime | Run |
| --- | --- | --- | --- |
| <a href="https://lutris.net/games/a-short-hike/"><img src="https://lutris.net/games/banner/a-short-hike.jpg" height="40" alt="a-short-hike"></a> | [A Short Hike](https://lutris.net/games/a-short-hike/) | `custom` | `nix run .#a-short-hike` |
| <a href="https://lutris.net/games/age-of-empires-ii-the-conquerors/"><img src="https://lutris.net/games/banner/age-of-empires-ii-the-conquerors.jpg" height="40" alt="age-of-empires-ii-the-conquerors"></a> | [Age of Empires II: The Conquerors](https://lutris.net/games/age-of-empires-ii-the-conquerors/) | `proton` | `nix run .#age-of-empires-ii-the-conquerors` |
| <a href="https://lutris.net/games/age-of-empires-iii/"><img src="https://lutris.net/games/banner/age-of-empires-iii.jpg" height="40" alt="age-of-empires-iii"></a> | [Age of Empires III: Complete Collection](https://lutris.net/games/age-of-empires-iii/) | `proton` | `nix run .#age-of-empires-iii` |
| <a href="https://lutris.net/games/anachronox/"><img src="https://lutris.net/games/banner/anachronox.jpg" height="40" alt="anachronox"></a> | [Anachronox](https://lutris.net/games/anachronox/) | `proton` | `nix run .#anachronox` |
| <a href="https://lutris.net/games/anatomy/"><img src="https://lutris.net/games/banner/anatomy.jpg" height="40" alt="anatomy"></a> | [Anatomy](https://lutris.net/games/anatomy/) | `native` | `nix run .#anatomy` |
| <a href="https://lutris.net/games/animal-well/"><img src="https://lutris.net/games/banner/animal-well.jpg" height="40" alt="animal-well"></a> | [ANIMAL WELL](https://lutris.net/games/animal-well/) | `proton` | `nix run .#animal-well` |
| <a href="https://lutris.net/games/anno-1404/"><img src="https://lutris.net/games/banner/anno-1404.jpg" height="40" alt="anno-1404"></a> | [Anno 1404 Gold Edition](https://lutris.net/games/anno-1404/) | `proton` | `nix run .#anno-1404` |
| <a href="https://lutris.net/games/anno-1503/"><img src="https://lutris.net/games/banner/anno-1503.jpg" height="40" alt="anno-1503"></a> | [Anno 1503 A.D.](https://lutris.net/games/anno-1503/) | `proton` | `nix run .#anno-1503` |
| <a href="https://lutris.net/games/anno-1602-ad/"><img src="https://lutris.net/games/banner/anno-1602-ad.jpg" height="40" alt="anno-1602-ad"></a> | [Anno 1602 A.D. Gold Edition](https://lutris.net/games/anno-1602-ad/) | `proton` | `nix run .#anno-1602-ad` |
| <a href="https://lutris.net/games/anno-1701/"><img src="https://lutris.net/games/banner/anno-1701.jpg" height="40" alt="anno-1701"></a> | [Anno 1701 + Sunken Treasure](https://lutris.net/games/anno-1701/) | `proton` | `nix run .#anno-1701` |
| <a href="https://lutris.net/games/aquanox/"><img src="https://lutris.net/games/banner/aquanox.jpg" height="40" alt="aquanox"></a> | [AquaNox](https://lutris.net/games/aquanox/) | `proton` | `nix run .#aquanox` |
| <a href="https://lutris.net/games/arcania/"><img src="https://lutris.net/games/banner/arcania.jpg" height="40" alt="arcania"></a> | [ArcaniA: Gothic 4 -- The Complete Tale](https://lutris.net/games/arcania/) | `proton` | `nix run .#arcania` |
| <a href="https://lutris.net/games/arcanum-of-steamworks-and-magick-obscura/"><img src="https://lutris.net/games/banner/arcanum-of-steamworks-and-magick-obscura.jpg" height="40" alt="arcanum-of-steamworks-and-magick-obscura"></a> | [Arcanum: Of Steamworks and Magick Obscura](https://lutris.net/games/arcanum-of-steamworks-and-magick-obscura/) | `proton` | `nix run .#arcanum-of-steamworks-and-magick-obscura` |
| <a href="https://lutris.net/games/archimedean-dynasty/"><img src="https://lutris.net/games/banner/archimedean-dynasty.jpg" height="40" alt="archimedean-dynasty"></a> | [Archimedean Dynasty / Schleichfahrt](https://lutris.net/games/archimedean-dynasty/) | `custom` | `nix run .#archimedean-dynasty` |
| <a href="https://lutris.net/games/arx-fatalis/"><img src="https://lutris.net/games/banner/arx-fatalis.jpg" height="40" alt="arx-fatalis"></a> | [Arx Fatalis](https://lutris.net/games/arx-fatalis/) | `native` | `nix run .#arx-fatalis` |
| <a href="https://lutris.net/games/atomicrops/"><img src="https://lutris.net/games/banner/atomicrops.jpg" height="40" alt="atomicrops"></a> | [Atomicrops](https://lutris.net/games/atomicrops/) | `proton` | `nix run .#atomicrops` |
| <a href="https://lutris.net/games/baba-is-you/"><img src="https://lutris.net/games/banner/baba-is-you.jpg" height="40" alt="baba-is-you"></a> | [Baba Is You](https://lutris.net/games/baba-is-you/) | `native` | `nix run .#baba-is-you` |
| <a href="https://lutris.net/games/baby-steps/"><img src="https://lutris.net/games/banner/baby-steps.jpg" height="40" alt="baby-steps"></a> | [Baby Steps](https://lutris.net/games/baby-steps/) | `proton` | `nix run .#baby-steps` |
| <a href="https://lutris.net/games/balatro/"><img src="https://lutris.net/games/banner/balatro.jpg" height="40" alt="balatro"></a> | [Balatro](https://lutris.net/games/balatro/) | `proton` | `nix run .#balatro` |
| <a href="https://lutris.net/games/baldurs-gate-enhanced-edition/"><img src="https://lutris.net/games/banner/baldurs-gate-enhanced-edition.jpg" height="40" alt="baldurs-gate-enhanced-edition"></a> | [Baldur's Gate: Enhanced Edition + 3 DLC](https://lutris.net/games/baldurs-gate-enhanced-edition/) | `native` | `nix run .#baldurs-gate-enhanced-edition` |
| <a href="https://lutris.net/games/baldurs-gate-ii-enhanced-edition/"><img src="https://lutris.net/games/banner/baldurs-gate-ii-enhanced-edition.jpg" height="40" alt="baldurs-gate-ii-enhanced-edition"></a> | [Baldur's Gate II: Enhanced Edition + DLC](https://lutris.net/games/baldurs-gate-ii-enhanced-edition/) | `native` | `nix run .#baldurs-gate-ii-enhanced-edition` |
| <a href="https://lutris.net/games/ball-x-pit/"><img src="https://lutris.net/games/banner/ball-x-pit.jpg" height="40" alt="ball-x-pit"></a> | [Ball x Pit](https://lutris.net/games/ball-x-pit/) | `proton` | `nix run .#ball-x-pit` |
| <a href="https://lutris.net/games/battlefield-1942/"><img src="https://lutris.net/games/banner/battlefield-1942.jpg" height="40" alt="battlefield-1942"></a> | [Battlefield 1942 Complete Collection](https://lutris.net/games/battlefield-1942/) | `proton` | `nix run .#battlefield-1942` |
| <a href="https://lutris.net/games/battlefield-1942-desert-combat/"><img src="https://lutris.net/games/banner/battlefield-1942-desert-combat.jpg" height="40" alt="battlefield-1942-desert-combat"></a> | [Battlefield 1942: Desert Combat](https://lutris.net/games/battlefield-1942-desert-combat/) | `proton` | `nix run .#battlefield-1942-desert-combat` |
| <a href="https://lutris.net/games/battlefield-2/"><img src="https://lutris.net/games/banner/battlefield-2.jpg" height="40" alt="battlefield-2"></a> | [Battlefield 2 Complete Collection](https://lutris.net/games/battlefield-2/) | `proton` | `nix run .#battlefield-2` |
| <a href="https://lutris.net/games/beamng-dot-drive/"><img src="https://lutris.net/games/banner/beamng-dot-drive.jpg" height="40" alt="beamng-dot-drive"></a> | [BeamNG.drive](https://lutris.net/games/beamng-dot-drive/) | `native` | `nix run .#beamng-dot-drive` |
| <a href="https://lutris.net/games/beneath-a-steel-sky/"><img src="https://lutris.net/games/banner/beneath-a-steel-sky.jpg" height="40" alt="beneath-a-steel-sky"></a> | [Beneath a Steel Sky](https://lutris.net/games/beneath-a-steel-sky/) | `native` | `nix run .#beneath-a-steel-sky` |
| <a href="https://lutris.net/games/bioshock/"><img src="https://lutris.net/games/banner/bioshock.jpg" height="40" alt="bioshock"></a> | [BioShock](https://lutris.net/games/bioshock/) | `proton` | `nix run .#bioshock` |
| <a href="https://lutris.net/games/black-and-white/"><img src="https://lutris.net/games/banner/black-and-white.jpg" height="40" alt="black-and-white"></a> | [Black & White](https://lutris.net/games/black-and-white/) | `proton` | `nix run .#black-and-white` |
| <a href="https://lutris.net/games/bloodborne-psx/"><img src="https://lutris.net/games/banner/bloodborne-psx.jpg" height="40" alt="bloodborne-psx"></a> | [Bloodborne PSX](https://lutris.net/games/bloodborne-psx/) | `proton` | `nix run .#bloodborne-psx` |
| <a href="https://lutris.net/games/braid/"><img src="https://lutris.net/games/banner/braid.jpg" height="40" alt="braid"></a> | [Braid](https://lutris.net/games/braid/) | `native` | `nix run .#braid` |
| <a href="https://lutris.net/games/bridge-builder/"><img src="https://lutris.net/games/banner/bridge-builder.jpg" height="40" alt="bridge-builder"></a> | [Bridge Builder](https://lutris.net/games/bridge-builder/) | `proton` | `nix run .#bridge-builder` |
| <a href="https://lutris.net/games/broforce/"><img src="https://lutris.net/games/banner/broforce.jpg" height="40" alt="broforce"></a> | [Broforce / Broforce Forever](https://lutris.net/games/broforce/) | `native` | `nix run .#broforce` |
| <a href="https://lutris.net/games/buckshot-roulette/"><img src="https://lutris.net/games/banner/buckshot-roulette.jpg" height="40" alt="buckshot-roulette"></a> | [Buckshot Roulette](https://lutris.net/games/buckshot-roulette/) | `proton` | `nix run .#buckshot-roulette` |
| <a href="https://lutris.net/games/bully-scholarship-edition/"><img src="https://lutris.net/games/banner/bully-scholarship-edition.jpg" height="40" alt="bully-scholarship-edition"></a> | [Bully: Scholarship Edition](https://lutris.net/games/bully-scholarship-edition/) | `proton` | `nix run .#bully-scholarship-edition` |
| <a href="https://lutris.net/games/burnout-3-takedown/"><img src="https://lutris.net/games/banner/burnout-3-takedown.jpg" height="40" alt="burnout-3-takedown"></a> | [Burnout 3: Takedown](https://lutris.net/games/burnout-3-takedown/) | `pcsx2` | `nix run .#burnout-3-takedown` |
| <a href="https://lutris.net/games/burntime/"><img src="https://lutris.net/games/banner/burntime.jpg" height="40" alt="burntime"></a> | [Burntime](https://lutris.net/games/burntime/) | `custom` | `nix run .#burntime` |
| <a href="https://lutris.net/games/call-of-cthulhu-dark-corners-of-the-earth/"><img src="https://lutris.net/games/banner/call-of-cthulhu-dark-corners-of-the-earth.jpg" height="40" alt="call-of-cthulhu-dark-corners-of-the-earth"></a> | [Call of Cthulhu: Dark Corners of the Earth](https://lutris.net/games/call-of-cthulhu-dark-corners-of-the-earth/) | `proton` | `nix run .#call-of-cthulhu-dark-corners-of-the-earth` |
| <a href="https://lutris.net/games/carrion/"><img src="https://lutris.net/games/banner/carrion.jpg" height="40" alt="carrion"></a> | [CARRION](https://lutris.net/games/carrion/) | `custom` | `nix run .#carrion` |
| <a href="https://lutris.net/games/cave-story--1/"><img src="https://lutris.net/games/banner/cave-story--1.jpg" height="40" alt="cave-story--1"></a> | [Cave Story / Doukutsu Monogatari](https://lutris.net/games/cave-story--1/) | `native` | `nix run .#cave-story--1` |
| <a href="https://lutris.net/games/celeste/"><img src="https://lutris.net/games/banner/celeste.jpg" height="40" alt="celeste"></a> | [Celeste](https://lutris.net/games/celeste/) | `native` | `nix run .#celeste` |
| <a href="https://lutris.net/games/chrono-trigger/"><img src="https://lutris.net/games/banner/chrono-trigger.jpg" height="40" alt="chrono-trigger"></a> | [Chrono Trigger](https://lutris.net/games/chrono-trigger/) | `retroarch` | `nix run .#chrono-trigger` |
| <a href="https://lutris.net/games/clive-barkers-undying/"><img src="https://lutris.net/games/banner/clive-barkers-undying.jpg" height="40" alt="clive-barkers-undying"></a> | [Clive Barker's Undying](https://lutris.net/games/clive-barkers-undying/) | `proton` | `nix run .#clive-barkers-undying` |
| <a href="https://lutris.net/games/clonk-4/"><img src="https://lutris.net/games/banner/clonk-4.jpg" height="40" alt="clonk-4"></a> | [Clonk 4](https://lutris.net/games/clonk-4/) | `proton` | `nix run .#clonk-4` |
| <a href="https://lutris.net/games/cloverpit/"><img src="https://lutris.net/games/banner/cloverpit.jpg" height="40" alt="cloverpit"></a> | [Cloverpit](https://lutris.net/games/cloverpit/) | `proton` | `nix run .#cloverpit` |
| <a href="https://lutris.net/games/command-conquer/"><img src="https://lutris.net/games/banner/command-conquer.jpg" height="40" alt="command-conquer"></a> | [Command & Conquer: Tiberian Dawn](https://lutris.net/games/command-conquer/) | `native` | `nix run .#command-conquer` |
| <a href="https://lutris.net/games/command-conquer-generals/"><img src="https://lutris.net/games/banner/command-conquer-generals.jpg" height="40" alt="command-conquer-generals"></a> | [Command & Conquer: Generals](https://lutris.net/games/command-conquer-generals/) | `proton` | `nix run .#command-conquer-generals` |
| <a href="https://lutris.net/games/command-conquer-red-alert/"><img src="https://lutris.net/games/banner/command-conquer-red-alert.jpg" height="40" alt="command-conquer-red-alert"></a> | [Command & Conquer: Red Alert](https://lutris.net/games/command-conquer-red-alert/) | `native` | `nix run .#command-conquer-red-alert` |
| <a href="https://lutris.net/games/command-conquer-red-alert-2/"><img src="https://lutris.net/games/banner/command-conquer-red-alert-2.jpg" height="40" alt="command-conquer-red-alert-2"></a> | [Command & Conquer: Red Alert 2 + Yuri's Revenge](https://lutris.net/games/command-conquer-red-alert-2/) | `proton` | `nix run .#command-conquer-red-alert-2` |
| <a href="https://lutris.net/games/command-conquer-renegade/"><img src="https://lutris.net/games/banner/command-conquer-renegade.jpg" height="40" alt="command-conquer-renegade"></a> | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `proton` | `nix run .#command-conquer-renegade` |
| <a href="https://lutris.net/games/command-conquer-tiberian-sun/"><img src="https://lutris.net/games/banner/command-conquer-tiberian-sun.jpg" height="40" alt="command-conquer-tiberian-sun"></a> | [Command & Conquer: Tiberian Sun + Firestorm](https://lutris.net/games/command-conquer-tiberian-sun/) | `proton` | `nix run .#command-conquer-tiberian-sun` |
| <a href="https://lutris.net/games/commandos-behind-enemy-lines/"><img src="https://lutris.net/games/banner/commandos-behind-enemy-lines.jpg" height="40" alt="commandos-behind-enemy-lines"></a> | [Commandos: Behind Enemy Lines](https://lutris.net/games/commandos-behind-enemy-lines/) | `proton` | `nix run .#commandos-behind-enemy-lines` |
| <a href="https://lutris.net/games/company-of-heroes/"><img src="https://lutris.net/games/banner/company-of-heroes.jpg" height="40" alt="company-of-heroes"></a> | [Company of Heroes](https://lutris.net/games/company-of-heroes/) | `proton` | `nix run .#company-of-heroes` |
| <a href="https://lutris.net/games/condemned-criminal-origins/"><img src="https://lutris.net/games/banner/condemned-criminal-origins.jpg" height="40" alt="condemned-criminal-origins"></a> | [Condemned: Criminal Origins](https://lutris.net/games/condemned-criminal-origins/) | `proton` | `nix run .#condemned-criminal-origins` |
| <a href="https://lutris.net/games/crosscode/"><img src="https://lutris.net/games/banner/crosscode.jpg" height="40" alt="crosscode"></a> | [CrossCode + 3 DLC](https://lutris.net/games/crosscode/) | `native` | `nix run .#crosscode` |
| <a href="https://lutris.net/games/cryostasis/"><img src="https://lutris.net/games/banner/cryostasis.jpg" height="40" alt="cryostasis"></a> | [Cryostasis: Sleep of Reason](https://lutris.net/games/cryostasis/) | `proton` | `nix run .#cryostasis` |
| <a href="https://lutris.net/games/crypt-of-the-necrodancer/"><img src="https://lutris.net/games/banner/crypt-of-the-necrodancer.jpg" height="40" alt="crypt-of-the-necrodancer"></a> | [Crypt of the NecroDancer](https://lutris.net/games/crypt-of-the-necrodancer/) | `native` | `nix run .#crypt-of-the-necrodancer` |
| <a href="https://lutris.net/games/cuphead/"><img src="https://lutris.net/games/banner/cuphead.jpg" height="40" alt="cuphead"></a> | [Cuphead Legacy](https://lutris.net/games/cuphead/) | `proton` | `nix run .#cuphead` |
| <a href="https://lutris.net/games/dark-messiah-of-might-and-magic/"><img src="https://lutris.net/games/banner/dark-messiah-of-might-and-magic.jpg" height="40" alt="dark-messiah-of-might-and-magic"></a> | [Dark Messiah of Might and Magic](https://lutris.net/games/dark-messiah-of-might-and-magic/) | `proton` | `nix run .#dark-messiah-of-might-and-magic` |
| <a href="https://lutris.net/games/dark-souls-prepare-to-die-edition/"><img src="https://lutris.net/games/banner/dark-souls-prepare-to-die-edition.jpg" height="40" alt="dark-souls-prepare-to-die-edition"></a> | [Dark Souls: Prepare to Die Edition](https://lutris.net/games/dark-souls-prepare-to-die-edition/) | `proton` | `nix run .#dark-souls-prepare-to-die-edition` |
| <a href="https://lutris.net/games/day-of-the-tentacle/"><img src="https://lutris.net/games/banner/day-of-the-tentacle.jpg" height="40" alt="day-of-the-tentacle"></a> | [Day of the Tentacle](https://lutris.net/games/day-of-the-tentacle/) | `native` | `nix run .#day-of-the-tentacle` |
| <a href="https://lutris.net/games/dead-cells/"><img src="https://lutris.net/games/banner/dead-cells.jpg" height="40" alt="dead-cells"></a> | [Dead Cells](https://lutris.net/games/dead-cells/) | `custom` | `nix run .#dead-cells` |
| <a href="https://lutris.net/games/death-and-taxes/"><img src="https://lutris.net/games/banner/death-and-taxes.jpg" height="40" alt="death-and-taxes"></a> | [Death and Taxes](https://lutris.net/games/death-and-taxes/) | `custom` | `nix run .#death-and-taxes` |
| <a href="https://lutris.net/games/deltarune/"><img src="https://lutris.net/games/banner/deltarune.jpg" height="40" alt="deltarune"></a> | [DELTARUNE](https://lutris.net/games/deltarune/) | `proton` | `nix run .#deltarune` |
| <a href="https://lutris.net/games/demon-lord-just-a-block/"><img src="https://lutris.net/games/banner/demon-lord-just-a-block.jpg" height="40" alt="demon-lord-just-a-block"></a> | [Demon Lord Just A Block](https://lutris.net/games/demon-lord-just-a-block/) | `proton` | `nix run .#demon-lord-just-a-block` |
| <a href="https://lutris.net/games/detention/"><img src="https://lutris.net/games/banner/detention.jpg" height="40" alt="detention"></a> | [Detention](https://lutris.net/games/detention/) | `proton` | `nix run .#detention` |
| <a href="https://lutris.net/games/deus-ex/"><img src="https://lutris.net/games/banner/deus-ex.jpg" height="40" alt="deus-ex"></a> | [Deus Ex GOTY](https://lutris.net/games/deus-ex/) | `proton` | `nix run .#deus-ex` |
| <a href="https://lutris.net/games/diablo-ii-lord-of-destruction/"><img src="https://lutris.net/games/banner/diablo-ii-lord-of-destruction.jpg" height="40" alt="diablo-ii-lord-of-destruction"></a> | [Diablo II + Lord of Destruction](https://lutris.net/games/diablo-ii-lord-of-destruction/) | `proton` | `nix run .#diablo-ii-lord-of-destruction` |
| <a href="https://lutris.net/games/disco-elysium-game-boy-edition/"><img src="https://lutris.net/games/banner/disco-elysium-game-boy-edition.jpg" height="40" alt="disco-elysium-game-boy-edition"></a> | [Disco Elysium: Game Boy Edition](https://lutris.net/games/disco-elysium-game-boy-edition/) | `retroarch` | `nix run .#disco-elysium-game-boy-edition` |
| <a href="https://lutris.net/games/disco-elysium-the-final-cut/"><img src="https://lutris.net/games/banner/disco-elysium-the-final-cut.jpg" height="40" alt="disco-elysium-the-final-cut"></a> | [Disco Elysium: The Final Cut](https://lutris.net/games/disco-elysium-the-final-cut/) | `proton` | `nix run .#disco-elysium-the-final-cut` |
| <a href="https://lutris.net/games/dome-keeper/"><img src="https://lutris.net/games/banner/dome-keeper.jpg" height="40" alt="dome-keeper"></a> | [Dome Keeper](https://lutris.net/games/dome-keeper/) | `custom` | `nix run .#dome-keeper` |
| <a href="https://lutris.net/games/doom/"><img src="https://lutris.net/games/banner/doom.jpg" height="40" alt="doom"></a> | [The Ultimate DOOM](https://lutris.net/games/doom/) | `custom` | `nix run .#doom` |
| <a href="https://lutris.net/games/doom-ii/"><img src="https://lutris.net/games/banner/doom-ii.jpg" height="40" alt="doom-ii"></a> | [DOOM II: Hell on Earth](https://lutris.net/games/doom-ii/) | `custom` | `nix run .#doom-ii` |
| <a href="https://lutris.net/games/driver-san-francisco/"><img src="https://lutris.net/games/banner/driver-san-francisco.jpg" height="40" alt="driver-san-francisco"></a> | [Driver: San Francisco](https://lutris.net/games/driver-san-francisco/) | `proton` | `nix run .#driver-san-francisco` |
| <a href="https://lutris.net/games/duck-game/"><img src="https://lutris.net/games/banner/duck-game.jpg" height="40" alt="duck-game"></a> | [Duck Game](https://lutris.net/games/duck-game/) | `custom` | `nix run .#duck-game` |
| <a href="https://lutris.net/games/dungeon-keeper/"><img src="https://lutris.net/games/banner/dungeon-keeper.jpg" height="40" alt="dungeon-keeper"></a> | [Dungeon Keeper](https://lutris.net/games/dungeon-keeper/) | `proton` | `nix run .#dungeon-keeper` |
| <a href="https://lutris.net/games/dungeon-siege/"><img src="https://lutris.net/games/banner/dungeon-siege.jpg" height="40" alt="dungeon-siege"></a> | [Dungeon Siege](https://lutris.net/games/dungeon-siege/) | `proton` | `nix run .#dungeon-siege` |
| <a href="https://lutris.net/games/dwarf-fortress/"><img src="https://lutris.net/games/banner/dwarf-fortress.jpg" height="40" alt="dwarf-fortress"></a> | [Dwarf Fortress](https://lutris.net/games/dwarf-fortress/) | `custom` | `nix run .#dwarf-fortress` |
| <a href="https://lutris.net/games/emperor-battle-for-dune/"><img src="https://lutris.net/games/banner/emperor-battle-for-dune.jpg" height="40" alt="emperor-battle-for-dune"></a> | [Emperor: Battle for Dune](https://lutris.net/games/emperor-battle-for-dune/) | `proton` | `nix run .#emperor-battle-for-dune` |
| <a href="https://lutris.net/games/empire-earth-ii/"><img src="https://lutris.net/games/banner/empire-earth-ii.jpg" height="40" alt="empire-earth-ii"></a> | [Empire Earth II Gold](https://lutris.net/games/empire-earth-ii/) | `proton` | `nix run .#empire-earth-ii` |
| <a href="https://lutris.net/games/environmental-station-alpha/"><img src="https://lutris.net/games/banner/environmental-station-alpha.jpg" height="40" alt="environmental-station-alpha"></a> | [Environmental Station Alpha](https://lutris.net/games/environmental-station-alpha/) | `proton` | `nix run .#environmental-station-alpha` |
| <a href="https://lutris.net/games/europa-1400-the-guild/"><img src="https://lutris.net/games/banner/europa-1400-the-guild.jpg" height="40" alt="europa-1400-the-guild"></a> | [Europa 1400: The Guild - Gold Edition](https://lutris.net/games/europa-1400-the-guild/) | `proton` | `nix run .#europa-1400-the-guild` |
| <a href="https://lutris.net/games/everhood/"><img src="https://lutris.net/games/banner/everhood.jpg" height="40" alt="everhood"></a> | [Everhood](https://lutris.net/games/everhood/) | `proton` | `nix run .#everhood` |
| <a href="https://lutris.net/games/everything-is-crab/"><img src="https://lutris.net/games/banner/everything-is-crab.jpg" height="40" alt="everything-is-crab"></a> | [Everything is Crab: The Animal Evolution Roguelite](https://lutris.net/games/everything-is-crab/) | `proton` | `nix run .#everything-is-crab` |
| <a href="https://lutris.net/games/factorio/"><img src="https://lutris.net/games/banner/factorio.jpg" height="40" alt="factorio"></a> | [Factorio](https://lutris.net/games/factorio/) | `native` | `nix run .#factorio` |
| <a href="https://lutris.net/games/faith-the-unholy-trinity/"><img src="https://lutris.net/games/banner/faith-the-unholy-trinity.jpg" height="40" alt="faith-the-unholy-trinity"></a> | [FAITH: The Unholy Trinity](https://lutris.net/games/faith-the-unholy-trinity/) | `proton` | `nix run .#faith-the-unholy-trinity` |
| <a href="https://lutris.net/games/fallout/"><img src="https://lutris.net/games/banner/fallout.jpg" height="40" alt="fallout"></a> | [Fallout](https://lutris.net/games/fallout/) | `proton` | `nix run .#fallout` |
| <a href="https://lutris.net/games/fallout-2/"><img src="https://lutris.net/games/banner/fallout-2.jpg" height="40" alt="fallout-2"></a> | [Fallout 2](https://lutris.net/games/fallout-2/) | `proton` | `nix run .#fallout-2` |
| <a href="https://lutris.net/games/far-cry/"><img src="https://lutris.net/games/banner/far-cry.jpg" height="40" alt="far-cry"></a> | [Far Cry](https://lutris.net/games/far-cry/) | `proton` | `nix run .#far-cry` |
| <a href="https://lutris.net/games/fear/"><img src="https://lutris.net/games/banner/fear.jpg" height="40" alt="fear"></a> | [F.E.A.R. Platinum Collection](https://lutris.net/games/fear/) | `proton` | `nix run .#fear` |
| <a href="https://lutris.net/games/fez/"><img src="https://lutris.net/games/banner/fez.jpg" height="40" alt="fez"></a> | [FEZ](https://lutris.net/games/fez/) | `native` | `nix run .#fez` |
| <a href="https://lutris.net/games/final-doom-plutonia/"><img src="https://lutris.net/games/banner/final-doom-plutonia.jpg" height="40" alt="final-doom-plutonia"></a> | [Final Doom: The Plutonia Experiment](https://lutris.net/games/final-doom-plutonia/) | `custom` | `nix run .#final-doom-plutonia` |
| <a href="https://lutris.net/games/final-doom-tnt/"><img src="https://lutris.net/games/banner/final-doom-tnt.jpg" height="40" alt="final-doom-tnt"></a> | [Final Doom: TNT - Evilution](https://lutris.net/games/final-doom-tnt/) | `custom` | `nix run .#final-doom-tnt` |
| <a href="https://lutris.net/games/forager/"><img src="https://lutris.net/games/banner/forager.jpg" height="40" alt="forager"></a> | [Forager](https://lutris.net/games/forager/) | `native` | `nix run .#forager` |
| <a href="https://lutris.net/games/forbidden-siren/"><img src="https://lutris.net/games/banner/forbidden-siren.jpg" height="40" alt="forbidden-siren"></a> | [Forbidden Siren](https://lutris.net/games/forbidden-siren/) | `pcsx2` | `nix run .#forbidden-siren` |
| <a href="https://lutris.net/games/freelancer/"><img src="https://lutris.net/games/banner/freelancer.jpg" height="40" alt="freelancer"></a> | [Freelancer](https://lutris.net/games/freelancer/) | `proton` | `nix run .#freelancer` |
| <a href="https://lutris.net/games/frog-fractions/"><img src="https://lutris.net/games/banner/frog-fractions.jpg" height="40" alt="frog-fractions"></a> | [frog-fractions](https://lutris.net/games/frog-fractions/) | `native` | `nix run .#frog-fractions` |
| <a href="https://lutris.net/games/ftl-faster-than-light/"><img src="https://lutris.net/games/banner/ftl-faster-than-light.jpg" height="40" alt="ftl-faster-than-light"></a> | [FTL: Faster Than Light Advanced Edition](https://lutris.net/games/ftl-faster-than-light/) | `native` | `nix run .#ftl-faster-than-light` |
| <a href="https://lutris.net/games/full-throttle/"><img src="https://lutris.net/games/banner/full-throttle.jpg" height="40" alt="full-throttle"></a> | [Full Throttle](https://lutris.net/games/full-throttle/) | `native` | `nix run .#full-throttle` |
| <a href="https://lutris.net/games/game-of-robot/"><img src="https://lutris.net/games/banner/game-of-robot.jpg" height="40" alt="game-of-robot"></a> | [The Game of Robot](https://lutris.net/games/game-of-robot/) | `native` | `nix run .#game-of-robot` |
| <a href="https://lutris.net/games/getting-over-it-with-bennett-foddy/"><img src="https://lutris.net/games/banner/getting-over-it-with-bennett-foddy.jpg" height="40" alt="getting-over-it-with-bennett-foddy"></a> | [Getting Over It with Bennett Foddy](https://lutris.net/games/getting-over-it-with-bennett-foddy/) | `proton` | `nix run .#getting-over-it-with-bennett-foddy` |
| <a href="https://lutris.net/games/gish/"><img src="https://lutris.net/games/banner/gish.jpg" height="40" alt="gish"></a> | [Gish](https://lutris.net/games/gish/) | `native` | `nix run .#gish` |
| <a href="https://lutris.net/games/golden-sun/"><img src="https://lutris.net/games/banner/golden-sun.jpg" height="40" alt="golden-sun"></a> | [Golden Sun](https://lutris.net/games/golden-sun/) | `retroarch` | `nix run .#golden-sun` |
| <a href="https://lutris.net/games/golden-sun-the-lost-age/"><img src="https://lutris.net/games/banner/golden-sun-the-lost-age.jpg" height="40" alt="golden-sun-the-lost-age"></a> | [Golden Sun: The Lost Age](https://lutris.net/games/golden-sun-the-lost-age/) | `retroarch` | `nix run .#golden-sun-the-lost-age` |
| <a href="https://lutris.net/games/gothic/"><img src="https://lutris.net/games/banner/gothic.jpg" height="40" alt="gothic"></a> | [Gothic](https://lutris.net/games/gothic/) | `proton` | `nix run .#gothic` |
| <a href="https://lutris.net/games/grand-theft-auto-2/"><img src="https://lutris.net/games/banner/grand-theft-auto-2.jpg" height="40" alt="grand-theft-auto-2"></a> | [Grand Theft Auto 2](https://lutris.net/games/grand-theft-auto-2/) | `proton` | `nix run .#grand-theft-auto-2` |
| <a href="https://lutris.net/games/grand-theft-auto-san-andreas/"><img src="https://lutris.net/games/banner/grand-theft-auto-san-andreas.jpg" height="40" alt="grand-theft-auto-san-andreas"></a> | [Grand Theft Auto: San Andreas](https://lutris.net/games/grand-theft-auto-san-andreas/) | `proton` | `nix run .#grand-theft-auto-san-andreas` |
| <a href="https://lutris.net/games/grand-theft-auto-vice-city/"><img src="https://lutris.net/games/banner/grand-theft-auto-vice-city.jpg" height="40" alt="grand-theft-auto-vice-city"></a> | [Grand Theft Auto: Vice City](https://lutris.net/games/grand-theft-auto-vice-city/) | `proton` | `nix run .#grand-theft-auto-vice-city` |
| <a href="https://lutris.net/games/graveyard-keeper/"><img src="https://lutris.net/games/banner/graveyard-keeper.jpg" height="40" alt="graveyard-keeper"></a> | [Graveyard Keeper +3 DLC](https://lutris.net/games/graveyard-keeper/) | `native` | `nix run .#graveyard-keeper` |
| <a href="https://lutris.net/games/grim-fandango-remastered/"><img src="https://lutris.net/games/banner/grim-fandango-remastered.jpg" height="40" alt="grim-fandango-remastered"></a> | [Grim Fandango Remastered](https://lutris.net/games/grim-fandango-remastered/) | `native` | `nix run .#grim-fandango-remastered` |
| <a href="https://lutris.net/games/gubble/"><img src="https://lutris.net/games/banner/gubble.jpg" height="40" alt="gubble"></a> | [Gubble](https://lutris.net/games/gubble/) | `proton` | `nix run .#gubble` |
| <a href="https://lutris.net/games/half-life/"><img src="https://lutris.net/games/banner/half-life.jpg" height="40" alt="half-life"></a> | [Half-Life](https://lutris.net/games/half-life/) | `proton` | `nix run .#half-life` |
| <a href="https://lutris.net/games/half-life-uplink/"><img src="https://lutris.net/games/banner/half-life-uplink.jpg" height="40" alt="half-life-uplink"></a> | [Half-Life: Uplink](https://lutris.net/games/half-life-uplink/) | `proton` | `nix run .#half-life-uplink` |
| <a href="https://lutris.net/games/hardspace-shipbreaker/"><img src="https://lutris.net/games/banner/hardspace-shipbreaker.jpg" height="40" alt="hardspace-shipbreaker"></a> | [Hardspace: Shipbreaker](https://lutris.net/games/hardspace-shipbreaker/) | `proton` | `nix run .#hardspace-shipbreaker` |
| <a href="https://lutris.net/games/harvest-moon/"><img src="https://lutris.net/games/banner/harvest-moon.jpg" height="40" alt="harvest-moon"></a> | [Harvest Moon](https://lutris.net/games/harvest-moon/) | `retroarch` | `nix run .#harvest-moon` |
| <a href="https://lutris.net/games/heroes-of-might-and-magic-2-gold/"><img src="https://lutris.net/games/banner/heroes-of-might-and-magic-2-gold.jpg" height="40" alt="heroes-of-might-and-magic-2-gold"></a> | [Heroes of Might & Magic II Gold](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `native` | `nix run .#heroes-of-might-and-magic-2-gold` |
| <a href="https://lutris.net/games/hexcells/"><img src="https://lutris.net/games/banner/hexcells.jpg" height="40" alt="hexcells"></a> | [Hexcells](https://lutris.net/games/hexcells/) | `proton` | `nix run .#hexcells` |
| <a href="https://lutris.net/games/hollow-knight/"><img src="https://lutris.net/games/banner/hollow-knight.jpg" height="40" alt="hollow-knight"></a> | [Hollow Knight](https://lutris.net/games/hollow-knight/) | `proton` | `nix run .#hollow-knight` |
| <a href="https://lutris.net/games/hollow-knight-silksong/"><img src="https://lutris.net/games/banner/hollow-knight-silksong.jpg" height="40" alt="hollow-knight-silksong"></a> | [Hollow Knight: Silksong](https://lutris.net/games/hollow-knight-silksong/) | `proton` | `nix run .#hollow-knight-silksong` |
| <a href="https://lutris.net/games/homeworld/"><img src="https://lutris.net/games/banner/homeworld.jpg" height="40" alt="homeworld"></a> | [Homeworld 2](https://lutris.net/games/homeworld/) | `proton` | `nix run .#homeworld` |
| <a href="https://lutris.net/games/hotline-miami/"><img src="https://lutris.net/games/banner/hotline-miami.jpg" height="40" alt="hotline-miami"></a> | [Hotline Miami](https://lutris.net/games/hotline-miami/) | `native` | `nix run .#hotline-miami` |
| <a href="https://lutris.net/games/hotline-miami-2-wrong-number/"><img src="https://lutris.net/games/banner/hotline-miami-2-wrong-number.jpg" height="40" alt="hotline-miami-2-wrong-number"></a> | [Hotline Miami 2: Wrong Number](https://lutris.net/games/hotline-miami-2-wrong-number/) | `native` | `nix run .#hotline-miami-2-wrong-number` |
| <a href="https://lutris.net/games/hyper-metroid/"><img src="https://lutris.net/games/banner/hyper-metroid.jpg" height="40" alt="hyper-metroid"></a> | [Hyper Metroid](https://lutris.net/games/hyper-metroid/) | `retroarch` | `nix run .#hyper-metroid` |
| <a href="https://lutris.net/games/indiana-jones-and-the-fate-of-atlantis/"><img src="https://lutris.net/games/banner/indiana-jones-and-the-fate-of-atlantis.jpg" height="40" alt="indiana-jones-and-the-fate-of-atlantis"></a> | [Indiana Jones and the Fate of Atlantis](https://lutris.net/games/indiana-jones-and-the-fate-of-atlantis/) | `native` | `nix run .#indiana-jones-and-the-fate-of-atlantis` |
| <a href="https://lutris.net/games/indiana-jones-and-the-last-crusade-the-graphic-adventure/"><img src="https://lutris.net/games/banner/indiana-jones-and-the-last-crusade-the-graphic-adventure.jpg" height="40" alt="indiana-jones-and-the-last-crusade-the-graphic-adventure"></a> | [Indiana Jones and the Last Crusade: The Graphic Adventure](https://lutris.net/games/indiana-jones-and-the-last-crusade-the-graphic-adventure/) | `native` | `nix run .#indiana-jones-and-the-last-crusade-the-graphic-adventure` |
| <a href="https://lutris.net/games/inscryption/"><img src="https://lutris.net/games/banner/inscryption.jpg" height="40" alt="inscryption"></a> | [Inscryption](https://lutris.net/games/inscryption/) | `native` | `nix run .#inscryption` |
| <a href="https://lutris.net/games/interstate-76/"><img src="https://lutris.net/games/banner/interstate-76.jpg" height="40" alt="interstate-76"></a> | [Interstate '76 Arsenal](https://lutris.net/games/interstate-76/) | `proton` | `nix run .#interstate-76` |
| <a href="https://lutris.net/games/iron-lung/"><img src="https://lutris.net/games/banner/iron-lung.jpg" height="40" alt="iron-lung"></a> | [Iron Lung](https://lutris.net/games/iron-lung/) | `proton` | `nix run .#iron-lung` |
| <a href="https://lutris.net/games/jade-empire-special-edition/"><img src="https://lutris.net/games/banner/jade-empire-special-edition.jpg" height="40" alt="jade-empire-special-edition"></a> | [Jade Empire: Special Edition](https://lutris.net/games/jade-empire-special-edition/) | `proton` | `nix run .#jade-empire-special-edition` |
| <a href="https://lutris.net/games/jazz-jackrabbit-2/"><img src="https://lutris.net/games/banner/jazz-jackrabbit-2.jpg" height="40" alt="jazz-jackrabbit-2"></a> | [Jazz Jackrabbit 2](https://lutris.net/games/jazz-jackrabbit-2/) | `native` | `nix run .#jazz-jackrabbit-2` |
| <a href="https://lutris.net/games/jet-set-radio/"><img src="https://lutris.net/games/banner/jet-set-radio.jpg" height="40" alt="jet-set-radio"></a> | [Jet Set Radio](https://lutris.net/games/jet-set-radio/) | `proton` | `nix run .#jet-set-radio` |
| <a href="https://lutris.net/games/journey/"><img src="https://lutris.net/games/banner/journey.jpg" height="40" alt="journey"></a> | [Journey](https://lutris.net/games/journey/) | `proton` | `nix run .#journey` |
| <a href="https://lutris.net/games/kknd/"><img src="https://lutris.net/games/banner/kknd.jpg" height="40" alt="kknd"></a> | [KKnD Xtreme / Krush Kill 'n Destroy](https://lutris.net/games/kknd/) | `proton` | `nix run .#kknd` |
| <a href="https://lutris.net/games/lands-of-lore-the-throne-of-chaos/"><img src="https://lutris.net/games/banner/lands-of-lore-the-throne-of-chaos.jpg" height="40" alt="lands-of-lore-the-throne-of-chaos"></a> | [Lands of Lore: The Throne of Chaos](https://lutris.net/games/lands-of-lore-the-throne-of-chaos/) | `custom` | `nix run .#lands-of-lore-the-throne-of-chaos` |
| <a href="https://lutris.net/games/leap-year/"><img src="https://lutris.net/games/banner/leap-year.jpg" height="40" alt="leap-year"></a> | [Leap Year](https://lutris.net/games/leap-year/) | `proton` | `nix run .#leap-year` |
| <a href="https://lutris.net/games/leap-year-march/"><img src="https://lutris.net/games/banner/leap-year-march.jpg" height="40" alt="leap-year-march"></a> | [Leap Year: March](https://lutris.net/games/leap-year-march/) | `proton` | `nix run .#leap-year-march` |
| <a href="https://lutris.net/games/legacy-of-kain-soul-reaver/"><img src="https://lutris.net/games/banner/legacy-of-kain-soul-reaver.jpg" height="40" alt="legacy-of-kain-soul-reaver"></a> | [Legacy of Kain: Soul Reaver](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `proton` | `nix run .#legacy-of-kain-soul-reaver` |
| <a href="https://lutris.net/games/legacy-of-kaintm-soul-reaver-12-remastered/"><img src="https://lutris.net/games/banner/legacy-of-kaintm-soul-reaver-12-remastered.jpg" height="40" alt="legacy-of-kaintm-soul-reaver-12-remastered"></a> | [Legacy of Kain Soul Reaver 1+2 Remastered](https://lutris.net/games/legacy-of-kaintm-soul-reaver-12-remastered/) | `proton` | `nix run .#legacy-of-kaintm-soul-reaver-12-remastered` |
| <a href="https://lutris.net/games/lego-star-wars-the-complete-saga/"><img src="https://lutris.net/games/banner/lego-star-wars-the-complete-saga.jpg" height="40" alt="lego-star-wars-the-complete-saga"></a> | [LEGO Star Wars: The Complete Saga](https://lutris.net/games/lego-star-wars-the-complete-saga/) | `proton` | `nix run .#lego-star-wars-the-complete-saga` |
| <a href="https://lutris.net/games/lemmings/"><img src="https://lutris.net/games/banner/lemmings.jpg" height="40" alt="lemmings"></a> | [Lemmings](https://lutris.net/games/lemmings/) | `native` | `nix run .#lemmings` |
| <a href="https://lutris.net/games/lemmings-95/"><img src="https://lutris.net/games/banner/lemmings-95.jpg" height="40" alt="lemmings-95"></a> | [Lemmings 95](https://lutris.net/games/lemmings-95/) | `native` | `nix run .#lemmings-95` |
| <a href="https://lutris.net/games/loop-hero/"><img src="https://lutris.net/games/banner/loop-hero.jpg" height="40" alt="loop-hero"></a> | [Loop Hero](https://lutris.net/games/loop-hero/) | `custom` | `nix run .#loop-hero` |
| <a href="https://lutris.net/games/lorns-lure/"><img src="https://lutris.net/games/banner/lorns-lure.jpg" height="40" alt="lorns-lure"></a> | [Lorn's Lure](https://lutris.net/games/lorns-lure/) | `proton` | `nix run .#lorns-lure` |
| <a href="https://lutris.net/games/luftrausers/"><img src="https://lutris.net/games/banner/luftrausers.jpg" height="40" alt="luftrausers"></a> | [Luftrausers](https://lutris.net/games/luftrausers/) | `custom` | `nix run .#luftrausers` |
| <a href="https://lutris.net/games/magicka/"><img src="https://lutris.net/games/banner/magicka.jpg" height="40" alt="magicka"></a> | [Magicka](https://lutris.net/games/magicka/) | `proton` | `nix run .#magicka` |
| <a href="https://lutris.net/games/manhunt/"><img src="https://lutris.net/games/banner/manhunt.jpg" height="40" alt="manhunt"></a> | [Manhunt](https://lutris.net/games/manhunt/) | `proton` | `nix run .#manhunt` |
| <a href="https://lutris.net/games/max-payne/"><img src="https://lutris.net/games/banner/max-payne.jpg" height="40" alt="max-payne"></a> | [Max Payne](https://lutris.net/games/max-payne/) | `proton` | `nix run .#max-payne` |
| <a href="https://lutris.net/games/max-payne-2-the-fall-of-max-payne/"><img src="https://lutris.net/games/banner/max-payne-2-the-fall-of-max-payne.jpg" height="40" alt="max-payne-2-the-fall-of-max-payne"></a> | [Max Payne 2: The Fall of Max Payne](https://lutris.net/games/max-payne-2-the-fall-of-max-payne/) | `proton` | `nix run .#max-payne-2-the-fall-of-max-payne` |
| <a href="https://lutris.net/games/mdk/"><img src="https://lutris.net/games/banner/mdk.jpg" height="40" alt="mdk"></a> | [MDK](https://lutris.net/games/mdk/) | `proton` | `nix run .#mdk` |
| <a href="https://lutris.net/games/medal-of-honor-allied-assault/"><img src="https://lutris.net/games/banner/medal-of-honor-allied-assault.jpg" height="40" alt="medal-of-honor-allied-assault"></a> | [Medal of Honor: Allied Assault](https://lutris.net/games/medal-of-honor-allied-assault/) | `native` | `nix run .#medal-of-honor-allied-assault` |
| <a href="https://lutris.net/games/metal-gear-solid/"><img src="https://lutris.net/games/banner/metal-gear-solid.jpg" height="40" alt="metal-gear-solid"></a> | [Metal Gear Solid](https://lutris.net/games/metal-gear-solid/) | `retroarch` | `nix run .#metal-gear-solid` |
| <a href="https://lutris.net/games/metal-gear-solid-2-substance/"><img src="https://lutris.net/games/banner/metal-gear-solid-2-substance.jpg" height="40" alt="metal-gear-solid-2-substance"></a> | [Metal Gear Solid 2: Substance](https://lutris.net/games/metal-gear-solid-2-substance/) | `pcsx2` | `nix run .#metal-gear-solid-2-substance` |
| <a href="https://lutris.net/games/metal-slug--1/"><img src="https://lutris.net/games/banner/metal-slug--1.jpg" height="40" alt="metal-slug--1"></a> | [Metal Slug - Super Vehicle-001](https://lutris.net/games/metal-slug--1/) | `retroarch` | `nix run .#metal-slug--1` |
| <a href="https://lutris.net/games/metro-2033-redux/"><img src="https://lutris.net/games/banner/metro-2033-redux.jpg" height="40" alt="metro-2033-redux"></a> | [Metro 2033 Redux](https://lutris.net/games/metro-2033-redux/) | `custom` | `nix run .#metro-2033-redux` |
| <a href="https://lutris.net/games/monkey-island-2-special-edition/"><img src="https://lutris.net/games/banner/monkey-island-2-special-edition.jpg" height="40" alt="monkey-island-2-special-edition"></a> | [Monkey Island 2: LeChuck's Revenge](https://lutris.net/games/monkey-island-2-special-edition/) | `native` | `nix run .#monkey-island-2-special-edition` |
| <a href="https://lutris.net/games/mouthwashing/"><img src="https://lutris.net/games/banner/mouthwashing.jpg" height="40" alt="mouthwashing"></a> | [Mouthwashing](https://lutris.net/games/mouthwashing/) | `proton` | `nix run .#mouthwashing` |
| <a href="https://lutris.net/games/myst/"><img src="https://lutris.net/games/banner/myst.jpg" height="40" alt="myst"></a> | [Myst: Masterpiece Edition](https://lutris.net/games/myst/) | `native` | `nix run .#myst` |
| <a href="https://lutris.net/games/need-for-speed-most-wanted/"><img src="https://lutris.net/games/banner/need-for-speed-most-wanted.jpg" height="40" alt="need-for-speed-most-wanted"></a> | [Need for Speed: Most Wanted (2005)](https://lutris.net/games/need-for-speed-most-wanted/) | `proton` | `nix run .#need-for-speed-most-wanted` |
| <a href="https://lutris.net/games/need-for-speed-underground-2/"><img src="https://lutris.net/games/banner/need-for-speed-underground-2.jpg" height="40" alt="need-for-speed-underground-2"></a> | [Need for Speed: Underground 2](https://lutris.net/games/need-for-speed-underground-2/) | `proton` | `nix run .#need-for-speed-underground-2` |
| <a href="https://lutris.net/games/no-one-lives-forever/"><img src="https://lutris.net/games/banner/no-one-lives-forever.jpg" height="40" alt="no-one-lives-forever"></a> | [The Operative: No One Lives Forever](https://lutris.net/games/no-one-lives-forever/) | `proton` | `nix run .#no-one-lives-forever` |
| <a href="https://lutris.net/games/noita/"><img src="https://lutris.net/games/banner/noita.jpg" height="40" alt="noita"></a> | [Noita](https://lutris.net/games/noita/) | `proton` | `nix run .#noita` |
| <a href="https://lutris.net/games/olliolli/"><img src="https://lutris.net/games/banner/olliolli.jpg" height="40" alt="olliolli"></a> | [OlliOlli](https://lutris.net/games/olliolli/) | `proton` | `nix run .#olliolli` |
| <a href="https://lutris.net/games/osmos/"><img src="https://lutris.net/games/banner/osmos.jpg" height="40" alt="osmos"></a> | [Osmos](https://lutris.net/games/osmos/) | `native` | `nix run .#osmos` |
| <a href="https://lutris.net/games/outer-wilds/"><img src="https://lutris.net/games/banner/outer-wilds.jpg" height="40" alt="outer-wilds"></a> | [Outer Wilds](https://lutris.net/games/outer-wilds/) | `proton` | `nix run .#outer-wilds` |
| <a href="https://lutris.net/games/outer-wilds-alpha/"><img src="https://lutris.net/games/banner/outer-wilds-alpha.jpg" height="40" alt="outer-wilds-alpha"></a> | [Outer Wilds Alpha 1.2](https://lutris.net/games/outer-wilds-alpha/) | `proton` | `nix run .#outer-wilds-alpha` |
| <a href="https://lutris.net/games/painkiller/"><img src="https://lutris.net/games/banner/painkiller.jpg" height="40" alt="painkiller"></a> | [Painkiller: Black Edition](https://lutris.net/games/painkiller/) | `proton` | `nix run .#painkiller` |
| <a href="https://lutris.net/games/papers-please/"><img src="https://lutris.net/games/banner/papers-please.jpg" height="40" alt="papers-please"></a> | [Papers, Please](https://lutris.net/games/papers-please/) | `native` | `nix run .#papers-please` |
| <a href="https://lutris.net/games/paquerette-down-the-bunburrows/"><img src="https://lutris.net/games/banner/paquerette-down-the-bunburrows.jpg" height="40" alt="paquerette-down-the-bunburrows"></a> | [Paquerette Down the Bunburrows v1.1.2](https://lutris.net/games/paquerette-down-the-bunburrows/) | `proton` | `nix run .#paquerette-down-the-bunburrows` |
| <a href="https://lutris.net/games/perfect-dark/"><img src="https://lutris.net/games/banner/perfect-dark.jpg" height="40" alt="perfect-dark"></a> | [Perfect Dark](https://lutris.net/games/perfect-dark/) | `retroarch` | `nix run .#perfect-dark` |
| <a href="https://lutris.net/games/pico-park/"><img src="https://lutris.net/games/banner/pico-park.jpg" height="40" alt="pico-park"></a> | [Pico Park](https://lutris.net/games/pico-park/) | `proton` | `nix run .#pico-park` |
| <a href="https://lutris.net/games/pico-park-2/"><img src="https://lutris.net/games/banner/pico-park-2.jpg" height="40" alt="pico-park-2"></a> | [Pico Park 2](https://lutris.net/games/pico-park-2/) | `proton` | `nix run .#pico-park-2` |
| <a href="https://lutris.net/games/pico-park-2021/"><img src="https://lutris.net/games/banner/pico-park-2021.jpg" height="40" alt="pico-park-2021"></a> | [PICO PARK](https://lutris.net/games/pico-park-2021/) | `proton` | `nix run .#pico-park-2021` |
| <a href="https://lutris.net/games/planescape-torment/"><img src="https://lutris.net/games/banner/planescape-torment.jpg" height="40" alt="planescape-torment"></a> | [Planescape: Torment](https://lutris.net/games/planescape-torment/) | `native` | `nix run .#planescape-torment` |
| <a href="https://lutris.net/games/plants-vs-zombies/"><img src="https://lutris.net/games/banner/plants-vs-zombies.jpg" height="40" alt="plants-vs-zombies"></a> | [Plants vs. Zombies: Game of the Year Edition](https://lutris.net/games/plants-vs-zombies/) | `proton` | `nix run .#plants-vs-zombies` |
| <a href="https://lutris.net/games/populous-the-beginning/"><img src="https://lutris.net/games/banner/populous-the-beginning.jpg" height="40" alt="populous-the-beginning"></a> | [Populous: The Beginning](https://lutris.net/games/populous-the-beginning/) | `proton` | `nix run .#populous-the-beginning` |
| <a href="https://lutris.net/games/portal/"><img src="https://lutris.net/games/banner/portal.jpg" height="40" alt="portal"></a> | [Portal](https://lutris.net/games/portal/) | `proton` | `nix run .#portal` |
| <a href="https://lutris.net/games/portal-2/"><img src="https://lutris.net/games/banner/portal-2.jpg" height="40" alt="portal-2"></a> | [Portal 2](https://lutris.net/games/portal-2/) | `proton` | `nix run .#portal-2` |
| <a href="https://lutris.net/games/prey-2006/"><img src="https://lutris.net/games/banner/prey-2006.jpg" height="40" alt="prey-2006"></a> | [Prey](https://lutris.net/games/prey-2006/) | `proton` | `nix run .#prey-2006` |
| <a href="https://lutris.net/games/project-zomboid/"><img src="https://lutris.net/games/banner/project-zomboid.jpg" height="40" alt="project-zomboid"></a> | [Project Zomboid](https://lutris.net/games/project-zomboid/) | `custom` | `nix run .#project-zomboid` |
| <a href="https://lutris.net/games/prototype/"><img src="https://lutris.net/games/banner/prototype.jpg" height="40" alt="prototype"></a> | [Prototype](https://lutris.net/games/prototype/) | `proton` | `nix run .#prototype` |
| <a href="https://lutris.net/games/psychonauts/"><img src="https://lutris.net/games/banner/psychonauts.jpg" height="40" alt="psychonauts"></a> | [Psychonauts](https://lutris.net/games/psychonauts/) | `proton` | `nix run .#psychonauts` |
| <a href="https://lutris.net/games/quake-iii-arena/"><img src="https://lutris.net/games/banner/quake-iii-arena.jpg" height="40" alt="quake-iii-arena"></a> | [Quake III Arena](https://lutris.net/games/quake-iii-arena/) | `native` | `nix run .#quake-iii-arena` |
| <a href="https://lutris.net/games/rain-world/"><img src="https://lutris.net/games/banner/rain-world.jpg" height="40" alt="rain-world"></a> | [Rain World](https://lutris.net/games/rain-world/) | `proton` | `nix run .#rain-world` |
| <a href="https://lutris.net/games/return-of-the-obra-dinn/"><img src="https://lutris.net/games/banner/return-of-the-obra-dinn.jpg" height="40" alt="return-of-the-obra-dinn"></a> | [Return of the Obra Dinn](https://lutris.net/games/return-of-the-obra-dinn/) | `proton` | `nix run .#return-of-the-obra-dinn` |
| <a href="https://lutris.net/games/rhythm-doctor/"><img src="https://lutris.net/games/banner/rhythm-doctor.jpg" height="40" alt="rhythm-doctor"></a> | [Rhythm Doctor](https://lutris.net/games/rhythm-doctor/) | `custom` | `nix run .#rhythm-doctor` |
| <a href="https://lutris.net/games/risk-of-rain/"><img src="https://lutris.net/games/banner/risk-of-rain.jpg" height="40" alt="risk-of-rain"></a> | [Risk of Rain](https://lutris.net/games/risk-of-rain/) | `proton` | `nix run .#risk-of-rain` |
| <a href="https://lutris.net/games/roketz--1/"><img src="https://lutris.net/games/banner/roketz--1.jpg" height="40" alt="roketz--1"></a> | [Roketz](https://lutris.net/games/roketz--1/) | `custom` | `nix run .#roketz--1` |
| <a href="https://lutris.net/games/rollercoaster-tycoon/"><img src="https://lutris.net/games/banner/rollercoaster-tycoon.jpg" height="40" alt="rollercoaster-tycoon"></a> | [RollerCoaster Tycoon Deluxe](https://lutris.net/games/rollercoaster-tycoon/) | `proton` | `nix run .#rollercoaster-tycoon` |
| <a href="https://lutris.net/games/rounds/"><img src="https://lutris.net/games/banner/rounds.jpg" height="40" alt="rounds"></a> | [ROUNDS](https://lutris.net/games/rounds/) | `proton` | `nix run .#rounds` |
| <a href="https://lutris.net/games/sanitarium/"><img src="https://lutris.net/games/banner/sanitarium.jpg" height="40" alt="sanitarium"></a> | [Sanitarium](https://lutris.net/games/sanitarium/) | `native` | `nix run .#sanitarium` |
| <a href="https://lutris.net/games/serious-sam/"><img src="https://lutris.net/games/banner/serious-sam.jpg" height="40" alt="serious-sam"></a> | [Serious Sam: The First Encounter](https://lutris.net/games/serious-sam/) | `proton` | `nix run .#serious-sam` |
| <a href="https://lutris.net/games/serious-sam-the-second-encounter/"><img src="https://lutris.net/games/banner/serious-sam-the-second-encounter.jpg" height="40" alt="serious-sam-the-second-encounter"></a> | [Serious Sam: The Second Encounter](https://lutris.net/games/serious-sam-the-second-encounter/) | `proton` | `nix run .#serious-sam-the-second-encounter` |
| <a href="https://lutris.net/games/shadow-of-the-colossus/"><img src="https://lutris.net/games/banner/shadow-of-the-colossus.jpg" height="40" alt="shadow-of-the-colossus"></a> | [Shadow of the Colossus](https://lutris.net/games/shadow-of-the-colossus/) | `pcsx2` | `nix run .#shadow-of-the-colossus` |
| <a href="https://lutris.net/games/shovel-knight/"><img src="https://lutris.net/games/banner/shovel-knight.jpg" height="40" alt="shovel-knight"></a> | [Shovel Knight: Treasure Trove](https://lutris.net/games/shovel-knight/) | `custom` | `nix run .#shovel-knight` |
| <a href="https://lutris.net/games/shovel-knight-treasure-trove/"><img src="https://lutris.net/games/banner/shovel-knight-treasure-trove.jpg" height="40" alt="shovel-knight-treasure-trove"></a> | [Shovel Knight: Treasure Trove](https://lutris.net/games/shovel-knight-treasure-trove/) | `native` | `nix run .#shovel-knight-treasure-trove` |
| <a href="https://lutris.net/games/sid-meiers-pirates/"><img src="https://lutris.net/games/banner/sid-meiers-pirates.jpg" height="40" alt="sid-meiers-pirates"></a> | [Sid Meier's Pirates!](https://lutris.net/games/sid-meiers-pirates/) | `proton` | `nix run .#sid-meiers-pirates` |
| <a href="https://lutris.net/games/signalis/"><img src="https://lutris.net/games/banner/signalis.jpg" height="40" alt="signalis"></a> | [Signalis](https://lutris.net/games/signalis/) | `proton` | `nix run .#signalis` |
| <a href="https://lutris.net/games/silent-hill-2/"><img src="https://lutris.net/games/banner/silent-hill-2.jpg" height="40" alt="silent-hill-2"></a> | [Silent Hill 2](https://lutris.net/games/silent-hill-2/) | `pcsx2` | `nix run .#silent-hill-2` |
| <a href="https://lutris.net/games/simcity-2000/"><img src="https://lutris.net/games/banner/simcity-2000.jpg" height="40" alt="simcity-2000"></a> | [SimCity 2000 Special Edition](https://lutris.net/games/simcity-2000/) | `custom` | `nix run .#simcity-2000` |
| <a href="https://lutris.net/games/simon-the-sorcerer/"><img src="https://lutris.net/games/banner/simon-the-sorcerer.jpg" height="40" alt="simon-the-sorcerer"></a> | [Simon the Sorcerer](https://lutris.net/games/simon-the-sorcerer/) | `native` | `nix run .#simon-the-sorcerer` |
| <a href="https://lutris.net/games/sin/"><img src="https://lutris.net/games/banner/sin.jpg" height="40" alt="sin"></a> | [SiN Gold](https://lutris.net/games/sin/) | `proton` | `nix run .#sin` |
| <a href="https://lutris.net/games/slay-the-spire/"><img src="https://lutris.net/games/banner/slay-the-spire.jpg" height="40" alt="slay-the-spire"></a> | [Slay the Spire](https://lutris.net/games/slay-the-spire/) | `custom` | `nix run .#slay-the-spire` |
| <a href="https://lutris.net/games/slay-the-spire-2/"><img src="https://lutris.net/games/banner/slay-the-spire-2.jpg" height="40" alt="slay-the-spire-2"></a> | [Slay the Spire 2](https://lutris.net/games/slay-the-spire-2/) | `proton` | `nix run .#slay-the-spire-2` |
| <a href="https://lutris.net/games/songs-of-syx/"><img src="https://lutris.net/games/banner/songs-of-syx.jpg" height="40" alt="songs-of-syx"></a> | [Songs of Syx](https://lutris.net/games/songs-of-syx/) | `custom` | `nix run .#songs-of-syx` |
| <a href="https://lutris.net/games/spec-ops-the-line/"><img src="https://lutris.net/games/banner/spec-ops-the-line.jpg" height="40" alt="spec-ops-the-line"></a> | [Spec Ops: The Line](https://lutris.net/games/spec-ops-the-line/) | `proton` | `nix run .#spec-ops-the-line` |
| <a href="https://lutris.net/games/stalker-shadow-of-chernobyl/"><img src="https://lutris.net/games/banner/stalker-shadow-of-chernobyl.jpg" height="40" alt="stalker-shadow-of-chernobyl"></a> | [S.T.A.L.K.E.R.: Shadow of Chernobyl](https://lutris.net/games/stalker-shadow-of-chernobyl/) | `proton` | `nix run .#stalker-shadow-of-chernobyl` |
| <a href="https://lutris.net/games/star-wars-battlefront-2/"><img src="https://lutris.net/games/banner/star-wars-battlefront-2.jpg" height="40" alt="star-wars-battlefront-2"></a> | [Star Wars: Battlefront II (2005) v1.1 Rerelease via Proton and gamescope](https://lutris.net/games/star-wars-battlefront-2/) | `proton` | `nix run .#star-wars-battlefront-2` |
| <a href="https://lutris.net/games/star-wars-jedi-knight-ii-jedi-outcast/"><img src="https://lutris.net/games/banner/star-wars-jedi-knight-ii-jedi-outcast.jpg" height="40" alt="star-wars-jedi-knight-ii-jedi-outcast"></a> | [Star Wars Jedi Knight II: Jedi Outcast](https://lutris.net/games/star-wars-jedi-knight-ii-jedi-outcast/) | `native` | `nix run .#star-wars-jedi-knight-ii-jedi-outcast` |
| <a href="https://lutris.net/games/starcraft/"><img src="https://lutris.net/games/banner/starcraft.jpg" height="40" alt="starcraft"></a> | [StarCraft + Brood War](https://lutris.net/games/starcraft/) | `proton` | `nix run .#starcraft` |
| <a href="https://lutris.net/games/stardew-valley/"><img src="https://lutris.net/games/banner/stardew-valley.jpg" height="40" alt="stardew-valley"></a> | [Stardew Valley](https://lutris.net/games/stardew-valley/) | `custom` | `nix run .#stardew-valley` |
| <a href="https://lutris.net/games/stronghold-hd/"><img src="https://lutris.net/games/banner/stronghold-hd.jpg" height="40" alt="stronghold-hd"></a> | [Stronghold HD](https://lutris.net/games/stronghold-hd/) | `proton` | `nix run .#stronghold-hd` |
| <a href="https://lutris.net/games/stubbs-the-zombie-in-rebel-without-a-pulse/"><img src="https://lutris.net/games/banner/stubbs-the-zombie-in-rebel-without-a-pulse.jpg" height="40" alt="stubbs-the-zombie-in-rebel-without-a-pulse"></a> | [Stubbs the Zombie in Rebel Without a Pulse](https://lutris.net/games/stubbs-the-zombie-in-rebel-without-a-pulse/) | `proton` | `nix run .#stubbs-the-zombie-in-rebel-without-a-pulse` |
| <a href="https://lutris.net/games/super-hexagon/"><img src="https://lutris.net/games/banner/super-hexagon.jpg" height="40" alt="super-hexagon"></a> | [Super Hexagon](https://lutris.net/games/super-hexagon/) | `native` | `nix run .#super-hexagon` |
| <a href="https://lutris.net/games/super-mario-64/"><img src="https://lutris.net/games/banner/super-mario-64.jpg" height="40" alt="super-mario-64"></a> | [Super Mario 64](https://lutris.net/games/super-mario-64/) | `retroarch` | `nix run .#super-mario-64` |
| <a href="https://lutris.net/games/super-meat-boy/"><img src="https://lutris.net/games/banner/super-meat-boy.jpg" height="40" alt="super-meat-boy"></a> | [Super Meat Boy](https://lutris.net/games/super-meat-boy/) | `custom` | `nix run .#super-meat-boy` |
| <a href="https://lutris.net/games/super-metroid/"><img src="https://lutris.net/games/banner/super-metroid.jpg" height="40" alt="super-metroid"></a> | [Super Metroid](https://lutris.net/games/super-metroid/) | `retroarch` | `nix run .#super-metroid` |
| <a href="https://lutris.net/games/super-smash-bros-melee/"><img src="https://lutris.net/games/banner/super-smash-bros-melee.jpg" height="40" alt="super-smash-bros-melee"></a> | [Super Smash Bros. Melee](https://lutris.net/games/super-smash-bros-melee/) | `native` | `nix run .#super-smash-bros-melee` |
| <a href="https://lutris.net/games/superhot/"><img src="https://lutris.net/games/banner/superhot.jpg" height="40" alt="superhot"></a> | [SUPERHOT](https://lutris.net/games/superhot/) | `proton` | `nix run .#superhot` |
| <a href="https://lutris.net/games/swat-4/"><img src="https://lutris.net/games/banner/swat-4.jpg" height="40" alt="swat-4"></a> | [SWAT 4: Gold Edition](https://lutris.net/games/swat-4/) | `proton` | `nix run .#swat-4` |
| <a href="https://lutris.net/games/syndicate/"><img src="https://lutris.net/games/banner/syndicate.jpg" height="40" alt="syndicate"></a> | [Syndicate](https://lutris.net/games/syndicate/) | `native` | `nix run .#syndicate` |
| <a href="https://lutris.net/games/system-shock/"><img src="https://lutris.net/games/banner/system-shock.jpg" height="40" alt="system-shock"></a> | [System Shock](https://lutris.net/games/system-shock/) | `native` | `nix run .#system-shock` |
| <a href="https://lutris.net/games/system-shock-2/"><img src="https://lutris.net/games/banner/system-shock-2.jpg" height="40" alt="system-shock-2"></a> | [System Shock 2](https://lutris.net/games/system-shock-2/) | `proton` | `nix run .#system-shock-2` |
| <a href="https://lutris.net/games/the-cat-lady/"><img src="https://lutris.net/games/banner/the-cat-lady.jpg" height="40" alt="the-cat-lady"></a> | [The Cat Lady](https://lutris.net/games/the-cat-lady/) | `proton` | `nix run .#the-cat-lady` |
| <a href="https://lutris.net/games/the-curse-of-monkey-island/"><img src="https://lutris.net/games/banner/the-curse-of-monkey-island.jpg" height="40" alt="the-curse-of-monkey-island"></a> | [The Curse of Monkey Island](https://lutris.net/games/the-curse-of-monkey-island/) | `native` | `nix run .#the-curse-of-monkey-island` |
| <a href="https://lutris.net/games/the-elder-scrolls-arena/"><img src="https://lutris.net/games/banner/the-elder-scrolls-arena.jpg" height="40" alt="the-elder-scrolls-arena"></a> | [The Elder Scrolls: Arena](https://lutris.net/games/the-elder-scrolls-arena/) | `custom` | `nix run .#the-elder-scrolls-arena` |
| <a href="https://lutris.net/games/the-elder-scrolls-ii-daggerfall/"><img src="https://lutris.net/games/banner/the-elder-scrolls-ii-daggerfall.jpg" height="40" alt="the-elder-scrolls-ii-daggerfall"></a> | [The Elder Scrolls II: Daggerfall](https://lutris.net/games/the-elder-scrolls-ii-daggerfall/) | `custom` | `nix run .#the-elder-scrolls-ii-daggerfall` |
| <a href="https://lutris.net/games/the-elder-scrolls-iii-morrowind/"><img src="https://lutris.net/games/banner/the-elder-scrolls-iii-morrowind.jpg" height="40" alt="the-elder-scrolls-iii-morrowind"></a> | [The Elder Scrolls III: Morrowind GOTY](https://lutris.net/games/the-elder-scrolls-iii-morrowind/) | `native` | `nix run .#the-elder-scrolls-iii-morrowind` |
| <a href="https://lutris.net/games/the-elder-scrolls-iv-oblivion/"><img src="https://lutris.net/games/banner/the-elder-scrolls-iv-oblivion.jpg" height="40" alt="the-elder-scrolls-iv-oblivion"></a> | [The Elder Scrolls IV: Oblivion GOTY](https://lutris.net/games/the-elder-scrolls-iv-oblivion/) | `proton` | `nix run .#the-elder-scrolls-iv-oblivion` |
| <a href="https://lutris.net/games/the-floor-is-jelly/"><img src="https://lutris.net/games/banner/the-floor-is-jelly.jpg" height="40" alt="the-floor-is-jelly"></a> | [The Floor is Jelly](https://lutris.net/games/the-floor-is-jelly/) | `proton` | `nix run .#the-floor-is-jelly` |
| <a href="https://lutris.net/games/the-legend-of-zelda-a-link-to-the-past/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-a-link-to-the-past.jpg" height="40" alt="the-legend-of-zelda-a-link-to-the-past"></a> | [The Legend of Zelda: A Link to the Past](https://lutris.net/games/the-legend-of-zelda-a-link-to-the-past/) | `retroarch` | `nix run .#the-legend-of-zelda-a-link-to-the-past` |
| <a href="https://lutris.net/games/the-legend-of-zelda-majoras-mask/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-majoras-mask.jpg" height="40" alt="the-legend-of-zelda-majoras-mask"></a> | [The Legend of Zelda: Majora's Mask](https://lutris.net/games/the-legend-of-zelda-majoras-mask/) | `retroarch` | `nix run .#the-legend-of-zelda-majoras-mask` |
| <a href="https://lutris.net/games/the-legend-of-zelda-ocarina-of-time/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-ocarina-of-time.jpg" height="40" alt="the-legend-of-zelda-ocarina-of-time"></a> | [The Legend of Zelda: Ocarina of Time](https://lutris.net/games/the-legend-of-zelda-ocarina-of-time/) | `retroarch` | `nix run .#the-legend-of-zelda-ocarina-of-time` |
| <a href="https://lutris.net/games/the-legend-of-zelda-oracle-of-ages/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-oracle-of-ages.jpg" height="40" alt="the-legend-of-zelda-oracle-of-ages"></a> | [The Legend of Zelda: Oracle of Ages](https://lutris.net/games/the-legend-of-zelda-oracle-of-ages/) | `retroarch` | `nix run .#the-legend-of-zelda-oracle-of-ages` |
| <a href="https://lutris.net/games/the-legend-of-zelda-oracle-of-seasons/"><img src="https://lutris.net/games/banner/the-legend-of-zelda-oracle-of-seasons.jpg" height="40" alt="the-legend-of-zelda-oracle-of-seasons"></a> | [The Legend of Zelda: Oracle of Seasons](https://lutris.net/games/the-legend-of-zelda-oracle-of-seasons/) | `retroarch` | `nix run .#the-legend-of-zelda-oracle-of-seasons` |
| <a href="https://lutris.net/games/the-secret-of-monkey-island/"><img src="https://lutris.net/games/banner/the-secret-of-monkey-island.jpg" height="40" alt="the-secret-of-monkey-island"></a> | [The Secret of Monkey Island](https://lutris.net/games/the-secret-of-monkey-island/) | `native` | `nix run .#the-secret-of-monkey-island` |
| <a href="https://lutris.net/games/the-settlers-ii-gold-edition/"><img src="https://lutris.net/games/banner/the-settlers-ii-gold-edition.jpg" height="40" alt="the-settlers-ii-gold-edition"></a> | [The Settlers II Gold](https://lutris.net/games/the-settlers-ii-gold-edition/) | `native` | `nix run .#the-settlers-ii-gold-edition` |
| <a href="https://lutris.net/games/the-simpsons-hit-run/"><img src="https://lutris.net/games/banner/the-simpsons-hit-run.jpg" height="40" alt="the-simpsons-hit-run"></a> | [The Simpsons: Hit & Run](https://lutris.net/games/the-simpsons-hit-run/) | `proton` | `nix run .#the-simpsons-hit-run` |
| <a href="https://lutris.net/games/the-typing-of-the-dead/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead.jpg" height="40" alt="the-typing-of-the-dead"></a> | [The Typing of the Dead](https://lutris.net/games/the-typing-of-the-dead/) | `proton` | `nix run .#the-typing-of-the-dead` |
| <a href="https://lutris.net/games/the-typing-of-the-dead-overkill/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead-overkill.jpg" height="40" alt="the-typing-of-the-dead-overkill"></a> | [The Typing of the Dead: Overkill](https://lutris.net/games/the-typing-of-the-dead-overkill/) | `proton` | `nix run .#the-typing-of-the-dead-overkill` |
| <a href="https://lutris.net/games/theme-hospital/"><img src="https://lutris.net/games/banner/theme-hospital.jpg" height="40" alt="theme-hospital"></a> | [Theme Hospital](https://lutris.net/games/theme-hospital/) | `native` | `nix run .#theme-hospital` |
| <a href="https://lutris.net/games/thief-2/"><img src="https://lutris.net/games/banner/thief-2.jpg" height="40" alt="thief-2"></a> | [Thief II: The Metal Age](https://lutris.net/games/thief-2/) | `proton` | `nix run .#thief-2` |
| <a href="https://lutris.net/games/thief-gold/"><img src="https://lutris.net/games/banner/thief-gold.jpg" height="40" alt="thief-gold"></a> | [Thief Gold with TFix](https://lutris.net/games/thief-gold/) | `proton` | `nix run .#thief-gold` |
| <a href="https://lutris.net/games/total-annihilation/"><img src="https://lutris.net/games/banner/total-annihilation.jpg" height="40" alt="total-annihilation"></a> | [Total Annihilation - Commander Pack](https://lutris.net/games/total-annihilation/) | `proton` | `nix run .#total-annihilation` |
| <a href="https://lutris.net/games/total-overdose/"><img src="https://lutris.net/games/banner/total-overdose.jpg" height="40" alt="total-overdose"></a> | [Total Overdose: A Gunslinger's Tale in Mexico](https://lutris.net/games/total-overdose/) | `proton` | `nix run .#total-overdose` |
| <a href="https://lutris.net/games/towerfall-ascension/"><img src="https://lutris.net/games/banner/towerfall-ascension.jpg" height="40" alt="towerfall-ascension"></a> | [TowerFall Ascension + Dark World](https://lutris.net/games/towerfall-ascension/) | `proton` | `nix run .#towerfall-ascension` |
| <a href="https://lutris.net/games/tunic/"><img src="https://lutris.net/games/banner/tunic.jpg" height="40" alt="tunic"></a> | [TUNIC](https://lutris.net/games/tunic/) | `proton` | `nix run .#tunic` |
| <a href="https://lutris.net/games/ultrakill/"><img src="https://lutris.net/games/banner/ultrakill.jpg" height="40" alt="ultrakill"></a> | [ULTRAKILL](https://lutris.net/games/ultrakill/) | `proton` | `nix run .#ultrakill` |
| <a href="https://lutris.net/games/undertale/"><img src="https://lutris.net/games/banner/undertale.jpg" height="40" alt="undertale"></a> | [Undertale](https://lutris.net/games/undertale/) | `native` | `nix run .#undertale` |
| <a href="https://lutris.net/games/unreal-tournament/"><img src="https://lutris.net/games/banner/unreal-tournament.jpg" height="40" alt="unreal-tournament"></a> | [Unreal Tournament](https://lutris.net/games/unreal-tournament/) | `native` | `nix run .#unreal-tournament` |
| <a href="https://lutris.net/games/unreal-tournament-2004/"><img src="https://lutris.net/games/banner/unreal-tournament-2004.jpg" height="40" alt="unreal-tournament-2004"></a> | [Unreal Tournament 2004](https://lutris.net/games/unreal-tournament-2004/) | `native` | `nix run .#unreal-tournament-2004` |
| <a href="https://lutris.net/games/untitled-goose-game/"><img src="https://lutris.net/games/banner/untitled-goose-game.jpg" height="40" alt="untitled-goose-game"></a> | [Untitled Goose Game](https://lutris.net/games/untitled-goose-game/) | `proton` | `nix run .#untitled-goose-game` |
| <a href="https://lutris.net/games/uplink/"><img src="https://lutris.net/games/banner/uplink.jpg" height="40" alt="uplink"></a> | [Uplink: Hacker Elite v1.6](https://lutris.net/games/uplink/) | `proton` | `nix run .#uplink` |
| <a href="https://lutris.net/games/v-rising/"><img src="https://lutris.net/games/banner/v-rising.jpg" height="40" alt="v-rising"></a> | [V Rising](https://lutris.net/games/v-rising/) | `proton` | `nix run .#v-rising` |
| <a href="https://lutris.net/games/vampire-crawlers/"><img src="https://lutris.net/games/banner/vampire-crawlers.jpg" height="40" alt="vampire-crawlers"></a> | [Vampire Crawlers](https://lutris.net/games/vampire-crawlers/) | `proton` | `nix run .#vampire-crawlers` |
| <a href="https://lutris.net/games/vampire-survivors/"><img src="https://lutris.net/games/banner/vampire-survivors.jpg" height="40" alt="vampire-survivors"></a> | [Vampire Survivors + 3 DLC](https://lutris.net/games/vampire-survivors/) | `native` | `nix run .#vampire-survivors` |
| <a href="https://lutris.net/games/vampire-the-masquerade-bloodlines/"><img src="https://lutris.net/games/banner/vampire-the-masquerade-bloodlines.jpg" height="40" alt="vampire-the-masquerade-bloodlines"></a> | [Vampire: The Masquerade — Bloodlines](https://lutris.net/games/vampire-the-masquerade-bloodlines/) | `proton` | `nix run .#vampire-the-masquerade-bloodlines` |
| <a href="https://lutris.net/games/vectronom/"><img src="https://lutris.net/games/banner/vectronom.jpg" height="40" alt="vectronom"></a> | [Vectronom](https://lutris.net/games/vectronom/) | `proton` | `nix run .#vectronom` |
| <a href="https://lutris.net/games/void-stranger/"><img src="https://lutris.net/games/banner/void-stranger.jpg" height="40" alt="void-stranger"></a> | [Void Stranger](https://lutris.net/games/void-stranger/) | `proton` | `nix run .#void-stranger` |
| <a href="https://lutris.net/games/vvvvvv/"><img src="https://lutris.net/games/banner/vvvvvv.jpg" height="40" alt="vvvvvv"></a> | [VVVVVV](https://lutris.net/games/vvvvvv/) | `native` | `nix run .#vvvvvv` |
| <a href="https://lutris.net/games/warcraft-iii-the-frozen-throne/"><img src="https://lutris.net/games/banner/warcraft-iii-the-frozen-throne.jpg" height="40" alt="warcraft-iii-the-frozen-throne"></a> | [Warcraft III: Reign of Chaos + The Frozen Throne v1.26a](https://lutris.net/games/warcraft-iii-the-frozen-throne/) | `proton` | `nix run .#warcraft-iii-the-frozen-throne` |
| <a href="https://lutris.net/games/warzone-2100/"><img src="https://lutris.net/games/banner/warzone-2100.jpg" height="40" alt="warzone-2100"></a> | [Warzone 2100](https://lutris.net/games/warzone-2100/) | `native` | `nix run .#warzone-2100` |
| <a href="https://lutris.net/games/white-knuckle/"><img src="https://lutris.net/games/banner/white-knuckle.jpg" height="40" alt="white-knuckle"></a> | [White Knuckle](https://lutris.net/games/white-knuckle/) | `proton` | `nix run .#white-knuckle` |
| <a href="https://lutris.net/games/world-of-goo/"><img src="https://lutris.net/games/banner/world-of-goo.jpg" height="40" alt="world-of-goo"></a> | [World of Goo](https://lutris.net/games/world-of-goo/) | `native` | `nix run .#world-of-goo` |
| <a href="https://lutris.net/games/worms-wmd/"><img src="https://lutris.net/games/banner/worms-wmd.jpg" height="40" alt="worms-wmd"></a> | [Worms W.M.D](https://lutris.net/games/worms-wmd/) | `proton` | `nix run .#worms-wmd` |
| <a href="https://lutris.net/games/xenogears/"><img src="https://lutris.net/games/banner/xenogears.jpg" height="40" alt="xenogears"></a> | [Xenogears](https://lutris.net/games/xenogears/) | `retroarch` | `nix run .#xenogears` |
| <a href="https://lutris.net/games/yume-nikki/"><img src="https://lutris.net/games/banner/yume-nikki.jpg" height="40" alt="yume-nikki"></a> | [Yume Nikki](https://lutris.net/games/yume-nikki/) | `native` | `nix run .#yume-nikki` |
| <a href="https://lutris.net/games/z/"><img src="https://lutris.net/games/banner/z.jpg" height="40" alt="z"></a> | [Z](https://lutris.net/games/z/) | `custom` | `nix run .#z` |

_267 games_

<!-- END GENERATED GAMES -->

## IPFS

Game files are fetched from IPFS via `fetchIpfs` (see `lib/fetch-ipfs.nix`).
Each game carries an IPFS CID and an optional archive.org fallback URL. At
build time, `aria2c` races Range requests across multiple public IPFS HTTP
gateways (ipfs.io, dweb.link, gateway.pinata.cloud, w3s.link,
nftstorage.link) in parallel; if all gateways fail it falls back to the
fallback URL. The nix output hash ensures integrity regardless of source.

You can prepend a private mirror by exporting `STROM_IPFS_GATEWAYS` (comma-
or space-separated prefixes, no trailing slash, no `/ipfs/`) before invoking
`nix build`. The mirror is preferred when reachable and the public gateways
serve as automatic failover.

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

To test the full fetch path that `fetchIpfs` uses at build time, point
`aria2c` at the same gateway set:

```bash
nix run nixpkgs#aria2 -- \
  --split=8 --max-connection-per-server=4 --min-split-size=16M \
  --out=/tmp/test.7z \
  https://ipfs.io/ipfs/QmZPyB... \
  https://dweb.link/ipfs/QmZPyB... \
  https://nftstorage.link/ipfs/QmZPyB...

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
