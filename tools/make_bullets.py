#!/usr/bin/env python3
"""Generate every bullet sprite, and `scripts/bullet_table/bullet_table.gml`.

- One sprite per shape, one frame per colour, so a bullet is drawn with
  `draw_sprite_ext(spr, colour, ...)`. An animated shape folds both into one
  index, `colour * frames + tick`, which `bullet_frame` in
  `danmaku_functions` computes.
- Oriented shapes point right at angle 0, like GameMaker's `direction`.
- This file is the only source of a bullet's hit radius. The table is written
  from the same catalogue as the pictures, so the two can't drift apart. (The
  flame is 66x42 of picture and 9.5 of hitbox; its tail isn't the bullet.)
- Each shape is a cut body (see "Cut bodies" in `art_common`): up to four
  masks (body, groove, bevel, core) rather than a shaded silhouette.

Usage:
    python tools/make_bullets.py          # -> sprites + bullet_table.gml
    python tools/make_bullets.py --preview-only
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SS = A.SS

# The mask-drawing kit is in `art_common` (the shards in `make_fx` use it too).
# Shapes are drawn in final pixels; `Cut` applies the supersample factor.
Cut = A.Cut
_ngon_pts = A.ngon_pts
_star_pts = A.star_pts
_polar = A.polar


# ---------------------------------------------------------------------------
# The round family: one sealed bead at four sizes
#
# A dark bezel, an engraved hoop, a lifted inner field, ticks through the
# outer band and a small hot core (the rings-and-marks language of
# `spr_boss_sigil`). Bigger sizes get more structure, not wider bands (see
# `edge_dist`).
# ---------------------------------------------------------------------------

def sh_pellet(w, h, **_):
    """Too small for a hoop: the bezel alone, a cut hexagonal bead with a hot
    centre.
    """
    c = Cut(w, h)
    c.ngon("body", c.cx, c.cy, 9.0, 6)
    c.ngon("core", c.cx, c.cy, 3.4, 6)
    c.blur("core", 0.30)
    return c


def _seal(c, r_body, r_ring, ring_w, ticks, tick_w, core_r, inner=None,
          alt=None):
    """A sealed bead: bezel, engraved hoop, lifted field, ticks, core.

    The field inside the hoop is lifted only part way (`v=160`), enough for the
    hoop to read as engraved.
    """
    cx, cy = c.cx, c.cy
    c.disc("body", cx, cy, r_body)
    c.disc("bevel", cx, cy, r_ring - ring_w * 0.5, v=160)
    c.hoop("groove", cx, cy, r_ring, ring_w)

    n, r0, r1 = ticks
    for i in range(n):
        # With `alt`, every other tick starts further out, so the ticks
        # alternate long and short.
        start = alt if (alt is not None and i % 2) else r0
        c.spoke("groove", cx, cy, i * 360.0 / n + 180.0 / n, start, r1, tick_w)

    if inner is not None:
        c.hoop("groove", cx, cy, inner[0], inner[1])
    c.ngon("core", cx, cy, core_r, 6)
    c.blur("core", 0.30)
    return c


def sh_orb(w, h, **_):
    return _seal(Cut(w, h), 13.5, 8.8, 1.2, (6, 10.4, 12.8), 1.2, 4.2)


def sh_ball(w, h, **_):
    return _seal(Cut(w, h), 22.0, 14.0, 1.6, (8, 16.2, 20.8), 1.6, 6.0)


def sh_sphere(w, h, **_):
    """The largest bead: twelve alternating ticks through the outer band, and a
    second hoop inside the first.
    """
    return _seal(Cut(w, h), 37.0, 24.0, 2.1, (12, 26.4, 35.2), 2.0, 9.0,
                 inner=(14.0, 1.8), alt=31.0)


# ---------------------------------------------------------------------------
# Hollow: a seal, and the circle that contains it
# ---------------------------------------------------------------------------

def sh_ring(w, h, **_):
    """A segmented seal: an annulus with a lit channel, cut through at the
    diagonals.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.annulus("body", cx, cy, 20.0, 11.5)
    c.annulus("core", cx, cy, 16.4, 14.4)
    c.blur("core", 0.35)
    for i in range(4):
        c.spoke("groove", cx, cy, 45.0 + i * 90.0, 10.5, 21.0, 1.7)
    return c


