#!/usr/bin/env python3
"""Mika's ring sprite (`spr_ring`).

One sprite with its colours baked in, matching the marking on the owner's
reference sheet (a black cuff edged in gold hairlines, with a gold interlace
knotted at every crossing down the middle). Unlike most art here it is not
tinted at draw time; a charged ring is the same sprite drawn again
additively in the attack's colour (`scripts/ring_functions`).

The band is computed as a field of (radius, angle). Its thickness ratio
`BAND_FRAC` must match `RING_BAND_FRAC` in `constants`, so the drawn metal
and the band that blocks shots are the same shape.

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

# How many times the interlace crosses itself round the ring (each crossing is
# a knot; the eye counts twice this many links).
LOBES = 9

# Two materials, each at two values (the reference is a flat two-colour
# design; full cylindrical shading would make it read as a pipe).
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
    Values outside [-1, 1] are off the metal; the coverage mask cuts the shape.
    """
    return (rr - R) / HALF


def coverage(u, soft=0.07):
    """A soft-edged mask of the band. `soft` is a fraction of the band's
    thickness, so the edge stays equally crisp at any scale.
    """
    return np.clip((1.0 - np.abs(u)) / soft, 0.0, 1.0)


def bump(x, width):
    """A raised cosine on [-width, width], exactly zero outside it (unlike a
    Gaussian, so nothing leaks past the band's edge).
    """
    t = np.clip(np.abs(x) / np.maximum(width, 1e-6), 0.0, 1.0)
    return 0.5 + 0.5 * np.cos(t * math.pi)


def rail(u, at, width):
    """One hairline of gold running round the band at |u| = `at`."""
    return bump(np.abs(u) - at, width)


def chain(u, th):
    """The interlace down the middle of the band: two crossing waves (`+A cos`
    and `-A cos`), so each link is a lens that closes to a point, plus a knot
    on every crossing.
    """
    ph = th * LOBES

    # The two curves; amplitude in units of `u` (a fraction of the band).
    amp = 0.40
    wave = amp * np.cos(ph)
    ribbon = np.maximum(bump(u - wave, 0.085), bump(u + wave, 0.085))

    # A knot on every crossing (`c` is the phase distance to the nearest).
    c = np.mod(ph - math.pi * 0.5, math.pi) - math.pi * 0.5
    ka = 0.20                       # radians of arc the knot spans
    kb = 0.15                       # ...and how far across the band
    e = np.sqrt((c / ka) ** 2 + (u / kb) ** 2)
    knot = bump(e - 1.0, 0.55)

    return np.clip(ribbon + knot, 0.0, 1.0)


def make_ring(rr, th):
    """The band, with its colours baked in."""
    u = band_u(rr)
    cov = coverage(u)

    # Four gold hairlines: one at each edge, and one each side of the channel
    # the interlace runs in, as in the reference.
    edge = rail(u, 0.93, 0.045)
    rails = rail(u, 0.70, 0.040)
    gilt = np.clip(edge + rails + chain(u, th), 0.0, 1.0)

    # The black at two values: a slight lift along the quarter lines, varying
    # slowly round the ring.
    lift = 0.6 * bump(np.abs(u) - 0.55, 0.45) * (0.8 + 0.2 * np.cos(th * 8.0))

    rgb = np.empty(u.shape + (3,), dtype=np.float32)
    for i in range(3):
        jet = JET[i] + (JET_LIT[i] - JET[i]) * lift
        # The gold is deeper over the darker parts of the black.
        au = GOLD_DEEP[i] + (GOLD[i] - GOLD_DEEP[i]) * (0.45 + 0.55 * lift)
        rgb[..., i] = jet + (au - jet) * gilt

    out = np.empty(u.shape + (4,), dtype=np.float32)
    out[..., :3] = rgb
    out[..., 3] = cov * 255.0
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    gm_new.folder("Sprites/ring")

    # Delete the sprites of the older three-sprite version.
    for stale in ("spr_ring_body", "spr_ring_gilt", "spr_ring_charge"):
        gm_new.delete(stale, "sprites")

    rr, th = fields()
    ring = make_ring(rr, th)
    gm_new.sprite("spr_ring", [ring], origin="center", folder="Sprites/ring")

    # Preview: plain, over a textured ground, charged (drawn additively over
    # itself, as the game does), and at in-game size.
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
