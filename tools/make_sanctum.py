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
import sanctum_glyphs as SG
import sanctum_relief as SR

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
CAT_LIT   = (38, 39, 50)
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

# The texture group the hall's sprites are packed in: mipmapped, with a wide
# border so the small mips don't take colour from their neighbours, and not
# cropped (the default group crops transparent borders, which the flame strip
# and the statue's rim can't have: their frames and alignment are measured
# from the whole image). The flame strip's frames have wide empty margins, so
# its small mips don't blend one frame into the next.
HALL_TEXGROUP = "Hall"


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
# The pavement and the carved stone (`sanctum_relief`)
#
# Every surface here is ornament worked into stone: gold inlaid flush in the
# floors, sunk relief with gilded floors on the walls, raised relief on the
# plinths. Each is drawn as masks (filled forms of varying weight, not
# outlines), and `Plate.finish` models the relief and writes the gloss into
# the alpha, which `sh_hall` reads (`HALL_MAT_*` with the gloss-map flag).
#
# Each texture is made at the proportions of the surface it is laid on, so
# its ornament isn't stretched.
# ---------------------------------------------------------------------------

# The runner is one tile a bay long and the runner's width across
# (`HALL_RUNNER_HW` * 2 by `HALL_BAY_Z`, 528 by 560).
RUNNER_W, RUNNER_H = 768, 816
# The border course, one of `HALL_BORDER_NZ` along a bay (92 by 251).
BORDER_W, BORDER_H = 160, 436
# A pilaster's face, floor to wall head (`HALL_PIL_W` by `HALL_CEIL_H`).
PIL_W, PIL_H = 104, 1624


def runner_tile():
    """The processional way: polished obsidian with its ornament let in as
    fine strip gold, as a floor's inlay is: a rule and a string of beads
    down each edge, and down the middle a winged sun at each bay's joint
    (half at each end of the tile, so a joint lands on one whole), a
    cartouche between, and a lotus between those. Forms are drawn in
    outline; only small parts (the sun, the glyphs, the beads) are solid.
    Everything faces the far end, which is the tile's top."""
    w, h = RUNNER_W, RUNNER_H
    p = SR.Plate(w, h, ss=2, gloss=0.62)
    W, H = p.W, p.H
    p.tint_stone(SR.marble(W, H, 23, base=(13, 13, 18), vein=(46, 46, 58),
                           scale=1.4))

    lines, ld = p.mask()        # drawn as strip: outlined
    solid, sd = p.mask()        # set whole
    for side in (0, 1):
        def X(u):
            return u * W if side == 0 else W - u * W

        def band(u0, u1, dr):
            dr.rectangle([min(X(u0), X(u1)), 0, max(X(u0), X(u1)), H],
                         fill=255)
        band(0.022, 0.027, sd)
        band(0.036, 0.038, sd)
        band(0.160, 0.163, sd)
        SR.bead_chain(sd, min(X(0.088), X(0.114)), max(X(0.088), X(0.114)),
                      0, H, 11)
    cx = W * 0.5
    for y in (0, H):
        SR.winged_disc(ld, cx, y, W * 0.64)
    SR.cartouche(ld, cx - W * 0.105, H * 0.285, W * 0.21, H * 0.43, 41,
                 glyphs=False)
    SG.column(sd, cx - W * 0.056, H * 0.285 + W * 0.075, W * 0.112,
              H * 0.43 - W * 0.19, 41, gap=0.06)
    for y in (H * 0.175, H * 0.845):
        SR.lotus_bouquet(ld, cx, y, W * 0.13)
    p.inlay(p.outline(lines, 1.6), bevel=0.5, lift=0.25)
    p.inlay(solid, bevel=0.6, lift=0.25)
    return p.finish(relief=0.8, seed=23)


def border_course():
    """The band between the runner and the marble: the lotus frieze in
    strip gold between two fine rules, on basalt."""
    w, h = BORDER_W, BORDER_H
    p = SR.Plate(w, h, ss=3, gloss=0.50)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 31, base=(20, 20, 26)))
    solid, sd = p.mask()
    sd.rectangle([W * 0.06, 0, W * 0.085, H], fill=255)
    sd.rectangle([W * 0.915, 0, W * 0.94, H], fill=255)
    lines, ld = p.mask()
    SR.lotus_chain(ld, W * 0.18, 0, W * 0.64, H, 4)
    p.inlay(solid, bevel=0.5, lift=0.25)
    p.inlay(p.outline(lines, 1.5), bevel=0.5, lift=0.25)
    return p.finish(relief=0.8, seed=31)


def floor_tile():
    """A slab of the marble field: nero marquina, a fine strip of gold let
    in round it with a hairline inside, and at its heart a scarab rolling
    the sun, drawn in the same strip."""
    n = FLOOR_N
    p = SR.Plate(n, n, ss=2, gloss=0.55)
    W = p.W
    p.tint_stone(SR.marble(W, W, 11))
    solid, sd = p.mask()
    for (m0, t) in ((0.032, 0.0065), (0.052, 0.0028)):
        sd.rectangle([W * m0, W * m0, W * (1 - m0), W * (1 - m0)], fill=255)
        sd.rectangle([W * (m0 + t), W * (m0 + t), W * (1 - m0 - t),
                      W * (1 - m0 - t)], fill=0)
    p.inlay(solid, bevel=0.5, lift=0.25)
    lines, ld = p.mask()
    SR.scarab(ld, W * 0.5, W * 0.5, W * 0.15)
    p.inlay(p.outline(lines, 1.3), bevel=0.5, lift=0.25)
    return p.finish(relief=0.8, seed=11)


def _pil_marks(d, W, H):
    """The pilaster's ornament: a small winged disc for a capital, a sunk
    panel with a column of glyphs, and a base band. Only the stretch the
    cornice and the dado leave uncovered is worked (see `HALL_CASE_TOP`,
    `HALL_PLINTH_H`)."""
    top = H * 0.172          # under the cornice's face
    bot = H * 0.892          # over the dado
    cx = W * 0.5
    SR.winged_disc(d, cx, top + W * 0.20, W * 0.92, feathers=4)
    d.rectangle([W * 0.10, top + W * 0.40, W * 0.90, top + W * 0.45],
                fill=255)
    d.rectangle([W * 0.10, bot - W * 0.12, W * 0.90, bot - W * 0.07],
                fill=255)
    return top + W * 0.55, bot - W * 0.22


def pilaster_face():
    """A pilaster: basalt, with a column of hieroglyphs cut into it in sunk
    relief and their floors gilded, under a winged disc. Returns the face
    and its glow: the same glyphs as light, which the hall wakes and pulses
    (`hall_glyph_glow`)."""
    w, h = PIL_W, PIL_H
    p = SR.Plate(w, h, ss=3, gloss=0.40)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 41, base=(24, 24, 31)))

    m, d = p.mask()
    y0, y1 = _pil_marks(d, W, H)
    p.inlay(m, bevel=1.0, lift=0.4)

    # the sunk panel's frame: a raised fillet
    m, d = p.mask()
    d.rectangle([W * 0.10, y0 - W * 0.04, W * 0.90, y1 + W * 0.04], fill=255)
    d.rectangle([W * 0.16, y0 + W * 0.02, W * 0.84, y1 - W * 0.02], fill=0)
    p.raise_(m, height=1.2, bevel=1.0, gild=True)

    gm, gd = p.mask()
    SG.column(gd, W * 0.18, y0 + W * 0.06, W * 0.64, y1 - y0 - W * 0.12, 771,
              gap=0.10)
    p.carve(gm, depth=2.4, bevel=1.1)
    face = p.finish(relief=1.0, seed=41, tile=False)

    glow = gm.filter(ImageFilter.GaussianBlur(p.ss * 0.8))
    glow = glow.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(glow)
    return face, out