def sh_bubble(w, h, **_):
    """A containment circle: two concentric hoops braced by four spokes."""
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.annulus("body", cx, cy, 34.0, 27.0)
    for i in range(4):
        a = 45.0 + i * 90.0
        c.line("body", [_polar(cx, cy, a, 18.5), _polar(cx, cy, a, 28.0)], 3.4)
    c.annulus("body", cx, cy, 21.0, 18.0)

    c.annulus("core", cx, cy, 31.4, 29.6)
    c.blur("core", 0.35)
    for i in range(8):
        c.spoke("groove", cx, cy, i * 45.0 + 22.5, 26.0, 35.0, 1.5)
    return c


# ---------------------------------------------------------------------------
# The oriented family
#
# Every one points right, and its core is a blade of light along its own
# axis.
# ---------------------------------------------------------------------------

def _blade(cx, cy, x_nose, x_tail, half):
    """A lens along the axis: the shape an axial core always is."""
    return [(x_nose, cy), (cx, cy - half), (x_tail, cy), (cx, cy + half)]


def sh_rice(w, h, **_):
    """The small workhorse: a hexagonal lozenge rather than an ellipse, so it
    reads as a shard.
    """
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(32, cy), (23, cy - 7.5), (9, cy - 7.5),
                    (2, cy), (9, cy + 7.5), (23, cy + 7.5)])
    c.poly("core", _blade(16.0, cy, 28.0, 6.0, 2.2))
    c.blur("core", 0.30)
    return c


def sh_oval(w, h, **_):
    """A polished bead: a chamfered capsule with a table cut along it (the
    crystal's construction on a blunt body).
    """
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(9.5, cy - 11.5), (37.5, cy - 11.5), (44.5, cy - 7.0),
                    (44.5, cy + 7.0), (37.5, cy + 11.5), (9.5, cy + 11.5),
                    (2.5, cy + 7.0), (2.5, cy - 7.0)])
    table = [(42.0, cy), (23.5, cy - 8.6), (5.0, cy), (23.5, cy + 8.6)]
    c.poly("bevel", table)
    c.line("groove", table + [table[0]], 1.3)
    c.poly("core", _blade(23.5, cy, 35.0, 12.0, 2.3))
    c.blur("core", 0.30)
    return c


def sh_dart(w, h, **_):
    """A kunai: point, barbed blade, collar, shaft."""
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(44, cy), (24, cy - 11.0), (15, cy), (24, cy + 11.0)])
    c.poly("body", [(17.0, cy - 6.5), (20.5, cy - 6.5),
                    (20.5, cy + 6.5), (17.0, cy + 6.5)])
    c.poly("body", [(3, cy - 3.0), (19, cy - 3.0), (19, cy + 3.0),
                    (3, cy + 3.0)])
    for s in (-1, 1):
        c.line("groove", [(18.8, cy + s * 2.9), (18.8, cy + s * 6.2)], 1.2)
    c.poly("core", _blade(25.0, cy, 41.0, 17.0, 2.3))
    c.line("core", [(5.0, cy), (16.0, cy)], 1.5)
    c.blur("core", 0.30)
    return c


def sh_needle(w, h, **_):
    """A lance: spike, guard, haft (the guard gives it a sense of scale)."""
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(61, cy), (23, cy - 5.7), (23, cy + 5.7)])
    c.poly("body", [(19.5, cy - 6.7), (23.0, cy - 6.7),
                    (23.0, cy + 6.7), (19.5, cy + 6.7)])
    c.poly("body", [(3, cy - 1.7), (19.5, cy - 3.9), (19.5, cy + 3.9),
                    (3, cy + 1.7)])
    for s in (-1, 1):
        c.line("groove", [(21.2, cy + s * 2.4), (21.2, cy + s * 5.8)], 1.1)
    c.poly("core", _blade(26.0, cy, 56.0, 6.0, 1.5))
    c.blur("core", 0.28)
    return c


def sh_card(w, h, **_):
    """An ofuda: a paper slip with a point at the front and a V cut out of the
    tail, with an incantation burning along it as one zigzag stroke.
    """
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(44, cy), (36, cy - 8.6), (4, cy - 8.6), (9.5, cy),
                    (4, cy + 8.6), (36, cy + 8.6)])
    for s in (-1, 1):
        c.line("groove", [(11.5, cy + s * 6.2), (35.0, cy + s * 6.2)], 1.1)
    c.line("core", [(13.0, cy), (34.0, cy)], 1.5)
    for i, (up, dn) in enumerate(((4.6, 1.6), (2.0, 4.4), (4.2, 2.2),
                                  (1.8, 4.0))):
        x = 16.0 + i * 5.0
        c.line("core", [(x, cy - up), (x, cy + dn)], 1.6)
    c.blur("core", 0.28)
    return c


