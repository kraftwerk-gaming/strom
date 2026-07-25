#!/usr/bin/env python3
"""Strom couch launcher.

A fullscreen game grid driven by a gamepad. Reads a JSON manifest baked
at build time, fetches Lutris banner art and Steam screenshots on first
run, shows nix's own build progress while a game builds, then runs it.
"""

import json
import math
import os
import re
import signal
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
import pygame  # noqa: E402

MANIFEST = Path(os.environ["STROM_MANIFEST"])
GAMES = Path(os.environ["STROM_GAMES"])
FLAKE_REF = os.environ.get("STROM_FLAKE", "github:kraftwerk-gaming/strom")

XDG_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
BANNER_CACHE = XDG_CACHE / "strom" / "banners"
SHOT_CACHE = XDG_CACHE / "strom" / "shots"

TILE_W, TILE_H = 460, 215
TILE_GAP = 36
COLS = 3

BG_TOP = (12, 14, 24)
BG_BOT = (24, 18, 38)
ACCENT = (94, 211, 255)
ACCENT_SOFT = (94, 211, 255, 70)
TEXT = (235, 238, 245)
DIM = (130, 135, 150)
SHADOW = (0, 0, 0, 140)

RUNTIME_COLORS = {
    "proton": (138, 95, 232),
    "native": (95, 200, 120),
    "dosbox": (232, 165, 70),
    "retroarch": (232, 95, 130),
    "wine": (120, 150, 232),
}

POP_SCALE = 1.08
EASE = 0.18  # 0..1 lerp factor per frame

SHOT_DWELL = 0.5  # seconds a tile stays selected before its slideshow starts
SHOT_HOLD = 3.2  # seconds each screenshot is shown
SHOT_FADE = 0.5  # screenshot cross-fade duration
MAX_SHOTS = 6  # screenshots fetched per game


# Filter facets for the overview. `genres` come straight from the catalog;
# feature facets map a chip label to the set of catalog `tags` that satisfy it.
# `tags` are Steam categories (overridable per-game via metadata.json `tags`), so
# "gamepad support" is just another tag group -- no schema change needed.
GAMEPAD_TAGS = frozenset(
    {
        "Full controller support",
        "Partial Controller Support",
        "Gamepad Recommended",
        "Steam Input API Support",
    }
)
FEATURE_FACETS = [
    ("Gamepad", GAMEPAD_TAGS),
    ("Single-player", frozenset({"Single-player"})),
    ("Multiplayer", frozenset({"Multi-player"})),
    (
        "Co-op",
        frozenset({"Online Co-op", "Shared/Split Screen Co-op", "LAN Co-op", "Co-op"}),
    ),
    ("Local Co-op", frozenset({"Shared/Split Screen Co-op", "LAN Co-op"})),
    ("PvP", frozenset({"PvP", "Online PvP", "Shared/Split Screen PvP", "LAN PvP"})),
    (
        "Split Screen",
        frozenset(
            {
                "Shared/Split Screen",
                "Shared/Split Screen Co-op",
                "Shared/Split Screen PvP",
            }
        ),
    ),
    ("Remote Play Together", frozenset({"Remote Play Together"})),
]


def build_facets(games: list[dict]) -> list[tuple]:
    """Ordered (label, predicate) facets present in the loaded games: All,
    then each genre alphabetically, then the feature groups with >=1 match."""
    facets: list[tuple] = [("All", lambda g: True)]
    for genre in sorted({gn for g in games for gn in g["genres"]}):
        facets.append((genre, lambda g, gn=genre: gn in g["genres"]))
    for label, tagset in FEATURE_FACETS:
        if any(g["tags"] & tagset for g in games):
            facets.append((label, lambda g, ts=tagset: bool(g["tags"] & ts)))
    return facets


NON_DISPLAY = {"appid", "cids", "description", "runtime"}


def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def _display_entry(slug: str) -> dict:
    """Merge games/<slug>/steam.json + metadata.json (steam overlaid by
    metadata's display fields), the same merge the web GUI does."""
    entry = _read_json(GAMES / slug / "steam.json")
    for k, v in _read_json(GAMES / slug / "metadata.json").items():
        if k.startswith("_") or k in NON_DISPLAY:
            continue
        entry[k] = v
    return entry


def load_manifest() -> list[dict]:
    data = json.loads(MANIFEST.read_text())
    games = []
    for slug, meta in sorted(data.items()):
        cat = _display_entry(slug)
        # Prefer the curated display name; fall back to the nix description
        # with its "(...)" packaging note stripped.
        label = cat.get("name")
        if not label:
            label = meta.get("description") or slug
            if "(" in label:
                label = label.split("(", 1)[0].strip()
        # Subtitle for the selected tile: genres, year, developers.
        bits = []
        genres = cat.get("genres") or []
        if genres:
            bits.append(", ".join(genres[:3]))
        if cat.get("year"):
            bits.append(str(cat["year"]))
        devs = cat.get("developers") or []
        if devs:
            bits.append(", ".join(devs[:2]))
        games.append(
            {
                "slug": slug,
                "label": label,
                "subtitle": "   |   ".join(bits),
                "runtime": meta.get("runtime", "?"),
                "genres": list(genres),
                "tags": set(cat.get("tags") or []),
                "screenshots": list(cat.get("screenshots") or []),
            }
        )
    return games


