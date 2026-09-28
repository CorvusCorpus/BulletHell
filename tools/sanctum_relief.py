#!/usr/bin/env python3
"""Stone, gold and carving for Mika's hall: the material side of its
textures. Imported by `make_sanctum.py`.

A `Plate` is one texture under construction at a supersampled size. Its
ornament is drawn as masks (`sanctum_glyphs`), and each mask is applied as a
kind of work:

- `inlay`: gold set flush into the stone, its edge eased;
- `carve`: sunk relief, cut into the stone with its floor gilded (the walls);
- `raise_`: raised relief in the stone itself;
- `groove`: an incised line.

Those build a height field, a gold coverage and a gloss. `finish` lights the
height field gently from the upper left (the hall's own lights do the real
lighting, per pixel, in `sh_hall`, so this is only enough for a carving to
read), darkens the recesses, and puts the gloss in the alpha: polished stone
up to about 0.6, gold 0.95 and over, which `sh_hall` reads as metal.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

import sanctum_glyphs as G

# Gold, as three stops of one metal: in shadow, lit, and at its highlight.
GOLD_DARK = np.array([66, 48, 22], np.float32)
GOLD_MID = np.array([184, 148, 84], np.float32)
GOLD_HOT = np.array([248, 228, 178], np.float32)

# The light the relief is modelled by: from the upper left and toward the
# viewer. Flat stone is left as it is.
LIGHT = np.array([-0.42, -0.58, 0.70], np.float32)
LIGHT /= np.linalg.norm(LIGHT)


def smooth01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def noise(w, h, seed, scale, octaves=4):
    """Fractal noise, tiling in both directions (built in the frequency
    domain), 0..1."""
    r = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.hypot(fx, fy)
    for o in range(octaves):
        s = scale / (2 ** o)
        f = np.fft.fft2(r.normal(0, 1, (h, w)))
        f *= np.exp(-(k * s) ** 2 * 2.0)
        n = np.real(np.fft.ifft2(f))
        n = (n - n.mean()) / max(1e-6, n.std())
        acc += n * amp
        tot += amp
        amp *= 0.55
    acc /= tot
    acc = (acc - acc.min()) / max(1e-6, acc.max() - acc.min())
    return acc.astype(np.float32)


class Plate:
    def __init__(self, w, h, ss=3, stone=(20, 20, 26), gloss=0.45):
        self.w, self.h, self.ss = w, h, ss
        self.W, self.H = w * ss, h * ss
        self.hgt = np.zeros((self.H, self.W), np.float32)
        self.gold = np.zeros((self.H, self.W), np.float32)
        self.stone = np.empty((self.H, self.W, 3), np.float32)
        self.stone[:] = np.array(stone, np.float32)
        self.gloss = np.full((self.H, self.W), gloss, np.float32)
        self.gold_gloss = 0.97

    # --- drawing -------------------------------------------------------
    def mask(self):
        """A blank mask at the plate's working size, and a drawer for it."""
        m = Image.new("L", (self.W, self.H), 0)
        return m, ImageDraw.Draw(m)

    def px(self, v):
        """Final texels to working pixels."""
        return v * self.ss

    @staticmethod
    def arr(m):
        return np.asarray(m, np.float32) / 255.0

    def _depth(self, a):
        """Distance inside the mask, in final texels."""
        return ndimage.distance_transform_edt(a > 0.5) / self.ss

    def outline(self, m, width):
        """The band `width` final texels wide just inside the shapes of a
        mask: how a form is drawn in inlaid metal strip rather than filled."""
        a = self.arr(m) > 0.5
        d = ndimage.distance_transform_edt(a)
        band = a & (d <= width * self.ss)
        return Image.fromarray((band * 255).astype(np.uint8), "L")

    # --- the kinds of work --------------------------------------------
    def inlay(self, m, bevel=0.9, lift=0.35, gloss=None):
        """Gold flush in the stone, with an eased edge (a little proud, so
        it catches the light along its rim)."""
        a = self.arr(m)
        prof = smooth01(self._depth(a) / max(bevel, 1e-3))
        self.hgt += prof * lift
        self.gold = np.maximum(self.gold, a)
        self.gloss = np.where(a > 0.5, gloss or self.gold_gloss, self.gloss)

    def carve(self, m, depth=2.2, bevel=1.2, gild=True):
        """Sunk relief: cut in, with sloped walls of stone and a gilded
        floor."""
        a = self.arr(m)
        d = self._depth(a)
        prof = smooth01(d / max(bevel, 1e-3))
        self.hgt -= prof * depth
        if gild:
            g = smooth01((d - bevel * 0.45) / max(bevel * 0.4, 1e-3))
            self.gold = np.maximum(self.gold, g)
            self.gloss = np.where(g > 0.5, self.gold_gloss, self.gloss)

    def raise_(self, m, height=1.6, bevel=1.4, gild=False):
        """Raised relief."""
        a = self.arr(m)
        prof = smooth01(self._depth(a) / max(bevel, 1e-3))
        self.hgt += prof * height
        if gild:
            self.gold = np.maximum(self.gold, a)
            self.gloss = np.where(a > 0.5, self.gold_gloss, self.gloss)

    def groove(self, m, depth=0.9):
        """An incised line, V-cut."""
        a = self.arr(m)
        a = np.asarray(Image.fromarray((a * 255).astype(np.uint8))
                       .filter(ImageFilter.GaussianBlur(self.ss * 0.5)),
                       np.float32) / 255.0
        self.hgt -= a * depth

    def tint_stone(self, rgb):
        """Replace the stone's colour (an array of the working size)."""
        self.stone = rgb.astype(np.float32)

    # --- finishing -----------------------------------------------------
    def finish(self, relief=1.0, ao=0.55, ao_r=2.5, gold_noise=0.10,
               seed=1, tile=True):
        """Light the relief, darken its recesses, and bring it down to size.
        Returns an RGBA image, the gloss in the alpha."""
        ss = self.ss
        mode = "wrap" if tile else "nearest"
        hs = ndimage.gaussian_filter(self.hgt, ss * 0.45, mode=mode)
        gy, gx = np.gradient(hs * ss)            # slope per final texel
        nx, ny, nz = -gx * relief, -gy * relief, np.ones_like(hs)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / ln, ny / ln, nz / ln
        lam = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
        flat = LIGHT[2]
        shade = np.clip(1.0 + 1.25 * (lam - flat), 0.25, 1.9)

        # Recesses and the foot of anything raised go dark: how far below
        # its surroundings a point is.
        wide = ndimage.gaussian_filter(self.hgt, ss * ao_r, mode=mode)
        cav = np.clip(wide - self.hgt, 0, None)
        occl = np.clip(1.0 - ao * cav, 0.35, 1.0)

        stone = self.stone * (shade * occl)[..., None]

        # Gold: the metal's ramp by how squarely it faces the light, a
        # brushed grain along x, and a hot line where it turns to the light.
        t = np.clip(0.55 + 0.9 * (lam - flat), 0, 1)
        g = (GOLD_DARK[None, None, :] * (1 - t)[..., None]
             + GOLD_MID[None, None, :] * t[..., None])
        hot = np.clip((lam - flat - 0.18) / 0.35, 0, 1) ** 1.5
        g = g + (GOLD_HOT - GOLD_MID)[None, None, :] * hot[..., None]
        grain = noise(self.W, self.H, seed + 900, ss * 0.6, octaves=2)
        g *= (1 - gold_noise + 2 * gold_noise * grain)[..., None]
        g *= occl[..., None] ** 0.6

        k = self.gold[..., None]
        rgb = stone * (1 - k) + g * k
        rgb = np.clip(rgb, 0, 255)
        gl = np.clip(self.gloss * (0.85 + 0.15 * occl), 0.05, 1.0)
        img = Image.fromarray(
            np.dstack([rgb, gl * 255]).astype(np.uint8), "RGBA")
        return img.resize((self.w, self.h), Image.LANCZOS)


