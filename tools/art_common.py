#!/usr/bin/env python3
"""Shared drawing for every art generator in this project.

- Everything is drawn supersampled (`SS` times the final size) and
  downsampled once at the end, because PIL's draw calls are hard-edged.
- Repeated things get variants and jitter from a fixed seed, so re-running
  writes identical files.
- A bullet is a bright core inside a saturated rim, with a hard dark contour:
  the core's luminance reads against a bright background and the rim's hue
  against a dark one. Bullets and shards are cut bodies (see "Cut bodies");
  `shade_shape` is the older, softer treatment the scenery and enemies use.
- Fields are numpy expressions over a coordinate grid; per-pixel Python
  loops don't scale at `SS`.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "tools", "fonts")
PREVIEW = os.path.join(ROOT, "tools", "_preview")
os.makedirs(PREVIEW, exist_ok=True)  # git-ignored, so a fresh clone lacks it

# How much larger than final everything is drawn before the single downsample.
SS = 4

GAME_W = 1920
GAME_H = 1080

# The playfield; the parallax layers are this size. Mirrors `FIELD_W` /
# `FIELD_H` in `scripts/constants`, and nothing checks that they agree.
FIELD_W = 1360
FIELD_H = 992


# ---------------------------------------------------------------------------
# Palette. `tools/make_palette.py` generates `scripts/palette` from these
# (GameMaker's colour literals are BGR, PIL's are RGB).
# ---------------------------------------------------------------------------

VOID = (10, 12, 20)          # behind everything
DUSK = (24, 27, 44)          # the ambient dark of a stage
SLATE = (58, 62, 84)         # UI furniture
SILVER = (188, 198, 220)     # UI lines and small text
PARCHMENT = (238, 228, 216)
INK = (40, 36, 48)

SZUIX = (46, 62, 190)        # the player's blue, lifted off the commission
SZUIX_LIT = (110, 130, 255)
ZIGGY = (206, 54, 48)        # the first boss's red
ZIGGY_LIT = (255, 128, 88)

LIFE = (232, 66, 88)         # the health bar, and red shards
MANA = (72, 168, 255)        # the special meter, and blue shards
GRAZE = (255, 214, 120)      # near-misses, and gold generally
POWER = (255, 168, 64)

# ---------------------------------------------------------------------------
# The console's own colours: gilt on indigo, the same on every stage.
# ---------------------------------------------------------------------------
ARCANE = (36, 26, 74)        # the console's ground: deep indigo-violet
ARCANE_LIT = (78, 54, 142)   # where the light falls on it
GILT = (196, 154, 74)        # filigree, rules, the frame -- old gold
GILT_LIT = (255, 226, 150)   # the highlight on a gilded edge
RUNE = (110, 224, 255)       # the arcane accent: Szuix's own eye-cyan

# Szuix's own magic, as opposed to his furniture: the violet of his wings for
# the sigil he casts, and the azure body of the fire he throws.
SIGIL = (150, 84, 255)
FLAME = (60, 168, 255)

# The mark ladder: STONE, BRONZE, SILVER, GOLD, AMETHYST. The rungs differ in
# hue as well as value. Amethyst is `SIGIL` lifted. Stone has no chroma and
# less value than silver, but stays well above `ARCANE` so the bottom medal is
# visible on the plate.
STONE = (118, 118, 132)      # smelted badly: cold, dull, and not quite grey
BRONZE = (176, 112, 62)      # the warm rung, so the low half is not all grey
AMETHYST = (186, 132, 255)   # SIGIL lifted: the top mark is his own magic

# The fourteen bullet hues: a colour wheel plus a neutral. Each is the rim; the
# core is always near-white.
BULLET_HUES = [
    ("crimson", (255, 40, 72)),
    ("ember",   (255, 116, 32)),
    ("amber",   (255, 186, 40)),
    ("gold",    (250, 232, 74)),
    ("lime",    (150, 240, 60)),
    ("jade",    (44, 220, 118)),
    ("spring",  (44, 226, 190)),
    ("cyan",    (56, 214, 255)),
    ("azure",   (68, 140, 255)),
    ("indigo",  (116, 92, 255)),
    ("violet",  (176, 84, 250)),
    ("magenta", (248, 72, 224)),
    ("rose",    (255, 128, 178)),
    ("bone",    (232, 238, 255)),   # the "white" bullet -- faintly blue
]

HUE_INDEX = {name: i for i, (name, _) in enumerate(BULLET_HUES)}


def hue(name):
    return BULLET_HUES[HUE_INDEX[name]][1]


def mix(a, b, t):
    """Blend two colours. `t` of 0 is all `a`."""
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, t):
    """Darken (t<0) or lighten (t>0) a colour."""
    return mix(c, (0, 0, 0) if t < 0 else (255, 255, 255), abs(t))


def rgba(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), int(a))


def gm_hex(c):
    """A colour as GameMaker's BGR literal, for pasting into constants.gml."""
    return "$%02X%02X%02X" % (c[2], c[1], c[0])


