# Strom on Android

Decision record. Read this before writing any Android code in this repo.

## The answer

**One general Strom APK that fetches games at runtime. Not one APK per game.**

The Strom APK is a *store front*, not a runtime: it browses the catalog,
fetches game payloads by CID, verifies them, and hands each game to an
already-installed runtime app over a documented intent. It does not
contain Wine, Box64, DXVK, Turnip, a glibc rootfs or an emulator core,
and it never `execve`s anything.

Per-game APKs survive only as a narrow seam (`android.outputs.apk`) for
games that have a genuine self-contained Android build. Today that is
exactly one game: `games/balatro/apk.nix`, a LOVE title repackaged by
`balatromobile`. That is not a path the catalog at large can take.

## Why not one APK per game

This was tried. The `wip/android` branch is 43 commits of it:
`pkgs/wine-glibc-rootfs`, `pkgs/box64`, `pkgs/fex-android`,
`pkgs/termux-x11`, `pkgs/libandroid-sysvshm-stub`,
`lib/android/build-android-apk.nix`, a 532-line Java `MainActivity` that
extracts a rootfs on first run, plus two binary-patch scripts for
wineserver's hardcoded Winlator paths. It produced a 2.4 GB APK for
`need-for-speed-underground-2` (1.5 GB of game plus ~700 MB of
framework) and never rendered a frame. Its own pivot commit (`a737b7a`)
states the reason: no prebuilt Wine fork ships the GLX-to-EGL plus
`xlib_surface`-to-`android_surface` patches that Lorie plus Mali needs,
and the Box64/FEX alternative means shipping a 754 MB glibc imagefs and
a proot-style sandbox. Multi-week projects, both.

The structural problems on top of that:

- The runtime is 160 to 185 MB compressed *per APK*, duplicated across
  every game, with no shared component cache and no shared wineprefix.
- Installing an APK copies it into `/data/app` and then the launcher
  extracts assets, so the payload costs roughly double on the internal
  partition, which is the small one.
- Executing a downloaded binary from the app home directory requires
  `targetSdk <= 28` (see the SELinux constraint below). Every project in
  this space is pinned there: Winlator 11.1, GameNative's main flavors,
  Termux 0.118.3. Strom does not need that pin *because it does not
  execute anything* - but a self-contained per-game APK would.
- No update path. A wine or DXVK fix means rebuilding and redistributing
  every game.
- GameNative's Android 15 exec workaround, its Steam bootstrap and its
  KGSL shim are three deliberately closed-source binaries
  (`libredirect.so`, `libsteambootstrap.so`, `libkgslshim.so`;
  `THIRD_PARTY_NOTICES` says outright that they are closed to make
  rebranded forks fail). We cannot redistribute them, so a fork inherits
  a degraded runtime.

Fetching content at runtime is also simply what every runtime in this
space already does: GameNative downloads a 159 MiB `imagefs` plus DXVK,
Turnip and Proton components from its own CDN on first launch. Strom
doing the same over IPFS is the same shape, not a new one.

## Backend mapping and coverage

`runtime` in a game's `default.nix` selects the Android backend
(`lib/android/default.nix`, `backendFor`):

| runtime     | games | backend       | how it reaches the device                                 |
| ----------- | ----- | ------------- | --------------------------------------------------------- |
| `proton`    |   269 | `gamenative`  | `app.gamenative.LAUNCH_GAME` as a CUSTOM_GAME             |
| `retroarch` |    64 | `retroarch`   | `CoreSideloadActivity` then `RetroActivityFuture`         |
| `dolphin`   |     6 | `dolphin`     | `dolphinemu://app/play/...`, user adds the folder once    |
| `azahar`    |     1 | `azahar`      | `ACTION_VIEW` + `SelectedGame` as a `!`-prefixed path     |
| `pcsx2`     |     9 | `unsupported` | no redistributable Android PS2 emulator exists            |
| `native`    |    76 | `unsupported` | Linux x86_64 ELF, no runtime app will launch one          |
| `custom`    |    40 | `unsupported` | per-game shell scripts, port individually                 |

340 of 465 games (73 percent) map onto a backend. The `unsupported`
entries carry a `reason` string in the manifest so the client explains
itself instead of hiding the game.

Runtime apps, all arm64-v8a:

- **GameNative** `app.gamenative` v1.1.1, GPL-3.0,
  `github.com/utkarshdalal/GameNative`. Wine 9.2 plus Proton 9.0/10.0
  patterns, Box64 0.4.2 and FEXCore 2605 (FEXCore is the default), DXVK
  2.6.1-gplasync, VKD3D 2.14.1, Turnip 25.2.0, Vortek 2.1 as the default
  graphics driver, PulseAudio 13, all inside proot. Sideload only.
- **RetroArch** `com.retroarch`, GPL-3.0, on F-Droid. The only backend
  we can drive end to end with no manual step.
- **Dolphin** `org.dolphinemu.dolphinemu`, GPLv2+, on F-Droid.
- **WatermelonDS** `me.magnum.melondualds`, GPLv3, a melonDS port that
  drives two physical panels. Used for every DS game, not only on
  dual-screen hardware.
- **Azahar** `org.azahar_emu.azahar`, GPL-2.0, `azahar-emu/azahar`. 3DS.
  Pin the vanilla artifact; the Play flavour has a different id and cannot
  open a `content:` URI. Two of its settings are private preferences the
  client cannot reach, so its setup message names them.

Not usable, for the record: Winlator itself exports no launch interface
at all (only `MainActivity` MAIN/LAUNCHER). GameHub is
`com.xiaoji.egggame` by GameSir/XiaoJi, closed source with no published
license and a vendor-coupled component backend, so it cannot be forked
or reliably targeted. DuckStation relicensed to CC BY-NC-ND 4.0.
AetherSX2 is discontinued and NetherSX2 is an unlicensed patch of it.

## Workflow

### One-time setup

1. Sideload the Strom APK (direct APK, our own F-Droid-style repo, or
   Obtainium). Play Store is unreachable, see below.
2. Strom creates `/storage/emulated/0/Download/Strom/{games,cores}/`.
   **It asks for no storage permission to do so.** The location is
   forced: the payload has to be somewhere the runtime apps can read,
   `Android/data/<pkg>/` is unreadable by other apps on API 30+, and
   arbitrary shared storage would cost an All-Files grant. Public
   `Downloads` is the one place a permissionless writer and a
   legacy-storage reader meet. Measured; see the table under RetroArch.
3. Strom checks which runtime apps are present. It cannot install them
   silently, so a missing one is a link plus a one-line explanation of
   what it unlocks ("RetroArch: 64 games", "GameNative: 269 games").
   Package visibility on API 30+ requires a `<queries>` block in our
   manifest naming `com.retroarch`, `app.gamenative` and
   `org.dolphinemu.dolphinemu`; without it `PackageManager` pretends
   they do not exist and our intents will not resolve.

### Pokemon Blue: retroarch backend, no manual step

1. Tap Install. Strom fetches `pokemon-blue-android.zip` (380 KiB)
   across the gateway pool, checks it against the `sha256` in the
   manifest, and unzips to
   `/storage/emulated/0/Download/Strom/games/pokemon-blue/pokemon-blue.gb`.
2. Tap Play. Strom checks its own record of which cores it has already
   fetched (RetroArch has no queryable API for this - see below), does
   not find `gambatte_libretro_android.so`, so downloads
   `.../arm64-v8a/gambatte_libretro_android.so.zip` from the libretro
   buildbot, unzips it to `Download/Strom/cores/`, and starts
   `com.retroarch/.browser.debug.CoreSideloadActivity` with
   `LIBRETRO` = that path and `ROM` = the `.gb`. RetroArch copies the
   core into its own `dataDir/cores/` and launches the game in the same
   step.
3. Every later launch is the **same single intent**. We do not switch to
   `RetroActivityFuture` directly: `CoreSideloadActivity` computes
   `CONFIGFILE` via `UserPreferences.getDefaultConfigPath`, which reads
   RetroArch's own private SharedPreferences (`global_config_enable`,
   `libretro_path`), so we cannot reproduce it. Re-sending the sideload
   intent re-copies the core (1-23 MB) and gets every extra right.

