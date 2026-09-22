#!/usr/bin/env python3
"""Stage one's three parallax layers (ground, rock, near).

- Every layer tiles seamlessly top to bottom (the world scrolls down
  forever). Layers are shaded three tiles tall and cropped to the middle
  (`shade_wrapped`), or built from fields periodic in y
  (`A.fbm_field(wrap_y=True)`, `worley`). `check_bg_seams` measures the join.
- Farther layers are hazed toward the air colour.
- The near layer is drawn over the field, so it keeps to the left and right
  edges (`NEAR_EDGE`); `check_bg_keepout` measures it.

The rock surface is built from layered fields: a Voronoi joint network
(`worley`), mottle and grain at two scales each, `rim_light`, and haze.

Usage:
    python tools/make_bg.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

# The layers are field-sized (the playfield is a window onto them).
W, H = A.FIELD_W, A.FIELD_H

# The share of the width at each edge the near layer may occupy. Must equal
# `BG_NEAR_EDGE` in `scripts/constants` (`check_bg_keepout` measures the PNG).
NEAR_EDGE = 0.13

# The Voronoi and mottle fields are smooth, so they are computed at half
# resolution and enlarged.
HALF = 2


class Brimstone:
    """Stage one's palette: a basalt pavement cracked open over lava. Kept very
    dark so the bullets read against it; only the lava is bright, and it is
    narrow, deep orange and never white.
    """

    name = "brim"
    # Kept very dark: only the narrow lava is bright.
    air = (26, 10, 9)             # what distance fades toward
    ground = (11, 8, 10)
    ground_lit = (29, 19, 18)
    ground_cool = (13, 12, 17)    # the other rock, so the floor is not one hue
    rock = (14, 10, 11)
    rock_lit = (37, 21, 19)
    # The near layer is slightly lighter, as the closest layer and the only
    # one with a silhouette.
    near = (10, 6, 8)
    near_lit = (34, 19, 18)
    lava = (150, 44, 11)
    lava_hot = (226, 108, 30)
    ember = (255, 132, 48)
    joint = (5, 3, 5)             # the dark in a crack, before it is lit


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

def worley(w, h, n, seed, wrap_y=True):
    """Distance to the nearest and second-nearest of `n` scattered points.
    `f2 - f1` is small on cell boundaries, giving a crack network that looks
    like basalt joints. With `wrap_y`, the points are replicated a tile above
    and below so the result tiles vertically.

    Returns `(f1, f2, cell)` at `w` by `h`, distances in pixels.
    """
    rng = np.random.default_rng(seed)
    px = rng.uniform(0, w, n).astype(np.float32)
    py = rng.uniform(0, h, n).astype(np.float32)
    if wrap_y:
        px = np.concatenate([px, px, px])
        py = np.concatenate([py - h, py, py + h])

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    big = np.float32(1e12)
    f1 = np.full((h, w), big, dtype=np.float32)
    f2 = np.full((h, w), big, dtype=np.float32)
    cell = np.zeros((h, w), dtype=np.int32)

    for i in range(px.size):
        d = (xs - px[i]) ** 2 + (ys - py[i]) ** 2
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cell = np.where(closer, i % n, cell)
        f1 = np.where(closer, d, f1)

    return np.sqrt(f1), np.sqrt(f2), cell


def plate_field(w, h, n, seed):
    """The joint network and a per-plate tone, both at `w` by `h`. `edge` is 1
    in the middle of a groove and 0 well inside a plate; `tone` is one value
    per plate.
    """
    f1, f2, cell = worley(w // HALF, h // HALF, n, seed)
    gap = (f2 - f1) * HALF                      # back into full-size pixels

    # A groove a few pixels wide with soft shoulders; squaring the ramp keeps
    # plate interiors clean.
    edge = np.clip(1.0 - gap / 26.0, 0, 1) ** 2.2

    rng = np.random.default_rng(seed + 7717)
    tone = rng.random(n).astype(np.float32)[cell]

    up = lambda a: np.asarray(
        Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "L")
             .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    return up(edge), up(tone)


def fbm(w, h, seed, octaves=5, base=6):
    """`A.fbm_field`, periodic in y, as a 0..1 float array."""
    return np.asarray(A.fbm_field(w, h, seed, octaves=octaves, base=base,
                                  wrap_y=True), dtype=np.float32) / 255.0


def grain(w, h, seed, amount=0.055):
    """Fine grain at two scales, periodic in y."""
    a = fbm(w, h, seed, octaves=2, base=w // 3)
    b = fbm(w, h, seed + 4001, octaves=2, base=w // 9)
    return ((a - 0.5) * amount + (b - 0.5) * amount * 0.8)


def shade_wrapped(mask3, colour, core, core_frac, edge_frac):
    """Shade a 3H-tall mask and return its middle third, so the distance-field
    shading sees across the wrap (shaded at one tile's height, shapes crossing
    the edge are lit as if they ended there, which leaves a seam).
    """
    body = A.shade_shape(mask3, colour, core=core, core_frac=core_frac,
                         edge_frac=edge_frac, spec=False)
    return body.crop((0, H, W, H * 2))


def _haze(img, air, amount):
    """Fade a layer toward the colour of the air."""
    arr = np.asarray(img, dtype=np.float32)
    arr[..., :3] = (arr[..., :3] * (1 - amount)
                    + np.array(air, dtype=np.float32) * amount)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# ---------------------------------------------------------------------------
# The floor
# ---------------------------------------------------------------------------

def make_ground(p, seed=1):
    """The floor: plates, a tone per plate, the grooves between them, fissures
    across them, then the light from below.
    """
    rng = np.random.default_rng(seed)

    # 210 plates on the floor, against 90 in the middle distance and 55 in the
    # foreground: the plate size shows the depth.
    edge, tone = plate_field(W, H, 210, seed)
    broad = fbm(W, H, seed + 11, octaves=5, base=4)     # patches of rock
    fine = fbm(W, H, seed + 23, octaves=4, base=22)     # what is on them

    lo = np.array(p.ground, dtype=np.float32)
    hi = np.array(p.ground_lit, dtype=np.float32)
    cool = np.array(p.ground_cool, dtype=np.float32)

    # Two rock colours mixed at a large scale, so the floor isn't one hue.
    base = lo[None, None, :] + (hi - lo)[None, None, :] * (broad ** 1.5)[..., None]
    base = base * (1 - (broad ** 3)[..., None] * 0.45) \
         + cool[None, None, :] * (broad ** 3)[..., None] * 0.45

    # Each plate a shade of its own, so the pavement is many stones.
    base *= (0.72 + 0.56 * tone)[..., None]

    # Fine variation and then tooth.
    base *= (0.86 + 0.28 * fine)[..., None]
    base *= (1.0 + grain(W, H, seed + 91))[..., None]

    # The grooves, darkened into the stone.
    base *= (1.0 - edge * 0.82)[..., None]

    # ...and the lit lip either side of each groove (the gradient of the edge
    # field, by one shifted subtraction).
    lip = np.clip(np.roll(edge, 5, axis=0) - edge, 0, 1)
    base += np.array(p.lava, dtype=np.float32)[None, None, :] * (lip * 0.16)[..., None]

    img = A.from_arrays(base, np.ones((H, W), dtype=np.float32))

    # The fissures: cracks open enough to see fire in. Each crack's wander is
    # de-trended (the accumulated drift subtracted in proportion to depth
    # down the tile), so it ends at the bottom where it started at the top and
    # the layer tiles.
    H3 = H * 3
    crack = Image.new("L", (W, H3), 0)
    cd = ImageDraw.Draw(crack)
    for _ in range(7):
        x0 = rng.uniform(0, W)
        x = x0
        raw = []
        n = 90
        for i in range(n):
            raw.append(x)
            x += rng.normal(0, 11)
        drift = raw[-1] - raw[0]
        pts = [(raw[i] - drift * (i / (n - 1)), i * H / (n - 1))
               for i in range(n)]

        wide = int(rng.uniform(3, 8))
        branches = []
        for _ in range(3):
            i = int(rng.integers(6, n - 8))
            bx, by = pts[i]
            bp = [(bx, by)]
            ang = rng.uniform(-70, 70)
            for _k in range(9):
                ang += rng.normal(0, 16)
                bx += math.cos(math.radians(ang)) * 30
                by += math.sin(math.radians(ang)) * 30
                bp.append((bx, by))
            branches.append(bp)

        for dy in (0, H, H * 2):
            cd.line([(px_, py_ + dy) for px_, py_ in pts], fill=255,
                    width=wide, joint="curve")
            for bp in branches:
                cd.line([(px_, py_ + dy) for px_, py_ in bp], fill=205,
                        width=max(2, wide // 2), joint="curve")

    # Three glows: a wide dim wash near each fissure, a tight glow that is the
    # fire, and a thread of the hottest colour down the widest cracks. None
    # near white.
    wide_glow = Image.new("RGBA", (W, H3), A.rgba(p.lava, 0))
    # The wash is additive over every fissure's neighbourhood, so overlapping
    # washes add up; it is kept dim for that reason.
    wide_glow.putalpha(crack.filter(ImageFilter.GaussianBlur(68))
                            .point(lambda v: int(min(255, v * 0.58))))
    core = Image.new("RGBA", (W, H3), A.rgba(p.lava_hot, 0))
    core.putalpha(crack.filter(ImageFilter.GaussianBlur(2.4))
                       .point(lambda v: int(v * 0.58)))

    img = A.add(img, wide_glow.crop((0, H, W, H * 2)))
    img = A.add(img, core.crop((0, H, W, H * 2)))

    # A dim glow along the plate joints too.
    seep = Image.new("RGBA", (W, H), A.rgba(p.lava, 0))
    seep.putalpha(Image.fromarray(
        np.clip(edge * 255, 0, 255).astype(np.uint8), "L")
        .filter(ImageFilter.GaussianBlur(9)).point(lambda v: int(v * 0.085)))
    img = A.add(img, seep)

    # Hazed toward the air (the farthest layer).
    return _haze(img, p.air, 0.38)


# ---------------------------------------------------------------------------
# The middle distance
# ---------------------------------------------------------------------------

def make_rock(p, seed=2):
    """The middle layer: lobed plateaus and boulders, shaded, with plate
    joints, per-plate tone, grain and a rim light.
    """
    rng = np.random.default_rng(seed)
    # Three tiles tall, so shading sees across the wrap. See `shade_wrapped`.
    mask = Image.new("L", (W, H * 3), 0)
    md = ImageDraw.Draw(mask)

    def blob(dy, cx, cy, rx, ry, lobes):
        pts = []
        for i in range(lobes):
            ang = 2 * math.pi * i / lobes
            k = rng.uniform(0.68, 1.0)
            pts.append((cx + math.cos(ang) * rx * k,
                        cy + dy + math.sin(ang) * ry * k))
        md.polygon(pts, fill=255)

    for _ in range(18):
        cx = rng.uniform(-100, W + 100)
        cy = rng.uniform(0, H)
        rx = rng.uniform(90, 310)
        ry = rng.uniform(60, 180)
        lobes = int(rng.integers(7, 12))
        state = rng.bit_generator.state
        for dy in (0, H, H * 2):
            rng.bit_generator.state = state       # the same blob, three places
            blob(dy, cx, cy, rx, ry, lobes)

    # Barely blurred (a soft edge at this distance reads as fog).
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    body = shade_wrapped(mask, p.rock_lit, A.shade(p.rock_lit, 0.28),
                         0.30, 0.44)

    # Joints, tone and grain, multiplied into the shaded body.
    edge, tone = plate_field(W, H, 90, seed + 5)
    fine = fbm(W, H, seed + 31, octaves=4, base=16)
    k = (1.0 - edge * 0.66) * (0.78 + 0.44 * tone) * (0.88 + 0.24 * fine)
    k = k * (1.0 + grain(W, H, seed + 77))

    arr = np.asarray(body, dtype=np.float32)
    arr[..., :3] *= k[..., None]
    body = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # The rim: the mask minus a copy shifted down leaves the top edge of every
    # lump, lit.
    rim = A.rim_light(mask, p.lava_hot, drop=6, blur=2.4, strength=0.55)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), mask))
    rim = rim.crop((0, H, W, H * 2))

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(body)
    out = A.add(out, rim)
    return _haze(out, p.air, 0.12)


# ---------------------------------------------------------------------------
# The foreground
# ---------------------------------------------------------------------------

def make_near(p, seed=3):
    """Spires up the two edges and nothing in the middle (it is drawn over the
    field).
    """
    rng = np.random.default_rng(seed)
    mask = Image.new("L", (W, H * 3), 0)      # see `shade_wrapped`
    md = ImageDraw.Draw(mask)
    edge_px = W * NEAR_EDGE

    for side in (0, 1):
        for _ in range(9):
            base_x = rng.uniform(-60, edge_px * 0.85)
            if side:
                base_x = W - base_x
            cy = rng.uniform(0, H)
            hgt = rng.uniform(220, 520)
            wid = rng.uniform(70, 175)
            lean = rng.uniform(-26, 26)
            # A tall column with a broken top (columnar basalt).
            state = rng.bit_generator.state
            for dy in (0, H, H * 2):
                rng.bit_generator.state = state
                top = cy + dy - hgt * 0.5
                bot = cy + dy + hgt * 0.5
                pts = [(base_x - wid * 0.50, bot),
                       (base_x - wid * 0.34 + lean * 0.7, top + hgt * 0.30),
                       (base_x - wid * 0.28 + lean, top + hgt * 0.06),
                       (base_x - wid * 0.05 + lean, top),
                       (base_x + wid * 0.16 + lean, top + hgt * 0.11),
                       (base_x + wid * 0.31 + lean, top + hgt * 0.04),
                       (base_x + wid * 0.38 + lean * 0.6, top + hgt * 0.34),
                       (base_x + wid * 0.50, bot)]
                md.polygon(pts, fill=255)

    mask = mask.filter(ImageFilter.GaussianBlur(1.4))

    # The keep-out is enforced by a window that reaches zero at the boundary,
    # rather than by constraining each spire.
    xs = np.arange(W, dtype=np.float32)
    window = np.clip(np.minimum(xs, W - 1 - xs) / edge_px, 0, 1)
    window = (1.0 - window) ** 1.5
    mask = Image.fromarray(
        (np.asarray(mask, dtype=np.float32) * window[None, :])
        .astype(np.uint8), "L")

    body = shade_wrapped(mask, p.near_lit, A.shade(p.near, 0.10), 0.20, 0.46)

    # The same treatment as the middle distance, with bigger plates.
    edge, tone = plate_field(W, H, 55, seed + 3)
    k = (1.0 - edge * 0.72) * (0.80 + 0.40 * tone)
    k = k * (1.0 + grain(W, H, seed + 61, amount=0.075))
    arr = np.asarray(body, dtype=np.float32)
    arr[..., :3] *= k[..., None]
    body = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    rim = A.rim_light(mask, p.ember, drop=5, blur=2.2, strength=1.05)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), mask))
    rim = rim.crop((0, H, W, H * 2))

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(body)
    return A.add(out, rim)


def keepout_columns(img):
    """The leftmost and rightmost columns the layer puts any ink in."""
    a = np.asarray(img.getchannel("A"), dtype=np.uint8)
    cols = (a > 12).any(axis=0)
    if not cols.any():
        return None
    idx = np.nonzero(cols)[0]
    return int(idx[0]), int(idx[-1])


PALETTES = [Brimstone]


def main():
    gm_new.folder("Sprites/bg")
    shown = []
    labels = []

    for p in PALETTES:
        ground = make_ground(p)
        rock = make_rock(p)
        near = make_near(p)

        # The keep-out is asserted here too (also `check_bg_keepout`).
        inner_l = W * NEAR_EDGE
        inner_r = W * (1 - NEAR_EDGE)
        cols = np.asarray(near.getchannel("A"), dtype=np.uint8) > 12
        middle = cols[:, int(inner_l):int(inner_r)]
        if middle.any():
            raise SystemExit(
                "the near layer for %s puts ink in the middle of the screen "
                "(columns %d..%d are reserved for the field)"
                % (p.name, inner_l, inner_r))

        for name, img in (("ground", ground), ("rock", rock), ("near", near)):
            gm_new.sprite("spr_bg_%s_%s" % (p.name, name), [img],
                          origin="topleft", folder="Sprites/bg")
            shown.append(img.resize((W // 4, H // 4), Image.LANCZOS))
            labels.append("%s %s" % (p.name, name))

        # The three layers stacked...
        stack = Image.new("RGBA", (W, H), A.rgba(p.air, 255))
        stack.alpha_composite(ground)
        stack.alpha_composite(rock)
        stack.alpha_composite(near)
        stack.resize((W // 2, H // 2), Image.LANCZOS).save(
            os.path.join(A.PREVIEW, "bg_%s.png" % p.name))

        # ...and a 1:1 crop.
        stack.crop((W // 2 - 440, H // 2 - 250, W // 2 + 440, H // 2 + 250)) \
             .save(os.path.join(A.PREVIEW, "bg_%s_detail.png" % p.name))
        print("%s: 3 layers of %dx%d" % (p.name, W, H))

    A.preview(shown, os.path.join(A.PREVIEW, "bg_layers.png"), cols=3,
              bg=(18, 12, 14), labels=labels)


if __name__ == "__main__":
    main()
