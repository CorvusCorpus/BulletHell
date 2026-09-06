#!/usr/bin/env python3
"""The fodder: a wisp, a grimoire, a cut gem and a stone sentry.

**Nothing here is a creature**, which is a story decision before it is an art
one. The game is about an imp who is tired of being somebody's trash mob, so
filling his stages with trash mobs that are people would say the opposite of
what the game is about. What he cuts through is animated furniture -- somebody
else's tools, left running.

**They are drawn greyscale and tinted at draw time**, so one set of four serves
every stage in the game: crimson wisps over Ziggy's brimstone, jade ones in a
yokai forest, violet in a vampire's hall. `enemy_draw` multiplies by the hue on
the enemy's `col`, which is why the art here is built out of a bright core and
a dark rim exactly as the bullets are -- a multiply maps that structure onto
any hue and keeps the reading. A flat mid-grey would tint to a flat mid-hue and
disappear.

What a silhouette is not enough for
-----------------------------------

The first version of these was a silhouette per shape run through
`shade_shape`, and at the size they are actually seen that is what it looked
like: four flat lozenges. `shade_shape` lights a shape by how deep inside it a
pixel is, which is the right answer for a *bullet* -- a bullet is a bead of
light and has no interior -- and the wrong one for an object, because an object
has planes and the planes are how the eye works out what it is looking at.

So each of these is now three things multiplied together:

body      the silhouette, shaded by depth, exactly as before
facets    a value per plane, so the form turns rather than bulges
detail    grooves, grain and inlay -- what the object is made of

plus a hard dark contour round the outside, for the same reason every bullet
has one: it is the one mark an additive background light cannot make, and it is
what keeps a dark shape legible over a bright one. See `CONTOUR` in
`make_bullets.py`.

Usage:
    python tools/make_enemies.py
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

# The "hue" the greyscale art is built in. Not pure white: `shade_shape` puts
# the rim at a third of this, and a rim off pure white is a neutral grey that
# tints to a dead colour. A hair of blue keeps the dark parts cool, which is
# what the multiply then carries into whatever hue it is given.
PALE = (236, 240, 252)

# The dark ring, in final pixels. Same argument as the bullets'.
CONTOUR = 2.0


def _mask(w, h):
    img = Image.new("L", (int(w * SS), int(h * SS)), 0)
    return img, ImageDraw.Draw(img)


# The value a facet map treats as leaving a plane alone, and the most it is
# allowed to brighten one by.
#
# **Neutral is high and the ceiling is low, because the body underneath is
# already nearly white.** `shade_shape` puts a white core in the middle of
# every silhouette; a facet map centred on mid-grey is therefore free to
# multiply that core by 1.8, which clips -- and a clipped facet is a flat white
# region with no plane information left in it at all. Photographed, all four of
# these came back as paper cut-outs.
#
# Painting mostly *below* neutral keeps the arithmetic in range, and it is also
# how carving works: a plane turned toward the light is barely brighter than
# the material it is cut from, and every other plane is darker.
FACET_NEUTRAL = 190.0
FACET_MAX = 1.15


def _facets(w, h):
    """A canvas to paint plane values into. FACET_NEUTRAL leaves one alone."""
    img = Image.new("L", (int(w * SS), int(h * SS)), int(FACET_NEUTRAL))
    return img, ImageDraw.Draw(img)


# ---------------------------------------------------------------------------
# The wisp -- a flame with a core and a tail of embers
# ---------------------------------------------------------------------------

def wisp(w, h, frame, frames):
    """A flame: rounded at the foot, bulging low, tapering to a licking point.

    The first version made the width a single `sin(pi * t)`, which is symmetric
    -- and a symmetric flame is an oval. **What makes a flame a flame is that
    its widest point is near the bottom**, so the silhouette has a shoulder and
    then a long taper; a shape whose widest point is in the middle reads as an
    egg however much it flickers.
    """
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames

    pts_l, pts_r = [], []
    n = 46
    for i in range(n + 1):
        t = i / n                              # 0 at the foot, 1 at the tip
        y = H * 0.86 - t * H * 0.78
        taper = (1.0 - t) ** 1.7               # convex fall to the point
        foot = min(1.0, (0.10 + t) / 0.26)     # rounds the very bottom off
        half = W * 0.32 * taper * foot + W * 0.012
        # The lick: the tip wanders and the base does not, so it flickers
        # rather than sways.
        lick = math.sin(t * 3.4 + ph) * W * 0.09 * (t ** 2)
        pts_l.append((cx + lick - half, y))
        pts_r.append((cx + lick + half, y))
    d.polygon(pts_l + pts_r[::-1], fill=255)

    # A ring of shed embers, orbiting rather than scattered. **Orbiting is what
    # says the thing is running**; a random spray of dots says it is on fire,
    # which for a lantern-flame somebody left burning is the wrong verb.
    for i in range(5):
        ang = ph + i * 2 * math.pi / 5
        ex = cx + math.cos(ang) * W * 0.40
        ey = H * 0.58 + math.sin(ang) * H * 0.17
        er = W * (0.045 + 0.018 * math.cos(ang * 2))
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=255)

    return img


def wisp_facets(w, h, frame, frames):
    """The flame's two sides. A flame is not flat, and one side of it is
    turned away -- which is the entire reason it reads as a volume rather than
    as a leaf."""
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames
    # The far side, darkened. Drawn as a tall wedge down the right of the
    # flame, which is the side away from the light everything else here uses.
    d.polygon([(cx + W * 0.02, H * 0.90), (cx + W * 0.06, H * 0.10),
               (cx + W * 0.34, H * 0.55), (cx + W * 0.26, H * 0.88)],
              fill=86)
    # ...and the sheet of brightest flame just inside the leading edge.
    d.polygon([(cx - W * 0.13, H * 0.82), (cx - W * 0.06, H * 0.22),
               (cx + W * 0.02, H * 0.60), (cx - W * 0.02, H * 0.86)],
              fill=214)
    # A bright iris round the hollow. **This is what turns a teardrop into a
    # wisp**: an eye is a dark centre with a lit ring, and without the ring the
    # hollow reads as a hole punched in a leaf.
    ey = H * 0.60 + math.sin(ph) * H * 0.02
    rx, ry = W * 0.26, H * 0.22
    d.ellipse([cx - rx, ey - ry, cx + rx, ey + ry], fill=218)
    return img.filter(ImageFilter.GaussianBlur(SS * 1.6))


def wisp_cuts(w, h, frame, frames):
    """The dark hollow at the flame's heart -- what makes it a wisp with a core
    rather than a leaf."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames
    cy = H * 0.60 + math.sin(ph) * H * 0.02
    rx, ry = W * 0.15, H * 0.13
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    return img


