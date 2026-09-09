#!/usr/bin/env python3
"""Generate every bullet sprite, and the table the engine reads them through.

**One sprite per shape, one frame per colour.** Eighteen shapes across fourteen
hues is 252 combinations, and 252 GameMaker sprites would be 252 `.yy` files,
252 entries in the `.yyp`, and a texture atlas nobody could reason about. So a
shape is one sprite whose frames are its colours, and drawing a bullet is
`draw_sprite_ext(spr, colour, ...)`. Animated shapes fold both axes into the
one index: `frame = colour * frames + tick`, which `bullet_frame` in
`danmaku_functions` is the only thing allowed to compute.

**Oriented shapes point RIGHT at angle zero**, because GameMaker's `direction`
0 is right and `image_angle` is measured the same way. Drawing them pointing up
-- which is how a Touhou sheet is usually laid out -- would mean every draw
call carrying a `- 90`, and the one that forgets it is a bullet that is
visually sideways while being mechanically correct, which is the worst kind of
bug to look at.

**This file is the single source of truth for a bullet's hit radius**, not just
its picture, and it writes `scripts/bullet_table/bullet_table.gml` to say so.
The radius and the sprite have to agree -- a 36px ball with an 11px radius is a
promise about where the player may fly, and if the number lived in GML while
the picture lived here the two would be edited apart within a week. The flame
is the case that proves it: it is 66x42 of picture and 9.5 of hitbox, because
the tail is not the bullet.


The redesign
------------

**The first set of these read as sweets, and that was a failure of the
rendering model rather than of the shapes.** Every bullet went through
`orb_field` or `shade_shape`, both of which light a silhouette the way a
photographer lights a bead -- a smooth radial ramp from a large white centre
out to a hue, plus a specular kicked up and to the left. Those two moves are
the entire visual grammar of a boiled sweet, and fourteen hues of it is a bag
of jelly beans. Reported, accurately, as belonging in a match-three game rather
than in a fantasy shooter.

The new model is in `art_common` under "Cut bodies" and the argument is written
out there. What it changes here is that **a shape is no longer a silhouette.**
It is up to four masks -- what exists, what is engraved into it, which planes
face the light, and where the small hot centre is -- because authored internal
structure is the whole of the difference between a shape that looks generated
and one that looks designed, and no shading model buys it.

So every one of these is now a *cut* object: a gem with a table and facet
breaks, a kunai with a collar and a spine, a talisman with a border and a
glyph, a rune tile with a lit sigil on it. What survived the rewrite is the
list of names, because eighteen `BSHAPE_*` macros are a contract with the
content, and the hit radii, because a picture is allowed to change without the
difficulty changing with it.

**One name did not survive: `heart` is now `rune`.** A heart is the single most
cute-coded shape in the genre and no amount of bevelling makes it read as
somebody's warding sigil; it was also referenced by nothing outside the
generated table, so the swap cost one line in a file this script writes anyway.

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

# The mask-drawing kit lives in `art_common` beside the shading it feeds,
# because the shards in `make_fx` are cut bodies too and there is no second
# right place for it.
Cut = A.Cut
_ngon_pts = A.ngon_pts
_star_pts = A.star_pts
_polar = A.polar


# ---------------------------------------------------------------------------
# Drawing the masks
#
# Everything below is in FINAL pixels -- `Cut` scales on the way in, so a shape
# function never has to think about the supersample factor. Same bargain
# `art_common.Canvas` makes, for the same reason.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# The round family: four sizes of one sealed bead
#
# **They are the same construction at four sizes rather than four different
# beads**, which is what makes a screen carrying all of them read as one
# arsenal: a dark bezel, an engraved hoop, a lifted inner field, ticks struck
# through the outer band, and a small hot core. It is `spr_boss_sigil`'s
# language -- rings and marks -- at a fortieth of the size, which is the point:
# a bullet a boss casts should look like something the boss's own circle
# produced.
#
# **The first pass of this was a brilliant cut seen from above** -- a hexagonal
# table with six facet breaks running out to the girdle -- and what six equal
# panels round a hexagon actually draws is a football. The failure is
# instructive and it is not about hexagons: any structure with the same order
# of symmetry as the silhouette, repeated at the same scale all the way to the
# edge, panels the shape instead of cutting it. What separates a bezel from a
# panel is that the bezel is *concentric* and the marks in it are small.
#
# What scales with size is the amount of structure, never the width of the
# bands -- see `edge_dist` for why.
# ---------------------------------------------------------------------------

def sh_pellet(w, h, **_):
    """Too small for a hoop, so it is the bezel alone: a cut hexagonal bead
    with a hot centre. At twenty-four pixels the six straight edges are the
    entire difference between a bead and a bubble."""
    c = Cut(w, h)
    c.ngon("body", c.cx, c.cy, 9.0, 6)
    c.ngon("core", c.cx, c.cy, 3.4, 6)
    c.blur("core", 0.30)
    return c


def _seal(c, r_body, r_ring, ring_w, ticks, tick_w, core_r, inner=None,
          alt=None):
    """A sealed bead: bezel, engraved hoop, lifted field, ticks, core.

    The field inside the hoop is lifted to two thirds rather than to the full
    `bevel`, because a hard step from a saturated bezel to a pale disc is a
    fried egg -- what is wanted is enough of a value break for the hoop to read
    as engraved and no more.
    """
    cx, cy = c.cx, c.cy
    c.disc("body", cx, cy, r_body)
    c.disc("bevel", cx, cy, r_ring - ring_w * 0.5, v=160)
    c.hoop("groove", cx, cy, r_ring, ring_w)

    n, r0, r1 = ticks
    for i in range(n):
        # **Alternating lengths where there are enough of them to count.**
        # Twelve equal ticks evenly spaced round two concentric hoops is a
        # clock face; long-short-long is a compass rose, which is the thing a
        # boss's own sigil is drawn out of.
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
    """The big one, and the only bullet in the set with room for a ward on it.

    Twelve ticks struck through the outer band, plus a second hoop inside the
    first. At the size this is fired at, a body with no incident in it is the
    one thing that reads as unfinished -- and marks that stop well short of the
    core are what keep the incident from becoming panelling.
    """
    return _seal(Cut(w, h), 37.0, 24.0, 2.1, (12, 26.4, 35.2), 2.0, 9.0,
                 inner=(14.0, 1.8), alt=31.0)


# ---------------------------------------------------------------------------
# Hollow: a seal, and the circle that contains it
# ---------------------------------------------------------------------------

def sh_ring(w, h, **_):
    """A segmented seal: an annulus with a lit channel down it, cut through at
    the diagonals so it reads as a *made* thing rather than as a washer."""
    c = Cut(w, h)
    cx, cy = c.cx, c.cy
    c.annulus("body", cx, cy, 20.0, 11.5)
    c.annulus("core", cx, cy, 16.4, 14.4)
    c.blur("core", 0.35)
    for i in range(4):
        c.spoke("groove", cx, cy, 45.0 + i * 90.0, 10.5, 21.0, 1.7)
    return c


def sh_bubble(w, h, **_):
    """A containment circle: two concentric hoops braced by four spokes.

    **Spokes rather than a wider wall.** The thing this has to say at seventy-
    six pixels is that it is hollow and deliberate; a fat ring says neither,
    and it is the only shape in the set whose interior the player may safely
    stand in, so the interior has to be unmistakably interior.
    """
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
# Every one of these points RIGHT, and every one of them carries a blade of
# light down its own axis rather than a highlight in a corner. **An axial core
# is what says "travelling"** -- it is the only kind of bright mark that does
# not move when the sprite rotates, so a fan of forty of them fanning out
# reads as forty things going somewhere rather than as forty lit beads.
# ---------------------------------------------------------------------------

def _blade(cx, cy, x_nose, x_tail, half):
    """A lens along the axis: the shape an axial core always is."""
    return [(x_nose, cy), (cx, cy - half), (x_tail, cy), (cx, cy + half)]


def sh_rice(w, h, **_):
    """The small workhorse. A hexagonal lozenge, not an ellipse -- at thirty-
    four pixels the straight edges are the entire difference between a shard of
    something and a grain of rice, and there are six hundred of these on screen
    at once."""
    c = Cut(w, h)
    cy = c.cy
    c.poly("body", [(32, cy), (23, cy - 7.5), (9, cy - 7.5),
                    (2, cy), (9, cy + 7.5), (23, cy + 7.5)])
    c.poly("core", _blade(16.0, cy, 28.0, 6.0, 2.2))
    c.blur("core", 0.30)
    return c


def sh_oval(w, h, **_):
    """A polished bead: a chamfered capsule with a table cut along it.

    Same construction as the crystal below on a blunt body, which is
    deliberate -- one cut repeated across the oriented shapes is a house style
    where three different treatments would be a collection.

    **The first version banded it instead**, with a pair of engraved shoulders
    top and bottom, and what two short vertical marks either side of a bright
    axis actually draws is the contact pad of a SIM card. Anything laid across
    the travel direction on a shape this rectangular reads as machined.
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
    """A kunai: point, barbed blade, collar, shaft.

    **Four pieces rather than a triangle**, because a triangle at forty-six
    pixels is a wedge of colour and the step where the blade meets the collar
    is what the eye reads as a *made* weapon. The old one was drawn as a
    chevron on a stick and photographed as clip art.
    """
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
    """A lance: spike, guard, haft.

    The guard is three pixels of sprite and it is what stops this reading as a
    sliver of light. **A needle with nothing behind its point has no scale** --
    it could be six pixels long or sixty -- and the step at the guard is the
    only thing in the silhouette that says which.
    """
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
    """An ofuda: a paper slip, swallowtailed at the back, with an incantation
    burning along it.

    **It was dark ink on a pale field for one pass and that was two mistakes.**
    A near-white body with a thin coloured edge is a bullet whose hue lives in
    two pixels, which is fourteen colours reduced to one. And a pale rectangle
    with a dark frame, a clipped leading corner and three horizontal marks in
    it is a *luggage tag* -- which is exactly what it photographed as, and no
    amount of redrawing the marks was going to fix a silhouette that was the
    problem.

    So the silhouette changed instead: a pennant with a point at the front and
    a V cut out of the tail, which is a shape nothing in an airport has. The
    writing is one continuous zigzag stroke rather than ruled lines, because
    three stacked bars at this size is a barcode for the same reason.

    It carries an *inscription* where the `rune` tile carries one figure, and
    that is the whole of what keeps two glyph-bearing shapes from reading as
    one idea drawn twice.
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
    """A cut shard, five facets of it visible.

    The case that proves the whole approach: a stone has no curvature at all,
    and everything the eye reads as a stone is flat planes meeting at angles.
    A silhouette shaded by depth makes a pillow out of it; a table, two ridges
    and a groove along each make a stone.
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
    """A five-pointed spark with a ridge down every arm.

    The ridge is the whole of it. A star shaded off its own depth is a star
    *sticker*; a star with a lit spine running out to each tip and the valleys
    between the arms cut dark is a star with facets.
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
    """A hexagram, drawn as two triangles that visibly cross.

    **The inner hexagon is engraved, and alternate arms are lit**, which is
    what makes the two triangles read as woven rather than as one six-pointed
    blob. A hexagram whose seam is invisible is a snowflake.
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
    """A warding tile: a chamfered plate with a lit sigil struck into it.

    **The glyph is the core, which is the opposite of the ofuda beside it.** A
    talisman is paper somebody wrote on and a rune is a stone somebody charged,
    so one has dark ink on a pale field and the other has a burning mark on a
    coloured one -- and having both is what stops the two shapes reading as the
    same idea at two angles.

    This is the slot the heart used to be in. A heart cannot be restyled into
    a warding sigil; it can only be replaced by one.
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
    """A tapered strip that sways along its length. Returns (outline, spine)."""
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
    """A moth. One swept wing a side, bitten along its trailing edge, with a
    hindwing lobe behind it -- plus a head and two antennae.

    **One wing per side and not four lobes**, which is the finding the previous
    version arrived at and the one thing about it worth keeping: four lobes at
    this size is a blob with sub-pixel notches in it.

    **The notch is deep, and it is what makes two wings out of one.** Bitten
    only a little, the forewing and the hindwing run into each other and the
    whole side is a fan of straight lines with veins on it -- which reads as a
    scallop shell.

    **The first angular attempt at it drew a fighter jet**, and every part of
    that was earned: a delta wing swept hard back, a long thin fuselage, a
    bright line running the whole length of it and two pale streamers off the
    front. So the wing is broad at its tip rather than pointed, the thorax
    stops well short of both ends, the lit axis is short, and there are
    antennae -- which are three pixels of sprite and the single cheapest thing
    that says *insect* rather than *aircraft*.
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
        # **The forewing is a lit plane and the hindwing is not**, which is
        # what tells them apart at 1:1 -- where the notch between them is two
        # pixels and the veins are one, and neither survives.
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


