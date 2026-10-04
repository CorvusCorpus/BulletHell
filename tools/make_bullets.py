#!/usr/bin/env python3
"""Generate every bullet sprite, and `scripts/bullet_table/bullet_table.gml`.

- One sprite per shape, one frame per colour, so a bullet is drawn with
  `draw_sprite_ext(spr, colour, ...)`. An animated shape folds both into one
  index, `colour * frames + tick`, which `bullet_frame` in
  `danmaku_functions` computes.
- Oriented shapes point right at angle 0, like GameMaker's `direction`.
- This file is the only source of a bullet's hitbox. The table is written
  from the same catalogue as the pictures, so the two can't drift apart. A
  round shape's is a circle given in `SHAPES`; a long shape's is a capsule
  fitted to its body (`CAPSULES`). (The flame is 66x42 of picture and 9.5 of
  hitbox, a circle on its head.)
- Each shape is a cut body (see "Cut bodies" in `art_common`): up to four
  masks (body, groove, bevel, core) rather than a shaded silhouette.

Usage:
    python tools/make_bullets.py          # -> sprites + bullet_table.gml
    python tools/make_bullets.py --preview-only
"""
import math
import os
import re
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
    centre. The smallest bullet: 18 px tall with its contour, about Touhou's
    dot (an 8 px cell on a 448 px field) on this 992 px one.
    """
    c = Cut(w, h)
    c.ngon("body", c.cx, c.cy, 7.0, 6)
    c.ngon("core", c.cx, c.cy, 2.65, 6)
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
    return _seal(Cut(w, h), 27.0, 17.5, 1.8, (12, 19.4, 25.8), 1.6, 6.8,
                 inner=(10.4, 1.5), alt=22.8)


# ---------------------------------------------------------------------------
# Hollow: a seal, and the circle that contains it
# ---------------------------------------------------------------------------

def sh_ring(w, h, **_):
    """A segmented seal, the medium hollow round: an annulus with a lit
    channel, cut through at the diagonals and ticked at the quarters.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.annulus("body", cx, cy, 30.0, 20.5)
    c.annulus("core", cx, cy, 26.2, 24.2)
    c.blur("core", 0.35)
    for i in range(4):
        c.spoke("groove", cx, cy, 45.0 + i * 90.0, 19.5, 31.0, 1.8)
        c.spoke("groove", cx, cy, i * 90.0, 27.4, 31.0, 1.1)
    return c


