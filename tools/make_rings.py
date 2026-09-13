#!/usr/bin/env python3
"""Mika's rings: the large objects his whole fight is built out of.

A ring is not decoration and it is not a bullet. It is a *thing on the field*
-- it stops the player's shots, it fires patterns of its own, and when it is
charged its band kills -- so it has to read as a solid made object at any size
from a hundred pixels across to most of the playfield. See
`scripts/ring_functions` for what one does; this is what one looks like.

**It is one sprite with its colour baked in**, which is the opposite of what
nearly everything else here does, and the reason is that the ring is not a
shape being lit -- it is a *marking*. Mika's reference sheet draws the same
band on his tails, his biceps and his wrists: a broad black cuff edged by two
gold hairlines, with a chain of linked gold lozenges running down the middle
of it and a knot between every pair. That pattern is the character, so it is
drawn once, exactly, rather than being approximated in white and tinted into
some other hue at every call site. A ring that came out cyan for a cyan spell
would be a different object, not the same object under different light.

What the spell's colour does get is the *charge*: the same sprite drawn again
additively over itself, so the gold chasing blazes in the attack's hue while
the metal underneath stays black gold. The marking is the conductor, which is
the whole idea of the fight.

**The band is drawn as a radial field rather than out of polygons.** An
annulus is one subtraction in polar coordinates and a chased annulus is a
handful of terms on top of it, where the same thing built out of
`ImageDraw.arc` is a few hundred segments with a seam wherever two of them
meet. Every term below is a function of (radius, angle), which also means the
picture and `RING_BAND_FRAC` cannot drift apart: the ratio below is the number
in `constants`, and it is what makes the drawn metal and the band that blocks
a shot the same shape by construction rather than by agreement.

Usage:
    python tools/make_rings.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SIZE = 512
SS = 2                       # the fields are smooth; 2x is plenty
R = 200.0                    # the band's centre line, in final pixels
HALF = 32.0                  # half its thickness
BAND_FRAC = HALF / R         # 0.16 -- must match RING_BAND_FRAC

# How many times the interlace crosses itself round the ring. Each crossing is
# a knot and each span between two of them is a lens, so this is *half* the
# number of links the eye counts.
LOBES = 9

# **Two materials and no others.** The reference is a flat two-colour design
# and the temptation with a ring this size is to give the metal a full
# cylindrical shade -- which turns a marking into a pipe. What is here is the
# black at two values and the gold at two, which is enough for relief and not
# enough to stop it reading as the same band he wears.
JET = (27, 24, 21)
JET_LIT = (54, 47, 39)
GOLD = (245, 176, 30)
GOLD_DEEP = (188, 124, 16)


def fields():
    """Radius and angle for every pixel, in final-pixel units."""
    n = SIZE * SS
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    cx = cy = (n - 1) * 0.5
    dx = (xs - cx) / SS
    dy = (ys - cy) / SS
    return np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)


def band_u(rr):
    """Where a pixel is across the band: -1 at the inner edge, +1 at the outer.

    Values outside [-1, 1] are off the metal, and every term below is written
    to be harmless there -- the coverage mask is what cuts the shape, once, so
    no ornament has to remember to stay inside it.
    """
    return (rr - R) / HALF


def coverage(u, soft=0.07):
    """A soft-edged mask of the band itself.

    `soft` is in units of `u`, so it is a *fraction of the band's thickness*
    rather than a number of pixels -- which keeps the edge the same crispness
    however the ring is scaled at draw time.
    """
    return np.clip((1.0 - np.abs(u)) / soft, 0.0, 1.0)


def bump(x, width):
    """A raised cosine on [-width, width], **exactly zero outside it**.

    A Gaussian is the obvious choice and it never reaches zero, so every rail
    and every link would leave a faint haze right across the band and out past
    its edge -- which on a shape whose whole job is to have a hard boundary is
    the one thing that cannot be allowed.
    """
    t = np.clip(np.abs(x) / np.maximum(width, 1e-6), 0.0, 1.0)
    return 0.5 + 0.5 * np.cos(t * math.pi)


def rail(u, at, width):
    """One hairline of gold running round the band at |u| = `at`."""
    return bump(np.abs(u) - at, width)


def chain(u, th):
    """The interlace down the middle of the band.

    **It is two crossing curves, not a row of separate links**, and getting
    that wrong is what made the first version read as a string of beads. The
    reference draws one continuous ribbon that crosses itself: a lens opens
    between two crossings, closes to a point, and the next one opens on the
    other side of the line. So what is drawn here is literally two waves --
    `+A cos` and `-A cos` -- and the lens shapes are what falls out between
    them. A knot sits on every crossing, which is where the ribbon passes
    through itself.

    Drawn this way the ends of every link come to a **point** rather than a
    curve, which is the single most recognisable thing about the marking and
    the thing an ellipse cannot do.
    """
    ph = th * LOBES

    # The two curves. The amplitude is in units of `u`, so the interlace is a
    # fixed fraction of the band's thickness at any size.
    amp = 0.40
    wave = amp * np.cos(ph)
    ribbon = np.maximum(bump(u - wave, 0.085), bump(u + wave, 0.085))

    # A knot on every crossing. `c` is the signed phase distance to the nearest
    # one, which is what puts a circle there without having to find them.
    c = np.mod(ph - math.pi * 0.5, math.pi) - math.pi * 0.5
    ka = 0.20                       # radians of arc the knot spans
    kb = 0.15                       # ...and how far across the band
    e = np.sqrt((c / ka) ** 2 + (u / kb) ** 2)
    knot = bump(e - 1.0, 0.55)

    return np.clip(ribbon + knot, 0.0, 1.0)


def make_ring(rr, th):
    """The band, with its colour baked in."""
    u = band_u(rr)
    cov = coverage(u)

    # **Four hairlines and not two.** The reference band carries a line right
    # at each edge, a black gap, and then a second line bounding the channel
    # the interlace runs in -- so the chain reads as being *inlaid* into a cuff
    # rather than as being printed on a strip. It is the same relief the
    # console's engraved divisions are built on, and it costs one term.
    edge = rail(u, 0.93, 0.045)
    rails = rail(u, 0.70, 0.040)
    gilt = np.clip(edge + rails + chain(u, th), 0.0, 1.0)

    # The black underneath, at two values: a shallow lift along the quarter
    # lines so the cuff has a little roundness, and a slow eight-period
    # variation round the ring so the metal is not perfectly uniform. Both are
    # small on purpose -- see the note on materials above.
    lift = 0.6 * bump(np.abs(u) - 0.55, 0.45) * (0.8 + 0.2 * np.cos(th * 8.0))

    rgb = np.empty(u.shape + (3,), dtype=np.float32)
    for i in range(3):
        jet = JET[i] + (JET_LIT[i] - JET[i]) * lift
        # The gold is deeper where it crosses the shadowed part of the cuff,
        # which is the only place the two materials are allowed to talk to
        # each other.
        au = GOLD_DEEP[i] + (GOLD[i] - GOLD_DEEP[i]) * (0.45 + 0.55 * lift)
        rgb[..., i] = jet + (au - jet) * gilt

    out = np.empty(u.shape + (4,), dtype=np.float32)
    out[..., :3] = rgb
    out[..., 3] = cov * 255.0
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    gm_new.folder("Sprites/ring")

    # The three-sprite version this replaced. Left as an explicit removal
    # rather than as orphaned files, because a sprite nothing references is
    # still a sprite in the project, on the texture page, and in every check
    # that walks `sprites/`.
    for stale in ("spr_ring_body", "spr_ring_gilt", "spr_ring_charge"):
        gm_new.delete(stale, "sprites")

    rr, th = fields()
    ring = make_ring(rr, th)
    gm_new.sprite("spr_ring", [ring], origin="center", folder="Sprites/ring")

    # **The preview shows it over a lit ground and charged**, because a ring
    # judged on black is a ring nobody has checked against the one thing it
    # has to read against, and the charge is the state it kills in.
    fbm = np.asarray(A.fbm_field(SIZE, SIZE, 7, octaves=4, base=5),
                     dtype=np.float32) / 255.0
    arr = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    arr[..., 0] = fbm * 90
    arr[..., 1] = fbm * 34
    arr[..., 2] = fbm * 16
    arr[..., 3] = 255
    ground = Image.fromarray(arr.astype(np.uint8), "RGBA")

    cold = ground.copy()
    cold.alpha_composite(ring)

    hot = cold.copy()
    hot = A.add(hot, ring)
    hot = A.add(hot, ring)

    small = ring.resize((166, 166), Image.LANCZOS)
    A.preview([ring, cold, hot, small],
              os.path.join(A.PREVIEW, "rings.png"), cols=4, bg=(16, 12, 14),
              labels=["ring", "over a stage", "charged",
                      "at the size the game draws it"])
    print("rings: 1 sprite of %dx%d, band %.3f of radius, %d lobes"
          % (SIZE, SIZE, BAND_FRAC, LOBES))


if __name__ == "__main__":
    main()
