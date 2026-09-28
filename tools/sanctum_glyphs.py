#!/usr/bin/env python3
"""Hieroglyphs and Egyptian ornament for Mika's hall, drawn as filled shapes.

Imported by `make_sanctum.py`. Everything here draws into a single-channel
mask (255 is material, 0 is none) at whatever supersampled size the caller
works at; `sanctum_relief.Plate` turns masks into inlay and carving.

A glyph is a function of a `Pen`, which maps the glyph's own unit box onto
the target (u across, v down, both 0..1). Widths are in units of the box's
shorter side, so a stroke weighs the same in a tall glyph as in a flat one.
Each glyph is drawn as solid forms of varying weight, the way a carver cuts
them, not as outlines.

Glyphs come in three shapes, as in real texts: tall ones (a reed, an ankh)
stand two to a square; flat ones (water, a mouth) stack two or three to a
square; square ones (birds, the eye) fill it. `column` lays a run of them out
in those squares.
"""
import math

import numpy as np
from PIL import Image, ImageDraw


def catmull(pts, n=12, closed=False):
    """A Catmull-Rom curve through the points."""
    p = list(pts)
    m = len(p)
    if m < 3:
        return p
    out = []
    rng = range(m) if closed else range(m - 1)
    for i in rng:
        p0 = p[(i - 1) % m] if closed else p[max(0, i - 1)]
        p1 = p[i]
        p2 = p[(i + 1) % m] if closed else p[min(m - 1, i + 1)]
        p3 = p[(i + 2) % m] if closed else p[min(m - 1, i + 2)]
        for k in range(n):
            t = k / float(n)
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t
                       + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                       + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3)
                for j in range(2)))
    if not closed:
        out.append(p[-1])
    return out


class Pen:
    """Draws into `draw` (an `ImageDraw` on an L image) inside the box
    `(x0, y0, w, h)`. `ink` is the value laid down; `cut` draws 0.
    """

    def __init__(self, draw, x0, y0, w, h, ink=255, flip=False):
        self.d = draw
        self.x0, self.y0, self.w, self.h = x0, y0, w, h
        self.ink = ink
        self.flip = flip
        self.unit = min(w, h)

    def P(self, u, v):
        if self.flip:
            u = 1 - u
        return (self.x0 + u * self.w, self.y0 + v * self.h)

    def poly(self, pts, cut=False, smooth=False, n=10):
        if smooth:
            pts = catmull(pts, n=n, closed=True)
        self.d.polygon([self.P(*p) for p in pts], fill=0 if cut else self.ink)

    def ell(self, cu, cv, ru, rv, cut=False):
        a = self.P(cu - ru, cv - rv)
        b = self.P(cu + ru, cv + rv)
        box = [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]),
               max(a[1], b[1])]
        self.d.ellipse(box, fill=0 if cut else self.ink)

    def disc(self, cu, cv, r, cut=False):
        """A round disc of radius `r` box-units (round whatever the box)."""
        c = self.P(cu, cv)
        rr = r * self.unit
        self.d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr],
                       fill=0 if cut else self.ink)

    def ring(self, cu, cv, ru, rv, t, cut=False):
        """An elliptical band `t` box-units thick."""
        self.ell(cu, cv, ru, rv, cut=cut)
        tu = t * self.unit / self.w
        tv = t * self.unit / self.h
        if ru > tu and rv > tv:
            self.ell(cu, cv, ru - tu, rv - tv, cut=not cut)

    def rect(self, u0, v0, u1, v1, cut=False):
        self.poly([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], cut=cut)

    def stroke(self, pts, w0, w1=None, cut=False, smooth=True, n=10,
               taper=None):
        """A stroke along the points whose weight runs from `w0` to `w1`
        (box-units, full width). `taper` thins both ends by that share.
        Laid as overlapping discs, which never spike on a tight curve.
        """
        if smooth and len(pts) > 2:
            pts = catmull(pts, n=n)
        pts = [self.P(*p) for p in pts]
        w1 = w0 if w1 is None else w1
        # densify so the discs overlap at the thinnest point
        dense = []
        seg = []
        tot = 0.0
        for i in range(len(pts) - 1):
            l = math.hypot(pts[i + 1][0] - pts[i][0],
                           pts[i + 1][1] - pts[i][1])
            seg.append(l)
            tot += l
        step = max(0.4, min(w0, w1) * self.unit * 0.18)
        acc = 0.0
        for i in range(len(pts) - 1):
            l = seg[i]
            k = max(1, int(math.ceil(l / step)))
            for j in range(k):
                t = j / float(k)
                dense.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t,
                              pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t,
                              (acc + l * t) / max(tot, 1e-6)))
            acc += l
        dense.append((pts[-1][0], pts[-1][1], 1.0))
        for (x, y, f) in dense:
            w = w0 + (w1 - w0) * f
            if taper:
                w *= 1 - taper * (1 - math.sin(math.pi * f) ** 0.5)
            r = max(0.5, w * self.unit * 0.5)
            self.d.ellipse([x - r, y - r, x + r, y + r],
                           fill=0 if cut else self.ink)

    def arc(self, cu, cv, ru, rv, a0, a1, w, n=40, cut=False, w1=None):
        """An arc of an ellipse, degrees measured clockwise from +u (image
        convention, v down), as a stroke."""
        pts = []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cu + math.cos(a) * ru, cv + math.sin(a) * rv))
        self.stroke(pts, w, w1, cut=cut, smooth=False)