def sh_crystal(w, h, **_):
    """A cut shard, five facets of it visible: a table, two ridges and a groove
    along each.
    """
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(42, cy), (30, cy - 12.5), (12, cy - 12.5),
                    (2, cy), (12, cy + 12.5), (30, cy + 12.5)])
    table = [(38, cy), (14, cy - 6.0), (5.5, cy), (14, cy + 6.0)]
    c.poly("bevel", table)
    c.line("groove", table + [table[0]], 1.3)
    c.line("groove", [(30, cy - 12.5), (14, cy - 6.0)], 1.2)
    c.line("groove", [(30, cy + 12.5), (14, cy + 6.0)], 1.2)
    c.poly("core", _blade(18.0, cy, 31.0, 11.0, 1.9))
    c.blur("core", 0.30)
    return c


# ---------------------------------------------------------------------------
# Radial: sparks and seals
# ---------------------------------------------------------------------------

def sh_star(w, h, **_):
    """A five-pointed spark with a lit ridge down every arm and dark valleys
    between them.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.star("body", cx, cy, 20.0, 5, 0.38)
    for i in range(5):
        c.spoke("groove", cx, cy, -54.0 + i * 72.0, 0.0, 7.6, 1.2)
    c.star("core", cx, cy, 13.0, 5, 0.12)
    c.disc("core", cx, cy, 2.6)
    c.blur("core", 0.35)
    return c


def sh_star6(w, h, **_):
    """A hexagram drawn as two triangles that visibly cross: the inner hexagon
    is engraved and alternate arms are lit.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    r = 24.0
    c.ngon("body", cx, cy, r, 3, turn=-90.0)
    c.ngon("body", cx, cy, r, 3, turn=90.0)

    r_hex = r / math.sqrt(3.0)
    hexa = _ngon_pts(cx, cy, r_hex, 6, turn=0.0)
    for i in range(3):
        tip = _polar(cx, cy, 90.0 + i * 120.0, r)
        c.poly("bevel", [tip, hexa[(i * 2 + 1) % 6], hexa[(i * 2 + 2) % 6]])
    c.ngon_line("groove", cx, cy, r_hex, 6, 2.1, turn=0.0)
    c.ngon("core", cx, cy, 5.4, 6, turn=0.0)
    c.blur("core", 0.30)
    return c