def flat_view(img):
    """A texture's colour, its gloss alpha dropped (for preview sheets)."""
    return img.convert("RGB").convert("RGBA")


def gloss_view(img):
    """A texture's gloss map, as grey (for preview sheets)."""
    a = img.split()[3]
    return Image.merge("RGBA", (a, a, a, Image.new("L", img.size, 255)))


# ---------------------------------------------------------------------------
# Stone
# ---------------------------------------------------------------------------
def basalt(w, h, seed, base=(22, 22, 28), var=7.0):
    """Black basalt: a fine even grain and a slow mottle, nothing that
    repeats visibly."""
    m = noise(w, h, seed, w * 0.25, 4)
    f = noise(w, h, seed + 1, 2.0, 2)
    v = (m - 0.5) * var + (f - 0.5) * var * 0.8
    rgb = np.empty((h, w, 3), np.float32)
    for c in range(3):
        rgb[..., c] = base[c] + v * (1.0 + 0.1 * c)
    return rgb


def marble(w, h, seed, base=(20, 20, 25), vein=(150, 150, 160), scale=1.0):
    """Nero marquina: black marble with pale veins that run long and
    branch, and a faint cloud in the ground. A vein is the zero line of a
    gently warped field, so it wanders; each fades in and out along its
    length, and a softer halo round it makes it read as depth in the stone
    rather than a line drawn on it."""
    cloud = noise(w, h, seed, w * 0.35 * scale, 4)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    rgb = np.empty((h, w, 3), np.float32)
    rgb[:] = np.array(base, np.float32)
    rgb *= (0.80 + 0.40 * cloud)[..., None]
    veins = np.zeros((h, w), np.float32)
    halo = np.zeros((h, w), np.float32)
    specs = ((0.62, 1.0, 0.42, 0.010, 1.0), (0.80, 2.0, 0.30, 0.006, 0.65),
             (-0.70, 1.0, 0.38, 0.005, 0.40), (0.50, 3.0, 0.25, 0.004, 0.30))
    for k, (ang, freq, amp, wid, strength) in enumerate(specs):
        warp = noise(w, h, seed + 11 + k, w * 0.45 * scale, 3)
        warp2 = noise(w, h, seed + 31 + k, w * 0.10 * scale, 2)
        dd = (xs * math.cos(ang) + ys * math.sin(ang)) / w
        field = np.sin((dd * freq + (warp - 0.5) * amp
                        + (warp2 - 0.5) * amp * 0.15 + k * 0.37)
                       * math.pi * 2)
        line = np.clip(1 - np.abs(field) / wid, 0, 1) ** 1.3
        soft = np.clip(1 - np.abs(field) / (wid * 7), 0, 1) ** 2
        fade = np.clip((noise(w, h, seed + 40 + k, w * 0.22, 2) - 0.30)
                       * 2.4, 0, 1)
        veins = np.maximum(veins, line * fade * strength)
        halo = np.maximum(halo, soft * fade * strength * 0.35)
    v = np.clip(veins + halo, 0, 1)
    vc = np.array(vein, np.float32)
    rgb = rgb * (1 - v[..., None] * 0.9) + vc[None, None, :] * (v * 0.9)[..., None]
    return rgb


