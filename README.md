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

## Web GUI

A Steam-like web catalog with clickable tiles, per-game detail pages (hero
art, screenshots, description, genre/year/developer), and a launch progress
bar:

```bash
nix run github:kraftwerk-gaming/strom#gui
```

This serves the static catalog on `127.0.0.1:8731` (override with
`STROM_GUI_PORT`) and opens it in your browser. Clicking **Play** navigates to
`strom://<slug>`, which the XDG scheme handler (`strom-launch`) turns into
`nix run`. Because the heavy IPFS asset download happens at the Nix layer, the
real download/build progress bar is shown in a native launcher window (zenity,
falling back to desktop notifications), not in the browser.

The catalog is per-game metadata: each game may have a `steam.json` (Steam-
enriched fields, written by `scripts/fetch-steam-metadata.py`) and/or a
`metadata.json` (hand-maintained). The GUI and couch launcher assemble these
into one catalog at build time via `scripts/assemble-catalog.py`; there is no
committed `catalog.json`. Games without a Steam match fall back to their lutris
banner so every game still gets a tile.

The grid is browsable Steam-style: a search box plus a filter sidebar with
Runtime, Genre and Features (Single-player, Local multiplayer, Local co-op,
Remote Play Together, …) facets. Selections are OR'd within a group and AND'd
across groups.

### Manual metadata for non-Steam games

Steam matching is automatic, but ~1/3 of games are not on Steam (GOG, fan
ports, abandonware). To give those, or any game whose Steam data is wrong,
proper genres, screenshots, player-mode tags, etc., drop a `metadata.json` next
to the game's `default.nix`:

```jsonc
// games/battlefield-2/metadata.json
{
  "genres": ["Action", "FPS"],
  "tags": ["Multi-player", "Online Co-op", "LAN Co-op"],
  "year": 2005,
  "developers": ["Digital Illusions CE"],
  "long": "Large-scale modern-combat warfare across land, sea and air ...",
  "hero": "https://.../banner.jpg",
  "screenshots": ["https://.../1.jpg", "https://.../2.jpg"]
}
```

Games with no Steam match are flagged in the GUI with a **community** badge
(on the tile and detail page) and a **Metadata** filter (Steam vs Community),
making clear which entries are hand-curated rather than pulled from Steam.

For a Steam game, `metadata.json` holds only the corrected fields, overlaid
**over** its `steam.json` (lists replace, they don't append); for an off-Steam
game it is the whole entry. Recognized fields: `name`, `short`, `long`,
`genres`, `tags`, `year`, `developers`, `hero`, `screenshots`, `lutris`. The
exact `tags` strings that map to each Features filter are documented in
[AGENTS.md](AGENTS.md). To control Steam matching itself, set `"appid"` in
`metadata.json` (an integer forces an appid, `null` skips Steam).

### NixOS integration

Register the `strom://` handler and install the GUI system-wide via the
provided module:

```nix
# flake.nix inputs: strom.url = "github:kraftwerk-gaming/strom";
{
  imports = [ strom.nixosModules.strom-desktop ];
  programs.strom-desktop.enable = true;
  # For a local checkout, point the launcher at it:
  # programs.strom-desktop.flake = "path:/home/you/strom";
}
```

Or wire it by hand without the module:

```nix
{ pkgs, strom, ... }:
let s = strom.legacyPackages.${pkgs.system}.scripts;
in {
  environment.systemPackages = [ s.gui s.strom-launch ];
  xdg.mime.defaultApplications."x-scheme-handler/strom" = "strom-launch.desktop";
}
```

## Cloning via Radicle

This repo is also hosted on [Radicle](https://radicle.xyz/). To clone via
the Radicle p2p network:

```bash
rad clone rad:zaCSBVa8UbKNEWBcmRTW1m9fZXhu
```

## Games

The game list is not committed to this file. Browse the full catalog on the
live **[game & IPFS status page](https://iris.radicle.xyz/raw/rad:zaCSBVa8UbKNEWBcmRTW1m9fZXhu/head/web/index.html)**,
served straight from a Radicle node: it builds the list at runtime from this
repo, so it is always current. Locally, `nix run .#gui` opens the same catalog
in a Steam-style browser.

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
3. Run `python3 scripts/sync-metadata.py` to write the game's build keys
   (`cids`/`description`/`runtime`) into `games/<slug>/metadata.json`
4. Run `python3 scripts/fetch-steam-metadata.py <slug>` so the game gets a
   `steam.json` (and thus a GUI/launcher tile). If it is not on Steam, add a
   `games/<slug>/metadata.json` with manual metadata (see
   [Web GUI metadata](#manual-metadata-for-non-steam-games)); for a wrong Steam
   match, set `"appid"` in that `metadata.json` (integer to pin, `null` to skip).
