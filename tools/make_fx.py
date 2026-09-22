#!/usr/bin/env python3
"""Effect and system sprites: bloom, spark, ring, laser textures, Szuix's shot
and bomb flames, his sigil, the hitbox and focus ring, the boss sigil, and
Ziggy's spell-background veins and horn.

Most are drawn white and tinted at draw time. The flames are the exception
(colour baked in). Pickups are in `tools/make_items.py`.

Usage:
    python tools/make_fx.py
"""
import math
import os
import sys

import numpy as np
from PIL import ImageChops, Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SS = A.SS


# ---------------------------------------------------------------------------
# Light
# ---------------------------------------------------------------------------

def make_bloom(size=128):
    """The soft round glow everything additive is built out of."""
    return A.soft_glow(size, (255, 255, 255), falloff=2.9)


def make_spark(w=34, h=14):
    """A streak pointing right, so `fx_spark` can rotate it to its heading."""
    dx, dy, _ = A.grid(w, h)
    # An ellipse in a stretched metric, brightest at the leading (right) end.
    r = np.hypot(dx / (w / 2.0), dy / (h / 2.0))
    a = np.clip(1 - r, 0, 1) ** 1.5
    lead = np.clip(0.45 + 0.55 * (dx / (w / 2.0) * 0.5 + 0.5), 0, 1)
    body = np.zeros((h, w, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a * lead)


def make_ring(size=256, thick=0.055):
    """A shockwave: a bright annulus with light falling off both ways."""
    _, _, r = A.grid(size, size)
    edge = 0.86
    d = np.abs(r - edge)
    a = np.clip(1 - d / thick, 0, 1) ** 1.6
    # A faint haze inside the ring.
    a = np.maximum(a, np.clip(1 - r / edge, 0, 1) ** 5 * 0.30)
    a = np.where(r >= 1.0, 0, a)
    body = np.zeros((size, size, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a)


def make_laser_body(w=64, h=48):
    """A laser's cross-section, uniform along its length so it stretches to any
    length. The origin is middle-left, so the beam extends forward from the
    point it is drawn at.
    """
    ys = np.arange(h, dtype=np.float32)
    t = np.abs(ys - (h - 1) / 2.0) / ((h - 1) / 2.0)
    prof = np.clip(1 - t, 0, 1) ** 1.9
    prof = prof * 0.55 + np.clip(1 - t / 0.30, 0, 1) ** 2 * 0.45
    a = np.repeat(prof[:, None], w, axis=1)
    body = np.zeros((h, w, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a)


def make_laser_node(size=48):
    return A.soft_glow(size, (255, 255, 255), falloff=2.1)


# ---------------------------------------------------------------------------
# The player's marks
# ---------------------------------------------------------------------------

def _vnoise(xs, ys, grid):
    """Smooth value noise, periodic in both axes of `grid`, so a flame animated
    by scrolling one full period loops seamlessly.
    """
    gh, gw = grid.shape
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx = xs - x0
    fy = ys - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    xa, xb = x0 % gw, (x0 + 1) % gw
    ya, yb = y0 % gh, (y0 + 1) % gh
    top = grid[ya, xa] * (1 - fx) + grid[ya, xb] * fx
    bot = grid[yb, xa] * (1 - fx) + grid[yb, xb] * fx
    return top * (1 - fy) + bot * fy


def _fbm(xs, ys, grids):
    acc, amp, tot, f = 0.0, 1.0, 0.0, 1.0
    for g in grids:
        acc = acc + _vnoise(xs * f, ys * f, g) * amp
        tot += amp
        amp *= 0.5
        f *= 2.0
    return acc / tot


# Szuix's fire, from a tongue's transparent edge to the heart of the ball:
# violet at the edges, azure through the body, cyan-white at the heart.
FLAME_RAMP = [
    (0.00, (40, 10, 110)),
    (0.12, (96, 34, 236)),
    (0.28, (64, 76, 255)),
    (0.46, (34, 146, 255)),
    (0.64, (60, 206, 255)),
    (0.82, (168, 242, 255)),
    (1.00, (255, 255, 255)),
]


def _flame_colour(rho):
    ts = [t for t, _ in FLAME_RAMP]
    cs = np.array([c for _, c in FLAME_RAMP], dtype=np.float32)
    out = np.zeros(rho.shape + (3,), dtype=np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(rho, ts, cs[:, ch])
    return out


def make_flame(w, h, k, n, seed=3, head=0.72, radius=0.60, reach=0.70,
               rag0=0.30, rag1=1.25, heat=1.8, ss=3):
    """One frame of a fireball pointing right: a soft envelope (a ball in
    front, a taper behind) with turbulence subtracted from it, so the edge is
    roughened near the ball and torn into separate licks toward the back. The
    turbulence scrolls back one full period over `n` frames (seamless loop),
    with a little domain warp so the licks curl. Colour is baked in (drawn
    untinted), since a flame is several colours at once.
    """
    W, H = w * ss, h * ss
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    hh = H / 2.0
    # Units of the half-height, origin at the centre of the ball.
    X = (xs - head * W) / hh
    Y = (ys - (H - 1) / 2.0) / hh
    rng = np.random.default_rng(seed)
    grids = [rng.random((4 * 2 ** o, 6 * 2 ** o)).astype(np.float32)
             for o in range(5)]
    ph = k / float(n)
    R = radius
    tail_len = reach * W / hh

    # 0 at the ball, 1 at the furthest a tongue can reach.
    s = np.clip(-X / tail_len, 0, 1)
    # The envelope is wider than the final flame, because the turbulence only
    # ever subtracts.
    wdt = np.where(X > 0, np.sqrt(np.clip(R * R - X * X, 0, None)),
                   R * (1 - s) ** 0.55 * (1 + 0.5 * s))
    shape = np.clip(1 - np.abs(Y) / np.maximum(wdt, 1e-3), 0, 1)
    shape = np.where(X > R, 0, shape)
    shape = shape ** 0.7 * (1 - s) ** 0.30

    px = X * 0.55 + ph * 6.0
    py = Y * 1.4
    warp = _fbm(px * 0.7 + 3.1, py * 0.7 + 1.7, grids[:3]) - 0.5
    turb = _fbm(px + warp * 1.3, py + warp * 0.8, grids) * 0.7 \
        + _fbm(px * 1.9 + ph * 6.0 + 11.0, py * 1.9 + 5.0, grids[:4]) * 0.3
    # Value-noise fbm clusters around 0.5; stretch it to use the whole range.
    turb = np.clip((turb - turb.mean()) / (turb.std() * 2.2), -1, 1)

    amp = rag0 + (rag1 - rag0) * s ** 0.8
    rho = np.clip((shape - (0.5 - 0.5 * turb) * amp)
                  / max(0.3, 1 - 0.15 * rag1), 0, 1)

    # The heart never tears (it sits on the collision point; see `main`).
    core = np.clip(1 - np.hypot(X / (R * 0.42), Y / (R * 0.34)), 0, 1)
    rho = np.maximum(rho, core ** 0.9)

    # `heat` controls how much of the body reaches white: raised to a power so
    # most of the ball is azure and only the heart is white.
    img = A.from_arrays(_flame_colour(rho ** heat),
                        np.clip(rho * 2.4, 0, 1) ** 1.1)
    # A halo from its own alpha.
    halo = img.getchannel("A").filter(ImageFilter.GaussianBlur(ss * 2.4))
    glow = Image.new("RGBA", img.size, (64, 56, 236, 0))
    glow.putalpha(halo.point(lambda v: int(v * 0.36)))
    return A.add(glow, img).resize((w, h), Image.LANCZOS)


PSHOT_FRAMES = 8
PSHOT_W, PSHOT_H = 96, 44
# Where the centre of the ball is, as a fraction of the sprite's width; the
# sprite's origin (see `main`).
FLAME_HEAD = 0.72


def make_pshot_frames():
    """Szuix's shot: his blue fireball, pointing right, eight frames."""
    return [make_flame(PSHOT_W, PSHOT_H, k, PSHOT_FRAMES, head=FLAME_HEAD)
            for k in range(PSHOT_FRAMES)]


WISP_FRAMES = 8
WISP_W, WISP_H = 208, 112


def make_wisp_frames():
    """The bomb's seals and the flames on its sweep: the shot's flame at twice
    the size with more tail and tearing (drawn at that size, not scaled up).
    """
    return [make_flame(WISP_W, WISP_H, k, WISP_FRAMES, seed=17, head=0.70,
                       radius=0.56, reach=0.72, rag0=0.34, rag1=1.45,
                       heat=2.0)
            for k in range(WISP_FRAMES)]


# ---------------------------------------------------------------------------
# Szuix's sigil
# ---------------------------------------------------------------------------

SIGIL_SIZE = 1024


def _glyph(c, x, y, ang, size, code, v, alpha, width):
    """One glyph of Szuix's script, standing on a circle and facing out: a stem
    plus a few strokes, from a small consistent set.
    """
    ca, sa = math.cos(ang), math.sin(ang)

    def P(u, w):
        # u runs outward along the radius, w along the circle
        return (x + ca * u * size - sa * w * size,
                y + sa * u * size + ca * w * size)

    fill = (v, v, v, alpha)
    c.line([P(-0.5, 0), P(0.5, 0)], fill, width)             # the stem
    bits = code
    if bits & 1:
        c.line([P(0.5, 0), P(0.18, 0.30)], fill, width * 0.85)
    if bits & 2:
        c.line([P(0.5, 0), P(0.18, -0.30)], fill, width * 0.85)
    if bits & 4:
        c.line([P(-0.05, 0), P(-0.30, 0.28)], fill, width * 0.85)
    if bits & 8:
        c.line([P(-0.05, 0), P(-0.30, -0.28)], fill, width * 0.85)
    if bits & 16:
        c.line([P(-0.5, -0.22), P(-0.5, 0.22)], fill, width * 0.85)
    if bits & 32:
        cx, cy = P(0.12, 0.0)
        r = size * 0.10
        c.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def make_sigil_frames():
    """Szuix's sigil, the circle the bomb draws, as three layers the game draws
    at different rotations and colours: 0 the rings, ticks and octagram (his
    violet), 1 the script, nodes and sparks (cyan), 2 the emblem at the heart
    (white).
    """
    size = SIGIL_SIZE
    cx = cy = size / 2.0
    ss = 2
    FACE = 190
    LIT = 255

    def ring(cv, r, width, v=FACE, a=255):
        cv.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(v, v, v, a), width=width)

    def polar(r, ang):
        return (cx + math.cos(ang) * r, cy + math.sin(ang) * r)

    # ---- 0: the rings, the ticks and the octagram ---------------------------
    c0 = A.Canvas(size, size, ss=ss)
    ring(c0, 494, 6, LIT)
    ring(c0, 480, 1.6, FACE, 200)
    for i in range(128):
        ang = math.radians(i * 360 / 128.0)
        long = (i % 4 == 0)
        c0.line([polar(480, ang), polar(466 if long else 472, ang)],
                (FACE, FACE, FACE, 220 if long else 150), 2.0 if long else 1.2)
    ring(c0, 438, 2.6, LIT)
    ring(c0, 402, 1.4, FACE, 170)
    # {8/3}: an eight-pointed star joining every third point.
    pts = [polar(402, math.radians(-90 + i * 45)) for i in range(8)]
    for i in range(8):
        c0.line([pts[i], pts[(i + 3) % 8]], (FACE, FACE, FACE, 235), 2.6)
    ring(c0, 254, 2.8, LIT)
    ring(c0, 240, 1.2, FACE, 160)
    # A chain of small links just inside the inner ring.
    for i in range(24):
        r = 16.0
        mx, my = polar(222, math.radians(i * 15.0 + 7.5))
        c0.ellipse([mx - r, my - r, mx + r, my + r],
                   outline=(FACE, FACE, FACE, 150), width=1.3)
    ring(c0, 124, 2.0, FACE, 220)
    img0 = _alpha_only_glow(c0.finish())

    # ---- 1: the script, the nodes and the sparks ---------------------------
    c1 = A.Canvas(size, size, ss=ss)
    # One word written eight times round, matching the octagram's symmetry.
    outer_word = [5, 34, 17, 42, 12]
    inner_word = [21, 10, 49, 6]
    n = 8 * len(outer_word)
    for i in range(n):
        ang = math.radians(-90 + i * 360.0 / n)
        gx, gy = polar(459, ang)
        _glyph(c1, gx, gy, ang, 26, outer_word[i % len(outer_word)],
               LIT, 235, 2.4)
    # An inner line of it, smaller and denser, round the heart.
    n2 = 8 * len(inner_word)
    for i in range(n2):
        ang = math.radians(-90 + (i + 0.5) * 360.0 / n2)
        gx, gy = polar(186, ang)
        _glyph(c1, gx, gy, ang, 16, inner_word[i % len(inner_word)],
               FACE, 220, 1.8)
    # A node on every point of the octagram, and a spark between each pair.
    for i in range(8):
        ang = math.radians(-90 + i * 45)
        nx_, ny_ = polar(402, ang)
        c1.ellipse([nx_ - 13, ny_ - 13, nx_ + 13, ny_ + 13],
                   outline=(LIT, LIT, LIT, 255), width=2.2)
        c1.ellipse([nx_ - 4, ny_ - 4, nx_ + 4, ny_ + 4],
                   fill=(LIT, LIT, LIT, 255))
        sx, sy = polar(420, ang + math.radians(22.5))
        _star4_at(c1, sx, sy, 11, LIT, 240, ang + math.radians(22.5))
    img1 = _alpha_only_glow(c1.finish())

    # ---- 2: the emblem at the heart ----------------------------------------
    c2 = A.Canvas(size, size, ss=ss)
    # The four-pointed star, large, as an outline with a faint fill, and a
    # second one turned 45 degrees inside it.
    for r, waist, rot, a_fill, w in ((232, 0.20, 0, 46, 3.2),
                                     (150, 0.24, 45, 30, 2.2)):
        pts = []
        for i in range(8):
            ang = math.radians(i * 45 - 90 + rot)
            rr = r if i % 2 == 0 else r * waist
            pts.append(polar(rr, ang))
        c2.polygon(pts, fill=(LIT, LIT, LIT, a_fill))
        c2.line(pts + [pts[0]], (LIT, LIT, LIT, 245), w)
    # The heart: rings round a bright point (symmetric like the rest).
    for r, w, a in ((56, 3.0, 245), (40, 1.4, 170)):
        c2.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(LIT, LIT, LIT, a), width=w)
    c2.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(LIT, LIT, LIT, 255))
    for i in range(8):
        dx_, dy_ = polar(90, math.radians(i * 45 + 22.5))
        c2.ellipse([dx_ - 4, dy_ - 4, dx_ + 4, dy_ + 4],
                   fill=(LIT, LIT, LIT, 220))
    img2 = _alpha_only_glow(c2.finish())

    return [img0, img1, img2]


def _star4_at(c, x, y, r, v, alpha, ang, waist=0.18):
    pts = []
    for i in range(8):
        a = ang + math.radians(i * 45)
        rr = r if i % 2 == 0 else r * waist
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    c.polygon(pts, fill=(v, v, v, alpha))


def _alpha_only_glow(img, glow=0.55, radius=5.0):
    """White ink with the value in the alpha, and a soft glow baked round every
    line (the sigil is drawn additively and every stroke should glow).
    """
    r, g, b, a = img.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    val = (np.asarray(lum, dtype=np.float32)
           * np.asarray(a, dtype=np.float32) / 255.0)
    line = Image.fromarray(val.astype(np.uint8), "L")
    halo = line.filter(ImageFilter.GaussianBlur(radius))
    out = np.maximum(val, np.asarray(halo, dtype=np.float32) * glow)
    res = Image.new("RGBA", img.size, (255, 255, 255, 0))
    res.putalpha(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "L"))
    return res