# ---------------------------------------------------------------------------
# Ornament: larger motifs, drawn into a mask with an ImageDraw
# ---------------------------------------------------------------------------
def _feather(d, ox, oy, R, s, th0, th1, r0, r1, ink, gap):
    """One feather of a fan: the wedge between angles `th0` and `th1`
    (degrees, up from outward) from radius `r0` to `r1` round the pivot,
    narrowed by `gap` at each side and rounded at its end."""
    def at(th, r):
        a = math.radians(th)
        return (ox + s * math.cos(a) * r * R, oy - math.sin(a) * r * R)
    tg0 = th0 + gap
    tg1 = th1 - gap
    mid = (tg0 + tg1) * 0.5
    pts = [at(tg0, r0)]
    n = 6
    for j in range(n + 1):
        pts.append(at(tg0, r0 + (r1 - r0) * j / n * 0.92))
    # the rounded end
    for j in range(1, 8):
        f = j / 8
        th = tg0 + (tg1 - tg0) * f
        pts.append(at(th, r1 * (0.92 + 0.08 * math.sin(math.pi * f))))
    for j in range(n, -1, -1):
        pts.append(at(tg1, r0 + (r1 - r0) * j / n * 0.92))
    d.polygon(pts, fill=ink)
    return at(mid, r0), at(mid, r1 * 0.9)