def dado_band():
    """The foundation the cases stand on: basalt between a fine gilt
    moulding and a fillet, with djed pillars and tyet knots cut into it in
    sunk relief, gilded. Four to a tile; the plinth takes two
    tiles a bay."""
    w, h = 512, 238
    p = SR.Plate(w, h, ss=2, gloss=0.40)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 97, base=(20, 20, 26)))
    m, d = p.mask()
    d.rectangle([0, H * 0.07, W, H * 0.11], fill=255)
    d.rectangle([0, H * 0.88, W, H * 0.90], fill=255)
    p.raise_(m, height=1.2, bevel=0.9, gild=True)
    m, d = p.mask()
    for i in range(4):
        cx = W * (i + 0.5) / 4
        name = "djed" if i % 2 == 0 else "tyet"
        SG.draw_glyph(d, name, cx - H * 0.26, H * 0.24, H * 0.52, H * 0.54)
    p.carve(m, depth=2.0, bevel=1.0)
    return p.finish(relief=1.0, seed=97)


def cornice_band():
    """The head of the wall: an Egyptian gorge (a cavetto of upright leaves
    bending out at the top) over a torus roll bound with cord, gilt along
    its edges."""
    w, h = 384, 288
    p = SR.Plate(w, h, ss=2, gloss=0.40)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 103, base=(19, 19, 25)))
    ys = np.arange(H, dtype=np.float32)[:, None] / H
    # the gorge's curve, as height: it swells out toward the top
    gorge = np.clip((0.76 - ys) / 0.62, 0, 1)
    p.hgt += (gorge ** 2.2) * 5.0 * np.ones((1, W), np.float32)
    # the leaves, grooved into the gorge
    m, d = p.mask()
    n = 10
    for i in range(n + 1):
        x = W * i / n
        d.polygon([(x - W * 0.006, H * 0.72), (x + W * 0.006, H * 0.72),
                   (x + W * 0.012, H * 0.10), (x - W * 0.012, H * 0.10)],
                  fill=255)
    p.groove(m, 1.6)
    # the fillet over the leaves
    m, d = p.mask()
    d.rectangle([0, 0, W, H * 0.07], fill=255)
    p.raise_(m, height=1.0, bevel=0.9, gild=True)
    # the torus roll, with its binding
    m, d = p.mask()
    d.rectangle([0, H * 0.76, W, H * 0.94], fill=255)
    p.raise_(m, height=3.0, bevel=3.0, gild=True)
    m, d = p.mask()
    for i in range(12):
        x = W * i / 12
        d.polygon([(x, H * 0.76), (x + W * 0.012, H * 0.76),
                   (x + W * 0.052, H * 0.94), (x + W * 0.040, H * 0.94)],
                  fill=255)
    p.groove(m, 1.4)
    return p.finish(relief=0.9, seed=103)


def plinth_face():
    """A plinth's face: a sunk panel inside a fine gilt fillet, and cut into
    it an ankh between two was sceptres over the basket of 'all', gilded."""
    w, h = 256, 384
    p = SR.Plate(w, h, ss=2, gloss=0.42)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 83, base=(23, 23, 30)))
    m, d = p.mask()
    d.rectangle([W * 0.09, H * 0.065, W * 0.91, H * 0.935], fill=255)
    d.rectangle([W * 0.11, H * 0.078, W * 0.89, H * 0.922], fill=0)
    p.raise_(m, height=1.0, bevel=0.7, gild=True)
    m, d = p.mask()
    d.rectangle([W * 0.14, H * 0.10, W * 0.86, H * 0.90], fill=255)
    p.carve(m, depth=1.2, bevel=1.6, gild=False)
    m, d = p.mask()
    SG.draw_glyph(d, "ankh", W * 0.37, H * 0.22, W * 0.26, H * 0.44)
    for s_ in (0, 1):
        SG.draw_glyph(d, "was", W * (0.20 if s_ == 0 else 0.62), H * 0.18,
                      W * 0.18, H * 0.54, flip=(s_ == 1))
    SG.draw_glyph(d, "basket", W * 0.22, H * 0.74, W * 0.56, H * 0.10)
    p.carve(m, depth=2.0, bevel=1.1)
    return p.finish(relief=1.0, seed=83, tile=False)


def desk_face():
    """A pedestal's side: a fine gilt rail and panel, with a lotus and two
    buds cut into the panel, gilded."""
    w, h = 256, 340
    p = SR.Plate(w, h, ss=2, gloss=0.42)
    W, H = p.W, p.H
    p.tint_stone(SR.basalt(W, H, 71, base=(22, 22, 29)))
    m, d = p.mask()
    d.rectangle([0, H * 0.02, W, H * 0.05], fill=255)
    d.rectangle([W * 0.11, H * 0.15, W * 0.89, H * 0.91], fill=255)
    d.rectangle([W * 0.13, H * 0.165, W * 0.87, H * 0.895], fill=0)
    p.raise_(m, height=1.0, bevel=0.7, gild=True)
    m, d = p.mask()
    SR.lotus_bouquet(d, W * 0.5, H * 0.56, W * 0.46)
    p.carve(m, depth=1.8, bevel=1.0)
    return p.finish(relief=1.0, seed=71, tile=False)


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
# Fire
# ---------------------------------------------------------------------------
FLAME_FRAMES = 16
FLAME_W, FLAME_H = 64, 128


