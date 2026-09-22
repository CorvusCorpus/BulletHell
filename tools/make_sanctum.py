#!/usr/bin/env python3
"""The Archives of Bequeathed Memories: the surfaces of Mika's hall.

Stage three is a room: two walls of shelving and a marble floor receding to
one point, open to the night sky. `scripts/bg_sanctum` builds it in 3D from
the materials made here, plus the things that stand in it and the sky.

- The marble and shelving are near black, with gold as hairline inlay and
  mouldings rather than area, so the scenery doesn't share hue and value
  with Mika's gold, amber and bone bullets.
- Lights and figures ship with a second layer drawn additively: `_lit` for
  a light (the orbs, the lamps, the chamber's windows) and `_rim` for the
  light on a figure.
- A projecting edge (cornice, shelf board, plinth, inlay) is a lit top over
  a shadowed underside (`moulding`).

Usage:
    python tools/make_sanctum.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as A
import gm_new

SS = 2

# The hall's palette: dark but saturated (a deep indigo at the value of a
# neutral grey costs the bullets no contrast).
VOID      = (7, 7, 11)
STONE     = (21, 21, 29)
STONE_LIT = (38, 38, 50)
MARBLE    = (12, 12, 18)
MARBLE_LT = (30, 31, 42)
# the runner down the middle of the nave, a shade under the marble either
# side of it: the player lives over this one, so it is the darkest
# surface in the hall
OBSIDIAN  = (8, 8, 13)
GILT      = (188, 146, 60)
GILT_HOT  = (255, 233, 166)
GILT_DIM  = (96, 72, 30)
GILT_DARK = (44, 33, 14)
PARCH     = (212, 198, 168)
ORB       = (120, 186, 255)
ORB_HOT   = (222, 240, 255)
CREST_RED = (94, 20, 24)
# the dark disc set inside the crest's ring
CREST_EYE = (15, 8, 10)
NAVY      = (16, 17, 38)
# The statues, as three stops of one material: polished stone is the distance
# between its shaded and lit faces, plus a narrower, cooler specular. Gold is
# the same three stops opened further, with a wider highlight.
CAT_DARK  = (9, 9, 13)
CAT_LIT   = (54, 56, 70)
CAT_SPEC  = (138, 152, 184)
AU_DARK   = (36, 26, 10)
AU_LIT    = (206, 164, 74)
AU_SPEC   = (255, 238, 182)

# One bay of shelving, and one square of floor. The nearest wall quad covers
# most of the field's height, so anything much smaller here is visibly soft.
WALL_W, WALL_H = 512, 1024
FLOOR_N = 512

# The chamber's half-width on screen, in design pixels. The painting's
# perspective is computed from it, so it must match the size the card is hung
# at; `check_rotunda_scale_agrees` derives that from `HALL_ROT_HW`,
# `HALL_ROT_Z` and the lens and checks the two agree.
HALL_ROT_HW_SCREEN = 401.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def canvas(w, h, col=(0, 0, 0)):
    """A drawing surface for colour only (RGB).

    `ImageDraw.Draw(im, "RGBA")` replaces the destination pixel, alpha
    included, rather than compositing, so a translucent fold painted on an RGBA
    sprite punches a hole in it. Colour is drawn on an RGB surface, where
    translucent calls blend as intended, and the silhouette is carried
    separately as a mask.
    """
    im = Image.new("RGB", (w * SS, h * SS), col[:3])
    return im, ImageDraw.Draw(im, "RGBA")


def mask(w, h):
    """The companion silhouette. Drawn only with hard, opaque shapes."""
    im = Image.new("L", (w * SS, h * SS), 0)
    return im, ImageDraw.Draw(im)


def down(im, w, h):
    return im.resize((w, h), Image.LANCZOS)


def solid(im, w, h):
    """A full-bleed tile: every pixel is material, so the alpha is all one."""
    out = down(im, w, h).convert("RGBA")
    out.putalpha(255)
    return out


def cut(im, mk, w, h):
    """Colour plus silhouette, downsampled together."""
    out = down(im, w, h).convert("RGBA")
    out.putalpha(down(mk, w, h))
    return out


class Tee:
    """Draw to the colour surface and to the silhouette at the same time.

    Every call is forwarded twice: to the RGB canvas as written, and to the
    mask with its fill and outline forced opaque. So the silhouette is the
    union of every mark the prop makes, and a translucent fold contributes its
    shape to the outline but only its shading to the colour. Props need this; a
    tile is material edge to edge.
    """

    def __init__(self, dc, dm):
        self._dc = dc
        self._dm = dm

    def __getattr__(self, name):
        _fc = getattr(self._dc, name)
        _fm = getattr(self._dm, name)

        def call(*a, **k):
            _fc(*a, **k)
            km = dict(k)
            if km.get("fill") is not None:
                km["fill"] = 255
            if km.get("outline") is not None:
                km["outline"] = 255
            _fm(*a, **km)
        return call


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def moulding(d, x0, y0, x1, y1, lit=GILT, shade=GILT_DARK, t=1):
    """A projecting band: a lit top edge over a shadowed underside."""
    s = SS
    d.rectangle([x0, y0, x1, y1], fill=rgba(shade, 255))
    d.rectangle([x0, y0, x1, y0 + t * s], fill=rgba(lit, 255))
    d.rectangle([x0, y1 - t * s, x1, y1], fill=(0, 0, 0, 190))


def spline(pts, n=16, closed=True):
    """Catmull-Rom through the control points, for curved outlines such as a
    cat's back (a polygon through the same points reads as faceted).
    """
    p = list(pts)
    m = len(p)
    out = []
    for i in (range(m) if closed else range(m - 1)):
        p0 = p[(i - 1) % m] if closed else p[max(0, i - 1)]
        p1 = p[i]
        p2 = p[(i + 1) % m] if closed else p[min(m - 1, i + 1)]
        p3 = p[(i + 2) % m] if closed else p[min(m - 1, i + 2)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append((
                0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
                0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)))
    return out


def bow(p0, p1, sag, n=16):
    """A quadratic arc from `p0` to `p1`, sagging by `sag` in the middle: the
    near half of a ring round a tube, seen in profile.
    """
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + sag
    out = []
    for k in range(n + 1):
        t = k / n
        a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        out.append((a * p0[0] + b * mx + c * p1[0],
                    a * p0[1] + b * my + c * p1[1]))
    return out


def grain(im, amount=4, seed=1):
    r = np.random.default_rng(seed)
    a = np.asarray(im).astype(np.float32)
    n = r.normal(0, amount, (a.shape[0], a.shape[1], 1))
    a[..., :3] += n
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), im.mode)


def veining(d, w, h, seed, n=48, col=MARBLE_LT):
    """Marble. Multi-scale, because one scale of wander is a scribble."""
    r = np.random.default_rng(seed)
    for _ in range(n):
        x, y = r.uniform(0, w), r.uniform(0, h)
        ang = r.uniform(0, 6.283)
        wide = r.random() < 0.25
        pts = [(x, y)]
        for _ in range(int(r.integers(14, 30))):
            ang += r.normal(0, 0.34 if wide else 0.62)
            x += math.cos(ang) * r.uniform(5, 18) * SS
            y += math.sin(ang) * r.uniform(5, 18) * SS
            pts.append((x, y))
        a = int(r.uniform(22, 74) * (1.5 if wide else 1.0))
        d.line(pts, fill=rgba(col, min(255, a)),
               width=max(1, int(r.integers(1, 4 if wide else 2)) * SS))


def glyph_run(d, cx, y0, y1, w, seed, col=GILT, alpha=200):
    """A cartouche of invented hieroglyphs: marks rather than letters, since at
    the size a pilaster is read only the rhythm of small bright shapes
    survives.
    """
    r = np.random.default_rng(seed)
    s = SS
    d.rectangle([cx - w / 2, y0, cx + w / 2, y1], fill=(0, 0, 0, 150))
    d.rectangle([cx - w / 2, y0, cx + w / 2, y1],
                outline=rgba(GILT_DIM, 170), width=s)
    y = y0 + 5 * s
    while y < y1 - 9 * s:
        h = int(r.integers(8, 17)) * s
        gw = w * r.uniform(0.34, 0.64)
        k = int(r.integers(0, 6))
        if k == 0:
            d.ellipse([cx - gw / 2, y + h * 0.22, cx + gw / 2, y + h * 0.78],
                      outline=rgba(col, alpha), width=s)
            d.ellipse([cx - gw * 0.14, y + h * 0.40, cx + gw * 0.14,
                       y + h * 0.60], fill=rgba(col, alpha))
        elif k == 1:
            for i in range(int(r.integers(2, 4))):
                yy = y + h * (0.22 + 0.26 * i)
                d.rectangle([cx - gw / 2, yy, cx + gw / 2, yy + s],
                            fill=rgba(col, alpha))
        elif k == 2:      # ankh
            d.ellipse([cx - gw * 0.30, y, cx + gw * 0.30, y + h * 0.44],
                      outline=rgba(col, alpha), width=s)
            d.rectangle([cx - s * 0.6, y + h * 0.38, cx + s * 0.6, y + h],
                        fill=rgba(col, alpha))
            d.rectangle([cx - gw * 0.44, y + h * 0.54, cx + gw * 0.44,
                         y + h * 0.54 + s], fill=rgba(col, alpha))
        elif k == 3:      # seated figure
            d.polygon([(cx - gw / 2, y + h), (cx, y), (cx + gw / 2, y + h)],
                      outline=rgba(col, alpha))
        elif k == 4:      # feather
            d.line([(cx, y), (cx, y + h)], fill=rgba(col, alpha), width=s)
            for i in range(4):
                yy = y + h * (0.2 + i * 0.2)
                d.line([(cx, yy), (cx + gw * 0.42, yy - h * 0.08)],
                       fill=rgba(col, alpha), width=s)
        else:             # water
            pts = [(cx - gw / 2 + gw * i / 8.0,
                    y + h * (0.5 + 0.28 * math.sin(i * 1.5 + k)))
                   for i in range(9)]
            d.line(pts, fill=rgba(col, alpha), width=s)
        y += h + int(r.integers(4, 8)) * s


# ---------------------------------------------------------------------------
# The wall: one bay of shelving, drawn flat
#
# Only the preview sheet draws a whole bay now; the hall builds its walls in
# 3D from the materials further down (`books` is shared with them). Half a
# pilaster at each edge, so tiled bays make whole pilasters on the joins.
# ---------------------------------------------------------------------------
# Book bindings: dark, with a little gilt.
BOOK_COLS = [(46, 20, 22), (22, 28, 52), (40, 33, 20), (17, 34, 31),
             (52, 40, 22), (28, 18, 36), (36, 24, 26), (20, 22, 30)]


def books(d, x0, x1, y0, y1, seed):
    """One shelf of spines: each gets a value, two or three gilt bands,
    sometimes a label block, and sometimes a lean.
    """
    r = np.random.default_rng(seed)
    s = SS
    x = x0
    while x < x1 - 4 * s:
        w = int(r.integers(6, 17)) * s
        if x + w > x1:
            w = int(x1 - x)
        if w < 3 * s:
            break
        h = (y1 - y0) * r.uniform(0.70, 0.99)
        top = y1 - h
        base = BOOK_COLS[int(r.integers(0, len(BOOK_COLS)))]
        v = r.uniform(0.62, 1.30)
        col = tuple(int(min(255, c * v)) for c in base)
        lean = r.random() < 0.10
        if lean and w > 5 * s:
            d.polygon([(x, y1), (x + w, y1), (x + w - w * 0.5, top),
                       (x - w * 0.5, top)], fill=rgba(col, 255))
        else:
            d.rectangle([x, top, x + w - s, y1], fill=rgba(col, 255))
            # the spine is round: a lit edge and a shadowed one
            d.rectangle([x, top, x + s, y1],
                        fill=(255, 255, 255, 26))
            d.rectangle([x + w - 2 * s, top, x + w - s, y1],
                        fill=(0, 0, 0, 70))
        for band in range(int(r.integers(1, 4))):
            by = top + h * r.uniform(0.12, 0.88)
            d.rectangle([x + s, by, x + w - 2 * s, by + max(1, int(s * 0.7))],
                        fill=rgba(GILT_DIM, int(r.uniform(110, 215))))
        if r.random() < 0.3 and w > 9 * s and h > 26 * s:
            ly = top + h * 0.30
            d.rectangle([x + s * 1.5, ly, x + w - 2.5 * s, ly + h * 0.15],
                        fill=rgba(GILT_DARK, 190))
        x += w
    # the recess is dark at the top and the books cast into it
    d.rectangle([x0, y0, x1, y0 + (y1 - y0) * 0.34], fill=(0, 0, 0, 120))


def wall_bay(kind):
    """One bay. `kind` 0 shelves, 1 shelves with a ladder, 2 an alcove."""
    im, d = canvas(WALL_W, WALL_H, STONE)
    W, H = WALL_W * SS, WALL_H * SS
    s = SS
    em, ed = canvas(WALL_W, WALL_H, (0, 0, 0))

    pil = 30 * s                      # half-width of a pilaster
    ix0, ix1 = pil, W - pil           # the bay's interior

    # --- the ground: a value ramp down the wall -------------------------
    # The cornice goes into the dark. Drawn first, so every moulding sits in
    # it.
    for y in range(0, H, 2 * s):
        t = y / H
        k = 0.22 + 0.78 * (1.0 - abs(t - 0.62) / 0.62) ** 1.5
        d.rectangle([0, y, W, y + 2 * s], fill=(0, 0, 0, int(185 * (1 - k))))

    # --- the interior ----------------------------------------------------
    top, bot = H * 0.115, H * 0.845
    if kind == 2:
        # The alcove: a deep recess with an arched head, a plinth and an orb
        # on it. The orb is the one bright thing on the wall, so it is in the
        # emissive.
        d.rectangle([ix0, top, ix1, bot], fill=(4, 4, 7, 255))
        d.pieslice([ix0, top - (ix1 - ix0) * 0.5, ix1, top + (ix1 - ix0) * 0.5],
                   180, 360, fill=(4, 4, 7, 255))
        d.arc([ix0, top - (ix1 - ix0) * 0.5, ix1, top + (ix1 - ix0) * 0.5],
              180, 360, fill=rgba(GILT_DIM, 235), width=2 * s)
        d.rectangle([ix0, top, ix0 + 2 * s, bot], fill=rgba(GILT_DIM, 220))
        d.rectangle([ix1 - 2 * s, top, ix1, bot], fill=rgba(GILT_DIM, 220))
        cx = (ix0 + ix1) / 2
        # the plinth
        d.polygon([(cx - W * 0.17, bot), (cx + W * 0.17, bot),
                   (cx + W * 0.14, bot - H * 0.20),
                   (cx - W * 0.14, bot - H * 0.20)], fill=(15, 15, 21, 255))
        moulding(d, cx - W * 0.18, bot - H * 0.215, cx + W * 0.18,
                 bot - H * 0.195, t=1.2)
        # the orb in its gilt claw
        oy = bot - H * 0.30
        orad = W * 0.105
        for i in range(3):
            rr = orad * (1 + i * 0.10)
            d.ellipse([cx - rr, oy - rr, cx + rr, oy + rr],
                      outline=rgba(GILT, 230 - i * 60), width=int(2.2 * s))
        d.ellipse([cx - orad * 0.86, oy - orad * 0.86, cx + orad * 0.86,
                   oy + orad * 0.86], fill=(24, 38, 70, 255))
        ed.ellipse([cx - orad * 0.80, oy - orad * 0.80, cx + orad * 0.80,
                    oy + orad * 0.80], fill=rgba(ORB, 255))
        ed.ellipse([cx - orad * 0.40, oy - orad * 0.40, cx + orad * 0.40,
                    oy + orad * 0.40], fill=rgba(ORB_HOT, 255))
        glyph_run(d, cx, top + H * 0.02, top + H * 0.20, W * 0.13, 900)
    else:
        n = 6
        sh = (bot - top) / n
        for i in range(n):
            sy0 = top + i * sh
            sy1 = sy0 + sh
            d.rectangle([ix0, sy0, ix1, sy1], fill=(8, 8, 12, 255))
            books(d, ix0 + 4 * s, ix1 - 4 * s, sy0 + 4 * s, sy1 - 6 * s,
                  200 + kind * 31 + i)
            # the board: it projects, so it is a moulding like everything else
            moulding(d, ix0 - 3 * s, sy1 - 6 * s, ix1 + 3 * s, sy1,
                     lit=(96, 88, 78), shade=(34, 31, 30), t=1.2)
        # the case's own frame
        d.rectangle([ix0 - 3 * s, top, ix0, bot], fill=rgba(STONE_LIT, 255))
        d.rectangle([ix1, top, ix1 + 3 * s, bot], fill=rgba(STONE_LIT, 255))
        if kind == 1:
            lx = ix0 + (ix1 - ix0) * 0.58
            for rail in (0, 20 * s):
                d.line([(lx + rail, top), (lx + rail - 7 * s, bot)],
                       fill=rgba(GILT_DIM, 240), width=3 * s)
            for r_ in range(12):
                t_ = r_ / 11.0
                yy = top + (bot - top) * t_
                d.line([(lx - 7 * s * t_, yy), (lx + 20 * s - 7 * s * t_, yy)],
                       fill=rgba(GILT_DIM, 205), width=2 * s)
        # a reading lamp bracketed on the case, on every bay
        cx = ix0 + (ix1 - ix0) * (0.18 if kind == 0 else 0.84)
        ly = top + (bot - top) * 0.47
        d.line([(cx, ly), (cx, ly + 16 * s)], fill=rgba(GILT, 220),
               width=int(1.6 * s))
        d.ellipse([cx - 11 * s, ly - 11 * s, cx + 11 * s, ly + 11 * s],
                  fill=(22, 34, 62, 255), outline=rgba(GILT, 235),
                  width=int(1.8 * s))
        ed.ellipse([cx - 8 * s, ly - 8 * s, cx + 8 * s, ly + 8 * s],
                   fill=rgba(ORB, 255))
        ed.ellipse([cx - 4 * s, ly - 4 * s, cx + 4 * s, ly + 4 * s],
                   fill=rgba(ORB_HOT, 255))

    # --- the pilasters ---------------------------------------------------
    # Half at each edge, so tiling makes whole ones on the joins.
    for px in (0, W):
        d.rectangle([px - pil, 0, px + pil, H], fill=rgba(STONE, 255))
        # the shaft is modelled: lit on one side, shadowed on the other
        d.rectangle([px - pil, 0, px - pil + 5 * s, H], fill=(0, 0, 0, 120))
        d.rectangle([px + pil - 5 * s, 0, px + pil, H], fill=(0, 0, 0, 120))
        d.rectangle([px - pil * 0.34, 0, px + pil * 0.16, H],
                    fill=rgba(STONE_LIT, 90))
        glyph_run(d, px, H * 0.155, H * 0.80, pil * 1.05, 500 + px + kind)
        # capital and base
        moulding(d, px - pil * 1.18, H * 0.095, px + pil * 1.18, H * 0.125,
                 t=1.4)
        moulding(d, px - pil * 1.18, H * 0.825, px + pil * 1.18, H * 0.855,
                 t=1.4)

    # --- cornice and plinth ----------------------------------------------
    d.rectangle([0, 0, W, H * 0.085], fill=rgba(VOID, 255))
    moulding(d, 0, H * 0.062, W, H * 0.092, t=1.6)
    moulding(d, 0, H * 0.030, W, H * 0.048, lit=GILT_DIM, shade=(24, 20, 12),
             t=1.0)
    d.rectangle([0, H * 0.855, W, H], fill=(13, 13, 18, 255))
    moulding(d, 0, H * 0.855, W, H * 0.885, t=1.6)
    moulding(d, 0, H * 0.962, W, H * 0.978, lit=GILT_DIM, shade=(24, 20, 12),
             t=1.0)
    # a dado of inlay along the plinth, which is what ties the wall to the
    # floor's own gold rather than leaving the two to meet at a dark line
    for i in range(7):
        bx = W * (i + 0.5) / 7.0
        d.ellipse([bx - 7 * s, H * 0.905, bx + 7 * s, H * 0.945],
                  outline=rgba(GILT_DIM, 200), width=int(1.4 * s))

    em = em.filter(ImageFilter.GaussianBlur(2.0 * s))
    body = grain(down(im, WALL_W, WALL_H), 3, 5 + kind).convert("RGBA")
    body.putalpha(255)
    lit = down(em, WALL_W, WALL_H).convert("RGBA")
    lit.putalpha(255)
    return body, lit


# ---------------------------------------------------------------------------
# The floor: black marble, gilded
# ---------------------------------------------------------------------------
def floor_tile():
    im, d = canvas(FLOOR_N, FLOOR_N, MARBLE)
    N = FLOOR_N * SS
    s = SS
    veining(d, N, N, 11, n=54)

    # the inlay: a hairline of gold with a dark line inside it, so it reads
    # as let into the stone
    def inlay(box, w=2.0, a=225):
        d.rectangle(box, outline=rgba(GILT, a), width=int(w * s))
        d.rectangle([box[0] + w * s, box[1] + w * s,
                     box[2] - w * s, box[3] - w * s],
                    outline=(0, 0, 0, 150), width=max(1, int(s * 0.7)))

    m = 11 * s
    inlay([m, m, N - m, N - m], 2.4)
    m2 = 30 * s
    d.rectangle([m2, m2, N - m2, N - m2], outline=rgba(GILT_DIM, 180),
                width=s)

    c = N / 2
    # a winged disc at the tile's heart
    d.ellipse([c - 31 * s, c - 31 * s, c + 31 * s, c + 31 * s],
              outline=rgba(GILT, 235), width=int(2.6 * s))
    d.ellipse([c - 15 * s, c - 15 * s, c + 15 * s, c + 15 * s],
              fill=rgba(GILT_DARK, 210))
    d.ellipse([c - 15 * s, c - 15 * s, c + 15 * s, c + 15 * s],
              outline=rgba(GILT, 200), width=int(1.2 * s))
    for sgn in (-1, 1):
        for i in range(6):
            t = i / 5.0
            d.line([(c + sgn * 35 * s, c - 3 * s + i * 3.2 * s),
                    (c + sgn * (35 + 62 * (1 - t * 0.45)) * s,
                     c + (5 + i * 7.4) * s)],
                   fill=rgba(GILT, int(215 - i * 26)), width=int(1.8 * s))
        # the tail feathers under it
        d.line([(c + sgn * 8 * s, c + 22 * s),
                (c + sgn * 16 * s, c + 58 * s)],
               fill=rgba(GILT, 190), width=int(1.6 * s))
    # ankhs at the corners of the field
    for (ax, ay) in ((m2 + 36 * s, m2 + 36 * s), (N - m2 - 36 * s, m2 + 36 * s),
                     (m2 + 36 * s, N - m2 - 36 * s),
                     (N - m2 - 36 * s, N - m2 - 36 * s)):
        d.ellipse([ax - 11 * s, ay - 20 * s, ax + 11 * s, ay + 2 * s],
                  outline=rgba(GILT, 200), width=int(2.0 * s))
        d.rectangle([ax - 2 * s, ay - 1 * s, ax + 2 * s, ay + 22 * s],
                    fill=rgba(GILT, 200))
        d.rectangle([ax - 14 * s, ay + 5 * s, ax + 14 * s, ay + 9 * s],
                    fill=rgba(GILT, 200))

    # a polish: a faint broad sheen, so the stone reads as wet-looking even
    # before the hall's own reflection is laid over it
    sh, shd = mask(FLOOR_N, FLOOR_N)
    shd.ellipse([-N * 0.2, N * 0.1, N * 0.7, N * 0.55], fill=40)
    sh = sh.filter(ImageFilter.GaussianBlur(30 * s))
    a = np.asarray(im).astype(np.float32) + np.asarray(sh)[:, :, None] * 0.45
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    out = grain(down(im, FLOOR_N, FLOOR_N), 3, 7).convert("RGBA")
    out.putalpha(255)
    return out



# ---------------------------------------------------------------------------
# ...and the rest of the pavement
#
# Three courses: a runner down the middle that the player flies along, an
# ornamented border either side of it, and the marble field out at the walls.
# `bg_sanctum` sinks the runner below the other two and faces the step in
# gilt, so the joins converge on the vanishing point. Both tiles here are
# periodic along the hall and not across it.
# ---------------------------------------------------------------------------
def _coil(d, x0, x1, y0, y1, n, col=GILT, a=190, t=1.4):
    """A running spiral frieze: round spirals joined by a wave (the Egyptian
    border, rather than a Greek key).
    """
    s = SS
    w = x1 - x0
    step = (y1 - y0) / n
    r = w * 0.40
    cx = (x0 + x1) * 0.5
    for i in range(n):
        cy = y0 + (i + 0.5) * step
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=rgba(col, a), width=int(t * s))
        d.ellipse([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42,
                   cy + r * 0.42], outline=rgba(col, int(a * 0.8)),
                  width=max(1, int(t * s * 0.7)))
        # The wave joining this coil to the next, sampled as a curve
        # (straight joins read as a chain).
        sgn = 1 if (i % 2 == 0) else -1
        pts = []
        for k in range(21):
            u = k / 20.0
            pts.append((cx + sgn * math.cos(u * math.pi) * w * 0.46,
                        cy + u * step))
        d.line(pts, fill=rgba(col, int(a * 0.85)), width=max(1, int(t * s)))


def _cartouche(d, cx, cy, hw, hh, seed):
    """A name-ring: the motif a processional way is paved with."""
    s = SS
    d.rounded_rectangle([cx - hw, cy - hh, cx + hw, cy + hh],
                        radius=hw, outline=rgba(GILT, 230), width=int(2.2 * s))
    d.rounded_rectangle([cx - hw + 4 * s, cy - hh + 4 * s,
                         cx + hw - 4 * s, cy + hh - 4 * s],
                        radius=hw, outline=rgba(GILT_DIM, 170), width=s)
    # the tie across the foot, which is what makes a ring a cartouche
    d.rectangle([cx - hw * 0.55, cy + hh - 2 * s, cx + hw * 0.55,
                 cy + hh + 3 * s], fill=rgba(GILT, 220))
    glyph_run(d, cx, cy - hh + 13 * s, cy + hh - 13 * s, hw * 1.05, seed,
              col=GILT, alpha=205)


def _winged_disc(d, cx, cy, size, col=GILT, a=215):
    """The sun with its wings out, spread along x for a floor read along z."""
    s = SS
    d.ellipse([cx - size * 0.30, cy - size * 0.30, cx + size * 0.30,
               cy + size * 0.30], outline=rgba(col, a), width=int(2.2 * s))
    d.ellipse([cx - size * 0.14, cy - size * 0.14, cx + size * 0.14,
               cy + size * 0.14], fill=rgba(GILT_DARK, 210))
    for sgn in (-1, 1):
        for i in range(6):
            t = i / 5.0
            d.line([(cx + sgn * size * 0.34, cy - size * 0.03 + i * size * 0.031),
                    (cx + sgn * size * (0.34 + 0.60 * (1 - t * 0.45)),
                     cy + size * (0.05 + i * 0.072))],
                   fill=rgba(col, max(40, a - i * 24)), width=int(1.8 * s))


def runner_tile(w=384, h=512):
    """The processional runner: obsidian, one tile across and many along, with
    everything on it laid out along the direction of flight.
    """
    im, d = canvas(w, h, OBSIDIAN)
    W, H = w * SS, h * SS
    s = SS
    veining(d, W, H, 23, n=20, col=(26, 27, 38))

    # The rules run the whole length unbroken: they are the lines the eye
    # follows to the vanishing point.
    for x in (16 * s, W - 16 * s):
        d.rectangle([x - 2.2 * s, 0, x + 2.2 * s, H], fill=rgba(GILT, 225))
    # the dark line inboard of the bright one: the moulding rule, laid flat,
    # which is what makes an inlay read as let *into* the stone
    for x in (21 * s, W - 22 * s):
        d.rectangle([x, 0, x + s, H], fill=(0, 0, 0, 150))
    for x in (46 * s, W - 46 * s):
        d.rectangle([x - s, 0, x + s, H], fill=rgba(GILT_DIM, 175))

    # the coil frieze, in the channel between the two rules
    _coil(d, 52 * s, 98 * s, 0, H, 8)
    _coil(d, W - 98 * s, W - 52 * s, 0, H, 8)

    # The chain down the middle, periodic in h: cartouches at a quarter and
    # three quarters, and the disc at both ends, so the joint between bays
    # lands on one motif.
    cx = W * 0.5
    d.rectangle([cx - 0.9 * s, 0, cx + 0.9 * s, H], fill=rgba(GILT_DIM, 110))
    _cartouche(d, cx, H * 0.25, 44 * s, 78 * s, 41)
    _cartouche(d, cx, H * 0.75, 44 * s, 78 * s, 42)
    for y in (0, H):
        _winged_disc(d, cx, y, 116 * s)

    # a broad sheen, off centre, so the stone reads as polished
    sh, shd = mask(w, h)
    shd.ellipse([-W * 0.3, H * 0.05, W * 0.8, H * 0.5], fill=32)
    sh = sh.filter(ImageFilter.GaussianBlur(26 * s))
    a = np.asarray(im).astype(np.float32) + np.asarray(sh)[:, :, None] * 0.45
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    return solid(grain(down(im, w, h), 3, 9), w, h)


def border_course(w=96, h=288):
    """The band between the runner and the marble, and the bay's threshold: one
    frieze, used along the hall and across it.
    """
    im, d = canvas(w, h, STONE)
    W, H = w * SS, h * SS
    s = SS
    veining(d, W, H, 31, n=9, col=(30, 31, 42))
    for x in (7 * s, W - 7 * s):
        d.rectangle([x - 1.6 * s, 0, x + 1.6 * s, H], fill=rgba(GILT, 215))
    d.rectangle([11 * s, 0, 12 * s, H], fill=(0, 0, 0, 160))
    d.rectangle([W - 12 * s, 0, W - 11 * s, H], fill=(0, 0, 0, 160))

    # A lotus frieze: an open flower and a closed bud, alternating.
    n = 8
    step = H / n
    cx = W * 0.5
    for i in range(n):
        cy = i * step
        open_ = (i % 2 == 0)
        r = 24 * s if open_ else 15 * s
        a = 205 if open_ else 170
        if open_:
            # the cup, and the petals standing out of it. `d.arc` measures
            # from three o'clock going clockwise, so the *lower* half is
            # 0 to 180 -- the other way round draws a lotus upside down.
            d.arc([cx - r, cy - r * 0.55, cx + r, cy + r * 1.25],
                  0, 180, fill=rgba(GILT, a), width=int(1.7 * s))
            for k, tip in ((-1, 0.74), (0, 1.0), (1, 0.74)):
                d.line([(cx + k * r * 0.20, cy + r * 0.50),
                        (cx + k * r * 0.92, cy - r * tip)],
                       fill=rgba(GILT, a), width=int(1.6 * s))
        else:
            d.ellipse([cx - r * 0.55, cy - r, cx + r * 0.55, cy + r * 0.55],
                      outline=rgba(GILT_DIM, a), width=int(1.4 * s))
            d.line([(cx, cy + r * 0.4), (cx, cy + step * 0.42)],
                   fill=rgba(GILT_DIM, 150), width=int(1.2 * s))
    return solid(grain(down(im, w, h), 3, 13), w, h)


# ---------------------------------------------------------------------------
# The sky
#
# The hall has no roof: over the nave is the night, with the orrery hanging
# in it. All of it is drawn white and tinted at draw time.
# ---------------------------------------------------------------------------
def star_point(kind, n=48):
    """One star: a very small, very bright point inside a faint bloom, at three
    magnitudes (a scaled-up star reads as a disc); the brightest get a
    four-point spike. White with the shape in the alpha, since stars are drawn
    additively and coloured by their vertex tint.
    """
    N = n * SS
    _, _, r = A.grid(N, N)
    core = np.clip(1 - r * (7.0 if kind == 2 else 5.5), 0, 1) ** 1.3
    halo = np.clip(1 - r, 0, 1) ** (4.6 - kind * 0.7)
    a = core + halo * (0.16 + 0.13 * kind)
    if kind == 2:
        dx, dy, _ = A.grid(N, N)
        dx = np.abs(dx) / (N * 0.5)
        dy = np.abs(dy) / (N * 0.5)
        sx = np.clip(1 - dx, 0, 1) ** 2.2 * np.clip(1 - dy * 15, 0, 1) ** 1.1
        sy = np.clip(1 - dy, 0, 1) ** 2.2 * np.clip(1 - dx * 15, 0, 1) ** 1.1
        a = a + (sx + sy) * 0.34
    a = np.clip(a, 0, 1)
    rgb = np.full((N, N, 3), 255.0, np.float32)
    im = Image.fromarray(
        np.clip(np.dstack([rgb, a * 255.0]), 0, 255).astype(np.uint8), "RGBA")
    return im.resize((n, n), Image.LANCZOS)


def nebula(seed, n=256):
    """A patch of the deep sky: two noise fields multiplied, for a mass with
    filaments and gaps. Several are added faintly so the dark isn't uniform.
    """
    N = n * SS
    big = np.asarray(A.fbm_field(N, N, seed, octaves=4, base=3),
                     np.float32) / 255.0
    fine = np.asarray(A.fbm_field(N, N, seed + 91, octaves=5, base=9),
                      np.float32) / 255.0
    _, _, r = A.grid(N, N)
    fall = np.clip(1 - r, 0, 1) ** 2.0
    a = np.clip((big - 0.36) * 2.4, 0, 1) * (0.45 + 0.55 * fine) * fall
    a = np.clip(a, 0, 1) ** 1.25
    rgb = np.full((N, N, 3), 255.0, np.float32)
    im = Image.fromarray(
        np.clip(np.dstack([rgb, a * 210.0]), 0, 255).astype(np.uint8), "RGBA")
    return im.resize((n, n), Image.LANCZOS)


def zodiac_band(w=512, h=56):
    """The graduated band an armillary's rings are made of, drawn as a metal
    section: a dark shadowed edge, a body rising to a hot specular line off
    centre, a fall to a mid tone, and a cooler bounce line. The divisions are
    cut into the body only and stop short of the specular, so the highlight
    runs unbroken.
    """
    W, H = w * SS, h * SS
    # the cross-section, as a value ramp down the band's width
    v = np.linspace(0, 1, H, dtype=np.float32)
    prof = np.interp(v,
                     [0.00, 0.05, 0.14, 0.26, 0.33, 0.46, 0.66, 0.82, 0.90,
                      0.96, 1.00],
                     [0.16, 0.30, 0.72, 0.97, 1.00, 0.74, 0.50, 0.34, 0.58,
                      0.40, 0.14]).astype(np.float32)
    base = np.repeat(prof[:, None], W, axis=1)
    # a slow swell along the limb, so its brightness isn't constant
    x = np.linspace(0, 1, W, dtype=np.float32)
    base = base * (0.90 + 0.10 * np.cos(x * math.pi * 6.0))[None, :]
    rgb = np.dstack([base * 255, base * 251, base * 242])
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im, "RGBA")
    s = SS

    # the divisions, engraved into the body and stopping clear of the light
    n = 24
    for i in range(n):
        px = W * i / n
        if i % 6 == 0:
            d.rectangle([px, H * 0.47, px + 2.4 * s, H * 0.86],
                        fill=(0, 0, 0, 205))
            d.rectangle([px + 2.4 * s, H * 0.47, px + 3.4 * s, H * 0.86],
                        fill=(255, 246, 226, 120))
        elif i % 2 == 0:
            d.rectangle([px, H * 0.49, px + 1.7 * s, H * 0.72],
                        fill=(0, 0, 0, 165))
        else:
            d.rectangle([px, H * 0.51, px + 1.2 * s, H * 0.63],
                        fill=(0, 0, 0, 120))

    # a bead-and-reel at the shadowed edge
    for i in range(n * 2):
        px = W * (i + 0.5) / (n * 2)
        rr = H * 0.055
        d.ellipse([px - rr, H * 0.90 - rr, px + rr, H * 0.90 + rr],
                  fill=(238, 226, 196, 235))
        d.ellipse([px - rr * 0.45, H * 0.90 - rr * 0.45,
                   px + rr * 0.45, H * 0.90 + rr * 0.45],
                  fill=(255, 252, 242, 255))
    out = grain(down(im, w, h), 2, 41).convert("RGBA")
    out.putalpha(255)
    return out


# ---------------------------------------------------------------------------
# The chamber at the end of the hall
# ---------------------------------------------------------------------------
def rotunda(w=1152, h=376):
    """The great round room the corridor flies toward, as one painting hung at
    a fixed depth (two quads), so the nave ends in a destination rather than in
    stars.

    Only the far half of the cylinder is drawn; the near rim would fall inside
    bays the hall already draws. The card is wide and short, to fit between the
    vanishing point and the orrery's skirt. The near arc of a ring above the
    eye is its upper half (drawn the other way, the galleries read as bowls).
    Every value except the lamps is kept under a tenth of white before tinting.
    """
    im, dc = canvas(w, h, (0, 0, 0))
    mk, dm = mask(w, h)
    li, ld = canvas(w, h, (0, 0, 0))
    d = Tee(dc, dm)
    W, H = w * SS, h * SS
    s = SS
    cx = W * 0.5
    # Where the hall's own horizon falls on the card -- see `HALL_ROT_Y0`.
    horiz = H * 0.877
    # Card pixels per design pixel, so the projection below is the real one.
    sc = W / (2.0 * HALL_ROT_HW_SCREEN)
    FOCAL = 894.8
    RHO = 0.42             # the chamber's radius over its distance

    def proj(t, ys):
        """A point on the far half of a ring `ys` design-pixels above the
        eye, at angle `t` degrees from dead ahead."""
        k = 1.0 + RHO * math.cos(math.radians(t))
        return (cx + FOCAL * RHO * math.sin(math.radians(t)) / k * sc,
                horiz - ys / k * sc)

    TH = [(-90 + 180.0 * i / 96) for i in range(97)]

    # --- the floor --------------------------------------------------------
    # It runs from the chamber's far edge down off the bottom of the card.
    floor = [proj(t, -6) for t in TH]
    d.polygon(floor + [(W, H), (0, H)], fill=(16, 17, 22, 255))
    for yy, val in ((-9, 24), (-14, 33), (-21, 44)):
        d.line([proj(t, yy) for t in TH], fill=(val, val, val + 3, 255),
               width=max(1, int(2.0 * s)), joint="curve")
    for t in range(-84, 85, 7):
        p = proj(t, -11)
        rr = 5 * s
        ld.ellipse([p[0] - rr * 3, p[1] - rr, p[0] + rr * 3, p[1] + rr],
                   fill=(46, 38, 24, 255))

    # --- the wall, in tiers of gallery ------------------------------------
    # Big shapes and lights only: finer detail smears at this distance.
    TIERS = 4
    ys = [8 + 60.0 * k for k in range(TIERS + 1)]
    for k in range(TIERS):
        pts = ([proj(t, ys[k]) for t in TH]
               + [proj(t, ys[k + 1]) for t in reversed(TH)])
        v = 13 + k * 2
        d.polygon(pts, fill=(v, v, v + 5, 255))
        # the parapet along its head, which is the one lit line on a tier
        d.line([proj(t, ys[k + 1]) for t in TH],
               fill=(104 - k * 9, 98 - k * 9, 82 - k * 7, 255),
               width=max(1, int(4.0 * s)), joint="curve")
        d.line([proj(t, ys[k + 1] - 5) for t in TH],
               fill=(6, 6, 9, 255), width=max(1, int(2.4 * s)), joint="curve")

        # the openings: a run of lit windows under each parapet
        n = 21 - k * 2
        for i in range(n):
            t = -86 + 172.0 * (i + 0.5) / n
            p0 = proj(t, ys[k + 1] - 26)
            rw = (3.2 - k * 0.3) * s
            val = int(190 - k * 18)
            ld.ellipse([p0[0] - rw, p0[1] - rw * 1.7,
                        p0[0] + rw, p0[1] + rw * 1.7],
                       fill=(val, int(val * 0.80), int(val * 0.48), 255))

    # the piers, standing the whole height so the wall has a structure
    for i in range(13):
        t = -86 + 172.0 * i / 12
        a = proj(t, ys[0] - 6)
        b = proj(t, ys[TIERS])
        hw = 5.0 * s * (1.0 - 0.5 * abs(math.sin(math.radians(t))))
        d.polygon([(a[0] - hw, a[1]), (a[0] + hw, a[1]),
                   (b[0] + hw * 0.7, b[1]), (b[0] - hw * 0.7, b[1])],
                  fill=(8, 8, 12, 255))

    # --- the portal, dead ahead and low -----------------------------------
    # The part of the wedge the player sees most. The arch is dark and the
    # light is inside it.
    pw = FOCAL * RHO * math.sin(math.radians(9.5)) / (1 + RHO) * sc
    pb = proj(0, -4)[1]
    ph = pw * 2.5

    def arch_at(half, top_y, rise):
        pts = [(cx - half, pb), (cx - half, top_y + rise)]
        for i in range(17):
            a = math.pi * i / 16.0
            pts.append((cx - math.cos(a) * half,
                        top_y + rise - math.sin(a) * rise))
        pts.append((cx + half, pb))
        return pts

    d.polygon(arch_at(pw * 1.55, pb - ph * 1.2, pw * 1.55),
              fill=(9, 9, 13, 255))
    # the lit opening, warm and falling off upward into the chamber's depth
    for f, val in ((1.00, 58), (0.86, 96), (0.66, 140), (0.42, 176)):
        ld.polygon(arch_at(pw * f, pb - ph * f, pw * f),
                   fill=(val, int(val * 0.76), int(val * 0.42), 255))
    # something standing in it, so the arch has a scale
    d.polygon([(cx - pw * 0.16, pb), (cx + pw * 0.16, pb),
               (cx + pw * 0.10, pb - ph * 0.55),
               (cx - pw * 0.10, pb - ph * 0.55)], fill=(7, 7, 10, 255))
    # its jambs, so it is cut into the wall rather than painted on it
    for e in (-1, 1):
        d.polygon([(cx + e * pw * 1.55, pb), (cx + e * pw * 1.86, pb),
                   (cx + e * pw * 1.86, pb - ph * 1.1),
                   (cx + e * pw * 1.55, pb - ph * 1.15)],
                  fill=(52, 50, 44, 255))

    # --- and the rim, with what stands on it ------------------------------
    rim = [proj(t, ys[TIERS]) for t in TH]
    d.line(rim, fill=(74, 70, 60, 255), width=max(1, int(3.2 * s)),
           joint="curve")
    for i in range(11):
        t = -82 + 164.0 * i / 10
        p = proj(t, ys[TIERS])
        th = H * (0.052 + 0.034 * abs(math.cos(math.radians(t))))
        hw = 7 * s
        d.polygon([(p[0] - hw, p[1]), (p[0] + hw, p[1]),
                   (p[0] + hw * 0.5, p[1] - th), (p[0] - hw * 0.5, p[1] - th)],
                  fill=(11, 11, 16, 255))
        d.polygon([(p[0] - hw * 0.5, p[1] - th), (p[0] + hw * 0.5, p[1] - th),
                   (p[0], p[1] - th - hw * 1.8)], fill=(40, 36, 30, 255))
        ld.ellipse([p[0] - 3.4 * s, p[1] - th - 3.4 * s,
                    p[0] + 3.4 * s, p[1] - th + 3.4 * s],
                   fill=(168, 140, 92, 255))

    body = cut(im, mk, w, h)
    # The bottom dissolves: in the thin band under the horizon neither the
    # hall's floor nor the chamber is drawn, and a hard edge there would be a
    # ruled line.
    a = np.asarray(body.split()[3]).astype(np.float32)
    ramp = np.clip((np.arange(h)[:, None] - h * 0.90) / (h * 0.08), 0, 1)
    body.putalpha(Image.fromarray(
        np.clip(a * (1 - ramp), 0, 255).astype(np.uint8), "L"))

    lit = down(li, w, h).convert("RGBA")
    la = np.asarray(lit.convert("L")).astype(np.float32)
    lit.putalpha(Image.fromarray(
        np.clip(la * (1 - ramp), 0, 255).astype(np.uint8), "L"))
    return body, lit


# ---------------------------------------------------------------------------
# The things that stand in it
# ---------------------------------------------------------------------------
# The Bastet's outline, in figure coordinates and facing +u (across the
# nave). `hall_bastet` mirrors the card on the far side, so a pair face each
# other. The proportions are a seated Egyptian cat's: a tall column of a
# neck, straight forelegs, and one large rounded haunch.
BASTET_OUTLINE = [
    (0.724, 0.100), (0.760, 0.046),
    (0.806, 0.002), (0.828, 0.014),                   # near ear, tip
    (0.856, 0.056), (0.876, 0.090),
    (0.902, 0.106), (0.920, 0.124),                   # forehead, brow
    (0.948, 0.148), (0.972, 0.168),                   # the bridge
    (0.984, 0.178), (0.988, 0.188),                   # the nose, blunt
    (0.980, 0.199),                                   # the lip
    (0.962, 0.209), (0.948, 0.219),                   # the chin
    (0.916, 0.232), (0.874, 0.252),                   # jaw
    (0.828, 0.276), (0.808, 0.308),                   # throat
    (0.800, 0.352), (0.804, 0.428), (0.801, 0.512),   # chest
    (0.794, 0.620), (0.790, 0.742), (0.792, 0.826),   # foreleg
    (0.806, 0.868), (0.848, 0.888),                   # ankle, toes
    (0.892, 0.902), (0.928, 0.916),
    (0.944, 0.936), (0.946, 0.982), (0.926, 0.999),   # base, front
    (0.500, 1.000),
    (0.064, 0.999), (0.044, 0.982), (0.046, 0.936),
    (0.066, 0.916),                                   # base, rear
    (0.064, 0.856), (0.030, 0.766),                   # rump
    (0.016, 0.664), (0.040, 0.566), (0.104, 0.498),
    (0.198, 0.452), (0.308, 0.410), (0.420, 0.356),   # the back
    (0.502, 0.298), (0.552, 0.244), (0.592, 0.192),   # neck
    (0.616, 0.156), (0.646, 0.126), (0.680, 0.110),
]


# The far ear: only its tip shows, and its base ends inside the skull.
BASTET_FAR_EAR = [
    (0.660, 0.136), (0.688, 0.078), (0.720, 0.034), (0.748, 0.022),
    (0.784, 0.060), (0.816, 0.100), (0.752, 0.132),
]


# The collar's bands, each as the two ends of an arc round the neck.
BASTET_COLLAR = [
    ((0.596, 0.196), (0.868, 0.248)), ((0.584, 0.213), (0.854, 0.260)),
    ((0.570, 0.230), (0.842, 0.270)), ((0.552, 0.248), (0.832, 0.280)),
]


# The light's direction: above, and out of the nave. Mirroring the card
# mirrors it, so both statues are lit from the middle of the room.
BASTET_LIGHT = (0.50, -0.70, 0.51)


def bastet(w=384, h=768):
    """A seated Bastet, in profile, as one card.

    In profile because `hall_bastet` hangs her on a quad facing down the hall,
    so the card shows what faces across the nave, and a pair look at each
    other.

    She is built as a height field, a dome per mass (haunch, ribs, chest, neck,
    skull), lit through its gradient by one lamp. The ornament goes into the
    same field: the collar's bands are raised and the eye, mouth and ear's
    conch are cut in, so the lamp shades them with the body. Gold is a mask
    over that one field, with a wider gap between shaded and lit and a broader
    highlight.

    Returns the figure and its moonward rim: a body and the light on it, tinted
    at draw time.
    """
    W, H = w * SS, h * SS
    size = (W, H)
    fh = 0.94 * H
    fw = 0.50 * fh
    fx = (W - fw) / 2
    fy = 0.03 * H
    s = SS

    def X(u):
        return fx + u * fw

    def Y(v):
        return fy + v * fh

    def pt(p):
        return (X(p[0]), Y(p[1]))

    def sil_of(pts, blur):
        """A silhouette, smoothed. Blur-and-threshold takes the corners
        off the spline's own control points without rounding the ear tips
        away, which a wider spline alone would."""
        im = Image.new("L", size, 0)
        ImageDraw.Draw(im).polygon([pt(p) for p in spline(pts)], fill=255)
        im = im.filter(ImageFilter.GaussianBlur(blur))
        return im.point(lambda v: 255 if v > 128 else 0)

    def lobe(cu, cv, ru, rv, rot=0.0):
        im = Image.new("L", size, 0)
        pts = []
        for k in range(72):
            a = 2 * math.pi * k / 72
            x, y = ru * math.cos(a), rv * math.sin(a)
            pts.append((X(cu + x * math.cos(rot) - y * math.sin(rot)),
                        Y(cv + x * math.sin(rot) + y * math.cos(rot))))
        ImageDraw.Draw(im).polygon(pts, fill=255)
        return im

    body = sil_of(BASTET_OUTLINE, 1.1 * s)
    far_ear = sil_of(BASTET_FAR_EAR, 1.1 * s)
    sil = ImageChops.lighter(body, far_ear)

    # --- the height field: one dome per mass -----------------------------
    hgt = np.zeros((H, W), np.float32)
    lobes = [
        (far_ear, 0.22),
        (lobe(0.500, 0.962, 0.450, 0.038), 0.38),            # the base slab
        (lobe(0.260, 0.660, 0.238, 0.208), 1.00),            # the haunch
        (lobe(0.470, 0.782, 0.240, 0.096, -0.07), 0.58),     # the hind leg
        (lobe(0.590, 0.470, 0.195, 0.150, -0.42), 0.76),     # the ribs
        (lobe(0.762, 0.418, 0.108, 0.128, -0.10), 0.66),     # the chest
        (lobe(0.746, 0.706, 0.056, 0.152), 0.50),            # the foreleg
        (lobe(0.672, 0.258, 0.098, 0.088, -0.62), 0.56),     # the neck
        (lobe(0.836, 0.156, 0.110, 0.050, -0.18), 0.66),     # the skull
        (lobe(0.950, 0.190, 0.032, 0.019, -0.16), 0.40),     # the muzzle
        (lobe(0.800, 0.052, 0.040, 0.050, -0.04), 0.42),     # the near ear
    ]
    # The masses are joined with a smooth union rather than `max`, which
    # would leave a crease where two domes cross.
    k = 0.07
    for m, amp in lobes:
        b = np.sqrt(np.clip(A.depth_field(m), 0, 1)) * amp
        t = np.clip(0.5 + 0.5 * (b - hgt) / k, 0, 1)
        hgt = hgt * (1 - t) + b * t + k * t * (1 - t)
    hgt = np.asarray(
        Image.fromarray((np.clip(hgt, 0, 1) * 255).astype(np.uint8), "L")
        .filter(ImageFilter.GaussianBlur(8.0 * s)), np.float32) / 255.0

    # --- relief: what is cut into the stone and what stands out of it ----
    rel = Image.new("L", size, 128)
    dr = ImageDraw.Draw(rel)
    gold = Image.new("L", size, 0)
    dg = ImageDraw.Draw(gold)

    def ridge(pts, up, wd, gilt=False):
        ln = [pt(p) for p in pts]
        dr.line(ln, fill=up, width=max(1, int(wd * s)), joint="curve")
        if gilt:
            dg.line(ln, fill=255, width=max(1, int(wd * s)), joint="curve")

    # the collar: four raised bands and a row of beads under them, with a
    # groove above and below the lot so the band sits *in* the neck
    ridge(bow((0.602, 0.188), (0.874, 0.242), 0.013), 76, 2.2)
    ridge(bow((0.542, 0.258), (0.826, 0.292), 0.013), 76, 2.2)
    for a, b in BASTET_COLLAR:
        ridge(bow(a, b, 0.013), 190, 3.4, gilt=True)
    for i in range(10):
        t = i / 9.0
        u = 0.538 + t * 0.278
        v = 0.266 + t * 0.028 + 0.026 * math.sin(math.pi * t)
        r = 0.0062
        box = [X(u - r), Y(v - r * 1.9), X(u + r), Y(v + r * 1.9)]
        dr.ellipse(box, fill=208)
        dg.ellipse(box, fill=255)

    # the hoop in the near ear
    hoop = [X(0.800), Y(0.078), X(0.838), Y(0.114)]
    dr.ellipse(hoop, outline=198, width=int(2.6 * s))
    dg.ellipse(hoop, outline=255, width=int(2.6 * s))

    # the eye: cut in, with a lid standing over it, in stone rather than gold
    dr.polygon([pt(p) for p in spline(
        [(0.852, 0.150), (0.878, 0.140), (0.904, 0.148), (0.878, 0.157)])],
        fill=58)
    dr.line([pt(p) for p in spline(
        [(0.848, 0.148), (0.878, 0.137), (0.907, 0.146)], closed=False)],
        fill=200, width=int(1.7 * s), joint="curve")
    # ...and the cosmetic line back from its outer corner, which is the one
    # mark on her that is Egyptian rather than feline
    dr.line([pt(p) for p in ((0.848, 0.150), (0.812, 0.144))],
            fill=78, width=int(1.4 * s))
    # the nose, the mouth, the ear's hollow
    dr.line([pt(p) for p in ((0.972, 0.178), (0.980, 0.186), (0.972, 0.193))],
            fill=56, width=int(1.6 * s), joint="curve")
    dr.line([pt(p) for p in ((0.972, 0.196), (0.952, 0.200))],
            fill=84, width=int(1.4 * s))
    # the ear is a bowl: the conch is cut well in and its two edges stand
    # round it
    dr.polygon([pt(p) for p in spline(
        [(0.762, 0.084), (0.784, 0.046), (0.806, 0.022), (0.826, 0.052),
         (0.834, 0.080), (0.798, 0.092)])], fill=20)
    dr.line([pt(p) for p in spline(
        [(0.752, 0.094), (0.782, 0.042), (0.810, 0.012)], closed=False)],
        fill=214, width=int(2.8 * s), joint="curve")
    dr.line([pt(p) for p in spline(
        [(0.816, 0.014), (0.840, 0.052), (0.860, 0.086)], closed=False)],
        fill=206, width=int(2.8 * s), joint="curve")
    # the far ear gets no hollow; only its tip shows

    # the tail, lying round the near side of the base
    ridge(spline([(0.098, 0.842), (0.126, 0.882), (0.250, 0.901),
                  (0.430, 0.906), (0.610, 0.901), (0.712, 0.890),
                  (0.744, 0.872)], closed=False), 178, 4.0)
    for i in range(3):
        u0 = 0.830 + i * 0.030
        dr.line([pt((u0, 0.874)), pt((u0 + 0.004, 0.898))], fill=84,
                width=int(1.5 * s))
    # the top of the base slab
    ridge([(0.058, 0.920), (0.500, 0.926), (0.938, 0.920)], 188, 2.0)
    # the far foreleg, and the groove between the shoulder and the near one
    dr.polygon([pt(p) for p in spline(
        [(0.690, 0.560), (0.706, 0.680), (0.708, 0.796), (0.726, 0.860),
         (0.768, 0.880), (0.754, 0.832), (0.746, 0.680), (0.734, 0.560)])],
        fill=96)
    ridge([(0.742, 0.500), (0.752, 0.580), (0.754, 0.700)], 88, 2.6)
    ridge(spline([(0.190, 0.740), (0.330, 0.786), (0.474, 0.820),
                  (0.580, 0.840), (0.642, 0.866), (0.690, 0.880)],
                 closed=False), 92, 2.4)

    rel = rel.filter(ImageFilter.GaussianBlur(1.3 * s))
    hgt = hgt + (np.asarray(rel, np.float32) - 128.0) / 128.0 * 0.052
    gold = np.asarray(gold.filter(ImageFilter.GaussianBlur(0.6 * s)),
                      np.float32) / 255.0

    # --- light it --------------------------------------------------------
    # The height is in units of the figure's own width, so the normals don't
    # depend on the canvas size.
    gy, gx = np.gradient(hgt * fw * 0.176)
    nx, ny, nz = -gx, -gy, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln

    lv = np.array(BASTET_LIGHT, np.float64)
    lv /= np.linalg.norm(lv)
    hv = lv + np.array([0.0, 0.0, 1.0])
    hv /= np.linalg.norm(hv)

    lam = np.clip(nx * lv[0] + ny * lv[1] + nz * lv[2], 0, 1)
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1)

    def material(dark, lit, sp, gamma, shine, power):
        d0 = np.array(dark, np.float32)[None, None, :]
        d1 = np.array(lit, np.float32)[None, None, :]
        d2 = np.array(sp, np.float32)[None, None, :]
        return (d0 + (d1 - d0) * (lam ** gamma)[..., None]
                + d2 * ((spec ** power) * shine)[..., None])

    stone = material(CAT_DARK, CAT_LIT, CAT_SPEC, 1.70, 0.46, 26)
    metal = material(AU_DARK, AU_LIT, AU_SPEC, 1.05, 0.70, 15)
    rgb = stone + (metal - stone) * gold[..., None]

    rgb += np.random.default_rng(7).normal(0, 2.6, (H, W, 1))

    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8),
                          "RGB").convert("RGBA")
    img.putalpha(sil)
    img = down(img, w, h)
    box = img.split()[3].getbbox()
    if box is not None:
        m = 3
        img = img.crop((max(0, box[0] - m), max(0, box[1] - m),
                        min(img.width, box[2] + m),
                        min(img.height, box[3] + m)))
    rim = A.rim_light(img.split()[3], ORB, drop=3, blur=2.0, strength=1.0)
    return img, rim


def _densify(pts, step):
    """Insert samples until no two are further apart than `step`. A stroke
    drawn as discs is only continuous if they overlap, so the spacing must suit
    the narrowest pass (the highlight, at 40% of the body's width).
    """
    out = []
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        d = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(math.ceil(d / max(0.35, step))))
        for j in range(n):
            t = j / float(n)
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(pts[-1])
    return out


def _ribbon(d, pts, col, a, w, taper=0.0):
    """A stroke along a path, as a disc per sample (`ImageDraw.line` mitres its
    joins into spikes on tight curls). `taper` thins it toward both ends.
    """
    pts = _densify(pts, w * 0.30)
    n = max(1, len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        t = i / float(n)
        k = 1.0 - taper * (1.0 - math.sin(math.pi * t) ** 0.45)
        ww = max(0.6, w * k)
        d.ellipse([x - ww, y - ww, x + ww, y + ww], fill=rgba(col, a))


def _ribbon_grad(d, pts, col, a, w0, w1, gamma=1.0):
    """A stroke whose weight runs from `w0` to `w1` along its length, for a
    stroke that ends on something: fine at the free end, full where it joins.
    """
    pts = _densify(pts, min(w0, w1) * 0.30)
    n = max(1, len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        t = (i / float(n)) ** gamma
        ww = max(0.6, w0 + (w1 - w0) * t)
        d.ellipse([x - ww, y - ww, x + ww, y + ww], fill=rgba(col, a))


def _relief_grad(d, pts, w0, w1, gamma=1.0):
    """`_ribbon_grad` as struck metal: shadow, body, highlight."""
    o = max(w0, w1) * 0.34
    _ribbon_grad(d, [(x + o, y + o) for (x, y) in pts], (26, 14, 6), 190,
                 w0, w1, gamma)
    _ribbon_grad(d, pts, GILT, 248, w0, w1, gamma)
    _ribbon_grad(d, [(x - o * 0.62, y - o * 0.62) for (x, y) in pts],
                 GILT_HOT, 135, w0 * 0.40, w1 * 0.40, gamma)


def _ribbon_relief(d, pts, w, taper=0.0, col=None, hot=None):
    """The same stroke as struck metal: a shadow under it, the body, and a fine
    highlight along its upper left.
    """
    col = GILT if col is None else col
    hot = GILT_HOT if hot is None else hot
    o = w * 0.34
    _ribbon(d, [(x + o, y + o) for (x, y) in pts], (26, 14, 6), 190, w, taper)
    _ribbon(d, pts, col, 248, w, taper)
    _ribbon(d, [(x - o * 0.62, y - o * 0.62) for (x, y) in pts],
            hot, 135, w * 0.40, taper)


def _eye_of_horus(d, cx, cy, s, col, a, px=1):
    """The wedjat, drawn as its parts: a brow, an almond eye with a round
    pupil, the vertical teardrop under the inner corner, and the long spiral
    tail from the outer one.
    """
    w = s * 0.085

    # the brow: a heavy arc standing clear above the eye, running past the
    # outer corner
    brow = []
    for i in range(40):
        t = i / 39.0
        ang = math.radians(196 + t * 128)
        brow.append((cx + math.cos(ang) * s * 1.06,
                     cy + math.sin(ang) * s * 0.72 - s * 0.20))
    _ribbon_relief(d, brow, w * 1.05, taper=0.40)

    # the upper lid, from the inner corner over to the outer one
    upper = []
    for i in range(44):
        t = i / 43.0
        upper.append((cx + s * (-0.95 + 1.95 * t),
                      cy - s * 0.46 * math.sin(math.pi * (0.12 + t * 0.88))))
    _ribbon_relief(d, upper, w, taper=0.30)
    # the lower lid, shallower, meeting it at both corners
    lower = []
    for i in range(40):
        t = i / 39.0
        lower.append((cx + s * (-0.95 + 1.62 * t),
                      cy + s * 0.36 * math.sin(math.pi * t)))
    _ribbon_relief(d, lower, w * 0.92, taper=0.30)

    # the pupil
    r = s * 0.27
    d.ellipse([cx - r * 0.55 - r, cy - r, cx - r * 0.55 + r, cy + r],
              fill=rgba(col, a))

    # the teardrop, falling from under the inner corner and tapering
    tear = []
    for i in range(26):
        t = i / 25.0
        tear.append((cx - s * (0.30 + 0.26 * t), cy + s * (0.30 + 0.78 * t)))
    for i, (x, y) in enumerate(tear):
        ww = w * (1.05 - 0.75 * (i / (len(tear) - 1.0)))
        d.ellipse([x - ww, y - ww, x + ww, y + ww], fill=rgba(col, a))

    # the tail: out from the outer corner, then curling under into a spiral
    tail = []
    for i in range(34):
        t = i / 33.0
        ang = math.radians(-72 + t * 250)
        rr = s * (0.50 - 0.30 * t)
        tail.append((cx + s * 0.52 + math.cos(ang) * rr,
                     cy + s * 0.62 + math.sin(ang) * rr))
    _ribbon_relief(d, tail, w * 0.86, taper=0.50)
    # ...and the straight run that joins the eye to it
    join = []
    for i in range(14):
        t = i / 13.0
        join.append((cx + s * (0.58 + 0.22 * t), cy + s * (0.30 + 0.18 * t)))
    _ribbon_relief(d, join, w * 0.9)


def _spline(pts, n=190):
    """A Catmull-Rom pass through the control points (the crest's ribbon
    reverses its curvature twice).
    """
    P = [pts[0]] + list(pts) + [pts[-1]]
    segs = len(P) - 3
    per = max(2, n // segs)
    out = []
    for i in range(segs):
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        for j in range(per):
            t = j / float(per)
            t2, t3 = t * t, t * t * t
            out.append((
                0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
                0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)))
    return out


def _crest(d, cx, cy, s, col, a):
    """Ashiah's crest: one ribbon, a tall S with a closed ring at its middle.

    A curl opening left at the head sweeps right and down into the ring; out of
    the ring a second curve goes down and left, then right, ending in a hook
    that opens upward. Both tails end on the ring, and their weight runs from a
    fine point at the outer end to full where they meet it.
    """
    w = s * 0.082
    R = s * 0.38
    tip = w * 0.16

    # the disc set inside the ring
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=rgba(CREST_EYE, 255))

    # where the two tails meet the metal
    def on_ring(deg):
        return (math.cos(math.radians(deg)) * R / s,
                math.sin(math.radians(deg)) * R / s)

    upper = _spline([(-0.52, -1.08), (-0.50, -1.33), (-0.27, -1.50),
                     (0.07, -1.47), (0.33, -1.26), (0.45, -0.94),
                     (0.41, -0.62), on_ring(-58)])
    lower = _spline([on_ring(102), (-0.24, 0.62), (-0.41, 0.92),
                     (-0.39, 1.20), (-0.15, 1.42), (0.18, 1.46),
                     (0.41, 1.32), (0.51, 1.05)])

    ring = []
    for i in range(150):
        ang = 2 * math.pi * i / 149
        ring.append((cx + math.cos(ang) * R, cy + math.sin(ang) * R))

    # the ring carries full weight; each tail runs from a point to full where
    # it lands on it
    _relief_grad(d, ring, w, w)
    _relief_grad(d, [(cx + x * s, cy + y * s) for (x, y) in upper],
                 tip, w, gamma=0.72)
    _relief_grad(d, [(cx + x * s, cy + y * s) for (x, y) in lower],
                 w, tip, gamma=1.45)


def banner(kind, w=224, h=704):
    """A tabard hung from the gallery: red with Ashiah's crest, or black with
    the gold eye. They alternate down the hall."""
    im, dc = canvas(w, h, (12, 11, 16))
    mk, dm = mask(w, h)
    d = Tee(dc, dm)
    W, H = w * SS, h * SS
    s = SS
    field = CREST_RED if kind == 0 else NAVY

    d.rectangle([0, 0, W, H * 0.020], fill=(27, 25, 26, 255))
    moulding(d, 0, H * 0.012, W, H * 0.026, t=1.2)

    cloth = [(W * 0.055, H * 0.024), (W * 0.945, H * 0.024),
             (W * 0.945, H * 0.865), (W * 0.5, H * 0.995),
             (W * 0.055, H * 0.865)]
    d.polygon(cloth, fill=rgba(field, 255))
    # folds: the cloth is not a board, and three soft verticals say so
    for fx, wd, al in ((0.20, 0.055, 46), (0.42, 0.07, 30), (0.68, 0.06, 52),
                       (0.86, 0.045, 36)):
        d.polygon([(W * fx, H * 0.024), (W * (fx + wd), H * 0.024),
                   (W * (fx + wd), H * 0.90), (W * fx, H * 0.92)],
                  fill=(0, 0, 0, al))
    for fx in (0.30, 0.55, 0.78):
        d.polygon([(W * fx, H * 0.024), (W * (fx + 0.02), H * 0.024),
                   (W * (fx + 0.02), H * 0.90), (W * fx, H * 0.91)],
                  fill=(255, 255, 255, 12))
    # the border
    d.line([(W * 0.095, H * 0.052), (W * 0.905, H * 0.052)],
           fill=rgba(GILT, 220), width=int(2.6 * s))
    d.line([(W * 0.095, H * 0.052), (W * 0.095, H * 0.862)],
           fill=rgba(GILT, 195), width=int(2.2 * s))
    d.line([(W * 0.905, H * 0.052), (W * 0.905, H * 0.862)],
           fill=rgba(GILT, 195), width=int(2.2 * s))
    d.line([(W * 0.095, H * 0.862), (W * 0.5, H * 0.962),
            (W * 0.905, H * 0.862)], fill=rgba(GILT, 220), width=int(2.6 * s))

    if kind == 0:
        _crest(d, W * 0.5, H * 0.38, W * 0.34, GILT, 245)
    else:
        _eye_of_horus(d, W * 0.5, H * 0.385, W * 0.32, GILT, 245, s)
    d.line([(W * 0.16, H * 0.685), (W * 0.84, H * 0.685)],
           fill=rgba(GILT_DIM, 205), width=int(2.0 * s))
    # Lozenges rather than rings (a row of small ellipses reads as zeros).
    for i in range(5):
        gx = W * (0.26 + i * 0.12)
        gy = H * 0.742
        r_ = 8 * s
        d.polygon([(gx, gy - r_), (gx + r_ * 0.58, gy), (gx, gy + r_),
                   (gx - r_ * 0.58, gy)], fill=rgba(GILT_DIM, 215))
    d.ellipse([W * 0.455, H * 0.955, W * 0.545, H * 0.998],
              fill=rgba(GILT, 228))

    img = cut(im, mk, w, h)
    rim = A.rim_light(img.split()[3], ORB, drop=2, blur=2.0, strength=0.9)
    return img, rim


def desk(kind, w=352, h=320):
    """A reading desk with an hourglass or an armillary on it. The armillary is
    small and warm, so it can't be mistaken for one of Mika's rings.
    """
    im, dc = canvas(w, h, (14, 13, 18))
    mk, dm = mask(w, h)
    d = Tee(dc, dm)
    W, H = w * SS, h * SS
    s = SS
    d.polygon([(W * 0.06, H), (W * 0.94, H), (W * 0.875, H * 0.615),
               (W * 0.125, H * 0.615)], fill=(18, 17, 23, 255))
    d.polygon([(W * 0.06, H), (W * 0.20, H), (W * 0.215, H * 0.615),
               (W * 0.125, H * 0.615)], fill=(255, 255, 255, 12))
    moulding(d, W * 0.035, H * 0.578, W * 0.965, H * 0.625, t=1.6)
    d.rectangle([W * 0.17, H * 0.72, W * 0.83, H * 0.765],
                fill=rgba(GILT_DIM, 175))
    glyph_run(d, W * 0.5, H * 0.80, H * 0.96, W * 0.20, 43, col=GILT_DIM,
              alpha=150)

    cx, base = W * 0.5, H * 0.578
    if kind == 0:
        sz = H * 0.21
        # the glass
        d.polygon([(cx - sz * 0.60, base - sz * 2.0),
                   (cx + sz * 0.60, base - sz * 2.0),
                   (cx + sz * 0.10, base - sz * 1.0),
                   (cx + sz * 0.60, base), (cx - sz * 0.60, base),
                   (cx - sz * 0.10, base - sz * 1.0)],
                  fill=(206, 190, 150, 70))
        # the sand, and it has fallen
        d.polygon([(cx - sz * 0.54, base - sz * 0.06),
                   (cx + sz * 0.54, base - sz * 0.06),
                   (cx + sz * 0.09, base - sz * 0.92),
                   (cx - sz * 0.09, base - sz * 0.92)],
                  fill=rgba(GILT_HOT, 238))
        d.polygon([(cx - sz * 0.29, base - sz * 1.98),
                   (cx + sz * 0.29, base - sz * 1.98),
                   (cx + sz * 0.07, base - sz * 1.12),
                   (cx - sz * 0.07, base - sz * 1.12)],
                  fill=rgba(GILT_HOT, 150))
        d.line([(cx, base - sz * 1.04), (cx, base - sz * 0.22)],
               fill=rgba(GILT_HOT, 225), width=max(1, int(1.4 * s)))
        for yy in (base, base - sz * 2.0):
            moulding(d, cx - sz * 0.72, yy - sz * 0.12, cx + sz * 0.72,
                     yy + sz * 0.04, t=1.4)
        for sgn in (-1, 1):
            d.line([(cx + sgn * sz * 0.67, base),
                    (cx + sgn * sz * 0.67, base - sz * 2.0)],
                   fill=rgba(GILT, 238), width=int(2.4 * s))
    else:
        sz = H * 0.185
        d.line([(cx, base), (cx, base - sz * 0.58)], fill=rgba(GILT, 232),
               width=int(2.8 * s))
        d.ellipse([cx - sz * 0.46, base - sz * 0.14, cx + sz * 0.46,
                   base + sz * 0.06], fill=rgba(GILT, 232))
        cy = base - sz * 1.38
        d.ellipse([cx - sz, cy - sz, cx + sz, cy + sz],
                  outline=rgba(GILT, 230), width=int(2.4 * s))
        d.ellipse([cx - sz, cy - sz * 0.31, cx + sz, cy + sz * 0.31],
                  outline=rgba(GILT, 212), width=int(2.2 * s))
        d.ellipse([cx - sz * 0.35, cy - sz, cx + sz * 0.35, cy + sz],
                  outline=rgba(GILT_DIM, 208), width=int(1.8 * s))
        d.ellipse([cx - sz * 0.13, cy - sz * 0.13, cx + sz * 0.13,
                   cy + sz * 0.13], fill=rgba(ORB, 238))

    img = cut(im, mk, w, h)
    rim = A.rim_light(img.split()[3], ORB, drop=2, blur=1.8, strength=0.9)
    return img, rim


def orb_lamp(n=96):
    """The standing light: a caged orb on a gilt stem. A real object at a real
    position, so the shelving is lit by it and its bloom passes the camera.
    """
    im, dc = canvas(n, n * 3, (11, 11, 15))
    mk, dm = mask(n, n * 3)
    d = Tee(dc, dm)
    W, H = n * SS, n * 3 * SS
    s = SS
    cx = W / 2
    d.polygon([(cx - W * 0.30, H), (cx + W * 0.30, H),
               (cx + W * 0.20, H * 0.93), (cx - W * 0.20, H * 0.93)],
              fill=(19, 18, 24, 255))
    moulding(d, cx - W * 0.32, H * 0.915, cx + W * 0.32, H * 0.945, t=1.2)
    d.line([(cx, H * 0.93), (cx, H * 0.34)], fill=rgba(GILT_DIM, 235),
           width=int(3.0 * s))
    for k in (0.78, 0.60):
        d.ellipse([cx - W * 0.11, H * k - W * 0.05, cx + W * 0.11,
                   H * k + W * 0.05], outline=rgba(GILT, 215), width=int(1.6 * s))
    oy = H * 0.22
    orad = W * 0.34
    d.ellipse([cx - orad * 1.06, oy - orad * 1.06, cx + orad * 1.06,
               oy + orad * 1.06], outline=rgba(GILT, 238), width=int(2.4 * s))
    for a in range(6):
        ang = math.radians(a * 60)
        d.line([(cx + math.cos(ang) * orad * 1.06,
                 oy + math.sin(ang) * orad * 1.06),
                (cx + math.cos(ang) * orad * 0.42,
                 oy + math.sin(ang) * orad * 0.42)],
               fill=rgba(GILT_DIM, 205), width=int(1.5 * s))
    d.ellipse([cx - orad, oy - orad, cx + orad, oy + orad],
              fill=(26, 40, 74, 255))
    img = cut(im, mk, n, n * 3)

    em, ed = canvas(n, n * 3, (0, 0, 0))
    ed.ellipse([cx - orad * 0.92, oy - orad * 0.92, cx + orad * 0.92,
                oy + orad * 0.92], fill=rgba(ORB, 255))
    ed.ellipse([cx - orad * 0.46, oy - orad * 0.46, cx + orad * 0.46,
                oy + orad * 0.46], fill=rgba(ORB_HOT, 255))
    em = em.filter(ImageFilter.GaussianBlur(3.0 * s))
    lit = down(em, n, n * 3).convert("RGBA")
    lit.putalpha(255)
    return img, lit


# ---------------------------------------------------------------------------
# Materials
#
# The walls are 3D joinery, so this section makes the materials they are cut
# from: stone, book spines, a gilded pilaster face and the rest.
# `scripts/bg_sanctum` cuts them into boards, reveals, cornices and plinths.
# ---------------------------------------------------------------------------
def stone_tile(n=128):
    """The material everything structural is cut from: nearly featureless
    (grain and a little mottle), because it is seen at many scales and a
    pattern would repeat visibly.
    """
    im, d = canvas(n, n, STONE)
    N = n * SS
    r = np.random.default_rng(31)
    for _ in range(90):
        x, y = r.uniform(0, N), r.uniform(0, N)
        rr = r.uniform(4, 26) * SS
        v = int(r.uniform(-16, 18))
        c = (max(0, STONE[0] + v), max(0, STONE[1] + v), max(0, STONE[2] + v))
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=rgba(c, 70))
    out = grain(down(im, n, n), 4, 33).convert("RGBA")
    out.putalpha(255)
    return out


def pale_tile(n=64):
    """A near-white tile, for anything whose colour comes from its tint. A
    vertex colour multiplies its texture, so gilt over the dark stone comes out
    black; anything tinted gold is textured with this instead.
    """
    im, d = canvas(n, n, (238, 238, 242))
    N = n * SS
    r = np.random.default_rng(57)
    for _ in range(70):
        x, y = r.uniform(0, N), r.uniform(0, N)
        rr = r.uniform(3, 14) * SS
        v = int(r.uniform(-14, 8))
        c = (238 + v, 238 + v, 242 + v)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=rgba(c, 80))
    out = grain(down(im, n, n), 3, 59).convert("RGBA")
    out.putalpha(255)
    return out


def plinth_face(n=160):
    """The face of a plinth: a recessed panel in a gilt border, with a mark in
    the recess. Every plinth, desk side and pedestal in the hall takes this.
    """
    im, d = canvas(n, n, STONE)
    N = n * SS
    s_ = SS
    r = np.random.default_rng(83)
    for _ in range(60):
        x, y = r.uniform(0, N), r.uniform(0, N)
        rr = r.uniform(5, 22) * s_
        v = int(r.uniform(-12, 14))
        d.ellipse([x - rr, y - rr, x + rr, y + rr],
                  fill=rgba((STONE[0] + v, STONE[1] + v, STONE[2] + v), 80))
    # the recessed panel, with its own lit top edge and shadowed underside
    m = 17 * s_
    d.rectangle([m, m, N - m, N - m], fill=(0, 0, 0, 120))
    d.rectangle([m, m, N - m, m + 2 * s_], fill=(0, 0, 0, 175))
    d.rectangle([m, N - m - 2 * s_, N - m, N - m], fill=rgba(STONE_LIT, 150))
    d.rectangle([m, m, N - m, N - m], outline=rgba(GILT_DIM, 210),
                width=max(1, int(1.4 * s_)))
    glyph_run(d, N * 0.5, m + 9 * s_, N - m - 9 * s_, N * 0.30, 611,
              col=GILT_DIM, alpha=180)
    out = grain(down(im, n, n), 3, 67).convert("RGBA")
    out.putalpha(255)
    return out


def board_edge(w=64, h=32):
    """The front edge of a shelf board: mostly shadow, with one lit row for the
    arris.
    """
    im, d = canvas(w, h, (36, 33, 32))
    W, H = w * SS, h * SS
    d.rectangle([0, 0, W, H * 0.11], fill=rgba((104, 96, 84), 255))
    d.rectangle([0, H * 0.11, W, H * 0.17], fill=rgba((62, 57, 52), 255))
    d.rectangle([0, H * 0.78, W, H], fill=rgba((10, 9, 12), 255))
    out = grain(down(im, w, h), 2, 107).convert("RGBA")
    out.putalpha(255)
    return out


def dado_band(w=256, h=128):
    """The foundation the bookcases stand on: a dark ground between two gilt
    mouldings, with a row of oval inlays. Periodic in x, since the plinth is
    one quad per bay and the tile repeats along it.
    """
    im, d = canvas(w, h, (13, 13, 18))
    W, H = w * SS, h * SS
    s_ = SS
    r = np.random.default_rng(97)
    for _ in range(40):
        x, y = r.uniform(0, W), r.uniform(0, H)
        rr = r.uniform(6, 26) * s_
        v = int(r.uniform(-8, 12))
        d.ellipse([x - rr, y - rr, x + rr, y + rr],
                  fill=rgba((17 + v, 17 + v, 23 + v), 90))
    # the moulding at its head, and the dimmer one at its foot
    moulding(d, 0, 0, W, H * 0.17, t=1.7)
    moulding(d, 0, H * 0.80, W, H * 0.90, lit=GILT_DIM, shade=(24, 20, 12),
             t=1.1)
    # the inlaid ovals, four to a tile, each a ring with a dark eye in it
    for i in range(4):
        bx = W * (i + 0.5) / 4.0
        d.ellipse([bx - 20 * s_, H * 0.32, bx + 20 * s_, H * 0.68],
                  outline=rgba(GILT_DIM, 215), width=max(1, int(1.6 * s_)))
        d.ellipse([bx - 12 * s_, H * 0.40, bx + 12 * s_, H * 0.60],
                  outline=rgba(GILT_DARK, 200), width=max(1, int(1.2 * s_)))
        d.ellipse([bx - 4 * s_, H * 0.46, bx + 4 * s_, H * 0.54],
                  fill=rgba(GILT_DIM, 190))
    out = grain(down(im, w, h), 3, 101).convert("RGBA")
    out.putalpha(255)
    return out


def cornice_band(w=256, h=96):
    """The head of the wall: two mouldings over a dark frieze."""
    im, d = canvas(w, h, (12, 12, 17))
    W, H = w * SS, h * SS
    moulding(d, 0, H * 0.62, W, H * 0.82, t=1.8)
    moulding(d, 0, H * 0.24, W, H * 0.36, lit=GILT_DIM, shade=(24, 20, 12),
             t=1.1)
    for i in range(8):
        bx = W * (i + 0.5) / 8.0
        d.rectangle([bx - 3 * SS, H * 0.40, bx + 3 * SS, H * 0.58],
                    fill=rgba(GILT_DARK, 190))
    out = grain(down(im, w, h), 2, 103).convert("RGBA")
    out.putalpha(255)
    return out


def desk_face(w=192, h=128):
    """A desk's side: two fielded panels under a moulded top rail."""
    im, d = canvas(w, h, STONE)
    W, H = w * SS, h * SS
    s_ = SS
    d.rectangle([0, 0, W, H * 0.17], fill=rgba(STONE_LIT, 120))
    d.rectangle([0, H * 0.16, W, H * 0.19], fill=(0, 0, 0, 165))
    for i in range(2):
        x0 = W * (0.07 + i * 0.47)
        x1 = x0 + W * 0.39
        d.rectangle([x0, H * 0.28, x1, H * 0.88], fill=(0, 0, 0, 115))
        d.rectangle([x0, H * 0.28, x1, H * 0.31], fill=(0, 0, 0, 170))
        d.rectangle([x0, H * 0.85, x1, H * 0.88], fill=rgba(STONE_LIT, 140))
        d.rectangle([x0, H * 0.28, x1, H * 0.88],
                    outline=rgba(GILT_DIM, 195), width=max(1, int(1.3 * s_)))
        d.ellipse([(x0 + x1) / 2 - 7 * s_, H * 0.52, (x0 + x1) / 2 + 7 * s_,
                   H * 0.66], outline=rgba(GILT_DIM, 175),
                  width=max(1, int(1.2 * s_)))
    out = grain(down(im, w, h), 3, 71).convert("RGBA")
    out.putalpha(255)
    return out


def books_tile(seed, w=256, h=168):
    """One shelf's worth of spines, periodic in x (a shelf is a quad whose
    texture repeats along it): the run is laid out twice and the middle kept.
    """
    im, d = canvas(w * 2, h, (7, 7, 10))
    W, H = w * 2 * SS, h * SS
    books(d, 0, W, H * 0.04, H, seed)
    full = down(im, w * 2, h)
    out = full.crop((w // 2, 0, w // 2 + w, h)).convert("RGBA")
    out.putalpha(255)
    return out


def pilaster_face(w=96, h=1024):
    """The face of a pilaster: a shaft with a cartouche running up it."""
    im, d = canvas(w, h, STONE)
    W, H = w * SS, h * SS
    s = SS
    # modelled across its width: a lit edge, a broad face, a shadowed return
    d.rectangle([0, 0, W * 0.16, H], fill=(0, 0, 0, 120))
    d.rectangle([W * 0.16, 0, W * 0.62, H], fill=rgba(STONE_LIT, 80))
    d.rectangle([W * 0.84, 0, W, H], fill=(0, 0, 0, 150))
    glyph_run(d, W * 0.45, H * 0.05, H * 0.95, W * 0.52, 771)
    out = grain(down(im, w, h), 3, 41).convert("RGBA")
    out.putalpha(255)
    return out


def orb(n=192):
    """The light in the alcove: a caged sphere and its light, standing in a
    real recess.
    """
    im, dc = canvas(n, n, (10, 11, 16))
    mk, dm = mask(n, n)
    d = Tee(dc, dm)
    N = n * SS
    c = N / 2
    rr = N * 0.40
    d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=(26, 40, 74, 255))
    # the cage: three gilt meridians and a ring
    d.ellipse([c - rr * 1.06, c - rr * 1.06, c + rr * 1.06, c + rr * 1.06],
              outline=rgba(GILT, 235), width=int(2.6 * SS))
    d.ellipse([c - rr * 1.06, c - rr * 0.30, c + rr * 1.06, c + rr * 0.30],
              outline=rgba(GILT, 210), width=int(2.0 * SS))
    d.ellipse([c - rr * 0.34, c - rr * 1.06, c + rr * 0.34, c + rr * 1.06],
              outline=rgba(GILT_DIM, 200), width=int(1.8 * SS))
    body = cut(im, mk, n, n)

    em, ed = canvas(n, n, (0, 0, 0))
    ed.ellipse([c - rr * 0.94, c - rr * 0.94, c + rr * 0.94, c + rr * 0.94],
               fill=rgba(ORB, 255))
    ed.ellipse([c - rr * 0.50, c - rr * 0.50, c + rr * 0.50, c + rr * 0.50],
               fill=rgba(ORB_HOT, 255))
    em = em.filter(ImageFilter.GaussianBlur(4.0 * SS))
    lit = down(em, n, n).convert("RGBA")
    lit.putalpha(255)
    return body, lit


# ---------------------------------------------------------------------------
# The statue's third dimension
#
# `bg_sanctum` sweeps the Bastet into a solid (a flat card reads as paper
# from above). The sweep's cross-section is measured off the shipped PNG's
# alpha rather than restated in GML, so the card and the solid share one
# outline. The one thing a profile can't give is width, so that is authored:
# a half-depth per height, as a fraction of the card's width. A seated cat is
# narrow at the ears, widest across the haunch, and stands on a base wider
# than she is.
BASTET_DEPTH = [
    (0.000, 0.052), (0.090, 0.086), (0.170, 0.106), (0.262, 0.088),
    (0.360, 0.126), (0.500, 0.150), (0.660, 0.176), (0.840, 0.170),
    (0.906, 0.150), (0.926, 0.224), (1.000, 0.228),
]
BASTET_SLICES = 34

BASTET_TABLE_GML = '''/// @desc The Gilded Sanctum's measured numbers -- GENERATED by
///       tools/make_sanctum.py. Do not edit.
///
/// How wide the Bastet is at each height, so `bg_sanctum` can sweep her into
/// a solid. Her outline is read row by row off the shipped sprite's alpha, so
/// the card and the solid agree. Each row is `[v, u0, u1, d]` in the sprite's
/// own box, 0..1 from its top-left: the height, the back and the front of her
/// at that height, and her half-depth. The half-depth is authored (a profile
/// can't say how wide a thing is), as a fraction of the card's width.

function sanctum_table_init() {
    global.bastet_slice = [
%s
    ];
}

/// @desc Her cross-section at height `_v`, as `[centre, half-length,
///       half-depth]` in the sprite's own box, interpolated between the
///       measured rows.
function bastet_at(_v) {
    var _t = global.bastet_slice;
    var _n = array_length(_t);
    var _i = 0;
    while (_i < _n - 2 && _t[_i + 1][0] < _v) _i++;
    var _a = _t[_i];
    var _b = _t[_i + 1];
    var _s = clamp((_v - _a[0]) / max(0.000001, _b[0] - _a[0]), 0, 1);
    var _u0 = lerp(_a[1], _b[1], _s);
    var _u1 = lerp(_a[2], _b[2], _s);
    return [(_u0 + _u1) * 0.5, (_u1 - _u0) * 0.5, lerp(_a[3], _b[3], _s)];
}
'''


def _bastet_depth_at(v):
    """The authored half-depth, interpolated."""
    pts = BASTET_DEPTH
    if v <= pts[0][0]:
        return pts[0][1]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if v <= b[0]:
            t = (v - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    return pts[-1][1]


def bastet_slices(img, n=BASTET_SLICES):
    """Read her outline off the shipped alpha, one row per slice. A row with no
    ink takes the nearest row that has some, rather than a zero-length slice
    (which would put a spike over her head and a funnel under the base).
    """
    a = np.asarray(img.split()[3])
    h, w = a.shape
    rows = []
    for y in range(h):
        xs = np.nonzero(a[y] > 40)[0]
        rows.append(None if len(xs) == 0 else
                    (float(xs[0]) / w, float(xs[-1] + 1) / w))
    have = [y for y, r in enumerate(rows) if r is not None]
    if not have:
        raise SystemExit("bastet: the sprite has no ink in it")
    out = []
    for i in range(n):
        v = i / (n - 1.0)
        y = min(h - 1, max(0, int(round(v * (h - 1)))))
        if rows[y] is None:
            y = min(have, key=lambda q: abs(q - y))
        u0, u1 = rows[y]
        out.append((v, u0, u1, _bastet_depth_at(v)))
    return out


def write_bastet_table(slices):
    rows = "\n".join("        [%.4f, %.4f, %.4f, %.4f]," % r for r in slices)
    path = os.path.join(A.ROOT, "scripts", "sanctum_table",
                        "sanctum_table.gml")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    gm_new.write(path, BASTET_TABLE_GML % rows)
    gm_new.script("sanctum_table")
    print("sanctum_table.gml: %d bastet slices, %.3f..%.3f long"
          % (len(slices), min(r[2] - r[1] for r in slices),
             max(r[2] - r[1] for r in slices)))


def main():
    gm_new.folder("Sprites/sanctum")
    f = "Sprites/sanctum"

    # Sprites from earlier versions of the hall, deleted if present: the flat
    # wall bays, the ceiling, and the light shafts and their pools. The bays
    # are still drawn for the preview sheet.
    for stale in ("spr_hall_wall", "spr_hall_wall_lit", "spr_hall_ceil",
                  "spr_hall_shaft", "spr_hall_pool"):
        gm_new.delete(stale, "sprites")
    bays = [wall_bay(k)[0] for k in range(3)]
    gm_new.sprite("spr_hall_floor", [floor_tile()], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_runner", [runner_tile()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_border", [border_course()], origin="topleft",
                  folder=f)

    # the sky, and the instrument hanging in it
    gm_new.sprite("spr_hall_star", [star_point(0), star_point(1),
                                    star_point(2)],
                  origin="center", folder=f)
    gm_new.sprite("spr_hall_neb", [nebula(301), nebula(302), nebula(303)],
                  origin="center", folder=f)
    gm_new.sprite("spr_hall_zodiac", [zodiac_band()], origin="topleft",
                  folder=f)
    rot, rot_lit = rotunda()
    gm_new.sprite("spr_hall_rot", [rot], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_rot_lit", [rot_lit], origin="topleft", folder=f)

    cat, cat_rim = bastet()
    gm_new.sprite("spr_hall_bastet", [cat], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_bastet_rim", [cat_rim], origin="topleft", folder=f)
    write_bastet_table(bastet_slices(cat))

    b0, r0 = banner(0)
    b1, r1 = banner(1)
    gm_new.sprite("spr_hall_banner", [b0, b1], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_banner_rim", [r0, r1], origin="topleft", folder=f)

    d0, dr0 = desk(0)
    d1, dr1 = desk(1)
    gm_new.sprite("spr_hall_desk", [d0, d1], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_desk_rim", [dr0, dr1], origin="topleft", folder=f)

    gm_new.sprite("spr_hall_stone", [stone_tile()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_pale", [pale_tile()], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_plinth", [plinth_face()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_deskface", [desk_face()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_board", [board_edge()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_dado", [dado_band()], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_cornice", [cornice_band()], origin="topleft",
                  folder=f)
    gm_new.sprite("spr_hall_books",
                  [books_tile(701), books_tile(702), books_tile(703)],
                  origin="topleft", folder=f)
    gm_new.sprite("spr_hall_pil", [pilaster_face()], origin="topleft",
                  folder=f)
    ob, ob_lit = orb()
    gm_new.sprite("spr_hall_orb", [ob], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_orb_lit", [ob_lit], origin="topleft", folder=f)

    lamp, lamp_em = orb_lamp()
    gm_new.sprite("spr_hall_lamp", [lamp], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_lamp_lit", [lamp_em], origin="topleft", folder=f)

    A.preview(bays, os.path.join(A.PREVIEW, "sanctum_wall.png"),
              cols=3, bg=(10, 10, 14),
              labels=["bay: shelves", "bay: ladder", "bay: alcove"])
    A.preview([floor_tile(), cat, b0, b1, d0, d1, lamp],
              os.path.join(A.PREVIEW, "sanctum_parts.png"), cols=4,
              bg=(10, 10, 14),
              labels=["floor", "bastet", "banner: crest",
                      "banner: eye", "desk: glass", "desk: armillary",
                      "lamp"])
    # The three courses side by side, at the proportions they are laid at.
    A.preview([runner_tile(), border_course(), floor_tile()],
              os.path.join(A.PREVIEW, "sanctum_floor.png"), cols=3,
              bg=(8, 8, 12),
              labels=["the runner", "the border course", "the marble field"])
    A.preview([star_point(0), star_point(1), star_point(2),
               nebula(301), nebula(302), zodiac_band()],
              os.path.join(A.PREVIEW, "sanctum_sky.png"), cols=3,
              bg=(6, 6, 10),
              labels=["star: faint", "star: middling", "star: bright",
                      "nebula", "nebula", "zodiac limb"])
    A.preview([rot, rot_lit], os.path.join(A.PREVIEW, "sanctum_rotunda.png"),
              cols=1, bg=(10, 14, 34),
              labels=["the far chamber", "...and its lamps"])
    A.preview([ob, ob_lit],
              os.path.join(A.PREVIEW, "sanctum_light.png"), cols=2,
              bg=(8, 8, 12), labels=["orb", "orb light"])
    A.preview([stone_tile(), books_tile(701), books_tile(702),
               pilaster_face()],
              os.path.join(A.PREVIEW, "sanctum_mat.png"), cols=4,
              bg=(8, 8, 12),
              labels=["stone", "books", "books", "pilaster"])

    gold = np.asarray(bays[0].convert("RGB")).astype(np.float32)
    lum = gold.mean(axis=2)
    warm = ((gold[..., 0] > gold[..., 2] + 26) & (lum > 70)).mean()
    print("sanctum: wall %dx%d x3, floor %d, no ceiling (the hall is open)" %
          (WALL_W, WALL_H, FLOOR_N))
    print("         bay is %.1f%% lit gold by area (the rule is: a line, "
          "not a fill)" % (warm * 100))


if __name__ == "__main__":
    main()