def winged_disc(d, cx, cy, span, ink=255, feathers=11):
    """The winged sun: a disc between two rearing uraei, with a falcon's
    wings swept out and up either side of it and its tail spread below.
    Each wing is a fan of long flight feathers from the shoulder, lengthening
    toward the lifted tip, with a tier of short rounded coverts over their
    roots; each feather's quill is cut in. `span` is tip to tip."""
    R = span * 0.5
    for s in (-1, 1):
        ox, oy = cx + s * 0.07 * R, cy + 0.07 * R        # the shoulder
        # the flight feathers: from pointing up and out at the tip down to
        # pointing down beside the body
        th_hi, th_lo = 16.0, -38.0
        step = (th_hi - th_lo) / feathers
        for k in range(feathers):
            th1 = th_hi - k * step
            th0 = th1 - step
            f = (k + 0.5) / feathers
            length = 0.30 + 0.72 * (1 - f) ** 0.6
            q0, q1 = _feather(d, ox, oy, R, s, th0, th1, 0.10, length, ink,
                              step * 0.07)
            d.line([q0, q1], fill=0, width=max(1, int(R * 0.006)))
        # the coverts over their roots, a half step round from them, then
        # the line where the two tiers meet
        for k in range(feathers - 1):
            th1 = th_hi - (k + 0.5) * step
            th0 = th1 - step
            f = (k + 1) / feathers
            length = 0.13 + 0.30 * (1 - f) ** 0.9
            _feather(d, ox, oy, R, s, th0, th1, 0.08, length, 0,
                     -step * 0.02)
            _feather(d, ox, oy, R, s, th0, th1, 0.08, length * 0.96, ink,
                     step * 0.05)
        # the tail: a short fan straight down under the disc
    for k in range(7):
        th1 = -64 - k * 7.5
        th0 = th1 - 7.5
        _feather(d, cx, cy + 0.02 * R, R, 1, th0, th1, 0.05, 0.30, ink, 0.6)
    # the uraei, rearing either side of the disc
    for s in (-1, 1):
        # its tail curling under the disc, its body rising at the disc's
        # side, its hood spread above
        pen = G.Pen(d, cx - R, cy - R, 2 * R, 2 * R, ink)
        body = [(0.5 + s * 0.012, 0.5 + 0.052), (0.5 + s * 0.040, 0.5 + 0.056),
                (0.5 + s * 0.056, 0.5 + 0.040), (0.5 + s * 0.058, 0.5 + 0.012)]
        pen.stroke(body, 0.006, 0.011)
        hx = cx + s * 0.118 * R
        hy = cy - 0.010 * R
        d.polygon([(hx - s * R * 0.010, hy + R * 0.030),
                   (hx - s * R * 0.022, hy - R * 0.010),
                   (hx - s * R * 0.004, hy - R * 0.048),
                   (hx + s * R * 0.014, hy - R * 0.030),
                   (hx + s * R * 0.012, hy + R * 0.030)], fill=ink)
    # the disc, over everything, with a ring cut into it
    r = R * 0.090
    d.ellipse([cx - r * 1.12, cy - r * 1.12, cx + r * 1.12, cy + r * 1.12],
              fill=0)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ink)
    rr = r * 0.76
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=0,
              width=max(1, int(r * 0.10)))