# ---------------------------------------------------------------------------
# The grimoire -- an open tome, seen from above, pages beating
# ---------------------------------------------------------------------------
#
# **This is the third silhouette this object has had and the reasoning behind
# each rejection is worth keeping**, because it is the same reasoning any
# future piece of fodder will have to survive.
#
# It was drawn open and face-on first: two panels meeting at a point, which at
# this size is a bowtie, and unmistakably was one.
#
# It was then drawn shut -- a squat block with page-fans beating either side --
# and that read, in the project's own notes, as "a floating tome and not much
# more". The trouble was that a closed book is a *rectangle*, and a rectangle
# with fins is read as whatever the viewer has most recently seen with fins.
# Standing it on its end and adding a spine and a page block made it a
# rectangle with a stripe down each side, which is a door.
#
# What it is now is open again, but seen from **above** rather than from the
# front, which is the view that fixes the bowtie: from overhead the two halves
# are quadrilaterals lying at an angle rather than triangles meeting at a
# vertex, they are separated by a gutter instead of touching, and the outer
# edges are page blocks rather than points. Nothing about it can collapse into
# a bowtie because nothing about it comes to a point.
#
# The lesson underneath all three: at eighty pixels an object is read off its
# *silhouette and its proportions*, never off its detail. Detail is what makes
# it look expensive once it is already recognisable.


def _tome_pages(W, H):
    """The two page panels, as (left, right) point lists.

    Splayed from a gutter down the middle, each one wider at its outer edge --
    which is what a book lying open looks like from above and is the whole of
    why this cannot read as a bowtie.
    """
    cx, cy = W / 2.0, H / 2.0
    gut = W * 0.045                       # half the gutter
    out = W * 0.44                        # how far the outer edge reaches
    left = [(cx - gut, cy - H * 0.24), (cx - out, cy - H * 0.14),
            (cx - out, cy + H * 0.24), (cx - gut, cy + H * 0.26)]
    right = [(cx + gut, cy - H * 0.24), (cx + out, cy - H * 0.14),
             (cx + out, cy + H * 0.24), (cx + gut, cy + H * 0.26)]
    return left, right


