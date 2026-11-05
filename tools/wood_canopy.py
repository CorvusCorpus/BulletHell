#!/usr/bin/env python3
"""The wood's canopy, and the treeline at its far end (`tools/make_wood.py`
writes them out).

The canopy is the ceiling the wood closes into overhead: clumps of twig
tangle, drooping twigs, hanging moss, ivy and dead leaves still clinging,
drawn on a sheet of their own (`canopy_sheet`) and set as crossed cards in
tiles that repeat down the wood (`tile`). A tile is laid out against the
path rather than the world: its x is the distance from the path's middle,
and the shader moves it onto the path as the path winds (`u_follow` in
`sh_wood.vsh`). It rises into a vault over the path, where the clumps thin
to a gap that boughs arch across. The light it lets through onto everything
under it is a tiling mask made from the same pictures (`canopy_light`).

A card's alpha is more than its outline. Inside, it climbs with the depth
from the edge (to 1 at `ERODE` pixels), so raising the cut-off in the
shader eats a clump from its twig tips inward: that is how the canopy thins
and opens into the mouth of the wood ahead (`u_mouth` in `sh_wood.fsh`).

The far treeline (`treeline`) is a silhouette of the wood beyond the end of
the path, drawn with the sky, into which the wood fades as it nears the far
end.
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import wood_mesh as M
import wood_tex as TX
import wood_trees as WT

# ---------------------------------------------------------------------------
# The sheet
# ---------------------------------------------------------------------------

SHEET_W, SHEET_H = 2048, 1024
CELL = 512
SS = 2                      # drawn at twice the size, then halved
ERODE = 9.0                 # how deep (final pixels) a card's alpha reaches 1

# Where each picture is on the sheet (column, row).
CANOPY_CELLS = {
    "lace0": (0, 0), "lace1": (1, 0), "droop": (2, 0), "moss": (3, 0),
    "ivy": (0, 1), "leaves": (1, 1), "bramble0": (2, 1), "bramble1": (3, 1),
}


def canopy_rect(name, inset=0.02):
    """A picture's texture rectangle (u0, v0, u1, v1), inset by `inset` of
    a cell so mipmaps don't bleed in from its neighbours."""
    c, r = CANOPY_CELLS[name]
    cu, cv = CELL / SHEET_W, CELL / SHEET_H
    return (c * cu + inset * cu, r * cv + inset * cv,
            (c + 1) * cu - inset * cu, (r + 1) * cv - inset * cv)


# Albedos (display values). Bark greys toward lichen on the old limbs; twigs
# are darker; the moss that hangs is pale.
BARK = np.array([78, 71, 63], float)
TWIG = np.array([58, 52, 47], float)
LICHEN = np.array([116, 124, 102], float)
BEARD = np.array([128, 138, 114], float)
IVY = [(34, 60, 38), (44, 72, 44), (30, 52, 36), (52, 78, 48)]
DEAD = [(96, 64, 38), (118, 82, 48), (84, 56, 36), (132, 96, 58)]
CANE = np.array([74, 50, 50], float)
BRAMBLE_LEAF = [(46, 58, 40), (58, 46, 52), (40, 52, 38), (66, 60, 44)]


