#!/usr/bin/env python3
"""Prepare Szuix from the commissioned pixel sheet, and draw his aura and eye
card.

The source is `tools/source/szuix_sheet.png`: six frames of 55x45 hard-alpha
pixel art, a back view of him flying. (Nobody has said whether this sheet is
under the same restriction as the painted commissions; ask before building
more on it.)

Upscaling: NEAREST to 6x, one blur at that size to round the staircase, then
LANCZOS down to 2x, all premultiplied (see `smooth_upscale`). A plain LANCZOS
enlargement blurs the silhouette; plain NEAREST keeps the staircase. Then a
dark contour and a cool rim on upward-facing edges are added (`dress`).

If the commission is redone at a higher resolution, point `SOURCE` at it and
set `SCALE` to 1.

Usage:
    python tools/make_player.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SOURCE = os.path.join(A.ROOT, "tools", "source", "szuix_sheet.png")
FRAME_W = 55
FRAME_H = 45
FRAMES = 6

# Final size is SCALE times the source: 110x90 at 2x.
SCALE = 2
OVERSAMPLE = 6


def smooth_upscale(img, scale, oversample=OVERSAMPLE, soften=2.4):
    """Enlarge pixel art: NEAREST up by `oversample`, blur, LANCZOS down to
    `scale`. Premultiplied, because the sheet's transparent pixels are white
    (it was drawn on white), and blurring unpremultiplied bleeds that white
    into the edges as a grey halo.
    """
    w, h = img.size
    arr = np.asarray(img, dtype=np.float32)
    a = arr[..., 3:4] / 255.0
    pm = Image.fromarray(
        np.concatenate([arr[..., :3] * a, arr[..., 3:4]], axis=2)
          .astype(np.uint8), "RGBA")

    big = pm.resize((w * oversample, h * oversample), Image.NEAREST)
    big = big.filter(ImageFilter.GaussianBlur(soften))
    big = big.resize((w * scale, h * scale), Image.LANCZOS)

    out = np.asarray(big, dtype=np.float32)
    oa = np.clip(out[..., 3:4] / 255.0, 1e-3, 1.0)
    return Image.fromarray(
        np.concatenate([np.clip(out[..., :3] / oa, 0, 255), out[..., 3:4]],
                       axis=2).astype(np.uint8), "RGBA")


def dress(img):
    """Add the contour and the rim light, on a canvas with room for both."""
    pad = 6
    out = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2),
                    (0, 0, 0, 0))
    out.alpha_composite(img, (pad, pad))

    # The contour, traced from a hardened copy of the alpha (tracing the
    # feathered edge thickens him by a pixel, which flickers across frames).
    solid = out.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    grown = solid.filter(ImageFilter.MaxFilter(5))
    ring = ImageChops.subtract(grown, solid).filter(
        ImageFilter.GaussianBlur(0.8))
    contour = Image.new("RGBA", out.size, (6, 8, 20, 0))
    contour.putalpha(ring.point(lambda v: int(v * 0.78)))

    result = Image.new("RGBA", out.size, (0, 0, 0, 0))
    result.alpha_composite(contour)
    result.alpha_composite(out)

    # The rim: a lit edge on every upward-facing edge (`rim_light`), so the
    # dark blue silhouette doesn't disappear against dark backgrounds.
    rim = A.rim_light(solid, A.SZUIX_LIT, drop=3, blur=1.2, strength=0.55)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), solid))
    result = A.add(result, rim)
    return result


AURA_PAD = 18


def aura(frame):
    """A soft white halo in the shape of one frame (his silhouette grown and
    blurred), tinted at draw time: red at one hit from death, cyan when he
    casts (`player_draw`). Padded by `AURA_PAD` all round; the game offsets its
    origin by the same amount.
    """
    w, h = frame.size
    solid = frame.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    big = Image.new("L", (w + AURA_PAD * 2, h + AURA_PAD * 2), 0)
    big.paste(solid, (AURA_PAD, AURA_PAD))
    grown = big.filter(ImageFilter.MaxFilter(7))
    soft = grown.filter(ImageFilter.GaussianBlur(6.5))
    # A tighter, brighter band right at the edge, over the wide one.
    rim = big.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.6))
    a = ImageChops.lighter(soft.point(lambda v: int(min(255, v * 1.15))),
                           rim.point(lambda v: int(v * 0.8)))
    out = Image.new("RGBA", big.size, (255, 255, 255, 0))
    out.putalpha(a)
    return out


# ---------------------------------------------------------------------------
# The eye card
# ---------------------------------------------------------------------------
#
# Drawn from nothing: the painted commissions of him are reference only and
# none of their pixels may ship (owner's rule), so every shape is a curve
# written out in card pixels. From the references: blue skin, glowing cyan
# eyes, bat ears with violet inside, ram horns curling beside them, dark
# spiky hair, one fang. Cel-shaded and inked: flat colour, one hard shadow
# shape and one light per plane, and a dark outline.

CARD_W, CARD_H = 1280, 420      # the same card Ziggy's spells use
CARD_SS = 3
CX = CARD_W / 2.0

SKIN = (54, 68, 208)
SKIN_SHADE = (30, 32, 134)
SKIN_LIT = (118, 138, 250)
EAR_IN = (164, 92, 244)
EAR_DEEP = (66, 28, 146)
HAIR = (16, 16, 40)
HAIR_SHEEN = (58, 72, 160)
HORN = (58, 50, 74)
HORN_LIT = (164, 150, 188)
INK = (8, 6, 24)
IRIS = (70, 222, 255)
IRIS_DEEP = (16, 104, 210)
SCLERA = (214, 228, 255)
MOUTH = (30, 10, 38)
TOOTH = (236, 238, 250)


def _bez(p0, p1, p2, p3, n=28):
    out = []
    for i in range(n + 1):
        t = i / float(n)
        u = 1 - t
        out.append((u * u * u * p0[0] + 3 * u * u * t * p1[0]
                    + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * p1[1]
                    + 3 * u * t * t * p2[1] + t * t * t * p3[1]))
    return out


def _chain(*segs):
    out = []
    for seg in segs:
        out.extend(seg if not out else seg[1:])
    return out


def _flip(pts, about=CX):
    return [(2 * about - x, y) for x, y in pts]


class _Card:
    """Masks in card pixels, painted at `CARD_SS` and downsampled once."""

    def __init__(self):
        self.s = CARD_SS
        self.size = (CARD_W * self.s, CARD_H * self.s)
        self.img = Image.new("RGBA", self.size, (0, 0, 0, 255))
        ys, xs = np.mgrid[0:self.size[1], 0:self.size[0]].astype(np.float32)
        self.xs = xs / self.s
        self.ys = ys / self.s

    def mask(self):
        return Image.new("L", self.size, 0)

    def P(self, pts):
        return [(x * self.s, y * self.s) for x, y in pts]

    def poly(self, pts, m=None, v=255):
        m = m if m is not None else self.mask()
        ImageDraw.Draw(m).polygon(self.P(pts), fill=v)
        return m

    def ellipse(self, cx, cy, rx, ry, m=None, v=255):
        m = m if m is not None else self.mask()
        s = self.s
        ImageDraw.Draw(m).ellipse([(cx - rx) * s, (cy - ry) * s,
                                   (cx + rx) * s, (cy + ry) * s], fill=v)
        return m

    def stroke(self, pts, width, m=None, v=255):
        m = m if m is not None else self.mask()
        ImageDraw.Draw(m).line(self.P(pts), fill=v,
                               width=max(1, int(round(width * self.s))),
                               joint="curve")
        return m

    def taper(self, pts, w0, w1, m=None, v=255):
        """A stroke that thickens or thins along its length."""
        m = m if m is not None else self.mask()
        d = ImageDraw.Draw(m)
        n = len(pts) - 1
        for i in range(n):
            w = w0 + (w1 - w0) * (i / max(1.0, n - 1.0))
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            d.line([(ax * self.s, ay * self.s), (bx * self.s, by * self.s)],
                   fill=v, width=max(1, int(round(w * self.s))))
            r = w * self.s / 2.0
            d.ellipse([bx * self.s - r, by * self.s - r,
                       bx * self.s + r, by * self.s + r], fill=v)
        return m

    def shift(self, m, dx, dy):
        return ImageChops.offset(m, int(dx * self.s), int(dy * self.s))

    def soft(self, m, r):
        return m.filter(ImageFilter.GaussianBlur(r * self.s))

    def paint(self, m, colour, alpha=1.0):
        layer = Image.new("RGBA", self.size, tuple(colour) + (0,))
        layer.putalpha(m if alpha >= 1 else
                       m.point(lambda v: int(v * alpha)))
        self.img.alpha_composite(layer)

    def paint_field(self, m, colour_arr, alpha=1.0):
        """Paint a per-pixel colour (an HxWx3 array) through a mask."""
        a = np.asarray(m, dtype=np.float32) / 255.0 * alpha
        self.img.alpha_composite(A.from_arrays(colour_arr, a))

    def light(self, m, colour, alpha=1.0, blur=0.0):
        """Additive: for anything that emits."""
        if blur:
            m = self.soft(m, blur)
        layer = Image.new("RGBA", self.size, tuple(colour) + (0,))
        layer.putalpha(m.point(lambda v: int(min(255, v * alpha))))
        self.img = A.add(self.img, layer)

    def ramp(self, t, stops):
        ts = [p for p, _ in stops]
        cs = np.array([c for _, c in stops], dtype=np.float32)
        out = np.zeros(t.shape + (3,), dtype=np.float32)
        for ch in range(3):
            out[..., ch] = np.interp(t, ts, cs[:, ch])
        return out


def _and(a, b):
    return ImageChops.multiply(a, b)


def _minus(a, b):
    return ImageChops.subtract(a, b)


def _or(a, b):
    return ImageChops.lighter(a, b)


# ---- the parts, each for the right-hand side and mirrored for the left ----

def _ear_right():
    """A bat ear sweeping up and out of the frame, and the membrane in it."""
    outer = _chain(_bez((876, 70), (950, 10), (1160, -80), (1330, -130)),
                   _bez((1330, -130), (1240, 60), (1080, 230), (896, 262)))
    inner = _chain(_bez((884, 98), (960, 40), (1150, -40), (1300, -96)),
                   _bez((1300, -96), (1210, 58), (1060, 214), (902, 236)))
    ridges = [_bez((900, 180), (1010, 140), (1150, 60), (1250, -40)),
              _bez((896, 132), (990, 90), (1100, 20), (1200, -60))]
    return outer, inner, ridges


def _face_half():
    """The right half of the face, top to chin: angular (a pointed cheekbone, a
    straight jaw, a defined chin).
    """
    return _chain(_bez((CX, -60), (760, -64), (868, -44), (878, -14)),
                  _bez((878, -14), (890, 60), (904, 150), (904, 206)),
                  _bez((904, 206), (890, 262), (852, 318), (800, 366)),
                  _bez((800, 366), (752, 408), (694, 452), (CX, 478)))


def _horn_right():
    """A ram's horn: a spine with a width along it, broad at the skull and
    tightening as it curls. It leaves the top of his head, goes up out of the
    frame, comes back down the outside and curls in to a point by his temple.
    """
    # A turn and a quarter, ending at a quarter of the starting radius, so the
    # tip sits visibly inside the curl.
    cx, cy = 992, 128
    n = 140
    th0, sweep = 206.0, 440.0
    spine, outer, inner = [], [], []
    for i in range(n + 1):
        t = i / float(n)
        th = math.radians(th0 + t * sweep)       # screen angles, y down
        r = 196 * (1 - 0.80 * t ** 0.85)
        spine.append((cx + math.cos(th) * r * 1.02, cy + math.sin(th) * r))
    for i, (x, y) in enumerate(spine):
        j0, j1 = max(0, i - 1), min(n, i + 1)
        tx = spine[j1][0] - spine[j0][0]
        ty = spine[j1][1] - spine[j0][1]
        ln = math.hypot(tx, ty) or 1.0
        # the normal pointing *away* from the curl's centre
        nx, ny = ty / ln, -tx / ln
        t = i / float(n)
        w = 44 * (1 - t) ** 0.95 + 3
        outer.append((x + nx * w, y + ny * w))
        inner.append((x - nx * w, y - ny * w))
    return spine, outer, inner


def _lock(root, width, tip, bend, n=16):
    """One lock of hair: a blade from the hairline to a point, bowed sideways
    by `bend`.
    """
    rx, ry = root
    tx, ty = tip
    mx = (rx + tx) * 0.5 + bend
    my = (ry + ty) * 0.5
    left = _bez((rx - width * 0.5, ry), (rx - width * 0.45 + bend * 0.4,
                                         my - (my - ry) * 0.3),
                (mx - width * 0.18, my + (ty - my) * 0.3), (tx, ty), n)
    right = _bez((tx, ty), (mx + width * 0.18, my + (ty - my) * 0.3),
                 (rx + width * 0.45 + bend * 0.4, my - (my - ry) * 0.3),
                 (rx + width * 0.5, ry), n)
    return _chain(left, right)


def _eye(c, ex, ey, flip):
    """One eye: a cat's almond, the outer corner lifted, iris lit from inside.

    `flip` is -1 for the left eye, which mirrors it about its own centre.
    """
    def F(pts):
        return [(ex + (x - ex) * flip, y) for x, y in pts]

    # Half-lidded: the top lid runs nearly flat across the upper iris.
    top = F(_bez((ex - 90, ey + 16), (ex - 52, ey - 26),
                 (ex + 36, ey - 42), (ex + 106, ey - 30)))
    bot = F(_bez((ex + 106, ey - 30), (ex + 66, ey + 22),
                 (ex - 30, ey + 38), (ex - 90, ey + 16)))
    opening = c.poly(_chain(top, bot))

    # The white, shaded at the top where the lid overhangs it.
    t = np.clip((c.ys - (ey - 40)) / 64.0, 0, 1)
    sclera = c.ramp(t, [(0, (90, 104, 190)), (0.5, SCLERA), (1, SCLERA)])
    c.paint_field(opening, sclera)

    # The iris, off centre toward the nose.
    ix, iy, ir = ex - 8 * flip, ey + 2, 43
    iris_m = _and(c.ellipse(ix, iy, ir, ir), opening)
    r = np.hypot(c.xs - ix, c.ys - iy) / ir
    col = c.ramp(r, [(0, (150, 246, 255)), (0.45, IRIS),
                     (0.82, IRIS_DEEP), (0.93, (12, 50, 140)),
                     (1.0, (6, 20, 70))])
    c.paint_field(iris_m, col)
    # Fibres, so the iris is a surface and not a gradient.
    fib = c.mask()
    for k in range(44):
        a = math.radians(k * (360 / 44.0) + 4)
        fib = c.stroke([(ix + math.cos(a) * 13, iy + math.sin(a) * 13),
                        (ix + math.cos(a) * 36, iy + math.sin(a) * 36)],
                       1.3, fib)
    c.paint(_and(c.soft(fib, 0.4), iris_m), (200, 250, 255), 0.30)
    # The lid's shadow across the top of it, hard-edged like every other
    # shadow on him.
    lid_shadow = _and(_minus(opening, c.shift(opening, 0, 18)), iris_m)
    c.paint(lid_shadow, (6, 30, 96), 0.6)

    # The pupil: a slit.
    pupil = c.poly(_chain(_bez((ix, iy - 38), (ix + 9, iy - 14),
                               (ix + 9, iy + 14), (ix, iy + 38)),
                          _bez((ix, iy + 38), (ix - 9, iy + 14),
                               (ix - 9, iy - 14), (ix, iy - 38))))
    pupil = _and(pupil, opening)
    c.paint(pupil, (6, 10, 32))

    # The lash line: heavy, thickening outward, and a flick at the corner.
    c.paint(c.taper(top, 6.0, 15.0), INK)
    flick = F(_bez((ex + 100, ey - 30), (ex + 114, ey - 38),
                   (ex + 126, ey - 48), (ex + 138, ey - 62)))
    c.paint(c.taper(flick, 11.0, 1.5), INK)
    c.paint(c.taper(bot[:18], 4.5, 1.2), INK)
    # One hard crease under the lid, above the lash line.
    crease = F(_bez((ex - 60, ey - 30), (ex - 10, ey - 52),
                    (ex + 50, ey - 58), (ex + 96, ey - 48)))
    c.paint(c.taper(crease, 1.5, 3.5), SKIN_SHADE, 0.9)

    # The highlights: one big and one small, on the same side for both eyes.
    # Returned rather than painted, so they go on after the glow.
    catches = [(ix - 14, iy - 12, 9, 7, 1.0), (ix + 16, iy + 17, 4, 3.5, 0.9)]
    return opening, iris_m, pupil, catches


def eye_card():
    """Szuix's eye card, shown when he spends a sigil: a close-up of his face
    in a band across the upper field, cropped so the head runs off all four
    edges, the eyes the brightest thing in it, with a vignette.
    """
    c = _Card()

    # ---- the ground: his indigo, lit from behind his head -----------------
    r = np.hypot((c.xs - CX) / 700.0, (c.ys - 190) / 380.0)
    c.paint_field(c.mask().point(lambda v: 255),
                  c.ramp(np.clip(r, 0, 1),
                         [(0, (78, 42, 150)), (0.45, (38, 20, 86)),
                          (1, (10, 7, 26))]))
    rays = c.mask()
    for k in range(32):
        a0 = math.radians(k * 11.25)
        a1 = a0 + math.radians(4.0)
        rays = c.poly([(CX, 190),
                       (CX + math.cos(a0) * 1400, 190 + math.sin(a0) * 1400),
                       (CX + math.cos(a1) * 1400, 190 + math.sin(a1) * 1400)],
                      rays)
    c.light(c.soft(rays, 2), A.SIGIL, 0.10)
    ring = c.mask()
    for rr, w in ((560, 3.0), (596, 1.4)):
        pts = [(CX + math.cos(math.radians(a)) * rr,
                190 + math.sin(math.radians(a)) * rr) for a in range(0, 361, 2)]
        ring = c.stroke(pts, w, ring)
    c.light(ring, A.SIGIL, 0.55, blur=0.6)

    # ---- the ears, behind everything ---------------------------------------
    outer, inner, ridges = _ear_right()
    for side in (1, -1):
        o = outer if side > 0 else _flip(outer)
        i = inner if side > 0 else _flip(inner)
        rs = ridges if side > 0 else [_flip(q) for q in ridges]
        # Closed inside the head, so the closing edge is hidden by the face.
        ear_m = c.poly(o + [(CX + side * 150, 300), (CX + side * 150, 40)])
        c.paint(ear_m, SKIN)
        mem = c.poly(i)
        base = (CX + side * 262, 180)
        t = np.clip(np.hypot(c.xs - base[0], c.ys - base[1]) / 440.0, 0, 1)
        c.paint_field(mem, c.ramp(t, [(0, EAR_DEEP), (0.35, (112, 54, 206)),
                                      (1, EAR_IN)]))
        rid = c.mask()
        for q in rs:
            rid = c.taper(q, 7.0, 2.0, rid)
        c.paint(_and(c.soft(rid, 1.2), mem), EAR_DEEP, 0.85)
        c.paint(_and(c.shift(c.soft(rid, 0.8), -3 * side, -3), mem),
                (200, 140, 255), 0.30)
        # The inner edge of the rim catches the light off the eyes.
        c.light(_and(_minus(ear_m, c.shift(ear_m, 6 * side, 5)), ear_m),
                A.RUNE, 0.45, blur=1.2)
        c.paint(c.stroke(o, 5.0), INK)
        c.paint(c.stroke(i, 2.4), INK, 0.8)

    # ---- the face ------------------------------------------------------------
    half = _face_half()
    face_pts = _flip(half)[::-1][:-1] + half
    face = c.poly(face_pts)
    t = np.clip((c.ys + 40) / 520.0, 0, 1)
    c.paint_field(face, c.ramp(t, [(0, (66, 82, 222)), (0.55, SKIN),
                                   (1, (46, 56, 186))]))
    # One hard shadow shape per plane: the side turned from the light, the
    # hollow under each cheekbone, and a thin one down the lit side.
    c.paint(_and(_minus(face, c.shift(face, -58, 0)), face), SKIN_SHADE, 0.95)
    c.paint(_and(_minus(face, c.shift(face, 12, 0)), face), SKIN_SHADE, 0.5)
    hollow_r = c.poly([(904, 206), (872, 240), (818, 300), (774, 340),
                       (800, 366), (852, 318), (890, 262)])
    hollow_l = c.poly(_flip([(904, 206), (878, 236), (836, 290), (800, 330),
                             (800, 366), (852, 318), (890, 262)]))
    c.paint(_and(hollow_r, face), SKIN_SHADE, 0.85)
    c.paint(_and(hollow_l, face), SKIN_SHADE, 0.45)
    # The light on the cheekbones: a hard sliver each, not a blush.
    for pts, a in (([(820, 232), (872, 214), (888, 222), (836, 246)], 0.55),
                   (_flip([(820, 236), (876, 218), (892, 228), (838, 252)]),
                    0.75)):
        c.paint(_and(c.poly(pts), face), SKIN_LIT, a)
    # The bridge of the nose.
    c.paint(c.taper([(CX - 7, 196), (CX - 9, 230), (CX - 7, 262)], 5, 9),
            SKIN_LIT, 0.45)

    # ---- the nose, the mouth, the fang ----------------------------------------
    nose = c.poly(_chain(_bez((CX - 28, 270), (CX - 12, 264), (CX + 12, 264),
                              (CX + 28, 270)),
                         _bez((CX + 28, 270), (CX + 22, 286), (CX + 8, 298),
                              (CX, 302)),
                         _bez((CX, 302), (CX - 8, 298), (CX - 22, 286),
                              (CX - 28, 270))))
    c.paint(c.shift(nose, 5, 9), SKIN_SHADE, 0.8)
    c.paint(nose, (20, 16, 50))
    c.paint(c.ellipse(CX - 9, 274, 9, 3.6), (104, 118, 220), 0.9)
    c.paint(c.stroke([(CX, 301), (CX, 316)], 3.0), INK)

    # A smirk: the corner on his left (our right) higher, the mouth open just
    # enough to show the fang on that side.
    upper = _bez((548, 316), (600, 332), (692, 330), (760, 292))
    lower = _bez((760, 292), (718, 340), (640, 358), (568, 324))
    mouth = c.poly(_chain(upper, lower))
    c.paint(mouth, MOUTH)
    c.paint(_and(c.taper(upper, 15, 11), mouth), TOOTH)
    fang_pts = _chain(_bez((690, 326), (696, 340), (702, 354), (708, 366)),
                      _bez((708, 366), (713, 350), (717, 334), (721, 318)))
    c.paint(c.poly(fang_pts), TOOTH)
    c.paint(c.stroke(fang_pts, 1.6), INK, 0.8)
    c.paint(c.taper(upper, 3.0, 6.5), INK)
    c.paint(c.taper(lower[6:-4], 2.2, 2.2), INK, 0.6)
    c.paint(c.taper(_bez((760, 292), (768, 286), (774, 278), (778, 268), 8),
                    5.0, 1.0), INK)
    # The chin's shadow, where the vignette will take it anyway.
    c.paint(_and(c.poly([(560, 372), (720, 372), (740, 480), (540, 480)]),
                 face), SKIN_SHADE, 0.35)

    # ---- the eyes --------------------------------------------------------------
    irises, pupils = c.mask(), c.mask()
    catches = []
    for ex, ey, flip in ((790, 190, 1), (490, 194, -1)):
        _, iris, pupil, cs = _eye(c, ex, ey, flip)
        irises = _or(irises, iris)
        pupils = _or(pupils, pupil)
        catches += cs

    # ---- the brows ---------------------------------------------------------------
    # One raised (on the smirk's side) and one lowered.
    c.paint(c.taper(_bez((712, 132), (756, 108), (820, 92), (882, 94)),
                    13, 3), HAIR)
    c.paint(c.taper(_bez((570, 138), (526, 124), (470, 118), (404, 124)),
                    13, 3), HAIR)

    # ---- the hair -----------------------------------------------------------------
    # Two rows of locks; the back row fills the gaps of the front row, and the
    # hair mass ends at their roots (so no straight edge shows between locks).
    back = [((438, 50), 70, (430, 150), -8),
            ((502, 56), 74, (486, 136), -6),
            ((574, 58), 78, (548, 150), -10),
            ((652, 58), 78, (652, 146), 4),
            ((728, 56), 74, (744, 138), 8),
            ((800, 52), 70, (824, 146), 10),
            ((858, 46), 64, (884, 170), 12)]
    locks = [((404, 44), 62, (388, 292), -18),
             ((466, 54), 70, (442, 180), -12),
             ((536, 58), 76, (512, 170), -10),
             ((612, 60), 82, (580, 236), -20),
             ((690, 60), 76, (702, 180), 10),
             ((764, 56), 72, (790, 160), 12),
             ((834, 50), 66, (866, 188), 14),
             ((878, 42), 58, (894, 288), 18)]
    crown = _chain(_bez((340, 70), (320, -20), (360, -110), (480, -140)),
                   _bez((480, -140), (600, -170), (700, -170), (820, -140)),
                   _bez((820, -140), (930, -110), (960, -20), (940, 70)))
    hair = c.poly(crown)
    back_hair = c.mask()
    for root, w, tip, bend in back:
        back_hair = c.poly(_lock(root, w, tip, bend), back_hair)
    lock_pts = []
    for root, w, tip, bend in locks:
        pts = _lock(root, w, tip, bend)
        lock_pts.append((pts, root, tip, bend))
        hair = c.poly(pts, hair)
    hair = _or(hair, back_hair)
    # The shadow the fringe throws on the forehead, down and to the right.
    c.paint(_and(_minus(c.shift(hair, 10, 22), hair), face), SKIN_SHADE, 0.9)
    c.paint(hair, HAIR)
    # The back row a step darker, so the front row stands off it.
    front = c.mask()
    for pts, _, _, _ in lock_pts:
        front = c.poly(pts, front)
    c.paint(_minus(back_hair, front), (8, 8, 22), 0.9)
    # A sheen down each lock, on the lit side.
    sheen = c.mask()
    for pts, root, tip, bend in lock_pts:
        dy = tip[1] - root[1]
        mid = _bez((root[0] - 12, root[1] + 6),
                   (root[0] - 10 + bend * 0.3, root[1] + dy * 0.3),
                   (tip[0] - 4 + bend * 0.2, root[1] + dy * 0.6),
                   (tip[0] - 2, tip[1] - dy * 0.3), 10)
        sheen = c.taper(mid, 7.0, 1.0, sheen)
    # ...and a few strands flowing out of the crown toward the fringe.
    for k in range(7):
        x0 = 470 + k * 60
        sheen = c.taper(_bez((640 + (x0 - 640) * 0.3, -150),
                             (640 + (x0 - 640) * 0.6, -80),
                             (x0 - 4, -20), (x0 - 8, 40), 12),
                        1.0, 5.0, sheen)
    c.paint(_and(sheen, hair), HAIR_SHEEN, 0.8)
    parting = c.mask()
    for pts, root, tip, bend in lock_pts:
        parting = c.stroke(pts[:-2], 1.8, parting)
    c.paint(_and(_and(parting, hair), c.poly([(0, 66), (CARD_W, 66),
                                               (CARD_W, 480), (0, 480)])),
            INK, 0.9)
    c.light(_and(_minus(hair, c.shift(hair, 5, 6)), hair), A.SIGIL, 0.6,
            blur=0.8)

    # ---- the horns -------------------------------------------------------------
    spine, o, i = _horn_right()
    for side in (1, -1):
        oo = o if side > 0 else _flip(o)
        ii = i if side > 0 else _flip(i)
        sp = spine if side > 0 else _flip(spine)
        n = len(sp)
        horn = c.poly(oo + ii[::-1])
        # Darker at the root, paler toward the tip, as horn is.
        tmap = c.mask()
        draw = ImageDraw.Draw(tmap)
        for k in range(n - 1):
            q = [oo[k], oo[k + 1], ii[k + 1], ii[k]]
            draw.polygon(c.P(q), fill=int(255 * k / (n - 1.0)))
        tarr = np.asarray(tmap, dtype=np.float32) / 255.0
        c.paint_field(horn, c.ramp(tarr, [(0, (40, 32, 52)), (0.6, HORN),
                                          (1, (122, 110, 140))]))
        # The inside of the curl in shadow, the outside lit: a hard line
        # partway across the horn.
        shade = c.poly(ii + [(sp[k][0] + (oo[k][0] - sp[k][0]) * 0.1,
                              sp[k][1] + (oo[k][1] - sp[k][1]) * 0.1)
                             for k in range(n - 1, -1, -1)])
        c.paint(_and(shade, horn), (20, 14, 30), 0.55)
        lit = c.poly(oo + [(sp[k][0] + (oo[k][0] - sp[k][0]) * 0.55,
                            sp[k][1] + (oo[k][1] - sp[k][1]) * 0.55)
                           for k in range(n - 1, -1, -1)])
        c.paint(_and(lit, horn), HORN_LIT, 0.35)
        # Growth rings: arched, closer together toward the tip, each with a lit
        # edge.
        rings, ring_lit = c.mask(), c.mask()
        k = 3.0
        while k < n - 8:
            j = int(k)
            a, m, b = ii[j], sp[min(n - 1, j + 2)], oo[j]
            arc = _bez(a, (a[0] + (m[0] - a[0]) * 0.7,
                           a[1] + (m[1] - a[1]) * 0.7),
                       (b[0] + (m[0] - b[0]) * 0.7,
                        b[1] + (m[1] - b[1]) * 0.7), b, 10)
            rings = c.stroke(arc, 2.6, rings)
            j2 = min(n - 1, j + 1)
            a2, b2 = ii[j2], oo[j2]
            ring_lit = c.stroke([((a2[0] + b2[0]) * 0.5,
                                  (a2[1] + b2[1]) * 0.5), b2], 1.6, ring_lit)
            k += 7.5 * (1 - k / (n * 1.25))
        c.paint(_and(rings, horn), (16, 10, 24), 0.85)
        c.paint(_and(ring_lit, horn), HORN_LIT, 0.45)
        c.light(_and(c.soft(c.stroke(oo[2:-10], 2.4), 0.8), horn), A.SIGIL,
                0.7)
        c.paint(c.stroke(oo + ii[::-1] + [oo[0]], 4.4), INK)

    # ---- the light off his eyes -------------------------------------------------
    # **The glow goes on first and the pupils and catchlights over it.** Added
    # over the finished eye it washed the slits out entirely, and a glowing
    # eye with no pupil is a lamp rather than a look.
    c.light(irises, IRIS, 0.55, blur=18)
    c.light(irises, (160, 246, 255), 0.30, blur=5)
    c.paint(pupils, (6, 10, 32), 0.92)
    for x, y, rx, ry, a in catches:
        c.paint(c.ellipse(x, y, rx, ry), (255, 255, 255), a)
    # ...and the same light along the lit side of the jaw, below the hair.
    jaw = _and(_minus(face, c.shift(face, 7, 0)),
               c.poly([(0, 150), (CX, 150), (CX, 480), (0, 480)]))
    c.light(_minus(jaw, hair), A.RUNE, 0.6, blur=0.9)
    c.paint(c.stroke(_flip(half)[::-1][40:] + half[40:], 4.2), INK)

    out = c.img.resize((CARD_W, CARD_H), Image.LANCZOS)

    # The vignette, as Ziggy's card has it.
    ys, xs = np.mgrid[0:CARD_H, 0:CARD_W].astype(np.float32)
    edge = np.minimum(np.minimum(xs, CARD_W - 1 - xs) / (CARD_W * 0.13),
                      np.minimum(ys, CARD_H - 1 - ys) / (CARD_H * 0.16))
    arr = np.asarray(out, dtype=np.float32)
    arr[..., 3] = 255.0 * np.clip(edge, 0, 1) ** 0.9
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def main():
    if not os.path.exists(SOURCE):
        raise SystemExit(
            "the commissioned sheet is missing.\n"
            "Expected six 55x45 frames at %s" % SOURCE)

    sheet = Image.open(SOURCE).convert("RGBA")
    expect = (FRAME_W * FRAMES, FRAME_H)
    if sheet.size != expect:
        raise SystemExit("%s is %dx%d; expected %dx%d (%d frames of %dx%d)"
                         % ((SOURCE,) + sheet.size + expect
                            + (FRAMES, FRAME_W, FRAME_H)))

    frames = []
    for i in range(FRAMES):
        cell = sheet.crop((i * FRAME_W, 0, (i + 1) * FRAME_W, FRAME_H))
        frames.append(dress(smooth_upscale(cell, SCALE)))

    # **The origin is on his chest, not in the middle of the box.** The frame
    # is mostly wing, and the wings are above the body -- so the box's centre
    # sits between his shoulders. The hitbox is drawn and tested at the origin,
    # and a hitbox floating above a character's head is the kind of thing that
    # makes a game feel like it is cheating even when the numbers are right.
    w, h = frames[0].size
    gm_new.folder("Sprites/player")
    gm_new.sprite("spr_szuix", frames, origin=(w // 2, int(h * 0.55)),
                  folder="Sprites/player", fps=12.0)
    # Frame for frame with him, so the halo flaps with his wings.
    auras = [aura(f) for f in frames]
    gm_new.sprite("spr_szuix_aura", auras,
                  origin=(w // 2 + AURA_PAD, int(h * 0.55) + AURA_PAD),
                  folder="Sprites/player", fps=12.0)

    card = eye_card()
    gm_new.sprite("spr_eye_szuix", [card], origin="center",
                  folder="Sprites/player")
    # Over a dark field at the alpha and the size the game draws it, because
    # that is the only way it is ever seen.
    field = Image.new("RGBA", (card.width + 80, card.height + 80),
                      (14, 11, 24, 255))
    shown = card.copy()
    shown.putalpha(shown.getchannel("A").point(lambda v: int(v * 0.8)))
    field.alpha_composite(shown, (40, 40))
    field.save(os.path.join(A.PREVIEW, "eye_szuix.png"))

    A.preview(frames, os.path.join(A.PREVIEW, "player.png"), cols=6,
              bg=(30, 34, 52))
    over = [A.over(A.checker(w, h, (196, 176, 150), (176, 156, 132)), f)
            for f in frames]
    A.preview(over, os.path.join(A.PREVIEW, "player_bright.png"), cols=6,
              bg=(200, 190, 170))
    print("szuix: %d frames of %dx%d" % (len(frames), w, h))


if __name__ == "__main__":
    main()
