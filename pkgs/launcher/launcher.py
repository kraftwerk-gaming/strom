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
# Baked in by pkgs/launcher/default.nix. Only used to address
# flake.modules.<system>.<slug> when building a customized game; having it here
# keeps `builtins.currentSystem` (and its impurity) out of that expression.
SYSTEM = os.environ["STROM_SYSTEM"]

XDG_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
BANNER_CACHE = XDG_CACHE / "strom" / "banners"
SHOT_CACHE = XDG_CACHE / "strom" / "shots"

# Per-game customize choices, keyed by slug: {"final-fantasy-viii": {"music":
# "psx"}}. Only values that differ from the packaged default are stored, so an
# empty (or missing) entry means "launch the plain package".
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "strom"
SETTINGS_FILE = CONFIG_DIR / "settings.json"

# Layout is computed from the actual window (see Layout.of); the only fixed
# thing about a tile is its aspect, which is the aspect of the banner art
# itself (Lutris serves 460x215).
BANNER_ASPECT = 215 / 460

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
    "dolphin": (70, 200, 210),
    "wine": (120, 150, 232),
}

POP_SCALE = 1.08
EASE = 0.18  # 0..1 lerp factor per frame

SHOT_DWELL = 0.5  # seconds a tile stays selected before its slideshow starts
SHOT_HOLD = 3.2  # seconds each screenshot is shown
SHOT_FADE = 0.5  # screenshot cross-fade duration
MAX_SHOTS = 6  # screenshots fetched per game

# --- layout ----------------------------------------------------------------
#
# Every metric below is derived from the window's real size, so the launcher
# lays out for the display it is on rather than rendering a fixed 1920x1080
# canvas and stretching it. Column count follows the width (a phone-ish narrow
# window gets 2, a 2880px panel gets 4), tile height follows the banner aspect,
# and text sizes follow the height. Rebuilt on every resize.


class Layout:
    __slots__ = (
        "w",
        "h",
        "cols",
        "tile_w",
        "tile_h",
        "gap",
        "pop_w",
        "pop_h",
        "row_pitch",
        "top",
        "left",
        "grid_x",
        "foot_y",
        "label_gap",
        "font",
        "small",
        "badge_font",
        "title_font",
        "big_font",
    )

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        # Columns follow the ASPECT, not the raw width: three across is the
        # design at 16:9, a wider window fits more, a portrait one fits fewer.
        # Keying it off width instead made tiles SHRINK on a bigger panel (a
        # 2880x1920 screen got 5 columns of 411px where 1920x1080 had 3 of 460).
        self.cols = max(2, min(5, round(3 * (w / h) / (16 / 9))))
        self.gap = max(12, round(w * 0.019))
        usable = round(w * 0.79)
        self.tile_w = (usable - (self.cols - 1) * self.gap) // self.cols
        self.tile_h = round(self.tile_w * BANNER_ASPECT)
        self.pop_w = round(self.tile_w * POP_SCALE)
        self.pop_h = round(self.tile_h * POP_SCALE)
        # Room under each tile for its label plus a subtitle on the selected one.
        self.label_gap = round(h * 0.046)
        self.row_pitch = self.tile_h + self.gap + self.label_gap
        self.top = round(h * 0.074)
        self.left = round(w * 0.021)
        grid_w = self.cols * self.tile_w + (self.cols - 1) * self.gap
        self.grid_x = (w - grid_w) // 2
        self.foot_y = h - round(h * 0.013)
        self.font = pygame.font.SysFont(None, max(16, round(h * 0.0315)))
        self.small = pygame.font.SysFont(None, max(13, round(h * 0.0222)))
        self.badge_font = pygame.font.SysFont(
            None, max(11, round(h * 0.0185)), bold=True
        )
        self.title_font = pygame.font.SysFont(
            None, max(24, round(h * 0.052)), bold=True
        )
        self.big_font = pygame.font.SysFont(None, max(24, round(h * 0.048)), bold=True)

    @classmethod
    def of(cls, surface: pygame.Surface) -> "Layout":
        return cls(*surface.get_size())


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
                "hero": cat.get("hero"),
                # Player-facing bool/enum knobs this game declares, already
                # resolved to {key,kind,label,help,default,choices} by
                # lib/mk-game.nix. Empty for almost every game.
                "settings": list(meta.get("settings") or []),
            }
        )
    return games


def fetch_banner(slug: str, hero: str | None = None) -> Path | None:
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
    # An explicit `hero` from metadata.json wins over the slug-derived Lutris
    # URL, matching what the web GUI already does (`e.hero || LUTRIS_BANNER`).
    # Needed whenever a package's slug is not its Lutris slug, which is now a
    # documented, operator-approved possibility.
    url = hero or f"https://lutris.net/games/banner/{slug}.jpg"
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