# ---------------------------------------------------------------------------
# The glyphs
# ---------------------------------------------------------------------------
# Each is drawn in its own unit box. Tall glyphs are drawn for a box about
# 0.42 as wide as it is high; flat ones for one about 0.36 as high as wide.

def g_ankh(p):
    # the loop: an oval ring, a touch narrower at the top
    p.ring(0.5, 0.20, 0.40, 0.185, 0.13)
    # the crossbar, flaring at both ends
    p.poly([(0.02, 0.37), (0.20, 0.405), (0.80, 0.405), (0.98, 0.37),
            (0.98, 0.49), (0.80, 0.455), (0.20, 0.455), (0.02, 0.49)])
    # the shaft, flaring toward its foot
    p.poly([(0.40, 0.38), (0.60, 0.38), (0.66, 1.0), (0.34, 1.0)])


def g_djed(p):
    # four capitals stacked on a column, the top one the widest
    for i, y in enumerate((0.02, 0.13, 0.24, 0.35)):
        p.poly([(0.02, y), (0.98, y), (0.92, y + 0.075), (0.08, y + 0.075)])
    p.poly([(0.30, 0.43), (0.70, 0.43), (0.66, 0.92), (0.34, 0.92)])
    p.rect(0.18, 0.92, 0.82, 1.0)


def g_was(p):
    # the head: a beast's, looking right, with an upright ear
    p.poly([(0.40, 0.16), (0.52, 0.06), (0.62, 0.0), (0.66, 0.04),
            (0.60, 0.10), (0.98, 0.14), (0.98, 0.20), (0.56, 0.22),
            (0.48, 0.24)], smooth=False)
    # the shaft
    p.stroke([(0.46, 0.20), (0.50, 0.60), (0.50, 0.88)], 0.18, 0.15,
             smooth=True)
    # the forked foot
    p.stroke([(0.50, 0.86), (0.28, 1.0)], 0.12)
    p.stroke([(0.50, 0.86), (0.72, 1.0)], 0.12)


def g_reed(p):
    # a flowering reed leaf, its tip bending right
    p.poly([(0.46, 1.0), (0.40, 0.72), (0.38, 0.42), (0.42, 0.20),
            (0.56, 0.06), (0.80, 0.0), (0.66, 0.12), (0.58, 0.26),
            (0.58, 0.50), (0.60, 0.76), (0.62, 1.0)], smooth=True, n=8)
    # the stalk's node
    p.poly([(0.30, 0.82), (0.70, 0.82), (0.66, 0.88), (0.34, 0.88)])


def g_feather(p):
    # Ma'at's feather: a broad blade, round-shouldered, its tip curling over
    # to the right
    p.poly([(0.40, 1.0), (0.14, 0.80), (0.06, 0.50), (0.12, 0.24),
            (0.30, 0.08), (0.58, 0.0), (0.90, 0.04), (0.98, 0.14),
            (0.80, 0.12), (0.70, 0.24), (0.76, 0.52), (0.70, 0.80),
            (0.56, 1.0)], smooth=True, n=8)
    # the quill, cut in
    p.stroke([(0.48, 0.98), (0.42, 0.60), (0.42, 0.26), (0.58, 0.08)],
             0.08, 0.03, cut=True)


def g_nefer(p):
    # the heart below, the windpipe rising from it with two crossbars
    p.ell(0.5, 0.80, 0.30, 0.19)
    p.stroke([(0.5, 0.64), (0.5, 0.02)], 0.20, 0.16, smooth=False)
    p.rect(0.16, 0.14, 0.84, 0.20)
    p.rect(0.22, 0.27, 0.78, 0.32)