def make_hitbox(size=32):
    """The hitbox marker, drawn by the game at exactly `PLAYER_R * 2`: a ring
    with a dot, since the ring makes the centre easy to find.
    """
    _, _, r = A.grid(size * SS, size * SS)
    outer = np.clip(1 - np.abs(r - 0.78) / 0.20, 0, 1) ** 1.4
    core = np.clip(1 - r / 0.34, 0, 1) ** 1.6
    a = np.clip(outer + core, 0, 1)
    body = np.zeros((size * SS, size * SS, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    # A pink cast on the ring, so it isn't mistaken for a bullet's white core.
    body[..., 1] -= (outer * 90)[...]
    body[..., 2] -= (outer * 40)[...]
    img = A.from_arrays(body, a)
    return img.resize((size, size), Image.LANCZOS)


def make_focus_ring(size=96):
    """The ticked ring shown while focused."""
    cv = A.Canvas(size, size)
    c = size / 2.0
    cv.ellipse([c - size * 0.40, c - size * 0.40, c + size * 0.40, c + size * 0.40],
               outline=(255, 255, 255, 170), width=1.6)
    cv.ellipse([c - size * 0.27, c - size * 0.27, c + size * 0.27, c + size * 0.27],
               outline=(255, 255, 255, 90), width=1.0)
    for i in range(8):
        ang = math.radians(i * 45)
        r0, r1 = size * 0.40, size * 0.49
        cv.line([(c + math.cos(ang) * r0, c + math.sin(ang) * r0),
                 (c + math.cos(ang) * r1, c + math.sin(ang) * r1)],
                fill=(255, 255, 255, 200), width=2.2)
    return cv.finish()


# ---------------------------------------------------------------------------
# The boss sigil
# ---------------------------------------------------------------------------

def make_sigil(size=320):
    """The magic circle under a boss: rings, ticks, glyph marks and two
    triangles, tinted per boss and stretched into an ellipse by the game.
    """
    cv = A.Canvas(size, size)
    c = size / 2.0
    for rad, wid, alpha in ((0.47, 2.4, 190), (0.41, 1.0, 110),
                            (0.28, 1.6, 150), (0.10, 1.0, 90)):
        r = size * rad
        cv.ellipse([c - r, c - r, c + r, c + r],
                   outline=(255, 255, 255, alpha), width=wid)

    # Ticks round the outer ring, and a ring of glyph-like marks inside it.
    for i in range(36):
        ang = math.radians(i * 10)
        r0 = size * (0.44 if i % 3 else 0.41)
        r1 = size * 0.47
        cv.line([(c + math.cos(ang) * r0, c + math.sin(ang) * r0),
                 (c + math.cos(ang) * r1, c + math.sin(ang) * r1)],
                fill=(255, 255, 255, 150), width=1.4)

    rnd = np.random.default_rng(11)
    for i in range(12):
        ang = math.radians(i * 30 + 15)
        rr = size * 0.345
        gx, gy = c + math.cos(ang) * rr, c + math.sin(ang) * rr
        for _ in range(3):
            ox, oy = rnd.uniform(-5, 5), rnd.uniform(-6, 6)
            cv.line([(gx + ox, gy + oy - 4), (gx + ox + rnd.uniform(-3, 3),
                                              gy + oy + 4)],
                    fill=(255, 255, 255, 165), width=1.3)

    # A triangle and its inverse.
    for turn in (0, 60):
        pts = [(c + math.cos(math.radians(turn + i * 120)) * size * 0.28,
                c + math.sin(math.radians(turn + i * 120)) * size * 0.28)
               for i in range(3)]
        cv.polygon(pts + [pts[0]], outline=(255, 255, 255, 110))

    return cv.finish()


# ---------------------------------------------------------------------------
# Spell backgrounds
#
# **A spell background is drawn in code and these are the pieces it is drawn
# out of.** A painted background per spell is a 1920x1080 sprite per spell,
# eleven of them for one boss and a texture page nobody can budget -- so what
# ships is a handful of tintable, tileable *motifs* and a function per boss
# that arranges them. A new boss costs one function and, if it wants one, one
# motif; it does not cost a background.
#
# Both of these are white-on-transparent and are drawn additively and tinted at
# run time, which is what lets one sprite serve a red imp and, later, a violet
# vampire.
# ---------------------------------------------------------------------------

def make_spell_veins(size=1024, seed=9):
    """Cracks radiating from the centre, for Ziggy's spell background (drawn
    centred on his station). Width tapers with distance, and branches fork only
    near the start.
    """
    ss = 2
    S = size * ss
    img = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    c = S / 2.0
    rnd = np.random.default_rng(seed)

    def crack(x, y, ang, reach, wide, depth):
        pts = [(x, y)]
        steps = 16
        for i in range(steps):
            ang += rnd.normal(0, 7)
            step = reach / steps
            x += math.cos(math.radians(ang)) * step
            y += math.sin(math.radians(ang)) * step
            pts.append((x, y))
            # Each segment a little thinner than the last, so the crack dies
            # out.
            w = max(1.0, wide * (1 - i / steps) ** 0.8)
            d.line([pts[-2], pts[-1]], fill=255, width=int(w * ss))
            # Branches, only near the start.
            if depth > 0 and i in (3, 7) and rnd.random() < 0.8:
                crack(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(28, 55),
                      reach * 0.45, wide * 0.55, depth - 1)

    for i in range(26):
        a = i * (360 / 26) + rnd.uniform(-6, 6)
        r0 = S * 0.055
        crack(c + math.cos(math.radians(a)) * r0,
              c + math.sin(math.radians(a)) * r0,
              a, S * rnd.uniform(0.30, 0.48), rnd.uniform(3.0, 7.0), 2)

    # The crack plus a wide bloom, composited into one sprite. The bloom is
    # kept faint because the game draws this about 2600px across, where a
    # stronger bloom washes the field in amber.
    core = img.filter(ImageFilter.GaussianBlur(ss * 1.4))
    wide = img.filter(ImageFilter.GaussianBlur(ss * 16)).point(
        lambda v: int(min(255, v * 2.4)))
    a = ImageChops.lighter(core, wide.point(lambda v: int(v * 0.22)))

    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(a)
    return out.resize((size, size), Image.LANCZOS)


def make_spell_horn(w=640, h=600, seed=4):
    """One horn for Ziggy's spell background, growing from the bottom-left of
    its canvas (its root is the origin, pinned to a bottom corner of the field)
    and curling up and to the right. A spine with a width along it; curvature
    increases along its length. Mostly a bright rim, since a dark shape is
    invisible on the near-black wash.
    """
    ss = 2
    W, H = w * ss, h * ss
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)

    n = 48

    def spine(t):
        return (W * 0.06 + W * 0.86 * t ** 1.45,
                H * 0.97 - H * 0.92 * t ** 0.72)

    inner, outer = [], []
    for i in range(n + 1):
        t = i / n
        px, py = spine(t)
        qx, qy = spine(min(1.0, t + 0.02))
        ang = math.atan2(qy - py, qx - px)
        # Broad at the root, tapering to the tip.
        half = W * 0.19 * (1 - t) ** 1.1 + W * 0.006
        nx, ny = math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2)
        inner.append((px - nx * half, py - ny * half))
        outer.append((px + nx * half, py + ny * half))
    d.polygon(inner + outer[::-1], fill=255)

    # Growth rings.
    ridge = Image.new("L", (W, H), 0)
    rd = ImageDraw.Draw(ridge)
    for i in range(8):
        j = int((0.08 + i * 0.108) * n)
        rd.line([inner[j], outer[j]], fill=255, width=int(ss * 9))

    # Three layers: a dim body, a bright rim on the upper-outer contour, and
    # the growth bands. Drawn additively over the near-black spell wash, the
    # rim is what shows the shape.
    body = mask.filter(ImageFilter.GaussianBlur(ss * 7)).point(
        lambda v: int(v * 0.19))
    lit = ImageChops.subtract(mask, ImageChops.offset(mask, 24 * ss, 22 * ss))
    lit = lit.filter(ImageFilter.GaussianBlur(ss * 4.0))
    bands = ImageChops.multiply(ridge.filter(ImageFilter.GaussianBlur(ss * 4)),
                                mask).point(lambda v: int(v * 0.34))
    a = ImageChops.lighter(ImageChops.lighter(body, lit), bands)

    out = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    out.putalpha(a)
    return out.resize((w, h), Image.LANCZOS)