def load_banner_surface(
    slug: str, hero: str | None, size: tuple[int, int]
) -> pygame.Surface | None:
    """Banner art scaled to `size`. Loaded from the cache file each time rather
    than kept at native size: a resize is rare, and holding ~700 unscaled
    surfaces to save a rescale is the wrong trade."""
    p = fetch_banner(slug, hero)
    if p is None:
        return None
    try:
        img = pygame.image.load(str(p)).convert()
        return pygame.transform.smoothscale(img, size)
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


# --- our window ------------------------------------------------------------
#
# A game does NOT get the screen by asking for it: gamescope is launched
# windowed on purpose, so on a normal sway/wayland desktop our fullscreen
# surface would simply sit on top of the game's tiled window and the operator
# would stare at the grid while the game they started renders underneath. So the
# launcher hands the screen back for the duration of a game: the window is
# destroyed and SDL is re-initialised on the dummy video driver, which keeps the
# event queue (and therefore the Back+Start kill combo and pad hotplug) alive
# with no window at all. Under the gamescope-session kiosk this costs nothing --
# there the game is a client of the session compositor either way.

_SDL_DRIVER = os.environ.get("SDL_VIDEODRIVER")


def open_display() -> pygame.Surface:
    """(Re)create the launcher window at the size the compositor gives us.

    No `SCALED`: the UI lays itself out for whatever surface it gets (see
    Layout), so there is no logical resolution to scale from. A plain resizable
    window is the default because the launcher is an ordinary application on a
    desktop; fullscreen is opt-IN via `STROM_LAUNCHER_FULLSCREEN` for a
    couch/kiosk seat, where taking the whole output is the point."""
    if os.environ.get("STROM_LAUNCHER_FULLSCREEN"):
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    else:
        # Default to most of the desktop without covering it. desktop_sizes()
        # is unavailable on the dummy driver, hence the fallback.
        try:
            dw, dh = pygame.display.get_desktop_sizes()[0]
        except (pygame.error, IndexError):
            dw, dh = 1600, 900
        screen = pygame.display.set_mode(
            (round(dw * 0.8), round(dh * 0.8)), pygame.RESIZABLE
        )
    pygame.display.set_caption("strom")
    return screen


def release_display() -> None:
    """Drop our window (see above). Surfaces stay valid across this -- they are
    software surfaces, not textures bound to the window."""
    pygame.display.quit()
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    pygame.display.init()
    pygame.display.set_mode((1, 1))


def reclaim_display() -> pygame.Surface:
    """Take the screen back after the game exits. Returns the NEW display
    surface; the one held across `release_display` is dead."""
    pygame.display.quit()
    if _SDL_DRIVER is None:
        os.environ.pop("SDL_VIDEODRIVER", None)
    else:
        os.environ["SDL_VIDEODRIVER"] = _SDL_DRIVER
    pygame.display.init()
    return open_display()


# --- launch progress -------------------------------------------------------
#
# The first launch of an uncached game fetches/builds for minutes, and doing
# that with nothing on screen is unacceptable. Rather than invent our own
# progress, reuse nix's: `nix build --log-format internal-json` emits the exact
# activity/result stream that drives nix's own progress bar (start/stop
# activities, done/expected counts, build-log lines). Parse that generically and
# draw it; the same command's `--print-out-paths` then names the binary to exec.

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


# --- per-game settings -----------------------------------------------------
#
# A game may flag bool/enum options of its own as player-facing (`user = true`,
# see lib/mk-option.nix); the flake resolves those into a schema per game and
# the launcher's manifest carries it. Picking a non-default value means building
# a different derivation -- there is no runtime switch for a mod that is an
# overlay lower -- so a customized launch goes through
# `flake.modules.<system>.<slug>.apply`, the same path a hand-written override
# takes.


def load_settings() -> dict:
    data = _read_json(SETTINGS_FILE)
    return {k: v for k, v in data.items() if isinstance(v, dict)}