That is the whole flow. No folder picking, no per-game grant.

### need-for-speed-underground-2: gamenative backend, parent mode

Setup happens **once, ever** - not once per game.

0. First GameNative game only: Strom sends the user to GameNative's
   add-game-folder picker to select `/storage/emulated/0/Download/Strom/games`
   (the parent). GameNative stores that raw path in its private
   `customGameManualFolders` setting, which is the whole reason the step
   exists; there is no intent that writes to it. Strom also writes
   `.gamenative` = `{"appId": <crc32 of "strom-games">}` there so the id
   is stable.
1. Tap Install. Strom fetches
   `need-for-speed-underground-2-android.zip`, verifies the sha256, and
   unzips to
   `/storage/emulated/0/Download/Strom/games/need-for-speed-underground-2/`.
2. Tap Play. Strom sends `app.gamenative.LAUNCH_GAME` with the parent's
   `app_id`, `game_source = "CUSTOM_GAME"`, and `container_config`
   carrying (a) `drives` with `A:` pointed at
   `Strom/games/need-for-speed-underground-2` and (b) the rest of the
   game's manifest config (`execArgs`, `screenSize`, `dxwrapper`, and
   whatever the recipe overrides).
3. GameNative symlinks `A:` onto that folder
   (`WineUtils.createDosdevicesSymlinks`), and
   `CustomGameScanner.getLaunchExecutable` finds `SPEED2.EXE` because it
   is the only depth-2 `.exe` in the folder. It runs `A:\SPEED2.EXE` in
   place - no copy into the container.
4. On the very first GameNative launch it also pulls its own
   `imagefs_gamenative.txz` (159 MiB) plus a Wine patch archive behind
   its own progress dialog. Strom warns about that before handing off,
   because otherwise it looks like our download stalled.

Note what step 2 does *not* send: `executablePath`. That omission is
load-bearing, see the GameNative contract below.

Per-game graphics tuning stays in the repo, not in the app: a game that
needs `d8vk`, `cnc-ddraw` or a `turnip` driver instead of the Vortek
default sets it in `android.containerConfig` in its `default.nix`, the
same way it already sets `gamescope.flags` for the desktop.

### What the intent-dispatch design cannot do

- Install a runtime app silently. Android has no silent-install API for
  a non-privileged app. It *can* drive a `PackageInstaller` session so
  the user only taps Confirm.
- Push libretro core options *while RetroArch is the runtime*. There is
  no per-launch extra; `retroarch-core-options.cfg` lives in RetroArch's
  own config dir. A game whose desktop recipe depends on a non-default
  core option (the melonDS screen-layout and touch-mode games) will
  behave differently. The manifest carries `coreOptions` so the client
  can at least display what to set. This is the single strongest
  argument for embedding the cores instead (Stage 4), where options are
  programmatic.
- Register a GameNative folder, or add an ISO path to Dolphin's
  `Dolphin.ini` (both live in app-private storage).

## Hard platform constraints

These are the facts that shape the design. Sources are AOSP, the Android
docs and upstream repos; the one local measurement is called out.

**External storage is `noexec`, and that blocks more than `execve`.**
`system/vold/Utils.cpp` mounts the emulated-storage FUSE filesystem with
`MS_NOSUID | MS_NODEV | MS_NOEXEC | MS_NOATIME | MS_LAZYTIME`, so all of
`/storage/emulated/0/**` - including `Android/data/<pkg>/files` - is
noexec. Measured locally (`unshare -Urm`, tmpfs mounted `-o noexec`):
`mmap(PROT_READ|PROT_EXEC, MAP_PRIVATE, fd)` of a file on a noexec mount
fails with `EPERM`, while the identical call on a normal mount succeeds.
So a noexec mount also refuses executable *file mappings*, which is what
a PE or ELF loader does.

[INFERENCE] This is survivable for us because the code in a `proton`
payload is x86: Box64/FEX read the guest image and JIT into their own
anonymous mappings, so the guest pages never need host `PROT_EXEC`.
GameNative's own default CustomGames root lives on that same noexec FUSE
mount, which is evidence it works in practice. Confirming it on a real
device is the first item on the device-test list. A *native arm64*
binary on external storage would be impossible, full stop.

**`execve` from the app home directory needs `targetSdk <= 28`.**
`system/sepolicy/private/untrusted_app_27.te` grants
`app_data_file:file execute_no_trans`; `untrusted_app_all.te` grants only
`{ r_file_perms execute }` (that is dlopen, not execve). The documented
escape hatch, also in `untrusted_app_all.te`, is
`system_linker_exec:file execute_no_trans`, i.e. invoking
`/system/bin/linker64 <binary>`. Strom itself needs none of this. It is
the reason the runtime apps are pinned at `targetSdk 28` and the reason
they are sideload-only.

**A libretro core cannot be dlopened from external storage.** Hence
RetroArch's exported `CoreSideloadActivity`, which copies a `.so` from
anywhere it can read into its own `dataDir/cores/` and then launches it.
That is our core-install mechanism; RetroArch's in-app core downloader
has no intent.

**There is no embeddable IPFS node for Android.**
`ipfs-shipyard/gomobile-ipfs` is archived (unmodified since 2023).
`kubo` publishes no android artifact (`dist.json` lists darwin, freebsd,
linux, openbsd, windows). `iroh` addresses content by BLAKE3, not by
CID, and `iroh-blobs` is explicitly out of scope for its Kotlin binding,
so it cannot fetch a public IPFS CID at all. Every Rust IPFS node
implementation is archived. There is no maintained JVM library for CAR
parsing or UnixFS DAG assembly.

**Gateways do work.** Verified live on 2026-08-04 against `ipfs.io`,
`dweb.link`, `w3s.link` and `trustless-gateway.link`: `?format=raw` with
a `Range` header returns `206` with `content-range`, and CAR requests
return `200 application/vnd.ipld.car; version=1; order=dfs; dups=n`.
`ipfs.io`, `dweb.link` and `w3s.link` answer with a `301` to a subdomain
first, so the client must follow redirects.

**Long downloads need a foreground service and must be resumable.** A
`WorkManager` `Worker` is stopped after ten minutes. A foreground
service of type `dataSync` (plus `FOREGROUND_SERVICE_DATA_SYNC`) is
mandatory for `targetSdk >= 34`, and on `targetSdk >= 35` all of an
app's `dataSync` services share a 6 hour budget per 24 hours, after
which `Service.onTimeout` fires and a restart throws
`ForegroundServiceStartNotAllowedException`. The budget resets when the
user foregrounds the app. A 30 GB game on a slow link will not finish in
one stretch, so the fetcher must resume at chunk granularity across app
sessions.

**Play Store is out, but no longer for the permission reason.** An
earlier draft of this document said Strom itself would need
`MANAGE_EXTERNAL_STORAGE`, which is restricted to file managers, backup
and anti-virus and would sink a Play listing on its own. Measurement
removed that: routing the payload through public `Downloads` means Strom
holds no storage permission at all. What still rules Play out is the
dependency graph, not us - GameNative ships proprietary Microsoft DLLs
and a self-updater and is sideload-only, and a launcher whose entire
function is fetching game images users supply themselves is not a
listing anyone should attempt. Distribution is sideload, same as every
runtime app it talks to. The permission finding still matters: it is one
fewer scary Settings trip during onboarding.

## Artifact model: add a derived payload, keep pinning the originals

A game's `src` is a source archive and its `buildScript` is arbitrary
Nix and shell: `innoextract`, `7zz`, `unar`, `patchelf`, merging GOG's
`__support` tree over the install root, baking a wineprefix with
winetricks. None of that can run on a phone. So Android does not fetch
`cids`; it fetches a **new artifact per game: a zip of the built
`_gameData` tree**, which is exactly what the desktop overlay lowers.

`outputs.payload` builds it. Deterministic: every mtime pinned to the
zip epoch, `zip -X` to strip extra fields, entry names fed in `LC_ALL=C`
order. Verified with `nix build --rebuild`.