def grimoire(w, h, frame, frames):
    """An open tome held flat in the air, with loose pages lifting off it."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    beat = math.sin(2 * math.pi * frame / frames)

    left, right = _tome_pages(W, H)

    # The boards, behind and a little below the pages, so the book has a
    # thickness rather than being two sheets of paper.
    for pts in (left, right):
        d.polygon([(x + (W * 0.012 if x > cx else -W * 0.012), y + H * 0.030)
                   for x, y in pts], fill=255)
    d.polygon(left, fill=255)
    d.polygon(right, fill=255)

    # **Loose pages lifting off the outer corners.** They are the animation and
    # they are also what says the book is *working* -- a tome lying open and
    # still is furniture, and a tome shedding pages is casting.
    for sign, pts in ((-1, left), (1, right)):
        for i in range(3):
            spread = (i + 1) / 3.0
            lift = (beat * 0.5 + 0.5) * spread
            rx = cx + sign * (W * 0.30 + W * 0.10 * spread)
            ry = cy - H * 0.20 - H * 0.20 * lift
            d.polygon([(rx - sign * W * 0.10, ry + H * 0.14),
                       (rx + sign * W * 0.12, ry - H * 0.03),
                       (rx + sign * W * 0.15, ry + H * 0.09),
                       (rx - sign * W * 0.05, ry + H * 0.20)], fill=255)

    # The rune hanging over the gutter, pulsing. It is the only part of the
    # object above the book, so it is also what keeps the silhouette from being
    # a horizontal slab.
    rr = W * (0.085 + 0.012 * beat)
    ry = cy - H * 0.40
    pts = []
    for i in range(8):
        ang = math.radians(-90 + i * 45)
        rad = rr if i % 2 == 0 else rr * 0.34
        pts.append((cx + math.cos(ang) * rad, ry + math.sin(ang) * rad))
    d.polygon(pts, fill=255)
    return img


def grimoire_facets(w, h, frame, frames):
    """The two page planes, the gutter between them, and the boards under.

    An open book from above is two flat sheets tilted toward each other, so
    they cannot be the same value -- and the gutter between them is the darkest
    thing on the object, because it is the one part light does not reach.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    left, right = _tome_pages(W, H)

    # Loose paper first, across the whole canvas, then covered by everything
    # else -- so the flying pages get the palest value and nothing else does.
    d.rectangle([0, 0, W, H], fill=216)
    # The boards: dark leather under the paper.
    for pts in (left, right):
        d.polygon([(x + (W * 0.012 if x > cx else -W * 0.012), y + H * 0.030)
                   for x, y in pts], fill=72)
    # The left page catches the light; the right one is turned away from it.
    d.polygon(left, fill=200)
    d.polygon(right, fill=132)
    # The gutter, in shadow.
    d.rectangle([cx - W * 0.055, cy - H * 0.25, cx + W * 0.055, cy + H * 0.27],
                fill=76)
    return img.filter(ImageFilter.GaussianBlur(SS * 0.9))


def grimoire_cuts(w, h, frame, frames):
    """Text on the pages, and the leaves stacked under each one.

    **Ruled lines, not letters.** Anything glyph-shaped at this size is a
    smudge that reads as dirt; a stack of horizontal rules is read as writing
    by everybody and costs six calls.
    """
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0

    for sign in (-1, 1):
        for i in range(5):
            t = (i + 1) / 6.0
            y = cy - H * 0.17 + t * H * 0.36
            x0 = cx + sign * W * 0.075
            x1 = cx + sign * (W * 0.36 - W * 0.03 * i)
            d.line([(x0, y), (x1, y)], fill=210,
                   width=max(2, int(H * 0.011)))

    # The leaves in the block, along the outer edge of each page.
    for sign in (-1, 1):
        for i in range(4):
            x = cx + sign * (W * 0.40 - W * 0.011 * i)
            d.line([(x, cy - H * 0.10), (x, cy + H * 0.21)], fill=150,
                   width=max(2, int(W * 0.006)))

    # And the gutter itself, cut deep.
    d.rectangle([cx - W * 0.020, cy - H * 0.24, cx + W * 0.020, cy + H * 0.25],
                fill=255)
    return img