# ---------------------------------------------------------------------------
# The canvas
# ---------------------------------------------------------------------------

class Canvas:
    """An RGBA image drawn at `SS` times its final size.

    Coordinates passed to the helpers are in *final* pixels and scaled on the
    way in, so a generator never has to think about the supersample factor.
    """

    def __init__(self, w, h, ss=SS):
        self.w = int(w)
        self.h = int(h)
        self.ss = ss
        self.img = Image.new("RGBA", (self.w * ss, self.h * ss), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def s(self, v):
        return v * self.ss

    def rect(self, box, fill=None, outline=None, width=1):
        self.d.rectangle([self.s(v) for v in box], fill=fill,
                         outline=outline, width=max(1, int(self.s(width))))

    def round_rect(self, box, radius, fill=None, outline=None, width=1):
        self.d.rounded_rectangle([self.s(v) for v in box],
                                 radius=self.s(radius), fill=fill,
                                 outline=outline,
                                 width=max(1, int(self.s(width))))

    def ellipse(self, box, fill=None, outline=None, width=1):
        self.d.ellipse([self.s(v) for v in box], fill=fill,
                       outline=outline, width=max(1, int(self.s(width))))

    def line(self, points, fill, width=1, joint="curve"):
        pts = [(self.s(x), self.s(y)) for x, y in points]
        self.d.line(pts, fill=fill, width=max(1, int(self.s(width))),
                    joint=joint)

    def polygon(self, points, fill=None, outline=None):
        pts = [(self.s(x), self.s(y)) for x, y in points]
        self.d.polygon(pts, fill=fill, outline=outline)

    def arc(self, box, start, end, fill, width=1):
        self.d.arc([self.s(v) for v in box], start, end, fill=fill,
                   width=max(1, int(self.s(width))))

    def pieslice(self, box, start, end, fill=None, outline=None, width=1):
        self.d.pieslice([self.s(v) for v in box], start, end, fill=fill,
                        outline=outline, width=max(1, int(self.s(width))))

    def text(self, xy, s, fnt, fill, anchor="la"):
        self.d.text((self.s(xy[0]), self.s(xy[1])), s, font=fnt, fill=fill,
                    anchor=anchor)

    def paste_full(self, layer):
        """Composite a full-size (already supersampled) RGBA layer on top."""
        self.img.alpha_composite(layer)

    def add_full(self, layer):
        """Additively composite a full-size RGBA layer -- for anything lit."""
        self.img = add(self.img, layer)
        self.d = ImageDraw.Draw(self.img)

    def blur(self, radius):
        self.img = self.img.filter(ImageFilter.GaussianBlur(self.s(radius)))
        self.d = ImageDraw.Draw(self.img)

    def finish(self):
        """Downsample to final size. Call once, at the end."""
        if self.ss == 1:
            return self.img
        return self.img.resize((self.w, self.h), Image.LANCZOS)


def new_layer(canvas):
    """A transparent layer the same (supersampled) size as `canvas`."""
    return Image.new("RGBA", canvas.img.size, (0, 0, 0, 0))


def layer_draw(layer):
    return ImageDraw.Draw(layer)


# ---------------------------------------------------------------------------
# Compositing
# ---------------------------------------------------------------------------

def add(base, top):
    """Additive composite that respects `top`'s alpha.

    PIL's `ImageChops.add` ignores alpha entirely, so a glow layer with a
    transparent surround brightens the whole frame. Premultiplying by alpha
    first is what makes it behave like a light.
    """
    b = np.asarray(base, dtype=np.float32)
    t = np.asarray(top, dtype=np.float32)
    a = t[..., 3:4] / 255.0
    colour = np.clip(b[..., :3] + t[..., :3] * a, 0, 255)
    alpha = np.clip(b[..., 3:4] + t[..., 3:4], 0, 255)
    return Image.fromarray(
        np.concatenate([colour, alpha], axis=2).astype(np.uint8), "RGBA")


def over(base, top):
    out = base.copy()
    out.alpha_composite(top)
    return out


def from_arrays(colour, alpha):
    """An RGBA image from a float HxWx3 colour array and an HxW alpha array."""
    colour = np.clip(colour, 0, 255)
    alpha = np.clip(alpha, 0, 1) * 255.0
    return Image.fromarray(
        np.concatenate([colour, alpha[..., None]], axis=2).astype(np.uint8),
        "RGBA")


def grid(w, h, cx=None, cy=None):
    """Coordinate arrays for a w-by-h image, centred on (cx, cy).

    Returns (dx, dy, r) with r normalised so 1.0 is `min(w, h) / 2`.
    """
    cx = (w - 1) / 2.0 if cx is None else cx
    cy = (h - 1) / 2.0 if cy is None else cy
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = xs - cx
    dy = ys - cy
    return dx, dy, np.hypot(dx, dy) / (min(w, h) / 2.0)


# ---------------------------------------------------------------------------
# The bullet body
# ---------------------------------------------------------------------------

def orb_field(size, rim, core=(255, 255, 255), radius=0.86, core_at=0.34,
              rim_at=0.92, glow=0.30, squash=1.0, spec=True):
    """A round body: a white core inside a saturated rim.

    Returned at `size` square. This is a raw field, so pass it SS-scaled
    dimensions and downsample it with everything else.

    `core_at` is where the white has fully given way to the hue, `rim_at` where
    the hue starts darkening into the outline, and `radius` the edge. `glow` is
    how far light leaks past the edge.
    """
    dx, dy, _ = grid(size, size)
    r = np.hypot(dx, dy * squash) / (size / 2.0)

    rim = np.array(rim, dtype=np.float32)
    core = np.array(core, dtype=np.float32)
    edge = rim * 0.34                       # the darkened outline

    # Colour: white -> hue -> dark rim, as a function of radius.
    t1 = np.clip(r / max(1e-6, core_at), 0, 1) ** 0.85
    body = (core[None, None, :] * (1 - t1[..., None])
            + rim[None, None, :] * t1[..., None])
    t2 = np.clip((r - rim_at) / max(1e-6, radius - rim_at), 0, 1)
    body = body * (1 - t2[..., None]) + edge[None, None, :] * t2[..., None]

    # A specular kick up and left, so a field of them reads as lit from one
    # place rather than as a field of self-illuminated discs.
    if spec:
        sd = (np.hypot(dx + size * 0.17, dy * squash + size * 0.19)
              / (size / 2.0))
        body = body + (np.clip(1 - sd / 0.42, 0, 1) ** 2)[..., None] * 90.0

    # Alpha: solid to `radius`, then a soft halo of the hue.
    px = 2.0 / size                          # one pixel, in r units
    solid = np.clip((radius - r) / (px * 1.6), 0, 1)
    halo = np.clip(1 - (r - radius) / max(1e-6, glow), 0, 1) ** 2 * 0.55
    alpha = np.maximum(solid, np.where(r > radius, halo, 0))

    # Past the edge the colour is the hue itself, so the halo is coloured light
    # rather than a translucent ring of dark outline.
    outside = (r > radius)[..., None]
    body = np.where(outside, rim[None, None, :] * 1.15, body)

    return from_arrays(body, alpha)


# The largest side `depth_field` will run the transform at. Above this the
# mask is scaled down first -- see the note inside the function.
WORK_MAX = 520

_depth_cache = {}


def depth_field(mask, smooth=None):
    """Distance from the edge, inside a mask, normalised so its deepest is 1.

    Counted rather than approximated (a blurred mask fails on anything thinner
    than the blur): erode by one pixel and add what survives. `MinFilter` is a
    square kernel, so the raw result is Chebyshev distance; one small blur at
    the end rounds it back toward Euclidean.

    Normalised by the shape's own maximum, so a thin shape gets a core down its
    middle just as a round one gets one at its centre. Cached on the mask's
    bytes, since the field doesn't depend on the hue.
    """
    key = (mask.size, mask.tobytes())
    hit = _depth_cache.get(key)
    if hit is not None:
        return hit

    # Large masks are transformed at reduced scale: the cost is one erosion
    # pass per pixel of half-thickness, and distance from an edge is smooth
    # (and normalised), so the enlarged result loses nothing visible.
    full = mask.size
    work = mask
    if max(full) > WORK_MAX:
        k = WORK_MAX / max(full)
        work = mask.resize((max(8, int(full[0] * k)), max(8, int(full[1] * k))),
                           Image.BILINEAR)

    steps = int(min(work.size) / 2) + 2
    acc = np.zeros((work.size[1], work.size[0]), dtype=np.float32)
    cur = work
    for _ in range(steps):
        arr = np.asarray(cur, dtype=np.float32) / 255.0
        if arr.max() <= 0.0:
            break
        acc += arr
        cur = cur.filter(ImageFilter.MinFilter(3))

    peak = float(acc.max())
    if peak <= 0:
        return np.zeros((full[1], full[0]), dtype=np.float32)

    if smooth is None:
        smooth = max(1.0, peak * 0.16)
    field = (Image.fromarray(np.clip(acc / peak * 255, 0, 255).astype(np.uint8),
                             "L")
             .filter(ImageFilter.GaussianBlur(smooth)))
    if work.size != full:
        field = field.resize(full, Image.BILINEAR)
    acc = np.asarray(field, dtype=np.float32) / 255.0

    _depth_cache[key] = acc
    return acc


def shade_shape(mask, rim, core=(255, 255, 255), core_frac=0.42,
                edge_frac=0.30, spec=True, halo=0.0, edge_dark=0.34):
    """The core-inside-rim treatment for a shape that isn't a circle, shaded
    off `depth_field`.

    Three bands, deepest last: a dark lip over the outer `edge_frac` of the
    depth, the hue at full strength across the middle (which carries the
    colour), and white over the deepest `core_frac`.

    `halo` puts a soft bleed of the hue behind the body, never over it (over
    it, `add` would blow a near-white body out).
    """
    w, h = mask.size
    d = depth_field(mask)
    a = np.asarray(mask, dtype=np.float32) / 255.0

    rim = np.array(rim, dtype=np.float32)
    core = np.array(core, dtype=np.float32)

    body = np.empty((h, w, 3), dtype=np.float32)
    body[:] = rim

    lip = np.clip(1.0 - d / max(1e-6, edge_frac), 0, 1) ** 1.25
    body = (body * (1 - lip[..., None])
            + (rim * edge_dark)[None, None, :] * lip[..., None])

    hot = np.clip((d - (1.0 - core_frac)) / max(1e-6, core_frac), 0, 1) ** 0.85
    body = body * (1 - hot[..., None]) + core[None, None, :] * hot[..., None]

    if spec:
        _, _, r = grid(w, h, cx=w * 0.36, cy=h * 0.30)
        body = body + (np.clip(1 - r / 0.5, 0, 1) ** 2)[..., None] * 55.0

    out = from_arrays(body, a)
    if halo > 0:
        # Kept tight: a wider blur fills the canvas, which shows as a coloured
        # square behind the shape.
        spread = max(2.0, min(w, h) * 0.10)
        glow = Image.new("RGBA", mask.size, tuple(int(v) for v in rim) + (0,))
        glow.putalpha(mask.filter(ImageFilter.GaussianBlur(spread))
                          .point(lambda v: int(v * halo)))
        out = over(glow, out)
    return out


def soft_glow(size, colour, falloff=2.4, inner=0.0, alpha=255):
    """A soft circular glow as an RGBA image, `size` square. The falloff is a
    power curve, since a linear ramp shows a disc edge where it meets zero.
    """
    _, _, r = grid(size, size)
    a = np.where(r <= inner, 1.0,
                 np.clip(1 - (r - inner) / max(1e-6, 1.0 - inner), 0, 1)
                 ** falloff)
    a = np.where(r >= 1.0, 0.0, a)
    body = np.zeros((size, size, 3), dtype=np.float32)
    body[:] = colour
    return from_arrays(body, a * (alpha / 255.0))


def trace_outline(img, width=1, colour=(0, 0, 0, 255)):
    """A hard outline traced around whatever is opaque in `img`, so a shape
    survives being drawn over its own colour.
    """
    a = img.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(int(width) * 2 + 1))
    ring = ImageChops.subtract(grown, a)
    out = Image.new("RGBA", img.size, tuple(colour[:3]) + (0,))
    out.putalpha(ring.point(lambda v: int(v * colour[3] / 255)))
    return out


