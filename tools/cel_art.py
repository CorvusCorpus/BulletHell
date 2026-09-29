#!/usr/bin/env python3
"""2D sprite illustration in code: cel-shaded parts with line work.
Importable only; used by `make_sanctum_foes.py` and `make_titles.py`.

Gameplay sprites are 2D art over a 3D stage (the owner's arrangement, as in
Touhou), so nothing here lights a model. A sprite is a stack of parts painted
back to front on a `Sheet` at `SS` times its final size. A part is a mask (what
it covers) and a colour ramp (`Ramp`: deep, shade, base, light, glint), and is
painted as a 2D artist paints one:

- its base colour, with a soft wash lighter toward the light;
- a shade band along the edges turned away from the light, found by testing
  the mask against itself moved toward the light, and a deep core to it;
- a lit rim along the edges facing the light;
- line work: a dark line round it, so where it overlaps a part painted
  earlier the join is drawn.

The light is from the upper left, as everywhere in the game. Detail inside a
part (tooling, seams, feathers, flow lines) is drawn as further parts or as
strokes. Coordinates are final pixels from the sheet's origin, y down.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

import art_common as A

SS = 4

# Toward the light, as a unit vector (up and to the left).
LIGHT = (-0.62, -0.78)


class Ramp:
    """A material's colours, darkest to brightest, and its line colour."""

    def __init__(self, deep, shade, base, light, glint=None, line=None):
        self.deep = np.array(deep, np.float32)
        self.shade = np.array(shade, np.float32)
        self.base = np.array(base, np.float32)
        self.light = np.array(light, np.float32)
        self.glint = np.array(glint if glint else light, np.float32)
        self.line = np.array(line if line else
                             tuple(int(c * 0.30) for c in deep), np.float32)


GOLD = Ramp((86, 44, 12), (168, 104, 34), (226, 170, 66), (255, 226, 140),
            (255, 250, 222), (44, 20, 6))
GOLD_DIM = Ramp((70, 36, 10), (136, 84, 28), (188, 138, 54), (236, 196, 112),
                (255, 236, 190), (40, 18, 6))
LAPIS = Ramp((10, 14, 50), (20, 32, 98), (36, 58, 150), (78, 110, 206),
             (170, 196, 255), (6, 6, 24))
TURQUOISE = Ramp((8, 64, 72), (22, 132, 136), (48, 196, 186), (150, 246, 232),
                 (235, 255, 252), (4, 30, 34))
CARNELIAN = Ramp((78, 14, 6), (150, 38, 14), (214, 82, 34), (255, 158, 98),
                 (255, 230, 200), (40, 6, 2))
CRIMSON = Ramp((60, 6, 18), (120, 16, 34), (178, 30, 52), (232, 90, 104),
               (255, 190, 196), (30, 2, 8))
SAND = Ramp((88, 52, 26), (150, 100, 52), (206, 158, 96), (240, 208, 148),
            (255, 238, 196), (52, 28, 12))
PARCHMENT = Ramp((116, 92, 58), (190, 164, 120), (234, 218, 182),
                 (252, 244, 220), (255, 255, 246), (70, 52, 30))