# ---------------------------------------------------------------------------
# The gem -- an octahedron, turning
# ---------------------------------------------------------------------------

def _gem_outline(W, H, frame, frames):
    cx, cy = W / 2.0, H / 2.0
    turn = 2 * math.pi * frame / frames
    half = W * 0.32 * abs(math.cos(turn)) + W * 0.085
    waist = H * 0.16
    return cx, cy, half, waist


def gem(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    # Turning about its vertical axis: the silhouette narrows and swells, which
    # is the whole of the rotation at this size.
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    d.polygon([(cx, cy - H * 0.42), (cx + half, cy - waist),
               (cx + half * 0.82, cy + waist), (cx, cy + H * 0.42),
               (cx - half * 0.82, cy + waist), (cx - half, cy - waist)],
              fill=255)
    return img


def gem_facets(w, h, frame, frames):
    """Six planes, each its own value.

    **This is the whole of what makes a gem a gem.** A cut stone has no
    curvature at all; every part of what the eye reads as sparkle is flat faces
    at different angles to the light, and shading one silhouette by depth --
    which is what this used to do -- produces a pillow. Six polygons and six
    numbers produce a stone, and the numbers are more important than the
    polygons: crown bright, girdle mid, pavilion dark, and one face on each
    side left near-white as the catch-light.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    top = (cx, cy - H * 0.42)
    bot = (cx, cy + H * 0.42)
    l_up, r_up = (cx - half, cy - waist), (cx + half, cy - waist)
    l_dn = (cx - half * 0.82, cy + waist)
    r_dn = (cx + half * 0.82, cy + waist)
    mid_up, mid_dn = (cx, cy - waist * 0.4), (cx, cy + waist * 0.6)

    # Crown: two faces, the left one catching.
    d.polygon([top, l_up, mid_up], fill=218)
    d.polygon([top, r_up, mid_up], fill=152)
    # Girdle band.
    d.polygon([l_up, mid_up, mid_dn, l_dn], fill=175)
    d.polygon([r_up, mid_up, mid_dn, r_dn], fill=99)
    # Pavilion: darkest, because it is pointing away and down.
    d.polygon([l_dn, mid_dn, bot], fill=114)
    d.polygon([r_dn, mid_dn, bot], fill=61)
    # **Barely blurred.** A gem's facets meet at hard lines; softening them by
    # more than a pixel is how a cut stone turns back into a pebble.
    return img.filter(ImageFilter.GaussianBlur(SS * 0.35))


def gem_cuts(w, h, frame, frames):
    """The grooves where facets meet. Subtracted, so they are edges in the
    stone rather than lines on it."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    wide = max(2, int(W * 0.010))
    d.line([(cx - half, cy - waist), (cx + half, cy - waist)], fill=255,
           width=wide)
    d.line([(cx - half * 0.82, cy + waist), (cx + half * 0.82, cy + waist)],
           fill=255, width=wide)
    d.line([(cx, cy - H * 0.42), (cx, cy + H * 0.42)], fill=190, width=wide)
    return img


# ---------------------------------------------------------------------------
# The sentry -- a carved mask that hangs in the air and watches
# ---------------------------------------------------------------------------

def _sentry_face(W, H):
    cx, cy = W / 2.0, H / 2.0
    return [(cx - W * 0.32, cy - H * 0.31), (cx + W * 0.32, cy - H * 0.31),
            (cx + W * 0.28, cy + H * 0.12), (cx, cy + H * 0.41),
            (cx - W * 0.28, cy + H * 0.12)]


def sentry(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    ph = 2 * math.pi * frame / frames

    d.polygon(_sentry_face(W, H), fill=255)
    # Horns, so it reads as an idol rather than as a shield.
    for sign in (-1, 1):
        d.polygon([(cx + sign * W * 0.25, cy - H * 0.29),
                   (cx + sign * W * 0.45, cy - H * 0.47),
                   (cx + sign * W * 0.33, cy - H * 0.18)], fill=255)
    # A collar under the chin: it is a bust, not a face floating alone.
    d.polygon([(cx - W * 0.22, cy + H * 0.20), (cx + W * 0.22, cy + H * 0.20),
               (cx + W * 0.15, cy + H * 0.36), (cx - W * 0.15, cy + H * 0.36)],
              fill=255)

    # Three orbiting shards, which is what says it is *active*.
    for i in range(3):
        ang = ph + i * 2 * math.pi / 3
        ox = cx + math.cos(ang) * W * 0.43
        oy = cy + math.sin(ang) * H * 0.25 + H * 0.06
        r = W * 0.052
        d.polygon([(ox, oy - r * 1.6), (ox + r, oy), (ox, oy + r * 1.6),
                   (ox - r, oy)], fill=255)
    return img


def sentry_facets(w, h, frame, frames):
    """The planes a face is carved in: brow, cheeks, nose, jaw.

    A mask is a *carving*, and a carving is a small number of large flat cuts.
    The values below are doing the same job the gem's are and are picked the
    same way -- lit from the upper left, so the left cheek is the pale one.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0

    # The brow, overhanging and therefore the brightest thing on the face.
    d.polygon([(cx - W * 0.32, cy - H * 0.31), (cx + W * 0.32, cy - H * 0.31),
               (cx + W * 0.30, cy - H * 0.14), (cx - W * 0.30, cy - H * 0.14)],
              fill=213)
    # Cheeks: the left one turned toward the light, the right away from it.
    d.polygon([(cx - W * 0.30, cy - H * 0.14), (cx, cy - H * 0.08),
               (cx, cy + H * 0.38), (cx - W * 0.28, cy + H * 0.11)], fill=163)
    d.polygon([(cx + W * 0.30, cy - H * 0.14), (cx, cy - H * 0.08),
               (cx, cy + H * 0.38), (cx + W * 0.28, cy + H * 0.11)], fill=87)
    # The nose ridge down the middle, catching.
    d.polygon([(cx - W * 0.045, cy - H * 0.12), (cx + W * 0.045, cy - H * 0.12),
               (cx + W * 0.03, cy + H * 0.14), (cx - W * 0.03, cy + H * 0.14)],
              fill=218)
    # The collar, in shadow under the jaw.
    d.polygon([(cx - W * 0.22, cy + H * 0.20), (cx + W * 0.22, cy + H * 0.20),
               (cx + W * 0.15, cy + H * 0.36), (cx - W * 0.15, cy + H * 0.36)],
              fill=68)
    return img.filter(ImageFilter.GaussianBlur(SS * 0.9))


def sentry_cuts(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    # Two eye slots and a mouth, cut through.
    for sign in (-1, 1):
        d.polygon([(cx + sign * W * 0.07, cy - H * 0.14),
                   (cx + sign * W * 0.24, cy - H * 0.18),
                   (cx + sign * W * 0.23, cy - H * 0.06),
                   (cx + sign * W * 0.08, cy - H * 0.04)], fill=255)
    d.rectangle([cx - W * 0.12, cy + H * 0.09, cx + W * 0.12, cy + H * 0.15],
                fill=255)
    # Weathering: chips along the brow and a split down one cheek, so no two
    # sentries in a wave are read as one sprite repeated.
    rnd = np.random.default_rng(5)
    for _ in range(7):
        ex = rnd.uniform(cx - W * 0.28, cx + W * 0.28)
        ey = rnd.uniform(cy - H * 0.26, cy + H * 0.16)
        er = rnd.uniform(W * 0.012, W * 0.030)
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=120)
    d.line([(cx + W * 0.14, cy - H * 0.24), (cx + W * 0.19, cy + H * 0.06)],
           fill=150, width=max(2, int(W * 0.008)))
    return img


# ---------------------------------------------------------------------------
#
# **Half again the size they were.** These are seen against a 1920x1080 field
# with 54-pixel bullets on it, and at 60 to 96 pixels they were smaller than
# some of the things they fire. The hit radii in `enemy_radius` came up with
# them.
# ---------------------------------------------------------------------------

SHAPES = [
    # name                w    h  frames  body       facets          cuts
    ("spr_foe_wisp",      88, 112, 4, wisp,      wisp_facets,     wisp_cuts),
    ("spr_foe_grimoire", 130, 116, 4, grimoire,  grimoire_facets, grimoire_cuts),
    ("spr_foe_gem",       94, 100, 6, gem,       gem_facets,      gem_cuts),
    ("spr_foe_sentry",   136, 130, 4, sentry,    sentry_facets,   sentry_cuts),
]


def build(spec):
    name, w, h, frames, body_fn, facet_fn, cut_fn = spec
    out = []
    for f in range(frames):
        mask = body_fn(w, h, f, frames)
        # **A smaller white core than a bullet gets.** These are tinted by a
        # multiply, so the only band of the greyscale that can carry a hue is
        # the one that is not already white -- at 0.46 nearly half of every
        # enemy was pure white and came out of the multiply as flat,
        # undifferentiated colour. Under a third is enough to keep the shape
        # reading against a bright background, and it leaves the rest of the
        # body to be tinted.
        img = A.shade_shape(mask, PALE, core_frac=0.30, edge_frac=0.40,
                            halo=0.30)
        arr = np.asarray(img, dtype=np.float32)

        if facet_fn is not None:
            # **Planes, multiplied in.** FACET_NEUTRAL leaves a region alone,
            # so anything the facet map does not paint keeps the depth shading
            # underneath -- which means a facet map is a set of corrections to
            # a body that already reads, not a replacement for it.
            fac = np.asarray(facet_fn(w, h, f, frames),
                             dtype=np.float32) / FACET_NEUTRAL
            arr[..., :3] *= np.minimum(fac, FACET_MAX)[..., None]

        if cut_fn is not None:
            # The grooves: darken the body where the cut is, rather than
            # punching a hole in it. A hole would show the background through a
            # solid object, and at this size that reads as a rendering fault.
            cut = np.asarray(
                cut_fn(w, h, f, frames).filter(ImageFilter.GaussianBlur(SS * 0.6)),
                dtype=np.float32) / 255.0
            arr[..., :3] *= (1 - cut[..., None] * 0.74)

        # Grain, so a surface is a material rather than a fill. Two scales,
        # because one reads as film noise and two as stone -- the finding the
        # Wordsearch slabs are built on, and the backgrounds here too.
        g1 = np.asarray(A.fbm_field(arr.shape[1], arr.shape[0], hash(name) % 9973,
                                    octaves=3, base=26), dtype=np.float32) / 255.0
        g2 = np.asarray(A.fbm_field(arr.shape[1], arr.shape[0],
                                    hash(name) % 9973 + 71, octaves=2, base=90),
                        dtype=np.float32) / 255.0
        arr[..., :3] *= (0.90 + 0.14 * g1 + 0.08 * g2)[..., None]

        img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        out.append(_contoured(img.resize((w, h), Image.LANCZOS)))
    return out


def _contoured(small):
    """The dark ring, traced at final size around the body rather than the
    halo. Same routine and same reasons as `make_bullets._contoured`."""
    solid = small.getchannel("A").point(lambda v: 255 if v >= 150 else 0)
    body = small.copy()
    body.putalpha(solid)
    ring = A.trace_outline(body, width=CONTOUR, colour=(0, 0, 0, 230))
    ring = ring.filter(ImageFilter.GaussianBlur(0.55))
    return A.over(ring, small)


def main():
    gm_new.folder("Sprites/foes")

    shown = []
    labels = []
    for spec in SHAPES:
        frames = build(spec)
        gm_new.sprite(spec[0], frames, origin="center", folder="Sprites/foes",
                      fps=10.0)
        for i, f in enumerate(frames):
            shown.append(f)
            labels.append(spec[0].replace("spr_foe_", "") if i == 0 else "")
        print("%-18s %d frames of %dx%d" % (spec[0], len(frames),
                                            spec[1], spec[2]))

    # Previewed tinted, because greyscale is not the state they ship in and a
    # sheet of grey shapes proves nothing about how they read on a stage.
    tinted = []
    for _name, col in (("crimson", A.hue("crimson")), ("jade", A.hue("jade")),
                       ("violet", A.hue("violet"))):
        for spec in SHAPES:
            f = build(spec)[0]
            arr = np.asarray(f, dtype=np.float32)
            arr[..., :3] *= np.array(col, dtype=np.float32) / 255.0
            tinted.append(Image.fromarray(arr.astype(np.uint8), "RGBA"))

    A.preview(shown + tinted, os.path.join(A.PREVIEW, "foes.png"),
              cols=6, bg=(22, 24, 36))


if __name__ == "__main__":
    main()