# ---------------------------------------------------------------------------
# Cut bodies: bullets, shards, and anything else that must read as an object
#
# A cut body is lit from inside rather than by a lamp: no highlight direction,
# bands of constant width in final pixels (a dark lip, a saturated rim, a lit
# interior) rather than ramps, and drawn internal structure (facets, engraved
# lines, glyphs). A shape hands `cut_shade` up to four masks: `body` is what
# exists, `groove` is cut into it dark, `bevel` is the planes that face the
# light, and `core` is the small hot centre. `cut_finish` then lays a dark
# contour and a tight bloom round the outside.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Drawing the masks a cut body is made of
#
# Everything here is in final pixels; `Cut` applies the supersample factor.
# ---------------------------------------------------------------------------

def ngon_pts(cx, cy, r, n, turn=-90.0):
    return [(cx + math.cos(math.radians(turn + i * 360.0 / n)) * r,
             cy + math.sin(math.radians(turn + i * 360.0 / n)) * r)
            for i in range(n)]


def star_pts(cx, cy, r, points, inner, turn=-90.0):
    pts = []
    for i in range(points * 2):
        ang = math.radians(turn + i * 180.0 / points)
        rad = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    return pts


def polar(cx, cy, ang, r):
    return (cx + math.cos(math.radians(ang)) * r,
            cy + math.sin(math.radians(ang)) * r)


