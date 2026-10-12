#!/usr/bin/env python3
"""A trial: Mika drawn in code (`cel_art`) instead of cut from the owner's
sheet, in a floating boss pose, keeping every feature of the sheet
(`tools/source/mika_ref.png`): a black fennec fox with huge ears, blue eyes
and gold markings (the forehead ring and flames, the eye and cheek swirls,
the flame commas on his shoulders and the slashes on his sides and legs), a
chain necklace with a ring pendant, banded forearms and ankle, gold-tipped
claws, a gold scrolled belt, a black tabard bordered in gold chain with the
forehead symbol, gold flame tufts at his ankles, and a huge tail with a gold
flame tip and two chain bands.

Not wired into the game: it writes previews only, to `tools/_preview/`.
Everything is laid out in design units, with him 1000 tall from ear tips to
claws, and drawn at `k` final pixels a unit (the game's sprite is 208 px
tall, so about 0.21).

Usage:
    python tools/make_mika_drawn.py            # a large render and game size
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cel_art as CA
import sanctum_glyphs as GL

W, H = 960, 1040            # the figure's box, in design units
GAME_K = 208 / 1000         # the game's sprite: 208 px for his 1000 units

# His colours, from the sheet: near-black fur, gold, blue eyes.
FUR = CA.Ramp((5, 5, 9), (13, 12, 19), (25, 23, 33), (52, 52, 80),
              (110, 114, 166), (2, 2, 4))
LACQUER = CA.Ramp((1, 1, 2), (4, 4, 6), (9, 9, 12), (34, 34, 44),
                  (150, 150, 168), (0, 0, 0))
GOLD = CA.Ramp((128, 66, 0), (204, 122, 8), (250, 178, 22), (255, 214, 96),
               (255, 244, 196), (64, 30, 0))
BLUE = CA.Ramp((0, 34, 110), (0, 84, 196), (32, 146, 255), (120, 200, 255),
               (232, 246, 255), (0, 12, 40))


class Pen:
    """A `cel_art.Sheet` addressed in design units, `k` pixels a unit, with an
    optional rotation (`turn`, degrees clockwise about `pivot`) for posing a
    group of parts."""

    def __init__(self, k, ss=CA.SS):
        self.k = k
        self.sh = CA.Sheet(int(math.ceil(W * k)), int(math.ceil(H * k)),
                           origin=(0, 0), ss=ss)
        self.turn, self.pivot = 0.0, (0.0, 0.0)

    def T(self, x, y):
        if not self.turn:
            return x, y
        a = math.radians(self.turn)
        px, py = self.pivot
        dx, dy = x - px, y - py
        return (px + dx * math.cos(a) - dy * math.sin(a),
                py + dx * math.sin(a) + dy * math.cos(a))

    def P(self, pts):
        out = []
        for x, y in pts:
            x, y = self.T(x, y)
            out.append((x * self.k, y * self.k))
        return out

    def poly(self, pts, smooth=True):
        if smooth:
            pts = GL.catmull(pts, n=10, closed=True)
        return self.sh.poly(self.P(pts))

    def ellipse(self, cx, cy, rx, ry, angle=0.0):
        k = self.k
        cx, cy = self.T(cx, cy)
        return self.sh.ellipse(cx * k, cy * k, rx * k, ry * k, angle + self.turn)

    def stroke(self, pts, w0, w1=None, taper=0.0):
        k = self.k
        return self.sh.stroke(self.P(pts), w0 * k, (w0 if w1 is None else w1) * k, taper)

    def part(self, mask, ramp, band=14, rim=5, line=5, wash=0.35, deep=0.45,
             alpha=1.0):
        k = self.k
        return self.sh.part(mask, ramp, band=band * k, rim=rim * k,
                            line=line * k, wash=wash, deep=deep,
                            soft=max(0.25, 1.2 * k), alpha=alpha)

    def gold(self, mask, line=2.2):
        """A gold marking: lit, shaded and lined like metal leaf."""
        return self.part(mask, GOLD, band=4, rim=2, line=line, wash=0.5,
                         deep=0.3)


# -- paths -------------------------------------------------------------------

def bez(p0, p1, p2, p3, n=28):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def spiral(cx, cy, r0, r1, a0, a1, n=40):
    """From angle `a0` at radius `r0` to `a1` at `r1` (degrees, counter-
    clockwise on screen)."""
    out = []
    for i in range(n + 1):
        t = i / n
        a = math.radians(a0 + (a1 - a0) * t)
        r = r0 + (r1 - r0) * t
        out.append((cx + r * math.cos(a), cy - r * math.sin(a)))
    return out


def sweep(center, half, n=160):
    """The outline of a shape swept along the centre line `center` (smoothed),
    `half(t)` units either side of it at `t` from 0 to 1 along it; and the
    centre line itself, evenly resampled, with its unit normals."""
    dense = GL.catmull(center, n=24, closed=False)
    seg = [math.hypot(dense[i + 1][0] - dense[i][0], dense[i + 1][1] - dense[i][1])
           for i in range(len(dense) - 1)]
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    pts, nrm = [], []
    for i in range(n + 1):
        d = total * i / n
        j = min(int(np.searchsorted(cum, d, side="right")) - 1, len(seg) - 1)
        f = (d - cum[j]) / max(seg[j], 1e-6)
        x = dense[j][0] + (dense[j + 1][0] - dense[j][0]) * f
        y = dense[j][1] + (dense[j + 1][1] - dense[j][1]) * f
        tx, ty = dense[j + 1][0] - dense[j][0], dense[j + 1][1] - dense[j][1]
        tl = math.hypot(tx, ty) or 1
        pts.append((x, y))
        nrm.append((-ty / tl, tx / tl))
    left = [(x + nx * half(i / n), y + ny * half(i / n)) for i, ((x, y), (nx, ny)) in enumerate(zip(pts, nrm))]
    right = [(x - nx * half(i / n), y - ny * half(i / n)) for i, ((x, y), (nx, ny)) in enumerate(zip(pts, nrm))]
    return left + right[::-1], pts, nrm


def interp(stops):
    """A function of t from (t, value) stops, smoothly between them."""
    ts = [a for a, _ in stops]
    vs = [b for _, b in stops]

    def f(t):
        if t <= ts[0]:
            return vs[0]
        for i in range(len(ts) - 1):
            if t <= ts[i + 1]:
                u = (t - ts[i]) / (ts[i + 1] - ts[i])
                u = u * u * (3 - 2 * u)
                return vs[i] + (vs[i + 1] - vs[i]) * u
        return vs[-1]
    return f


def mirror(pts, cx=340):
    return [(2 * cx - x, y) for x, y in pts]


def furred(pts, depth, every, where=lambda x, y: 1.0, seed=0, lean=0.35):
    """Closed outline `pts` (smoothed) with tufts of fur along it: a spike out
    of the outline every `every` units, `depth` deep (varied), leaning along
    the outline by `lean`, wherever `where(x, y)` is above zero."""
    dense = GL.catmull(pts, n=12, closed=True)
    n = len(dense)
    area = sum(dense[i][0] * dense[(i + 1) % n][1] - dense[(i + 1) % n][0] * dense[i][1]
               for i in range(n))
    out_sign = 1 if area > 0 else -1
    rng = np.random.default_rng(seed)
    seg = [math.hypot(dense[(i + 1) % n][0] - dense[i][0],
                      dense[(i + 1) % n][1] - dense[i][1]) for i in range(n)]
    total = sum(seg)
    out, s, k = [], 0.0, 0
    jit = rng.uniform(0.6, 1.25, int(total / every) + 4)
    for i in range(n):
        x, y = dense[i]
        tx = dense[(i + 1) % n][0] - dense[i - 1][0]
        ty = dense[(i + 1) % n][1] - dense[i - 1][1]
        tl = math.hypot(tx, ty) or 1
        nx, ny = out_sign * ty / tl, -out_sign * tx / tl
        ph = (s % every) / every
        idx = int(s / every)
        w = where(x, y)
        # A tuft: rising slowly to a sharp tip, then dropping back.
        h = (ph ** 1.6 if ph < 0.85 else (1 - ph) / 0.15 * 0.85 ** 1.6)
        d = depth * jit[idx] * h * w
        out.append((x + nx * d + tx / tl * d * lean, y + ny * d + ty / tl * d * lean))
        s += seg[i]
    return out


# -- marks -------------------------------------------------------------------

def comma(pen, head, ctrl1, ctrl2, tail, w):
    """The general marking: a flame-like comma, thick at its head and drawn
    out to a fine tail."""
    return pen.gold(pen.stroke(bez(head, ctrl1, ctrl2, tail), w, w * 0.08))


def ring_mark(pen, cx, cy, r, w):
    pts = [(cx + r * math.cos(a), cy + r * math.sin(a))
           for a in np.linspace(0, 2 * math.pi, 48)]
    return pen.stroke(pts, w)


def forehead_symbol(pen, cx, cy, s):
    """The forehead (and tabard) mark: a ring with a flame rising from its top
    and curling one way, and one falling from its bottom curling the other."""
    m = ring_mark(pen, cx, cy, 9 * s, 4.2 * s)
    up = bez((cx, cy - 9 * s), (cx - 2 * s, cy - 20 * s), (cx + 9 * s, cy - 26 * s),
             (cx + 4 * s, cy - 36 * s))
    down = bez((cx, cy + 9 * s), (cx + 2 * s, cy + 20 * s), (cx - 9 * s, cy + 26 * s),
               (cx - 4 * s, cy + 36 * s))
    m = np.maximum(m, pen.stroke(up, 4.6 * s, 0.6 * s))
    m = np.maximum(m, pen.stroke(down, 4.6 * s, 0.6 * s))
    return pen.gold(m, line=1.6)


def chain(pen, path, link, w, flat_every=2):
    """Gold chain along `path`: oval links `link` long, every other one seen
    edge on as a short bar."""
    dense = GL.catmull(path, n=12, closed=False) if len(path) > 2 else path
    seg = [math.hypot(dense[i + 1][0] - dense[i][0], dense[i + 1][1] - dense[i][1])
           for i in range(len(dense) - 1)]
    total = sum(seg)
    m = None
    k, s = 0, link * 0.5
    while s < total:
        acc, i = 0.0, 0
        while i < len(seg) - 1 and acc + seg[i] < s:
            acc += seg[i]
            i += 1
        f = (s - acc) / max(seg[i], 1e-6)
        x = dense[i][0] + (dense[i + 1][0] - dense[i][0]) * f
        y = dense[i][1] + (dense[i + 1][1] - dense[i][1]) * f
        ang = math.degrees(math.atan2(dense[i + 1][1] - dense[i][1], dense[i + 1][0] - dense[i][0]))
        if k % flat_every == 0:
            pts = []
            for a in np.linspace(0, 2 * math.pi, 28):
                ex, ey = link * 0.55 * math.cos(a), link * 0.3 * math.sin(a)
                c, sn = math.cos(math.radians(ang)), math.sin(math.radians(ang))
                pts.append((x + ex * c - ey * sn, y + ex * sn + ey * c))
            piece = pen.stroke(pts, w)
        else:
            c, sn = math.cos(math.radians(ang)), math.sin(math.radians(ang))
            piece = pen.stroke([(x - c * link * 0.5, y - sn * link * 0.5),
                                (x + c * link * 0.5, y + sn * link * 0.5)], w * 1.3)
        m = piece if m is None else np.maximum(m, piece)
        s += link * 0.85
        k += 1
    return pen.gold(m, line=1.4)


def band(pen, a0, a1, b0, b1, clip, width_pad=0):
    """A lacquered band: black glossy between edge `a0`-`a1` and edge
    `b0`-`b1`, gold rules along both edges and a chain of gold links down its
    middle, cut to `clip`."""
    mask = pen.poly([a0, a1, b1, b0], smooth=False) * clip
    pen.part(mask, LACQUER, band=6, rim=3, line=3, wash=0.15)
    # A glossy streak a third of the way across.
    g0 = (a0[0] * 0.7 + b0[0] * 0.3, a0[1] * 0.7 + b0[1] * 0.3)
    g1 = (a1[0] * 0.7 + b1[0] * 0.3, a1[1] * 0.7 + b1[1] * 0.3)
    pen.sh.over(LACQUER.glint, pen.stroke([g0, g1], 3, 3, taper=0.8) * clip * 0.35)
    for p, q in ((a0, a1), (b0, b1)):
        pen.gold(pen.stroke([p, q], 4.4) * clip, line=1.0)
    m0 = ((a0[0] + b0[0]) / 2, (a0[1] + b0[1]) / 2)
    m1 = ((a1[0] + b1[0]) / 2, (a1[1] + b1[1]) / 2)
    wide = math.hypot(b0[0] - a0[0], b0[1] - a0[1])
    m = None
    n = max(3, int(math.hypot(m1[0] - m0[0], m1[1] - m0[1]) / (wide * 0.75)))
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        c = (m0[0] + (m1[0] - m0[0]) * (t0 + t1) / 2, m0[1] + (m1[1] - m0[1]) * (t0 + t1) / 2)
        L = math.hypot(m1[0] - m0[0], m1[1] - m0[1]) / n
        ang = math.atan2(m1[1] - m0[1], m1[0] - m0[0])
        pts = []
        for a in np.linspace(0, 2 * math.pi, 28):
            ex, ey = L * 0.5 * math.cos(a), wide * 0.18 * math.sin(a)
            pts.append((c[0] + ex * math.cos(ang) - ey * math.sin(ang),
                        c[1] + ex * math.sin(ang) + ey * math.cos(ang)))
        piece = pen.stroke(pts, 2.8)
        m = piece if m is None else np.maximum(m, piece)
    pen.gold(m * clip, line=0.8)


def claw(pen, base, tip, w):
    """A long black claw with a gold tip."""
    mid = ((base[0] * 0.4 + tip[0] * 0.6), (base[1] * 0.4 + tip[1] * 0.6))
    m = pen.stroke([base, mid, tip], w, w * 0.12)
    pen.part(m, LACQUER, band=2, rim=1.5, line=1.5, wash=0.5)
    pen.gold(pen.stroke([mid, tip], w * 0.55, w * 0.1), line=0.8)


# -- the figure -------------------------------------------------------------------

# The tail's centre line, from its root behind his right hip round to its tip,
# and its half-width along it.
TAIL = [(430, 640), (512, 716), (630, 762), (752, 718), (818, 604), (826, 476),
        (790, 350), (730, 244), (684, 140)]
TAIL_HALF = interp([(0, 32), (0.12, 74), (0.32, 108), (0.55, 104), (0.75, 88),
                    (0.9, 56), (1.0, 0)])
FLAME_T = 0.74              # where the tail's gold tip begins
BAND_T = ((0.37, 0.43), (0.60, 0.66))
HEAD_TILT = -5.0            # degrees, about his neck
HEAD_NOD = 1.6              # degrees either way it sways in the idle
TAIL_SWAY = 4.0             # degrees the tail's tip swings either way
NECK = (340, 280)


def limb(pen, center, half, ramp=FUR, tufts=0.0, seed=0, band=16):
    """A limb swept along `center`; furred if `tufts` (their depth)."""
    out, _, _ = sweep(center, half)
    if tufts:
        out = furred(out, tufts, 16, seed=seed)
    m = pen.poly(out, smooth=False)
    pen.part(m, ramp, band=band, rim=5, line=5)
    return m


def hand(pen, palm, fingers, thumb):
    """A paw: a palm and long fingers, each ending in a gold-tipped claw."""
    pen.part(pen.ellipse(palm[0], palm[1], 17, 19), FUR, band=8, rim=4, line=4)
    for base, mid, tip in fingers + [thumb]:
        m = pen.stroke([base, mid, tip], 11, 8)
        pen.part(m, FUR, band=5, rim=3, line=4)
        dx, dy = tip[0] - mid[0], tip[1] - mid[1]
        dl = math.hypot(dx, dy) or 1
        claw(pen, tip, (tip[0] + dx / dl * 28, tip[1] + dy / dl * 28), 6.5)


def swayed(t_ph):
    """The tail's centre line swung about its root, more toward its tip, by
    up to `TAIL_SWAY` degrees as `t_ph` goes round 0 to 1."""
    a = math.radians(TAIL_SWAY * math.sin(2 * math.pi * t_ph))
    rx, ry = TAIL[0]
    out = []
    for i, (x, y) in enumerate(TAIL):
        f = (i / (len(TAIL) - 1)) ** 1.3
        c, s_ = math.cos(a * f), math.sin(a * f)
        out.append((rx + (x - rx) * c - (y - ry) * s_, ry + (x - rx) * s_ + (y - ry) * c))
    return out


def draw(k, ss=CA.SS, phase=0.0, blink=0.0):
    """Mika at `k` pixels a unit. `phase` (0 to 1) runs his idle: the tail's
    sway and the head's nod; `blink` (0 to 1) closes his eyes."""
    pen = Pen(k, ss)
    X, Y = pen.sh.X / k, pen.sh.Y / k

    # -- the tail, behind everything --------------------------------------------
    outline, cpts, cnrm = sweep(swayed(phase), TAIL_HALF)
    tail = pen.poly(furred(outline, 16, 30, seed=3,
                           where=lambda x, y: 1.0 if x > 470 else 0.0), smooth=False)
    pen.part(tail, FUR, band=26, rim=6, line=6)
    n = len(cpts) - 1

    def at(t):
        i = min(n, int(round(t * n)))
        j = min(n, i + 1)
        tx, ty = cpts[j][0] - cpts[i - 1][0], cpts[j][1] - cpts[i - 1][1]
        tl = math.hypot(tx, ty) or 1
        return cpts[i], cnrm[i], (tx / tl, ty / tl), TAIL_HALF(t)

    (cx, cy), (nx, ny), (tx, ty), hw = at(FLAME_T)
    # Across the tail (u) and along it toward the tip (v) from where the gold
    # begins: black fur rises into the gold in pointed tongues...
    u = (X - cx) * nx + (Y - cy) * ny
    v = (X - cx) * tx + (Y - cy) * ty
    rise = 30 * np.abs(np.sin(np.pi * u / 34.0)) ** 2.5
    tip = tail * (v > rise)
    # ...and the gold hangs down into the black in curling flames.
    tongues = None
    for i in range(5):
        f = (i + 0.5) / 5 * 2 - 1
        bx, by = cx + nx * hw * f * 0.8, cy + ny * hw * f * 0.8
        L = 58 + 26 * (1 - abs(f))
        curl = 1 if f > 0 else -1
        ex, ey = bx - tx * L, by - ty * L
        path = bez((bx + tx * 6, by + ty * 6), (bx - tx * L * 0.45 - nx * curl * 10, by - ty * L * 0.45 - ny * curl * 10),
                   (ex + nx * curl * 22, ey + ny * curl * 22),
                   (ex + nx * curl * 16 + tx * 14, ey + ny * curl * 16 + ty * 14))
        piece = pen.stroke(path, 13, 1.2)
        tongues = piece if tongues is None else np.maximum(tongues, piece)
    tip = np.maximum(tip, tongues * tail)
    pen.part(tip, GOLD, band=16, rim=5, line=3, wash=0.55)
    for t0, t1 in BAND_T:
        (c0, n0, _, h0), (c1, n1, _, h1) = at(t0), at(t1)
        a0 = (c0[0] + n0[0] * (h0 + 40), c0[1] + n0[1] * (h0 + 40))
        a1 = (c0[0] - n0[0] * (h0 + 40), c0[1] - n0[1] * (h0 + 40))
        b0 = (c1[0] + n1[0] * (h1 + 40), c1[1] + n1[1] * (h1 + 40))
        b1 = (c1[0] - n1[0] * (h1 + 40), c1[1] - n1[1] * (h1 + 40))
        band(pen, a0, a1, b0, b1, tail)

    # -- the legs: his right hanging, his left bent up at the knee ---------------
    leg_l = [(330, 578), (322, 650), (308, 726), (296, 796), (294, 862), (270, 866),
             (266, 812), (260, 760), (242, 720), (232, 660), (244, 600), (276, 556)]
    leg_r = [(352, 578), (368, 640), (394, 698), (406, 758), (404, 822), (430, 826),
             (444, 768), (466, 712), (468, 652), (448, 596), (404, 556)]
    feet = ((282, 858, -1, leg_l, 7), (417, 818, 1, leg_r, 8))
    for x0, y0, side, pts, sd in feet:
        m = pen.poly(furred(pts, 12, 20, seed=sd,
                            where=lambda x, y, side=side: 1.0 if (x - 340) * side > 60 and y < 790 else 0.15),
                     smooth=False)
        pen.part(m, FUR, band=20, rim=6, line=5)
    for x0, y0, side, _, _ in feet:
        dy = y0 - 858
        foot = [(x0 - 16, 858), (x0 + 16, 858), (x0 + 24, 904), (x0 + 22, 946),
                (x0 + 8, 966), (x0 - 8, 966), (x0 - 22, 946), (x0 - 24, 904)]
        pen.part(pen.poly([(x, y + dy) for x, y in foot]), FUR, band=12, rim=5, line=5)
        for i, dx in enumerate((-13, -4.5, 4.5, 13)):
            claw(pen, (x0 + dx, 958 + dy), (x0 + dx * 1.25, 996 + dy + (5 if i in (1, 2) else 0)), 6)
        flames = None
        for i in range(6):
            bx = x0 + (i - 2.5) * 9 + side * 6
            lean = side * (i - 2.5) * 2.5
            fl = bez((bx, 896 + dy), (bx - 4, 878 + dy), (bx + lean + 6, 866 + dy),
                     (bx + lean * 1.6, 838 + dy - (i % 2) * 12))
            piece = pen.stroke(fl, 10, 0.8)
            flames = piece if flames is None else np.maximum(flames, piece)
        pen.gold(flames, line=1.4)
    band(pen, (395, 772), (440, 766), (396, 796), (442, 790), 1.0)
    for (a, b, c, d, w) in (((236, 628), (250, 620), (266, 624), (276, 634), 9),
                            ((240, 690), (254, 682), (270, 686), (280, 696), 8),
                            ((256, 752), (268, 745), (282, 749), (290, 758), 7),
                            ((264, 810), (274, 804), (286, 807), (292, 815), 6),
                            ((466, 628), (452, 620), (436, 624), (426, 634), 9),
                            ((464, 690), (450, 682), (434, 686), (424, 696), 8),
                            ((444, 750), (432, 744), (418, 748), (412, 756), 7)):
        comma(pen, a, b, c, d, w)

    # -- the torso, with his chest ruff ---------------------------------------------
    torso_pts = [(310, 262), (262, 282), (224, 306), (214, 338), (232, 374), (252, 412),
                 (270, 452), (286, 500), (280, 548), (300, 584), (340, 596), (380, 584),
                 (400, 548), (394, 500), (410, 452), (428, 412), (448, 374), (466, 338),
                 (456, 306), (418, 282), (370, 262)]
    torso = pen.poly(furred(torso_pts, 8, 18, seed=9,
                            where=lambda x, y: 1.0 if y < 330 or 400 < y < 470 else 0.0), smooth=False)
    pen.part(torso, FUR, band=22, rim=6, line=6)
    ruff = [(292, 262), (298, 320), (316, 360), (340, 384), (364, 360), (382, 320),
            (388, 262), (340, 280)]
    pen.part(pen.poly(furred(ruff, 16, 14, seed=13)), FUR, band=14, rim=5, line=4, wash=0.5)
    for (a, b, c, d, w) in (((258, 418), (274, 408), (290, 412), (300, 424), 9),
                            ((272, 456), (286, 448), (298, 452), (306, 462), 8),
                            ((422, 418), (406, 408), (390, 412), (380, 424), 9),
                            ((408, 456), (394, 448), (382, 452), (374, 462), 8),
                            ((284, 494), (294, 488), (304, 492), (310, 500), 7),
                            ((396, 494), (386, 488), (376, 492), (370, 500), 7)):
        comma(pen, a, b, c, d, w)
    comma(pen, (238, 312), (226, 292), (242, 276), (262, 290), 12)
    comma(pen, (442, 312), (454, 292), (438, 276), (418, 290), 12)

    # -- the belt and tabard: two gold threads woven in loops down its edges ------
    tab = [(280, 566), (400, 566), (402, 640), (394, 740), (374, 830), (352, 884), (340, 904),
           (328, 884), (306, 830), (286, 740), (278, 640)]
    pen.part(pen.poly(tab), LACQUER, band=12, rim=4, line=5, wash=0.35)
    weave = None
    for side in (-1, 1):
        rail = [(340 + side * 48, 584), (340 + side * 47, 650), (340 + side * 41, 740),
                (340 + side * 25, 830), (340 + side * 5, 886)]
        _, pts, nrm = sweep(rail, lambda t: 0, n=200)
        dist = np.concatenate([[0], np.cumsum([math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
                                                for i in range(len(pts) - 1)])])
        for ph in (0, math.pi):
            thread = [(x + nx * 6 * math.sin(d / 26 * 2 * math.pi + ph), y + ny * 6 * math.sin(d / 26 * 2 * math.pi + ph))
                      for (x, y), (nx, ny), d in zip(pts, nrm, dist)]
            piece = pen.stroke(thread, 2.8)
            weave = piece if weave is None else np.maximum(weave, piece)
    pen.gold(weave, line=1.0)
    forehead_symbol(pen, 340, 800, 2.0)
    belt = pen.poly([(270, 546), (410, 546), (412, 572), (340, 578), (268, 572)])
    pen.part(belt, LACQUER, band=4, rim=3, line=4)
    pen.gold(pen.stroke([(270, 549), (340, 554), (410, 549)], 3), line=1.0)
    pen.gold(pen.stroke([(270, 569), (340, 575), (410, 569)], 3), line=1.0)
    scroll = None
    for i in range(7):
        sp = spiral(284 + i * 19, 561, 1.5, 6.5, 90, 90 + 300 * (1 if i % 2 else -1))
        piece = pen.stroke(sp, 2)
        scroll = piece if scroll is None else np.maximum(scroll, piece)
    pen.gold(scroll, line=0.6)

    # -- the arms: his right raised beside his head, his left held out --------------
    upper = interp([(0, 24), (1, 19)])
    fore = interp([(0, 20), (1, 15)])
    limb(pen, [(226, 324), (204, 370), (178, 414)], upper, tufts=6, seed=11)
    limb(pen, [(182, 418), (146, 372), (112, 318)], fore, tufts=5, seed=12)
    band(pen, (106, 330), (136, 312), (124, 360), (154, 342), 1.0)
    hand(pen, (106, 292),
         [((92, 280), (88, 262), (86, 248)), ((103, 276), (104, 256), (105, 240)),
          ((114, 280), (119, 262), (123, 249)), ((121, 293), (130, 279), (137, 268))],
         ((90, 302), (78, 292), (70, 280)))
    pen.gold(pen.stroke(spiral(208, 366, 3, 12, 100, -200), 4, 1.2), line=1.0)

    limb(pen, [(454, 326), (470, 376), (478, 420)], upper, tufts=6, seed=13)
    limb(pen, [(476, 424), (510, 442), (546, 440)], fore, tufts=5, seed=14)
    band(pen, (504, 424), (510, 458), (528, 424), (532, 458), 1.0)
    hand(pen, (560, 436),
         [((572, 424), (584, 412), (594, 402)), ((578, 433), (592, 427), (604, 422)),
          ((578, 446), (593, 446), (606, 447)), ((572, 456), (584, 464), (594, 472))],
         ((556, 422), (560, 408), (566, 398)))
    pen.gold(pen.stroke(spiral(470, 378, 3, 12, 80, 380), 4, 1.2), line=1.0)

    # -- the neck: necklace ------------------------------------------------------
    chain(pen, [(292, 270), (306, 296), (330, 312)], 11, 2.0, flat_every=2)
    chain(pen, [(388, 270), (374, 296), (350, 312)], 11, 2.0, flat_every=2)
    pend = ring_mark(pen, 340, 316, 9, 4)
    pend = np.maximum(pend, pen.stroke([(318, 316), (331, 316)], 3, 1.5))
    pend = np.maximum(pend, pen.stroke([(349, 316), (362, 316)], 1.5, 3))
    pen.gold(pend, line=1.2)

    # -- the head, tilted a little, with its ears -----------------------------------
    pen.turn, pen.pivot = HEAD_TILT + HEAD_NOD * math.sin(2 * math.pi * (phase + 0.25)), NECK
    ear_l = [(300, 150), (262, 105), (238, 60), (232, 12), (214, 40), (186, 66),
             (166, 84), (180, 120), (214, 158), (246, 186), (272, 190)]
    for pts, sd in ((ear_l, 5), (mirror(ear_l), 6)):
        side = -1 if pts is ear_l else 1
        m = pen.poly(furred(pts, 14, 18, seed=sd,
                            where=lambda x, y, side=side: 1.0 if (x - 340) * side > 80 else 0.25),
                     smooth=False)
        pen.part(m, FUR, band=18, rim=6, line=5)
        inner = [(300, 156), (266, 108), (242, 62), (236, 30), (226, 70), (214, 112), (240, 150)]
        if side > 0:
            inner = mirror(inner)
        pen.part(pen.poly(furred(inner, 9, 12, seed=sd + 10)), FUR, band=10, rim=3, line=3, wash=0.2)
        edge = [(234, 14), (246, 44), (262, 80), (276, 104)]
        curl = spiral(268, 116, 4, 13, 200, -40)
        if side > 0:
            edge, curl = mirror(edge), mirror(curl)
        pen.gold(pen.stroke(edge, 9, 1.5), line=1.4)
        pen.gold(pen.stroke(curl, 1.2, 4.5), line=1.2)

    skull = [(340, 136), (378, 140), (408, 160), (424, 192), (432, 226), (420, 248),
             (392, 258), (364, 262), (340, 272), (316, 262), (288, 258), (260, 248),
             (248, 226), (256, 192), (272, 160), (302, 140)]
    head = pen.poly(furred(skull, 14, 14, seed=14,
                           where=lambda x, y: 1.0 if abs(x - 340) > 62 and y > 196 else 0.0), smooth=False)
    pen.part(head, FUR, band=16, rim=6, line=6, wash=0.45)
    muzzle = [(320, 232), (360, 232), (370, 250), (356, 266), (340, 272), (324, 266), (310, 250)]
    pen.part(pen.poly(muzzle), FUR, band=6, rim=4, line=0, wash=0.55)
    pen.part(pen.poly([(330, 244), (350, 244), (346, 252), (340, 256), (334, 252)]), LACQUER,
             band=2, rim=1.5, line=2)
    pen.sh.over(FUR.line, pen.stroke([(328, 262), (334, 266), (340, 264), (346, 266), (352, 262)], 1.6) * 0.85)

    for side in (-1, 1):
        ex = 340 + side * 36
        glow = pen.sh.soften(pen.ellipse(ex, 214, 18, 11 * (1 - blink) + 2, angle=-side * 16), 9 * k)
        pen.sh.add((10, 60, 150), glow * 0.55)
        ry = 10 * (1 - blink)
        if ry > 2:
            eye = pen.ellipse(ex, 214 + (10 - ry) * 0.5, 17, ry, angle=-side * 16)
            pen.part(eye, BLUE, band=5, rim=2, line=2.5, wash=0.6)
            pen.sh.over(BLUE.deep, pen.ellipse(ex + side * 1, 214 + (10 - ry) * 0.5, 3.4, ry * 0.9,
                                               angle=-side * 16) * 0.95)
            pen.sh.over(BLUE.glint, pen.ellipse(ex - 5, 210 + (10 - ry) * 0.6, 3.2, min(2.6, ry * 0.3)) * 0.95)
        else:
            # Shut: the lid's line, curved down like a smile.
            shut = bez((ex - 17, 212 + side * 3), (ex - 6, 222), (ex + 6, 222), (ex + 17, 212 - side * 3))
            pen.sh.over(FUR.line, pen.stroke(shut, 3, 2) * 0.95)
        liner = bez((340 + side * 18, 208), (340 + side * 26, 197), (340 + side * 46, 195),
                    (340 + side * 58, 203))
        pen.gold(pen.stroke(liner, 2, 4.5), line=1.0)
        pen.gold(pen.stroke(spiral(340 + side * 60, 195, 2, 8, 270, 270 + side * 320), 4, 1.2), line=1.0)
        pen.gold(pen.stroke(spiral(340 + side * 52, 238, 3, 10, 90, 90 - side * 330), 1.5, 4.5), line=1.0)
        under = bez((340 + side * 22, 226), (340 + side * 30, 234), (340 + side * 42, 234),
                    (340 + side * 46, 228))
        pen.gold(pen.stroke(under, 3.5, 1.0), line=1.0)
    forehead_symbol(pen, 340, 176, 1.0)
    pen.turn = 0.0

    pen.sh.outline(w=max(0.8, 5 * k), col=(4, 3, 8), alpha=0.95)
    return pen.sh.finish()


