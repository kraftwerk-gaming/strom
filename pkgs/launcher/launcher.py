#!/usr/bin/env python3
"""Strom couch launcher.

A fullscreen game grid driven by a gamepad. Reads a JSON manifest baked
at build time, fetches Lutris banner art on first run, and shells out to
`nix run` to start the selected game.
"""

import json
import math
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
import pygame  # noqa: E402

MANIFEST = Path(os.environ["STROM_MANIFEST"])
FLAKE_REF = os.environ.get("STROM_FLAKE", "github:kraftwerk-gaming/strom")

XDG_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
BANNER_CACHE = XDG_CACHE / "strom" / "banners"

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


def load_manifest() -> list[dict]:
    data = json.loads(MANIFEST.read_text())
    games = []
    for slug, meta in sorted(data.items()):
        desc = meta.get("description") or slug
        if "(" in desc:
            desc = desc.split("(", 1)[0].strip()
        games.append(
            {
                "slug": slug,
                "label": desc,
                "runtime": meta.get("runtime", "?"),
            }
        )
    return games


def fetch_banner(slug: str) -> Path | None:
    BANNER_CACHE.mkdir(parents=True, exist_ok=True)
    dest = BANNER_CACHE / f"{slug}.jpg"
    if dest.exists():
        return dest
    url = f"https://lutris.net/games/banner/{slug}.jpg"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "strom-launcher/1"})
        with urllib.request.urlopen(req, timeout=5) as r:
            dest.write_bytes(r.read())
        return dest
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


def launch_with_fade(screen: pygame.Surface, slug: str) -> None:
    sw, sh = screen.get_size()
    snap = screen.copy()
    overlay = pygame.Surface((sw, sh), pygame.SRCALPHA)
    font = pygame.font.SysFont(None, 48)
    msg = font.render(f"launching {slug}...", True, TEXT)

    for i in range(18):
        a = int((i / 17) * 220)
        overlay.fill((0, 0, 0, a))
        screen.blit(snap, (0, 0))
        screen.blit(overlay, (0, 0))
        screen.blit(msg, msg.get_rect(center=(sw // 2, sh // 2)))
        pygame.display.flip()
        pygame.time.wait(12)

    pygame.display.iconify()
    cmd = ["nix", "run", f"{FLAKE_REF}#{slug}"]
    print(f"+ {' '.join(cmd)}", file=sys.stderr)
    try:
        subprocess.run(cmd, check=False)
    except FileNotFoundError:
        print("nix not found in PATH", file=sys.stderr)
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

    pygame.init()
    pygame.joystick.init()
    for i in range(pygame.joystick.get_count()):
        pygame.joystick.Joystick(i).init()

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

    # warm cache
    banners: dict[str, pygame.Surface] = {}
    for g in games:
        s = load_banner_surface(g["slug"])
        if s:
            banners[g["slug"]] = round_surface(s, 8)

    # pre-scale popped versions of banners
    pop_w, pop_h = int(TILE_W * POP_SCALE), int(TILE_H * POP_SCALE)
    banners_pop: dict[str, pygame.Surface] = {
        k: pygame.transform.smoothscale(v, (pop_w, pop_h)) for k, v in banners.items()
    }
    pop_shadow = make_shadow(pop_w, pop_h)

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

    sel = 0
    scroll = 0.0
    scroll_tgt = 0.0
    pop = [0.0] * len(games)  # 0..1 lerp per tile
    n = len(games)
    clock = pygame.time.Clock()
    t = 0.0

    AXIS_DEAD = 0.6
    axis_latched = {0: 0, 1: 0}

    def move(d: int) -> None:
        nonlocal sel, scroll_tgt
        sel = max(0, min(n - 1, sel + d))
        scroll_tgt = target_scroll(sel, scroll_tgt, sh)

    grid_w = COLS * TILE_W + (COLS - 1) * TILE_GAP
    ox = (sw - grid_w) // 2

    running = True
    while running:
        dt = clock.tick(60) / 1000.0
        t += dt

        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_ESCAPE:
                    running = False
                elif ev.key in (pygame.K_RIGHT, pygame.K_d):
                    move(1)
                elif ev.key in (pygame.K_LEFT, pygame.K_a):
                    move(-1)
                elif ev.key in (pygame.K_DOWN, pygame.K_s):
                    move(COLS)
                elif ev.key in (pygame.K_UP, pygame.K_w):
                    move(-COLS)
                elif ev.key in (pygame.K_RETURN, pygame.K_SPACE):
                    launch_with_fade(screen, games[sel]["slug"])
            elif ev.type == pygame.JOYHATMOTION:
                hx, hy = ev.value
                if hx:
                    move(hx)
                if hy:
                    move(-hy * COLS)
            elif ev.type == pygame.JOYAXISMOTION:
                if ev.axis in (0, 1):
                    v = ev.value
                    prev = axis_latched[ev.axis]
                    if abs(v) > AXIS_DEAD and prev == 0:
                        step = 1 if v > 0 else -1
                        move(step if ev.axis == 0 else step * COLS)
                        axis_latched[ev.axis] = step
                    elif abs(v) < AXIS_DEAD * 0.5:
                        axis_latched[ev.axis] = 0
            elif ev.type == pygame.JOYBUTTONDOWN:
                if ev.button == 0:
                    launch_with_fade(screen, games[sel]["slug"])
                elif ev.button == 1:
                    running = False
            elif ev.type == pygame.JOYDEVICEADDED:
                pygame.joystick.Joystick(ev.device_index).init()

        # ease
        scroll += (scroll_tgt - scroll) * EASE
        for i in range(n):
            tgt = 1.0 if i == sel else 0.0
            pop[i] += (tgt - pop[i]) * EASE

        # draw
        screen.blit(bg, (0, 0))
        screen.blit(title, (40, 28))

        oy = 80 - scroll
        pulse = 0.5 + 0.5 * math.sin(t * 3.2)

        # pass 1: non-selected tiles
        for i, g in enumerate(games):
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

            label = small.render(g["label"], True, DIM)
            screen.blit(label, label.get_rect(midtop=(x + TILE_W // 2, y + TILE_H + 8)))

        # pass 2: selected tile on top, popped + glowing
        i = sel
        g = games[i]
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

        label = font.render(g["label"], True, TEXT)
        screen.blit(label, label.get_rect(midtop=(bx + TILE_W // 2, by + TILE_H + 10)))

        screen.blit(vignette, (0, 0))

        hint = small.render(
            "D-pad / arrows  move        A / Enter  launch        B / Esc  quit",
            True,
            DIM,
        )
        screen.blit(hint, hint.get_rect(midbottom=(sw // 2, sh - 14)))

        pygame.display.flip()

    pygame.quit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