def sh_bubble(w, h, **_):
    """A containment circle, the large round: two concentric hoops braced by
    eight spokes, hollow so its size costs little screen.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.annulus("body", cx, cy, 56.0, 47.0)
    for i in range(8):
        a = 22.5 + i * 45.0
        c.line("body", [_polar(cx, cy, a, 34.5), _polar(cx, cy, a, 48.0)],
               3.6 if i % 2 == 0 else 2.6)
    c.annulus("body", cx, cy, 37.0, 32.5)

    c.annulus("core", cx, cy, 52.6, 50.4)
    c.annulus("core", cx, cy, 35.4, 34.2)
    c.blur("core", 0.35)
    for i in range(16):
        c.spoke("groove", cx, cy, i * 22.5 + 11.25, 46.0,
                57.0 if i % 2 == 0 else 51.0, 1.5)
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


# The droplet's round head, in final pixels: the hitbox, and the origin. On a
# half pixel, so it lands on a whole-pixel origin (see `ORIGINS`).
def _drop_head(w, h):
    return (w - 11.5, (h - 1) / 2.0)


def sh_droplet(w, h, **_):
    """A tear: a round head leading, drawn out into a fine tail behind it.
    Origin and hitbox are on the head (see `ORIGINS`).
    """
    c = Cut(w, h)
    hx, cy = _drop_head(w, h)
    r = 8.4
    # The flanks leave the head on its tangent and bow inward on their way to
    # the tail, so it reads as liquid drawn out rather than a cone.
    tail_x = 2.0
    top = []
    for i in range(17):
        t = i / 16.0
        x = hx - r * 0.42 + (tail_x - (hx - r * 0.42)) * t
        top.append((x, cy - r * 0.91 * (1.0 - t) ** 1.9))
    c.poly("body", top + [(x, 2 * cy - y) for x, y in top[::-1]])
    c.disc("body", hx, cy, r)

    # A lifted field and a hot bead set toward the front, and a thread of
    # light back into the tail.
    c.disc("bevel", hx + 1.2, cy, 5.8, v=160)
    c.disc("core", hx + 2.2, cy, 3.2)
    c.line("core", [(hx - 2.0, cy), (hx - 13.0, cy)], 1.1)
    c.blur("core", 0.35)
    return c


def sh_oval(w, h, **_):
    """A polished bead: a rounded capsule with a table cut along it (the
    crystal's construction on a blunt body).
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    # A superellipse, a little squarer than an ellipse, so it reads as a
    # capsule and not as the rice's point.
    c.poly("body", [(cx + math.copysign(abs(math.cos(a)) ** 0.8, math.cos(a))
                     * 16.5,
                     cy + math.copysign(abs(math.sin(a)) ** 0.8, math.sin(a))
                     * 8.6)
                    for a in (i * math.pi / 32.0 for i in range(64))])
    table = [(33.0, cy), (cx, cy - 6.4), (4.0, cy), (cx, cy + 6.4)]
    c.poly("bevel", table)
    c.line("groove", table + [table[0]], 1.1)
    c.poly("core", _blade(cx, cy, 28.0, 9.0, 1.9))
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


def sh_knife(w, h, **_):
    """A throwing knife: a single-edged blade with a fuller, a crossguard, a
    bound grip and a pommel. The canvas centre (the hitbox) is on the blade.
    """
    c = Cut(w, h)
    cy = c.cy
    spine, edge = cy - 4.4, cy + 4.4
    c.poly("body", [(15.5, spine), (41.0, spine), (51.0, cy - 0.6),
                    (48.0, cy + 1.6), (43.5, cy + 3.4), (37.0, edge),
                    (15.5, edge)])
    c.poly("body", [(12.5, cy - 7.4), (15.8, cy - 7.4),
                    (15.8, cy + 7.4), (12.5, cy + 7.4)])
    c.poly("body", [(5.0, cy - 2.6), (12.8, cy - 2.6),
                    (12.8, cy + 2.6), (5.0, cy + 2.6)])
    c.disc("body", 3.8, cy, 3.0)

    # The ground edge is lit; the fuller is cut above it.
    c.poly("bevel", [(16.0, cy + 1.0), (41.0, cy + 1.0), (50.0, cy - 0.5),
                     (48.0, cy + 1.6), (43.5, cy + 3.4), (37.0, edge),
                     (16.0, edge)])
    c.line("groove", [(18.0, cy - 1.7), (38.0, cy - 1.7)], 1.3)
    for s in (-1, 1):
        c.line("groove", [(14.2, cy + s * 2.9), (14.2, cy + s * 6.4)], 1.0)
    for x in (7.4, 10.2):
        c.line("groove", [(x, cy - 2.6), (x, cy + 2.6)], 0.9)

    c.poly("core", [(20.0, cy + 2.2), (40.0, cy + 2.2), (48.5, cy + 0.2),
                    (40.0, cy + 3.3), (20.0, cy + 3.3)])
    c.disc("core", 3.8, cy, 1.1)
    c.blur("core", 0.30)
    return c


# The arrowhead's centre, in final pixels: the hitbox, and the origin. On a
# half pixel, so it lands on a whole-pixel origin (see `ORIGINS`).
def _arrow_head(w, h):
    return (w - 9.5, (h - 1) / 2.0)


def sh_arrow(w, h, **_):
    """An arrow: a barbed head, a shaft and two fletching vanes. Its origin
    and hitbox are on the head (see `ORIGINS`); the shaft trails harmlessly.
    """
    c = Cut(w, h)
    cy = c.cy
    hx = _arrow_head(w, h)[0]
    tip = hx + 7.0
    c.poly("body", [(tip, cy), (hx - 5.5, cy - 7.2), (hx - 2.6, cy - 1.8),
                    (hx - 2.6, cy + 1.8), (hx - 5.5, cy + 7.2)])
    c.poly("body", [(4.0, cy - 1.6), (hx - 1.0, cy - 1.6),
                    (hx - 1.0, cy + 1.6), (4.0, cy + 1.6)])
    for s in (-1, 1):
        vane = [(22.0, cy + s * 1.2), (13.5, cy + s * 6.6),
                (4.5, cy + s * 6.6), (9.0, cy + s * 1.2)]
        c.poly("body", vane)
        c.poly("bevel", vane)
        for x in (10.0, 14.0, 18.0):
            c.line("groove", [(x, cy + s * 1.6), (x - 3.6, cy + s * 5.6)],
                   0.9)
    c.poly("body", [(1.5, cy - 2.4), (5.0, cy - 2.4),
                    (5.0, cy + 2.4), (1.5, cy + 2.4)])
    c.line("groove", [(1.0, cy), (3.4, cy)], 1.1)

    c.poly("bevel", [(tip, cy), (hx - 5.5, cy - 7.2), (hx - 2.6, cy - 1.8),
                     (hx - 2.6, cy)])
    c.poly("core", _blade(hx + 0.5, cy, tip - 2.0, hx - 3.0, 1.9))
    c.blur("core", 0.30)
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


def sh_shuriken(w, h, **_):
    """A four-bladed throwing star with a hole through its hub. Each blade has
    a short straight leading edge and a long hooked trailing one, and its
    leading facet is lit, so it reads as whirling (it spins by default; see
    `SPIN`).
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    tip_r, hub_r = 19.5, 7.2
    for i in range(4):
        a = i * 90.0 - 45.0
        lead = [(a - 24.0, hub_r), (a - 15.0, 11.2), (a - 7.0, 15.4)]
        trail = [(a + 14.0, 13.4), (a + 30.0, 10.4), (a + 48.0, 8.6),
                 (a + 64.0, hub_r)]
        blade = ([_polar(cx, cy, b, r) for b, r in lead]
                 + [_polar(cx, cy, a, tip_r)]
                 + [_polar(cx, cy, b, r) for b, r in trail])
        c.poly("body", blade)
        c.poly("bevel", [_polar(cx, cy, b, r) for b, r in lead]
               + [_polar(cx, cy, a, tip_r), _polar(cx, cy, a + 12.0, hub_r)])
        c.line("groove", [_polar(cx, cy, a + 12.0, hub_r + 0.5),
                          _polar(cx, cy, a + 2.0, tip_r - 4.0)], 1.0)
    c.disc("body", cx, cy, hub_r + 0.8)
    c.hoop("groove", cx, cy, hub_r - 0.6, 1.1)
    c.annulus("core", cx, cy, 5.2, 3.0)
    c.blur("core", 0.30)
    c.disc("body", cx, cy, 2.5, v=0)
    return c


def sh_rune(w, h, **_):
    """A warding tile: a chamfered plate with a lit sigil struck into it (where
    the card has an inscription, this has one figure).
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    m, k = 2.0, 4.2
    c.poly("body", [(m + k, m), (w - 1 - m - k, m), (w - 1 - m, m + k),
                    (w - 1 - m, h - 1 - m - k), (w - 1 - m - k, h - 1 - m),
                    (m + k, h - 1 - m), (m, h - 1 - m - k), (m, m + k)])
    i, j = 5.0, 3.4
    face = [(i + j, i), (w - 1 - i - j, i), (w - 1 - i, i + j),
            (w - 1 - i, h - 1 - i - j), (w - 1 - i - j, h - 1 - i),
            (i + j, h - 1 - i), (i, h - 1 - i - j), (i, i + j)]
    c.line("groove", face + [face[0]], 1.1)

    c.line("core", [(cx, cy - 6.6), (cx, cy + 6.6)], 1.7)
    c.line("core", [(cx - 5.0, cy - 5.0), (cx, cy - 0.4)], 1.7)
    c.line("core", [(cx + 5.0, cy - 5.0), (cx, cy - 0.4)], 1.7)
    c.line("core", [(cx - 4.0, cy + 3.4), (cx + 4.0, cy + 3.4)], 1.5)
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


# How much larger the butterfly is than it was laid out (the medium tier).
BUTTERFLY_K = 1.36


def sh_butterfly(w, h, frame=0, frames=4, **_):
    """A moth: one swept wing a side, notched deeply along its trailing edge so
    it reads as a forewing and a hindwing, plus a head and two antennae.
    """
    c = Cut(w, h)
    cy = c.cy
    s = 1.0 - 0.40 * abs(math.sin(math.pi * frame / frames))
    # Drawn at `BUTTERFLY_K` times the size the numbers below were laid out
    # at, from the canvas's left edge and its centre line.
    k = BUTTERFLY_K

    def P(x, y):
        return (x * k, cy + y * k)

    for sign in (-1, 1):
        wing = [P(40, sign * 2.6),
                P(37, sign * 15.5 * s),
                P(27, sign * 21.5 * s),
                P(18, sign * 16.5 * s),
                P(25, sign * 7.5 * s),
                P(14, sign * 13.5 * s),
                P(11, sign * 4.5 * s),
                P(20, sign * 2.6)]
        c.poly("body", wing)
        # The forewing is lit and the hindwing isn't, which is what tells them
        # apart at 1:1.
        c.poly("bevel", wing[0:4] + [wing[4]])
        c.line("groove", [P(39, sign * 3.4), P(29, sign * 18.0 * s)], 1.5)
        c.line("body", [P(45.5, sign * 1.4), P(53, sign * 6.5)], 2.2)

    c.poly("body", [P(43, 0), P(39, -3.0), P(15, -3.0),
                    P(11, 0), P(15, 3.0), P(39, 3.0)])
    c.disc("body", 43.0 * k, cy, 3.8 * k)
    c.poly("core", _blade(27.0 * k, cy, 42.0 * k, 14.0 * k, 1.6 * k))
    c.disc("core", 43.0 * k, cy, 1.9 * k)
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


# How much larger the nova is than the mote: the big four-point star beside
# the small one.
NOVA_K = 2.28


def sh_nova(w, h, frame=0, frames=4, **_):
    """The mote drawn at `NOVA_K` times its size, pulsing and spinning the same
    way.
    """
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    k = NOVA_K
    p = 0.84 + 0.16 * math.cos(2 * math.pi * frame / frames)
    c.star("body", cx, cy, 13.0 * k * p, 4, 0.30)
    c.star("body", cx, cy, 7.8 * k * p, 4, 0.36, turn=-45.0)
    c.star("core", cx, cy, 5.2 * k * p, 4, 0.36)
    c.disc("core", cx, cy, 1.8 * k)
    c.blur("core", 0.32 * k)
    return c


# ---------------------------------------------------------------------------
# The ray
#
# A travelling laser (`laser_ray`), drawn as light in the manner of Touhou's
# loose lasers, one frame per hue like a bullet: a white-hot core fading
# through the hue to nothing at its edges, narrowing to a soft point at each
# end. It has no dark contour, since it is drawn additively (`laser_draw`).
# It is not a bullet shape: `laser_draw_ray` stretches it to the ray's length
# and width. Its measurements go into the table (`BRAY_*`).
# ---------------------------------------------------------------------------

RAY_W, RAY_H = 128, 32
RAY_TAPER = 26.0              # how far each end narrows to its point
RAY_X0 = 1.0                  # the tail's point, in sprite px
RAY_X1 = RAY_W - 1.0          # the head's point
RAY_CORE = 0.22               # the white core's share of the half width


def build_ray():
    """Every hue of the ray, and its measurements in sprite pixels."""
    ss = SS
    xs = (np.arange(RAY_W * ss, dtype=np.float32) + 0.5) / ss
    ys = (np.arange(RAY_H * ss, dtype=np.float32) + 0.5) / ss
    # Half the width, full along the middle and rounding to a point at each
    # end; then how far across that half each sample is.
    end = np.minimum(xs - RAY_X0, RAY_X1 - xs)
    half = (RAY_H / 2.0 - 1.0) * np.clip(end / RAY_TAPER, 0, 1) ** 0.55
    v = np.abs(ys - RAY_H / 2.0)[:, None]
    t = np.where(half[None, :] > 0, v / np.maximum(half[None, :], 1e-6), 9.0)
    glow = np.clip(1 - t, 0, 1) ** 0.75
    core = np.clip(1 - t / RAY_CORE, 0, 1) ** 1.5
    alpha = np.clip(glow * 0.85 + core * 0.3, 0, 1)
    # White only along the core, the hue through the body.
    w = np.clip((t - 0.04) / 0.26, 0, 1)
    w = w * w * (3 - 2 * w)

    images = []
    for _, rim in A.BULLET_HUES:
        rim = np.array(rim, dtype=np.float32)
        col = (np.array([255, 255, 255], dtype=np.float32) * (1 - w[..., None])
               + rim * w[..., None])
        # Downsampled premultiplied, so the edges don't darken.
        pm = col * alpha[..., None]
        pm = pm.reshape(RAY_H, ss, RAY_W, ss, 3).mean(axis=(1, 3))
        a = alpha.reshape(RAY_H, ss, RAY_W, ss).mean(axis=(1, 3))
        rgb = np.where(a[..., None] > 1e-4, pm / np.maximum(a[..., None], 1e-4),
                       0)
        images.append(A.from_arrays(rgb, a))
    geom = {
        "BODY0": RAY_X0,
        "BODY1": RAY_X1,
        "THICK": float(RAY_H),
        "TAPER": RAY_TAPER,
    }
    return images, geom


# ---------------------------------------------------------------------------
# The catalogue
#
# w/h are the final sprite size, including the margin the contour and bloom
# need; `hit` is the collision radius, a property of the drawn body rather
# than of the canvas. A long shape's is fitted instead (`CAPSULES`).
# ---------------------------------------------------------------------------

SHAPES = [
    # name        w   h  hit  orient frames  shape          opts
    ("pellet",    20, 20, 3.3,  False, 1, sh_pellet,   {}),
    ("orb",       34, 34, 7.0,  False, 1, sh_orb,      {}),
    ("ball",      54, 54, 15.0, False, 1, sh_ball,     {}),
    ("sphere",    62, 62, 20.5, False, 1, sh_sphere,   {}),
    ("ring",      66, 66, 18.5, False, 1, sh_ring,     {}),
    ("bubble",   124, 124, 42.0, False, 1, sh_bubble,  {}),
    ("rice",      34, 22, None, True,  1, sh_rice,     {}),
    ("droplet",   36, 24, 6.0,  True,  1, sh_droplet,  {}),
    ("oval",      38, 22, None, True,  1, sh_oval,     {}),
    ("dart",      46, 30, None, True,  1, sh_dart,     {}),
    ("knife",     54, 20, None, True,  1, sh_knife,    {}),
    ("arrow",     60, 20, None, True,  1, sh_arrow,    dict(contour=1.0)),
    ("card",      46, 30, None, True,  1, sh_card,     {}),
    ("star",      44, 44, 10.5, False, 1, sh_star,     dict(contour=1.0)),
    ("shuriken",  42, 42, 9.0,  False, 1, sh_shuriken, {}),
    ("crystal",   44, 32, None, True,  1, sh_crystal,  {}),
    ("rune",      30, 30, 8.0,  False, 1, sh_rune,     {}),
    ("butterfly", 80, 66, 14.0, True,  4, sh_butterfly, dict(contour=1.0)),
    ("flame",     66, 42, 9.5,  True,  4, sh_flame,    {}),
    # The mote and nova pulse: their hit radius fits the smallest frame, where
    # a hitbox touching it in the notch between two arms still overlaps them.
    ("mote",      30, 30, 4.3,  False, 4, sh_mote,     dict(contour=1.0)),
    ("nova",      68, 68, 9.0,  False, 4, sh_nova,     dict(contour=1.0,
                                                          bloom_r=3.0)),
]

# Default spin in degrees per frame; `fire` copies it into the bullet's `spin`.
# Oriented shapes get none, because their `angle` is their heading
# (`test_bullet_table` checks this).
SPIN = {
    "star":     2.2,
    "shuriken": 9.0,
    "mote":     2.8,
    "nova":     2.8,
}

# Origins other than the centre. The flame, the droplet and the arrow pivot on
# their heads, which are their hitboxes. A shape's coordinates put a pixel's
# centre on its integer coordinate, so a head at `x` is at `x + 0.5` on the
# sprite, whose origin counts from its corner. A whole-pixel origin needs an
# even height to sit on the centre line.
ORIGINS = {
    "flame": lambda w, h, pad: (int(round(_flame_head(w, h)[0] + 0.5)) + pad,
                                h // 2 + pad),
    "droplet": lambda w, h, pad: (int(round(_drop_head(w, h)[0] + 0.5)) + pad,
                                  h // 2 + pad),
    "arrow": lambda w, h, pad: (int(round(_arrow_head(w, h)[0] + 0.5)) + pad,
                                h // 2 + pad),
}


def _shape_pad(opts):
    """The empty canvas `cut_finish` will add round this shape. The flame's
    origin and the table's sprite sizes both depend on it.
    """
    return A.cut_pad(opts.get("contour", 2.0), opts.get("bloom_r", 2.2))


def _origin(spec):
    """Where the sprite's origin is, in sprite pixels from its corner (what
    `gm_new.sprite` is given, with "center" worked out as it does)."""
    name, w, h, _hit, _o, _f, _fn, opts = spec
    pad = _shape_pad(opts)
    if name in ORIGINS:
        return ORIGINS[name](w, h, pad)
    return (w + 2 * pad) // 2, (h + 2 * pad) // 2


# ---------------------------------------------------------------------------
# Long shapes' hitboxes
#
# A long shape's hitbox is a capsule rather than a circle: everything within
# `r` of a spine along its heading, from `spine0` to `spine1` pixels from its
# origin. It is fitted to the drawn body here, so it follows the art:
#
# - Honest: a hit never registers before the player's hitbox (`PLAYER_R`)
#   overlaps the body, from any direction. Every point `r + PLAYER_R` from the
#   spine is within `PLAYER_R` of the body.
# - The whole shape, not one end of it: of the honest capsules, those running
#   end to end within `CAPSULE_SPAN_SLACK` of the longest possible, and of
#   those the one covering most of the body. A thin part (a grip, a shaft) so
#   limits the thickness, and the wider parts are generous.
#
# The droplet and the flame keep a circle on their heads: one honest capsule
# down their tails would be as thin as the tail.
# ---------------------------------------------------------------------------

CAPSULES = ("rice", "oval", "dart", "knife", "arrow", "card", "crystal")
CAPSULE_SPAN_SLACK = 0.10


def _player_r():
    """`PLAYER_R`, read from `scripts/constants`."""
    path = os.path.join(A.ROOT, "scripts", "constants", "constants.gml")
    with open(path, encoding="utf-8") as f:
        return float(re.search(r"#macro PLAYER_R ([0-9.]+)", f.read()).group(1))


def fit_capsule(spec):
    """`(r, spine0, spine1)` for a long shape: see "Long shapes' hitboxes"."""
    from scipy import ndimage

    name, w, h, _hit, _o, frames, shape_fn, opts = spec
    pr = _player_r()
    pad = _shape_pad(opts)
    xo, yo = _origin(spec)
    step = 0.25
    grow = 48 * SS

    # Per frame: the distance from every point to the body (final px), and
    # where the sprite's origin is on the padded supersampled grid.
    fields = []
    body0 = None
    for f in range(frames):
        body = np.asarray(shape_fn(w, h, frame=f, frames=frames)
                          .parts()["body"]) >= 128
        m = np.pad(body, grow)
        edt = ndimage.distance_transform_edt(~m) / SS
        ox = (xo - pad) * SS + grow + A.CUT_SHIFT - 0.5
        oy = (yo - pad) * SS + grow + A.CUT_SHIFT - 0.5
        fields.append((edt, ox, oy))
        if body0 is None:
            ys, xs = np.nonzero(m)
            body0 = ((xs - ox) / SS, (ys - oy) / SS)

    def near(u, v):
        """Is every point (u along the heading, v across it) within
        `PLAYER_R` of the body, on every frame?"""
        u = np.atleast_1d(u)
        v = np.atleast_1d(v)
        return all(np.all(ndimage.map_coordinates(
                       edt, [oy + v * SS, ox + u * SS], order=1,
                       mode="constant", cval=1e9) <= pr)
                   for edt, ox, oy in fields)

    bu, bv = body0
    lo, hi = float(bu.min()), float(bu.max())
    us = np.arange(math.floor(lo), math.ceil(hi) + step, step)
    fwd = np.radians(np.arange(-90, 91, 3))
    back = np.radians(np.arange(90, 271, 3))

    found = []
    for r in np.arange(0.5, 20.0, 0.1):
        d = r + pr
        side = [near([u, u], [-d, d]) for u in us]
        cap0 = [near(u + d * np.cos(back), d * np.sin(back)) for u in us]
        cap1 = [near(u + d * np.cos(fwd), d * np.sin(fwd)) for u in us]
        any_here = False
        k = 0
        while k < len(us):
            if not side[k]:
                k += 1
                continue
            j = k
            while j + 1 < len(us) and side[j + 1]:
                j += 1
            starts = [i for i in range(k, j + 1) if cap0[i]]
            ends = [i for i in range(k, j + 1) if cap1[i]]
            if starts and ends and starts[0] <= ends[-1]:
                u0, u1 = float(us[starts[0]]), float(us[ends[-1]])
                span = (min(hi, u1 + r) - max(lo, u0 - r)) / (hi - lo)
                cover = float(np.mean(np.hypot(bu - np.clip(bu, u0, u1), bv)
                                      <= r))
                found.append((round(float(r), 1), u0, u1, span, cover))
                any_here = True
            k = j + 1
        if not any_here:
            break

    longest = max(c[3] for c in found)
    r, u0, u1, _span, _cover = max(
        (c for c in found if c[3] >= longest - CAPSULE_SPAN_SLACK),
        key=lambda c: c[4])
    return r, u0, u1


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

        spine = (0.0, 0.0)
        if name in CAPSULES:
            hit, s0, s1 = fit_capsule(spec)
            spine = (s0, s1)
            print("  %-8s capsule r %.1f, spine %+.2f to %+.2f"
                  % (name, hit, s0, s1))
        table.append((name, sprite, hit, orient, frames,
                      images[0].width, images[0].height,
                      0.0 if orient else SPIN.get(name, 0.0)) + spine)

        # One row of the preview per shape: every hue, first animation frame.
        for i in range(len(A.BULLET_HUES)):
            sheets.append(images[i * frames])

    ray, ray_geom = build_ray()
    if not preview_only:
        gm_new.sprite("spr_bul_ray", ray, origin="center",
                      folder="Sprites/bullets", fps=1.0)
    A.preview(ray, os.path.join(A.PREVIEW, "bullets_ray.png"), cols=2,
              bg=(18, 20, 30))

    A.preview(sheets, os.path.join(A.PREVIEW, "bullets_sheet.png"),
              cols=len(A.BULLET_HUES), bg=(18, 20, 30))

    # The same over a bright, busy ground.
    _bright_ground(sheets, len(A.BULLET_HUES)).save(
        os.path.join(A.PREVIEW, "bullets_bright.png"))

    # And at 4x: three hues per shape, every frame of the animated ones.
    _zoom_sheet()

    if not preview_only:
        write_table(table, ray_geom)
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


def write_table(table, ray_geom):
    lines = [TABLE_HEADER]

    for i, rec in enumerate(table):
        name = rec[0]
        lines.append("#macro BSHAPE_%s %d" % (name.upper(), i))
    lines.append("#macro BSHAPE_COUNT %d" % len(table))
    lines.append("")

    for i, (name, _) in enumerate(A.BULLET_HUES):
        lines.append("#macro BCOL_%s %d" % (name.upper(), i))
    lines.append("#macro BCOL_COUNT %d" % len(A.BULLET_HUES))
    lines.append("")

    # The ray (`spr_bul_ray`, `laser_draw_ray`), in sprite pixels: where its
    # tail and head points are, its drawn width, and how far each end narrows
    # to its point. The sprite's origin is midway between the points.
    for key in ("BODY0", "BODY1", "THICK", "TAPER"):
        v = ray_geom[key]
        lines.append("#macro BRAY_%s %s" % (key, ("%d" % v) if isinstance(v, int)
                                             else ("%.2f" % v)))
    lines.append("")

    lines.append("/// @desc Fill in the shape table. Called once, from obj_boot.")
    lines.append("function bullet_table_init() {")
    lines.append("    global.bshape_sprite = [")
    for rec in table:
        lines.append("        %s," % rec[1])
    lines.append("    ];")

    def flag(v):
        return "true" if v else "false"

    # (field, value from a record, format). `long` marks a capsule hitbox;
    # `spine0`/`spine1` are its spine's ends along the heading from the
    # origin, and `ext` the further of the two (0 for a circle).
    fields = (
        ("radius",   lambda r: "%.1f" % r[2]),
        ("oriented", lambda r: flag(r[3])),
        ("frames",   lambda r: "%d" % r[4]),
        ("w",        lambda r: "%d" % r[5]),
        ("h",        lambda r: "%d" % r[6]),
        ("spin",     lambda r: "%.2f" % r[7]),
        ("long",     lambda r: flag(r[8] != r[9])),
        ("spine0",   lambda r: "%.2f" % r[8]),
        ("spine1",   lambda r: "%.2f" % r[9]),
        ("ext",      lambda r: "%.2f" % max(abs(r[8]), abs(r[9]))),
    )
    for field, fmt in fields:
        lines.append("    global.bshape_%s = [" % field)
        lines.append("        " + ", ".join(fmt(rec) for rec in table) + ",")
        lines.append("    ];")

    lines.append("}")
    lines.append("")

    path = os.path.join(A.ROOT, "scripts", "bullet_table", "bullet_table.gml")
    gm_new.write(path, "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