Zip rather than tar.zst because `java.util.zip` is in the Android
platform - no native dependency to ship, and `ZipFile` gives per-entry
random access so an interrupted extraction resumes. Deflate on
already-compressed game assets costs little against zstd.

Verification is by the artifact's **sha256**, which the repo already has
for every FOD. That sidesteps the missing JVM CAR/UnixFS verifier
entirely: gateways are an untrusted transport, and the payload is
end-to-end verified against a hash committed in this repo. Stronger than
trusting the gateway's CID resolution.

Publishing follows the same discipline as a game's `src` (AGENTS.md,
"IPFS pinning only after testing"): build the payload, test the game on
a device, pin, then wire the result back as `android.data = fetchIpfs
{ ... }`. Until that happens the manifest reports `payload = null` and
the client lists the game as not yet available on Android. Do not pin
multi-GB Android payloads for games nobody has run on a phone.

### Superseded: keeping the originals as the only pinned artifact

Kept for the reasoning, but overtaken by the plan of record below. The
argument was that the derived payload should be purely **additive** and
the originals (CD/DVD images, GOG installers, repack archives) stay the
canonical artifact, for five reasons:

1. **Provenance.** The pinned original is the bytes you can verify
   against something outside this repo. The Explorers of Time recipe
   (`games/pokemon-mystery-dungeon-explorers-of-time`) checks CRC32,
   MD5 and SHA-1 against
   libretro-database's No-Intro DAT and names two independent
   archive.org items serving the identical TorrentZip. A tree we
   extracted ourselves has no external hash to check against and no
   second source. That chain is the repo's audit trail.
2. **Lifecycle.** Original bytes never change. A derived tree's hash
   changes with every `buildScript` edit - AGENTS.md already records
   that rebasing a stage branch can change a `<slug>-data` hash. If the
   tree were the only pinned copy, every recipe tweak would orphan a
   multi-GB pin and require a re-upload. This is the objection the
   single-artifact proposal below answers, by moving the churn (mods,
   patches, fixes) out of the pinned layer and into local ones.
3. **`fallbackUrl` only exists for originals.** The non-IPFS escape
   hatch AGENTS.md insists on points at archive.org, GOG or a
   publisher CDN. Nobody mirrors our extracted tree, ever.
4. **Desktop regression.** The desktop can extract locally, so fetching
   a prebuilt tree buys it nothing on its own. Weak once the tree is
   shared - see the single-artifact proposal below, which turns this from
   a cost into "extract once centrally instead of on every machine".
5. **A zip dedups nothing.** Pinning trees is sometimes argued for on
   cross-game deduplication (shared redists, engine DLLs). A single zip
   blob gets none of that. If dedup ever becomes the goal the move is a
   UnixFS *directory* plus a per-file sha256 side manifest, not a zip -
   and the price is thousands of gateway requests per install instead of
   one ranged fetch.

Zipping 5.7 GiB of trees took 334 s on this machine, about 17 MB/s, which
is a real but tolerable build cost. Sizes are measured below.

### Measured cost of pinning both

Seven games, original (gateway `Content-Length` on the pinned CID) versus
built payload zip:

| game | original | payload | ratio |
| ---- | -------- | ------- | ----- |
| final-fantasy-viii | 2696 M | 3213 M | 1.19x |
| need-for-speed-underground-2 | 1841 M | 2057 M | 1.12x |
| max-payne | 702 M | 624 M | 0.89x |
| half-life | 311 M | 311 M | 1.00x |
| risk-of-rain | 65 M | 77 M | 1.18x |
| animal-well | 31 M | 31 M | 0.98x |
| pokemon-blue | 1.0 M | 0.36 M | 0.36x |
| total | 3806 M | 4256 M | **1.12x** |

Deflate over an installed tree lands close to a compressed installer;
`max-payne`'s payload is smaller than its own installer. So pinning both
is **2.12x** the current footprint for a game. Retract an earlier claim
here: "the desktop would fetch more bytes" was made against an assumed
1.19x and the real figure is 1.12x, so bandwidth is a weak argument
either way.

### Plan of record: pin installed worktrees, not installation media

Stop pinning installers and archives. Pin the **installed worktree** -- the
extracted, normalised game directory -- and have desktop and Android both
consume it. Mods are more worktrees, stacked the same way. This is not an
Android-specific artifact; it becomes *the* build product, and
`outputs.payload` stops being an Android output and becomes the thing
`_gameData` is fetched from.

**Implemented, in part.** `outputs.payload` now builds the merged
worktree as a directory rather than a zip, which is what the client can
actually consume: it fetches a CAR and verifies the DAG, so it
reconstructs a UnixFS tree and has no archive reader. The operator pins
it with `ipfs add -r --raw-leaves` and puts the resulting directory CID
in `android.data`. The remaining half of the plan -- making `_gameData`
itself fetch that pinned tree, so the desktop stops extracting too -- is
not done.

Verified on device that a directory payload round-trips: pointed a
catalog entry at a known public UnixFS directory, and the client fetched
it, verified every block, wrote all six files, and resolved the launch
target named in the manifest from inside the tree. So a multi-disc game
needs no new mechanism -- its `.chd` files sit beside the `.m3u` that
lists them, and a single-file ROM is the degenerate case of the same
shape. What multi-disc still lacks is the BIOS, which is a placement
problem rather than a payload-shape one (see the storage table below).

Consequences, in order of importance:

1. **Extraction leaves the user's machine entirely, on both platforms.**
   The 269 proton recipes declare 22 distinct build tools -- `innoextract`
   (92 games), `unzip` (96), `p7zip` (73), `unar` (57), `cabextract` (20),
   `gnutar` (17), `python3` (13), `zstd` (12), `libarchive` (8), `7zz`
   (7), `unshield` (6), `mono` (5), `bchunk` (4), `binutils` (3),
   `wine-wow64` (2), `mingw32-gcc`, `unarc`, `msitools`, `ffmpeg`. All of
   it becomes packager-side. A desktop install becomes fetch-and-unpack,
   and the Android client needs no archive tooling beyond
   `java.util.zip`. This is the argument that makes the whole thing
   uniform: there is one artifact kind and one code path.
2. **"Install a mod" is the same operation everywhere.** Desktop stacks
   worktrees as fuse-overlayfs lowers; Android extracts them in reverse
   priority order. Verified equivalent: the layers carry no whiteout
   entries (zero character/block/fifo/socket nodes across
   `ff8-music-orchestral`, `ff8-texturepack-spells`, the uplink mod
   tree), and a lower can only add a file or win a path conflict.
3. **Footprint.** Today's baseline is 1.0x (originals only, no Android).
   Pinning both would be 2.12x. Pinning worktrees only is **~1.12x** --
   so Android support costs 12% more storage rather than 112%.

The objection I had raised -- that recipe edits stop being free, because a
`buildScript` tweak orphans a multi-GB pin -- is real but much smaller
than I assumed. Measured over the full history of all 464 recipes: 61%
are never touched after landing; 686 post-landing edits exist in total,
and classifying each by whether it changes the tree:

| post-landing edit | count | |
| ----------------- | ----- | --- |
| comment / metadata only | 346 (50.4%) | free |
| runtime config only (`preRun`, `env`, gamescope, `saveLocations`, ...) | 177 (25.8%) | free |
| **build-affecting** | **163 (23.8%)** | **needs a re-pin** |

So ~24% of edits, 163 events across the project's entire history, would
have required re-uploading a tree. That is an operator bandwidth cost, not
an architectural problem, and it is bounded by how often extraction logic
actually changes.

Two real losses, and both want a per-bucket policy rather than a blanket
switch:

- **Provenance.** A No-Intro ROM zip can be checked against an external
  DAT; an extracted `.nds` cannot. That chain is worth keeping, and it is
  cheap to keep: ROM originals are ~30 MiB. So keep pinning originals for
  the `retroarch`/`dolphin` buckets and switch the big `proton` games,
  where the "original" is a scene repack with no authoritative hash
  anyway.