class Cut:
    """The masks of one cut body: `body` (what exists), `groove` (cut into it),
    `bevel` (what catches the light) and `core` (the hot centre). `body` is
    always drawn; the others are dropped on the way out if nothing was drawn in
    them.
    """

    NAMES = ("body", "groove", "bevel", "core")

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cx, self.cy = (w - 1) / 2.0, (h - 1) / 2.0
        self.L = {n: Image.new("L", (w * SS, h * SS), 0) for n in self.NAMES}
        self.D = {n: ImageDraw.Draw(v) for n, v in self.L.items()}

    # -- primitives ---------------------------------------------------------

    def _p(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def _w(self, wid):
        return max(1, int(round(wid * SS)))

    def poly(self, layer, pts, v=255):
        self.D[layer].polygon(self._p(pts), fill=v)

    def disc(self, layer, cx, cy, r, v=255):
        self.D[layer].ellipse([(cx - r) * SS, (cy - r) * SS,
                               (cx + r) * SS, (cy + r) * SS], fill=v)

    def annulus(self, layer, cx, cy, r_out, r_in, v=255):
        self.disc(layer, cx, cy, r_out, v)
        self.disc(layer, cx, cy, r_in, 0)

    def hoop(self, layer, cx, cy, r, wid, v=255):
        """A ring centred on `r`, not inscribed in it: PIL draws an ellipse's
        outline inward from its bounding box, so a hoop asked for at a radius
        would otherwise sit half a width inside it.
        """
        rr = r + wid / 2.0
        self.D[layer].ellipse([(cx - rr) * SS, (cy - rr) * SS,
                               (cx + rr) * SS, (cy + rr) * SS],
                              outline=v, width=self._w(wid))

    def line(self, layer, pts, wid, v=255):
        self.D[layer].line(self._p(pts), fill=v, width=self._w(wid),
                           joint="curve")

    def ngon(self, layer, cx, cy, r, n, turn=-90.0, v=255):
        self.poly(layer, ngon_pts(cx, cy, r, n, turn), v)

    def ngon_line(self, layer, cx, cy, r, n, wid, turn=-90.0, v=255):
        pts = ngon_pts(cx, cy, r, n, turn)
        self.line(layer, pts + [pts[0]], wid, v)

    def star(self, layer, cx, cy, r, points, inner, turn=-90.0, v=255):
        self.poly(layer, star_pts(cx, cy, r, points, inner, turn), v)

    def spoke(self, layer, cx, cy, ang, r0, r1, wid, v=255):
        self.line(layer, [polar(cx, cy, ang, r0), polar(cx, cy, ang, r1)],
                  wid, v)

    def blur(self, layer, r):
        self.L[layer] = self.L[layer].filter(
            ImageFilter.GaussianBlur(r * SS))
        self.D[layer] = ImageDraw.Draw(self.L[layer])

    def parts(self):
        return {n: v for n, v in self.L.items()
                if n == "body" or v.getbbox() is not None}


def _shrink(a, diag):
    """One pixel of erosion: 4-neighbour, or 8-neighbour when `diag`."""
    p = np.pad(a, 1, mode="constant", constant_values=0.0)
    out = p[1:-1, 1:-1].copy()
    np.minimum(out, p[:-2, 1:-1], out=out)
    np.minimum(out, p[2:, 1:-1], out=out)
    np.minimum(out, p[1:-1, :-2], out=out)
    np.minimum(out, p[1:-1, 2:], out=out)
    if diag:
        np.minimum(out, p[:-2, :-2], out=out)
        np.minimum(out, p[:-2, 2:], out=out)
        np.minimum(out, p[2:, :-2], out=out)
        np.minimum(out, p[2:, 2:], out=out)
    return out


_edge_cache = {}


def edge_dist(mask, max_px, ss=SS):
    """Distance from the nearest edge, inside `mask`, in final pixels.

    Unnormalised (unlike `depth_field`), so a band drawn off it is a fixed
    number of pixels wide whatever shape it is on. Counted by erosion,
    alternating 4- and 8-neighbour so the metric is octagonal rather than
    Chebyshev (a square kernel is 41% generous along the diagonals). Stops at
    `max_px`, and is cached on the mask, since a shape is drawn once per hue.
    """
    key = (mask.size, mask.tobytes(), round(float(max_px), 3), ss)
    hit = _edge_cache.get(key)
    if hit is not None:
        return hit

    cur = (np.asarray(mask, dtype=np.float32) >= 128).astype(np.float32)
    acc = np.zeros_like(cur)
    for i in range(int(math.ceil(max_px * ss)) + 1):
        if cur.max() <= 0.0:
            break
        acc += cur
        cur = _shrink(cur, diag=(i % 2 == 1))

    out = acc / float(ss)
    _edge_cache[key] = out
    return out


# How deep `cut_shade` measures. Past this every pixel is interior, so a
# sphere and a bubble's wall get the same rim.
CUT_PROBE = 15.0


def _cut_layer(parts, name, alpha):
    """One structure mask as a 0..1 field, clipped to its body by
    multiplication rather than by a threshold. PIL resizes RGBA
    unpremultiplied, so a groove drawn a hair past the outline would otherwise
    arrive as a dark notch in the contour.
    """
    layer = parts.get(name)
    if layer is None:
        return None
    return (np.asarray(layer, dtype=np.float32) / 255.0) * alpha


def cut_shade(parts, rim, ss=SS, lip=None, band=None, lit_t=0.22,
              bevel_t=0.34, groove_k=0.70, deep_t=0.28):
    """Shade one cut body from its masks. Returns RGBA at the masks' size.

    Three bands out of `body`, measured in final pixels:

    - a lip of `rim * deep_t` at the edge (the bevel);
    - the hue at full chroma for `band` pixels, which carries the colour;
    - the interior, `lit_t` of the way to white (never white; that is the
      core's job).

    `lit_t` and `bevel_t` are small, so the body stays saturated and the small
    core carries the luminance. Then `bevel`, `groove` and `core` are laid in
    that order, so a groove cut through a lit plane shows as an engraved line.
    """
    body = parts["body"]
    w, h = body.size
    alpha = np.asarray(body, dtype=np.float32) / 255.0

    hue = np.array(rim, dtype=np.float32)
    deep = hue * deep_t
    lit = hue + (255.0 - hue) * lit_t
    bright = hue + (255.0 - hue) * bevel_t
    white = np.array((255.0, 255.0, 255.0), dtype=np.float32)

    d = edge_dist(body, CUT_PROBE, ss)
    half = float(d.max())
    if lip is None:
        lip = min(4.0, max(0.85, half * 0.17))
    if band is None:
        band = min(12.0, max(1.5, half * 0.34))

    col = np.empty((h, w, 3), dtype=np.float32)
    col[:] = deep
    col += (hue - deep) * (np.clip(d / lip, 0, 1) ** 0.85)[..., None]
    inner = np.clip((d - (lip + band)) / max(0.7, band * 0.42), 0, 1)
    col += (lit - col) * inner[..., None]

    bevel = _cut_layer(parts, "bevel", alpha)
    if bevel is not None:
        col += (bright - col) * bevel[..., None]
    groove = _cut_layer(parts, "groove", alpha)
    if groove is not None:
        col *= (1.0 - groove_k * groove)[..., None]
    core = _cut_layer(parts, "core", alpha)
    if core is not None:
        col += (white - col) * core[..., None]

    return from_arrays(col, alpha)


def cut_pad(contour=2.0, bloom_r=2.2):
    """How much empty canvas a cut body needs around it. The contour grows
    outward by its own width and the bloom is a Gaussian, so a shape drawn
    close to its canvas edge gets its outline and glow clipped flat. Two sigmas
    of blur puts the bloom under 1/200 of its peak, and `cut_finish` also
    windows the last two pixels to zero.
    """
    return int(math.ceil(contour + 2.2 * bloom_r))


def cut_finish(img, w, h, rim, contour=2.0, bloom=0.30, bloom_r=2.2,
               threshold=140, pad=None):
    """Downsample one cut body and lay its contour and its bloom round it.

    The contour is traced at the final size (a two-pixel ring drawn at `SS` and
    shrunk loses most of its alpha), around the body rather than the alpha (the
    bloom is fog), and under the body, so it takes pixels outside the
    silhouette instead of eating into the rim. It is the hue at an eighth
    rather than black: still near-black, but it keeps a warm bullet warm to its
    edge.
    """
    if pad is None:
        pad = cut_pad(contour, bloom_r)
    ww, hh = w + 2 * pad, h + 2 * pad

    small = Image.new("RGBA", (ww, hh), (0, 0, 0, 0))
    small.alpha_composite(img.resize((w, h), Image.LANCZOS), (pad, pad))

    solid = small.getchannel("A").point(lambda v: 255 if v >= threshold else 0)
    body = small.copy()
    body.putalpha(solid)

    ring = trace_outline(body, width=contour,
                         colour=tuple(int(c * 0.13) for c in rim) + (242,))
    out = over(ring.filter(ImageFilter.GaussianBlur(0.42)), small)

    if bloom > 0:
        grown = solid.filter(ImageFilter.MaxFilter(int(contour) * 2 + 1))
        a = np.asarray(grown.filter(ImageFilter.GaussianBlur(bloom_r)),
                       dtype=np.float32) * bloom
        # Window the border to zero whatever the blur did, so a glow never
        # ends in a straight line.
        ys, xs = np.mgrid[0:hh, 0:ww]
        edge = np.minimum.reduce([xs, ys, ww - 1 - xs, hh - 1 - ys])
        a *= np.clip(edge.astype(np.float32) / 2.0, 0, 1)
        glow = Image.new("RGBA", (ww, hh), tuple(int(c) for c in rim) + (0,))
        glow.putalpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "L"))
        out = over(glow, out)
    return out