# The horn's root as a fraction of the sprite's size: the sprite's origin,
# which the game pins to a bottom corner of the field.
HORN_ROOT = (0.06, 0.97)


# ---------------------------------------------------------------------------

def main():
    gm_new.folder("Sprites/fx")
    gm_new.folder("Sprites/ui")

    made = []

    def emit(name, img, origin="center", folder="Sprites/fx", label=None):
        gm_new.sprite(name, [img], origin=origin, folder=folder)
        made.append((label or name, img))

    emit("spr_fx_bloom", make_bloom())
    emit("spr_fx_spark", make_spark())
    emit("spr_fx_ring", make_ring())
    emit("spr_laser_node", make_laser_node())

    body = make_laser_body()
    gm_new.sprite("spr_laser_body", [body], origin=(0, body.height // 2),
                  folder="Sprites/fx")
    made.append(("spr_laser_body", body))

    # The shot's origin is on the ball, not the sprite's centre, so the drawn
    # fire is where the collision point is.
    pshot = make_pshot_frames()
    gm_new.sprite("spr_pshot", pshot,
                  origin=(int(PSHOT_W * FLAME_HEAD), PSHOT_H // 2),
                  folder="Sprites/ui", fps=30.0)
    made.append(("spr_pshot", pshot[0]))
    wisp = make_wisp_frames()
    gm_new.sprite("spr_fx_wisp", wisp,
                  origin=(int(WISP_W * 0.70), WISP_H // 2),
                  folder="Sprites/fx", fps=30.0)
    made.append(("spr_fx_wisp", wisp[0]))
    sigil = make_sigil_frames()
    # Not on the contact sheet (at 1024px it would set every cell's size).
    gm_new.sprite("spr_fx_sigil", sigil, origin="center", folder="Sprites/fx")

    # The animated ones get sheets of their own.
    A.preview([f.resize((f.width * 3, f.height * 3), Image.LANCZOS)
               for f in pshot], os.path.join(A.PREVIEW, "pshot.png"),
              cols=4, bg=(12, 12, 22))
    A.preview(wisp, os.path.join(A.PREVIEW, "wisp.png"), cols=4,
              bg=(12, 12, 22))
    tints = (A.SIGIL, A.RUNE, (236, 230, 255))
    layered = Image.new("RGBA", sigil[0].size, (10, 8, 20, 255))
    for img, tint in zip(sigil, tints):
        lit = Image.new("RGBA", img.size, A.rgba(tint, 0))
        lit.putalpha(img.getchannel("A"))
        layered = A.add(layered, lit)
    layered.resize((768, 768), Image.LANCZOS).save(
        os.path.join(A.PREVIEW, "sigil.png"))
    emit("spr_hitbox", make_hitbox(), folder="Sprites/ui")
    emit("spr_focus_ring", make_focus_ring(), folder="Sprites/ui")
    emit("spr_boss_sigil", make_sigil(), folder="Sprites/fx")
    emit("spr_spell_veins", make_spell_veins(), folder="Sprites/fx")
    # Origin at the root of the horn (pinned to a corner of the field).
    horn = make_spell_horn()
    gm_new.sprite("spr_spell_horn", [horn],
                  origin=(int(horn.width * HORN_ROOT[0]),
                          int(horn.height * HORN_ROOT[1])),
                  folder="Sprites/fx")
    made.append(("spr_spell_horn", horn))

    A.preview([i for _, i in made],
              os.path.join(A.PREVIEW, "fx.png"),
              cols=5, bg=(26, 28, 42),
              labels=[n.replace("spr_", "") for n, _ in made])
    print("fx: %d sprites" % len(made))


if __name__ == "__main__":
    main()