- **`fallbackUrl`.** Nobody mirrors our worktrees. Keep the original's URL
  in the recipe as documentation, which AGENTS.md already endorses ("the
  URL doubles as documentation").

And one modest regression: a mod shipping several pre-patched variants in
one archive gets cheaper under the media model. Ragnarok's two difficulty
variants are one 546 MiB RAR, versus two 340 MiB worktrees -- 1.24x. See
the variant measurements above; delta encoding is the fix if that pattern
spreads.

### Mods and user options: one artifact per layer

A moddable game must not become one payload per option combination. FF8
has 7 published settings (2 enums, 5 bools), so flattening would mean
something like 96 multi-GB artifacts. It does not have to, because the
recipes already express mods the right way.

`games/final-fantasy-viii` stacks every opt-in mod as its own overlay
lower above `_gameData` (`bwrap.overlay.lowers = lib.mkBefore (...)`,
with the comment "the base game is never re-extracted"). Measured:

| config | layers | sizes |
| ------ | ------ | ----- |
| default | 1 | 3707 MiB base |
| `music = "orchestral"` | 2 | base + **743 MiB** music pack |
| everything on | 13 | base + 12 packs, 24 to 758 MiB each |

So enabling the orchestral soundtrack on Android is: fetch one extra
743 MiB zip and unzip it over the game directory. The 3.7 GiB base is
pinned once and never re-fetched, and each mod layer is pinned once,
independently of every other combination.

**Why unzip-in-order is exactly equivalent to the overlay merge.** These
layers are all lowers, and a lower can only add a file or win a path
conflict - it can never delete one, because overlayfs whiteouts live in
the upper. Confirmed the layers contain no whiteout entries at all: zero
character, block, fifo or socket nodes in `ff8-music-orchestral`,
`ff8-texturepack-spells` or the uplink mod tree. So extracting layers
lowest-priority-first reproduces the desktop's merged view byte for byte.
`lowers` is ordered first = highest priority, hence the `reverseList`.

What this means for the current outputs:

- `outputs.payload` flattens the lowers of the **default** config, which
  is right for both cases: `half-life-uplink`'s mod tree is an
  unconditional lower and belongs in the base, while FF8's are
  conditional and correctly stay out of it.
- **Still missing**: a per-optional-layer artifact plus the settings
  mapping in the manifest. `passthru.settingsSchema` already carries the
  option list with labels, help text, kinds and defaults - the desktop
  launcher renders it today - so the Android options UI comes for free
  once the manifest carries it alongside a layer-name-to-setting-value
  map. Only `final-fantasy-viii` and `need-for-speed-underground-2`
  publish settings today, so this is not urgent, but it must exist before
  either of them is published for Android.
- One wrinkle for whoever builds it: the layer set is option-dependent,
  and some options only take effect when a parent is on (`ragnarokMode`
  is ignored unless `ragnarok` is set). Deriving the layer list by
  diffing `lowers` per setting therefore needs the parent enabled, or the
  recipe needs to declare its layers explicitly.

### Rejected: run the build on the phone

Tempting version of the same idea - ship the original and re-run the
`buildScript` on-device, perhaps under a "fake" Nix store that extracts
and then discards. Two separate findings, both negative.

**Nix cannot be embedded in an Android app.** `nix-on-droid`
(nix-community, MIT, active, last release line `release-24.05`) is the
only Nix-on-Android that exists, and it is a whole terminal-emulator APK
(`com.termux.nix`, a Termux fork), not a library: no `.so`, no `.aar`, no
headless binary, and its store paths are hardcoded to
`/data/data/com.termux.nix/files/usr`. It works by **proot** ptrace path
translation (`-b <installDir>/nix:/nix`), ships `sandbox = false`
unconditionally, is single-user with no daemon, and survives only by
pinning **targetSdk 28** - the same W^X exemption Termux and Winlator
rely on. The one cross-app hook is Termux's `RUN_COMMAND` service, which
needs a custom permission *and* the user hand-editing
`allow-external-apps=true` in `~/.termux/termux.properties` (default
`false`). Depending on it would mean: user installs a second terminal
app, grants a permission, edits a properties file, then waits through
proot's 2-10x syscall overhead - to produce bytes we could have handed
them pre-extracted. It also drags Strom back to `targetSdk 28`, which it
currently escapes precisely because it executes nothing.

**The tools, however, are available on-device** - which is the useful
half of the "fake store" instinct, and it needs no Nix.
`zhanghai/libarchive-android` (Apache-2.0, active, `libarchive` 3.8.8,
minSdk 21, on Maven Central) compiles readers for 7z **including the
zstd codec**, RAR4, RAR5, ZIP, ISO9660, tar and cab, with AES via
mbedcrypto. So every archive format this repo pins is decodable from
JNI. The gap is Inno Setup: there is no maintained `innoextract`
library for Android (only a 2.8-year-stale app port), so GOG installers
would need an NDK build of our own.

But this only matters if we ship originals. Under the single-artifact
proposal above the phone needs no archive tooling beyond
`java.util.zip`, so the two ideas are alternatives, not complements -
and layering is the simpler one.

## Manifest

`nix build .#androidManifests.<slug>`. Pure projection of the game's
`default.nix`; the schema is versioned by the `schema` field.

```json
{
  "schema": 1,
  "slug": "portal",
  "runtime": "proton",
  "backend": "gamenative",
  "payload": { "cid": "Qm...", "name": "portal-android.zip", "sha256": "sha256-..." },
  "gamenative": {
    "containerConfig": {
      "executablePath": "hl2.exe",
      "execArgs": "-game portal -steam",
      "screenSize": "1280x720",
      "dxwrapper": "dxvk"
    }
  }
}
```

`executablePath` is always present and always equals the game's
`executable`. Backend-specific shapes: `retroarch` carries
`{ core, rom, coreOptions }`, `dolphin` carries `{ disc }`,
`unsupported` carries `reason`. Per-game overrides are `android.backend`,
`android.retroarchCore`, `android.containerConfig`, `android.data`.

## Integration contracts

### GameNative (`gamenative`)

There is no SDK, no library and no plugin API. "Integration" is four
coupling points, and only the last one is something GameNative
advertises:

  1. one shared parent folder on public storage that both apps can read,
  2. a `.gamenative` file we write into it to fix its id,
  3. one registration of that parent folder, performed once ever by the
     *user* in GameNative's own UI,
  4. the `app.gamenative.LAUNCH_GAME` intent, which per launch moves the
     `A:` drive onto the game's own subfolder.

The mechanics, in the order they have to happen:

1. **Register the parent once.** `/storage/emulated/0/Download/Strom/games` must
   be in `PrefManager.customGameManualFolders`, a string list in
   GameNative's own private SharedPreferences. The user, inside
   GameNative, taps add-game-folder; that opens the Android system
   folder picker (`ActivityResultContracts.OpenDocumentTree`,
   `ui/components/CustomGameFolderPicker.kt`); `getPathFromTreeUri`
   converts the tree URI to a raw filesystem path (handling primary
   storage, SD cards and USB OTG mount points); and
   `LibraryViewModel.addCustomGameFolder` appends it. It persists until
   removed - a stored setting, not a per-launch grant.

   That list *is* the custom-game library:
   `CustomGameScanner.scanAsLibraryItems` iterates only
   `customGameManualFolders` and emits exactly one library item per
   stored path, with no recursion. Registering the parent therefore
   produces **one** library entry and **one** container shared by every
   game, which is what makes the step once-ever. We cannot do it for the
   user: the list is in another app's private SharedPreferences and
   nothing exported writes to it.

   Registration is also what makes the Steamworks-style layout work -
   `WineUtils.createDosdevicesSymlinks` only treats the `A:` path as the
   game directory when it is under `/Steam/steamapps/common/` or
   literally listed in `customGameManualFolders`.
2. Write `.gamenative` in the parent: `{"appId": <positive int>}`.
   `getOrGenerateGameId` returns a present, positive `appId` unchanged,
   so a deterministic id survives every rescan. Per-game `.gamenative`
   files are pointless in parent mode - there is one library entry.
3. Extract each payload to
   `/storage/emulated/0/Download/Strom/games/<slug>/`.
4. **Per launch, move the `A:` drive and send `executablePath`.** Send
   `drives` with `A:` pointed at the game's own subfolder;
   `ContainerUtils` re-asserts `A:` on every launch and
   `createDosdevicesSymlinks` rebuilds the dosdevices link, so the
   window is per launch. Send `executablePath` too, always, equal to the
   recipe's `executable`.

   **Why always send it.** `executable` is already the single source of
   truth for the launch target, and `getLaunchExecutable` prefers
   `container.executablePath` whenever that file exists relative to `A:`,
   falling back to its own scan otherwise. So sending it is strictly more
   robust than omitting it: right answer when the path is good, graceful
   degradation when it is not.

   The alternative - omit it and let
   `CustomGameScanner.findUniqueExeRelativeToFolder` rediscover it - was
   built and then removed. It collects `*.exe` (case-insensitive) from the
   folder root plus each immediate subdirectory, drops basenames starting
   with `unins`, deduplicates, and returns the single survivor. Three
   things killed it:

   - **It can launch the wrong binary.** Uniqueness is not correctness. A
     payload whose real target sits at depth 3 with a single stray
     `Patcher.exe` at depth 1 yields exactly one candidate, so a
     uniqueness check passes and the updater boots instead of the game.
     Reproduced against a synthetic tree before deleting the mechanism.
   - **It needs a per-game flag and a build-time scan**, both of which
     exist only to protect the optimisation, and it discards information
     the repo already has.
   - **Ambiguity is the common case anyway.** Of six real built trees,
     three cannot be auto-detected: `portal` (`Launcher.exe` + `hl2.exe`),
     `half-life` (nine, including Wise's `UNWISE.EXE`, which GameNative's
     `startsWith("unins")` filter does not catch) and
     `final-fantasy-viii` (nine). `animal-well`, `risk-of-rain` and
     `max-payne` are clean.

   **The cost we accept, and it is unmeasured.**
   `ContainerUtils.applyToContainer` calls `setNeedsUnpacking(true)`
   whenever `executablePath` differs from a non-empty stored value, and
   `needsUnpacking` makes the next boot run
   `wine msiexec /i wine-mono-11.0.0-x86.msi && wineserver -k` plus a
   redistributables pass behind an "Installing Mono..." splash. With one
   shared container and every game sending its own path, that plausibly
   fires on every game switch. **How slow that is has not been measured
   and is device test item 6.** If it turns out to hurt, the fix is
   per-game registration - separate containers, so no shared stored value
   to churn - not a heuristic that can boot the wrong exe.

   The other two `setNeedsUnpacking(true)` sites are
   `launchRealSteam`/`launchBionicSteam` changing and `unpackFiles`
   becoming true; we send none of those. So `wincomponents`,
   `dxwrapper`, `graphicsDriver`, `envVars`, `screenSize` and `execArgs`
   are all free to differ per game regardless.
5. Launch: `Intent("app.gamenative.LAUNCH_GAME")` with
   `app_id` (positive Int), `game_source = "CUSTOM_GAME"`, and
   `container_config` (JSON, max 50000 chars). The game runs **in
   place** off `A:`; nothing is copied into the container.

**What parent mode costs.** One wineprefix for every game, so
`drive_c/users/xuser/{Documents,AppData,...}` is shared and a game that
needs components baked into the prefix pollutes it for the others. That
is a real regression against the desktop, where each game gets its own
`~/.strom/.compatdata/<game>`; on the other hand it is exactly how an
ordinary Windows install behaves, different games write to different
vendor directories, and saves that land next to the binary stay in the
game's own folder on external storage. Per-game registration remains
available for anyone who wants isolation, at one picker trip per game.

Notes that constrain what we can express:

- `container_config` is a temporary in-memory override, restored
  afterwards. Merge semantics are "differs from the parse-time default
  wins", so a value cannot be forced *back* to a default over the
  intent (`showFPS = false` is indistinguishable from absent).
- Not settable over the intent even though `ContainerData` has them:
  `wineVersion`, `emulator` (Box64 versus FEX), `containerVariant`
  (glibc versus bionic), `fexcore*`, `graphicsDriverConfig`. Those are
  in-app settings only.
- `dxwrapperConfig` is stored as `"version=" + value`, so pass only the
  version string.
- The `drives` string has no separator: `"D:/path...E:/path...A:/path"`,
  parsed by scanning for `:`. Paths must not contain `:`. `D:` and `E:`
  are re-added automatically if missing; max 8 drive letters.
- `CUSTOM_GAME` needs no Steam login (`needsDeferLaunch` returns false
  for it). A never-logged-in install may still land on the login screen
  before consuming a pending launch request - unverified.
- The first launch of any game downloads `imagefs_gamenative.txz`
  (166,439,388 bytes, measured 2026-08-04) plus a Wine patch archive,
  behind GameNative's own progress dialog. Warn the user before the
  first handoff.
- Paths outside GameNative's own directories are gated on
  `Environment.isExternalStorageManager()`, so the user grants All-Files
  access to GameNative too.

**This is a source-derived contract, not a published API.** Only the
`LAUNCH_GAME` intent is advertised; the folder layout, the `.gamenative`
file format, the `A:` drive mapping and the `container_config` key set
were all established by reading GameNative 1.1.1's source, and any of
them can change without notice. Mitigations, in order of value: keep the
whole `containerConfig` data-driven from the manifest so a schema change
is a repo edit rather than an app release; check GameNative's
`versionCode` via `PackageManager` and refuse to hand off to an untested
version with a clear message instead of failing weirdly; and upstream an
`ADD_CUSTOM_GAME_FOLDER` intent so even the once-ever picker trip
disappears.

### RetroArch (`retroarch`)

No manual step per game, but two one-time preconditions and one intent.

**Preconditions, measured on an API 34 AVD.** Both reduce to a single
one-time user action: launch RetroArch once and accept its storage
prompt.

1. `<dataDir>/cores/` must exist, or `CoreSideloadActivity` hard-fails
   with "Destination directory doesn't exist
   (/data/user/0/com.retroarch/cores)". Only a first launch creates it.
2. RetroArch needs `READ_EXTERNAL_STORAGE`, which it prompts for on that
   same first launch. Revoking it turns the handoff into "open failed:
   EACCES (Permission denied)".

**Where the payload has to live.** Not a free choice: three of the four
candidate locations are dead ends. Measured with a freshly installed
client holding no grants at all:

| location | client writes | RetroArch reads |
|---|---|---|
| `/storage/emulated/0/Strom/` | only if the client created it | yes |
| `Android/data/<client>/files/` | yes, no permission | **no** |
| internal `getFilesDir()` | yes | no |
| `/storage/emulated/0/Download/Strom/` | **yes, no permission** | **yes** |
| `/storage/emulated/0/RetroArch/system/` | **no - EPERM** | (its own) |

The client's own external files dir is the intuitive choice and it does
not work: RetroArch reports "Input file doesn't exist" for a file that
demonstrably exists (the client reads it back with `canRead=true`),
because no app may reach into another app's `Android/data`. Public
`Downloads` is the location both processes reach, and the client needs
**no storage permission at all** to use it - by direct path or through
`MediaStore.Downloads`. Prefer the direct path: MediaStore de-duplicates
rather than overwrites, so a stale entry makes the next insert
`<name> (1).so`, which then mismatches the name the manifest declares.

Two corrections to earlier readings of this table, both from re-measuring:

- Arbitrary shared storage is not simply "needs All-Files". *Creating*
  `/storage/emulated/0/Strom/` needs it; writing into that directory
  afterwards does not, because the client owns what it created. The
  first measurement conflated the two.
- `MANAGE_EXTERNAL_STORAGE` is **not** required for the handoff. An A/B/A
  over the grant showed no difference; the apparent dependency was an
  artifact of reading the unconditional `sideload:` log lines as success.

**The BIOS has nowhere to go.** RetroArch keeps its data on shared
storage at `/storage/emulated/0/RetroArch/`, including the `system/`
directory where PSX cores look for `scph1001.bin`. The client cannot
write there: both that directory and its parent return `EPERM`, because
they belong to another app. So the 15 PSX and multi-disc-with-BIOS games
cannot be delivered end to end today, even though their payload shape is
expressible. Three ways out, none yet tested: ship the BIOS in the
payload and point `system_directory` at it via a `CONFIGFILE` we write
ourselves (which means driving `RetroActivityFuture` directly, see
below); take the All-Files grant purely to place one file; or have the
user drop the BIOS in once by hand. The first is the only one that keeps
the zero-permission property.

**The single intent, used for every launch:**

```
Intent().setClassName("com.retroarch",
                      "com.retroarch.browser.debug.CoreSideloadActivity")
  .putExtra("LIBRETRO", "/storage/emulated/0/Download/Strom/<core>.so")
  .putExtra("ROM",      "/storage/emulated/0/Download/Strom/<slug>/<rom>")
```

`CoreSideloadActivity` is `exported="true"` with no intent-filter, so it
must be addressed by explicit component name. It copies the file at
`LIBRETRO` into `prefs.getString("libretro_path", dataDir + "/cores/")`,
then calls `MainMenuActivity.startRetroActivity` and finishes itself.

**One intent does not install-and-launch; the first one only installs.**
When the core is not yet in `<dataDir>/cores/`, the freshly started
`RetroActivityFuture` is force-finished and the process dies as the
sideload activity tears itself down - the core lands, but no game runs.
A second, byte-identical intent then launches it. Measured 2/2 on clean
state (core absent, client holding no storage grant): fire 1 `died`,
fire 2 `RetroActivityFuture`. So the client must send the intent, and on
observing that RetroArch exited without a foreground activity, send it
again. Once the core is installed, a single intent suffices, which is
why this reads as flaky rather than deterministic if you only ever test
a warm device.

*Do not trust the `sideload:` log lines as a success signal.* Both
"Copying X to Y" and "Running RetroArch with core Y" are emitted
unconditionally, before the copy is known to have worked - they appear
in full even when the run ends on "Destination directory doesn't exist".
The trustworthy signals are the on-screen error text and whether
`RetroActivityFuture` is the top activity afterwards.

**`RetroActivityFuture` with a config we own: measured, and it works.**
The earlier reasoning here was wrong in an important way. It said we
cannot drive `RetroActivityFuture` because `CONFIGFILE` comes from
`UserPreferences.getDefaultConfigPath`, which branches on RetroArch's
private SharedPreferences and is unreadable by us. True, and irrelevant:
we do not need to reproduce *their* config path, we can supply *ours*.

Measured on an API 34 AVD. Starting
`com.retroarch/.browser.retroactivity.RetroActivityFuture` with `ROM`,
`LIBRETRO`, `DATADIR` (`ApplicationInfo.dataDir`), `APK`
(`.sourceDir`), `SDCARD` and a `CONFIGFILE` pointing into our own
writable directory makes RetroArch report
`[ENV] Config file: "/storage/emulated/0/Download/strom-ra.cfg"` and
auto-start the ROM from our payload. It then keeps that file as its
config: `system_directory`, `savefile_directory` and
`input_player1_a = "x"` all survive in it afterwards.

That single lever resolves three separate problems that looked
unrelated, because all three are "RetroArch must read a config we
control":

- **BIOS.** `system_directory` can point at a directory inside our
  payload area, which we can write, instead of
  `/storage/emulated/0/RetroArch/system`, which we cannot.
- **Core options.** `core_options_path` can name a file we generate from
  the manifest's `coreOptions`, lifting the limitation recorded below.
- **Keybindings.** The desktop's `retroarch.settings` are just config
  lines; the same generator can emit them here.

Still unverified, and it is the part that matters for the 15 PSX games:
that a PSX core actually finds `scph1001.bin` through a
`system_directory` set this way. Nothing about the config mechanism
suggests it will not, but it has not been run.

**The client now does this**, confirmed on an AYN Thor against
`com.retroarch.aarch64` 1.22.2 and not only on an AVD: RetroArch logs
`[ENV] Config file: "/storage/emulated/0/Download/Strom/retroarch.cfg"`
and starts the ROM. What forced it was the touch overlay, which is drawn
over every game and is useless on a handheld with physical controls;
`input_overlay_enable` is a config key and there is no intent extra or
broadcast that reaches it.

Two things had to be got right, both measured rather than reasoned:

- **The core still has to arrive through the sideload activity**, because
  shared storage is `noexec` and RetroArch cannot load the `.so` from
  where we downloaded it. Sending that activity a core with *no* ROM does
  copy it, but RetroArch then starts the core with no content and dies in
  it -- SIGSEGV in `bsnes_libretro_android.so` `retro_set_environment`.
  So the first game on each core is launched through the sideload intent
  as before, which copies the core as a side effect, and every launch
  after that is ours. The cost is honest and bounded: that first launch
  runs under RetroArch's config, so the overlay appears once per core.
- **`input_overlay_hide_when_gamepad_connected` is the wrong key**, though
  it names exactly this intent. RetroArch's Android input driver registers
  a pad only when an event arrives from it (`handle_hotplug` is reached
  from the poll loop; nothing enumerates devices at init), so the overlay
  is drawn over the start of every game until the player presses
  something. The client decides it instead, from
  `InputDevice.getDeviceIds()` at launch, and writes `input_overlay_enable`
  -- so a phone with no pad keeps its overlay.

`config_save_on_exit` defaults true, so RetroArch rewrites that file with
its complete settings on every clean exit. The client therefore
read-modify-writes it before each launch instead of generating it: a
fresh file would silently discard everything the player changed in
RetroArch's own menus.

**`QUERY_INSTALLED_CORES` does not exist in any release.** It is on
master only; RetroArch 1.22.2_GIT declares no receivers at all and the
broadcast is silently dropped. Losing it costs nothing. Because we
re-send the sideload intent on every launch anyway, the broadcast was
only an optimisation to skip a *download*, so the client instead records
locally which cores it has already fetched. Cores come from
`https://buildbot.libretro.com/nightly/android/latest/arm64-v8a/<core>.so.zip`.

**Risk.** `CoreSideloadActivity`'s own javadoc reads "This activity
allows developers to sideload and run a core from their PC through adb".
It is a developer affordance that happens to be exported, not a
supported API, and it could be removed. Fallback if it is: have the user
install the core once through RetroArch's own Core Downloader, which then
forces us to solve `CONFIGFILE`. This is a second reason Stage 4
(embedding the cores) is the real destination.

Android core names are derived from the nixpkgs libretro package's
`pname` (`libretro-melonds` -> `melonds_libretro_android.so`). One
override is needed: the Android buildbot ships no plain
`mupen64plus_next`, only `_gles2` and `_gles3` variants, so
`libretro-mupen64plus-next` maps to
`mupen64plus_next_gles3_libretro_android.so`.

**Limitation:** core options live in `retroarch-core-options.cfg` in
RetroArch's config directory and there is no per-launch extra for them.
`CONFIGFILE` overrides the main config only. So the `coreOptions` a game
sets on the desktop (see `lib/retroarch.nix`) cannot be applied while
RetroArch is the runtime; the manifest carries them so the client can at
least show what to set. Stage 4 removes this limitation.

### Dolphin (`dolphin`)

Cache-bound and the weakest of the three. `AppLinkActivity` accepts
`dolphinemu://app/play/<channelId>/<gameId>` where `gameId` is the
6-character disc id and `channelId` is only logged, but it resolves
through `GameFileCacheManager.getGameFileByGameId`, so the disc must
already be scanned. The scan paths are `ISOPaths`/`ISOPath0..N` in
`[General]` of `Dolphin.ini`, which lives under Dolphin's own
`Android/data` directory and is therefore not writable by us. No
exported component takes a raw path or URI.

So: download the disc image, then ask the user to add
`/storage/emulated/0/Download/Strom/games/` to Dolphin's game folders once. Six
games; not worth more engineering than that.

### Azahar (`azahar`)

3DS, and the only live emulator for it (Citra deleted after the 2024
settlement, Lime3DS merged into Azahar). Pin the **vanilla** artifact, not
`googleplay`: different application id and only vanilla opens an incoming
`content:` URI.

`org.citra.citra_emu.activities.EmulationActivity`, `ACTION_VIEW`. Pass the
ROM as the `SelectedGame` extra prefixed with `!`, Azahar's own marker for
"filesystem path, not document" -- a `content:` URI works only for a file
this client created, so a path avoids the ownership question entirely.

Its first run is a mandatory wizard (all-files permission plus a folder for
its data); handing it a ROM before that crashes it out of
`DirectoryInitialization.getUserDirectory`, so it is primed like RetroArch.
The dump must be **decrypted** -- any NCCH with `no_crypto` clear is
refused, and no keys are needed since they are compiled in.

Settings split three ways and only one is reachable: screen layout lives in
`config.ini` in the granted folder (ours to write), while host-key mapping
and the on-screen overlay are private SharedPreferences (not ours, so the
setup message names them -- Azahar ships no pad mapping at all, and its
Controls settings have an Auto-Map action). Azahar never reports which
folder it was given, so the client finds it by shape: a readable
`config/config.ini` beside two or more of `sdmc`, `nand`, `sysdata`,
`shaders`. Read-modify-write, because Azahar rewrites that file on exit.


## How many apps does a user install?

**Two per game. Four to cover everything. Never five.**

A game needs Strom plus exactly one runtime app, and each runtime app is
a one-time install that covers a whole bucket:

| install                  | unlocks   |
| ------------------------ | --------- |
| Strom + RetroArch        | 64 games  |
| Strom + GameNative       | 269 games |
| Strom + Dolphin          | 6 games   |

RetroArch and Dolphin are on F-Droid; GameNative is a direct APK. A user
who only wants Pokemon installs two apps, full stop.

Strom should also *drive* those installs rather than send the user
hunting: fetch the runtime's own release APK and hand it to a
`PackageInstaller` session (`REQUEST_INSTALL_PACKAGES`). That makes it
"tap yes twice", not a treasure hunt. One constraint: we must **not
bundle GameNative's APK** in ours - it contains three binaries its own
`THIRD_PARTY_NOTICES` marks proprietary with no redistribution grant.
Fetching it from `downloads.gamenative.app` on the user's device is
linking, not redistribution.

### The path to fewer apps

**RetroArch (64 games) can be removed.** A libretro core is a
self-contained `.so` whose entire contract is `dlopen` plus ~23
`dlsym("retro_*")`; verified by `readelf` on the real arm64-v8a nightly
builds, they have zero undefined `retro_*`, JNI or `ANativeWindow`
symbols and do not expect RetroArch. `dlopen` from our own `filesDir`
is permitted at any `targetSdk` - the Android 10 rule blocks `execve`
and text-relocation mappings, and NDK-built cores are neither.

What that buys and costs:

- A software-blit frontend covers **54 of 64 games**: 26 outright
  (mgba 13, gambatte 7, bsnes 5, fbneo 1 - none of these ever call
  `SET_HW_RENDER`) and 28 more by pinning a renderer core option
  (swanstation 15 via `swanstation_GPU_Renderer = Software`, melonds 13
  which logs a software fallback when `SET_HW_RENDER` is refused).
- The remaining 10 hard-require a GL context: mupen64plus-next (9 games,
  its `.so` has `libEGL.so`/`libGLESv3.so` in `DT_NEEDED`) and flycast
  (1 game, returns false from `retro_load_game` if neither GL nor Vulkan
  is available). Those need real `SET_HW_RENDER` plumbing
  (`get_current_framebuffer`, `get_proc_address`, context reset/destroy
  on the GL thread) - that is where the schedule risk lives.
- **It fixes the core-options gap.** Options are purely programmatic in
  the API (`SET_VARIABLES` / `GET_VARIABLE` / `GET_VARIABLE_UPDATE`);
  the config file is a RetroArch implementation detail. Not implementing
  `GET_CORE_OPTIONS_VERSION` makes every core fall back to the simple v0
  list. So each game's `coreOptions` from `lib/retroarch.nix` gets
  applied properly, which the intent path can never do.
- Size: `LibretroDroid` (GPL-3, active, powers Lemuroid) does the
  core-loading layer in 80 lines and the environment layer in 482 across
  22 cases. A working software-only frontend is 1.5-2k lines of C++/JNI
  plus the Kotlin surface. Read LibretroDroid for architecture only - it
  is GPL-3 and cannot be copied into a permissive frontend.
- License: our frontend must be **permissive (MIT/Apache-2.0)** or
  GPL-2.0-or-later. gambatte is GPL-2.0-*only* while melonds, bsnes and
  swanstation are GPL-3; a GPL-3-only frontend could not be distributed
  in combination with gambatte. Do not bundle cores in the APK - fetch
  them from the libretro buildbot into `filesDir`, which keeps the
  source-offer obligation with buildbot. fbneo additionally is not open
  source (its `src/license.txt` forbids monetary profit and donations),
  so it must never be bundled.

**GameNative (269 games) cannot be removed, and that is the right
answer, not a compromise.** Both candidate fork bases are
irreproducible, and one of them is a legal problem:

- Winlator (LGPL-2.1, no proprietary-labelled shim, download endpoints
  are plain `raw.githubusercontent.com` constants a fork would edit)
  ships **154 MB of committed binaries with no build script anywhere**:
  a 65 MB `rootfs.tzst` that expands to 415 MB of glibc plus Wine 10.10,
  24 prebuilt `jniLibs` `.so` files, and every DXVK/VKD3D/Turnip/Box64
  component. Worse, `assets/wincomponents/*.tzst` is ~40 MB / **218
  genuine Microsoft PE files** (d3dx9_*, d3dcompiler_*, msvcr80/100,
  xaudio2_*, wmvcore, quartz, dsound, dmusic) with no Wine builtin
  marker. Forking means redistributing Microsoft binaries we have no
  licence for, undeclared, on top of vendoring an unbuildable rootfs.
- GameNative is worse still: GPL-3 plus three binaries deliberately kept
  closed to make rebranded forks fail, and its `imagefs` build scripts
  are not published either.

Delegating is what keeps those blobs in someone else's APK, installed by
the user, rather than in an artifact this repo distributes. For a project
whose whole premise is that every byte is fetched by hash from a
derivation, that distinction is the point.

## Device verification checklist

Everything above is read from source, measured on the build host, or -
for items 1, 3 and 4 - settled on an x86_64 API 34 emulator. These are
the claims that only a real device can settle, in cheapest-first order.
Driven over `adb` (`am start`, `am broadcast`, `push`, `logcat`,
`exec-out screencap`, `uiautomator dump` + `input tap`).

**Items 1, 3 and 4 are closed** (2026-08-04, `stromtest` AVD, API 34,
x86_64, SwiftShader). They needed no arm64 hardware because they test
Android platform policy and Java-side contracts, not GPU or translation.
What remains - 2, 5, 6, 7 - is hardware-bound. Note that a screenshot
can be verified without eyeballing it: the Game Boy viewport reduces to
`colors=4` under `imagemagick identify`, which is a stronger assertion
than "looks right" anyway.

Instrumentation note: without root we cannot read another app's private
data, so GameNative's `.container` JSON, RetroArch's `retroarch.cfg` and
`customGameManualFolders` are all invisible. Verification is `logcat`
(both apps log liberally - GameNative through Timber, and its splash text
names what it is doing) plus screencaps of actual frames.

1. ~~**Environment facts.**~~ **Done.** `/storage/emulated` and
   `/mnt/user/0/emulated` are `fuse ... nodev,noexec`; `/data` is ext4
   with no `noexec`, so the restriction there is SELinux, not the mount.
   `Android/data` is `drwxrws--x` - traverse, not list. Still re-run on
   the real device for `ro.soc.model` and the GPU, since Adreno vs Mali
   decides whether GameNative gets native Turnip or Vortek, and every
   later result has to name it.
2. **PE mapping from noexec storage.** The load-bearing inference in
   "Hard platform constraints": that a game payload on external storage
   works because the x86 code is emulated rather than natively executed.
   Any proton game reaching a frame settles it.
3. ~~**RetroArch, small payload.**~~ **Done, end to end.** A
   never-launched RetroArch fails exactly as predicted ("Destination
   directory doesn't exist (/data/user/0/com.retroarch/cores)"). After
   one launch, the sideload copies the core in, SELinux logs
   `avc: granted { execute } ... untrusted_app_27`, and Pokemon Blue
   renders. Two corrections fell out: `QUERY_INSTALLED_CORES` does not
   exist in any release, and the payload cannot live where the earlier
   draft put it (see the location table under RetroArch).
4. ~~**Caller identity.**~~ **Done.** `probe/` in this worktree builds a
   12 KB APK with `aapt2` + `javac` + `d8` + `apksigner` and no Gradle.
   The intent originates `from uid 10193`, not shell's 2000, and behaves
   identically. It also confirmed the `<queries>` block works and that
   `ApplicationInfo` exposes `dataDir`/`sourceDir`, so the `DATADIR`/`APK`
   extras are computable. Reuse it for item 5 rather than trusting `adb`.
5. **The decisive GameNative test.** Register
   `/storage/emulated/0/Download/Strom/games` once (drive the SAF picker with
   `uiautomator dump` + `input tap` rather than blind coordinates; try
   `appops set app.gamenative MANAGE_EXTERNAL_STORAGE allow` first to
   skip a UI trip). Then `am start -a app.gamenative.LAUNCH_GAME
   --ei app_id <n> --es game_source CUSTOM_GAME --es container_config
   '<json>'` with `drives` repointing `A:` at one game's subfolder, and
   check that *that* game boots. This is the one unknown the whole parent
   mode design rests on.
6. **Mono reinstall on game switch: how bad?** Every game now sends its
   own `executablePath` into one shared container, so
   `setNeedsUnpacking(true)` plausibly fires on each switch. Launch
   `animal-well`, then `risk-of-rain`, then back, watching `logcat` for
   the "Installing Mono..." splash text and the "Cleared needsUnpacking"
   line, and **time it**. A couple of seconds is noise; a minute per
   switch means parent mode needs the per-game-registration escape for
   anyone with a large library. This is the number that decides whether
   one-registration-ever was the right trade.
7. **The real fetch path.** Once the handoffs work, stop using
   `adb push` and let the app pull a small payload from the gateway pool
   for real, including a mid-download kill to prove chunk-granular
   resume and the sha256 rejection of a corrupted chunk.

Results are per device. A pass on one SoC is not a pass on Mali or
Xclipse, and any measurement should name the GameNative version it was
taken on (its Wine/Proton stack floats).

## Signing: the debug key, deliberately, and how to leave it

Releases are signed with the debug key committed in `pkgs/android-app/`.
It is public, so it authenticates nobody. What stands in for authenticity
is that the build is reproducible: anyone can run
`nix build github:kraftwerk-gaming/strom/<rev>#androidApp` and compare
sha256 with the release notes, which is a stronger claim than a signature
from a key only one person holds and nobody checks.

**What repo permissions do and do not cover.** Only the maintainers can
publish to the GitHub repo, so the distribution channel is controlled.
That is a different thing from app identity. Android accepts an in-place
update from anyone holding the signing key, whatever route the APK
arrived by, so with a public key any APK signed with it will install over
the real one without a warning. The channel is safe; the identity is not.
In practice that only bites if a user installs from somewhere other than
these releases -- a mirror, a link, a second Obtainium source -- which for
a sideloaded app used by a handful of people is an acceptable risk, and
the reason this is "for now" rather than settled.

**Leaving is cheap, contrary to what one might assume.** Re-signing an
installed Android app normally makes it a different application and forces
an uninstall. That is avoidable here: the APK is signed with v2 and v3
(verified with `apksigner verify -v`; v1 is off, minSdk being 26), and v3
carries a signing-certificate lineage. So a future switch to a real key is
a rotation, not a reinstall:

```
apksigner rotate --out lineage.bin \
  --old-signer --ks pkgs/android-app/debug.keystore --ks-key-alias strom \
  --new-signer --ks real.keystore --ks-key-alias strom
apksigner sign --ks real.keystore --ks-key-alias strom --lineage lineage.bin app.apk
```

Android 9 and later accept the update; older releases would not, but
minSdk is 26 and the practical floor for this client is higher anyway.
The lineage file then has to be kept and passed on every subsequent
signing, which is the real ongoing cost of switching.

## Staged plan

**Stage 0 - contract (done).** `lib/android/default.nix` gains `backend`,
`retroarchCore`, `containerConfig`, `data`, `outputs.payload` and
`outputs.manifest`; `flake.nix` exposes `androidManifests.<slug>` and
`androidPayloads.<slug>`. Verified: manifests evaluate correctly for all
six runtime buckets, the payload zip is byte-reproducible under
`nix build --rebuild`, `android.data` wiring yields a non-null `payload`.

**Stage 1 - publication.** The client must read the catalog over plain
HTTP without Nix, the way `web/gui/app.js` already does from a Radicle
seed's `radicle-httpd` API. Add the manifest as an `android` build key
in `games/<slug>/metadata.json` via `scripts/sync-metadata.{nix,py}`,
and add `"android"` to `NON_DISPLAY` in `web/gui/app.js` so the GUI does
not treat it as a display field. Gate this on real payload CIDs
existing: an `android` key that is all nulls for 464 games is noise.

**Stage 2 - the APK, RetroArch by intent.** Catalog browser,
multi-gateway range fetcher in a `dataSync` foreground service with
chunk-granular resume and sha256 verification, `java.util.zip`
extraction, then the RetroArch dispatch above. RetroArch first because
it is the only backend with zero manual steps, which makes it the
honest end-to-end proof of the fetch pipeline every other backend
shares. 64 games. Sideloaded APK, `targetSdk` current (Strom executes
nothing, so it is not pinned at 28). The dispatcher itself is ~200
deliberately disposable lines, superseded by Stage 4.

**Stage 3 - GameNative backend.** Same fetch path, plus the
`.gamenative` id file, the container config, the per-launch `A:` drive
override, and the once-ever parent-folder registration the user performs.
Worth upstreaming to GameNative: an exported `ADD_CUSTOM_GAME_FOLDER`
intent so we can register the path ourselves; `scanAsLibraryItems` reads
only `customGameManualFolders`, so writing to that list is the whole
patch, a handful of lines in a GPL-3.0 app. Also add
`PackageInstaller`-driven runtime install so the user never has to go
find GameNative themselves.

**Stage 4 - embedded libretro frontend, drop the RetroArch dependency.**
Software-blit first (54 of 64 games, see above), permissively licensed,
cores downloaded to `filesDir` rather than bundled. This is what makes
Strom a single app for the whole retroarch bucket and the only way the
per-game `coreOptions` ever get applied. Add `SET_HW_RENDER` afterwards
for the 10 mupen64plus-next and flycast titles.

**Stage 5 - the 125 unsupported games.** `native` (76) needs Box64 plus
a glibc rootfs with no runtime app to host it; `custom` (40) is per-game
work; `pcsx2` (9) has no legitimate target and should stay unsupported
until one exists. Do not start here.

## Out of scope, deliberately

- Forking GameNative or Winlator. Legally possible (GPL-3.0 and
  LGPL-2.1) but both bases are irreproducible, and Winlator's 218
  bundled Microsoft DLLs would make our APK the thing redistributing
  them. See "The path to fewer apps" above for the full accounting.
  Revisit only if the GameNative folder-registration patch is rejected
  upstream and the friction proves fatal.
- Running an IPFS node on the device. Nothing maintained exists.
- Bundling a Wine runtime, a rootfs, or a whole emulator app into the
  Strom APK. Note this does *not* rule out the Stage 4 libretro
  frontend: that is our own code, and the cores it loads are downloaded
  into `filesDir` at runtime, never shipped in the package.
- Google Play. The sideload-only runtime apps make it unreachable, and
  nothing is lost. (Strom's own permission set no longer stands in the
  way - it needs none - but the apps it hands off to still do.)