def g_heqa(p):
    # the crook
    p.arc(0.62, 0.17, 0.30, 0.14, 180, 360, 0.16, n=30)
    p.stroke([(0.92, 0.17), (0.92, 0.28)], 0.14)
    p.stroke([(0.32, 0.17), (0.34, 1.0)], 0.18, 0.15, smooth=False)


def g_tyet(p):
    # the knot of Isis: a loop, arms dropping either side, a long apron
    p.ring(0.5, 0.16, 0.30, 0.15, 0.14)
    p.stroke([(0.5, 0.30), (0.12, 0.40), (0.06, 0.52)], 0.14, 0.10)
    p.stroke([(0.5, 0.30), (0.88, 0.40), (0.94, 0.52)], 0.14, 0.10)
    p.poly([(0.36, 0.30), (0.64, 0.30), (0.74, 1.0), (0.26, 1.0)])
    p.rect(0.42, 0.52, 0.58, 0.94, cut=True)


def g_sceptre(p):
    # the sekhem sceptre: a papyrus-headed baton
    p.poly([(0.10, 0.0), (0.90, 0.0), (0.62, 0.20), (0.38, 0.20)])
    p.stroke([(0.5, 0.18), (0.5, 1.0)], 0.18, 0.14, smooth=False)
    p.rect(0.30, 0.30, 0.70, 0.36)


TALL = {
    "ankh": g_ankh, "djed": g_djed, "was": g_was, "reed": g_reed,
    "feather": g_feather, "nefer": g_nefer, "heqa": g_heqa, "tyet": g_tyet,
    "sekhem": g_sceptre,
}


def g_water(p):
    # a band of ripples
    pts = []
    n = 7
    for i in range(n * 2 + 1):
        u = 0.02 + 0.96 * i / (n * 2)
        pts.append((u, 0.28 if i % 2 == 0 else 0.72))
    p.stroke(pts, 0.34, smooth=False)


def g_mouth(p):
    p.poly([(0.0, 0.5), (0.22, 0.14), (0.5, 0.04), (0.78, 0.14), (1.0, 0.5),
            (0.78, 0.86), (0.5, 0.96), (0.22, 0.86)], smooth=True, n=6)


def g_loaf(p):
    p.poly([(0.04, 1.0), (0.06, 0.66), (0.18, 0.28), (0.38, 0.06),
            (0.62, 0.06), (0.82, 0.28), (0.94, 0.66), (0.96, 1.0)],
           smooth=True, n=6)


def g_basket(p):
    # a half bowl, its rim a straight line
    p.poly([(0.0, 0.0), (1.0, 0.0), (0.94, 0.40), (0.76, 0.80),
            (0.5, 0.96), (0.24, 0.80), (0.06, 0.40)], smooth=False)
    p.poly([(0.16, 0.20), (0.84, 0.20), (0.74, 0.54), (0.5, 0.70),
            (0.26, 0.54)], cut=True)


def g_viper(p):
    # the horned viper, lying along, its head at the right
    p.stroke([(0.0, 0.84), (0.20, 0.70), (0.44, 0.78), (0.66, 0.62),
              (0.86, 0.56)], 0.30, 0.44)
    p.ell(0.88, 0.50, 0.11, 0.34)
    p.stroke([(0.86, 0.22), (0.80, 0.0)], 0.14)
    p.stroke([(0.94, 0.24), (0.98, 0.02)], 0.14)


def g_cobra(p):
    # the cobra, reared at the right with its hood spread
    p.stroke([(0.0, 0.88), (0.30, 0.80), (0.56, 0.86), (0.76, 0.80)],
             0.26, 0.32)
    p.poly([(0.70, 0.86), (0.72, 0.40), (0.82, 0.06), (0.96, 0.02),
            (1.0, 0.18), (0.92, 0.30), (0.94, 0.86)], smooth=True, n=6)


def g_arm(p):
    # a forearm, palm up: the hand at the left with its thumb raised, the
    # elbow at the right
    p.poly([(0.02, 0.58), (0.04, 0.36), (0.12, 0.30), (0.14, 0.02),
            (0.22, 0.02), (0.24, 0.34), (0.40, 0.44), (0.90, 0.40),
            (1.0, 0.60), (0.92, 0.84), (0.40, 0.80), (0.10, 0.80)],
           smooth=False)


