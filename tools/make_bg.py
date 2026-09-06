#!/usr/bin/env python3
"""The parallax layers a stage scrolls past.

**Every layer tiles seamlessly top to bottom**, because the world moves down
the screen forever and a seam is the one artefact a player cannot un-see.
Everything is therefore drawn three tiles tall and cropped to the middle, or
generated from a field that is periodic in y by construction; `shade_wrapped`
and `A.fbm_field(wrap_y=True)` are the two routes and nothing here takes a
third. `check_bg_seams` in `tools/check_project.py` measures the join.

**Depth is value, not detail.** The rule the Wordsearch backgrounds are built
on holds here for the same reason: the further away something is, the closer
its colour is to the ambient light -- so the deepest layer is hazed almost to
the colour of the air and only the nearest is allowed real contrast.

**The near layer keeps out of the middle.** It is drawn *over* the field, so
anything it puts in the centre of the screen is something a bullet can hide
behind. It lives in the left and right sixths. `check_bg_keepout` measures it.

Texture, and why there is so much of it
---------------------------------------

The first version of this stage was six polygon calls and one noise field per
layer, and photographed at 1:1 that is exactly what it looked like: flat brown
masses with orange squiggles laid over them. It read as *drawn by a script*,
which next to a commissioned player sprite is the one thing scenery cannot
afford to read as.

So the rock is built the way the Wordsearch slabs are, out of layers that each
answer a different question about the surface:

`worley`      where the stone is jointed -- the plate boundaries
mottle        what colour this patch of rock happens to be, at two scales
grain         what it feels like at arm's length, at two scales
`rim_light`   which edges the light from below is catching
haze          how far away it is

None of them is expensive and none is representational. What makes the result
read as rock rather than as noise is that the joint network is a *Voronoi*
diagram: real basalt cools into polygonal columns, so plates meeting at
three-way junctions at consistent angles is not a stylisation, it is what the
material does. Nothing else here has to be drawn once that is right.

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

# **The size of the field, not of the screen.** These layers are the world the
# playfield is a window onto, and since the window became a rectangle inside
# the screen rather than the whole of it, a 1920-wide layer would be a fifth of
# its own art hidden under the HUD margin -- including a third of the near
# layer's spires, which would leave the field with a foreground down one side
# and nothing down the other.
W, H = A.FIELD_W, A.FIELD_H

# The share of the width at each edge the near layer may occupy. The rest is
# the field, and the field belongs to the bullets. **Mirrored in
# `scripts/constants` as `BG_NEAR_EDGE`**, which is what `check_bg_keepout`
# measures the shipped PNG against -- the two have to be edited together.
NEAR_EDGE = 0.13

# Voronoi and the two mottle fields are computed at half resolution and
# enlarged. Every one of them is a *smooth* field being used as a shading ramp,
# so the only thing full resolution would buy is four times the runtime; the
# joint grooves are drawn from the field rather than being the field, and they
# get their crispness from the threshold, not from the sampling.
HALF = 2


class Brimstone:
    """Stage one: a basalt pavement cracked open over something molten.

    **Dark, and deliberately much darker than it wants to be.** A background
    for a bullet hell is not a picture, it is the ground a picture is drawn on:
    two thousand lit bullets have to read against it in a fifth of a second,
    and every point of value spent on the scenery is a point the bullets no
    longer have. The first pass of this was a handsome mid-brown ravine and it
    was useless -- an amber bullet over it was invisible.

    So the rock is nearly black and the only bright thing is the lava, which is
    narrow, deep orange, and never white. White is what a bullet's core is.
    """

    name = "brim"
    #
    # **Every one of these came down by about forty per cent after the first
    # textured pass was photographed.** The texture was right and the values
    # were not: a jointed pavement at these hues and twice this brightness is a
    # handsome mid-brown floor, and a handsome mid-brown floor is precisely
    # what the flat version of this stage was replaced for. Detail does not
    # earn a background any extra value budget -- if anything it costs some,
    # because a busy surface competes for attention in a way a flat one does
    # not, and the thing it is competing with is the bullets.
    #
    # The only bright thing on the stage is the lava, and it is narrow.
    air = (26, 10, 9)             # what distance fades toward
    ground = (11, 8, 10)
    ground_lit = (29, 19, 18)
    ground_cool = (13, 12, 17)    # the other rock, so the floor is not one hue
    rock = (14, 10, 11)
    rock_lit = (37, 21, 19)
    # The one layer allowed a little more than the rest. It is the closest
    # thing to the camera and the only one with a silhouette, so it is where
    # the depth actually comes from -- taken down with everything else in the
    # darkening pass it stopped being visible at all, which is a layer being
    # paid for and not delivered.
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

    `f2 - f1` is small exactly on the boundary between two cells, which is the
    canonical cheap crack network -- and for basalt it is not a stylisation:
    cooling lava contracts into polygonal columns, so plate boundaries really
    do meet three at a time at something near 120 degrees. Drawing the joints
    by hand as strokes is what makes rock look like a doodle of rock; letting
    the plates decide where their own edges are is what stops it.

    **The points are replicated a tile above and a tile below**, which is the
    whole of what makes the result periodic in y. Without it every cell along
    the top edge is bounded by the canvas rather than by its neighbour, and the
    joint network arrives at the bottom of the tile disagreeing with the top --
    the same failure `shade_wrapped` exists to fix, one layer down.

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
    """The joint network and a per-plate tone, both at `w` by `h`.

    `edge` is 1 in the middle of a groove and 0 well inside a plate; `tone` is
    one value per plate, so no two neighbouring stones are the same colour.
    """
    f1, f2, cell = worley(w // HALF, h // HALF, n, seed)
    gap = (f2 - f1) * HALF                      # back into full-size pixels

    # A groove a few pixels wide, with soft shoulders. Squaring the ramp keeps
    # the middle of a plate perfectly clean -- a linear falloff shades the
    # whole stone toward its own edges and the floor turns into a quilt.
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
    """Fine tooth, at two scales.

    **Two, because one reads as film noise and two as stone** -- the same
    finding the Wordsearch slabs are built on. It goes through `fbm_field`
    rather than through `A.noise_layer` for one reason only: this has to be
    periodic in y, and white noise is not.
    """
    a = fbm(w, h, seed, octaves=2, base=w // 3)
    b = fbm(w, h, seed + 4001, octaves=2, base=w // 9)
    return ((a - 0.5) * amount + (b - 0.5) * amount * 0.8)


def shade_wrapped(mask3, colour, core, core_frac, edge_frac):
    """Shade a 3H-tall mask and return its middle third.

    **A layer that tiles has to be *shaded* tall and cropped, not shaded at its
    own height.** `shade_shape` works off a distance field, and a distance
    field measured on a one-tile canvas treats the canvas edge as the edge of
    the shape -- so a boulder crossing the top of the tile is lit as though it
    ended there, while the copy of it drawn at the bottom is lit as though it
    ended *there*. The two do not match, and what that produces is a hard
    horizontal line across the screen every time the layer wraps. The first
    screenshot of this stage had two of them.
    """
    body = A.shade_shape(mask3, colour, core=core, core_frac=core_frac,
                         edge_frac=edge_frac, spec=False)
    return body.crop((0, H, W, H * 2))


def _haze(img, air, amount):
    """Fade a layer toward the colour of the air. Distance, in one line."""
    arr = np.asarray(img, dtype=np.float32)
    arr[..., :3] = (arr[..., :3] * (1 - amount)
                    + np.array(air, dtype=np.float32) * amount)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# ---------------------------------------------------------------------------
# The floor
# ---------------------------------------------------------------------------

def make_ground(p, seed=1):
    """The floor: a jointed basalt pavement with fire under it.

    Built in the order the material was: the plates, then what colour each of
    them happens to be, then the grooves between them, then the fissures that
    cut across the lot, then the light coming up through both.
    """
    rng = np.random.default_rng(seed)

    # 210 plates on the floor against 90 on the middle distance and 55 on the
    # foreground. **The scale of the joint network is doing depth work**: the
    # same rock at three distances has the same plates at three apparent sizes,
    # and that reads as distance far more strongly than the haze does, because
    # it survives the haze being subtle.
    edge, tone = plate_field(W, H, 210, seed)
    broad = fbm(W, H, seed + 11, octaves=5, base=4)     # patches of rock
    fine = fbm(W, H, seed + 23, octaves=4, base=22)     # what is on them

    lo = np.array(p.ground, dtype=np.float32)
    hi = np.array(p.ground_lit, dtype=np.float32)
    cool = np.array(p.ground_cool, dtype=np.float32)

    # **Two rocks, not one.** A floor mixed between a warm stone and a cold one
    # at a large scale stops the whole layer reading as a single flat hue, and
    # it costs one lerp. This is the part that does the most for how expensive
    # the ground looks and the least to the frame budget.
    base = lo[None, None, :] + (hi - lo)[None, None, :] * (broad ** 1.5)[..., None]
    base = base * (1 - (broad ** 3)[..., None] * 0.45) \
         + cool[None, None, :] * (broad ** 3)[..., None] * 0.45

    # Each plate a shade of its own, so the pavement is many stones.
    base *= (0.72 + 0.56 * tone)[..., None]

    # Fine variation and then tooth.
    base *= (0.86 + 0.28 * fine)[..., None]
    base *= (1.0 + grain(W, H, seed + 91))[..., None]

    # The grooves. Darkened rather than drawn: a joint is an absence of stone,
    # and a dark line laid *on* the stone reads as a line drawn on a floor.
    base *= (1.0 - edge * 0.82)[..., None]

    # ...and the lip of stone either side of a groove, catching what light
    # there is from below. `rim_light` does this for a silhouette; here the
    # shape is the groove itself, so it is the gradient of the edge field that
    # is wanted, and one shifted subtraction is that.
    lip = np.clip(np.roll(edge, 5, axis=0) - edge, 0, 1)
    base += np.array(p.lava, dtype=np.float32)[None, None, :] * (lip * 0.16)[..., None]

    img = A.from_arrays(base, np.ones((H, W), dtype=np.float32))

    # The fissures: the cracks that are open far enough to see fire in.
    #
    # **A crack has to arrive at the bottom of the tile where it left the
    # top.** Left to wander freely it does not, and what that produces is a
    # line of orange that jumps sideways every time the layer wraps -- which
    # measured as a join delta of 5.2 against an adjacent-row delta of 0.2, and
    # read on screen as a horizontal fault across the whole floor.
    #
    # So the wander is *de-trended*: the accumulated drift is subtracted back
    # out in proportion to how far down the tile each point is, which pins the
    # last point to the first without flattening the wander in between.
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

    # Three glows and they do different jobs: a wide, dim wash saying the rock
    # near a fissure is warm; a tight one that is the fire itself; and a thread
    # of the hottest colour down the middle of the widest cracks. None goes
    # near white -- the one thing on this screen allowed to be white is a
    # bullet's core.
    wide_glow = Image.new("RGBA", (W, H3), A.rgba(p.lava, 0))
    # **Dim, and the reason is arithmetic rather than taste.** This wash is
    # additive over the whole neighbourhood of every fissure, so its alpha is
    # multiplied by the number of fissures near a given pixel -- at 1.35 the
    # seven of them lit most of the floor between them and the stage came back
    # from the darkening pass no darker at all. The rock was never the problem;
    # the light on it was.
    wide_glow.putalpha(crack.filter(ImageFilter.GaussianBlur(68))
                            .point(lambda v: int(min(255, v * 0.58))))
    core = Image.new("RGBA", (W, H3), A.rgba(p.lava_hot, 0))
    core.putalpha(crack.filter(ImageFilter.GaussianBlur(2.4))
                       .point(lambda v: int(v * 0.58)))

    img = A.add(img, wide_glow.crop((0, H, W, H * 2)))
    img = A.add(img, core.crop((0, H, W, H * 2)))

    # A dim glow along the plate joints as well, so the pavement is lit from
    # underneath everywhere rather than only where a fissure happens to run.
    seep = Image.new("RGBA", (W, H), A.rgba(p.lava, 0))
    seep.putalpha(Image.fromarray(
        np.clip(edge * 255, 0, 255).astype(np.uint8), "L")
        .filter(ImageFilter.GaussianBlur(9)).point(lambda v: int(v * 0.085)))
    img = A.add(img, seep)

    # Hazed toward the air, which is what puts it at the back.
    return _haze(img, p.air, 0.38)


# ---------------------------------------------------------------------------
# The middle distance
# ---------------------------------------------------------------------------

def make_rock(p, seed=2):
    """Plateaus and boulders standing off the floor.

    The silhouettes are the same lobed blobs they always were -- what changed
    is everything inside them. A shaded blob with a rim light is a *shape*; the
    same blob with plate joints running across it, a tone per plate and grain
    over the top is a rock, and the difference is four fields and no extra
    geometry.
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

    # **Barely blurred, and that is a change.** At a blur of 3 every boulder
    # had a soft edge, and a soft edge at this distance reads as fog rather
    # than as stone. One pixel is enough to take the polygon's stairs off.
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    body = shade_wrapped(mask, p.rock_lit, A.shade(p.rock_lit, 0.28),
                         0.30, 0.44)

    # The inside of the rock: joints, tone, grain. Multiplied into the shaded
    # body rather than composited over it, so it darkens the stone instead of
    # laying a grey film across the alpha the shading worked out.
    edge, tone = plate_field(W, H, 90, seed + 5)
    fine = fbm(W, H, seed + 31, octaves=4, base=16)
    k = (1.0 - edge * 0.66) * (0.78 + 0.44 * tone) * (0.88 + 0.24 * fine)
    k = k * (1.0 + grain(W, H, seed + 77))

    arr = np.asarray(body, dtype=np.float32)
    arr[..., :3] *= k[..., None]
    body = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # **The rim is what stops a dark mass reading as a hole in the picture.**
    # Subtract the mask from a copy of itself shifted down and what is left is
    # the top edge of every lump in it, which is where the light from the
    # cracks below would actually land.
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
    """Spires up the two edges, and nothing in the middle.

    Drawn over the field, so the keep-out is not a style choice -- a spire in
    the centre of the screen is a place a bullet can be invisible.
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
            # **A column, not a triangle.** Columnar basalt fractures into
            # near-parallel shafts with a broken top, so the silhouette wanted
            # here is a tall box with a chipped crown -- the four-point wedge
            # this used to be read as a paper cut-out of a mountain. The extra
            # vertices cost nothing and they are the whole difference between
            # "spire" and "triangle".
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

    # **The keep-out is enforced by a window, not by arithmetic on the
    # spires.** Getting it right per spire means every one of base_x, width,
    # lean and the shading halo staying inside the budget, and the first
    # version of this missed by fifty pixels -- which the check caught, and
    # which would have been a bullet hiding behind a rock had it not. A window
    # that reaches zero at the boundary cannot be got wrong, and it fades the
    # spires into the haze on the way in, which is what they should be doing
    # anyway.
    xs = np.arange(W, dtype=np.float32)
    window = np.clip(np.minimum(xs, W - 1 - xs) / edge_px, 0, 1)
    window = (1.0 - window) ** 1.5
    mask = Image.fromarray(
        (np.asarray(mask, dtype=np.float32) * window[None, :])
        .astype(np.uint8), "L")

    body = shade_wrapped(mask, p.near_lit, A.shade(p.near, 0.10), 0.20, 0.46)

    # The same treatment the middle distance gets, at a coarser scale: this is
    # the closest layer to the camera, so its plates are the biggest.
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

        # The keep-out is asserted here as well as in `check_project.py`,
        # because the generator is the only place that can explain *why*.
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

        # ...and the three of them stacked, which is the only view that says
        # whether the depth ramp is doing its job.
        stack = Image.new("RGBA", (W, H), A.rgba(p.air, 255))
        stack.alpha_composite(ground)
        stack.alpha_composite(rock)
        stack.alpha_composite(near)
        stack.resize((W // 2, H // 2), Image.LANCZOS).save(
            os.path.join(A.PREVIEW, "bg_%s.png" % p.name))

        # And a crop at 1:1, because a background judged at half size is a
        # background whose texture has been resampled away before anyone looked
        # at it -- which is how the flat first version passed inspection.
        stack.crop((W // 2 - 440, H // 2 - 250, W // 2 + 440, H // 2 + 250)) \
             .save(os.path.join(A.PREVIEW, "bg_%s_detail.png" % p.name))
        print("%s: 3 layers of %dx%d" % (p.name, W, H))

    A.preview(shown, os.path.join(A.PREVIEW, "bg_layers.png"), cols=3,
              bg=(18, 12, 14), labels=labels)


if __name__ == "__main__":
    main()