def save_settings(chosen: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS_FILE.with_suffix(".json.new")
    tmp.write_text(json.dumps(chosen, indent=2, sort_keys=True) + "\n")
    tmp.replace(SETTINGS_FILE)


def prune_settings(chosen: dict, games: list[dict]) -> dict:
    """Drop stored choices the current flake revision no longer offers (a key
    that is gone, a value an enum no longer accepts) and anything that just
    restates the default, so a stale file can never build a bogus expression."""
    schemas = {g["slug"]: {s["key"]: s for s in g["settings"]} for g in games}
    out = {}
    for slug, picked in chosen.items():
        schema = schemas.get(slug, {})
        keep = {}
        for key, value in picked.items():
            spec = schema.get(key)
            if not spec or value == spec["default"]:
                continue
            if spec["kind"] == "bool" and not isinstance(value, bool):
                continue
            if spec["kind"] == "enum" and value not in spec["choices"]:
                continue
            keep[key] = value
        if keep:
            out[slug] = keep
    return out


def _nix_literal(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    # A nix string takes the same escapes as JSON, plus ${...} interpolation.
    return json.dumps(str(value)).replace("${", "\\${")


def build_expr(slug: str, overrides: dict, no_gamescope: bool) -> str:
    """The `--expr` installable for a game with non-default settings.

    mkForce because an override has to win over whatever the recipe's own
    `config` sets, not merely tie with it.

    This needs `--impure`, and only for one reason: `builtins.getFlake` refuses
    an unlocked flake reference in pure evaluation mode, and STROM_FLAKE is
    exactly that -- `github:kraftwerk-gaming/strom` with no rev, or a path to a
    working checkout. The system comes from STROM_SYSTEM (baked in at build
    time) rather than `builtins.currentSystem`, so that is not a second reason.

    `no_gamescope` mirrors what the plain path does by appending
    `.no-gamescope` to the ref: under a gamescope-session kiosk
    (STROM_NO_GAMESCOPE=1) the session compositor already IS gamescope, so the
    game renders into it directly instead of nesting a second one. It is not a
    policy this code invents, and it is the only case where the launcher touches
    an option the player did not pick."""
    args = dict(overrides)
    if no_gamescope:
        args["enableGamescope"] = False
    body = "".join(
        f"  {key} = lib.mkForce {_nix_literal(value)};\n"
        for key, value in sorted(args.items())
    )
    return (
        "let\n"
        f'  flake = builtins.getFlake "{FLAKE_REF}";\n'
        "  lib = flake.inputs.nixpkgs.lib;\n"
        "in\n"
        f"(flake.modules.{SYSTEM}.{slug}.apply {{\n{body}}}).outputs.wrapper\n"
    )


def _game_binary(out_path: str, slug: str) -> str | None:
    """The launchable binary inside a built game's output. `lib/mk-game.nix`
    names it after the game (`bwrap.binName = cfg.name`), so this is a
    construction guarantee, not a guess; fall back to a lone entry in bin/
    rather than picking one arbitrarily."""
    if not out_path:
        return None
    bindir = Path(out_path) / "bin"
    exact = bindir / slug
    if exact.exists():
        return str(exact)
    try:
        entries = sorted(bindir.iterdir())
    except OSError:
        return None
    return str(entries[0]) if len(entries) == 1 else None


def fmt_value(spec: dict, value) -> str:
    if spec["kind"] == "bool":
        return "on" if value else "off"
    return str(value)


def cycle_value(spec: dict, value, step: int):
    if spec["kind"] == "bool":
        return not value
    values = spec["choices"]
    idx = values.index(value) if value in values else 0
    return values[(idx + step) % len(values)]


def wrap_text(font: pygame.font.Font, text: str, width: int) -> list[str]:
    lines: list[str] = []
    cur = ""
    for word in text.split():
        cand = f"{cur} {word}".strip()
        if not cur or font.size(cand)[0] <= width:
            cur = cand
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def settings_view(
    screen: pygame.Surface, game: dict, picked: dict, pads: dict
) -> tuple[str, dict]:
    """Modal per-game customize view. Returns ("launch" | "back", choices),
    where choices holds only the values that differ from the defaults."""
    specs = game["settings"]
    values = {s["key"]: picked.get(s["key"], s["default"]) for s in specs}

    lay = Layout.of(screen)
    bg = make_gradient(lay.w, lay.h)

    def measure():
        """Everything that depends on the window size, so a resize just calls
        this again."""
        title = lay.title_font.render(
            f"{game.get('label', game['slug'])} -- options", True, TEXT
        )
        hint = lay.small.render(
            "D-pad / arrows  move      Left/Right  change      "
            "A / Enter  launch      X  defaults      B / Esc  back",
            True,
            DIM,
        )
        row_h = round(lay.h * 0.054)
        # Selected-row plate. Drawn on its own SRCALPHA surface and blitted:
        # pygame.draw ignores the alpha channel of a colour when the target has
        # no per-pixel alpha, which turned the row into a solid accent block.
        pad = round(lay.w * 0.0125)
        plate = pygame.Surface(
            (lay.w - 2 * (lay.left * 4 - pad), row_h - 6), pygame.SRCALPHA
        )
        pygame.draw.rect(plate, (*ACCENT, 46), plate.get_rect(), border_radius=8)
        pygame.draw.rect(
            plate, (*ACCENT, 120), plate.get_rect(), width=2, border_radius=8
        )
        return title, hint, row_h, pad, plate

    title, hint, row_h, pad, row_hl = measure()
    left = lay.left * 4
    top = round(lay.h * 0.157)
    val_x = lay.w - left
    help_w = lay.w - 2 * left

    def relayout(size: tuple[int, int]) -> None:
        nonlocal lay, bg, title, hint, row_h, pad, row_hl, left, top, val_x, help_w
        screen = pygame.display.set_mode(size, pygame.RESIZABLE)
        lay = Layout.of(screen)
        bg = make_gradient(lay.w, lay.h)
        title, hint, row_h, pad, row_hl = measure()
        left = lay.left * 4
        top = round(lay.h * 0.157)
        val_x = lay.w - left
        help_w = lay.w - 2 * left

    sel = 0
    axis_latch = {0: 0, 1: 0}
    action = "back"
    clock = pygame.time.Clock()
    running = True
    while running:
        # Wait with a timeout rather than indefinitely: the first pass must
        # reach the draw below without an input, and pads need the rescan.
        for ev in [pygame.event.wait(100)] + pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.VIDEORESIZE:
                relayout((ev.w, ev.h))
                screen = pygame.display.get_surface()
            elif ev.type == pygame.KEYDOWN:
                if ev.key in (pygame.K_ESCAPE, pygame.K_BACKSPACE):
                    running = False
                elif ev.key in (pygame.K_DOWN, pygame.K_s):
                    sel = (sel + 1) % len(specs)
                elif ev.key in (pygame.K_UP, pygame.K_w):
                    sel = (sel - 1) % len(specs)
                elif ev.key in (pygame.K_RIGHT, pygame.K_d):
                    key = specs[sel]["key"]
                    values[key] = cycle_value(specs[sel], values[key], 1)
                elif ev.key in (pygame.K_LEFT, pygame.K_a):
                    key = specs[sel]["key"]
                    values[key] = cycle_value(specs[sel], values[key], -1)
                elif ev.key in (pygame.K_r, pygame.K_x):
                    values = {s["key"]: s["default"] for s in specs}
                elif ev.key in (pygame.K_RETURN, pygame.K_SPACE):
                    action = "launch"
                    running = False
            elif ev.type == pygame.JOYHATMOTION:
                hx, hy = ev.value
                if hy:
                    sel = (sel - hy) % len(specs)
                elif hx:
                    key = specs[sel]["key"]
                    values[key] = cycle_value(specs[sel], values[key], hx)
            elif ev.type == pygame.JOYAXISMOTION and ev.axis in (0, 1):
                prev = axis_latch[ev.axis]
                if abs(ev.value) > 0.6 and prev == 0:
                    step = 1 if ev.value > 0 else -1
                    axis_latch[ev.axis] = step
                    if ev.axis == 1:
                        sel = (sel + step) % len(specs)
                    else:
                        key = specs[sel]["key"]
                        values[key] = cycle_value(specs[sel], values[key], step)
                elif abs(ev.value) < 0.3 and prev != 0:
                    axis_latch[ev.axis] = 0
            elif ev.type == pygame.JOYBUTTONDOWN:
                if ev.button == 0:
                    action = "launch"
                    running = False
                elif ev.button == 1:
                    running = False
                elif ev.button == 2:
                    values = {s["key"]: s["default"] for s in specs}
            elif ev.type == pygame.JOYDEVICEADDED:
                _rescan_pads(pads)

        screen.blit(bg, (0, 0))
        screen.blit(title, (left, round(lay.h * 0.056)))
        for i, spec in enumerate(specs):
            y = top + i * row_h
            cur = i == sel
            color = TEXT if cur else DIM
            if cur:
                screen.blit(row_hl, (left - pad, y - round(row_h * 0.14)))
            lab = lay.font.render(spec["label"], True, color)
            screen.blit(lab, (left, y))
            shown = fmt_value(spec, values[spec["key"]])
            if values[spec["key"]] != spec["default"]:
                shown += " *"
            val = lay.font.render(f"<  {shown}  >" if cur else shown, True, color)
            screen.blit(val, val.get_rect(topright=(val_x, y)))

        help_y = top + len(specs) * row_h + round(lay.h * 0.037)
        for line in wrap_text(lay.small, specs[sel]["help"], help_w):
            screen.blit(lay.small.render(line, True, DIM), (left, help_y))
            help_y += round(lay.small.get_height() * 1.15)

        screen.blit(hint, hint.get_rect(midbottom=(lay.w // 2, lay.foot_y)))
        pygame.display.flip()
        clock.tick(30)

    pygame.event.clear()
    defaults = {s["key"]: s["default"] for s in specs}
    return action, {k: v for k, v in values.items() if v != defaults[k]}


def launch_with_fade(
    screen: pygame.Surface, game: dict, overrides: dict | None = None
) -> pygame.Surface:
    """Build the game, hand the screen over to it, take it back when it exits.
    Returns the display surface to keep drawing on -- a NEW one whenever the
    window had to be recreated, so callers must not reuse the one they passed."""
    slug = game["slug"]
    label = game.get("label", slug)
    lay = Layout.of(screen)
    sw, sh = lay.w, lay.h
    big = lay.big_font
    fonts = (big, lay.font, lay.small)
    small = lay.small
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
    no_gamescope = bool(os.environ.get("STROM_NO_GAMESCOPE"))
    overrides = overrides or {}

    # What to build. A customized game is not one of the flake's packaged
    # attributes, so it is addressed as an `apply` expression instead of a ref;
    # both forms are installables, so the command below takes either unchanged.
    if overrides:
        installable = ["--impure", "--expr", build_expr(slug, overrides, no_gamescope)]
    else:
        installable = [
            f"{FLAKE_REF}#{slug}" + (".no-gamescope" if no_gamescope else "")
        ]

    # ONE nix invocation, then exec what it produced. `nix build` is the one
    # that can report progress (`--log-format internal-json` is the same stream
    # nix's own progress bar consumes) and `--print-out-paths` hands back the
    # path, so a following `nix run` would only re-evaluate the identical
    # installable to arrive at the same store path -- ~3s for a trivial game,
    # uncached, since `--impure` turns the eval cache off. Worse, `nix run`
    # re-resolves the ref: an unlocked `github:` STROM_FLAKE could move between
    # the two commands and start a build we never showed progress for.
    state = {
        "headline": "preparing",
        "detail": "",
        "bytes": (0, 0),
        "rc": None,
        "error": "",
    }
    lock = threading.Lock()
    build = [
        "nix",
        "build",
        *installable,
        "--no-link",
        "-L",
        "--log-format",
        "internal-json",
        "--print-out-paths",
    ]
    print(f"+ {' '.join(build)}", file=sys.stderr)
    try:
        proc = subprocess.Popen(
            build,
            start_new_session=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        print("nix not found in PATH", file=sys.stderr)
        pygame.event.clear()
        return screen
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
            return screen
        _draw_progress(screen, fonts, bg, state, lock, t)
        t += clock.tick(30) / 1000.0

    def _fail(err: str) -> None:
        screen.blit(bg, (0, 0))
        t1 = big.render(f"failed to launch {label}", True, (240, 150, 150))
        screen.blit(t1, t1.get_rect(center=(sw // 2, sh // 2 - 30)))
        t2 = small.render(err[:104], True, DIM)
        screen.blit(t2, t2.get_rect(center=(sw // 2, sh // 2 + 30)))
        msg = small.render("any button to continue", True, DIM)
        screen.blit(msg, msg.get_rect(midbottom=(sw // 2, sh - 24)))
        pygame.display.flip()
        held.clear()
        waited = 0
        while waited < 5000:
            for ev in pygame.event.get():
                if ev.type in (pygame.JOYBUTTONDOWN, pygame.KEYDOWN):
                    waited = 5000
            waited += clock.tick(30)
        pygame.event.clear()

    if rc != 0:
        with lock:
            err = state["error"] or state["detail"] or "see journal"
        _fail(err)
        return screen

    # Hand the screen to the game (see release_display), then run it. Hold
    # Back+Start to kill it; the combo still works with no window because the
    # dummy driver keeps SDL's event queue pumping.
    printed = (proc.stdout.read() if proc.stdout else "").strip().splitlines()
    binary = _game_binary(printed[-1] if printed else "", slug)
    if not binary:
        _fail("built game has no launchable binary")
        return screen
    cap = big.render(f"starting {label}", True, TEXT)
    screen.blit(bg, (0, 0))
    screen.blit(cap, cap.get_rect(center=(sw // 2, sh // 2)))
    pygame.display.flip()
    print(f"+ {binary}", file=sys.stderr)
    release_display()
    try:
        # start_new_session so the whole game tree gets its own process group
        # and we can signal all of it, not just the wrapper.
        proc = subprocess.Popen([binary], start_new_session=True)
    except OSError as err:
        print(f"{binary}: {err}", file=sys.stderr)
        pygame.event.clear()
        return reclaim_display()

    held.clear()
    while proc.poll() is None:
        if _poll_kill(held, pads, proc):
            _terminate(proc)
        clock.tick(30)
    _terminate(proc)
    screen = reclaim_display()
    pygame.event.clear()
    return screen


def target_scroll(sel: int, cur: float, lay: Layout) -> float:
    """Keep the selected row inside the viewport, in layout units."""
    row = sel // lay.cols
    tile_y = lay.top + row * lay.row_pitch
    if tile_y - cur < lay.top:
        return float(tile_y - lay.top)
    bottom_pad = lay.top + lay.label_gap
    if tile_y + lay.tile_h - cur > lay.h - bottom_pad:
        return float(tile_y + lay.tile_h - lay.h + bottom_pad)
    return cur


def main() -> int:
    games = load_manifest()
    if not games:
        print("manifest empty", file=sys.stderr)
        return 1

    # Customize choices persist across launches, and across flake revisions
    # that change what a game offers -- hence the prune before first use.
    picked = prune_settings(load_settings(), games)

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

    screen = open_display()
    lay = Layout.of(screen)
    sw, sh = lay.w, lay.h

    # Every surface below is sized from `lay` and rebuilt by relayout() when the
    # window changes size; nothing here assumes a resolution.
    bg = vignette = shadow = pop_shadow = title = None

    # Banner art loads without blocking the grid: a background thread downloads
    # every banner into the cache, and pump_banners() pulls finished ones into
    # surfaces a few per frame from the main loop. Previously this warmed ~700
    # banners synchronously before the event loop, delaying input for minutes.
    banners: dict[str, pygame.Surface] = {}
    banners_pop: dict[str, pygame.Surface] = {}
    banner_queue = [g["slug"] for g in games]
    banner_done: dict[str, bool] = {}

    hero_by_slug = {g["slug"]: g.get("hero") for g in games}

    def _prefetch_banners() -> None:
        for g in games:
            banner_done[g["slug"]] = fetch_banner(g["slug"], g.get("hero")) is not None

    threading.Thread(target=_prefetch_banners, daemon=True).start()

    def pump_banners(budget: int = 6) -> None:
        loaded = 0
        while banner_queue and loaded < budget:
            slug = banner_queue[0]
            if slug not in banner_done:
                break  # prefetch works in order; nothing later is ready yet
            banner_queue.pop(0)
            if banner_done[slug]:
                surf = load_banner_surface(
                    slug, hero_by_slug.get(slug), (lay.tile_w, lay.tile_h)
                )
                if surf:
                    surf = round_surface(surf, 8)
                    banners[slug] = surf
                    banners_pop[slug] = pygame.transform.smoothscale(
                        surf, (lay.pop_w, lay.pop_h)
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
            surfs.append(load_shot_surface(files[len(surfs)], lay.pop_w, lay.pop_h))
            loaded += 1

    badges: dict[str, pygame.Surface] = {}
    labels_dim: dict[str, pygame.Surface] = {}
    labels_sel: dict[str, pygame.Surface] = {}
    subtitles: dict[str, pygame.Surface] = {}
    tuned_badge = dimmer = hint = hint_opts = None

    # Footer legend. The options entry is always present -- only a couple of
    # games in the catalog expose settings, so hiding the entry on the rest
    # means nobody ever discovers it -- and it greys out on a game that has
    # none instead of moving, so the line never reflows under the selection.
    def _legend(options_color: tuple) -> pygame.Surface:
        parts = [
            ("D-pad / arrows  move      A / Enter  launch      ", DIM),
            ("Y / C  options", options_color),
            ("      LB / RB  filter      B / Esc  quit", DIM),
        ]
        rendered = [lay.small.render(text, True, color) for text, color in parts]
        out = pygame.Surface(
            (
                sum(s.get_width() for s in rendered),
                max(s.get_height() for s in rendered),
            ),
            pygame.SRCALPHA,
        )
        x = 0
        for surf in rendered:
            out.blit(surf, (x, 0))
            x += surf.get_width()
        return out

    def rebuild_visuals() -> None:
        """(Re)render everything whose size depends on the window: gradients,
        drop shadows, badges, the per-game text, the legend. Called once at
        startup and again after every resize, so text stays crisp instead of
        being a scaled bitmap."""
        nonlocal bg, vignette, shadow, pop_shadow, title
        nonlocal tuned_badge, dimmer, hint, hint_opts
        bg = make_gradient(lay.w, lay.h)
        vignette = make_vignette(lay.w, lay.h)
        shadow = make_shadow(lay.tile_w, lay.tile_h)
        pop_shadow = make_shadow(lay.pop_w, lay.pop_h)
        title = lay.title_font.render("STROM", True, ACCENT)

        badges.clear()
        for g in games:
            rt = g["runtime"]
            if rt not in badges:
                color = RUNTIME_COLORS.get(rt, (100, 100, 110))
                badges[rt] = make_badge(lay.badge_font, rt, color)
        # Marks a tile whose stored settings differ from the packaged defaults,
        # so it is visible from the grid that this game builds something custom.
        tuned_badge = make_badge(lay.badge_font, "tuned", (226, 160, 70))

        # dim overlay for non-selected tiles
        dim = pygame.Surface((lay.tile_w, lay.tile_h), pygame.SRCALPHA)
        dim.fill((0, 0, 0, 90))
        dimmer = round_surface(dim, 8)

        # Per-game text is pre-rendered: doing it per frame was a large slice of
        # the frame cost with ~700 tiles.
        labels_dim.clear()
        labels_sel.clear()
        subtitles.clear()
        for g in games:
            labels_dim[g["slug"]] = lay.small.render(g["label"], True, DIM)
            labels_sel[g["slug"]] = lay.font.render(g["label"], True, TEXT)
            if g["subtitle"]:
                subtitles[g["slug"]] = lay.small.render(g["subtitle"], True, DIM)

        hint = _legend((62, 65, 78))
        hint_opts = _legend(ACCENT)

    rebuild_visuals()

    def relayout(size: tuple[int, int]) -> None:
        """Adopt a new window size: recompute the layout, re-render everything,
        and drop the art caches so banners and screenshots come back at the new
        tile size instead of being stretched."""
        nonlocal screen, lay, sw, sh, scroll, scroll_tgt
        screen = pygame.display.set_mode(size, pygame.RESIZABLE)
        lay = Layout.of(screen)
        sw, sh = lay.w, lay.h
        rebuild_visuals()
        banners.clear()
        banners_pop.clear()
        banner_queue[:] = [g["slug"] for g in games if banner_done.get(g["slug"])]
        banner_queue.extend(g["slug"] for g in games if g["slug"] not in banner_done)
        shot_surfs.clear()
        scroll = scroll_tgt = target_scroll(sel, 0.0, lay)

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
    # Vertical steps are one grid row, so they follow the current column count.
    KEY_MOVE_H = {
        pygame.K_RIGHT: 1,
        pygame.K_d: 1,
        pygame.K_LEFT: -1,
        pygame.K_a: -1,
    }
    KEY_MOVE_V = {
        pygame.K_DOWN: 1,
        pygame.K_s: 1,
        pygame.K_UP: -1,
        pygame.K_w: -1,
    }

    def key_move(key: int) -> int:
        if key in KEY_MOVE_H:
            return KEY_MOVE_H[key]
        return KEY_MOVE_V.get(key, 0) * lay.cols

    def move(d: int) -> None:
        nonlocal sel, scroll_tgt
        sel = max(0, min(n - 1, sel + d))
        scroll_tgt = target_scroll(sel, scroll_tgt, lay)

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

    def launch(game: dict) -> None:
        # The window is destroyed while the game has the screen, so pick up the
        # surface the launch hands back rather than the one captured above.
        nonlocal screen
        stop_hold()
        screen = launch_with_fade(screen, game, picked.get(game["slug"]))

    def open_options(game: dict) -> None:
        """Customize view for a game that declares settings; a launch from
        inside it uses the choices just made."""
        if not game["settings"]:
            return
        stop_hold()
        action, chosen = settings_view(
            screen, game, picked.get(game["slug"], {}), joysticks
        )
        if chosen:
            picked[game["slug"]] = chosen
        else:
            picked.pop(game["slug"], None)
        save_settings(picked)
        if action == "launch":
            launch(game)

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
            elif ev.type == pygame.VIDEORESIZE:
                relayout((ev.w, ev.h))
            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_ESCAPE:
                    running = False
                elif key_move(ev.key):
                    start_hold(key_move(ev.key))
                elif ev.key == pygame.K_q:
                    cycle_facet(-1)
                elif ev.key == pygame.K_e:
                    cycle_facet(1)
                elif ev.key == pygame.K_c:
                    open_options(view[sel])
                elif ev.key in (pygame.K_RETURN, pygame.K_SPACE):
                    launch(view[sel])
            elif ev.type == pygame.KEYUP:
                if key_move(ev.key):
                    stop_hold(key_move(ev.key))
            elif ev.type == pygame.JOYHATMOTION:
                hx, hy = ev.value
                if hx:
                    start_hold(hx)
                elif hy:
                    start_hold(-hy * lay.cols)
                else:
                    stop_hold()
            elif ev.type == pygame.JOYAXISMOTION:
                if ev.axis in (0, 1):
                    v = ev.value
                    prev = axis_latched[ev.axis]
                    if abs(v) > AXIS_DEAD and prev == 0:
                        step = 1 if v > 0 else -1
                        axis_latched[ev.axis] = step
                        start_hold(step if ev.axis == 0 else step * lay.cols)
                    elif abs(v) < AXIS_DEAD * 0.5 and prev != 0:
                        axis_latched[ev.axis] = 0
                        stop_hold(prev if ev.axis == 0 else prev * lay.cols)
            elif ev.type == pygame.JOYBUTTONDOWN:
                if ev.button == 0:
                    launch(view[sel])
                elif ev.button == 1:
                    running = False
                elif ev.button == 3:
                    open_options(view[sel])
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
        pad = max(6, round(lay.h * 0.008))
        screen.blit(bg, (0, 0))
        screen.blit(title, (lay.left, round(lay.h * 0.026)))
        fac = facets[facet_idx][0]
        fac_txt = lay.font.render(
            f"< {fac} >   ({n})", True, ACCENT if facet_idx else DIM
        )
        screen.blit(
            fac_txt, (lay.w - lay.left - fac_txt.get_width(), round(lay.h * 0.037))
        )

        oy = lay.top - scroll
        pulse = 0.5 + 0.5 * math.sin(t * 3.2)

        # pass 1: non-selected tiles
        for i, g in enumerate(view):
            col, row = i % lay.cols, i // lay.cols
            x = lay.grid_x + col * (lay.tile_w + lay.gap)
            y = oy + row * lay.row_pitch
            if y + lay.tile_h < -lay.tile_h or y > lay.h + lay.tile_h:
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
                    screen,
                    (40, 42, 56),
                    (x, y, lay.tile_w, lay.tile_h),
                    border_radius=8,
                )
                ph = lay.small.render(g["slug"], True, DIM)
                screen.blit(
                    ph,
                    ph.get_rect(center=(x + lay.tile_w // 2, y + lay.tile_h // 2)),
                )

            badge = badges[g["runtime"]]
            screen.blit(badge, (x + lay.tile_w - badge.get_width() - pad, y + pad))
            if picked.get(g["slug"]):
                screen.blit(
                    tuned_badge,
                    (
                        x
                        + lay.tile_w
                        - badge.get_width()
                        - tuned_badge.get_width()
                        - pad * 2,
                        y + pad,
                    ),
                )

            label = labels_dim[g["slug"]]
            screen.blit(
                label,
                label.get_rect(midtop=(x + lay.tile_w // 2, y + lay.tile_h + pad)),
            )

        # pass 2: selected tile on top, popped + glowing
        i = sel
        g = view[sel]
        col, row = i % lay.cols, i // lay.cols
        bx = lay.grid_x + col * (lay.tile_w + lay.gap)
        by = oy + row * lay.row_pitch

        p = pop[i]
        cw = int(lay.tile_w + (lay.pop_w - lay.tile_w) * p)
        ch = int(lay.tile_h + (lay.pop_h - lay.tile_h) * p)
        x = bx - (cw - lay.tile_w) // 2
        y = by - (ch - lay.tile_h) // 2

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
                ph = lay.font.render(g["slug"], True, TEXT)
                screen.blit(ph, ph.get_rect(center=(x + cw // 2, y + ch // 2)))

        badge = badges[g["runtime"]]
        screen.blit(badge, (x + cw - badge.get_width() - pad, y + pad))
        if picked.get(g["slug"]):
            screen.blit(
                tuned_badge,
                (
                    x + cw - badge.get_width() - tuned_badge.get_width() - pad * 2,
                    y + pad,
                ),
            )

        label = labels_sel[g["slug"]]
        screen.blit(
            label,
            label.get_rect(midtop=(bx + lay.tile_w // 2, by + lay.tile_h + pad)),
        )
        sub = subtitles.get(g["slug"])
        if sub:
            screen.blit(
                sub,
                sub.get_rect(
                    midtop=(
                        bx + lay.tile_w // 2,
                        by + lay.tile_h + pad + label.get_height() + pad // 2,
                    )
                ),
            )

        screen.blit(vignette, (0, 0))

        cur_hint = hint_opts if g["settings"] else hint
        screen.blit(cur_hint, cur_hint.get_rect(midbottom=(lay.w // 2, lay.foot_y)))

        pygame.display.flip()

    pygame.quit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