def sh_rune(w, h, **_):
    """A warding tile: a chamfered plate with a lit sigil struck into it (where
    the card has an inscription, this has one figure).
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    m, k = 2.5, 5.5
    c.poly("body", [(m + k, m), (w - 1 - m - k, m), (w - 1 - m, m + k),
                    (w - 1 - m, h - 1 - m - k), (w - 1 - m - k, h - 1 - m),
                    (m + k, h - 1 - m), (m, h - 1 - m - k), (m, m + k)])
    i, j = 6.5, 4.5
    face = [(i + j, i), (w - 1 - i - j, i), (w - 1 - i, i + j),
            (w - 1 - i, h - 1 - i - j), (w - 1 - i - j, h - 1 - i),
            (i + j, h - 1 - i), (i, h - 1 - i - j), (i, i + j)]
    c.line("groove", face + [face[0]], 1.3)

    c.line("core", [(cx, cy - 9.0), (cx, cy + 9.0)], 1.9)
    c.line("core", [(cx - 7.0, cy - 7.0), (cx, cy - 0.5)], 1.9)
    c.line("core", [(cx + 7.0, cy - 7.0), (cx, cy - 0.5)], 1.9)
    c.line("core", [(cx - 5.5, cy + 4.5), (cx + 5.5, cy + 4.5)], 1.7)
    c.blur("core", 0.30)
    return c


# ---------------------------------------------------------------------------
# Animated
# ---------------------------------------------------------------------------

def _tongue(x0, x1, cy, half0, half1, amp, freq, phase, n=26, taper=0.85):
    """A tapered strip swaying along its length. Returns (outline, spine)."""
    top, bot, spine = [], [], []
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        half = half1 + (half0 - half1) * (1.0 - t) ** taper
        y = cy + math.sin(t * freq + phase) * amp * t
        spine.append((x, y))
        top.append((x, y - half))
        bot.append((x, y + half))
    return top + bot[::-1], spine


def sh_butterfly(w, h, frame=0, frames=4, **_):
    """A moth: one swept wing a side, notched deeply along its trailing edge so
    it reads as a forewing and a hindwing, plus a head and two antennae.
    """
    c = Cut(w, h)
    cy = c.cy
    s = 1.0 - 0.40 * abs(math.sin(math.pi * frame / frames))

    for sign in (-1, 1):
        wing = [(40, cy + sign * 2.6),
                (37, cy + sign * 15.5 * s),
                (27, cy + sign * 21.5 * s),
                (18, cy + sign * 16.5 * s),
                (25, cy + sign * 7.5 * s),
                (14, cy + sign * 13.5 * s),
                (11, cy + sign * 4.5 * s),
                (20, cy + sign * 2.6)]
        c.poly("body", wing)
        # The forewing is lit and the hindwing isn't, which is what tells them
        # apart at 1:1.
        c.poly("bevel", wing[0:4] + [wing[4]])
        c.line("groove", [(39, cy + sign * 3.4), (29, cy + sign * 18.0 * s)],
               1.3)
        c.line("body", [(45.5, cy + sign * 1.4), (53, cy + sign * 6.5)], 1.8)

    c.poly("body", [(43, cy), (39, cy - 3.0), (15, cy - 3.0),
                    (11, cy), (15, cy + 3.0), (39, cy + 3.0)])
    c.disc("body", 43.0, cy, 3.8)
    c.poly("core", _blade(27.0, cy, 42.0, 14.0, 1.6))
    c.disc("core", 43.0, cy, 1.9)
    c.blur("core", 0.30)
    return c


# The flame's head, in final pixels. It is the hitbox, and `ORIGINS` puts the
# sprite's origin on it.
def _flame_head(w, h):
    return (w - h * 0.30 - 2.0, (h - 1) / 2.0)


def sh_flame(w, h, frame=0, frames=4, **_):
    """A wisp: a round hot head, and a tail that undulates away behind it with
    three tongues forking off it. The tail starts at the head's centre and the
    head is drawn over it, so there is no notch where they meet.
    """
    c = Cut(w, h)
    hx, cy = _flame_head(w, h)
    wob = math.sin(2 * math.pi * frame / frames)

    body, spine = _tongue(hx, 4.0, cy, 10.6, 0.5, 5.6, 3.9, wob * 2.1,
                          taper=1.15)
    c.poly("body", body)

    for frac, reach, wide, drift in ((0.40, 12.0, 4.6, -1.9),
                                     (0.55, 20.0, 3.6, 1.7),
                                     (0.62, 8.0, 2.6, -0.9)):
        x0, y0 = spine[int(frac * (len(spine) - 1))]
        fork, _ = _tongue(x0, reach, y0, wide, 0.35, 5.0 * drift, 3.0,
                          wob * 1.6, taper=0.9)
        c.poly("body", fork)

    for r, dx in ((10.3, 0.0), (8.2, 3.4), (5.2, 6.4)):
        c.disc("body", hx + dx, cy, r)

    c.line("groove", [(x, y - 3.8) for x, y in spine[3:18]], 1.2)
    c.line("groove", [(x, y + 3.4) for x, y in spine[4:20]], 1.1)

    # The core is a streak along the direction of travel, not a disc.
    c.line("core", [(hx + 6.5, cy)] + spine[:5], 5.0)
    c.line("core", [(hx + 2.0, cy)] + spine[:11], 2.4)
    c.blur("core", 0.40)
    return c


def sh_mote(w, h, frame=0, frames=4, **_):
    """A four-point spark, the same figure as the console's divider rules and
    crest. It pulses over its frames (and spins by default; see `SPIN`).
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    p = 0.84 + 0.16 * math.cos(2 * math.pi * frame / frames)
    c.star("body", cx, cy, 13.0 * p, 4, 0.30)
    c.star("body", cx, cy, 7.8 * p, 4, 0.36, turn=-45.0)
    c.star("core", cx, cy, 5.2 * p, 4, 0.36)
    c.disc("core", cx, cy, 1.8)
    c.blur("core", 0.32)
    return c


# ---------------------------------------------------------------------------
# The catalogue
#
# w/h are the final sprite size, including the margin the contour and bloom
# need; `hit` is the collision radius, a property of the drawn body rather
# than of the canvas.
# ---------------------------------------------------------------------------