def fetch_banner(slug: str) -> Path | None:
    BANNER_CACHE.mkdir(parents=True, exist_ok=True)
    dest = BANNER_CACHE / f"{slug}.jpg"
    if dest.exists():
        return dest
    # Negative cache: a banner that upstream doesn't have (404) is marked so we
    # don't pay a network round-trip for it on every launch. Transient failures
    # are left unmarked so they retry next time.
    miss = BANNER_CACHE / f"{slug}.miss"
    if miss.exists():
        return None
    url = f"https://lutris.net/games/banner/{slug}.jpg"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "strom-launcher/1"})
        with urllib.request.urlopen(req, timeout=5) as r:
            dest.write_bytes(r.read())
        return dest
    except urllib.error.HTTPError as e:
        if e.code == 404:
            miss.touch()
        return None
    except (urllib.error.URLError, TimeoutError, OSError):
        return None


def load_banner_surface(slug: str) -> pygame.Surface | None:
    p = fetch_banner(slug)
    if p is None:
        return None
    try:
        img = pygame.image.load(str(p)).convert()
        return pygame.transform.smoothscale(img, (TILE_W, TILE_H))
    except pygame.error:
        return None


def fetch_shot(slug: str, idx: int, url: str) -> Path | None:
    """Download one screenshot into the per-slug cache. 404s are negative-cached
    like banners so a missing shot isn't re-fetched on every selection."""
    d = SHOT_CACHE / slug
    dest = d / f"{idx}.jpg"
    if dest.exists():
        return dest
    miss = d / f"{idx}.miss"
    if miss.exists():
        return None
    if not url:
        return None
    d.mkdir(parents=True, exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "strom-launcher/1"})
        with urllib.request.urlopen(req, timeout=8) as r:
            dest.write_bytes(r.read())
        return dest
    except urllib.error.HTTPError as e:
        if e.code == 404:
            miss.touch()
        return None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None