def g_hand(p):
    # a flat hand, fingers to the right, thumb along the top
    p.poly([(0.0, 0.40), (0.30, 0.24), (0.62, 0.30), (0.96, 0.36),
            (1.0, 0.56), (0.94, 0.78), (0.40, 0.88), (0.0, 0.84)],
           smooth=True, n=5)
    p.stroke([(0.34, 0.26), (0.52, 0.02), (0.64, 0.06)], 0.14, 0.10)


def g_house(p):
    # the house plan: a rectangle with its door
    p.rect(0.0, 0.0, 1.0, 1.0)
    p.rect(0.12, 0.26, 0.88, 0.74, cut=True)
    p.rect(0.40, 0.70, 0.58, 1.02, cut=True)


def g_bolt(p):
    # a door bolt
    p.rect(0.0, 0.30, 1.0, 0.70)
    for u in (0.18, 0.36, 0.64, 0.82):
        p.rect(u - 0.035, 0.0, u + 0.035, 1.0)


def g_sky(p):
    # the sky, its ends coming down
    p.poly([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.88, 1.0), (0.88, 0.38),
            (0.12, 0.38), (0.12, 1.0), (0.0, 1.0)])


FLAT = {
    "water": g_water, "mouth": g_mouth, "loaf": g_loaf, "basket": g_basket,
    "viper": g_viper, "cobra": g_cobra, "arm": g_arm, "hand": g_hand,
    "house": g_house, "bolt": g_bolt, "sky": g_sky,
}


def g_eye(p):
    """The wedjat: brow, almond eye, pupil, and the falcon's two marks."""
    # brow
    p.stroke([(0.04, 0.22), (0.30, 0.10), (0.62, 0.10), (0.96, 0.20)],
             0.075, 0.055)
    # the eye: an almond band with the pupil in it
    p.poly([(0.02, 0.40), (0.24, 0.26), (0.52, 0.24), (0.86, 0.32),
            (0.98, 0.40), (0.84, 0.46), (0.52, 0.58), (0.22, 0.54)],
           smooth=True, n=6)
    p.poly([(0.14, 0.40), (0.30, 0.33), (0.54, 0.32), (0.80, 0.38),
            (0.54, 0.50), (0.28, 0.48)], smooth=True, n=6, cut=True)
    p.disc(0.44, 0.405, 0.095)
    # the teardrop under the inner corner
    p.stroke([(0.30, 0.54), (0.26, 0.74), (0.22, 0.96)], 0.07, 0.03)
    # the spiral from the outer corner
    pts = [(0.52, 0.56), (0.62, 0.66)]
    for i in range(22):
        a = math.radians(-90 + i * 17)
        r = 0.16 * (1 - i / 30.0)
        pts.append((0.74 + math.cos(a) * r, 0.80 + math.sin(a) * r * 0.8))
    p.stroke(pts, 0.07, 0.035, smooth=True, n=4)


def g_scarab(p):
    """Khepri seen from above, head up."""
    p.ell(0.5, 0.62, 0.28, 0.30)                   # wing cases
    p.poly([(0.30, 0.32), (0.70, 0.32), (0.66, 0.20), (0.34, 0.20)],
           smooth=False)                           # thorax
    p.ell(0.5, 0.26, 0.20, 0.10)
    p.poly([(0.36, 0.16), (0.40, 0.04), (0.60, 0.04), (0.64, 0.16)])  # head
    for s in (-1, 1):
        # the head's serrations
        p.poly([(0.5 + s * 0.08, 0.04), (0.5 + s * 0.14, 0.0),
                (0.5 + s * 0.16, 0.06)])
        # six legs, drawn as bent strokes
        for (y0, dy, reach) in ((0.30, -0.06, 0.34), (0.50, 0.02, 0.37),
                                (0.72, 0.08, 0.34)):
            p.stroke([(0.5 + s * 0.24, y0), (0.5 + s * reach, y0 + dy),
                      (0.5 + s * (reach + 0.02), y0 + dy + 0.06)],
                     0.055, 0.04, smooth=False)
    p.stroke([(0.5, 0.34), (0.5, 0.92)], 0.035, cut=True, smooth=False)
    p.stroke([(0.30, 0.34), (0.70, 0.34)], 0.03, cut=True, smooth=False)