def periodic_noise(w, h, seed, scale):
    """Noise that tiles in both directions: white noise low-passed in the
    frequency domain, which is periodic by construction. `scale` is the size
    of its features in pixels. Normalised to 0..1.
    """
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.normal(0, 1, (h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.hypot(fx, fy) * scale
    f *= np.exp(-k * k * 4.0)
    n = np.real(np.fft.ifft2(f))
    n -= n.min()
    return (n / max(1e-6, n.max())).astype(np.float32)


def flame_strip():
    """A fire's tongues as a looping strip of `FLAME_FRAMES` frames, side by
    side in one image (the hall draws a frame by its span of the strip, so
    the whole animation is one texture).

    Three tongues rise from one seat, their heights breathing and their bodies
    swaying at whole multiples of the loop, and a turbulence field scrolls up
    through them exactly one period per loop, so the last frame runs into the
    first. White-hot at the root, through gold and orange to a red tip. Drawn
    for additive blending: the colour is the light, the alpha how much of it.
    """
    s = SS * 2
    fw, fh = FLAME_W * s, FLAME_H * s
    period = fh
    turb = periodic_noise(fw, period, 811, 9.0 * s)
    fine = periodic_noise(fw, period, 812, 3.5 * s)
    ys, xs = np.mgrid[0:fh, 0:fw].astype(np.float32)
    u = (xs - fw * 0.5) / (fw * 0.5)          # -1..1 across
    v = 1.0 - ys / fh                         # 0 at the seat, 1 at the top
    tongues = [  # centre, width, height, breath rate and phase
        (0.00, 0.34, 0.92, 1, 0.0),
        (-0.30, 0.22, 0.58, 2, 1.7),
        (0.28, 0.24, 0.66, 3, 4.1),
        (0.08, 0.16, 0.78, 2, 2.9),
    ]
    frames = []
    for f in range(FLAME_FRAMES):
        ph = 2 * math.pi * f / FLAME_FRAMES
        # the turbulence, scrolled up one period over the loop
        off = int(round(period * f / FLAME_FRAMES))
        tr = np.roll(turb, -off, axis=0)
        fn = np.roll(fine, -off * 2 % period, axis=0)
        sway = ((tr - 0.5) * 0.55 + 0.10 * np.sin(v * 7.0 - ph * 2 + 0.4)) \
            * np.clip(v, 0, 1) ** 1.3
        dens = np.zeros_like(u)
        for (cx, w, hgt, rate, p0) in tongues:
            hh = hgt * (1 + 0.13 * math.sin(ph * rate + p0))
            t = np.clip(v / hh, 0, 1.2)
            width = w * (0.30 + 0.70 * np.clip(1 - t, 0, 1) ** 0.55) \
                * np.clip(1 - t, 0, 1) ** 0.25 \
                * (0.40 + 0.60 * np.clip(v / 0.22, 0, 1) ** 0.6)
            d =(u - cx - sway * (0.6 + 0.4 * hgt)) / np.maximum(width, 1e-3)
            body = np.exp(-d * d * 1.6)
            env = np.clip(v / 0.10, 0, 1) ** 0.7 * (1 - np.clip((t - 0.55) / 0.45, 0, 1)) ** 1.4
            dens += body * env * (0.72 + 0.28 * hgt)
        dens *= 0.70 + 0.45 * fn + 0.25 * (tr - 0.5)
        dens = np.clip(dens, 0, 1.6)
        # temperature: hottest low and in the thick of it
        temp = np.clip(dens * (1.05 - 0.55 * v), 0, 1.3)
        stops = [(0.00, (60, 8, 2)), (0.18, (150, 30, 6)),
                 (0.38, (235, 88, 18)), (0.60, (255, 158, 46)),
                 (0.82, (255, 222, 120)), (1.05, (255, 248, 226))]
        rgb = np.zeros(u.shape + (3,), np.float32)
        xs_ = [p for p, _ in stops]
        for c in range(3):
            rgb[..., c] = np.interp(temp, xs_, [col[c] for _, col in stops])
        a = np.clip(dens * 1.25, 0, 1) ** 1.1
        img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255),
                                         a * 255]).astype(np.uint8), "RGBA")
        frames.append(img.resize((FLAME_W, FLAME_H), Image.LANCZOS))
    strip = Image.new("RGBA", (FLAME_W * FLAME_FRAMES, FLAME_H), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        strip.paste(fr, (i * FLAME_W, 0))
    return strip


# ---------------------------------------------------------------------------
# The things that stand in it
# ---------------------------------------------------------------------------
# The Bastet, seated in profile and facing +u (across the nave). `hall_bastet`
# mirrors the card on the far side, so a pair face each other.
#
# Her outline follows the owner's reference statue (a Bastet in black bronze,
# the Gayer-Anderson type), read off its silhouette and written down here as
# points: in the reference's own frame (u across, v down, 0..1 over the
# photograph's crop), mirrored so she faces right. `BASTET_BOX` maps that frame
# onto the figure. What makes her a cat rather than a hare or a hound: a big
# upright ear with a broad base set well back on the skull, a short wedge of a
# muzzle under a full brow, a long thick neck, the chest carried high and
# forward, and an open arch between the foreleg and the haunch.
BASTET_BOX = (0.075, 0.012, 0.965, 0.995)      # u0, v0, u1, v1 of the figure

BASTET_REF = [
    # the ear, leaning a little forward, its tip over the brow
    (0.708, 0.108), (0.742, 0.078), (0.776, 0.052), (0.806, 0.030),
    (0.832, 0.016), (0.846, 0.012), (0.854, 0.022), (0.852, 0.045),
    (0.842, 0.070), (0.838, 0.092),
    # brow, bridge, nose, mouth, chin
    (0.864, 0.106), (0.890, 0.120), (0.905, 0.136), (0.909, 0.155),
    (0.914, 0.178), (0.924, 0.196), (0.938, 0.210), (0.944, 0.222),
    (0.938, 0.234), (0.924, 0.242), (0.910, 0.250), (0.894, 0.257),
    # under the jaw and down the throat into the collar
    (0.860, 0.262), (0.822, 0.270), (0.808, 0.285), (0.811, 0.310),
    # the chest, carried forward
    (0.822, 0.340), (0.836, 0.372), (0.843, 0.405), (0.840, 0.445),
    (0.838, 0.485), (0.828, 0.525), (0.808, 0.560),
    # the foreleg, straight down, to the paw
    (0.798, 0.610), (0.793, 0.690), (0.794, 0.770), (0.800, 0.840),
    (0.812, 0.872), (0.842, 0.884), (0.870, 0.892), (0.884, 0.904),
    (0.886, 0.914),
    # the base slab, its corners rounded
    (0.950, 0.916), (0.963, 0.930), (0.965, 0.975), (0.952, 0.995),
    (0.520, 0.996),
    (0.092, 0.995), (0.077, 0.978), (0.076, 0.930), (0.090, 0.916),
    # the haunch, round and full, up into the back
    (0.180, 0.914), (0.166, 0.880), (0.158, 0.830), (0.157, 0.780),
    (0.162, 0.730), (0.176, 0.680), (0.192, 0.635), (0.210, 0.595),
    (0.232, 0.556), (0.256, 0.518), (0.290, 0.478), (0.340, 0.440),
    (0.410, 0.408), (0.480, 0.380), (0.520, 0.356), (0.540, 0.330),
    # the back of the neck, up to the skull behind the ear
    (0.560, 0.300), (0.584, 0.270), (0.602, 0.250), (0.620, 0.228),
    (0.638, 0.208), (0.650, 0.180), (0.662, 0.155), (0.680, 0.132),
]

# The opening between the foreleg and the haunch: a tall arch whose front
# edge is the foreleg's back edge (`BASTET_FORELEG`) and whose foot is the
# tail and the hind paw.
BASTET_ARCH = [
    (0.598, 0.588), (0.622, 0.598), (0.655, 0.620), (0.688, 0.652),
    (0.710, 0.690), (0.722, 0.740), (0.728, 0.790), (0.732, 0.840),
    (0.736, 0.866), (0.620, 0.868), (0.540, 0.866), (0.530, 0.790),
    (0.540, 0.700), (0.565, 0.630),
]

# Her parts, in the reference's frame, used twice: for the relief on the
# card (`BASTET_PARTS`) and for the solid she is swept into
# (`BASTET_SOLIDS`). The far ear is the pair's other half, set back and
# showing past the near one, which is what makes the card read as a head with
# two sides.
BASTET_FAR_EAR = [(0.706, 0.124), (0.716, 0.086), (0.736, 0.050),
                  (0.758, 0.026), (0.776, 0.020), (0.786, 0.040),
                  (0.790, 0.076), (0.786, 0.110), (0.750, 0.124)]
BASTET_HAUNCH = [(0.200, 0.560), (0.320, 0.522), (0.450, 0.548),
                 (0.540, 0.608), (0.576, 0.700), (0.566, 0.792),
                 (0.530, 0.852), (0.450, 0.884), (0.300, 0.896),
                 (0.200, 0.884), (0.160, 0.800), (0.156, 0.680)]
BASTET_HIND_PAW = [(0.450, 0.852), (0.540, 0.866), (0.600, 0.878),
                   (0.626, 0.892), (0.622, 0.912), (0.450, 0.914)]
BASTET_CHEST = [(0.690, 0.300), (0.790, 0.296), (0.822, 0.340),
                (0.842, 0.405), (0.840, 0.470), (0.800, 0.520),
                (0.730, 0.520), (0.690, 0.440)]
# The forelegs, side by side, so from the side they are one leg. It flows
# out of the chest: its back edge curves out from under the belly at the
# elbow (the arch's front edge) and runs down to the wrist, and it ends in a
# large rounded paw. Its top reaches up into the chest, where it blends away.
BASTET_FORELEG = [(0.640, 0.560), (0.700, 0.500), (0.760, 0.460),
                  (0.820, 0.462), (0.838, 0.490), (0.826, 0.530),
                  (0.810, 0.562), (0.799, 0.600), (0.795, 0.640),
                  (0.793, 0.690), (0.794, 0.770), (0.799, 0.830),
                  (0.806, 0.858), (0.826, 0.866), (0.856, 0.872),
                  (0.880, 0.884), (0.891, 0.898), (0.888, 0.914),
                  (0.750, 0.914), (0.740, 0.896), (0.736, 0.866),
                  (0.732, 0.840), (0.728, 0.790), (0.722, 0.740),
                  (0.710, 0.690), (0.688, 0.652), (0.655, 0.620),
                  (0.622, 0.598)]
# The tail, lying along the base round her near side, its tip between the
# hind paw and the forepaws.
BASTET_TAIL = [(0.420, 0.884), (0.520, 0.874), (0.620, 0.866),
               (0.700, 0.864), (0.752, 0.868), (0.770, 0.884),
               (0.762, 0.902), (0.720, 0.910), (0.620, 0.912),
               (0.520, 0.912), (0.420, 0.910)]
# Where the torso's solid stops, so the forelegs' solids stand clear of it:
# from the top of the arch along the underside of the belly and chest.
BASTET_TORSO_CUT = [(0.600, 0.600), (0.625, 0.585), (0.650, 0.565),
                    (0.700, 0.552), (0.745, 0.540), (0.800, 0.528),
                    (1.0, 0.528), (1.0, 1.0), (0.600, 1.0)]
BASTET_HEAD = [(0.668, 0.150), (0.700, 0.114), (0.760, 0.098),
               (0.830, 0.100), (0.880, 0.116), (0.906, 0.140),
               (0.912, 0.172), (0.926, 0.196), (0.944, 0.222),
               (0.930, 0.240), (0.896, 0.258), (0.840, 0.270),
               (0.770, 0.262), (0.712, 0.240), (0.676, 0.200)]
BASTET_NEAR_EAR = [(0.708, 0.110), (0.742, 0.078), (0.776, 0.052),
                   (0.806, 0.030), (0.832, 0.016), (0.846, 0.012),
                   (0.854, 0.024), (0.852, 0.046), (0.842, 0.072),
                   (0.836, 0.100), (0.790, 0.116)]
# The base slab is straight-sided (a spline would overshoot its corners).
BASTET_BASE = [(0.090, 0.916), (0.950, 0.916), (0.963, 0.930),
               (0.965, 0.975), (0.952, 0.995), (0.092, 0.995),
               (0.077, 0.978), (0.076, 0.930)]

# She is carved as a relief is: each part a rounded form of its own, laid
# over the ones behind it. Each is `(outline, base, swell, join, emerge)`,
# back to front: `base` is how far forward its edge stands and `swell` how
# much it rounds up from there. `emerge` (heights, or `None`) is a stretch
# over which a part rises out of what is above it, as the leg does out of the
# chest, rather than stopping in an end of its own. A part that crosses
# another (the haunch over the body) has a crease where it does (`join`
# "crease"); one that grows out of what is behind it (the leg out of the
# chest, the head out of the neck) blends into it ("blend").
BASTET_PARTS = [
    (BASTET_FAR_EAR, 0.10, 0.16, "crease", None),
    (None, 0.22, 0.46, "crease", None),           # the body (see below)
    (BASTET_TAIL, 0.30, 0.12, "crease", None),
    (BASTET_HAUNCH, 0.36, 0.58, "crease", None),
    (BASTET_HIND_PAW, 0.40, 0.18, "crease", None),
    (BASTET_FORELEG, 0.30, 0.30, "blend", (0.500, 0.660)),
    (BASTET_CHEST, 0.34, 0.36, "blend", None),
    (BASTET_HEAD, 0.40, 0.46, "blend", None),
    (BASTET_NEAR_EAR, 0.40, 0.20, "blend", None),
    (BASTET_BASE, 0.18, 0.10, "crease", None),
]

# ...and the solid she is swept into (`hall_bastet_sweep`): each part swept
# round its own axis and set to her near side (-) or far side (+), so seen
# from above her legs are legs with space between them. The forelegs start up
# inside the chest and are deepest there, so from the front and from above
# they widen into it. Each is `(name,
# outline, heights kept (v0, v1), cut away, added, side, half-depth)`:
# `None` for her whole outline; `cut` is a region taken out and `added` one
# put back; side and half-depth are shares of the card's width, the
# half-depth a number or `[(v, d), ...]`.
# A foreleg's half-depth down its length: deepest where it leaves the chest.
_FORELEG_DEPTH = [(0.460, 0.050), (0.580, 0.048), (0.680, 0.040),
                  (0.780, 0.036), (0.860, 0.035), (0.900, 0.040),
                  (0.914, 0.040)]
BASTET_SOLIDS = [
    # the torso: head, neck, chest, back and haunch. It carries the skull up
    # into the ears' bases, where the ears' back edges run into the back of
    # the head, and the ears stand free above that; the legs stand apart
    # from it.
    ("torso", None, (0.080, 0.914),
     BASTET_TORSO_CUT, BASTET_HEAD,
     0.0, [(0.080, 0.036), (0.095, 0.052), (0.115, 0.080), (0.140, 0.096),
           (0.200, 0.102),
           (0.260, 0.090),
           (0.340, 0.098), (0.450, 0.112), (0.550, 0.124), (0.650, 0.146),
           (0.800, 0.158), (0.914, 0.150)]),
    ("near ear", BASTET_NEAR_EAR, (0.0, 0.118), None, None, -0.034, 0.015),
    ("far ear", BASTET_FAR_EAR, (0.0, 0.124), None, None, 0.034, 0.015),
    ("near foreleg", BASTET_FORELEG, (0.460, 0.914), None, None, -0.055,
     _FORELEG_DEPTH),
    ("far foreleg", BASTET_FORELEG, (0.460, 0.914), None, None, 0.055,
     _FORELEG_DEPTH),
    ("tail", BASTET_TAIL, (0.860, 0.914), None, None, -0.120, 0.022),
    ("near hind paw", BASTET_HIND_PAW, (0.850, 0.914), None, None, -0.105,
     0.032),
    ("far hind paw", BASTET_HIND_PAW, (0.850, 0.914), None, None, 0.105,
     0.032),
    ("base", BASTET_BASE, (0.914, 0.996), None, None, 0.0, 0.210),
]

# The broad collar, as the two curves bounding it: its top edge under the
# jaw, and its lower edge round the chest. Its rows run between them.
BASTET_COLLAR_TOP = [(0.618, 0.214), (0.690, 0.236), (0.760, 0.258),
                     (0.816, 0.272)]
BASTET_COLLAR_BOT = [(0.536, 0.320), (0.640, 0.352), (0.745, 0.382),
                     (0.838, 0.404)]

# The light that models her: from above and toward the camera, a little from
# her front. A second, cold light rims her from above and behind.
BASTET_LIGHT = (0.42, -0.70, 0.58)
BASTET_RIM = (-0.70, -0.55, 0.20)

# Lapis, for the collar's inlaid rows.
LAPIS = (24, 44, 122)
LAPIS_HOT = (84, 118, 214)


def _bastet_ref_to_fig(p):
    u0, v0, u1, v1 = BASTET_BOX
    return ((p[0] - u0) / (u1 - u0), (p[1] - v0) / (v1 - v0))


def _curve_at(curve, t):
    """A point along a polyline, by its share of the length."""
    seg = []
    tot = 0.0
    for i in range(len(curve) - 1):
        l = math.hypot(curve[i + 1][0] - curve[i][0],
                       curve[i + 1][1] - curve[i][1])
        seg.append(l)
        tot += l
    d = t * tot
    for i, l in enumerate(seg):
        if d <= l or i == len(seg) - 1:
            f = 0 if l == 0 else min(1, d / l)
            return (curve[i][0] + (curve[i + 1][0] - curve[i][0]) * f,
                    curve[i][1] + (curve[i + 1][1] - curve[i][1]) * f)
        d -= l
    return curve[-1]


def bastet(w=512, h=768):
    """A seated Bastet, in profile, as one card: black basalt, polished; a
    broad collar of gold and lapis with a row of gold drops; a gilt eye with
    Ashiah's red in it, glowing, and a kohl line; a gold hoop in her ear.

    She is modelled as a relief (`BASTET_PARTS`): each part rounds up from
    its own edge and stands over the parts behind it, so her ears, legs,
    haunch and chest each have an edge and a shadowed crease where they cross.

    Returns the figure; its rim (the upward edges and the glow of her eye,
    drawn additively); and the outlines of the parts she is swept into
    (`BASTET_SOLIDS`), as masks in the figure's own box.
    """
    from scipy import ndimage as _nd
    W, H = w * SS, h * SS
    size = (W, H)
    fh = 0.94 * H
    u0, v0, u1, v1 = BASTET_BOX
    fw = fh * (u1 - u0) / (v1 - v0) * (1220.0 / 1700.0)
    fx = (W - fw) / 2
    fy = 0.03 * H
    s = SS

    def pt(p):
        f = _bastet_ref_to_fig(p)
        return (fx + f[0] * fw, fy + f[1] * fh)

    def shape(pts, n=10):
        pp = pts if pts is BASTET_BASE else spline(pts, n=n)
        m = Image.new("L", size, 0)
        ImageDraw.Draw(m).polygon([pt(p) for p in pp], fill=255)
        return m

    # --- the silhouette: her outline, the far ear, the far foreleg --------
    body = shape(BASTET_REF)
    ImageDraw.Draw(body).polygon([pt(p) for p in spline(BASTET_ARCH, n=10)],
                                 fill=0)
    sil = body.copy()
    for (pts, _, _, _, _) in BASTET_PARTS:
        if pts is not None:
            sil = ImageChops.lighter(sil, shape(pts))
    sil = sil.filter(ImageFilter.GaussianBlur(1.0 * s)).point(
        lambda v: 255 if v > 128 else 0)
    a = np.asarray(sil, np.float32) / 255.0

    # --- the relief: each part rounded up from its edge, nearer over farther
    hgt = np.zeros((H, W), np.float32)
    own = np.full((H, W), -1, np.int32)      # which part is on top, per pixel
    vs = (np.arange(H, dtype=np.float32)[:, None] - fy) / fh
    vs = v0 + vs * (v1 - v0)                 # each row's height, ref frame
    for k, (pts, base, swell, join, emerge) in enumerate(BASTET_PARTS):
        m = body if pts is None else shape(pts)
        ma = (np.asarray(m, np.float32) / 255.0 > 0.5) & (a > 0.5)
        d = _nd.distance_transform_edt(ma)
        r = max(1.0, float(d.max()))
        # rounded over from the edge, and smoothed within the part so its
        # crown has no ridge down the middle
        prof = np.sqrt(np.clip(d / r, 0, 1))
        prof = _nd.gaussian_filter(prof, 0.10 * r) * ma
        ph = base + swell * prof
        if emerge is not None:
            e = np.clip((vs - emerge[0]) / (emerge[1] - emerge[0]), 0, 1)
            ph = ph * (0.45 + 0.55 * e * e * (3 - 2 * e))
        ph = np.where(ma, ph, 0)
        if join == "blend":
            # grown out of what is behind: a smooth union, no edge
            kb = 0.10
            t = np.clip(0.5 + 0.5 * (ph - hgt) / kb, 0, 1)
            hgt = np.where(ma, hgt * (1 - t) + ph * t + kb * t * (1 - t),
                           hgt)
            continue
        own = np.where(ma & (ph >= hgt), k, own)
        hgt = np.maximum(hgt, ph)
    # The creases: at the foot of each step where one part stands over the
    # part beside it, on the lower side. Found once every part is down, so
    # the outline of a part another covers leaves no line.
    rr = int(3 * s)
    edge = np.zeros((H, W), np.float32)
    for k in range(len(BASTET_PARTS)):
        mine = own == k
        if not mine.any():
            continue
        other = np.where((own != k) & (own >= 0), hgt, -1.0)
        hm = _nd.maximum_filter(other, size=2 * rr + 1)
        edge = np.where(mine, np.clip(hm - hgt - 0.02, 0, None), edge)
    # Round the steps into tight creases rather than cut-outs.
    hgt = _nd.gaussian_filter(hgt, 1.6 * s) * a
    # A fine grain in the stone, so its polish isn't the smooth sheen of a
    # moulding.
    grain = _nd.gaussian_filter(
        np.random.default_rng(17).normal(0, 1, (H, W)).astype(np.float32),
        0.9 * s)
    hgt = hgt + grain * 0.0006

    # --- ornament ------------------------------------------------------------
    rel = Image.new("L", size, 128)          # +/- relief
    dr = ImageDraw.Draw(rel)
    gold = Image.new("L", size, 0)
    dg = ImageDraw.Draw(gold)
    lapis = Image.new("L", size, 0)
    dl = ImageDraw.Draw(lapis)

    # The collar: rows between its two bounding curves, alternating gold and
    # lapis, then a row of gold drops along its lower edge; it stands a
    # little proud of the neck.
    def row(r0, r1, n=40):
        top = [_curve_at(BASTET_COLLAR_TOP, i / n) for i in range(n + 1)]
        bot = [_curve_at(BASTET_COLLAR_BOT, i / n) for i in range(n + 1)]
        ra = [(t[0] + (b[0] - t[0]) * r0, t[1] + (b[1] - t[1]) * r0)
              for t, b in zip(top, bot)]
        rb = [(t[0] + (b[0] - t[0]) * r1, t[1] + (b[1] - t[1]) * r1)
              for t, b in zip(top, bot)]
        return [pt(p) for p in ra + rb[::-1]]

    for (r0, r1, kind) in ((0.00, 0.07, "g"), (0.07, 0.24, "l"),
                           (0.24, 0.31, "g"), (0.31, 0.50, "l"),
                           (0.50, 0.57, "g"), (0.57, 0.64, "l")):
        poly = row(r0, r1)
        (dg if kind == "g" else dl).polygon(poly, fill=255)
        dr.polygon(poly, fill=170 if kind == "g" else 156)
    for i in range(1, 14):
        t = i / 14.0
        tp = _curve_at(BASTET_COLLAR_TOP, t)
        bp = _curve_at(BASTET_COLLAR_BOT, t)
        c = pt((tp[0] + (bp[0] - tp[0]) * 0.405,
                tp[1] + (bp[1] - tp[1]) * 0.405))
        r = fw * 0.0065
        for dd, v in ((dg, 255), (dr, 196)):
            dd.ellipse([c[0] - r, c[1] - r * 1.4, c[0] + r, c[1] + r * 1.4],
                       fill=v)
    for i in range(15):
        t = (i + 0.5) / 15.0
        tp = _curve_at(BASTET_COLLAR_TOP, t)
        bp = _curve_at(BASTET_COLLAR_BOT, t)
        p0 = pt((tp[0] + (bp[0] - tp[0]) * 0.66,
                 tp[1] + (bp[1] - tp[1]) * 0.66))
        p1 = pt(bp)
        wdt = fw * 0.011
        drop = [(p0[0] - wdt * 0.5, p0[1]), (p0[0] + wdt * 0.5, p0[1])]
        for kk in range(9):
            ang = math.pi * kk / 8
            drop.append((p1[0] + math.cos(ang) * wdt,
                         p1[1] - wdt * 0.6 + math.sin(ang) * wdt))
        dg.polygon(drop, fill=255)
        dr.polygon(drop, fill=186)

    # the near ear's bowl, cut in, and the gold hoop in it
    dr.polygon([pt(p) for p in spline(
        [(0.762, 0.090), (0.792, 0.058), (0.822, 0.034), (0.834, 0.060),
         (0.828, 0.090), (0.792, 0.100)])], fill=44)
    hx, hy = pt((0.790, 0.094))
    hr = fw * 0.018
    dg.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], outline=255,
               width=int(fw * 0.0075))
    dr.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], outline=206,
               width=int(fw * 0.0075))

    # the eye: a gilt rim, a red iris, a slit pupil; the kohl line back
    ex, ey = pt((0.872, 0.173))
    ew, eh = fw * 0.030, fw * 0.014
    eye = [(ex + math.cos(t) * ew,
            ey + math.sin(t) * eh * (1.0 if math.sin(t) > 0 else 0.8))
           for t in np.linspace(0, 2 * math.pi, 40)]
    dg.polygon(eye, fill=255)
    dr.polygon(eye, fill=150)
    iris = Image.new("L", size, 0)
    ImageDraw.Draw(iris).ellipse([ex - ew * 0.62, ey - eh * 0.72,
                                  ex + ew * 0.62, ey + eh * 0.72], fill=255)
    dr.ellipse([ex - ew * 0.62, ey - eh * 0.72, ex + ew * 0.62,
                ey + eh * 0.72], fill=110)
    pupil = Image.new("L", size, 0)
    ImageDraw.Draw(pupil).ellipse([ex - ew * 0.13, ey - eh * 0.66,
                                   ex + ew * 0.13, ey + eh * 0.66], fill=255)
    k0, k1 = (ex - ew * 0.95, ey + eh * 0.1), pt((0.830, 0.165))
    dg.line([k0, k1], fill=255, width=int(fw * 0.007))
    dr.line([k0, k1], fill=180, width=int(fw * 0.007))
    dr.line([pt((0.850, 0.159)), pt((0.876, 0.154)), pt((0.898, 0.161))],
            fill=176, width=int(fw * 0.008), joint="curve")

    # the nose and mouth, cut in; the whisker pad standing
    dr.line([pt((0.936, 0.214)), pt((0.941, 0.221)), pt((0.934, 0.228))],
            fill=50, width=int(fw * 0.007), joint="curve")
    dr.line([pt((0.930, 0.236)), pt((0.906, 0.242))], fill=70,
            width=int(fw * 0.005))
    dr.ellipse(list(pt((0.900, 0.214))) + list(pt((0.926, 0.236))), fill=160)
    # the toes of the near forepaw and of the hind paw, and the rings on
    # the tail where it shows between them
    for (u0, v0, n) in ((0.848, 0.886, 3), (0.588, 0.892, 2)):
        for i in range(n):
            u = u0 + i * 0.014
            dr.line([pt((u, v0)), pt((u + 0.003, 0.911))], fill=66,
                    width=int(fw * 0.005))
    for u in (0.642, 0.662, 0.682):
        dr.line([pt((u, 0.868)), pt((u - 0.006, 0.908))], fill=84,
                width=int(fw * 0.004))

    rel = rel.filter(ImageFilter.GaussianBlur(1.0 * s))
    hgt = hgt + (np.asarray(rel, np.float32) - 128.0) / 128.0 * 0.035
    gold = np.asarray(gold.filter(ImageFilter.GaussianBlur(0.5 * s)),
                      np.float32) / 255.0
    lap = np.asarray(lapis.filter(ImageFilter.GaussianBlur(0.5 * s)),
                     np.float32) / 255.0 * (1 - gold)
    iri = np.asarray(iris.filter(ImageFilter.GaussianBlur(0.4 * s)),
                     np.float32) / 255.0
    pup = np.asarray(pupil.filter(ImageFilter.GaussianBlur(0.3 * s)),
                     np.float32) / 255.0

    # --- light it ---------------------------------------------------------------
    gy, gx = np.gradient(hgt * fw * 0.22)
    nx, ny, nz = -gx, -gy, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln

    def unit(v):
        v = np.array(v, np.float64)
        return v / np.linalg.norm(v)

    lv, rv = unit(BASTET_LIGHT), unit(BASTET_RIM)
    hv = unit(lv + np.array([0.0, 0.0, 1.0]))
    lam = np.clip(nx * lv[0] + ny * lv[1] + nz * lv[2], 0, 1)
    rim = np.clip(nx * rv[0] + ny * rv[1] + nz * rv[2], 0, 1) ** 3
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1)
    # The creases where one part crosses another, and the hollows of the
    # carving, hold shadow.
    cav = np.clip(_nd.gaussian_filter(hgt, 5 * s) - hgt, 0, None)
    crease = _nd.gaussian_filter(edge, 1.5 * s)
    occl = np.clip(1 - cav * 10.0 - crease * 0.9, 0.35, 1)

    def material(dark, lit, sp, gamma, shine, power, amb=0.12):
        d0 = np.array(dark, np.float32)[None, None, :]
        d1 = np.array(lit, np.float32)[None, None, :]
        d2 = np.array(sp, np.float32)[None, None, :]
        k_ = amb + (1 - amb) * lam ** gamma
        return (d0 + (d1 - d0) * k_[..., None]
                + d2 * ((spec ** power) * shine)[..., None])

    stone = material(CAT_DARK, CAT_LIT, CAT_SPEC, 1.8, 0.55, 70)
    stone += np.array([34, 42, 62], np.float32)[None, None, :] * rim[..., None]
    metal = material(AU_DARK, AU_LIT, AU_SPEC, 1.0, 0.65, 14, amb=0.35)
    blue = material(tuple(c * 0.35 for c in LAPIS), LAPIS, LAPIS_HOT, 1.2,
                    0.35, 24)
    # Her eyes are Ashiah's red.
    ruby = material((60, 4, 6), (214, 28, 26), (255, 150, 120), 0.8, 0.5,
                    10, amb=0.6)
    rgb = stone
    rgb = rgb + (blue - rgb) * lap[..., None]
    rgb = rgb + (metal - rgb) * gold[..., None]
    rgb = rgb + (ruby - rgb) * iri[..., None]
    rgb = rgb * (1 - pup[..., None] * 0.92)
    rgb = rgb * occl[..., None]

    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8),
                          "RGB").convert("RGBA")
    img.putalpha(sil)
    img = down(img, w, h)
    box = img.split()[3].getbbox()
    m = 3
    box = (max(0, box[0] - m), max(0, box[1] - m),
           min(img.width, box[2] + m), min(img.height, box[3] + m))
    img = img.crop(box)
    # Her colour is carried out past her outline (each clear texel takes the
    # nearest of hers), so where the solid samples just outside it, it shows
    # stone rather than a gap (the hall draws her ignoring the alpha).
    arr = np.asarray(img).copy()
    clear = arr[..., 3] < 128
    if clear.any():
        _, idx = _nd.distance_transform_edt(clear, return_indices=True)
        arr[..., :3] = arr[idx[0], idx[1], :3]
        img = Image.fromarray(arr, "RGBA")

    # the rim: a faint cold edge along her upper surfaces, and her eye's glow
    rim_img = A.rim_light(img.split()[3], ORB, drop=3, blur=2.0, strength=0.40)
    glow = Image.new("L", size, 0)
    ImageDraw.Draw(glow).ellipse([ex - ew * 0.75, ey - eh * 0.9,
                                  ex + ew * 0.75, ey + eh * 0.9], fill=255)
    glow = down(glow.filter(ImageFilter.GaussianBlur(ew * 0.35)), w, h).crop(box)
    red = Image.new("RGBA", glow.size, (255, 40, 30, 0))
    red.putalpha(glow)
    rim_img.alpha_composite(red)

    # the parts she is swept into, as masks in the same box
    solids = []
    for (name, pts, keep, cut, added, side, depth) in BASTET_SOLIDS:
        mm = body.copy() if pts is None else shape(pts)
        dm = ImageDraw.Draw(mm)
        if keep is not None:
            dm.rectangle([0, 0, W, pt((0, keep[0]))[1]], fill=0)
            dm.rectangle([0, pt((0, keep[1]))[1], W, H], fill=0)
        if cut is not None:
            dm.polygon([pt(q) for q in cut], fill=0)
        if added is not None:
            mm = ImageChops.lighter(mm, shape(added))
        mm = ImageChops.multiply(mm, sil)
        solids.append((name, down(mm, w, h).crop(box), side, depth))
    return img, rim_img, solids


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
# from above), part by part (`BASTET_SOLIDS`): each part is swept round its
# own axis and set to her near or far side. Its cross-section at each height
# is measured off the part's outline in the shipped sprite's own box, so the
# card and the solid agree. The one thing a profile can't give is width, so
# that is authored: each part's half-depth, as a share of the card's width.
# ---------------------------------------------------------------------------
BASTET_ROWS = {"torso": 30, "base": 5}
BASTET_ROWS_PART = 10

