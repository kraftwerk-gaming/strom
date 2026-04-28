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
| <a href="https://lutris.net/games/archimedean-dynasty/"><img src="https://lutris.net/games/banner/archimedean-dynasty.jpg" height="40" alt="archimedean-dynasty"></a> | [Archimedean Dynasty / Schleichfahrt (via DOSBox-X with Voodoo/Glide)](https://lutris.net/games/archimedean-dynasty/) | `custom` | `nix run github:kraftwerk-gaming/strom#archimedean-dynasty` |
| <a href="https://lutris.net/games/balatro/"><img src="https://lutris.net/games/banner/balatro.jpg" height="40" alt="balatro"></a> | [Balatro (native Linux)](https://lutris.net/games/balatro/) | `native` | `nix run github:kraftwerk-gaming/strom#balatro` |
| <a href="https://lutris.net/games/burnout-3-takedown/"><img src="https://lutris.net/games/banner/burnout-3-takedown.jpg" height="40" alt="burnout-3-takedown"></a> | [Burnout 3: Takedown (via PCSX2)](https://lutris.net/games/burnout-3-takedown/) | `pcsx2` | `nix run github:kraftwerk-gaming/strom#burnout-3-takedown` |
| <a href="https://lutris.net/games/command-conquer/"><img src="https://lutris.net/games/banner/command-conquer.jpg" height="40" alt="command-conquer"></a> | [Command & Conquer: Tiberian Dawn (Vanilla Conquer, native)](https://lutris.net/games/command-conquer/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer` |
| <a href="https://lutris.net/games/command-conquer-red-alert/"><img src="https://lutris.net/games/banner/command-conquer-red-alert.jpg" height="40" alt="command-conquer-red-alert"></a> | [Command & Conquer: Red Alert (Vanilla Conquer, native)](https://lutris.net/games/command-conquer-red-alert/) | `native` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert` |
| <a href="https://lutris.net/games/command-conquer-red-alert-2/"><img src="https://lutris.net/games/banner/command-conquer-red-alert-2.jpg" height="40" alt="command-conquer-red-alert-2"></a> | [Command & Conquer: Red Alert 2 + Yuri's Revenge (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-red-alert-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-red-alert-2` |
| <a href="https://lutris.net/games/command-conquer-renegade/"><img src="https://lutris.net/games/banner/command-conquer-renegade.jpg" height="40" alt="command-conquer-renegade"></a> | [command-conquer-renegade](https://lutris.net/games/command-conquer-renegade/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-renegade` |
| <a href="https://lutris.net/games/command-conquer-tiberian-sun/"><img src="https://lutris.net/games/banner/command-conquer-tiberian-sun.jpg" height="40" alt="command-conquer-tiberian-sun"></a> | [Command & Conquer: Tiberian Sun + Firestorm (via Proton with cnc-ddraw)](https://lutris.net/games/command-conquer-tiberian-sun/) | `proton` | `nix run github:kraftwerk-gaming/strom#command-conquer-tiberian-sun` |
| <a href="https://lutris.net/games/diablo-ii-lord-of-destruction/"><img src="https://lutris.net/games/banner/diablo-ii-lord-of-destruction.jpg" height="40" alt="diablo-ii-lord-of-destruction"></a> | [Diablo II + Lord of Destruction (CJ_Strife portable, via Proton and gamescope)](https://lutris.net/games/diablo-ii-lord-of-destruction/) | `proton` | `nix run github:kraftwerk-gaming/strom#diablo-ii-lord-of-destruction` |
| <a href="https://lutris.net/games/dungeon-keeper/"><img src="https://lutris.net/games/banner/dungeon-keeper.jpg" height="40" alt="dungeon-keeper"></a> | [Dungeon Keeper (KeeperFX, via Proton and gamescope)](https://lutris.net/games/dungeon-keeper/) | `proton` | `nix run github:kraftwerk-gaming/strom#dungeon-keeper` |
| <a href="https://lutris.net/games/europa-1400-the-guild/"><img src="https://lutris.net/games/banner/europa-1400-the-guild.jpg" height="40" alt="europa-1400-the-guild"></a> | [Europa 1400: The Guild - Gold Edition (via Proton and gamescope)](https://lutris.net/games/europa-1400-the-guild/) | `proton` | `nix run github:kraftwerk-gaming/strom#europa-1400-the-guild` |
| <a href="https://lutris.net/games/frog-fractions/"><img src="https://lutris.net/games/banner/frog-fractions.jpg" height="40" alt="frog-fractions"></a> | [frog-fractions](https://lutris.net/games/frog-fractions/) | `native` | `nix run github:kraftwerk-gaming/strom#frog-fractions` |
| <a href="https://lutris.net/games/game-of-robot/"><img src="https://lutris.net/games/banner/game-of-robot.jpg" height="40" alt="game-of-robot"></a> | [The Game of Robot (1988, via DOSBox-X)](https://lutris.net/games/game-of-robot/) | `native` | `nix run github:kraftwerk-gaming/strom#game-of-robot` |
| <a href="https://lutris.net/games/half-life/"><img src="https://lutris.net/games/banner/half-life.jpg" height="40" alt="half-life"></a> | [Half-Life (WON 1.1.1.0, via Proton and gamescope)](https://lutris.net/games/half-life/) | `proton` | `nix run github:kraftwerk-gaming/strom#half-life` |
| <a href="https://lutris.net/games/heroes-of-might-and-magic-2-gold/"><img src="https://lutris.net/games/banner/heroes-of-might-and-magic-2-gold.jpg" height="40" alt="heroes-of-might-and-magic-2-gold"></a> | [Heroes of Might & Magic II Gold (via fheroes2)](https://lutris.net/games/heroes-of-might-and-magic-2-gold/) | `native` | `nix run github:kraftwerk-gaming/strom#heroes-of-might-and-magic-2-gold` |
| <a href="https://lutris.net/games/jazz-jackrabbit-2/"><img src="https://lutris.net/games/banner/jazz-jackrabbit-2.jpg" height="40" alt="jazz-jackrabbit-2"></a> | [Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)](https://lutris.net/games/jazz-jackrabbit-2/) | `native` | `nix run github:kraftwerk-gaming/strom#jazz-jackrabbit-2` |
| <a href="https://lutris.net/games/legacy-of-kain-soul-reaver/"><img src="https://lutris.net/games/banner/legacy-of-kain-soul-reaver.jpg" height="40" alt="legacy-of-kain-soul-reaver"></a> | [Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope)](https://lutris.net/games/legacy-of-kain-soul-reaver/) | `proton` | `nix run github:kraftwerk-gaming/strom#legacy-of-kain-soul-reaver` |
| <a href="https://lutris.net/games/lemmings/"><img src="https://lutris.net/games/banner/lemmings.jpg" height="40" alt="lemmings"></a> | [Lemmings (DOS CD version with CD audio, via DOSBox-X)](https://lutris.net/games/lemmings/) | `native` | `nix run github:kraftwerk-gaming/strom#lemmings` |
| <a href="https://lutris.net/games/lemmings-95/"><img src="https://lutris.net/games/banner/lemmings-95.jpg" height="40" alt="lemmings-95"></a> | [Lemmings 95 (Windows 95 version via Wine)](https://lutris.net/games/lemmings-95/) | `native` | `nix run github:kraftwerk-gaming/strom#lemmings-95` |
| <a href="https://lutris.net/games/need-for-speed-underground-2/"><img src="https://lutris.net/games/banner/need-for-speed-underground-2.jpg" height="40" alt="need-for-speed-underground-2"></a> | [Need for Speed: Underground 2 (via Proton and gamescope)](https://lutris.net/games/need-for-speed-underground-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#need-for-speed-underground-2` |
| <a href="https://lutris.net/games/shadow-of-the-colossus/"><img src="https://lutris.net/games/banner/shadow-of-the-colossus.jpg" height="40" alt="shadow-of-the-colossus"></a> | [Shadow of the Colossus (via PCSX2)](https://lutris.net/games/shadow-of-the-colossus/) | `pcsx2` | `nix run github:kraftwerk-gaming/strom#shadow-of-the-colossus` |
| <a href="https://lutris.net/games/starcraft/"><img src="https://lutris.net/games/banner/starcraft.jpg" height="40" alt="starcraft"></a> | [StarCraft + Brood War (via Proton and gamescope)](https://lutris.net/games/starcraft/) | `proton` | `nix run github:kraftwerk-gaming/strom#starcraft` |
| <a href="https://lutris.net/games/stronghold-hd/"><img src="https://lutris.net/games/banner/stronghold-hd.jpg" height="40" alt="stronghold-hd"></a> | [Stronghold HD (via Proton and gamescope)](https://lutris.net/games/stronghold-hd/) | `proton` | `nix run github:kraftwerk-gaming/strom#stronghold-hd` |
| <a href="https://lutris.net/games/syndicate/"><img src="https://lutris.net/games/banner/syndicate.jpg" height="40" alt="syndicate"></a> | [Syndicate (via FreeSynd engine)](https://lutris.net/games/syndicate/) | `native` | `nix run github:kraftwerk-gaming/strom#syndicate` |
| <a href="https://lutris.net/games/the-settlers-ii-gold-edition/"><img src="https://lutris.net/games/banner/the-settlers-ii-gold-edition.jpg" height="40" alt="the-settlers-ii-gold-edition"></a> | [The Settlers II Gold (via Return to the Roots)](https://lutris.net/games/the-settlers-ii-gold-edition/) | `native` | `nix run github:kraftwerk-gaming/strom#the-settlers-ii-gold-edition` |
| <a href="https://lutris.net/games/the-typing-of-the-dead/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead.jpg" height="40" alt="the-typing-of-the-dead"></a> | [The Typing of the Dead (2001 PC port, via Proton and gamescope)](https://lutris.net/games/the-typing-of-the-dead/) | `proton` | `nix run github:kraftwerk-gaming/strom#the-typing-of-the-dead` |
| <a href="https://lutris.net/games/the-typing-of-the-dead-overkill/"><img src="https://lutris.net/games/banner/the-typing-of-the-dead-overkill.jpg" height="40" alt="the-typing-of-the-dead-overkill"></a> | [The Typing of the Dead: Overkill (Steam, via Proton and gamescope)](https://lutris.net/games/the-typing-of-the-dead-overkill/) | `proton` | `nix run github:kraftwerk-gaming/strom#the-typing-of-the-dead-overkill` |
| <a href="https://lutris.net/games/theme-hospital/"><img src="https://lutris.net/games/banner/theme-hospital.jpg" height="40" alt="theme-hospital"></a> | [Theme Hospital (via CorsixTH engine)](https://lutris.net/games/theme-hospital/) | `native` | `nix run github:kraftwerk-gaming/strom#theme-hospital` |
| <a href="https://lutris.net/games/thief-2/"><img src="https://lutris.net/games/banner/thief-2.jpg" height="40" alt="thief-2"></a> | [Thief II: The Metal Age (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-2/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-2` |
| <a href="https://lutris.net/games/thief-gold/"><img src="https://lutris.net/games/banner/thief-gold.jpg" height="40" alt="thief-gold"></a> | [Thief Gold with TFix (NewDark engine, via Proton and gamescope)](https://lutris.net/games/thief-gold/) | `proton` | `nix run github:kraftwerk-gaming/strom#thief-gold` |
| <a href="https://lutris.net/games/unreal-tournament-2004/"><img src="https://lutris.net/games/banner/unreal-tournament-2004.jpg" height="40" alt="unreal-tournament-2004"></a> | [Unreal Tournament 2004 (OldUnreal native Linux)](https://lutris.net/games/unreal-tournament-2004/) | `native` | `nix run github:kraftwerk-gaming/strom#unreal-tournament-2004` |
| <a href="https://lutris.net/games/untitled-goose-game/"><img src="https://lutris.net/games/banner/untitled-goose-game.jpg" height="40" alt="untitled-goose-game"></a> | [Untitled Goose Game (via Proton and gamescope)](https://lutris.net/games/untitled-goose-game/) | `proton` | `nix run github:kraftwerk-gaming/strom#untitled-goose-game` |
| <a href="https://lutris.net/games/warcraft-iii-the-frozen-throne/"><img src="https://lutris.net/games/banner/warcraft-iii-the-frozen-throne.jpg" height="40" alt="warcraft-iii-the-frozen-throne"></a> | [Warcraft III: Reign of Chaos + The Frozen Throne v1.26a (via Proton)](https://lutris.net/games/warcraft-iii-the-frozen-throne/) | `proton` | `nix run github:kraftwerk-gaming/strom#warcraft-iii-the-frozen-throne` |
| <a href="https://lutris.net/games/worms-wmd/"><img src="https://lutris.net/games/banner/worms-wmd.jpg" height="40" alt="worms-wmd"></a> | [Worms W.M.D (GOG build, via Proton and gamescope)](https://lutris.net/games/worms-wmd/) | `proton` | `nix run github:kraftwerk-gaming/strom#worms-wmd` |
| <a href="https://lutris.net/games/xenogears/"><img src="https://lutris.net/games/banner/xenogears.jpg" height="40" alt="xenogears"></a> | [Xenogears (via RetroArch / SwanStation)](https://lutris.net/games/xenogears/) | `retroarch` | `nix run github:kraftwerk-gaming/strom#xenogears` |

_38 games_

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

Use `--nocopy` (which implies `--raw-leaves`) to avoid duplicating multi-GB
files into the blockstore. All CIDs in this repo use this mode. A plain
`ipfs add` without `--raw-leaves` produces a **different CID** for the same
file -- do not use it.

Example: adding The Typing of the Dead: Overkill (7.4 GB):

```bash
# place the file somewhere the ipfs user can read (important!)
# if you have file share set up between daemons, ensure that ipfs
# is in a common group (e.g. "download")

# add to IPFS (as the ipfs user, since the daemon owns the repo)
sudo -u ipfs ipfs add --nocopy --progress \
  '/media/download/torrents/The.Typing.of.the.Dead.Overkill.7z'
# output: added QmZPyB... The.Typing.of.the.Dead.Overkill.7z
```

Note the CID from the output (`QmZPyBk...` in this case). `--nocopy` means
the blockstore references the file at its current path -- do not move or
delete it while it is pinned.

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