def cartouche(d, x0, y0, w, h, seed, ink=255, glyphs=True):
    """A royal name-ring, upright: a doubled oval rope with its tie across
    the foot, and a column of glyphs inside."""
    t = w * 0.075
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h - t * 1.6], radius=w * 0.5,
                        fill=ink)
    d.rounded_rectangle([x0 + t, y0 + t, x0 + w - t, y0 + h - t * 2.6],
                        radius=w * 0.5 - t, fill=0)
    # the fine inner line of the rope
    d.rounded_rectangle([x0 + t * 1.55, y0 + t * 1.55, x0 + w - t * 1.55,
                         y0 + h - t * 3.15], radius=w * 0.5 - t * 1.55,
                        outline=ink, width=max(1, int(t * 0.28)))
    # the tie
    d.rectangle([x0 - t * 0.2, y0 + h - t * 1.9, x0 + w + t * 0.2,
                 y0 + h], fill=ink)
    if glyphs:
        iw = w - t * 4.2
        G.column(d, x0 + t * 2.1, y0 + w * 0.30, iw, h - w * 0.52 - t * 2.6,
                 seed, ink, gap=0.05)


def lotus_chain(d, x0, y0, w, h, n, ink=255):
    """The lotus frieze, running up the band: open flowers and buds
    alternating, each standing on a short stem that springs from the head of
    the one before, with a pair of leaves curling back at the joint. `n`
    motifs over the length, so it repeats exactly over `h`; they point up
    the band (toward the top of the image)."""
    step = h / n
    cx = x0 + w * 0.5
    pen = G.Pen(d, x0, y0, w, h, ink)

    def U(x):
        return (x - x0) / w

    def V(y):
        return (y - y0) / h

    for i in range(-1, n + 1):
        base = y0 + h - i * step               # where this motif's stem starts
        head = base - step * 0.34              # where its flower sits
        # the stem, and the two leaves curling back from its foot
        pen.stroke([(U(cx), V(base)), (U(cx), V(head))], 0.028, 0.024,
                   smooth=False)
        for s_ in (-1, 1):
            pen.stroke([(U(cx), V(base - step * 0.02)),
                        (U(cx + s_ * w * 0.22), V(base - step * 0.10)),
                        (U(cx + s_ * w * 0.36), V(base + step * 0.02)),
                        (U(cx + s_ * w * 0.30), V(base + step * 0.10))],
                       0.030, 0.012)
        if i % 2 == 0:
            # an open flower: two sepals flaring and three petals between
            fw = w * 0.44
            fh = step * 0.60
            d.polygon([(cx - fw * 0.16, head), (cx + fw * 0.16, head),
                       (cx + fw * 0.98, head - fh * 0.62),
                       (cx + fw * 0.60, head - fh * 0.54),
                       (cx, head - fh * 0.14),
                       (cx - fw * 0.60, head - fh * 0.54),
                       (cx - fw * 0.98, head - fh * 0.62)], fill=ink)
            for (px, top, pw) in ((-0.40, 0.80, 0.21), (0.0, 0.98, 0.26),
                                  (0.40, 0.80, 0.21)):
                pts = []
                for k in range(17):
                    a = math.pi * k / 16
                    pts.append((cx + fw * px + math.cos(a) * fw * pw,
                                head - fh * 0.14 - math.sin(a) ** 0.7
                                * fh * (top - 0.14)))
                d.polygon(pts, fill=ink)
                d.line([(cx + fw * px, head - fh * 0.18),
                        (cx + fw * px, head - fh * (top - 0.10))], fill=0,
                       width=max(1, int(fw * 0.04)))
        else:
            # a bud: a closed teardrop between its sepals
            bw = w * 0.16
            bh = step * 0.46
            pts = []
            for k in range(25):
                a = 2 * math.pi * k / 24
                r = 1 - 0.5 * max(0, -math.cos(a))
                pts.append((cx + math.sin(a) * bw * r,
                            head - bh * 0.42 - math.cos(a) * bh * 0.42
                            - (bh * 0.16 * (-math.cos(a)) ** 6
                               if math.cos(a) < 0 else 0)))
            d.polygon(pts, fill=ink)
            d.polygon([(cx - bw * 0.25, head), (cx + bw * 0.25, head),
                       (cx + bw * 1.05, head - bh * 0.34),
                       (cx + bw * 0.60, head - bh * 0.30), (cx, head - bh * 0.1),
                       (cx - bw * 0.60, head - bh * 0.30),
                       (cx - bw * 1.05, head - bh * 0.34)], fill=ink)