SHAPES = [
    # name        w   h  hit  orient frames  shape          opts
    ("pellet",    24, 24, 4.2,  False, 1, sh_pellet,   {}),
    ("orb",       34, 34, 7.0,  False, 1, sh_orb,      {}),
    ("ball",      54, 54, 15.0, False, 1, sh_ball,     {}),
    ("sphere",    88, 88, 29.0, False, 1, sh_sphere,   dict(bloom_r=3.2)),
    ("ring",      46, 46, 12.5, False, 1, sh_ring,     {}),
    ("bubble",    76, 76, 26.0, False, 1, sh_bubble,   {}),
    ("rice",      34, 22, 5.6,  True,  1, sh_rice,     {}),
    ("oval",      48, 30, 9.0,  True,  1, sh_oval,     {}),
    ("dart",      46, 30, 7.6,  True,  1, sh_dart,     {}),
    ("needle",    64, 18, 5.6,  True,  1, sh_needle,   dict(contour=1.0)),
    ("card",      46, 30, 9.0,  True,  1, sh_card,     {}),
    ("star",      44, 44, 10.5, False, 1, sh_star,     dict(contour=1.0)),
    ("star6",     54, 54, 14.0, False, 1, sh_star6,    {}),
    ("crystal",   44, 32, 9.0,  True,  1, sh_crystal,  {}),
    ("rune",      40, 40, 10.5, False, 1, sh_rune,     {}),
    ("butterfly", 58, 48, 10.5, True,  4, sh_butterfly, dict(contour=1.0)),
    ("flame",     66, 42, 9.5,  True,  4, sh_flame,    {}),
    ("mote",      30, 30, 5.6,  False, 4, sh_mote,     dict(contour=1.0)),
]

# Default spin in degrees per frame; `fire` copies it into the bullet's `spin`.
# Oriented shapes get none, because their `angle` is their heading
# (`test_bullet_table` checks this).
SPIN = {
    "star":  2.2,
    "star6": 1.5,
    "mote":  2.8,
}