def g_owl(p):
    """The owl (m): a bird in profile, facing left, with its face turned out."""
    # body and tail
    p.poly([(0.30, 0.40), (0.50, 0.30), (0.80, 0.42), (0.98, 0.78),
            (0.88, 0.84), (0.64, 0.80), (0.40, 0.84), (0.26, 0.70)],
           smooth=True, n=8)
    # the head, turned to face out, with its ear tufts
    p.ell(0.34, 0.26, 0.20, 0.20)
    p.poly([(0.16, 0.14), (0.18, 0.0), (0.26, 0.10)])
    p.poly([(0.42, 0.10), (0.50, 0.0), (0.52, 0.14)])
    p.disc(0.27, 0.25, 0.055, cut=True)
    p.disc(0.41, 0.25, 0.055, cut=True)
    # the wing
    p.stroke([(0.46, 0.46), (0.66, 0.52), (0.86, 0.70)], 0.04, 0.02,
             cut=True)
    # legs
    p.stroke([(0.44, 0.80), (0.42, 1.0)], 0.06)
    p.stroke([(0.56, 0.80), (0.58, 1.0)], 0.06)


def g_vulture(p):
    """The vulture (3): standing, facing left, a hooked beak."""
    p.poly([(0.20, 0.36), (0.40, 0.28), (0.70, 0.36), (0.92, 0.62),
            (1.0, 0.86), (0.86, 0.84), (0.62, 0.78), (0.36, 0.76),
            (0.22, 0.60)], smooth=True, n=8)
    # neck and head
    p.stroke([(0.26, 0.40), (0.20, 0.22), (0.16, 0.10)], 0.13, 0.10)
    p.ell(0.14, 0.09, 0.09, 0.07)
    p.poly([(0.06, 0.08), (0.0, 0.14), (0.04, 0.18), (0.10, 0.12)])
    # the wing's edge, cut in
    p.stroke([(0.38, 0.42), (0.62, 0.48), (0.88, 0.72)], 0.035, 0.02,
             cut=True)
    p.stroke([(0.40, 0.74), (0.36, 1.0)], 0.06)
    p.stroke([(0.54, 0.76), (0.56, 1.0)], 0.06)


def g_chick(p):
    """The quail chick (w)."""
    p.ell(0.52, 0.52, 0.30, 0.26)
    p.ell(0.28, 0.30, 0.15, 0.14)
    p.poly([(0.14, 0.28), (0.04, 0.33), (0.14, 0.36)])
    p.poly([(0.72, 0.42), (0.98, 0.40), (0.80, 0.60)])
    p.stroke([(0.44, 0.74), (0.40, 1.0)], 0.06)
    p.stroke([(0.60, 0.74), (0.64, 1.0)], 0.06)
    p.disc(0.25, 0.28, 0.03, cut=True)


def g_akhet(p):
    """The horizon: the sun between two hills."""
    p.disc(0.5, 0.52, 0.19)
    p.poly([(0.0, 1.0), (0.04, 0.62), (0.16, 0.44), (0.30, 0.56),
            (0.36, 0.80), (0.40, 1.0)], smooth=False)
    p.poly([(0.60, 1.0), (0.64, 0.80), (0.70, 0.56), (0.84, 0.44),
            (0.96, 0.62), (1.0, 1.0)], smooth=False)


def g_sun(p):
    p.ring(0.5, 0.5, 0.42, 0.42, 0.13)
    p.disc(0.5, 0.5, 0.10)


def g_star(p):
    """The five-armed star of the Duat."""
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 0.48 if i % 2 == 0 else 0.15
        pts.append((0.5 + math.cos(a) * r, 0.52 + math.sin(a) * r))
    p.poly(pts)
    p.disc(0.5, 0.52, 0.08)


def g_shen(p):
    """The shen ring: a loop of rope over its tied bar."""
    p.ring(0.5, 0.42, 0.40, 0.38, 0.14)
    p.rect(0.06, 0.84, 0.94, 0.98)


def g_placenta(p):
    p.ring(0.5, 0.5, 0.42, 0.42, 0.11)
    for v in (0.34, 0.5, 0.66):
        p.rect(0.16, v - 0.035, 0.84, v + 0.035)


def g_flax(p):
    """Twisted flax (h): three loops down a cord."""
    for i, v in enumerate((0.18, 0.50, 0.82)):
        p.ring(0.5, v, 0.30, 0.16, 0.12)


def g_lotus(p):
    """A lotus in flower on its stalk."""
    p.poly([(0.5, 0.54), (0.30, 0.44), (0.14, 0.12), (0.34, 0.22),
            (0.5, 0.0), (0.66, 0.22), (0.86, 0.12), (0.70, 0.44)],
           smooth=False)
    p.stroke([(0.5, 0.50), (0.48, 0.76), (0.52, 1.0)], 0.10, 0.08)