def lotus_bouquet(d, cx, cy, size, ink=255):
    """An open lotus between two buds, their stems gathered at the foot: the
    flower of the Nile, standing upright (toward the top of the image).
    `size` is its height."""
    h = size
    pen = G.Pen(d, cx - h, cy - h * 0.5, 2 * h, h, ink)

    def U(x):
        return 0.5 + x / 2.0

    # the stems, springing from one knot
    pen.stroke([(U(0), 1.0), (U(0), 0.62)], 0.050, 0.040, smooth=False)
    for s in (-1, 1):
        pen.stroke([(U(0), 0.98), (U(s * 0.16), 0.80), (U(s * 0.36), 0.56),
                    (U(s * 0.44), 0.42)], 0.040, 0.030)
        # a bud: a closed teardrop, leaning out
        bx, by = cx + s * h * 0.46, cy - h * 0.5 + h * 0.30
        pts = []
        for k in range(21):
            a = 2 * math.pi * k / 20
            r = 1 - 0.45 * max(0, -math.cos(a))
            pts.append((bx + math.sin(a) * h * 0.075 * r + s * h * 0.03
                        * (1 - math.cos(a)) * 0.5,
                        by - math.cos(a) * h * 0.14))
        d.polygon(pts, fill=ink)
    # the open flower: sepals flaring out and three petals between them
    fy = cy - h * 0.5 + h * 0.62
    fw = h * 0.42
    d.polygon([(cx - fw * 0.20, fy), (cx + fw * 0.20, fy),
               (cx + fw * 0.96, fy - h * 0.40), (cx + fw * 0.58, fy - h * 0.34),
               (cx, fy - h * 0.10),
               (cx - fw * 0.58, fy - h * 0.34), (cx - fw * 0.96, fy - h * 0.40)],
              fill=ink)
    for (px, top, pw) in ((-0.40, 0.52, 0.21), (0.0, 0.62, 0.26),
                          (0.40, 0.52, 0.21)):
        pts = []
        for k in range(17):
            a = math.pi * k / 16
            pts.append((cx + fw * px + math.cos(a) * fw * pw,
                        fy - h * 0.10 - math.sin(a) ** 0.7 * h * (top - 0.10)))
        d.polygon(pts, fill=ink)
        d.line([(cx + fw * px, fy - h * 0.14),
                (cx + fw * px, fy - h * (top - 0.08))], fill=0,
               width=max(1, int(h * 0.012)))


def bead_chain(d, x0, x1, y0, y1, n, ink=255):
    """A string of long barrels and round beads running along y, `n` of each
    over the length (so it repeats exactly)."""
    step = (y1 - y0) / n
    cx = (x0 + x1) * 0.5
    hw = (x1 - x0) * 0.5
    for i in range(n):
        ya = y0 + i * step
        # the barrel: a long hexagon
        b0, b1 = ya + step * 0.06, ya + step * 0.62
        k = (b1 - b0) * 0.16
        d.polygon([(cx, b0), (cx + hw * 0.72, b0 + k), (cx + hw * 0.72, b1 - k),
                   (cx, b1), (cx - hw * 0.72, b1 - k), (cx - hw * 0.72, b0 + k)],
                  fill=ink)
        # the bead
        r = min(hw * 0.55, step * 0.13)
        by = ya + step * 0.81
        d.ellipse([cx - r, by - r, cx + r, by + r], fill=ink)
        # the thread between them
        d.rectangle([cx - hw * 0.08, ya, cx + hw * 0.08, ya + step],
                    fill=ink)