# Origins other than the centre. The flame pivots on its head, which is its
# hitbox.
ORIGINS = {
    "flame": lambda w, h, pad: (int(round(_flame_head(w, h)[0])) + pad,
                                h // 2 + pad),
}


def _shape_pad(opts):
    """The empty canvas `cut_finish` will add round this shape. The flame's
    origin and the table's sprite sizes both depend on it.
    """
    return A.cut_pad(opts.get("contour", 2.0), opts.get("bloom_r", 2.2))


def build_shape(spec):
    """Every frame of one shape: colours outermost, animation innermost."""
    name, w, h, _hit, _orient, frames, shape_fn, opts = spec
    masks = [shape_fn(w, h, frame=f, frames=frames).parts()
             for f in range(frames)]
    shade_kw = {k: v for k, v in opts.items()
                if k in ("lip", "band", "lit_t", "bevel_t", "groove_k",
                         "deep_t")}
    finish_kw = {k: v for k, v in opts.items()
                 if k in ("contour", "bloom", "bloom_r", "threshold")}

    out = []
    for _, rim in A.BULLET_HUES:
        for f in range(frames):
            out.append(A.cut_finish(A.cut_shade(masks[f], rim, **shade_kw),
                                    w, h, rim, **finish_kw))
    return out


def main():
    preview_only = "--preview-only" in sys.argv

    sheets = []
    table = []

    for spec in SHAPES:
        name, w, h, hit, orient, frames, _fn, _opts = spec
        images = build_shape(spec)
        sprite = "spr_bul_%s" % name

        if not preview_only:
            origin = ORIGINS.get(name,
                                 lambda a, b, c: "center")(w, h,
                                                           _shape_pad(_opts))
            gm_new.sprite(sprite, images, origin=origin,
                          folder="Sprites/bullets", fps=1.0)

        table.append((name, sprite, hit, orient, frames,
                      images[0].width, images[0].height,
                      0.0 if orient else SPIN.get(name, 0.0)))

        # One row of the preview per shape: every hue, first animation frame.
        for i in range(len(A.BULLET_HUES)):
            sheets.append(images[i * frames])

    A.preview(sheets, os.path.join(A.PREVIEW, "bullets_sheet.png"),
              cols=len(A.BULLET_HUES), bg=(18, 20, 30))

    # The same over a bright, busy ground.
    _bright_ground(sheets, len(A.BULLET_HUES)).save(
        os.path.join(A.PREVIEW, "bullets_bright.png"))

    # And at 4x: three hues per shape, every frame of the animated ones.
    _zoom_sheet()

    if not preview_only:
        write_table(table)
    print("bullets: %d shapes x %d hues -> %d frames"
          % (len(SHAPES), len(A.BULLET_HUES),
             sum(len(A.BULLET_HUES) * s[5] for s in SHAPES)))


def _zoom_sheet(scale=4):
    rows = []
    for spec in SHAPES:
        name, w, h, _hit, _o, frames, shape_fn, opts = spec
        shade_kw = {k: v for k, v in opts.items()
                    if k in ("lip", "band", "lit_t", "bevel_t", "groove_k",
                             "deep_t")}
        finish_kw = {k: v for k, v in opts.items()
                     if k in ("contour", "bloom", "bloom_r", "threshold")}
        for f in range(frames):
            for hue_name in ("crimson", "cyan", "bone"):
                rim = A.hue(hue_name)
                img = A.cut_finish(
                    A.cut_shade(shape_fn(w, h, frame=f, frames=frames).parts(),
                                rim, **shade_kw), w, h, rim, **finish_kw)
                rows.append(img.resize((w * scale, h * scale), Image.NEAREST))
    return A.preview(rows, os.path.join(A.PREVIEW, "bullets_zoom.png"),
                     cols=9, bg=(14, 15, 24), pad=8)


def _bright_ground(images, cols, pad=10):
    """The preview again over something a bullet could get lost in."""
    rows = (len(images) + cols - 1) // cols
    cw = max(i.width for i in images)
    ch = max(i.height for i in images)
    w = cols * (cw + pad) + pad
    h = rows * (ch + pad) + pad

    field = A.fbm_field(w, h, seed=7, octaves=5, base=5)
    arr = np.asarray(field, dtype=np.float32)[..., None] / 255.0
    warm = np.array([210, 150, 90], dtype=np.float32)
    cool = np.array([120, 190, 210], dtype=np.float32)
    sheet = A.from_arrays(warm * arr + cool * (1 - arr),
                          np.ones((h, w), dtype=np.float32))

    for i, img in enumerate(images):
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (ch + pad)
        sheet.alpha_composite(img, (x + (cw - img.width) // 2,
                                    y + (ch - img.height) // 2))
    return sheet


TABLE_HEADER = '''/// @desc The bullet catalogue -- GENERATED by tools/make_bullets.py. Do not
///       edit: each hit radius is defined there beside its picture. A shape
///       is one sprite whose frames are its colours; `bullet_frame` computes
///       the frame index.

'''


def write_table(table):
    lines = [TABLE_HEADER]

    for i, (name, _spr, _hit, _o, _f, _w, _h, _sp) in enumerate(table):
        lines.append("#macro BSHAPE_%s %d" % (name.upper(), i))
    lines.append("#macro BSHAPE_COUNT %d" % len(table))
    lines.append("")

    for i, (name, _) in enumerate(A.BULLET_HUES):
        lines.append("#macro BCOL_%s %d" % (name.upper(), i))
    lines.append("#macro BCOL_COUNT %d" % len(A.BULLET_HUES))
    lines.append("")

    lines.append("/// @desc Fill in the shape table. Called once, from obj_boot.")
    lines.append("function bullet_table_init() {")
    lines.append("    global.bshape_sprite = [")
    for name, spr, _h, _o, _f, _w, _hh, _sp in table:
        lines.append("        %s," % spr)
    lines.append("    ];")

    for field, idx, fmt in (("radius", 2, "%s"), ("oriented", 3, "%s"),
                            ("frames", 4, "%d"), ("w", 5, "%d"), ("h", 6, "%d"),
                            ("spin", 7, "%s")):
        lines.append("    global.bshape_%s = [" % field)
        row = []
        for rec in table:
            v = rec[idx]
            if field == "oriented":
                row.append("true" if v else "false")
            elif field == "radius":
                row.append("%.1f" % v)
            elif field == "spin":
                row.append("%.2f" % v)
            else:
                row.append("%d" % v)
        lines.append("        " + ", ".join(row) + ",")
        lines.append("    ];")

    lines.append("}")
    lines.append("")

    path = os.path.join(A.ROOT, "scripts", "bullet_table", "bullet_table.gml")
    gm_new.write(path, "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
