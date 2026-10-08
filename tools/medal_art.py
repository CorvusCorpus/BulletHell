#!/usr/bin/env python3
"""The rank medals, rendered. Imported by `make_ui.py`; run on its own it
writes only a preview sheet (`tools/_preview/ui_medals.png`).

It makes, one frame per rung of the ladder (STONE .. AMETHYST):

- the medal the rank card throws: its obverse, its reverse and its edge, which
  `medal_draw` turns into a coin spinning about its upright;
- the star a spell's medal is mounted on;
- the small medal a console socket holds (non-spells, then spells on their
  star), and the empty socket itself, at the console's size and the card's.

Each face is a height field (rims, cable, beading, relief, engraving, enamel
cells) shaded per pixel: metal reflects a studio (a softbox up and to the
left, a strip light to the right, a dark floor), polished or satin; enamel is
translucent over engine turning, with a glaze on top; a cut stone is a set of
planes, lit by what it reflects and by the pavilion seen through it; stone is
granite lit diffusely. Everything is in its final colours: none of this is
tinted at draw time.

Usage:
    python tools/medal_art.py          # preview only
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from PIL import ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A

TIERS = ["STONE", "BRONZE", "SILVER", "GOLD", "AMETHYST"]

# Sizes, in final pixels. `MEDAL_D`, `MEDAL_THICK`, `MARK_D` and `STAR_AXIS`
# are repeated in `scripts/constants` (`check_medal_sizes_agree`).
MEDAL_D = 216                 # the card's medal, drawn at scale 1
MEDAL_SIZE = MEDAL_D + 16
MEDAL_THICK = 15              # its edge, seen when it turns
STAR_R = 1.34                 # a spell's star: its longest points, in radii
STAR_AXIS = 1.16              # ...and its points above, below and beside it
STAR_SIZE = 2 * (int(round(MEDAL_D * 0.5 * STAR_R)) + 6)
MARK_D = 32                   # a console socket's medal
MARK_SIZE = 50                # holds the spell's star and the socket's ring
SOCKET_R = 1.20               # the socket's ring, in mark radii


# ---------------------------------------------------------------------------
# Light
# ---------------------------------------------------------------------------

def _unit(v):
    v = np.array(v, np.float32)
    return v / np.linalg.norm(v)


KEY = _unit((-0.52, -0.66, 0.54))      # the softbox, up and to the left
FILL = _unit((0.82, 0.08, 0.57))       # a weaker strip light to the right
KICK = _unit((0.36, 0.80, 0.48))       # a low kicker, so undersides aren't dead
LIGHT = _unit((-0.45, -0.60, 0.66))    # the diffuse light for satin and stone


def _ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def env(rx, ry, rz):
    """What a mirror sees looking along (rx, ry, rz): y is down the screen."""
    sky = 0.24 + 0.22 * (-ry)
    sky = sky * (1.0 - 0.6 * _ss(0.05, 0.32, ry))      # the floor is dark
    key = _ss(0.70, 0.94, rx * KEY[0] + ry * KEY[1] + rz * KEY[2]) * 1.20
    fill = _ss(0.72, 0.94, rx * FILL[0] + ry * FILL[1] + rz * FILL[2]) * 0.42
    kick = _ss(0.82, 0.97, rx * KICK[0] + ry * KICK[1] + rz * KICK[2]) * 0.30
    return sky + key + fill + kick


def ramp(stops, v):
    xs = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    out = np.empty(v.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(v, xs, cs[:, c])
    return out


# Each metal is a ramp from its deepest reflection to its hottest.
METALS = {
    "gold": [(0.00, (26, 12, 3)), (0.18, (80, 42, 10)), (0.40, (156, 100, 28)),
             (0.62, (214, 160, 60)), (0.84, (246, 210, 116)),
             (1.06, (255, 238, 180)), (1.45, (255, 252, 238))],
    "silver": [(0.00, (14, 16, 24)), (0.18, (52, 56, 70)),
               (0.40, (112, 118, 136)), (0.62, (168, 175, 192)),
               (0.84, (212, 218, 232)), (1.06, (240, 244, 252)),
               (1.45, (255, 255, 255))],
    "bronze": [(0.00, (22, 9, 3)), (0.18, (66, 30, 12)), (0.40, (128, 68, 32)),
               (0.62, (182, 110, 58)), (0.84, (222, 158, 98)),
               (1.06, (246, 206, 156)), (1.45, (255, 238, 214))],
    # The console's old gold, for the sockets.
    "gilt": [(0.00, (24, 15, 6)), (0.20, (78, 54, 22)), (0.45, (150, 112, 50)),
             (0.68, (200, 160, 80)), (0.90, (236, 206, 132)),
             (1.10, (252, 232, 176)), (1.45, (255, 248, 226))],
}

GEMS = {
    "amethyst": [(0.00, (14, 3, 30)), (0.22, (52, 12, 96)),
                 (0.46, (108, 40, 190)), (0.70, (168, 104, 246)),
                 (0.90, (214, 178, 255)), (1.15, (252, 244, 255))],
    "sapphire": [(0.00, (3, 5, 26)), (0.22, (10, 26, 100)),
                 (0.46, (34, 72, 200)), (0.70, (92, 142, 255)),
                 (0.90, (180, 210, 255)), (1.15, (250, 252, 255))],
    # The console's cyan, as a stone.
    "rune": [(0.00, (2, 14, 28)), (0.22, (6, 52, 92)), (0.46, (24, 132, 196)),
             (0.70, (90, 212, 255)), (0.90, (186, 244, 255)),
             (1.15, (252, 255, 255))],
}

# Enamels: the colour where it lies deep, and where the turning under it
# shows through.
ENAMELS = {
    "blue": ((8, 22, 84), (46, 104, 214)),
    "night": ((12, 8, 42), (54, 40, 132)),
    "violet": ((28, 6, 60), (124, 60, 212)),
    "violet_night": ((18, 5, 44), (80, 38, 156)),
}


# ---------------------------------------------------------------------------
# A face under construction
# ---------------------------------------------------------------------------

class Face:
    """One square picture of a round thing, at `ss` times its final size.

    Geometry is in units of the thing's radius (`radius` final pixels), with
    y down the screen. `h` is height in the same units, so a slope of 1 is 45
    degrees.
    """

    def __init__(self, size, radius, ss):
        self.size, self.ss = size, ss
        self.n = n = size * ss
        self.upx = radius * ss
        self.c = (n - 1) / 2.0
        ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
        self.X = (xs - self.c) / self.upx
        self.Y = (ys - self.c) / self.upx
        self.r = np.hypot(self.X, self.Y)
        self.th = np.arctan2(self.Y, self.X)
        self.h = np.zeros((n, n), np.float32)
        self.rough = np.zeros((n, n), np.float32)    # 0 mirror .. 1 satin
        self.enamel = np.zeros((n, n), bool)
        self.en_deep = np.zeros((n, n, 3), np.float32)
        self.en_lit = np.zeros((n, n, 3), np.float32)
        self.under = np.zeros((n, n), np.float32)    # turning under enamel
        self.over = np.zeros((n, n), bool)           # metal over a stone
        self.gems = []
        self.cover = np.clip((1.0 - self.r) * self.upx + 0.5, 0, 1)

    # --- masks -------------------------------------------------------------
    def pt(self, x, y):
        return (self.c + x * self.upx, self.c + y * self.upx)

    def polys(self, polys):
        img = Image.new("L", (self.n, self.n), 0)
        d = ImageDraw.Draw(img)
        for p in polys:
            d.polygon([self.pt(x, y) for x, y in p], fill=255)
        return np.asarray(img) > 127

    def lines(self, lines):
        """`lines` is [(points, width)], in units."""
        img = Image.new("L", (self.n, self.n), 0)
        d = ImageDraw.Draw(img)
        for pts, w in lines:
            d.line([self.pt(x, y) for x, y in pts], fill=255,
                   width=max(1, int(round(w * self.upx))))
        return np.asarray(img) > 127

    def disc(self, cx, cy, r):
        return np.hypot(self.X - cx, self.Y - cy) < r

    def ring(self, r0, r1):
        return (self.r >= r0) & (self.r < r1)

    def dist(self, m):
        """Distance from inside `m` to its edge, in units, from the pixels.
        Good enough for thin lines; a slanted edge comes out as a staircase,
        which a mirror finish shows, so shapes use the exact fields below."""
        return (ndimage.distance_transform_edt(m).astype(np.float32)
                / self.upx)

    def shape(self, polys):
        """Polygons as (mask, distance): the distance inside each polygon to
        its own edge, exactly, and the largest where polygons overlap (so
        each keeps its own spine)."""
        d = np.zeros((self.n, self.n), np.float32)
        for p in polys:
            xs = [q[0] for q in p]
            ys = [q[1] for q in p]
            x0, y0 = self.pt(min(xs), min(ys))
            x1, y1 = self.pt(max(xs), max(ys))
            sl = (slice(max(0, int(y0) - 2), min(self.n, int(y1) + 3)),
                  slice(max(0, int(x0) - 2), min(self.n, int(x1) + 3)))
            X, Y = self.X[sl], self.Y[sl]
            inside = np.zeros(X.shape, bool)
            best = np.full(X.shape, 1e9, np.float32)
            for i in range(len(p)):
                xa, ya = p[i]
                xb, yb = p[(i + 1) % len(p)]
                if (ya > Y).any() or (yb > Y).any():
                    cross = ((ya > Y) != (yb > Y))
                    with np.errstate(divide="ignore", invalid="ignore"):
                        xc = (xb - xa) * (Y - ya) / (yb - ya) + xa
                    inside ^= cross & (X < xc)
                ex, ey = xb - xa, yb - ya
                ll = ex * ex + ey * ey
                t = np.clip(((X - xa) * ex + (Y - ya) * ey) / max(ll, 1e-12),
                            0, 1)
                best = np.minimum(best, np.hypot(X - xa - t * ex,
                                                 Y - ya - t * ey))
            d[sl] = np.maximum(d[sl], np.where(inside, best, 0))
        return d > 0, d

    def round_(self, cx, cy, r):
        """A disc as (mask, distance)."""
        d = r - np.hypot(self.X - cx, self.Y - cy)
        return d > 0, np.maximum(d, 0)

    def crescent(self, cx, cy, r, bx, by, br):
        """A disc with a bite out of it, as (mask, distance)."""
        d = np.minimum(r - np.hypot(self.X - cx, self.Y - cy),
                       np.hypot(self.X - bx, self.Y - by) - br)
        return d > 0, np.maximum(d, 0)

    def _md(self, shape):
        if isinstance(shape, tuple):
            return shape
        if isinstance(shape, list):
            return self.shape(shape)
        return shape, self.dist(shape)

    # --- laying things down -------------------------------------------------
    def put(self, m, hh, rough=0.0, mode="max"):
        """Lay height `hh` over `m`: over what is there (`max`, raised work),
        or in place of it (`set`, a recess or a level)."""
        win = m & (hh >= self.h) if mode == "max" else m.copy()
        self.h[win] = hh[win] if np.ndim(hh) else hh
        self.rough[win] = rough
        self.enamel[win] = False
        return win

    def level(self, m, height, rough=0.0):
        return self.put(m, np.full_like(self.h, height), rough, "set")

    def band(self, r0, r1, height, base=0.0, rough=0.0):
        """A half-round band: a rim or a wire."""
        rc, w = (r0 + r1) / 2.0, (r1 - r0) / 2.0
        q = (self.r - rc) / w
        m = np.abs(q) < 1
        self.put(m, base + height * np.sqrt(np.clip(1 - q * q, 0, 1)), rough)
        return m

    def chamfer(self, r0, r1, top, bottom, rough=0.0):
        """A straight bevel falling from `top` at r0 to `bottom` at r1."""
        m = self.ring(r0, r1)
        f = np.clip((self.r - r0) / (r1 - r0), 0, 1)
        self.put(m, top + (bottom - top) * f, rough, "set")
        return m

    def cable(self, r0, r1, height, strands, twist=1.1, base=0.0, rough=0.0):
        """A twisted cable: a half-round band cut into diagonal strands."""
        rc, w = (r0 + r1) / 2.0, (r1 - r0) / 2.0
        q = (self.r - rc) / w
        m = np.abs(q) < 1
        ph = self.th / (2 * math.pi) * strands + q * twist * 0.5
        s = ph - np.floor(ph) - 0.5
        strand = np.sqrt(np.clip(1 - (2 * s) ** 2, 0, 1))
        prof = np.sqrt(np.clip(1 - q * q, 0, 1)) * (0.60 + 0.40 * strand)
        self.put(m, base + height * prof, rough)
        return m

    def beads(self, rr, n, rb, height, base=0.0, phase=0.0, rough=0.0,
              over=False):
        """A course of `n` round beads on the circle `rr`."""
        step = 2 * math.pi / n
        k = np.round((self.th - phase) / step)
        a = k * step + phase
        d = np.hypot(self.X - rr * np.cos(a), self.Y - rr * np.sin(a)) / rb
        m = d < 1
        win = self.put(m, base + height * np.sqrt(np.clip(1 - d * d, 0, 1)),
                       rough)
        if over:
            self.over |= win
        return m

    def relief(self, shape, height, base=0.0, profile="round", bevel=0.03,
               rough=0.0, mode="max"):
        """Raise a shape (a mask, polygons, or a (mask, distance) pair):
        `round` has a rounded shoulder and a flat top, `ridge` rises in
        straight facets to a sharp spine (a star's arms), `dome` swells to
        its thickest point."""
        m, d = self._md(shape)
        if profile == "round":
            t = np.clip(d / bevel, 0, 1)
            p = np.sqrt(1 - (1 - t) ** 2)
        elif profile == "ridge":
            p = d / max(float(d.max()), 1e-6)
        else:
            t = d / max(float(d.max()), 1e-6)
            p = np.sqrt(1 - (1 - t) ** 2)
        return self.put(m, base + height * p, rough, mode)

    def groove(self, m, depth):
        """Cut a V-groove along `m` (a line mask)."""
        d = self.dist(m)
        w = max(float(d.max()), 1e-6)
        self.h -= np.where(m, depth * np.clip(d / w, 0, 1), 0).astype(
            np.float32)

    def sink(self, shape, depth, bevel):
        """Carve a shape into the surface with sloped walls (sunk relief)."""
        m, d = self._md(shape)
        t = np.clip(d / bevel, 0, 1)
        self.h -= np.where(m, depth * t, 0).astype(np.float32)

    def enamel_fill(self, m, kind, level=-0.02, under=None):
        """Recess `m` and fill it with translucent enamel over `under`."""
        self.level(m, level, 0.0)
        self.enamel |= m
        deep, lit = ENAMELS[kind]
        self.en_deep[m] = deep
        self.en_lit[m] = lit
        if under is not None:
            self.under[m] = under[m]

    def gem(self, cx, cy, rg, kind, seed=0):
        self.gems.append((cx, cy, rg, kind, seed))

    # --- patterns -----------------------------------------------------------
    def sunburst(self, n, sharp=0.6):
        return np.abs(np.cos(self.th * n * 0.5)) ** sharp

    def barleycorn(self, rings, waves, amp):
        """Engine turning: concentric rings that wave round the circle."""
        return 0.5 + 0.5 * np.cos(2 * math.pi * (self.r * rings
                                                 + amp * np.cos(self.th * waves)))


# ---------------------------------------------------------------------------
# Shading
# ---------------------------------------------------------------------------

def _normals(face, blur=0.45):
    # Blurred by about half a final pixel: the distance transforms that build
    # the relief are exact only to a pixel, and a mirror shows every step.
    h = ndimage.gaussian_filter(face.h, blur * face.ss)
    gy, gx = np.gradient(h, 1.0 / face.upx)
    l = np.sqrt(gx * gx + gy * gy + 1.0)
    return h, -gx / l, -gy / l, 1.0 / l


def _cavity(face, h, reach=0.035, gain=26.0):
    """How far a point sits below its surroundings: grooves, cells and the
    foot of relief, which catch less light."""
    b = ndimage.gaussian_filter(h, reach * face.upx)
    return np.clip((b - h) * gain, 0, 1)


def shade_metal(face, metal):
    h, nx, ny, nz = _normals(face)
    rx, ry, rz = 2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1
    mirror = env(rx, ry, rz)
    lam = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    satin = 0.06 + 0.86 * lam + 0.10 * (-ny)
    rough = ndimage.gaussian_filter(face.rough, 0.5 * face.ss)
    val = mirror * (1 - rough) + satin * rough
    cav = _cavity(face, h)
    val = val * (1 - 0.62 * cav)
    col = ramp(METALS[metal], val)

    if face.enamel.any():
        col = _enamel(face, col, cav)
    for g in face.gems:
        _gem(face, col, *g)
    return col


def _enamel(face, col, cav):
    e = face.enamel
    under = ndimage.gaussian_filter(face.under, 0.35 * face.ss)
    body = face.en_deep + (face.en_lit - face.en_deep) * np.clip(
        0.10 + 0.78 * under, 0, 1)[..., None]
    # The glaze: it climbs the walls of its cell (a meniscus), which is where
    # it catches the softbox, and it carries a soft sheen across its flat.
    dw = face.dist(e)
    men = (np.clip(1 - dw / 0.05, 0, 1) ** 2 * 0.035).astype(np.float32)
    men = ndimage.gaussian_filter(men, 0.4 * face.ss)
    gy, gx = np.gradient(men, 1.0 / face.upx)
    l = np.sqrt(gx * gx + gy * gy + 1.0)
    nx, ny, nz = -gx / l, -gy / l, 1.0 / l
    rx, ry, rz = 2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1
    spec = _ss(0.86, 0.97, rx * KEY[0] + ry * KEY[1] + rz * KEY[2])
    sheen = np.clip(0.5 - 0.42 * (face.X + face.Y), 0, 1) ** 2
    glaze = 255.0 * (0.42 * spec + 0.05 * sheen)[..., None]
    shaded = body * (1 - 0.45 * cav)[..., None] + glaze
    return np.where(e[..., None], shaded, col)


# The crown of a round brilliant, as (azimuth, slope, height at the centre):
# its surface is the lowest of these planes, so the facets are their own
# polygons. The table's corners sit on the bezel azimuths at radius `C`, and
# the bezels reach the girdle at radius 1.
def _brilliant():
    c = 0.56
    sb = math.tan(math.radians(34.0))
    table = sb * (1 - c)
    planes = [(0.0, 0.0, table, 0)]
    for k in range(8):
        planes.append((k * 45.0, sb, table + sb * c, 1))
    ss = math.tan(math.radians(17.0))
    ap = c * math.cos(math.radians(22.5))
    for k in range(8):
        planes.append((k * 45.0 + 22.5, ss, table + ss * ap, 2))
    sg = math.tan(math.radians(43.0))
    for k in range(16):
        planes.append((k * 22.5 + 11.25, sg, sg * 1.035, 3))
    return planes


BRILLIANT = _brilliant()


def _gem(face, col, cx, cy, rg, kind, seed):
    x0, y0 = face.pt(cx - rg, cy - rg)
    x1, y1 = face.pt(cx + rg, cy + rg)
    sl = (slice(max(0, int(y0) - 1), min(face.n, int(y1) + 2)),
          slice(max(0, int(x0) - 1), min(face.n, int(x1) + 2)))
    u = (face.X[sl] - cx) / rg
    v = (face.Y[sl] - cy) / rg
    rho = np.hypot(u, v)

    hs = np.stack([h0 - s * (u * math.cos(math.radians(a))
                             + v * math.sin(math.radians(a)))
                   for a, s, h0, _ in BRILLIANT])
    idx = np.argmin(hs, axis=0)
    az = np.radians(np.array([p[0] for p in BRILLIANT], np.float32))[idx]
    sl_ = np.array([p[1] for p in BRILLIANT], np.float32)[idx]
    cls = np.array([p[3] for p in BRILLIANT])[idx]
    nx, ny = sl_ * np.cos(az), sl_ * np.sin(az)
    l = np.sqrt(nx * nx + ny * ny + 1)
    nx, ny, nz = nx / l, ny / l, 1 / l

    # What the crown reflects: the softbox, on the facets facing it, held
    # short of white so one facet can't blank out.
    rx, ry, rz = 2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1
    ext = np.minimum(0.85,
                     _ss(0.90, 0.985, rx * KEY[0] + ry * KEY[1] + rz * KEY[2])
                     * 1.1
                     + _ss(0.88, 0.98, rx * FILL[0] + ry * FILL[1]
                           + rz * FILL[2]) * 0.3)

    # What comes back out of it: the ray refracts in and crosses to the
    # pavilion, whose facets (eight mains and their halves, in rings) are
    # alternately lit and dark. A crown facet is a small prism, so it shows
    # the pavilion mirrored about its own azimuth: neighbouring facets show
    # opposite pieces of the pattern, which is a cut stone's kaleidoscope.
    eta = 1 / 1.6
    k = 1 - eta * eta * (1 - nz * nz)
    tt = eta * nz - np.sqrt(np.clip(k, 0, 1))
    tx, ty, tz = tt * nx, tt * ny, -eta + tt * nz
    depth = 1.3
    hx = u + tx / np.maximum(-tz, 0.2) * depth
    hy = v + ty / np.maximum(-tz, 0.2) * depth
    ha = np.arctan2(hy, hx)
    ha = np.where(cls > 0, 2 * az - ha, ha)
    hr = np.hypot(hx, hy)
    # Which pavilion facet the ray lands on. Eight mains run as narrow kites
    # from the culet to the girdle, and sixteen lower girdles fill between
    # them, meeting in a point far in toward the culet. Each is flat, so it
    # has one value: the two halves of a main differ, and the lower girdles
    # alternate round the stone. Seen through the table, the dark halves of
    # the mains are a brilliant's arrows.
    pm = np.mod(ha / (2 * math.pi / 8), 1.0)
    lower = hr > 0.24 + 1.5 * np.abs(pm - 0.5)
    half = pm < 0.5
    sec = np.floor(np.mod(ha, 2 * math.pi) / (2 * math.pi) * 8).astype(int)
    inner = np.where(lower, np.where(half, 0.86, 0.46),
                     np.where(half, 0.28, 0.66))
    inner = inner + 0.08 * (sec % 2) - 0.30 * (hr < 0.12)

    # Each class of facet, and alternate facets within it, sit at their own
    # value, so neighbours never merge.
    alt = (idx % 2).astype(np.float32)
    gain = np.select([cls == 0, cls == 1, cls == 2, cls == 3],
                     [1.00, 0.84 + 0.16 * alt, 1.06 - 0.22 * alt,
                      0.66 + 0.36 * alt])
    val = np.clip(inner, 0, 1) * gain + 0.06 + ext

    # Light along the junctions of the facets, which is what makes a cut read
    # as cut; darker and more saturated toward the girdle, which is a dark
    # hairline.
    w = max(1, face.ss // 4)
    e = np.zeros(idx.shape, bool)
    e[:-w, :] |= idx[:-w, :] != idx[w:, :]
    e[:, :-w] |= idx[:, :-w] != idx[:, w:]
    val = val + 0.16 * e
    val = val * (1 - 0.22 * rho ** 3) * (1 - 0.8 * _ss(0.93, 1.0, rho))
    g = ramp(GEMS[kind] if isinstance(kind, str) else kind, val)

    # Fire: a few of the small facets throw a spectral colour.
    rng = np.random.default_rng(seed + 11)
    hues = rng.random(len(BRILLIANT))
    fire = rng.random(len(BRILLIANT)) < 0.22
    fire &= np.array([p[3] in (2, 3) for p in BRILLIANT])
    fh = hues[idx]
    spec = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (fh - o))
                     for o in (0.0, 0.33, 0.67)], -1) * 255.0
    fm = (fire[idx] & (val > 0.55))[..., None]
    g = np.where(fm, g * 0.65 + spec * 0.35, g)

    m = (rho < 1.0) & ~face.over[sl]
    col[sl] = np.where(m[..., None], g, col[sl])


def granite(face, base, seed):
    """Close-grained granite: a slow mottle, black and white flecks."""
    rng = np.random.default_rng(seed)
    n = face.n

    def blob(sigma):
        g = ndimage.gaussian_filter(rng.standard_normal((n, n)).astype(
            np.float32), sigma)
        return (g - g.mean()) / max(1e-6, float(g.std()))

    s = float(face.ss)              # the grain is the same size at any scale
    mott = blob(20 * s) * 0.55 + blob(6 * s) * 0.45
    col = np.empty((n, n, 3), np.float32)
    col[:] = np.array(base, np.float32)
    col *= (1 + 0.07 * mott)[..., None]
    warm = np.clip(blob(14 * s), 0, None)[..., None]
    col += warm * np.array([6, 3, -2], np.float32)
    dark = _ss(1.35, 1.9, blob(0.9 * s))[..., None]
    light = _ss(1.55, 2.1, blob(0.8 * s))[..., None]
    col = col * (1 - 0.55 * dark)
    col = col * (1 - 0.55 * light) \
        + np.array((196, 196, 204), np.float32) * 0.55 * light
    return col


def shade_stone(face, base, seed):
    h, nx, ny, nz = _normals(face, 0.9)
    lam = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    hx, hy, hz = LIGHT[0], LIGHT[1], LIGHT[2] + 1
    hl = math.sqrt(hx * hx + hy * hy + hz * hz)
    spec = np.clip((nx * hx + ny * hy + nz * hz) / hl, 0, 1) ** 24
    cav = _cavity(face, h, 0.04, 30.0)
    light = (0.22 + 0.92 * lam) * (1 - 0.6 * cav)
    col = granite(face, base, seed) * light[..., None] + 38.0 * spec[..., None]
    return col


def finish(face, col, alpha=None, contour=0.012):
    """Darken the outermost edge (a contour, so the piece reads on anything),
    then reduce to final size: an exact box filter over premultiplied
    colour."""
    a = face.cover if alpha is None else alpha
    if contour:
        edge = _ss(1.0 - contour * 2.0, 1.0, face.r) * (face.r <= 1.0)
        col = col * (1 - 0.55 * edge)[..., None]
    col = np.clip(col, 0, 255)
    n, ss = face.n, face.ss
    m = n // ss
    pre = (col * a[..., None]).reshape(m, ss, m, ss, 3).mean(axis=(1, 3))
    al = a.reshape(m, ss, m, ss).mean(axis=(1, 3))
    rgb = pre / np.maximum(al, 1e-6)[..., None]
    return A.from_arrays(rgb, al)


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

def star(cx, cy, tips, waist, turn=-90.0):
    """A star with len(tips) points (each its own length) and a waist
    between each pair."""
    n = len(tips)
    pts = []
    for i in range(n * 2):
        a = math.radians(turn + i * 180.0 / n)
        rr = tips[i // 2] if i % 2 == 0 else waist
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


# ---------------------------------------------------------------------------
# The card's medals
# ---------------------------------------------------------------------------

METAL_OF = ["stone", "bronze", "silver", "gold", "gold"]
STONE_BASE = (112, 114, 126)


def _big():
    return Face(MEDAL_SIZE, MEDAL_D / 2.0, 4)


def front_stone():
    f = _big()
    f.level(f.r < 1.0, 0.06)
    f.chamfer(0.84, 1.0, 0.06, 0.0)
    ring = f.ring(0.765, 0.79)
    f.groove(ring, 0.035)
    # Eight notches pointing in, cut as small wedges.
    wedges = []
    for k in range(8):
        a = math.radians(k * 45.0 - 90.0)
        p = math.radians(90.0)
        cx, cy = math.cos(a), math.sin(a)
        px, py = math.cos(a + p), math.sin(a + p)
        wedges.append([(cx * 0.815 + px * 0.028, cy * 0.815 + py * 0.028),
                       (cx * 0.815 - px * 0.028, cy * 0.815 - py * 0.028),
                       (cx * 0.735, cy * 0.735)])
    f.sink(wedges, 0.05, 0.03)
    # The device, carved: a crescent holding a star.
    cr = f.crescent(-0.05, 0.04, 0.46, 0.11, -0.08, 0.39)
    f.sink(cr, 0.07, 0.05)
    f.sink([star(0.11, -0.08, [0.27] * 4, 0.075)], 0.07, 0.04)
    col = shade_stone(f, STONE_BASE, 3)
    return finish(f, col)


def front_bronze():
    f = _big()
    f.level(f.r < 1.0, 0.0, 0.55)
    f.band(0.855, 1.0, 0.085)
    f.band(0.822, 0.855, 0.028)
    f.beads(0.775, 28, 0.02, 0.032)
    f.groove(f.ring(0.728, 0.742), 0.012)
    # Rays engraved on the field behind the device.
    rays = []
    for k in range(48):
        a = math.radians(k * 7.5)
        rays.append(([(math.cos(a) * 0.22, math.sin(a) * 0.22),
                      (math.cos(a) * 0.68, math.sin(a) * 0.68)], 0.011))
    f.groove(f.lines(rays), 0.012)
    # The device: a four-pointed star over a second one turned 45 degrees.
    f.relief([star(0, 0, [0.36] * 4, 0.10, -45.0)], 0.07, 0.0,
             "ridge", rough=0.1)
    f.relief([star(0, 0, [0.58] * 4, 0.14)], 0.11, 0.0, "ridge",
             rough=0.0)
    return finish(f, shade_metal(f, "bronze"))


def _laurel(r, a0, a1, count, length, width, lean=30.0):
    """One branch of a laurel wreath along the circle `r`, from `a0` to `a1`
    degrees (y is down, so 90 is the foot): `count` leaves, alternately
    outside and inside the stem, leaning toward `a1` and shrinking as they
    go. Returns the leaves' outlines, their veins, and the stem's points."""
    leaves, veins, stem = [], [], []
    d = 1.0 if a1 > a0 else -1.0
    for i in range(count):
        f = (i + 0.5) / count
        a = math.radians(a0 + (a1 - a0) * f)
        px, py = math.cos(a) * r, math.sin(a) * r
        tx, ty = -math.sin(a) * d, math.cos(a) * d          # along the stem
        ox, oy = math.cos(a), math.sin(a)                   # outward
        sgn = 1.0 if i % 2 == 0 else -1.0
        sc = 1.0 - 0.30 * f
        la = math.radians(lean)
        lx = tx * math.cos(la) + ox * sgn * math.sin(la)
        ly = ty * math.cos(la) + oy * sgn * math.sin(la)
        L, W = length * sc, width * sc
        pts = []
        for k in range(25):
            tt = k / 12.0 if k <= 12 else (24 - k) / 12.0
            side = 1.0 if k <= 12 else -1.0
            # Fullest a third of the way along, then drawn out to a point.
            w = W * 0.5 * math.sin(math.pi * tt ** 0.8) ** 0.8 * side
            pts.append((px + lx * L * tt - ly * w, py + ly * L * tt + lx * w))
        leaves.append(pts)
        veins.append(([(px + lx * L * 0.12, py + ly * L * 0.12),
                       (px + lx * L * 0.82, py + ly * L * 0.82)], 0.010))
    for i in range(41):
        a = math.radians(a0 + (a1 - a0) * i / 40.0)
        stem.append((math.cos(a) * r, math.sin(a) * r))
    return leaves, veins, stem


def _collar(f, cx, cy, r0, r1, height, base):
    """A collar round a stone anywhere on the face (`band` is always centred
    on the medal). The stone is kept out from under it."""
    rr = np.hypot(f.X - cx, f.Y - cy)
    rc, w = (r0 + r1) / 2.0, (r1 - r0) / 2.0
    q = (rr - rc) / w
    m = np.abs(q) < 1
    f.put(m, base + height * np.sqrt(np.clip(1 - q * q, 0, 1)), 0.0)
    f.over |= (rr >= r0 + (r1 - r0) * 0.2) & (rr < r1 + 0.05)


def front_silver():
    f = _big()
    f.level(f.r < 1.0, 0.0, 0.2)
    f.band(0.87, 1.0, 0.085)
    f.beads(0.843, 48, 0.017, 0.028)
    f.band(0.806, 0.826, 0.02)
    # A polished field, finely engine-turned in rays.
    f.put(f.r < 0.806, (0.003 * f.sunburst(200, 1.0)).astype(np.float32),
          0.3, "set")
    # A frosted laurel wreath: two branches rising from the foot, open at the
    # head, with a small star where their stems cross.
    leaves, veins, stems = [], [], []
    for a0, a1 in ((100.0, 248.0), (80.0, -68.0)):
        lv, vn, st = _laurel(0.655, a0, a1, 15, 0.20, 0.088)
        leaves += lv
        veins += vn
        stems.append((st, 0.016))
    f.relief(f.lines(stems), 0.025, 0.0, "dome", rough=0.6)
    f.relief(leaves, 0.055, 0.0, "dome", rough=0.6)
    f.groove(f.lines(veins), 0.018)
    f.relief([star(0, 0.655, [0.075] * 4, 0.022)], 0.06, 0.0,
             "ridge")
    # The device: a faceted star over a smaller one turned half a point.
    f.relief([star(0, 0, [0.30] * 4, 0.085, -45.0)], 0.07, 0.0,
             "ridge", rough=0.3)
    f.relief([star(0, 0, [0.47] * 4, 0.12)], 0.11, 0.0, "ridge")
    return finish(f, shade_metal(f, "silver"))


def front_gold():
    f = _big()
    f.level(f.r < 1.0, 0.0, 0.4)
    f.cable(0.872, 1.0, 0.09, 44)
    f.beads(0.846, 52, 0.018, 0.03)
    f.band(0.812, 0.834, 0.022)
    # A glory: polished rays, long and short, on a satin ground cut with
    # finer rays.
    f.put(f.r < 0.812, (-0.015 + 0.003 * f.sunburst(240, 1.0)).astype(
        np.float32), 0.75, "set")
    rays = []
    for k in range(48):
        a = math.radians(k * 7.5 - 90)
        tip = 0.80 if k % 2 == 0 else 0.63
        half = 0.036 if k % 2 == 0 else 0.027
        p = a + math.pi / 2
        bx, by = math.cos(a) * 0.30, math.sin(a) * 0.30
        rays.append([(bx + math.cos(p) * half, by + math.sin(p) * half),
                     (math.cos(a) * tip, math.sin(a) * tip),
                     (bx - math.cos(p) * half, by - math.sin(p) * half)])
    f.relief(rays, 0.06, -0.015, "ridge")
    # At its heart a cut stone of the console's cyan, in a collar, held by
    # eight claws.
    f.band(0.245, 0.33, 0.07, 0.0)
    f.over |= f.r >= 0.252
    f.beads(0.258, 8, 0.03, 0.05, 0.035, math.radians(22.5), over=True)
    f.gem(0, 0, 0.27, "rune", 9)
    return finish(f, shade_metal(f, "gold"))


def front_amethyst():
    f = _big()
    f.level(f.r < 1.0, 0.0, 0.5)
    f.cable(0.872, 1.0, 0.09, 48)
    f.beads(0.846, 52, 0.018, 0.03)
    # The band: violet enamel, set with four amethysts, eight stars between
    # them and twelve pips.
    f.enamel_fill(f.ring(0.655, 0.826), "violet", -0.02, f.sunburst(144))
    f.band(0.814, 0.834, 0.024)
    f.band(0.634, 0.664, 0.03)
    stars, pips, stones = [], [], []
    for k in range(12):
        a = math.radians(k * 30 - 90)
        x, y = math.cos(a) * 0.742, math.sin(a) * 0.742
        if k % 3 == 0:
            stones.append((x, y))
        else:
            stars.append(star(x, y, [0.068] * 4, 0.02))
        b = a + math.radians(15)
        pips.append((math.cos(b) * 0.742, math.sin(b) * 0.742))
    f.relief(stars, 0.05, -0.02, "ridge")
    for x, y in pips:
        f.relief(f.round_(x, y, 0.016), 0.03, -0.02, "dome")
    for i, (x, y) in enumerate(stones):
        _collar(f, x, y, 0.05, 0.075, 0.04, -0.01)
        f.gem(x, y, 0.058, "amethyst", 20 + i)
    # The centre: a violet night, a crescent holding a star, and an amethyst
    # at the star's heart.
    centre = f.r < 0.636
    f.enamel_fill(centre, "violet_night", -0.02,
                  0.35 * f.barleycorn(18, 6, 0.08))
    rng = np.random.default_rng(7)
    for _ in range(26):
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.1, 0.58)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        if math.hypot(x + 0.05, y - 0.04) < 0.52 or rr > 0.57:
            continue
        f.relief(f.round_(x, y, rng.uniform(0.008, 0.014)), 0.02, -0.02,
                 "dome")
    cr = f.crescent(-0.05, 0.05, 0.45, 0.10, -0.07, 0.37)
    f.relief(cr, 0.10, -0.02, "dome", rough=0.0)
    f.relief([star(0.10, -0.07, [0.28] * 4, 0.075)], 0.10, -0.02,
             "ridge")
    _collar(f, 0.10, -0.07, 0.072, 0.108, 0.05, 0.06)
    f.gem(0.10, -0.07, 0.082, "amethyst", 9)
    return finish(f, shade_metal(f, "gold"))


FRONTS = [front_stone, front_bronze, front_silver, front_gold, front_amethyst]


def back(tier):
    """The reverse: the same rim, an engine-turned field (under its enamel,
    for the tiers that have one), and a boss engraved with the star."""
    f = _big()
    if tier == 0:
        f.level(f.r < 1.0, 0.06)
        f.chamfer(0.84, 1.0, 0.06, 0.0)
        for rr in (0.30, 0.52, 0.74):
            f.groove(f.ring(rr - 0.013, rr + 0.013), 0.03)
        f.sink([star(0, 0, [0.20] * 4, 0.055)], 0.06, 0.035)
        return finish(f, shade_stone(f, STONE_BASE, 4))
    metal = METAL_OF[tier]
    f.level(f.r < 1.0, 0.0, 0.3)
    if tier >= 3:
        f.cable(0.872, 1.0, 0.09, 44 if tier == 3 else 48)
    else:
        f.band(0.862, 1.0, 0.085)
    f.beads(0.842, 44, 0.019, 0.03)
    field = f.r < 0.815
    turned = f.barleycorn(30, 12, 0.045)
    enamel = {4: "violet_night"}.get(tier)
    if enamel:
        f.enamel_fill(field, enamel, -0.02, turned)
    else:
        f.put(field, (0.004 * turned).astype(np.float32), 0.2, "set")
    f.band(0.80, 0.826, 0.026)
    # The boss.
    f.relief(f.round_(0, 0, 0.24), 0.06, 0.0, "dome", rough=0.0)
    f.band(0.235, 0.265, 0.03)
    f.groove(f.lines([([(0, -0.17), (0, 0.17)], 0.018),
                      ([(-0.17, 0), (0.17, 0)], 0.018)]), 0.02)
    f.groove(f.lines([([(-0.07, -0.07), (0.07, 0.07)], 0.012),
                      ([(-0.07, 0.07), (0.07, -0.07)], 0.012)]), 0.015)
    return finish(f, shade_metal(f, metal))


def edge(tier):
    """The medal's edge, for the spin: a disc whose colour is that of a
    reeded cylinder at each height (only a sliver of it shows at a time, so
    the colour need only vary with height)."""
    f = _big()
    t = np.clip(f.Y, -0.999, 0.999)
    nz = np.sqrt(1 - t * t)
    ny = t
    ry, rz = 2 * nz * ny, 2 * nz * nz - 1
    phi = np.arcsin(t)
    if tier == 0:
        lam = np.clip(ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
        col = granite(f, STONE_BASE, 5) * (0.2 + 0.8 * lam)[..., None]
        return finish(f, col, contour=0)
    val = env(np.zeros_like(ry), ry, rz)
    val = val * (0.80 + 0.20 * (0.5 + 0.5 * np.cos(phi * 110)))
    return finish(f, ramp(METALS[METAL_OF[tier]], val), contour=0)


# A spell's star: (tip, half-width at the centre) for its four long points
# on the diagonals, its four on the axes, and eight small ones between.
STAR_BIG = ((STAR_R, 0.30), (STAR_AXIS, 0.24), (1.05, 0.13))
STAR_MINI = ((1.52, 0.46), (1.32, 0.32), None)


def star_mount(tier, size=STAR_SIZE, radius=MEDAL_D / 2.0, ss=4,
               points=STAR_BIG):
    """The star a spell's medal is mounted on: faceted points in the medal's
    metal (stone for STONE). Only what shows past the medal matters."""
    f = Face(size, radius, ss)
    polys = []
    for k in range(16):
        spec = (points[0] if k % 4 == 2 else points[1]) if k % 2 == 0             else points[2]
        if spec is None:
            continue
        tip, w = spec
        a = math.radians(k * 22.5 - 90)
        p = a + math.pi / 2
        polys.append([(math.cos(p) * w, math.sin(p) * w),
                      (math.cos(a) * tip, math.sin(a) * tip),
                      (-math.cos(p) * w, -math.sin(p) * w)])
    m, d = f.shape(polys)
    f.h = np.where(m, d * 0.9, 0).astype(np.float32)
    f.rough[:] = 0.0
    alpha = m.astype(np.float32)
    if tier == 0:
        col = shade_stone(f, STONE_BASE, 6)
    else:
        col = shade_metal(f, METAL_OF[tier])
    # A dark contour, so the points read against the plate and each other.
    edge = (d < 0.5 / radius) & m
    col = col * (1 - 0.5 * edge)[..., None]
    return finish(f, col, alpha, contour=0)


# ---------------------------------------------------------------------------
# The console's medals
# ---------------------------------------------------------------------------

def _mini():
    return Face(MARK_SIZE, MARK_D / 2.0, 8)


def mini(tier):
    """The console's medal: each tier's own design, cut down to what reads
    at 32 pixels."""
    f = _mini()
    if tier == 0:
        f.level(f.r < 1.0, 0.08)
        f.chamfer(0.72, 1.0, 0.08, 0.0)
        f.sink([star(0, 0, [0.58] * 4, 0.16)], 0.10, 0.07)
        return finish(f, shade_stone(f, STONE_BASE, 8), contour=0.04)
    metal = METAL_OF[tier]
    f.level(f.r < 1.0, 0.0, 0.5)
    f.band(0.74, 1.0, 0.13)
    if tier == 1:
        f.relief([star(0, 0, [0.64] * 4, 0.17)], 0.16, 0.0,
                 "ridge")
    elif tier == 2:
        f.rough[f.r < 0.74] = 0.35
        f.relief([star(0, 0, [0.40] * 4, 0.11, -45.0)], 0.10, 0.0,
                 "ridge")
        f.relief([star(0, 0, [0.62] * 4, 0.15)], 0.16, 0.0,
                 "ridge")
    elif tier == 3:
        f.put(f.r < 0.74, np.full_like(f.h, -0.02), 0.75, "set")
        rays = []
        for k in range(16):
            a = math.radians(k * 22.5 - 90)
            tip = 0.72 if k % 2 == 0 else 0.56
            half = 0.10 if k % 2 == 0 else 0.075
            p = a + math.pi / 2
            bx, by = math.cos(a) * 0.3, math.sin(a) * 0.3
            rays.append([(bx + math.cos(p) * half, by + math.sin(p) * half),
                         (math.cos(a) * tip, math.sin(a) * tip),
                         (bx - math.cos(p) * half, by - math.sin(p) * half)])
        f.relief(rays, 0.10, -0.02, "ridge")
        f.band(0.28, 0.42, 0.10)
        f.over |= f.r >= 0.30
        f.gem(0, 0, 0.33, "rune", 3)
    else:
        f.enamel_fill(f.r < 0.75, "violet_night", -0.02, 0.3 + 0 * f.r)
        cr = f.crescent(-0.08, 0.07, 0.56, 0.13, -0.10, 0.46)
        f.relief(cr, 0.14, -0.02, "dome")
        f.relief([star(0.13, -0.10, [0.33] * 4, 0.09)], 0.14,
                 -0.02, "ridge")
    return finish(f, shade_metal(f, metal), contour=0.04)


def mini_star(tier):
    return star_mount(tier, MARK_SIZE, MARK_D / 2.0, 8, STAR_MINI)


def socket(size, radius, ss, ring=SOCKET_R):
    """An empty socket in the plate: a gilt ring round a recess of the
    console's indigo, shadowed from the upper left."""
    f = Face(size, radius, ss)
    inside = f.r < 1.0
    f.level(inside, -0.10, 1.0)
    rim = f.band(0.98, ring, 0.09)
    col_m = shade_metal(f, "gilt")
    # The recess: indigo, lit from the light's side and shadowed under the
    # rim on the other.
    ground = np.array(A.ARCANE, np.float32) * 0.62
    lit = np.clip(0.55 + 0.5 * (f.X * -LIGHT[0] + f.Y * -LIGHT[1]) * 0.6,
                  0.2, 1.1)
    shadow = ndimage.shift(rim.astype(np.float32),
                           (0.10 * f.upx, 0.10 * f.upx), order=1)
    shadow = ndimage.gaussian_filter(shadow, 0.06 * f.upx)
    rec = ground * (lit * (1 - 0.7 * shadow))[..., None]
    col = np.where(rim[..., None], col_m, rec)
    alpha = np.clip((ring - f.r) * f.upx + 0.5, 0, 1)
    return finish(f, col, alpha, contour=0)


# ---------------------------------------------------------------------------
# Building the lot
# ---------------------------------------------------------------------------

def build():
    """Every picture, as a dict of frame lists."""
    out = {"front": [], "back": [], "edge": [], "star": [], "mark": [],
           "mark_star": []}
    for t in range(len(TIERS)):
        out["front"].append(FRONTS[t]())
        out["back"].append(back(t))
        out["edge"].append(edge(t))
        out["star"].append(star_mount(t))
        out["mark"].append(mini(t))
        out["mark_star"].append(mini_star(t))
    # The console's marks: non-spells, then spells on their stars.
    marks = out["mark"] + [A.over(out["mark_star"][t], out["mark"][t])
                           for t in range(len(TIERS))]
    out["marks"] = marks
    out["socket"] = socket(MARK_SIZE, MARK_D / 2.0, 8)
    out["socket_big"] = socket(MEDAL_SIZE, MEDAL_D / 2.0 / 1.06, 4, 1.06)
    return out


def spin(front, back_, edge_, turn, star_=None, thick=MEDAL_THICK):
    """What `medal_draw` draws at `turn` degrees: for the preview."""
    w, h = front.size
    cw = star_.size[0] if star_ else w
    canvas = Image.new("RGBA", (cw, cw), (0, 0, 0, 0))
    c = math.cos(math.radians(turn))
    s = math.sin(math.radians(turn))
    xs = max(abs(c), 0.02)
    half = thick * 0.5 * s

    def put(img, dx, gain=1.0):
        iw = max(1, int(round(img.size[0] * xs)))
        im = img.resize((iw, img.size[1]), Image.LANCZOS)
        if gain != 1.0:
            arr = np.asarray(im, np.float32)
            arr[..., :3] *= gain
            im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        canvas.alpha_composite(im, (int(round(cw / 2 + dx - iw / 2)),
                                    int(round(cw / 2 - img.size[1] / 2))))

    if star_:
        put(star_, 0)
    n = int(math.ceil(abs(half) * 2 / 1.2))
    for k in range(n + 1):
        put(edge_, -half + 2 * half * k / max(1, n))
    face = front if c >= 0 else back_
    put(face, half if c >= 0 else -half,
        0.4 + 0.6 * max(0.0, (-0.5 * s + 0.62 * c) / 0.62
                        if c >= 0 else (0.5 * s - 0.62 * c) / 0.62))
    return canvas


def preview(out, path=None):
    path = path or os.path.join(A.PREVIEW, "ui_medals.png")
    ground = A.mix(A.ARCANE, (0, 0, 0), 0.35)

    def cell(img, scale=1.0, size=None):
        if scale != 1.0:
            img = img.resize((max(1, int(img.width * scale)),
                              max(1, int(img.height * scale))), Image.LANCZOS)
        sz = size or (img.width + 16, img.height + 16)
        c = Image.new("RGBA", sz, tuple(ground) + (255,))
        c.alpha_composite(img, ((sz[0] - img.width) // 2,
                                (sz[1] - img.height) // 2))
        return c

    imgs, labels = [], []
    for t, name in enumerate(TIERS):
        imgs.append(cell(out["front"][t], size=(312, 312)))
        labels.append(name)
        imgs.append(cell(A.over(out["star"][t],
                                _centred(out["front"][t], STAR_SIZE)),
                         size=(312, 312)))
        labels.append(name.lower() + " spell")
        imgs.append(cell(out["back"][t], size=(312, 312)))
        labels.append("reverse")
        for turn in (38, 70, 118):
            imgs.append(cell(spin(out["front"][t], out["back"][t],
                                  out["edge"][t], turn), size=(312, 312)))
            labels.append("turned %d" % turn)
    A.preview(imgs, path, cols=6, bg=(10, 8, 20), labels=labels)

    # The console row, at 1x and 3x: sockets, then each tier seated in one.
    row = Image.new("RGBA", (MARK_SIZE * 12, MARK_SIZE * 2 + 8),
                    tuple(ground) + (255,))
    for i in range(11):
        x = i * MARK_SIZE + 4
        for j, spell in enumerate((False, True)):
            y = j * (MARK_SIZE + 4) + 4
            row.alpha_composite(out["socket"], (x, y))
            if i < 10:
                t = i % 5
                idx = t + (5 if (i >= 5) != spell else 0)
                row.alpha_composite(out["marks"][idx], (x, y))
    big = row.resize((row.width * 3, row.height * 3), Image.NEAREST)
    sheet = Image.new("RGBA", (big.width, row.height + big.height + 30),
                      (10, 8, 20, 255))
    sheet.alpha_composite(row, (0, 0))
    sheet.alpha_composite(big, (0, row.height + 30))
    sheet.save(path.replace(".png", "_marks.png"))
    return path


def _centred(img, size):
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c.alpha_composite(img, ((size - img.width) // 2, (size - img.height) // 2))
    return c


if __name__ == "__main__":
    o = build()
    p = preview(o)
    print("->  %s" % os.path.relpath(p, A.ROOT))