def load_shot_surface(path: Path, w: int, h: int) -> pygame.Surface | None:
    """Load a screenshot scaled to cover a w*h tile (crop to fill, no
    distortion), with the same rounded corners as a banner."""
    try:
        img = pygame.image.load(str(path)).convert()
    except (pygame.error, OSError):
        return None
    iw, ih = img.get_size()
    if iw <= 0 or ih <= 0:
        return None
    scale = max(w / iw, h / ih)
    nw, nh = max(w, round(iw * scale)), max(h, round(ih * scale))
    img = pygame.transform.smoothscale(img, (nw, nh))
    crop = img.subsurface(((nw - w) // 2, (nh - h) // 2, w, h)).copy()
    return round_surface(crop, 8)


def make_gradient(w: int, h: int) -> pygame.Surface:
    """Vertical gradient. Render to a 1px-wide strip then stretch; cheap."""
    strip = pygame.Surface((1, h))
    for y in range(h):
        t = y / h
        c = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        strip.set_at((0, y), c)
    return pygame.transform.scale(strip, (w, h))


def make_shadow(w: int, h: int, radius: int = 14) -> pygame.Surface:
    """Soft drop shadow. Draw at offset behind the tile."""
    s = pygame.Surface((w + radius * 2, h + radius * 2), pygame.SRCALPHA)
    pygame.draw.rect(s, SHADOW, (radius, radius, w, h), border_radius=10)
    # cheap blur: scale down and back up
    small = pygame.transform.smoothscale(s, (s.get_width() // 4, s.get_height() // 4))
    return pygame.transform.smoothscale(small, s.get_size())


def make_vignette(w: int, h: int) -> pygame.Surface:
    """Darken edges so the eye lands on the centre column."""
    cx, cy = w / 2, h / 2
    maxd = math.hypot(cx, cy)
    # render at quarter res for speed
    qw, qh = w // 4, h // 4
    small = pygame.Surface((qw, qh), pygame.SRCALPHA)
    for y in range(qh):
        for x in range(qw):
            d = math.hypot(x * 4 - cx, y * 4 - cy) / maxd
            a = int(max(0, d - 0.55) * 200)
            small.set_at((x, y), (0, 0, 0, min(a, 120)))
    return pygame.transform.smoothscale(small, (w, h))


def round_surface(surf: pygame.Surface, radius: int) -> pygame.Surface:
    """Clip a surface to rounded corners."""
    w, h = surf.get_size()
    mask = pygame.Surface((w, h), pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), (0, 0, w, h), border_radius=radius)
    out = pygame.Surface((w, h), pygame.SRCALPHA)
    out.blit(surf, (0, 0))
    out.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MIN)
    return out


def make_badge(font: pygame.font.Font, text: str, color: tuple) -> pygame.Surface:
    label = font.render(text, True, (255, 255, 255))
    pad = 6
    w, h = label.get_width() + pad * 2, label.get_height() + pad
    s = pygame.Surface((w, h), pygame.SRCALPHA)
    pygame.draw.rect(s, (*color, 220), (0, 0, w, h), border_radius=h // 2)
    s.blit(label, (pad, pad // 2))
    return s


# --- launch progress -------------------------------------------------------
#
# `nix run` builds the game before running it, and the first launch of an
# uncached game fetches/builds for minutes with nothing on screen. Rather than
# invent our own progress, reuse nix's: `nix build --log-format internal-json`
# emits the exact activity/result stream that drives nix's own progress bar
# (start/stop activities, done/expected counts, build-log lines). Parse that
# generically and draw it; then `nix run` (cached now) starts the game at once.

KILL_COMBO = {6, 7}  # Back (View) + Start (Menu) on an Xbox pad

_STORE_RE = re.compile(r"/nix/store/[a-z0-9]{32}-([^\s'\"]+)")

# nix ActivityType / ResultType (src/libutil/logging.hh); only the ones we
# surface, everything else is ignored.
_ACT_COPY_PATH = 100
_ACT_FILE_TRANSFER = 101
_ACT_BUILD = 105
_ACT_SUBSTITUTE = 108
_ACT_BYTES = {_ACT_COPY_PATH, _ACT_FILE_TRANSFER}
_ACT_HEADLINE = {_ACT_COPY_PATH, _ACT_FILE_TRANSFER, _ACT_BUILD, _ACT_SUBSTITUTE}
_RES_BUILD_LOG = 101
_RES_PROGRESS = 105
_RES_POST_BUILD_LOG = 107


def _terminate(proc: "subprocess.Popen") -> None:
    """Kill a game's whole process group (nix -> gamescope -> proton -> game),
    escalating to SIGKILL if it does not exit promptly."""
    if proc.poll() is not None:
        return
    try:
        pgid = os.getpgid(proc.pid)
    except ProcessLookupError:
        return
    try:
        os.killpg(pgid, signal.SIGTERM)
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    except ProcessLookupError:
        pass


def _tidy(text: str) -> str:
    """Strip /nix/store/<hash>- prefixes and quotes so nix's activity text fits
    on one line and reads as a name."""
    return _STORE_RE.sub(r"\1", text or "").strip().strip("'\"")


def _read_nix(proc: "subprocess.Popen", state: dict, lock: threading.Lock) -> None:
    """Consume nix's internal-json stream on stderr and publish the current
    activity, aggregate byte progress and the last log line into `state`."""
    acts: dict = {}  # activity id -> activity type
    prog: dict = {}  # activity id -> (done, expected) bytes
    for line in proc.stderr:
        if not line.startswith("@nix "):
            continue
        try:
            ev = json.loads(line[5:])
        except json.JSONDecodeError:
            continue
        action = ev.get("action")
        if action == "start":
            typ = ev.get("type", 0)
            acts[ev.get("id")] = typ
            text = ev.get("text")
            if typ in _ACT_HEADLINE and text:
                with lock:
                    state["headline"] = _tidy(text)
        elif action == "stop":
            aid = ev.get("id")
            acts.pop(aid, None)
            prog.pop(aid, None)
        elif action == "result":
            aid = ev.get("id")
            rt = ev.get("type")
            fields = ev.get("fields") or []
            if rt in (_RES_BUILD_LOG, _RES_POST_BUILD_LOG) and fields:
                with lock:
                    state["detail"] = _tidy(str(fields[0]))
            elif (
                rt == _RES_PROGRESS and len(fields) >= 2 and acts.get(aid) in _ACT_BYTES
            ):
                prog[aid] = (fields[0] or 0, fields[1] or 0)
                done = sum(d for d, _ in prog.values())
                exp = sum(e for _, e in prog.values())
                with lock:
                    state["bytes"] = (done, exp)
        elif action == "msg" and ev.get("level", 3) <= 1:
            with lock:
                state["error"] = _tidy(ev.get("msg", ""))
    with lock:
        state["rc"] = proc.wait()


def _rescan_pads(pads: dict) -> None:
    """Open any present-but-unopened joystick, keyed by instance id, holding a
    reference in `pads` so SDL keeps it open. Callers poll this because SDL's
    JOYDEVICEADDED hotplug is unreliable without udev under the kiosk."""
    for i in range(pygame.joystick.get_count()):
        js = pygame.joystick.Joystick(i)
        iid = js.get_instance_id()
        if iid not in pads:
            js.init()
            pads[iid] = js


def _poll_kill(held: set, pads: dict, proc: "subprocess.Popen") -> bool:
    """Pump pygame events into `held`; return True when the kill/cancel combo
    (Back+Start, or Esc) is triggered. Re-scans pads every call so a controller
    that drops and reconnects mid-game still drives the combo, since SDL's
    JOYDEVICEADDED hotplug is unreliable without udev here."""
    _rescan_pads(pads)
    for ev in pygame.event.get():
        if ev.type == pygame.JOYBUTTONDOWN:
            held.add(ev.button)
        elif ev.type == pygame.JOYBUTTONUP:
            held.discard(ev.button)
        elif ev.type == pygame.JOYDEVICEREMOVED:
            pads.pop(ev.instance_id, None)
            held.clear()
        elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            return True
    return KILL_COMBO <= held


def _draw_progress(screen, fonts, bg, state, lock, t) -> None:
    sw, sh = screen.get_size()
    with lock:
        headline = state["headline"]
        detail = state["detail"]
        done, exp = state["bytes"]
    big, mid, small = fonts

    screen.blit(bg, (0, 0))
    title = big.render("launching", True, ACCENT)
    screen.blit(title, title.get_rect(center=(sw // 2, sh // 2 - 130)))
    hl = mid.render(headline[:80], True, TEXT)
    screen.blit(hl, hl.get_rect(center=(sw // 2, sh // 2 - 60)))

    bw, bh = 900, 26
    bx, by = (sw - bw) // 2, sh // 2 - 20
    pygame.draw.rect(screen, (40, 42, 56), (bx, by, bw, bh), border_radius=13)
    if exp > 0:
        frac = max(0.0, min(1.0, done / exp))
        pygame.draw.rect(
            screen, ACCENT, (bx, by, max(bh, int(bw * frac)), bh), border_radius=13
        )
        mib = small.render(f"{done // 1048576} / {exp // 1048576} MiB", True, DIM)
        screen.blit(mib, mib.get_rect(midtop=(sw // 2, by + bh + 10)))
    else:
        cw = 220
        x = bx + int((0.5 - 0.5 * math.cos(t * 2.2)) * (bw - cw))
        pygame.draw.rect(screen, ACCENT, (x, by, cw, bh), border_radius=13)

    if detail:
        dt = small.render(detail[:104], True, DIM)
        screen.blit(dt, dt.get_rect(center=(sw // 2, by + bh + 46)))

    hint = small.render("Back + Start   cancel", True, DIM)
    screen.blit(hint, hint.get_rect(midbottom=(sw // 2, sh - 24)))
    pygame.display.flip()


def launch_with_fade(screen: pygame.Surface, game: dict) -> None:
    slug = game["slug"]
    label = game.get("label", slug)
    sw, sh = screen.get_size()

    big = pygame.font.SysFont(None, 56, bold=True)
    mid = pygame.font.SysFont(None, 34)
    small = pygame.font.SysFont(None, 24)
    fonts = (big, mid, small)
    bg = make_gradient(sw, sh)

    # fade the grid out under a "launching <label>" caption
    snap = screen.copy()
    overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
    cap = big.render(f"launching {label}", True, TEXT)
    for i in range(18):
        overlay.fill((0, 0, 0, int((i / 17) * 220)))
        screen.blit(snap, (0, 0))
        screen.blit(overlay, (0, 0))
        screen.blit(cap, cap.get_rect(center=(sw // 2, sh // 2)))
        pygame.display.flip()
        pygame.time.wait(12)

    # In a gamescope-session kiosk (STROM_NO_GAMESCOPE=1) run the game directly
    # in the session compositor instead of nesting a per-game gamescope.
    ref = f"{FLAKE_REF}#{slug}"
    if os.environ.get("STROM_NO_GAMESCOPE"):
        ref += ".no-gamescope"

    # Phase 1: build, showing nix's own progress. `nix run` alone would build
    # too, but silently; building first lets us surface the download/build.
    state = {
        "headline": "preparing",
        "detail": "",
        "bytes": (0, 0),
        "rc": None,
        "error": "",
    }
    lock = threading.Lock()
    build = ["nix", "build", ref, "--no-link", "-L", "--log-format", "internal-json"]
    print(f"+ {' '.join(build)}", file=sys.stderr)
    try:
        proc = subprocess.Popen(
            build,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        print("nix not found in PATH", file=sys.stderr)
        pygame.event.clear()
        return
    threading.Thread(target=_read_nix, args=(proc, state, lock), daemon=True).start()

    held: set = set()
    pads: dict = {}
    clock = pygame.time.Clock()
    t = 0.0
    while True:
        with lock:
            rc = state["rc"]
        if rc is not None:
            break
        if _poll_kill(held, pads, proc):
            _terminate(proc)
            pygame.event.clear()
            return
        _draw_progress(screen, fonts, bg, state, lock, t)
        t += clock.tick(30) / 1000.0

    if rc != 0:
        with lock:
            err = state["error"] or state["detail"] or "see journal"
        screen.blit(bg, (0, 0))
        t1 = big.render(f"failed to launch {label}", True, (240, 150, 150))
        screen.blit(t1, t1.get_rect(center=(sw // 2, sh // 2 - 30)))
        t2 = small.render(err[:104], True, DIM)
        screen.blit(t2, t2.get_rect(center=(sw // 2, sh // 2 + 30)))
        hint = small.render("any button to continue", True, DIM)
        screen.blit(hint, hint.get_rect(midbottom=(sw // 2, sh - 24)))
        pygame.display.flip()
        held.clear()
        waited = 0
        while waited < 5000:
            for ev in pygame.event.get():
                if ev.type in (pygame.JOYBUTTONDOWN, pygame.KEYDOWN):
                    waited = 5000
            waited += clock.tick(30)
        pygame.event.clear()
        return

    # Phase 2: run. Build is cached now, so `nix run` starts the game at once;
    # its gamescope maps over us under sway. Hold Back+Start to kill it.
    cap = big.render(f"starting {label}", True, TEXT)
    screen.blit(bg, (0, 0))
    screen.blit(cap, cap.get_rect(center=(sw // 2, sh // 2)))
    pygame.display.flip()
    run = ["nix", "run", ref]
    print(f"+ {' '.join(run)}", file=sys.stderr)
    try:
        # start_new_session so the whole game tree gets its own process group
        # and we can signal all of it, not just `nix run`.
        proc = subprocess.Popen(run, start_new_session=True)
    except FileNotFoundError:
        print("nix not found in PATH", file=sys.stderr)
        pygame.event.clear()
        return

    held.clear()
    while proc.poll() is None:
        if _poll_kill(held, pads, proc):
            _terminate(proc)
        clock.tick(30)
    _terminate(proc)
    pygame.event.clear()


def target_scroll(sel: int, cur: float, sh: int) -> float:
    row = sel // COLS
    tile_y = 80 + row * (TILE_H + TILE_GAP + 50)
    if tile_y - cur < 80:
        return float(tile_y - 80)
    if tile_y + TILE_H - cur > sh - 120:
        return float(tile_y + TILE_H - sh + 120)
    return cur


def main() -> int:
    games = load_manifest()
    if not games:
        print("manifest empty", file=sys.stderr)
        return 1

    facets = build_facets(games)
    facet_idx = 0
    view = list(games)

    pygame.init()
    pygame.joystick.init()

    # Opened pads keyed by instance id, holding a reference so SDL keeps each
    # open. JOYDEVICEADDED hotplug is unreliable without udev under the kiosk
    # compositor, so the loops poll _rescan_pads() to catch (re)connects.
    joysticks: dict = {}

    _rescan_pads(joysticks)

    flags = pygame.FULLSCREEN | pygame.SCALED
    if os.environ.get("STROM_LAUNCHER_WINDOWED"):
        flags = pygame.RESIZABLE
    screen = pygame.display.set_mode((1920, 1080), flags)
    pygame.display.set_caption("strom")
    sw, sh = screen.get_size()

    font = pygame.font.SysFont(None, 34)
    small = pygame.font.SysFont(None, 24)
    badge_font = pygame.font.SysFont(None, 20, bold=True)
    title_font = pygame.font.SysFont(None, 56, bold=True)

    # static layers
    bg = make_gradient(sw, sh)
    vignette = make_vignette(sw, sh)
    shadow = make_shadow(TILE_W, TILE_H)
    title = title_font.render("STROM", True, ACCENT)

    # Banner art loads without blocking the grid: a background thread downloads
    # every banner into the cache, and pump_banners() pulls finished ones into
    # surfaces a few per frame from the main loop. Previously this warmed ~700
    # banners synchronously before the event loop, delaying input for minutes.
    pop_w, pop_h = int(TILE_W * POP_SCALE), int(TILE_H * POP_SCALE)
    pop_shadow = make_shadow(pop_w, pop_h)
    banners: dict[str, pygame.Surface] = {}
    banners_pop: dict[str, pygame.Surface] = {}
    banner_queue = [g["slug"] for g in games]
    banner_done: dict[str, bool] = {}

    def _prefetch_banners() -> None:
        for g in games:
            banner_done[g["slug"]] = fetch_banner(g["slug"]) is not None

    threading.Thread(target=_prefetch_banners, daemon=True).start()

    def pump_banners(budget: int = 6) -> None:
        loaded = 0
        while banner_queue and loaded < budget:
            slug = banner_queue[0]
            if slug not in banner_done:
                break  # prefetch works in order; nothing later is ready yet
            banner_queue.pop(0)
            if banner_done[slug]:
                surf = load_banner_surface(slug)
                if surf:
                    surf = round_surface(surf, 8)
                    banners[slug] = surf
                    banners_pop[slug] = pygame.transform.smoothscale(
                        surf, (pop_w, pop_h)
                    )
            loaded += 1

    # Screenshots load lazily for the *selected* game only -- prefetching every
    # game's shots would be thousands of images. A worker downloads the current
    # selection's screenshots; the main loop surfaces finished files and
    # cross-fades between them as a slideshow on the popped tile.
    shot_urls = {g["slug"]: g["screenshots"] for g in games}
    shot_files: dict[str, list] = {}  # slug -> downloaded jpg paths
    shot_surfs: dict[str, list] = {}  # slug -> scaled surfaces (None = failed)
    shot_done: set[str] = set()  # slug -> every shot downloaded
    shot_lock = threading.Lock()
    shot_want: list = [None]  # slug the worker should fetch next
    shot_wake = threading.Event()

    def _shot_worker() -> None:
        while True:
            with shot_lock:
                slug = shot_want[0]
            if not slug or slug in shot_done or not shot_urls.get(slug):
                shot_wake.wait(timeout=0.2)
                shot_wake.clear()
                continue
            got: list = []
            aborted = False
            for idx, url in enumerate(shot_urls[slug][:MAX_SHOTS]):
                with shot_lock:
                    if shot_want[0] != slug:
                        aborted = True
                        break
                p = fetch_shot(slug, idx, url)
                if p:
                    got.append(p)
                    with shot_lock:
                        shot_files[slug] = list(got)
            if not aborted:
                with shot_lock:
                    shot_done.add(slug)

    threading.Thread(target=_shot_worker, daemon=True).start()

    def pump_shots(slug: str, budget: int = 2) -> None:
        with shot_lock:
            files = list(shot_files.get(slug, []))
        surfs = shot_surfs.setdefault(slug, [])
        loaded = 0
        while len(surfs) < len(files) and loaded < budget:
            surfs.append(load_shot_surface(files[len(surfs)], pop_w, pop_h))
            loaded += 1

    # pre-render badges
    badges: dict[str, pygame.Surface] = {}
    for g in games:
        rt = g["runtime"]
        if rt not in badges:
            color = RUNTIME_COLORS.get(rt, (100, 100, 110))
            badges[rt] = make_badge(badge_font, rt, color)

    # dim overlay for non-selected tiles
    dimmer = pygame.Surface((TILE_W, TILE_H), pygame.SRCALPHA)
    dimmer.fill((0, 0, 0, 90))
    dimmer = round_surface(dimmer, 8)

    # Pre-render per-game labels and the footer hint once. Re-rendering this
    # text every frame was a large slice of the per-frame cost.
    labels_dim = {g["slug"]: small.render(g["label"], True, DIM) for g in games}
    labels_sel = {g["slug"]: font.render(g["label"], True, TEXT) for g in games}
    subtitles = {
        g["slug"]: small.render(g["subtitle"], True, DIM)
        for g in games
        if g["subtitle"]
    }
    hint = small.render(
        "D-pad / arrows  move      A / Enter  launch      "
        "LB / RB  filter      B / Esc  quit",
        True,
        DIM,
    )

    sel = 0
    scroll = 0.0
    scroll_tgt = 0.0
    pop = [0.0] * len(games)  # 0..1 lerp per tile
    n = len(view)
    clock = pygame.time.Clock()
    t = 0.0
    next_rescan = 0.0

    # Selected-tile screenshot slideshow. Reset whenever the selection changes.
    ss_slug = None  # slug the slideshow currently tracks
    sel_since = 0.0  # t when the current tile became selected
    ss_active = False  # past the dwell and showing screenshots
    ss_idx = 0
    ss_from = None  # surface being faded out (banner or previous shot)
    ss_fade = 1.0  # 0..1 fade progress toward the current shot
    ss_next = 0.0  # t of the next slideshow advance
    surfs_sel: list = []  # loaded shot surfaces for the selection this frame

    AXIS_DEAD = 0.6
    axis_latched = {0: 0, 1: 0}

    # Held-direction auto-repeat. Pads emit no key-repeat and the axis latch
    # below fires once per crossing, so holding a direction only moved once.
    # Track the held move delta and re-apply it on a timer (initial delay,
    # then a faster interval) for keyboard, d-pad, and analog stick alike.
    held_move = 0
    repeat_at = 0.0
    REPEAT_DELAY = 0.35
    REPEAT_INTERVAL = 0.09
    KEY_MOVE = {
        pygame.K_RIGHT: 1,
        pygame.K_d: 1,
        pygame.K_LEFT: -1,
        pygame.K_a: -1,
        pygame.K_DOWN: COLS,
        pygame.K_s: COLS,
        pygame.K_UP: -COLS,
        pygame.K_w: -COLS,
    }

    def move(d: int) -> None:
        nonlocal sel, scroll_tgt
        sel = max(0, min(n - 1, sel + d))
        scroll_tgt = target_scroll(sel, scroll_tgt, sh)

    def start_hold(d: int) -> None:
        nonlocal held_move, repeat_at
        if not d:
            return
        move(d)
        held_move = d
        repeat_at = t + REPEAT_DELAY

    def stop_hold(d: int | None = None) -> None:
        nonlocal held_move
        if d is None or d == held_move:
            held_move = 0

    def set_facet(i: int) -> None:
        nonlocal facet_idx, view, n, sel, scroll, scroll_tgt
        facet_idx = i % len(facets)
        pred = facets[facet_idx][1]
        view = [g for g in games if pred(g)]
        n = len(view)
        sel = 0
        scroll = scroll_tgt = 0.0
        for k in range(len(pop)):
            pop[k] = 0.0

    def cycle_facet(step: int) -> None:
        set_facet(facet_idx + step)

    grid_w = COLS * TILE_W + (COLS - 1) * TILE_GAP
    ox = (sw - grid_w) // 2

    def _settled() -> bool:
        # True when no animation is in flight, so the loop can idle on events
        # instead of redrawing the whole screen at 60fps.
        if banner_queue:
            return False
        if held_move:
            return False
        if abs(scroll_tgt - scroll) > 0.5:
            return False
        if ss_active and ss_fade < 1.0:
            return False
        with shot_lock:
            nfiles = len(shot_files.get(ss_slug, [])) if ss_slug else 0
        if ss_slug and len(shot_surfs.get(ss_slug, [])) < nfiles:
            return False
        return all(abs(pop[i] - (1.0 if i == sel else 0.0)) <= 0.01 for i in range(n))

    running = True
    while running:
        # Idle when nothing is animating: block on events (waking at least
        # once a second for the pad rescan) instead of spinning a full-screen
        # 60fps redraw, which otherwise pins a CPU core the whole time the
        # launcher sits idle on the grid.
        if _settled():
            wake_ms = int((next_rescan - t) * 1000)
            if ss_slug and ss_slug not in shot_done:
                wake_ms = min(wake_ms, 200)  # surface newly downloaded shots soon
            if ss_active and len(surfs_sel) > 1:
                wake_ms = min(wake_ms, int((ss_next - t) * 1000))
            ev0 = pygame.event.wait(max(1, min(1000, wake_ms)))
            dt = clock.tick() / 1000.0
            pending = [] if ev0.type == pygame.NOEVENT else [ev0]
            pending += pygame.event.get()
        else:
            dt = clock.tick(60) / 1000.0
            pending = pygame.event.get()
        t += dt

        for ev in pending:
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_ESCAPE:
                    running = False
                elif ev.key in KEY_MOVE:
                    start_hold(KEY_MOVE[ev.key])
                elif ev.key == pygame.K_q:
                    cycle_facet(-1)
                elif ev.key == pygame.K_e:
                    cycle_facet(1)
                elif ev.key in (pygame.K_RETURN, pygame.K_SPACE):
                    stop_hold()
                    launch_with_fade(screen, view[sel])
            elif ev.type == pygame.KEYUP:
                if ev.key in KEY_MOVE:
                    stop_hold(KEY_MOVE[ev.key])
            elif ev.type == pygame.JOYHATMOTION:
                hx, hy = ev.value
                if hx:
                    start_hold(hx)
                elif hy:
                    start_hold(-hy * COLS)
                else:
                    stop_hold()
            elif ev.type == pygame.JOYAXISMOTION:
                if ev.axis in (0, 1):
                    v = ev.value
                    prev = axis_latched[ev.axis]
                    if abs(v) > AXIS_DEAD and prev == 0:
                        step = 1 if v > 0 else -1
                        axis_latched[ev.axis] = step
                        start_hold(step if ev.axis == 0 else step * COLS)
                    elif abs(v) < AXIS_DEAD * 0.5 and prev != 0:
                        axis_latched[ev.axis] = 0
                        stop_hold(prev if ev.axis == 0 else prev * COLS)
            elif ev.type == pygame.JOYBUTTONDOWN:
                if ev.button == 0:
                    stop_hold()
                    launch_with_fade(screen, view[sel])
                elif ev.button == 1:
                    running = False
                elif ev.button == 4:
                    cycle_facet(-1)
                elif ev.button == 5:
                    cycle_facet(1)
            elif ev.type == pygame.JOYDEVICEADDED:
                _rescan_pads(joysticks)

        # Fire the held-direction repeat once the initial delay has passed,
        # then every REPEAT_INTERVAL while the direction stays held.
        if held_move and t >= repeat_at:
            move(held_move)
            repeat_at = t + REPEAT_INTERVAL

        # SDL hotplug is unreliable under the kiosk compositor, so poll for
        # newly connected pads about once a second.
        if t >= next_rescan:
            _rescan_pads(joysticks)
            next_rescan = t + 1.0

        pump_banners()

        # Track the selection for the screenshot slideshow. On a change, reset
        # the slideshow and tell the worker which game's shots to fetch.
        sel_slug = view[sel]["slug"] if n else None
        if sel_slug != ss_slug:
            ss_slug = sel_slug
            sel_since = t
            ss_active = False
            ss_idx = 0
            ss_from = None
            ss_fade = 1.0
            with shot_lock:
                shot_want[0] = sel_slug
            shot_wake.set()

        if sel_slug:
            pump_shots(sel_slug)
        surfs_sel = [s for s in shot_surfs.get(sel_slug, []) if s] if sel_slug else []

        # Drive the slideshow once the tile has settled and its shots exist.
        if surfs_sel and pop[sel] > 0.98 and (t - sel_since) >= SHOT_DWELL:
            if not ss_active:
                ss_active = True
                ss_idx = 0
                ss_from = banners_pop.get(sel_slug)
                ss_fade = 0.0
                ss_next = t + SHOT_HOLD
            elif t >= ss_next and len(surfs_sel) > 1:
                ss_from = surfs_sel[ss_idx % len(surfs_sel)]
                ss_idx = (ss_idx + 1) % len(surfs_sel)
                ss_fade = 0.0
                ss_next = t + SHOT_HOLD
            if ss_fade < 1.0:
                ss_fade = min(1.0, ss_fade + dt / SHOT_FADE)
        else:
            ss_active = False

        # ease
        scroll += (scroll_tgt - scroll) * EASE
        for i in range(n):
            tgt = 1.0 if i == sel else 0.0
            pop[i] += (tgt - pop[i]) * EASE

        # draw
        screen.blit(bg, (0, 0))
        screen.blit(title, (40, 28))
        fac = facets[facet_idx][0]
        fac_txt = font.render(f"< {fac} >   ({n})", True, ACCENT if facet_idx else DIM)
        screen.blit(fac_txt, (sw - 40 - fac_txt.get_width(), 40))

        oy = 80 - scroll
        pulse = 0.5 + 0.5 * math.sin(t * 3.2)

        # pass 1: non-selected tiles
        for i, g in enumerate(view):
            col, row = i % COLS, i // COLS
            x = ox + col * (TILE_W + TILE_GAP)
            y = oy + row * (TILE_H + TILE_GAP + 50)
            if y + TILE_H < -50 or y > sh + 50:
                continue
            if i == sel:
                continue

            screen.blit(shadow, (x - 14 + 4, y - 14 + 8))
            banner = banners.get(g["slug"])
            if banner:
                screen.blit(banner, (x, y))
                screen.blit(dimmer, (x, y))
            else:
                pygame.draw.rect(
                    screen, (40, 42, 56), (x, y, TILE_W, TILE_H), border_radius=8
                )
                ph = font.render(g["slug"], True, DIM)
                screen.blit(ph, ph.get_rect(center=(x + TILE_W // 2, y + TILE_H // 2)))

            badge = badges[g["runtime"]]
            screen.blit(badge, (x + TILE_W - badge.get_width() - 8, y + 8))

            label = labels_dim[g["slug"]]
            screen.blit(label, label.get_rect(midtop=(x + TILE_W // 2, y + TILE_H + 8)))

        # pass 2: selected tile on top, popped + glowing
        i = sel
        g = view[sel]
        col, row = i % COLS, i // COLS
        bx = ox + col * (TILE_W + TILE_GAP)
        by = oy + row * (TILE_H + TILE_GAP + 50)

        p = pop[i]
        cw = int(TILE_W + (pop_w - TILE_W) * p)
        ch = int(TILE_H + (pop_h - TILE_H) * p)
        x = bx - (cw - TILE_W) // 2
        y = by - (ch - TILE_H) // 2

        # pulsing glow ring
        glow_a = int(120 + 80 * pulse)
        ring = pygame.Surface((cw + 24, ch + 24), pygame.SRCALPHA)
        pygame.draw.rect(
            ring, (*ACCENT, glow_a), (0, 0, cw + 24, ch + 24), width=4, border_radius=14
        )
        screen.blit(ring, (x - 12, y - 12))

        screen.blit(pop_shadow, (x - 14 + 6, y - 14 + 12))

        if ss_active and surfs_sel:
            cur = surfs_sel[ss_idx % len(surfs_sel)]
            if ss_from is not None and ss_fade < 1.0:
                screen.blit(ss_from, (x, y))
                fade_img = cur.copy()
                fade_img.set_alpha(int(255 * ss_fade))
                screen.blit(fade_img, (x, y))
            else:
                screen.blit(cur, (x, y))
        else:
            banner = banners.get(g["slug"])
            if banner:
                if p > 0.98:
                    surf = banners_pop[g["slug"]]
                elif p < 0.02:
                    surf = banner
                else:
                    surf = pygame.transform.smoothscale(banner, (cw, ch))
                screen.blit(surf, (x, y))
            else:
                pygame.draw.rect(screen, (60, 64, 84), (x, y, cw, ch), border_radius=8)
                ph = font.render(g["slug"], True, TEXT)
                screen.blit(ph, ph.get_rect(center=(x + cw // 2, y + ch // 2)))

        badge = badges[g["runtime"]]
        screen.blit(badge, (x + cw - badge.get_width() - 10, y + 10))

        label = labels_sel[g["slug"]]
        screen.blit(label, label.get_rect(midtop=(bx + TILE_W // 2, by + TILE_H + 10)))
        sub = subtitles.get(g["slug"])
        if sub:
            screen.blit(sub, sub.get_rect(midtop=(bx + TILE_W // 2, by + TILE_H + 44)))

        screen.blit(vignette, (0, 0))

        screen.blit(hint, hint.get_rect(midbottom=(sw // 2, sh - 14)))

        pygame.display.flip()

    pygame.quit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