class Canvas:
    """A picture drawn as a signed distance (`d`, supersampled pixels,
    negative inside) with the colour of the nearest part, which is bled out
    over the empty parts at the end so a filtered edge never darkens."""

    def __init__(self, w=CELL * SS, h=CELL * SS):
        self.w, self.h = w, h
        self.d = np.full((h, w), 1e6, np.float32)
        self.col = np.zeros((h, w, 3), np.float32)

    def capsule(self, a, b, ra, rb, col, shade=0.30):
        """A tapered segment from `a` to `b`, lit along its upper side."""
        ax, ay = float(a[0]), float(a[1])
        bx, by = float(b[0]), float(b[1])
        r = max(ra, rb)
        x0 = int(max(0, math.floor(min(ax, bx) - r - 3)))
        x1 = int(min(self.w, math.ceil(max(ax, bx) + r + 3)))
        y0 = int(max(0, math.floor(min(ay, by) - r - 3)))
        y1 = int(min(self.h, math.ceil(max(ay, by) + r + 3)))
        if x0 >= x1 or y0 >= y1:
            return
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        vx, vy = bx - ax, by - ay
        l2 = vx * vx + vy * vy + 1e-9
        t = np.clip(((X - ax) * vx + (Y - ay) * vy) / l2, 0.0, 1.0)
        qx, qy = ax + t * vx, ay + t * vy
        rr = ra + (rb - ra) * t
        sd = np.hypot(X - qx, Y - qy) - rr
        # Across the segment, +1 on its upper side (toward the top of the
        # picture), for a little roundness.
        ln = math.sqrt(l2)
        nx, ny = -vy / ln, vx / ln
        if ny > 0:
            nx, ny = -nx, -ny
        side = ((X - qx) * nx + (Y - qy) * ny) / np.maximum(rr, 0.75)
        sub = self.d[y0:y1, x0:x1]
        upd = sd < sub
        if not upd.any():
            return
        sub[upd] = sd[upd]
        k = 1.0 + shade * np.clip(side, -1.0, 1.0)
        c = np.asarray(col, float)[None, None, :] * k[..., None]
        self.col[y0:y1, x0:x1][upd] = c[upd]

    def polyline(self, pts, rads, col, shade=0.30):
        for i in range(len(pts) - 1):
            self.capsule(pts[i], pts[i + 1], rads[i], rads[i + 1], col, shade)

    def shapes(self, layer):
        """Union an RGBA layer (drawn at the canvas's size): its opaque part
        joins the picture, in its own colours."""
        arr = np.asarray(layer).astype(np.float32)
        m = arr[..., 3] > 127
        if not m.any():
            return
        inside = ndimage.distance_transform_edt(m)
        outside = ndimage.distance_transform_edt(~m)
        sd = np.where(m, 0.5 - inside, outside - 0.5).astype(np.float32)
        upd = sd < self.d
        self.d[upd] = sd[upd]
        self.col[upd] = arr[..., :3][upd]

    def finish(self, erode=ERODE):
        d = self.d
        a = np.where(d > 0, 0.5 - 0.5 * np.clip(d / SS, 0.0, 1.0),
                     0.5 + 0.5 * np.clip(-d / (erode * SS), 0.0, 1.0))
        known = d < 1.5 * SS
        if known.any():
            idx = ndimage.distance_transform_edt(~known, return_distances=False,
                                                 return_indices=True)
            col = self.col[idx[0], idx[1]]
        else:
            col = self.col
        rgba = np.dstack([col, a * 255.0])
        img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
        return img.resize((self.w // SS, self.h // SS), Image.BOX)


def _heading(pts, i):
    j = min(i + 1, len(pts) - 1)
    k = max(j - 1, 0)
    d = pts[j] - pts[k]
    return math.atan2(d[1], d[0])


def grow(cv, rng, p, ang, length, r, level, P, col_of):
    """A branch walked from `p` (supersampled pixels) at angle `ang`, which
    forks into smaller ones (`P`: its walk and its children per level).
    `col_of(level, t)` colours it."""
    step = float(np.clip(length / 9.0, 3.0 * SS, 16.0 * SS))
    n = max(2, int(math.ceil(length / step)))
    pts = [np.asarray(p, float)]
    a = ang
    curl = rng.normal(0.0, P["curl"])
    for i in range(n):
        a += rng.normal(0.0, P["gnarl"]) + curl
        if rng.random() < P["kink"]:
            a += rng.choice([-1.0, 1.0]) * rng.uniform(0.3, 0.6)
        if P["droop"]:
            # Bend toward hanging straight down (+y in the picture).
            down = math.pi / 2
            da = math.atan2(math.sin(down - a), math.cos(down - a))
            a += da * P["droop"] * (i + 1) / n
        pts.append(pts[-1] + step * np.array([math.cos(a), math.sin(a)]))
    t = np.linspace(0.0, 1.0, n + 1)
    rads = np.maximum(r * (1.0 - (1.0 - P["tip"]) * t ** 0.85), 0.7 * SS)
    for i in range(n):
        cv.capsule(pts[i], pts[i + 1], rads[i], rads[i + 1],
                   col_of(level, i / n))
    if level + 1 >= P["levels"]:
        return pts, rads
    lo, hi = P["kids"][min(level, len(P["kids"]) - 1)]
    for _ in range(int(rng.integers(lo, hi + 1))):
        tt = rng.uniform(0.18, 0.95)
        i = int(np.clip(round(tt * n), 1, n - 1))
        side = rng.choice([-1.0, 1.0])
        ka = _heading(pts, i) + side * rng.uniform(*P["fork"])
        kl = length * rng.uniform(*P["kid_len"]) * (1.0 - 0.3 * tt)
        kr = rads[i] * rng.uniform(0.55, 0.8)
        if kl < 6 * SS:
            continue
        grow(cv, rng, pts[i], ka, kl, kr, level + 1, P, col_of)
    return pts, rads


def _bark_col(rng, lichen_k=0.35):
    """Bark colouring by level: the old limbs greyed with lichen here and
    there, the twigs dark."""
    pick = rng.random(64)

    def col_of(level, t):
        base = BARK + (TWIG - BARK) * min(1.0, level / 3.0)
        j = int((level * 7 + t * 9) % 64)
        if level <= 1 and pick[j] < lichen_k:
            base = base + (LICHEN - base) * 0.45
        return base * rng.uniform(0.92, 1.06)
    return col_of


# Few forks, each kept thick, so a clump reads as a handful of crooked
# branches rather than a haze of hairlines.
LACE = {
    "levels": 4, "kids": [(3, 4), (2, 3), (2, 3)],
    "fork": (0.35, 0.95), "kid_len": (0.48, 0.74), "gnarl": 0.17,
    "curl": 0.03, "kink": 0.10, "tip": 0.38, "droop": 0.0,
}


def lace(rng, limbs, leafy=0.0):
    """A tangle of branches seen from below: `limbs` limbs coming in from
    the picture's edges toward its middle, each forking down to fine twigs,
    crossing one another; with `leafy`, some twig ends still hold a few
    dead leaves."""
    cv = Canvas()
    S = CELL * SS
    col_of = _bark_col(rng)
    for k in range(limbs):
        # In from a point round the edge, aimed across the middle.
        a = (k + rng.uniform(-0.3, 0.3)) / limbs * math.tau
        sx = 0.5 + 0.52 * math.cos(a)
        sy = 0.5 + 0.52 * math.sin(a)
        aim = math.atan2(0.5 - sy, 0.5 - sx) + rng.normal(0.0, 0.35)
        grow(cv, rng, (sx * S, sy * S), aim, rng.uniform(0.5, 0.78) * S,
             rng.uniform(0.022, 0.032) * S, 0, LACE, col_of)
    if leafy > 0:
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        tips = np.argwhere((cv.d < 0) & (cv.d > -1.5 * SS))
        for _ in range(int(60 * leafy)):
            cy, cx = tips[int(rng.integers(0, len(tips)))]
            for _ in range(int(rng.integers(2, 6))):
                _oak_leaf(d, cx + rng.normal(0, 7 * SS), cy + rng.normal(0, 7 * SS),
                          rng.uniform(13, 21) * SS,
                          math.pi / 2 + rng.normal(0, 0.9),
                          np.array(DEAD[int(rng.integers(0, len(DEAD)))])
                          * rng.uniform(0.75, 1.05))
        cv.shapes(layer)
    return cv.finish()


def _oak_leaf(d, cx, cy, size, ang, col):
    """A dead oak leaf `size` long, pointing along `ang`: widest past its
    middle, with four or five round lobes down each side and a dark rib."""
    up, dn = [], []
    n = 40
    for k in range(n + 1):
        u = k / n
        env = math.sin(math.pi * min(1.0, u * 1.08)) ** 0.75 * (0.6 + 0.4 * u)
        lobe = 0.62 + 0.38 * abs(math.cos(4.5 * math.pi * u))
        w = size * 0.27 * env * lobe
        x = (u - 0.35) * size
        up.append((x, -w))
        dn.append((x, w))
    pts = up + dn[::-1]
    ca, sa = math.cos(ang), math.sin(ang)
    tr = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]
    c = tuple(int(min(255, v)) for v in col)
    d.polygon(tr, fill=c + (255,))
    rib = tuple(int(v * 0.6) for v in c) + (255,)
    x0, x1 = -0.42 * size, 0.6 * size
    d.line([(cx + x0 * ca, cy + x0 * sa), (cx + x1 * ca, cy + x1 * sa)], fill=rib,
           width=max(1, int(size * 0.06)))


DROOP = {
    "levels": 3, "kids": [(2, 3), (1, 2)], "fork": (0.2, 0.6),
    "kid_len": (0.35, 0.6), "gnarl": 0.10, "curl": 0.0, "kink": 0.04,
    "tip": 0.25, "droop": 0.55,
}


def droop(rng):
    """A limb across the top of the picture with twigs hanging from it, as
    a weeping branch's are: the fringe a clump trails below it."""
    cv = Canvas()
    S = CELL * SS
    col_of = _bark_col(rng, 0.25)
    pts, rads = grow(cv, rng, (-0.02 * S, 0.10 * S), rng.normal(0, 0.06),
                     1.04 * S, 0.020 * S, 0,
                     {"levels": 1, "kids": [(0, 0)], "fork": (0, 0),
                      "kid_len": (0, 0), "gnarl": 0.08, "curl": 0.0,
                      "kink": 0.05, "tip": 0.6, "droop": 0.0}, col_of)
    for _ in range(26):
        i = int(rng.integers(1, len(pts) - 1))
        ang = math.pi / 2 + rng.normal(0, 0.9)
        ln = rng.uniform(0.30, 0.85) * S
        grow(cv, rng, pts[i], ang, ln, rads[i] * rng.uniform(0.35, 0.6), 1,
             dict(DROOP, levels=3), col_of)
    return cv.finish()


def moss(rng):
    """Old man's beard: pale lichen hanging from a twig in tufts, each tuft
    a bundle of fine strands of its own length, crinkled and parting."""
    cv = Canvas()
    S = CELL * SS
    pts, rads = grow(cv, rng, (0.04 * S, 0.06 * S), rng.normal(0, 0.05),
                     0.92 * S, 0.012 * S, 0,
                     {"levels": 1, "kids": [(0, 0)], "fork": (0, 0),
                      "kid_len": (0, 0), "gnarl": 0.10, "curl": 0.0,
                      "kink": 0.05, "tip": 0.5, "droop": 0.0}, lambda l, t: TWIG)
    for _ in range(int(rng.integers(7, 11))):
        i = int(rng.integers(1, len(pts)))
        x, y = pts[i]
        tuft = rng.uniform(0.25, 0.9) * S
        tone = rng.uniform(0.8, 1.05)
        for _ in range(int(rng.integers(9, 16))):
            ln = tuft * rng.uniform(0.55, 1.05)
            n = max(5, int(ln / (8 * SS)))
            ph = rng.uniform(0, math.tau)
            amp = rng.uniform(2, 7) * SS
            drift = rng.normal(0.0, 0.12) * ln
            sp = [np.array([x + rng.normal(0, 5 * SS), y])]
            for k in range(n):
                f = (k + 1) / n
                sp.append(np.array([sp[0][0] + drift * f
                                    + math.sin(ph + f * rng.uniform(8, 14)) * amp,
                                    y + ln * f]))
            r0 = rng.uniform(1.1, 2.0) * SS
            cv.polyline(sp, np.linspace(r0, 0.6 * SS, len(sp)),
                        BEARD * tone * rng.uniform(0.9, 1.05), shade=0.15)
    return cv.finish(erode=5.0)


def ivy_mass(rng):
    """A clump of ivy grown up into the crown: dark leaves on stems, round
    in outline and ragged at its edge."""
    S = CELL * SS
    cv = Canvas()
    col_of = _bark_col(rng, 0.0)
    for _ in range(5):
        grow(cv, rng, (rng.uniform(0.3, 0.7) * S, 0.98 * S),
             -math.pi / 2 + rng.normal(0, 0.5), rng.uniform(0.4, 0.75) * S,
             0.010 * S, 1, {"levels": 3, "kids": [(2, 3), (1, 3), (1, 2)],
                            "fork": (0.4, 1.0), "kid_len": (0.4, 0.6),
                            "gnarl": 0.2, "curl": 0.0, "kink": 0.1, "tip": 0.4,
                            "droop": 0.0}, col_of)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # An uneven outline for the mass, longer than wide, as ivy hangs.
    lobes = rng.normal(0.0, 1.0, 6)
    for _ in range(300):
        r = math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        edge = 0.36 * (1.0 + 0.16 * sum(lobes[k] * math.cos((k + 2) * a + k)
                                        for k in range(6)) / 2.5)
        cx = (0.5 + math.cos(a) * r * edge * 0.95) * S
        cy = (0.5 + math.sin(a) * r * edge * 1.2) * S
        if rng.random() < r ** 3 * 0.6:
            continue
        base = IVY[int(rng.integers(0, len(IVY)))]
        k = rng.uniform(0.8, 1.15)
        col = tuple(int(min(255, v * k)) for v in base) + (255,)
        vein = tuple(int(min(255, v * k * 1.45)) for v in base) + (255,)
        TX._ivy_leaf(d, cx, cy, rng.uniform(16, 26) * SS, rng.normal(0, 0.6),
                     col, vein)
    cv.shapes(layer)
    return cv.finish(erode=12.0)


def leaves(rng):
    """Dead leaves that never fell: twigs heavy with them, hanging in
    bunches, brown, a few curled edge-on."""
    cv = Canvas()
    S = CELL * SS
    col_of = _bark_col(rng, 0.2)
    for sx, ang in ((0.15, -1.1), (0.5, -1.6), (0.85, -2.05)):
        grow(cv, rng, (sx * S, 1.0 * S), ang + rng.normal(0, 0.2),
             rng.uniform(0.6, 0.85) * S, 0.018 * S, 0,
             dict(LACE, levels=4, kids=[(3, 4), (2, 4), (2, 3)]), col_of)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    twig = np.argwhere((cv.d < 0) & (cv.d > -2.0 * SS))
    for _ in range(46):
        cy, cx = twig[int(rng.integers(0, len(twig)))]
        for _ in range(int(rng.integers(4, 9))):
            size = rng.uniform(22, 36) * SS
            ang = math.pi / 2 + rng.normal(0, 0.8)
            col = np.array(DEAD[int(rng.integers(0, len(DEAD)))]) * rng.uniform(0.75, 1.05)
            _oak_leaf(d, cx + rng.normal(0, 8 * SS) + math.cos(ang) * size * 0.3,
                      cy + rng.normal(0, 8 * SS) + math.sin(ang) * size * 0.3,
                      size, ang, col)
    cv.shapes(layer)
    return cv.finish(erode=10.0)


def bramble(rng, tall=False):
    """Bramble and scrub standing on the bottom of the picture: arching
    canes with leaves along them, and with `tall` a young tree rising out
    of it. Seen from far off: its ragged top is what matters."""
    cv = Canvas()
    S = CELL * SS
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # The dense heart of it: a low mass with a lumpy top, so the scrub is
    # solid below whatever pokes out of it.
    ph = rng.uniform(0, math.tau, 5)
    top = []
    for k in range(65):
        u = k / 64
        h = 0.34 + 0.07 * sum(math.sin((j + 2) * math.pi * u + ph[j]) for j in range(5)) / 2.0
        top.append((u * S, S - h * S))
    d.polygon(top + [(S, S), (0, S)], fill=(40, 44, 34, 255))
    for _ in range(140):
        u = rng.random()
        k = int(u * 64)
        y = top[k][1] + rng.uniform(-0.04, 0.12) * S
        _bramble_leaf(d, u * S, y, rng.uniform(18, 30) * SS, rng.uniform(0, math.tau),
                      np.array(BRAMBLE_LEAF[int(rng.integers(0, len(BRAMBLE_LEAF)))])
                      * rng.uniform(0.75, 1.0))
    for _ in range(30):
        x0 = rng.uniform(0.02, 0.98) * S
        h = rng.uniform(0.38, 0.78) * S * (0.8 if tall else 1.0)
        lean = rng.choice([-1.0, 1.0]) * rng.uniform(0.15, 0.6)
        n = 14
        pts = []
        for k in range(n + 1):
            f = k / n
            pts.append(np.array([x0 + lean * h * f * f * 1.2 + rng.normal(0, 2 * SS),
                                 S - h * math.sin(f * math.pi * 0.62) / math.sin(math.pi * 0.62)
                                 * (1.0 - 0.15 * f)]))
        r0 = rng.uniform(3.5, 6.0) * SS
        cv.polyline(pts, np.linspace(r0, 1.0 * SS, len(pts)), CANE * rng.uniform(0.8, 1.1))
        for k in range(2, n + 1):
            if rng.random() < 0.75:
                c = pts[k]
                col = np.array(BRAMBLE_LEAF[int(rng.integers(0, len(BRAMBLE_LEAF)))])
                _bramble_leaf(d, c[0] + rng.normal(0, 5 * SS), c[1] + rng.normal(0, 5 * SS),
                              rng.uniform(18, 30) * SS, rng.uniform(0, math.tau),
                              col * rng.uniform(0.85, 1.1))
    # Low twiggy scrub filling the foot.
    col_of = _bark_col(rng, 0.1)
    for _ in range(6):
        grow(cv, rng, (rng.uniform(0.05, 0.95) * S, S), -math.pi / 2 + rng.normal(0, 0.6),
             rng.uniform(0.18, 0.4) * S, 0.006 * S, 1,
             {"levels": 3, "kids": [(2, 3), (2, 3), (1, 2)], "fork": (0.4, 1.0),
              "kid_len": (0.4, 0.65), "gnarl": 0.25, "curl": 0.0, "kink": 0.1,
              "tip": 0.4, "droop": 0.0}, col_of)
    if tall:
        grow(cv, rng, (rng.uniform(0.35, 0.65) * S, S), -math.pi / 2 + rng.normal(0, 0.1),
             0.92 * S, 0.016 * S, 0,
             {"levels": 4, "kids": [(3, 4), (2, 3), (2, 3)], "fork": (0.35, 0.8),
              "kid_len": (0.3, 0.5), "gnarl": 0.12, "curl": 0.0, "kink": 0.06,
              "tip": 0.3, "droop": 0.0}, col_of)
    cv.shapes(layer)
    return cv.finish(erode=7.0)


def _bramble_leaf(d, cx, cy, size, ang, col):
    """A bramble leaf: a pointed oval with a toothed edge."""
    pts = []
    for k in range(40):
        t = k / 40 * math.tau
        r = size * 0.5 * (1.0 + 0.08 * (k % 2))
        x = math.cos(t) * r
        y = math.sin(t) * r * 0.62 * (1.0 - 0.35 * max(0.0, math.cos(t)))
        pts.append((x, y))
    ca, sa = math.cos(ang), math.sin(ang)
    d.polygon([(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts],
              fill=tuple(int(min(255, v)) for v in col) + (255,))


def canopy_cells(seed=91):
    """Every picture on the sheet, by name."""
    rng = np.random.default_rng(seed)
    return {
        "lace0": lace(rng, 4),
        "lace1": lace(rng, 5, leafy=1.0),
        "droop": droop(rng),
        "moss": moss(rng),
        "ivy": ivy_mass(rng),
        "leaves": leaves(rng),
        "bramble0": bramble(rng),
        "bramble1": bramble(rng, tall=True),
    }


def canopy_sheet(cells):
    sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    for name, img in cells.items():
        c, r = CANOPY_CELLS[name]
        sheet.paste(img, (c * CELL, r * CELL))
    # Bleed the colour into the empty space between cells too.
    arr = np.asarray(sheet).astype(np.float32)
    known = arr[..., 3] > 0
    idx = ndimage.distance_transform_edt(~known, return_distances=False,
                                         return_indices=True)
    arr[..., :3] = arr[..., :3][idx[0], idx[1]]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------------------
# The light under it
# ---------------------------------------------------------------------------

LIGHT_N = 1024
LIGHT_MEAN = 0.2            # how much moonlight gets through it on the whole


def canopy_light(cells, seed=93):
    """How much moonlight gets through the canopy, as a tiling mask (white
    through a gap, black under cover): the clumps' own pictures scattered,
    turned and overlapping until most of the sky is shut, over a slower
    swell of thicker and thinner cover. Softened a little, as a shadow is
    from that height."""
    rng = np.random.default_rng(seed)
    n = LIGHT_N
    cov = np.zeros((n, n), np.float32)
    names = ["lace0", "lace1", "ivy", "leaves", "lace0", "lace1"]
    for _ in range(170):
        img = cells[names[int(rng.integers(0, len(names)))]]
        size = int(rng.uniform(110, 260))
        a = img.split()[3].resize((size, size), Image.BILINEAR)
        a = a.rotate(rng.uniform(0, 360), resample=Image.BILINEAR, expand=True)
        m = np.asarray(a).astype(np.float32) / 255.0
        m = np.clip((m - 0.35) / 0.3, 0.0, 1.0)
        h, w = m.shape
        x0, y0 = int(rng.integers(0, n)), int(rng.integers(0, n))
        ys = (np.arange(h) + y0) % n
        xs = (np.arange(w) + x0) % n
        cov[np.ix_(ys, xs)] = np.maximum(cov[np.ix_(ys, xs)], m)
    swell = TX.unit(TX.spectral(n, seed + 1, beta=2.6, fmin=1.5))
    cov = np.clip(cov + (swell - 0.45) * 0.8, 0.0, 1.0)
    cov = ndimage.gaussian_filter(cov, 1.6, mode="wrap")
    # Darkened so that `LIGHT_MEAN` of the moonlight gets through on the
    # whole, the gaps staying bright.
    open_ = np.clip(1.0 - cov, 0.0, 1.0)
    lo, hi = 0.3, 6.0
    for _ in range(30):
        g = math.sqrt(lo * hi)
        if float((open_ ** g).mean()) > LIGHT_MEAN:
            lo = g
        else:
            hi = g
    light = open_ ** math.sqrt(lo * hi)
    g = (np.clip(light, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([g, g, g, np.full_like(g, 255)]), "RGBA")


# ---------------------------------------------------------------------------
# The tiles
# ---------------------------------------------------------------------------

TILE_Z = 1600.0             # a tile's depth down the path
HALF_W = 4200.0             # how far it reaches either side of the path
GAP = (120.0, 420.0)        # over the path the clumps thin out from GAP[1] in to GAP[0]
H_SIDE, H_PATH = 760.0, 1150.0
VAULT = (260.0, 1400.0)     # the vault rises from H_SIDE to H_PATH between these
CLEAR = (320.0, 500.0)      # nothing hangs lower than [1] within [0] of the path's middle
SPACING = 235.0             # clumps a jittered grid this far apart
BARK_TINT = np.array([0.62, 0.60, 0.56])


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def vault(x):
    """The canopy's underside over distance `x` from the path's middle."""
    return H_SIDE + (H_PATH - H_SIDE) * (1.0 - smoothstep(VAULT[0], VAULT[1], abs(x)))


def _frame(yaw, tilt_axis=None, tilt=0.0):
    """A card's right, up and normal from its yaw (radians) and a tilt."""
    r = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
    u = np.array([0.0, 1.0, 0.0])
    if tilt and tilt_axis is not None:
        m = M.rot_axis(tilt_axis, tilt)
        r, u = m @ r, m @ u
    return r, u


def _upright(c, yaw, w, top, h, cell, tint, ao, sway):
    """A card standing upright (hanging from `top`, `h` tall, `w` wide)."""
    r, _ = _frame(yaw)
    c = np.asarray(c, float)
    bl = c + (-r * w * 0.5) + np.array([0.0, top - h, 0.0])
    br = c + (r * w * 0.5) + np.array([0.0, top - h, 0.0])
    tr = c + (r * w * 0.5) + np.array([0.0, top, 0.0])
    tl = c + (-r * w * 0.5) + np.array([0.0, top, 0.0])
    return M.card((bl, br, tr, tl), canopy_rect(cell), tint, ao=ao, sway=sway)


def _flat(c, yaw, s, tilt_axis, tilt, cell, tint, ao, sway):
    """A card lying (nearly) flat, seen from below: a crown of twigs."""
    r = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
    f = np.array([math.sin(yaw), 0.0, math.cos(yaw)])
    m = M.rot_axis(tilt_axis, tilt)
    r, f = m @ r, m @ f
    c = np.asarray(c, float)
    h = s * 0.5
    bl, br = c - r * h - f * h, c + r * h - f * h
    tr, tl = c + r * h + f * h, c - r * h + f * h
    return M.card((bl, br, tr, tl), canopy_rect(cell), tint, ao=ao, sway=sway)


def _tint(rng, k=1.0):
    t = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.72, 1.0) * k
    t *= np.array([1.0 + rng.normal(0, 0.04), 1.0 + rng.normal(0, 0.04),
                   1.0 + rng.normal(0, 0.04)])
    return np.clip(t, 0.0, 1.0)


def clump(strip, rng, x, z):
    """One clump of the canopy: a crown of twig tangle seen from below, and
    curtains hanging from it (drooping twigs, ivy, dead leaves, moss), which
    are what it shows edge-on from far down the path."""
    side = smoothstep(GAP[0], GAP[1], abs(x))
    s = rng.uniform(260.0, 460.0) * (0.8 + 0.35 * side)
    y = vault(x) + rng.normal(0.0, 45.0)
    tint = _tint(rng)
    yaw = rng.uniform(0.0, math.tau)
    axis = M.norm(np.array([rng.normal(), 0.0, rng.normal()]))
    crown = ["lace0", "lace1", "lace0", "lace1", "leaves", "ivy"][int(rng.integers(0, 6))]
    strip.add(_flat((x, y + 0.12 * s, z), yaw, s, axis, rng.normal(0.0, 0.35),
                    crown, tint, 0.85, (0.08, 0.08, 0.08, 0.08)))
    if rng.random() < 0.45:
        # A second, smaller crown under the first, for depth.
        axis2 = M.norm(np.array([rng.normal(), 0.0, rng.normal()]))
        strip.add(_flat((x + rng.normal(0, 60), y - 0.06 * s, z + rng.normal(0, 60)),
                        rng.uniform(0, math.tau), s * 0.7, axis2, rng.normal(0.0, 0.4),
                        ["lace0", "lace1", "leaves"][int(rng.integers(0, 3))],
                        tint * 0.92, 0.8, (0.1, 0.1, 0.1, 0.1)))
    th = rng.normal(0.0, 0.55)
    for k in range(2):
        # (Not the ivy or the dead leaves: hung up as a curtain, a mass of
        # them reads as a ball floating in the air.)
        cell = ["droop", "droop", "droop", "moss", "lace1"][int(rng.integers(0, 5))]
        w = s * rng.uniform(0.6, 0.95)
        h = s * rng.uniform(0.45, 0.8)
        yw = th if k == 0 else th + rng.uniform(1.0, 2.1)
        c = (x + rng.normal(0, 40), 0.0, z + rng.normal(0, 40))
        strip.add(_upright(c, yw, w, y + 0.18 * s, h, cell, tint * 0.95, 0.8,
                           (0.45, 0.3, 0.15, 0.05)))
    if rng.random() < 0.12:
        c = (x + rng.normal(0, 70), 0.0, z + rng.normal(0, 70))
        strip.add(_upright(c, rng.normal(0.0, 0.7), s * rng.uniform(0.35, 0.5),
                           y, s * rng.uniform(0.5, 0.95), "moss", tint, 0.9,
                           (0.6, 0.4, 0.15, 0.0)))


def _over_path(q, r=0.0):
    """Whether a point hangs low over the path, where the camera flies."""
    return abs(q[0]) - r < CLEAR[0] and q[1] - r < CLEAR[1]


def bough(strip, rng, z):
    """A bough arching over the path from the canopy on one side, across
    or partway, its lowest point well over the camera's head, with branches
    off it ending in twigs, and drooping twigs and moss hanging under it."""
    side = rng.choice([-1.0, 1.0])
    x0 = side * rng.uniform(560.0, 900.0)
    y0 = vault(x0) - rng.uniform(30.0, 120.0)
    across = rng.random() < 0.6
    x1 = -side * (rng.uniform(420.0, 900.0) if across else rng.uniform(-200.0, 220.0))
    low = rng.uniform(640.0, 860.0)
    y1 = (vault(x1) - rng.uniform(0.0, 100.0)) if across else low - rng.uniform(40.0, 140.0)
    z1 = z + rng.normal(0.0, 160.0)
    p0 = np.array([x0, y0, z])
    p2 = np.array([x1, y1, z1])
    p1 = np.array([(x0 + x1) * 0.5, 2.0 * low - 0.5 * (y0 + y1), (z + z1) * 0.5
                   + rng.normal(0.0, 120.0)])
    k = 26
    t = np.linspace(0.0, 1.0, k)[:, None]
    P = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2
    # Gnarl: a wander off the curve, smoothed, held at its root.
    wob = np.cumsum(rng.normal(0.0, 9.0, (k, 3)), axis=0)
    wob -= wob[:1]
    P = WT.smooth(P + wob * np.array([0.6, 1.0, 1.0]), 2)
    r0 = rng.uniform(17.0, 26.0)
    R = WT.taper(k, r0, r0 * (0.28 if across else 0.2), 0.9)
    s = M.arclen(P)
    sway = np.clip(s / s[-1], 0.0, 1.0) * 0.12
    strip.add(M.tube(P, R, 10, BARK_TINT, ao=np.full(k, 0.85), u_tile=170.0,
                     v_tile=340.0, sway=sway))
    T, N, B = M.frames(P)
    for _ in range(int(rng.integers(4, 8))):
        i = int(rng.integers(3, k - 2))
        out = M.norm(np.array([T[i][0], 0.0, T[i][2]]))
        yaw = rng.choice([-1.0, 1.0]) * rng.uniform(0.5, 1.2)
        d = M.rot_y(math.degrees(yaw)) @ out
        d = M.norm(d + np.array([0.0, rng.uniform(-0.35, 0.25), 0.0]))
        ln = rng.uniform(120.0, 360.0)
        pts = WT.walk(rng, P[i], d, ln, 26.0, 0.16, -0.06, droop=0.5,
                      avoid=lambda q: _over_path(q, 8.0))
        if len(pts) < 3:
            continue
        pts = WT.smooth(pts, 2)
        rr = WT.taper(len(pts), R[i] * rng.uniform(0.35, 0.5), 1.0, 0.9)
        sw = 0.12 + 0.5 * np.linspace(0.0, 1.0, len(pts))
        if rr[0] > WT.RIBBON_R:
            strip.add(M.tube(pts, rr, 6, BARK_TINT * 0.95, ao=np.full(len(pts), 0.85),
                             u_tile=170.0, v_tile=340.0, sway=sw))
        else:
            strip.add(M.ribbon(pts, rr, BARK_TINT * 0.9, ao=0.85, sway=sw))
        for _ in range(int(rng.integers(2, 5))):
            j = int(rng.integers(max(1, len(pts) // 2), len(pts)))
            tw = WT.walk(rng, pts[j], M.norm(d + rng.normal(0, 0.6, 3)),
                         rng.uniform(40.0, 120.0), 14.0, 0.25, -0.1, droop=0.9,
                         avoid=lambda q: _over_path(q, 4.0))
            if len(tw) < 2:
                continue
            strip.add(M.ribbon(tw, np.linspace(2.0, 0.3, len(tw)), BARK_TINT * 0.85,
                               ao=0.85, sway=0.6))
    for _ in range(int(rng.integers(2, 4))):
        i = int(rng.integers(4, k - 3))
        c = P[i] - np.array([0.0, R[i] * 0.6, 0.0])
        cell = ["droop", "droop", "droop", "moss", "moss"][int(rng.integers(0, 5))]
        h = rng.uniform(140.0, 320.0)
        w = rng.uniform(150.0, 260.0)
        if abs(c[0]) - w * 0.5 < CLEAR[0]:
            h = min(h, c[1] + 20.0 - CLEAR[1])
        if h < 80.0:
            continue
        strip.add(_upright((c[0], 0.0, c[2]), rng.normal(0.0, 0.6),
                           w, c[1] + 20.0, h, cell,
                           _tint(rng), 0.8, (0.6, 0.4, 0.15, 0.0)))


def tile(seed):
    """One tile of canopy, `TILE_Z` deep, laid out from the path's middle:
    clumps on a jittered grid, fewer over the path, sorted far to near (so
    it draws back to front), then two boughs across the path. A clump near
    a tile's end overhangs into the next, which hides the join."""
    rng = np.random.default_rng(seed)
    sites = []
    nx = int(HALF_W / SPACING)
    for ix in range(-nx, nx + 1):
        for iz in range(int(TILE_Z / SPACING)):
            x = (ix + rng.uniform(-0.45, 0.45)) * SPACING
            z = (iz + rng.uniform(0.0, 1.0)) * SPACING
            dens = 0.22 + 0.78 * smoothstep(GAP[0], GAP[1], abs(x))
            if rng.random() > dens:
                continue
            sites.append((x, z))
    sites.sort(key=lambda s: -s[1])
    strip = M.Strip()
    for x, z in sites:
        clump(strip, rng, x, z)
    for zb in (TILE_Z * rng.uniform(0.1, 0.4), TILE_Z * rng.uniform(0.6, 0.9)):
        bough(strip, rng, zb)
    return strip.build()


# ---------------------------------------------------------------------------
# The far treeline
# ---------------------------------------------------------------------------
#
# The wood beyond the end of the path, as a silhouette at the foot of the sky:
# a band the wood draws round the camera with the sky (so, like the moon, it
# turns with the camera and never comes nearer), into which everything the
# wood draws fades as it nears the far end. So a tree arrives out of the far
# wood rather than appearing, and the moon sets its foot behind trees.
#
# Two layers in one picture, coloured by the sky's shader: red, the far
# forest, a mass with crowns and dead spires standing out of it; green, the
# nearer edge of the forest, lower, with a few big crooked trees standing
# clear against the sky; and blue, a rim along the upper edges of both, which
# catches the moon's glow. The picture spans `TL_SPAN` degrees round (the
# wood repeats it) and `TL_EL` degrees of elevation; it tiles across. It is
# drawn at twice the size it is kept at (`TL_KEEP`), which smooths its edges.

TL_W, TL_H = 4096, 1024
TL_KEEP = 2
TL_SPAN = 120.0
TL_EL = (-14.0, 12.0)       # bottom and top of the picture, degrees


class _Sdf:
    """A silhouette as a signed distance in pixels (negative inside),
    drawn with capsules, `margin` pixels wider each side so that what
    crosses an edge can be folded back round (`fold`)."""

    def __init__(self, w, h, margin):
        self.w, self.h, self.m = w, h, margin
        self.d = np.full((h, w + 2 * margin), 1e6, np.float32)

    def capsule(self, a, b, ra, rb, col=None, shade=0.0):
        ax, ay = float(a[0]) + self.m, float(a[1])
        bx, by = float(b[0]) + self.m, float(b[1])
        r = max(ra, rb)
        x0 = int(max(0, math.floor(min(ax, bx) - r - 2)))
        x1 = int(min(self.d.shape[1], math.ceil(max(ax, bx) + r + 2)))
        y0 = int(max(0, math.floor(min(ay, by) - r - 2)))
        y1 = int(min(self.h, math.ceil(max(ay, by) + r + 2)))
        if x0 >= x1 or y0 >= y1:
            return
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        vx, vy = bx - ax, by - ay
        l2 = vx * vx + vy * vy + 1e-9
        t = np.clip(((X - ax) * vx + (Y - ay) * vy) / l2, 0.0, 1.0)
        sd = np.hypot(X - (ax + t * vx), Y - (ay + t * vy)) - (ra + (rb - ra) * t)
        sub = self.d[y0:y1, x0:x1]
        np.minimum(sub, sd.astype(np.float32), out=sub)

    def below(self, top):
        """Everything under the line `top` (a row per column)."""
        y = np.arange(self.h, dtype=np.float32)[:, None] + 0.5
        t = np.concatenate([top[-self.m:], top, top[:self.m]])[None, :]
        np.minimum(self.d, (t - y).astype(np.float32), out=self.d)

    def fold(self):
        m, w = self.m, self.w
        d = self.d[:, m:m + w].copy()
        np.minimum(d[:, :m], self.d[:, m + w:], out=d[:, :m])
        np.minimum(d[:, w - m:], self.d[:, :m], out=d[:, w - m:])
        return d


def _tl_row(el):
    """The picture's row at elevation `el` (degrees)."""
    return (TL_EL[1] - el) / (TL_EL[1] - TL_EL[0]) * TL_H


def _tl_px(deg):
    """Pixels up the picture for `deg` degrees of elevation."""
    return deg / (TL_EL[1] - TL_EL[0]) * TL_H


def _tl_ridge(rng, mean, swing, lumps):
    """A wavering line (a row per column) across the picture, tiling:
    `mean` degrees up, swinging by `swing`, broken by `lumps` round crowns."""
    x = np.arange(TL_W) / TL_W * math.tau
    h = np.zeros(TL_W)
    for k, amp in ((2, 0.55), (3, 0.35), (5, 0.25), (9, 0.15)):
        h += amp * np.sin(k * x + rng.uniform(0, math.tau))
    h = h / 1.3 * swing + mean
    row = (TL_EL[1] - h) / (TL_EL[1] - TL_EL[0]) * TL_H
    bump = np.zeros(TL_W)
    cols = np.arange(TL_W)
    for _ in range(lumps):
        c = rng.uniform(0, TL_W)
        r = rng.uniform(14, 46)
        dx = (cols - c + TL_W / 2) % TL_W - TL_W / 2
        bump = np.maximum(bump, np.sqrt(np.clip(r * r - dx * dx, 0, None)) * 0.55)
    return row - bump


def _tl_thicket(sd, rng, ridge, n, rise, rad):
    """A forest's mass seen from afar: solid under `ridge` and broken along
    its top by `n` crowns of bare twigs (each a ragged spatter of specks,
    thick in its heart, on a stem), rising up to `rise` degrees over it, so
    no level line shows anywhere."""
    sd.below(ridge + 40)
    for _ in range(n):
        x = rng.uniform(0, TL_W)
        base = ridge[int(x) % TL_W]
        top = base - _tl_px(rng.uniform(0.0, rise) ** 1.4 / rise ** 0.4)
        w = rng.uniform(1.2, 2.4) * rad[1]
        h = rng.uniform(0.8, 1.6) * rad[1]
        cy = top + h
        for _ in range(int(rng.integers(10, 20))):
            u, v = rng.normal(0, 0.45, 2)
            c = (x + u * w, cy + v * h)
            r = rng.uniform(1.6, rad[0]) * (1.0 - 0.5 * min(1.0, math.hypot(u, v)))
            sd.capsule(c, c, max(r, 1.2), max(r, 1.2))
        sd.capsule((x, cy), (x + rng.normal(0, 4), base + 44), 1.8, 2.8)


TL_BARE = {
    "levels": 4, "kids": [(2, 3), (2, 3), (1, 3)], "fork": (0.35, 0.85),
    "kid_len": (0.45, 0.68), "gnarl": 0.12, "curl": 0.02, "kink": 0.08,
    "tip": 0.35, "droop": 0.0,
}
TL_DENSE = dict(TL_BARE, kids=[(3, 4), (2, 3), (2, 3)], gnarl=0.16, kink=0.12)
TL_WEEP = dict(TL_BARE, droop=0.55, kids=[(3, 4), (2, 3), (2, 3)], fork=(0.5, 1.1))


def _tl_tree(sd, rng, x, base, height, trunk, lean=0.0, weep=False, dense=False):
    """A tree in silhouette standing on row `base`, `height` pixels tall:
    a trunk that forks into a few strong limbs ending in claws of twig."""
    P = TL_WEEP if weep else (TL_DENSE if dense else TL_BARE)
    split = rng.uniform(0.35, 0.6) * height
    pts = [np.array([x, base + 4.0])]
    n = 6
    a = -math.pi / 2 + lean
    for k in range(n):
        a += rng.normal(0, 0.06)
        pts.append(pts[-1] + split / n * np.array([math.cos(a), math.sin(a)]))
    for k in range(n):
        sd.capsule(pts[k], pts[k + 1], trunk * (1.0 - 0.25 * k / n),
                   trunk * (1.0 - 0.25 * (k + 1) / n))
    for j in range(int(rng.integers(2, 5))):
        ka = a + rng.uniform(-0.9, 0.9)
        grow(sd, rng, pts[-1], ka, (height - split) * rng.uniform(0.75, 1.05),
             trunk * rng.uniform(0.5, 0.7), 1, P, lambda lv, t: (0, 0, 0))


def _tl_snag(sd, rng, x, base, height, trunk):
    """A dead spire: a straight trunk snapped off, a few broken stubs."""
    lean = rng.normal(0, 0.05)
    top = np.array([x + math.sin(lean) * height, base - height])
    foot = np.array([x, base + 4.0])
    sd.capsule(foot, top, trunk, trunk * 0.55)
    for _ in range(int(rng.integers(1, 4))):
        f = rng.uniform(0.45, 0.9)
        p = foot + (top - foot) * f
        s = rng.choice([-1.0, 1.0])
        q = p + np.array([s * rng.uniform(10, 30), -rng.uniform(4, 16)])
        sd.capsule(p, q, trunk * 0.4, trunk * 0.2)


def treeline(seed=97):
    """The far treeline's picture (see above)."""
    rng = np.random.default_rng(seed)
    far = _Sdf(TL_W, TL_H, 300)
    near = _Sdf(TL_W, TL_H, 300)

    # The far forest: a mass a little over the horizon whose top is a press
    # of bare crowns, with taller trees and dead spires standing out of it.
    ridge = _tl_ridge(rng, 1.4, 0.8, 0)
    _tl_thicket(far, rng, ridge, 900, 2.0, (6, 20))
    for _ in range(340):
        x = rng.uniform(0, TL_W)
        _tl_tree(far, rng, x, ridge[int(x) % TL_W] + 30, _tl_px(rng.uniform(1.2, 2.6)),
                 rng.uniform(1.6, 2.6), lean=rng.normal(0, 0.1))
    for _ in range(46):
        x = rng.uniform(0, TL_W)
        _tl_tree(far, rng, x, ridge[int(x) % TL_W] + 20, _tl_px(rng.uniform(2.8, 5.0)),
                 rng.uniform(2.6, 3.6), lean=rng.normal(0, 0.08), dense=True)
    for _ in range(8):
        x = rng.uniform(0, TL_W)
        _tl_snag(far, rng, x, ridge[int(x) % TL_W] + 10, _tl_px(rng.uniform(4.5, 7.0)),
                 rng.uniform(3.0, 4.2))

    # The near edge: lower, its top a press of scrub and thicket (no level
    # line anywhere), and a few big crooked trees set apart, so each reads on
    # its own against the far forest and the moon.
    ridge2 = _tl_ridge(rng, -0.9, 0.5, 0)
    _tl_thicket(near, rng, ridge2, 520, 1.5, (4, 13))
    for _ in range(220):
        x = rng.uniform(0, TL_W)
        _tl_tree(near, rng, x, ridge2[int(x) % TL_W] + 24, _tl_px(rng.uniform(1.0, 2.4)),
                 rng.uniform(1.6, 2.6), lean=rng.normal(0, 0.25))
    xs = (np.arange(14) + rng.uniform(0.1, 0.9, 14)) / 14 * TL_W
    for x in xs:
        b = ridge2[int(x) % TL_W] + 12
        kind = rng.random()
        if kind < 0.15:
            _tl_snag(near, rng, x, b, _tl_px(rng.uniform(5.5, 8.0)), rng.uniform(4.5, 6.0))
        else:
            _tl_tree(near, rng, x, b, _tl_px(rng.uniform(4.0, 7.5)), rng.uniform(5.0, 7.0),
                     lean=rng.normal(0, 0.12), weep=kind > 0.8, dense=True)

    df, dn = far.fold(), near.fold()
    cf = np.clip(0.5 - df, 0.0, 1.0)
    cn = np.clip(0.5 - dn, 0.0, 1.0)
    # The rim: a band just inside an upper edge of either layer.
    d = np.minimum(df, dn)
    gy = np.zeros_like(d)
    gy[1:-1] = (d[2:] - d[:-2]) * 0.5
    up = np.clip(-gy, 0.0, 1.0)
    rim = np.clip(1.0 + d / 3.0, 0.0, 1.0) * np.clip(0.5 - d, 0.0, 1.0) * up
    rgba = np.dstack([cf, cn, rim, np.ones_like(cf)]) * 255.0
    img = Image.fromarray(np.clip(rgba + 0.5, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((TL_W // TL_KEEP, TL_H // TL_KEEP), Image.BOX)