# The idle loop, as the game's sprite runs it: twelve frames, each held for
# seven game frames; the blink and the float as `make_mika.py` has them.
FRAMES = 12
BLINK = {8: 0.55, 9: 1.0, 10: 0.5}
BOB = 3.2                   # pixels at the game's size


def frames(k, ss=CA.SS):
    """The idle loop at `k` pixels a unit: the tail swaying, the head nodding,
    the blink, and the whole figure floating up and down."""
    out = []
    for i in range(FRAMES):
        f = i / FRAMES
        img = draw(k, ss, phase=f, blink=BLINK.get(i, 0.0))
        dy = BOB * (k / GAME_K) * math.sin(2 * math.pi * f)
        out.append(img.transform(img.size, Image.AFFINE, (1, 0, 0, 0, 1, -dy), Image.BILINEAR))
    return out


def gif(imgs, path, scale=1, ground=(24, 20, 34)):
    """An animated preview over a flat ground, 120 ms a frame."""
    pics = []
    for im in imgs:
        g = Image.new("RGBA", im.size, ground + (255,))
        g.alpha_composite(im)
        if scale != 1:
            g = g.resize((g.width * scale, g.height * scale), Image.NEAREST)
        pics.append(g.convert("RGB"))
    pics[0].save(path, save_all=True, append_images=pics[1:], duration=120, loop=0)


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_preview")
    os.makedirs(out, exist_ok=True)
    k = float(sys.argv[1]) if len(sys.argv) > 1 else 0.6
    big = draw(k, ss=3)
    ground = Image.new("RGBA", big.size, (60, 46, 70, 255))
    ground.alpha_composite(big)
    ground.save(os.path.join(out, "mika_drawn.png"))
    if "--still" in sys.argv:
        print("wrote", os.path.join(out, "mika_drawn.png"))
        return
    game = frames(GAME_K)
    gif(game, os.path.join(out, "mika_drawn_idle_game_x2.gif"), scale=2)
    gif(frames(0.45, ss=3), os.path.join(out, "mika_drawn_idle.gif"))
    print("wrote the still, the idle at game size (x2) and the idle large")


if __name__ == "__main__":
    main()