SQUARE = {
    "eye": g_eye, "scarab": g_scarab, "owl": g_owl, "vulture": g_vulture,
    "chick": g_chick, "akhet": g_akhet, "sun": g_sun, "star": g_star,
    "shen": g_shen, "placenta": g_placenta, "flax": g_flax,
    "lotus": g_lotus,
}

TALL_ASPECT = 0.42     # a tall glyph's width over its height
FLAT_ASPECT = 0.36     # a flat glyph's height over its width


def draw_glyph(draw, name, x0, y0, w, h, ink=255, flip=False):
    """Draw one glyph by name into the box, keeping its own proportions and
    centring it."""
    if name in TALL:
        gw = min(w, h * TALL_ASPECT)
        gh = gw / TALL_ASPECT
        fn = TALL[name]
    elif name in FLAT:
        gh = min(h, w * FLAT_ASPECT)
        gw = gh / FLAT_ASPECT
        fn = FLAT[name]
    else:
        gw = gh = min(w, h)
        fn = SQUARE[name]
    fn(Pen(draw, x0 + (w - gw) / 2, y0 + (h - gh) / 2, gw, gh, ink, flip))


def column(draw, x0, y0, w, h, seed, ink=255, flip=False, gap=0.14):
    """Fill a column with hieroglyphs laid out in squares, as a text is: a
    square glyph alone, two tall ones side by side, or two or three flat ones
    stacked. The run is seeded, so a column reads the same every build.

    Returns the list of squares used, each as (y0, y1).
    """
    r = np.random.default_rng(seed)
    tall = sorted(TALL)
    flat = sorted(FLAT)
    square = sorted(SQUARE)
    y = y0
    q = w                          # a square's side
    pad = q * gap
    used = []
    last = None
    while y + q * 0.55 <= y0 + h:
        kind = r.choice(["square", "tall2", "flat2", "flat3", "tallflat"],
                        p=[0.36, 0.22, 0.20, 0.08, 0.14])
        if kind == last and r.random() < 0.6:
            continue
        last = kind
        side = min(q, y0 + h - y)
        if side < q * 0.55:
            break
        x, s, pp = x0 + pad, side - 2 * pad, pad
        if kind == "square":
            draw_glyph(draw, r.choice(square), x, y + pp, q - 2 * pad, s,
                       ink, flip)
        elif kind == "tall2":
            half = (q - 2 * pad) / 2
            for k in range(2):
                draw_glyph(draw, r.choice(tall), x + k * half + half * 0.08,
                           y + pp, half * 0.84, s, ink, flip)
        elif kind in ("flat2", "flat3"):
            n = 2 if kind == "flat2" else 3
            hh = s / n
            for k in range(n):
                draw_glyph(draw, r.choice(flat), x, y + pp + k * hh
                           + hh * 0.12, q - 2 * pad, hh * 0.76, ink, flip)
        else:
            half = (q - 2 * pad) / 2
            draw_glyph(draw, r.choice(tall), x, y + pp, half * 0.9, s, ink,
                       flip)
            hh = s / 2
            for k in range(2):
                draw_glyph(draw, r.choice(flat), x + half, y + pp + k * hh
                           + hh * 0.14, half, hh * 0.72, ink, flip)
        used.append((y, y + side))
        y += side
    return used


def specimen(path, size=96):
    """Every glyph, labelled, for looking at."""
    from PIL import ImageFont
    names = sorted(TALL) + sorted(FLAT) + sorted(SQUARE)
    cols = 8
    rows = (len(names) + cols - 1) // cols
    ss = 4
    cell = size * ss
    im = Image.new("L", (cols * cell, rows * cell), 0)
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x = (i % cols) * cell
        y = (i // cols) * cell
        draw_glyph(d, n, x + cell * 0.12, y + cell * 0.08, cell * 0.76,
                   cell * 0.72)
    im = im.resize((cols * size, rows * size), Image.LANCZOS)
    out = Image.new("RGB", im.size, (14, 12, 20))
    gold = Image.new("RGB", im.size, (214, 170, 84))
    out.paste(gold, (0, 0), im)
    d2 = ImageDraw.Draw(out)
    for i, n in enumerate(names):
        d2.text(((i % cols) * size + 3, (i // cols) * size + size - 12), n,
                fill=(120, 120, 140))
    out.save(path)