def scarab(d, cx, cy, size, ink=255):
    """Khepri rolling the sun, seen from above, head toward the top, as an
    amulet shows him: one compact oval body divided by seams into the
    toothed head, the broad pronotum and the two wing cases; the sun held up
    against his head between his forelegs; and his other legs braced out.
    `size` is his height, sun included. The seams are cut, so an outline of
    it (`Plate.outline`) traces each part."""
    h = size

    def P(u, v):
        return (cx + u * h, cy + v * h)

    def poly(pts, fill=ink):
        d.polygon([P(u, v) for (u, v) in pts], fill=fill)

    bw, top, bot = 0.20, -0.18, 0.46       # the body's half-width and ends

    def body_x(v):
        """The oval's half-width at height v."""
        t = (v - top) / (bot - top) * 2 - 1
        return bw * math.sqrt(max(0.0, 1 - t * t)) ** 0.85

    # the body, as one oval, with the head's teeth along its front
    pts = []
    n = 48
    for k in range(n + 1):
        a = 2 * math.pi * k / n
        v = (top + bot) / 2 - math.cos(a) * (bot - top) / 2
        u = math.sin(a) * body_x(v) * 1.0
        if v < top + 0.05 and k % 2 == 1:
            v -= 0.012                      # a tooth
        pts.append((u, v))
    poly(pts)
    # the seams: head from pronotum, pronotum from wing cases, and between
    # the wing cases
    seam = max(1, int(h * 0.018))
    for (v0, bow) in ((top + 0.11, -0.03), (top + 0.28, 0.035)):
        q = []
        for k in range(21):
            t = k / 20
            u = (t * 2 - 1) * body_x(v0) * 1.02
            q.append(P(u, v0 + bow * (1 - (t * 2 - 1) ** 2)))
        d.line(q, fill=0, width=seam, joint="curve")
    d.line([P(0, top + 0.28 + 0.035), P(0, bot)], fill=0, width=seam)

    # the sun, against his head
    r = 0.13
    a0, b0 = P(-r, top - 0.2 * 0 - r * 2 + 0.01), P(r, top + 0.01)
    d.ellipse([a0[0], a0[1], b0[0], b0[1]], fill=ink)

    # the legs: tapered, with an elbow; the forelegs reach up round the sun
    def leg(pts, w0, w1):
        q = [P(u, v) for (u, v) in pts]
        steps = 24
        for k in range(steps + 1):
            t = k / steps
            # along the polyline
            seg = min(len(q) - 2, int(t * (len(q) - 1)))
            f = t * (len(q) - 1) - seg
            x = q[seg][0] + (q[seg + 1][0] - q[seg][0]) * f
            y = q[seg][1] + (q[seg + 1][1] - q[seg][1]) * f
            rr = (w0 + (w1 - w0) * t) * h * 0.5
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=ink)

    for s_ in (-1, 1):
        leg([(s_ * 0.13, top + 0.08), (s_ * 0.24, top - 0.02),
             (s_ * 0.15, top - 0.20)], 0.045, 0.022)
        leg([(s_ * 0.18, top + 0.24), (s_ * 0.33, top + 0.20),
             (s_ * 0.38, top + 0.32)], 0.040, 0.020)
        leg([(s_ * 0.16, top + 0.42), (s_ * 0.30, top + 0.52),
             (s_ * 0.32, top + 0.66)], 0.040, 0.020)