class Sheet:
    """An RGBA canvas `w` by `h` final pixels, with (0, 0) at `origin`,
    painted at `SS` times that size in premultiplied colour."""

    def __init__(self, w, h, origin=None, ss=SS):
        self.w, self.h, self.ss = int(w), int(h), ss
        self.ox, self.oy = (w / 2.0, h / 2.0) if origin is None else origin
        self.W, self.H = self.w * ss, self.h * ss
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)   # premultiplied
        self.a = np.zeros((self.H, self.W), np.float32)
        ys, xs = np.mgrid[0:self.H, 0:self.W].astype(np.float32)
        self.X = (xs + 0.5) / ss - self.ox
        self.Y = (ys + 0.5) / ss - self.oy

    # -- coordinates and masks ---------------------------------------------

    def p(self, x, y):
        return ((x + self.ox) * self.ss, (y + self.oy) * self.ss)

    def pts(self, pts):
        return [self.p(x, y) for x, y in pts]

    def canvas(self):
        """A blank mask to draw on, and its `ImageDraw`."""
        img = Image.new("L", (self.W, self.H), 0)
        return img, ImageDraw.Draw(img)

    def m(self, img):
        """A mask image as a 0..1 array."""
        return np.asarray(img, np.float32) / 255.0

    def poly(self, pts, smooth=False, n=8):
        img, d = self.canvas()
        if smooth:
            import sanctum_glyphs as GL
            pts = GL.catmull(pts, n=n, closed=True)
        d.polygon(self.pts(pts), fill=255)
        return self.m(img)

    def ellipse(self, cx, cy, rx, ry, angle=0.0, n=96):
        pts = []
        c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        for k in range(n):
            t = 2 * math.pi * k / n
            x, y = rx * math.cos(t), ry * math.sin(t)
            pts.append((cx + x * c - y * s, cy + x * s + y * c))
        return self.poly(pts)

    def circle(self, cx, cy, r):
        return self.ellipse(cx, cy, r, r, 0, max(24, int(r * 3)))

    def stroke(self, pts, w0, w1=None, taper=0.0):
        """A stroke through the points, `w0` to `w1` final pixels wide,
        thinned toward both ends by `taper`, as overlapping discs."""
        img, d = self.canvas()
        w1 = w0 if w1 is None else w1
        P = [self.p(x, y) for x, y in pts]
        seg = [math.hypot(P[i + 1][0] - P[i][0], P[i + 1][1] - P[i][1])
               for i in range(len(P) - 1)]
        tot = max(sum(seg), 1e-6)
        acc = 0.0
        step = max(0.6, min(w0, w1) * self.ss * 0.25)
        for i in range(len(P) - 1):
            k = max(1, int(math.ceil(seg[i] / step)))
            for j in range(k + 1):
                t = j / k
                f = (acc + seg[i] * t) / tot
                w = (w0 + (w1 - w0) * f) * self.ss
                if taper:
                    w *= 1 - taper * (1 - math.sin(math.pi * f))
                r = max(0.5, w * 0.5)
                x = P[i][0] + (P[i + 1][0] - P[i][0]) * t
                y = P[i][1] + (P[i + 1][1] - P[i][1]) * t
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
            acc += seg[i]
        return self.m(img)

    # -- mask arithmetic -----------------------------------------------------

    def shift(self, mask, dx, dy):
        """The mask moved by (`dx`, `dy`) final pixels (sub-pixel)."""
        return ndimage.shift(mask, (dy * self.ss, dx * self.ss), order=1,
                             mode="constant", cval=0.0)

    def soften(self, mask, r):
        return ndimage.gaussian_filter(mask, r * self.ss) if r > 0 else mask

    def ring(self, mask, w):
        """Coverage of a line `w` final pixels wide round the outside of
        `mask`, antialiased."""
        inside = mask > 0.5
        d = ndimage.distance_transform_edt(~inside) / self.ss
        return np.clip(w - d + 0.5 / self.ss, 0, 1) * (~inside)

    # -- painting ------------------------------------------------------------

    def bbox(self, mask, pad):
        """The slices round where `mask` is set, `pad` final pixels wider, or
        `None` if it is empty. Painting works inside this, which keeps small
        parts on a large sheet cheap."""
        rows = np.any(mask > 0.001, axis=1)
        if not rows.any():
            return None
        cols = np.any(mask > 0.001, axis=0)
        r0 = int(np.argmax(rows))
        r1 = len(rows) - int(np.argmax(rows[::-1]))
        c0 = int(np.argmax(cols))
        c1 = len(cols) - int(np.argmax(cols[::-1]))
        p = int(math.ceil(pad * self.ss)) + 2
        return (slice(max(0, r0 - p), min(self.H, r1 + p)),
                slice(max(0, c0 - p), min(self.W, c1 + p)))

    def over(self, col, a, sl=None):
        """Lay colour `col` (an RGB triple or an array) at coverage `a`;
        within slices `sl` if given (then `a`, and `col` if it is an array,
        are that size)."""
        col = np.asarray(col, np.float32)
        if col.ndim == 1:
            col = col[None, None, :]
        a = np.clip(a, 0, 1)
        if sl is None:
            self.rgb = col * a[..., None] + self.rgb * (1 - a[..., None])
            self.a = a + self.a * (1 - a)
        else:
            self.rgb[sl] = col * a[..., None] + self.rgb[sl] * (1 - a[..., None])
            self.a[sl] = a + self.a[sl] * (1 - a)

    def add(self, col, a):
        """Add light (for glows painted into the art itself)."""
        col = np.asarray(col, np.float32)
        if col.ndim == 1:
            col = col[None, None, :]
        self.rgb = self.rgb + col * np.clip(a, 0, 1)[..., None]

    def part(self, mask, ramp, band=3.0, rim=1.2, line=1.3, wash=0.35,
             deep=0.45, soft=0.35, alpha=1.0, line_alpha=0.95, light=LIGHT):
        """Paint one cel-shaded part (see the module's docstring). `band` is
        how deep the shade runs in from the edges away from the light,
        `rim` how wide the lit edge is, `line` the line work's weight (0 for
        none), `wash` how much lighter it is toward the light across its
        width, and `deep` how much of the shade band's far edge falls to the
        ramp's deepest colour."""
        sl = self.bbox(mask, max(band, rim) + line + 3 * soft + 2)
        if sl is None:
            return mask
        m = np.clip(mask[sl], 0, 1)
        X, Y = self.X[sl], self.Y[sl]
        lx, ly = light

        # The wash: lighter toward the light across the part's own extent.
        ys, xs = np.nonzero(m > 0.5)
        if len(xs):
            span = max(np.ptp(xs), np.ptp(ys), 1) / self.ss
            cx = X[ys, xs].mean()
            cy = Y[ys, xs].mean()
            t = np.clip(((X - cx) * lx + (Y - cy) * ly) / (span * 0.5), -1, 1)
        else:
            t = np.zeros_like(m)
        col = np.empty(m.shape + (3,), np.float32)
        col[:] = ramp.base
        col += (ramp.light - ramp.base) * (np.clip(t, 0, 1) * wash)[..., None]
        col += (ramp.shade - ramp.base) * (np.clip(-t, 0, 1) * wash)[..., None]

        # The shade band: what the part does not cover when moved toward the
        # light, and a deeper core at the very edge.
        toward = self.soften(self.shift(m, lx * band, ly * band), soft)
        shade = np.clip(1 - toward, 0, 1) * m
        edge = self.soften(self.shift(m, lx * band * 0.4, ly * band * 0.4),
                           soft)
        core = np.clip(1 - edge, 0, 1) * m * deep
        col += (ramp.shade - col) * shade[..., None]
        col += (ramp.deep - col) * core[..., None]

        # The lit rim: what the part does not cover when moved away.
        if rim > 0:
            away = self.soften(self.shift(m, -lx * rim, -ly * rim), soft * 0.6)
            lit = np.clip(1 - away, 0, 1) * m * (1 - shade)
            col += (ramp.light - col) * lit[..., None]

        self.over(col, m * alpha, sl)
        if line > 0:
            self.over(ramp.line, self.ring(m, line) * line_alpha * alpha, sl)
        return mask

    def lines(self, mask, col, alpha=1.0):
        """Paint strokes (a mask from `stroke`) in one colour."""
        self.over(col, mask * alpha)

    def outline(self, w=1.4, col=(10, 8, 18), alpha=0.9):
        """A line round the whole sprite's silhouette, under it."""
        m = (self.a > 0.45).astype(np.float32)
        ring = self.ring(m, w) * alpha
        col = np.asarray(col, np.float32)[None, None, :]
        # Under: added behind what is there.
        self.rgb = self.rgb + col * (ring * (1 - self.a))[..., None]
        self.a = self.a + ring * (1 - self.a)

    # -- output --------------------------------------------------------------

    def finish(self):
        """Reduce to the final size (a box filter over premultiplied
        colour). Returns an RGBA image."""
        ss, h, w = self.ss, self.h, self.w
        pre = np.clip(self.rgb, 0, 255).reshape(h, ss, w, ss, 3).mean(
            axis=(1, 3))
        al = np.clip(self.a, 0, 1).reshape(h, ss, w, ss).mean(axis=(1, 3))
        rgb = pre / np.maximum(al, 1e-6)[..., None]
        return A.from_arrays(rgb, al)