# ---------------------------------------------------------------------------
# Gradients and texture
# ---------------------------------------------------------------------------

def vertical_gradient(w, h, top=None, bottom=None, stops=None):
    """A vertical gradient, optionally through a list of (t, colour) stops."""
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = gradient_at(stops, t) if stops else mix(top, bottom, t)
    return img.resize((w, h), Image.BILINEAR).convert("RGBA")


def gradient_at(stops, t):
    """Sample a list of (position, colour) stops, sorted by position."""
    if t <= stops[0][0]:
        return stops[0][1]
    if t >= stops[-1][0]:
        return stops[-1][1]
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t0 <= t <= t1:
            return mix(c0, c1, (t - t0) / max(1e-6, t1 - t0))
    return stops[-1][1]


def noise_layer(w, h, seed, scale=1, amount=18, colour=(255, 255, 255)):
    """Fine grain, for stone and cloth. Subtle -- it is texture, not dirt."""
    rnd = random.Random(seed)
    small = Image.new("L", (max(1, w // scale), max(1, h // scale)))
    small.putdata([rnd.randint(0, 255)
                   for _ in range(small.width * small.height)])
    if scale > 1:
        small = small.resize((w, h), Image.BILINEAR)
    solid = Image.new("RGBA", (w, h), tuple(colour) + (0,))
    solid.putalpha(small.point(lambda v: int(abs(v - 128) / 128 * amount)))
    return solid


def fbm_field(w, h, seed, octaves=4, base=4, wrap_y=False):
    """Fractal value noise as an L image, for fog, canopy masses and mottling:
    octaves of upsampled white noise at halving amplitude.

    `wrap_y` makes the field periodic top to bottom, which a scrolling layer
    needs: the noise grid's first row is repeated at its bottom before
    upsampling. (Cross-fading two fields only reduces the seam.)
    """
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    amp, total, freq = 1.0, 0.0, float(base)

    for _ in range(octaves):
        gw = max(2, int(round(freq)))
        gh = max(2, int(round(freq * h / w)))
        cell = rng.random((gh, gw), dtype=np.float32)
        if wrap_y:
            cell = np.vstack([cell, cell[:1]])
        layer = np.asarray(
            Image.fromarray((cell * 255).astype(np.uint8), "L")
                 .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
        acc += layer * amp
        total += amp
        amp *= 0.5
        freq *= 2

    acc /= max(1e-6, total)
    return Image.fromarray(np.clip(acc * 255, 0, 255).astype(np.uint8), "L")


def rim_light(mask, colour, drop=3, blur=1.5, strength=1.0):
    """Light the upward-facing edges of a silhouette: subtract a copy of the
    mask shifted down, which leaves the top edge of every lump. It keeps a dark
    mass from reading as a hole.
    """
    lowered = ImageChops.offset(mask, 0, drop)
    edge = ImageChops.subtract(mask, lowered)
    edge = edge.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", mask.size, tuple(colour) + (0,))
    out.putalpha(edge.point(lambda v: int(min(255, v * strength))))
    return out


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

_font_cache = {}


def font(name, size, weight=None):
    """Load one of the bundled OFL fonts. Cinzel is a variable font, so a
    weight is selected rather than a file loaded. The system's Microsoft fonts
    are not used: their licence doesn't allow baking them into a game.
    """
    key = (name, size, weight)
    if key in _font_cache:
        return _font_cache[key]
    f = ImageFont.truetype(os.path.join(FONT_DIR, name), size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    _font_cache[key] = f
    return f


CINZEL = "Cinzel-var.ttf"
SPECTRAL = "Spectral-Regular.ttf"
SPECTRAL_MED = "Spectral-Medium.ttf"
SPECTRAL_SEMI = "Spectral-SemiBold.ttf"


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def preview(images, path, cols=None, bg=(20, 22, 34), pad=10, labels=None):
    """Tile images into one PNG so a generator's output can be looked at."""
    if not images:
        return
    cols = cols or min(len(images), 8)
    rows = (len(images) + cols - 1) // cols
    cw = max(i.width for i in images)
    ch = max(i.height for i in images)
    lab = 14 if labels else 0

    sheet = Image.new("RGBA",
                      (cols * (cw + pad) + pad, rows * (ch + lab + pad) + pad),
                      tuple(bg) + (255,))
    d = ImageDraw.Draw(sheet)
    small = font(SPECTRAL, 11)
    for i, img in enumerate(images):
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (ch + lab + pad)
        sheet.alpha_composite(img, (x + (cw - img.width) // 2,
                                    y + (ch - img.height) // 2))
        if labels and i < len(labels):
            d.text((x + cw // 2, y + ch + 2), labels[i], font=small,
                   fill=(170, 178, 200, 255), anchor="ma")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    return sheet


def checker(w, h, a=(150, 150, 158), b=(120, 120, 128), size=8):
    """A mid-grey checker, for previewing anything whose alpha matters."""
    img = Image.new("RGBA", (w, h), tuple(a) + (255,))
    d = ImageDraw.Draw(img)
    for y in range(0, h, size):
        for x in range(0, w, size):
            if (x // size + y // size) % 2:
                d.rectangle([x, y, x + size - 1, y + size - 1],
                            fill=tuple(b) + (255,))
    return img