BASTET_TABLE_GML = '''/// @desc The Gilded Sanctum's measured numbers -- GENERATED by
///       tools/make_sanctum.py. Do not edit.
///
/// The parts the Bastet is swept into (`hall_bastet_sweep`): her torso, her
/// ears, her legs and paws, and her base, each swept round its own axis.
/// Each part is `{name, z, rows}`: `z` is how far to her near (-) or far (+)
/// side it stands, as a share of the card's width; each row is `[v, u0, u1,
/// d]` in the sprite's own box, 0..1 from its top-left: the height, the back
/// and the front of the part at that height (read off its outline, so the
/// card and the solid agree), and its half-depth (authored: a profile can't
/// say how wide a thing is), as a share of the card's width.

function sanctum_table_init() {
    global.bastet_parts = [
%s
    ];
}

/// @desc Part `_p`'s cross-section at height `_v`, as `[centre, half-length,
///       half-depth]` in the sprite's own box, interpolated between its
///       measured rows (and held at its ends).
function bastet_part_at(_p, _v) {
    var _t = _p.rows;
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


def _depth_at(depth, v):
    """A part's authored half-depth at height `v`: a number, or a table of
    `(v, d)` interpolated."""
    if not isinstance(depth, (list, tuple)):
        return depth
    if v <= depth[0][0]:
        return depth[0][1]
    for i in range(len(depth) - 1):
        a, b = depth[i], depth[i + 1]
        if v <= b[0]:
            return a[1] + (b[1] - a[1]) * (v - a[0]) / (b[0] - a[0])
    return depth[-1][1]


def bastet_solid_rows(solids):
    """Each part's rows, read off its mask. A row with no ink takes the
    nearest that has some, rather than a zero-length slice."""
    out = []
    for (name, mask, side, depth) in solids:
        a = np.asarray(mask) > 100
        h, w = a.shape
        ys = [y for y in range(h) if a[y].any()]
        if not ys:
            raise SystemExit("bastet: part %s has no ink" % name)
        y0, y1 = ys[0], ys[-1]
        n = BASTET_ROWS.get(name, BASTET_ROWS_PART)
        rows = []
        for i in range(n):
            y = int(round(y0 + (y1 - y0) * i / (n - 1.0)))
            if not a[y].any():
                y = min(ys, key=lambda q: abs(q - y))
            xs = np.nonzero(a[y])[0]
            v = (y + 0.5) / h
            # heights in the reference's frame, for the authored depth
            vr = BASTET_BOX[1] + v * (BASTET_BOX[3] - BASTET_BOX[1])
            rows.append((v, float(xs[0]) / w, float(xs[-1] + 1) / w,
                         _depth_at(depth, vr)))
        out.append((name, side, rows))
    return [_seat_ear(p, out[0]) if p[0].endswith("ear") else p for p in out]


def _torso_at(torso, v):
    """The torso's section at height `v` as `(centre, half-length,
    half-depth)`, or None above or below it."""
    rows = torso[2]
    if v < rows[0][0] or v > rows[-1][0]:
        return None
    for a, b in zip(rows, rows[1:]):
        if a[0] <= v <= b[0]:
            t = (v - a[0]) / max(1e-6, b[0] - a[0])
            u0 = a[1] + (b[1] - a[1]) * t
            u1 = a[2] + (b[2] - a[2]) * t
            return ((u0 + u1) / 2, (u1 - u0) / 2, a[3] + (b[3] - a[3]) * t)
    return None


def _seat_ear(ear, torso):
    """An ear's rows, trimmed where they reach into the head so none of it
    stands outside the skull: at each height the head has, the ear keeps
    only the stretch the head's section spans at the ear's depth. Above the
    skull it stands free."""
    name, side, rows = ear
    out = []
    for (v, u0, u1, d) in rows:
        sec = _torso_at(torso, v)
        if sec is not None and abs(side) < sec[2]:
            c, half, deep = sec
            k = half * math.sqrt(1 - (side / deep) ** 2)
            lo, hi = c - k, c + k
            n0, n1 = max(u0, lo), min(u1, hi)
            if n1 <= n0:
                n0 = n1 = min(max((u0 + u1) / 2, lo), hi)
            u0, u1 = n0, n1
        out.append((v, u0, u1, d))
    return (name, side, out)


def write_bastet_table(parts):
    blocks = []
    for (name, side, rows) in parts:
        body = "\n".join("            [%.4f, %.4f, %.4f, %.4f]," % r
                         for r in rows)
        blocks.append("        { name: \"%s\", z: %.4f, rows: [\n%s\n"
                      "        ] }," % (name, side, body))
    path = os.path.join(A.ROOT, "scripts", "sanctum_table",
                        "sanctum_table.gml")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    gm_new.write(path, BASTET_TABLE_GML % "\n".join(blocks))
    gm_new.script("sanctum_table")
    print("sanctum_table.gml: the bastet in %d parts, %d rows"
          % (len(parts), sum(len(r) for (_, _, r) in parts)))


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
    # The pavement and the carved stone carry their gloss in the alpha
    # (`sanctum_relief`).
    slab, runner, border = floor_tile(), runner_tile(), border_course()
    gm_new.sprite("spr_hall_floor", [slab], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_runner", [runner], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_border", [border], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)

    # the sky, and the instrument hanging in it
    gm_new.sprite("spr_hall_star", [star_point(0), star_point(1),
                                    star_point(2)],
                  origin="center", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_neb", [nebula(301), nebula(302), nebula(303)],
                  origin="center", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_zodiac", [zodiac_band()], origin="topleft",
                  folder=f, texgroup=HALL_TEXGROUP)
    rot, rot_lit = rotunda()
    gm_new.sprite("spr_hall_rot", [rot], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_rot_lit", [rot_lit], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)

    cat, cat_rim, cat_solids = bastet()
    gm_new.sprite("spr_hall_bastet", [cat], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_bastet_rim", [cat_rim], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    write_bastet_table(bastet_solid_rows(cat_solids))

    b0, r0 = banner(0)
    b1, r1 = banner(1)
    gm_new.sprite("spr_hall_banner", [b0, b1], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_banner_rim", [r0, r1], origin="topleft", folder=f)

    d0, dr0 = desk(0)
    d1, dr1 = desk(1)
    gm_new.sprite("spr_hall_desk", [d0, d1], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_desk_rim", [dr0, dr1], origin="topleft", folder=f)

    gm_new.sprite("spr_hall_stone", [stone_tile()], origin="topleft",
                  folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_pale", [pale_tile()], origin="topleft", folder=f,
                  texgroup=HALL_TEXGROUP)
    plinth, deskf = plinth_face(), desk_face()
    dado, cornice = dado_band(), cornice_band()
    gm_new.sprite("spr_hall_plinth", [plinth], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_deskface", [deskf], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_board", [board_edge()], origin="topleft",
                  folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_dado", [dado], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_cornice", [cornice], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_books",
                  [books_tile(701), books_tile(702), books_tile(703)],
                  origin="topleft", folder=f,
                  texgroup=HALL_TEXGROUP)
    pil, pil_glow = pilaster_face()
    gm_new.sprite("spr_hall_pil", [pil], origin="topleft", folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_pil_glow", [pil_glow], origin="topleft",
                  folder=f, texgroup=HALL_TEXGROUP)
    gm_new.sprite("spr_hall_flame", [flame_strip()], origin="topleft",
                  folder=f, texgroup=HALL_TEXGROUP)
    ob, ob_lit = orb()
    gm_new.sprite("spr_hall_orb", [ob], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_orb_lit", [ob_lit], origin="topleft", folder=f)

    lamp, lamp_em = orb_lamp()
    gm_new.sprite("spr_hall_lamp", [lamp], origin="topleft", folder=f)
    gm_new.sprite("spr_hall_lamp_lit", [lamp_em], origin="topleft", folder=f)

    A.preview(bays, os.path.join(A.PREVIEW, "sanctum_wall.png"),
              cols=3, bg=(10, 10, 14),
              labels=["bay: shelves", "bay: ladder", "bay: alcove"])
    A.preview([cat, b0, b1],
              os.path.join(A.PREVIEW, "sanctum_parts.png"), cols=3,
              bg=(10, 10, 14),
              labels=["bastet", "banner: crest", "banner: eye"])
    # The courses and the carved stone, as colour and as gloss. They are
    # dark: the hall's lights take them well past what is painted here.
    fl = [runner, border, slab]
    A.preview([SR.flat_view(i) for i in fl] + [SR.gloss_view(i) for i in fl],
              os.path.join(A.PREVIEW, "sanctum_floor.png"), cols=3,
              bg=(8, 8, 12),
              labels=["the runner", "the border course", "the marble field",
                      "gloss", "gloss", "gloss"])
    SG.specimen(os.path.join(A.PREVIEW, "sanctum_glyphs.png"), size=96)
    cs = [plinth, deskf, dado, cornice]
    A.preview([SR.flat_view(i) for i in cs],
              os.path.join(A.PREVIEW, "sanctum_carved.png"), cols=4,
              bg=(8, 8, 12),
              labels=["plinth", "pedestal", "dado", "cornice"])
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
               SR.flat_view(pil)],
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