def warp_quad(src, dst_size, quad):
    """Warp image `src` onto the quadrilateral `quad` ((x, y) for its
    top-left, top-right, bottom-right and bottom-left corners, in pixels of
    an output `dst_size`), the way a 2D artist foreshortens a flat panel.
    Returns an RGBA image of `dst_size`."""
    sw, sh = src.size
    srcq = [(0, 0), (sw, 0), (sw, sh), (0, sh)]
    # Perspective coefficients mapping output pixels to source pixels.
    rows, rhs = [], []
    for (x, y), (u, v) in zip(quad, srcq):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        rhs.append(v)
    coef = np.linalg.solve(np.array(rows, np.float64), np.array(rhs, np.float64))
    # Premultiply, so the warp's filtering doesn't bleed transparent black.
    arr = np.asarray(src.convert("RGBA"), np.float32)
    pre = arr.copy()
    pre[..., :3] *= arr[..., 3:4] / 255.0
    im = Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8), "RGBA")
    out = im.transform(dst_size, Image.PERSPECTIVE, tuple(coef),
                       Image.BICUBIC)
    o = np.asarray(out, np.float32)
    a = o[..., 3:4]
    o[..., :3] = o[..., :3] * 255.0 / np.maximum(a, 1e-3)
    return Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), "RGBA")