# The flame's head, in final pixels. **Mirrored by `ORIGINS` rather than
# guessed at twice**: the hitbox is the head and the sprite has to pivot about
# it, so the two numbers cannot be allowed to be edited apart.
def _flame_head(w, h):
    return (w - h * 0.30 - 2.0, (h - 1) / 2.0)


def sh_flame(w, h, frame=0, frames=4, **_):
    """A wisp: a round hot head with a tail that undulates away behind it and
    splits into two tongues at its end.

    **Three things had to be true and the first version had none of them.**
    The tail has to *leave the head*, so it starts at the head's own centre and
    the head is laid over it -- drawn as a separate strip butted up against a
    pointed head, the two disagree and what appears between them is a notch.
    The forks have to branch from the back half; two short symmetric tongues
    either side of the neck are fletching, and with a pointed head in front of
    them the whole thing was an arrow. And the head has to be *round*: fire has
    no leading edge, and a pointed one made this a dart with a flame decal.
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

    # **The core is axial, not a disc.** A round white centre in a round head
    # is one of the four round bullets with a tail glued to it, and at speed
    # that is what it reads as; a hot streak lying along the travel is fire.
    c.line("core", [(hx + 6.5, cy)] + spine[:5], 5.0)
    c.line("core", [(hx + 2.0, cy)] + spine[:11], 2.4)
    c.blur("core", 0.40)
    return c


def sh_mote(w, h, frame=0, frames=4, **_):
    """A four-point spark, which is the house motif -- the same figure is on
    the console's divider rules and on its crest. It pulses rather than
    spinning, because a spinning spark is a pinwheel."""
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
# w/h are the FINAL sprite size and include the margin the contour and the
# bloom need; `hit` is the radius the engine collides with and is a property of
# the drawn body, not of the canvas.
#
# **The hit radii are unchanged from the set this replaced.** A picture is
# allowed to change without the difficulty changing with it, and a redesign
# that quietly moved eighteen hitboxes would be impossible to review.
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

# How fast a shape turns on its own, in degrees per frame. `fire` reads it into
# the bullet's `spin`, which the engine has always had and which nothing but two
# hand-written patterns ever set.
#
# **The star-shaped ones turn and everything else does not**, which is the
# genre's convention and is worth having as a default rather than as something
# a pattern remembers: a spell that spun half its stars and not the other half
# would read as a bug in the spell. The rates go down as the shape goes up in
# size, because what the eye tracks is a *point* coming round and a big shape's
# points cover more ground per degree.
#
# Nothing oriented may have one. There `angle` is the heading, so a spin would
# aim the sprite somewhere the bullet is not going -- `test_bullet_table`
# asserts it rather than trusting this table to stay right.
SPIN = {
    "star":  2.2,
    "star6": 1.5,
    "mote":  2.8,
}

# The flame's hitbox is its head, and the head is at the right-hand end. The
# origin has to sit on the hitbox or the bullet pivots about its tail, which
# looks like a bullet that swings when it turns. Anything not named here is
# centred.
ORIGINS = {
    "flame": lambda w, h, pad: (int(round(_flame_head(w, h)[0])) + pad,
                                h // 2 + pad),
}


def _shape_pad(opts):
    """The empty canvas `cut_finish` will add round this shape.

    Read here as well as there because the flame's origin is on its head and
    the table records the sprite's real size -- both of which have to agree
    with a number `cut_finish` works out on its own.
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

    # ...and the same again over a bright, busy ground, because the whole point
    # of the core-inside-rim rule is that a bullet reads against *both*, and a
    # sheet on black only ever proves half of it.
    _bright_ground(sheets, len(A.BULLET_HUES)).save(
        os.path.join(A.PREVIEW, "bullets_bright.png"))

    # ...and once more at four times the size, three hues per shape and every
    # frame of the animated ones. **A bullet's structure is the thing being
    # reviewed and it is two pixels wide**, so a sheet at 1:1 can say whether
    # the set reads and cannot say whether any of it is drawn correctly.
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


TABLE_HEADER = '''/// @desc The bullet catalogue -- GENERATED by tools/make_bullets.py.
///
/// **Do not edit this file.** A bullet's hit radius and its picture have to
/// agree, and the picture is drawn in Python; a radius maintained by hand here
/// would drift from the sprite it describes within a week. Change
/// `tools/make_bullets.py` and re-run it.
///
/// A shape is one sprite whose frames are its colours. An animated shape folds
/// both axes into the one index, and `bullet_frame` is the only thing allowed
/// to compute it.

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
