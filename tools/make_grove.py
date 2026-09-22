#!/usr/bin/env python3
"""The Hollow Grove's scenery: a forest flown through rather than over.

This stage isn't a parallax stack. Its world is billboards the camera
passes, drawn at a size and position worked out from a depth at run time
(`scripts/bg_corridor` does the projection, `scripts/bg_grove` the
arrangement). So nothing here is `spr_bg_*`, the prefix `check_bg_seams`
and `check_bg_keepout` measure; the prefix is `spr_scn_`.

Everything is luminance, tinted at draw time, because the moon turns to
blood halfway through the stage and everything changes colour with it.
Each solid thing ships as two sprites:

`spr_scn_thing`      the body, white, with its own internal value structure;
                     tinted dark at draw time.
`spr_scn_thing_rim`  the moonward edge, white, drawn additively in the
                     moon's current colour.

Usage:
    python tools/make_grove.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

# ---------------------------------------------------------------------------
# Sizes
#
# A billboard is authored at about the size it is largest on screen; the
# corridor scales a tree up to about 1.6 times this at its closest.
# ---------------------------------------------------------------------------

TREE_W, TREE_H = 480, 780
TREE_N = 6

# The rims ship at half the body's resolution (a blurred edge has no detail
# to lose). The draw side derives the factor from the two sprites' widths.
RIM_DIV = 2

# The trunk of a tree the camera passes, drawn as a fragment that leaves the
# top of its frame, so the tree is always bigger than the screen.
TRUNK_W, TRUNK_H = 460, 1020

# Eight trunks with different silhouettes (see `TRUNK_KINDS`); the
# randomness fills each one in.
TRUNK_N = 8

# Ivy, the one green thing in the wood.
LEAF_W, LEAF_H = 230, 180
LEAF_N = 5

CHARM_W, CHARM_H = 136, 260
CHARM_N = 7

BUSH_W, BUSH_H = 380, 210
BUSH_N = 4

# The understorey along the verge: six different plants (a bramble mound, a
# bracken clump, a fallen log, a stand of saplings, a grass tussock and a mass
# of dock), each built on a solid base so it reads at a distance.
BRUSH_W, BRUSH_H = 460, 300
BRUSH_N = 6

# The hedgerow along the foot of the far wood: one band, tiled, drawn over
# the floor (see `grove_draw_scrub`). Authored at twice the field's width
# because it is drawn small, which keeps the repeat wide.
SCRUB_W, SCRUB_H = A.FIELD_W * 2, 160

# The forest floor: one square tile, periodic in both axes, laid down the
# corridor in bands (see `grove_draw_floor`).
FLOOR = 512

MOON = 512
TREELINE_W, TREELINE_H = A.FIELD_W, 340
CANOPY_W, CANOPY_H = A.FIELD_W, 470
MIST_W, MIST_H = A.FIELD_W, 260
ANTLER_W, ANTLER_H = 440, 620

SS = 2          # the supersample for the big silhouettes; see the note below


# ---------------------------------------------------------------------------
# Strokes
# ---------------------------------------------------------------------------

def tapered(d, pts, widths, fill=255):
    """A polyline drawn as a ribbon that narrows along its length, built as one
    polygon from the two offset edges (PIL has no per-point stroke width).
    """
    n = len(pts)
    if n < 2:
        return
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        if i == 0:
            ax, ay = pts[1][0] - x, pts[1][1] - y
        elif i == n - 1:
            ax, ay = x - pts[i - 1][0], y - pts[i - 1][1]
        else:
            ax, ay = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        m = math.hypot(ax, ay) or 1.0
        nx, ny = -ay / m, ax / m
        w = max(0.4, widths[i]) * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    d.polygon(left + right[::-1], fill=fill)


def sweep(d, x, y, ang, turn, length, w0, w1, steps=6):
    """A stroke that curves at a constant rate. Returns its points. Unlike
    `limb` it doesn't wobble, for smooth things like an antler's beam and
    tines.
    """
    pts, ws = [], []
    a = ang
    for i in range(steps + 1):
        pts.append((x, y))
        ws.append(w0 + (w1 - w0) * i / steps)
        a += turn
        x += math.cos(math.radians(a)) * length / steps
        y += math.sin(math.radians(a)) * length / steps
    tapered(d, pts, ws)
    return pts


def limb(d, rng, x, y, ang, length, width, depth, hangs, taper=0.42,
         segs=4, wobble=13.0):
    """One branch and everything that grows off it. Recursive.

    `hangs` collects the tips a charm could be tied to; they are written into
    `scripts/grove_table`, so the hang points always match the drawn branches.
    """
    pts = [(x, y)]
    widths = [width]
    a = ang
    curve = rng.normal(0, 6.0)
    for s in range(segs):
        a += rng.normal(0, wobble) + curve
        step = length / segs
        x += math.cos(math.radians(a)) * step
        y += math.sin(math.radians(a)) * step
        pts.append((x, y))
        widths.append(width * (1.0 - (s + 1) / segs * taper))
    tapered(d, pts, widths)

    if depth <= 0:
        # A tip. Only the ones reaching sideways and downward can hold a
        # charm; one tied to a branch pointing up hangs back across it.
        if abs(math.cos(math.radians(a))) > 0.35 and width < 13:
            hangs.append((x, y))
        return

    kids = 2 if rng.random() < 0.78 else 3
    for k in range(kids):
        spread = rng.uniform(20, 48) * (1 if k % 2 else -1)
        i = len(pts) - 1 - (k % 2)
        bx, by = pts[i]
        limb(d, rng, bx, by, a + spread + rng.normal(0, 7),
             length * rng.uniform(0.52, 0.74),
             widths[i] * rng.uniform(0.52, 0.70),
             depth - 1, hangs, taper, segs, wobble)


def soft_border(mask, sides="lrt", frac=0.055):
    """Fade a mask to nothing at the sprite's own edge, on the `sides` given
    (left, right, top). A billboard's edge is a hard clip, so a branch reaching
    the border would otherwise be sliced along a straight line. The bottom is
    never windowed: that is where a tree meets the ground.
    """
    a = np.asarray(mask, dtype=np.float32)
    h, w = a.shape
    if "l" in sides or "r" in sides:
        xs = np.arange(w, dtype=np.float32)
        dx = np.minimum(xs if "l" in sides else np.full(w, w, np.float32),
                        (w - 1 - xs) if "r" in sides
                        else np.full(w, w, np.float32))
        a *= np.clip(dx / max(1.0, w * frac), 0, 1)[None, :] ** 0.8
    if "t" in sides:
        ys = np.arange(h, dtype=np.float32)
        a *= np.clip(ys / max(1.0, h * frac), 0, 1)[:, None] ** 0.8
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "L")


def tree_mask(seed):
    """One crooked tree, as a mask at SS, plus its hang points in final px.
    Bare and gnarled rather than leafy, so the charms hanging from it show.
    """
    rng = np.random.default_rng(seed)
    w, h = TREE_W * SS, TREE_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    hangs = []

    base_x = TREE_W * 0.5 * SS
    base_y = h - 2 * SS

    # The trunk. It leans one way below a random node and the other way above
    # it, so it goes out and comes back. Wide at the base, thinning hard
    # toward the crown.
    trunk_h = h * rng.uniform(0.44, 0.58)
    lean = rng.uniform(0.26, 0.52) * (1 if rng.random() < 0.5 else -1)
    n = 9
    elbow = int(rng.integers(2, n - 2))
    pts, widths = [], []
    x, y = base_x, base_y
    wid = SS * rng.uniform(58, 86)
    step = trunk_h / (n - 1)
    for i in range(n):
        t = i / (n - 1)
        # A burl or two, so the taper doesn't read as a cone.
        burl = 1.0 + 0.16 * math.cos(t * 7.0 + seed % 7)
        pts.append((x, y))
        widths.append(wid * (1.0 - 0.70 * t ** 0.80) * burl)
        y -= step
        x += lean * step * (1 if i < elbow else -1) + rng.normal(0, 11 * SS)
    tapered(d, pts, widths)

    # Root flare: wedges going down and out into the ground.
    for k in range(int(rng.integers(5, 8))):
        side = 1 if (k % 2 == 0) else -1
        rl = rng.uniform(0.10, 0.22) * w * side
        rw = wid * rng.uniform(0.34, 0.60)
        rx = base_x + rng.normal(0, 8 * SS)
        tapered(d,
                [(rx, base_y - wid * 0.55),
                 (rx + rl * 0.55, base_y - wid * 0.16),
                 (rx + rl, base_y + 6 * SS)],
                [rw, rw * 0.62, rw * 0.20])

    # The crown: boughs off the upper half of the trunk and a pair off the
    # top. They leave nearer sixty degrees off vertical than thirty, and low
    # ones may droop past horizontal, so the tree holds its arms out.
    top_x, top_y = pts[-1]
    for k in range(int(rng.integers(5, 8))):
        i = int(rng.integers(2, n))
        bx, by = pts[i]
        side = 1 if (k % 2 == 0) else -1
        low = 1.0 - i / (n - 1)          # 1 at the bottom of the trunk
        a = -90 + side * (rng.uniform(48, 86) + low * 26)
        limb(d, rng, bx, by, a,
             rng.uniform(0.22, 0.38) * h,
             widths[i] * rng.uniform(0.46, 0.68), 2, hangs)
    for side in (-1, 1):
        limb(d, rng, top_x, top_y, -90 + side * rng.uniform(10, 34),
             rng.uniform(0.16, 0.26) * h, widths[-1] * 0.86, 2, hangs)

    # Hanging vines: thin, drooping, and started a little back from a branch's
    # tip rather than at it.
    for _ in range(int(rng.integers(3, 6))):
        if not hangs:
            break
        hx, hy = hangs[int(rng.integers(0, len(hangs)))]
        hx += (base_x - hx) * 0.12
        hy += 2 * SS
        vp, vw = [(hx, hy)], [4.0 * SS]
        vx, vy = hx, hy
        for s in range(6):
            vx += rng.normal(0, 6 * SS)
            vy += rng.uniform(14, 34) * SS
            vp.append((vx, vy))
            vw.append(3.4 * SS * (1 - s / 7))
        tapered(d, vp, vw)

    mask = soft_border(mask)

    hangs = [(hx / SS / TREE_W, hy / SS / TREE_H) for hx, hy in hangs]
    # Only the outermost few, and only ones with room under them. A charm
    # tied at the very top of the frame has nowhere to hang to.
    hangs = [p for p in hangs if 0.06 < p[0] < 0.94 and 0.05 < p[1] < 0.62]
    hangs.sort(key=lambda p: -abs(p[0] - 0.5))
    return mask, hangs[:3]


# ---------------------------------------------------------------------------
# Turning a mask into a body and a rim
# ---------------------------------------------------------------------------

def bark(w, h, seed):
    """The value field a trunk is textured with, 0..1: noise at two scales,
    generated short and stretched vertically so its features run up the trunk.
    """
    def band(rows, base, s):
        return np.asarray(
            A.fbm_field(w, max(3, rows), s, octaves=3, base=base)
             .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0

    coarse = band(max(3, h // 12), 9, seed)
    fine = band(max(3, h // 5), 30, seed + 91)
    return np.clip(0.50 + 0.36 * coarse + 0.22 * fine, 0.32, 1.0)


def body_from_mask(mask, seed, floor=0.35, gradient=0.0):
    """A white body carrying its own value structure, at final size. White
    because it is tinted at draw time; the structure is in the value.
    """
    small = mask.resize((mask.width // SS, mask.height // SS), Image.LANCZOS)
    a = np.asarray(small, dtype=np.float32) / 255.0
    w, h = small.size
    k = bark(w, h, seed)
    if gradient:
        # Darker toward the base, which is where the light from the moon
        # reaches least and where the fog is thickest.
        ramp = np.linspace(1.0, 1.0 - gradient, h, dtype=np.float32)[:, None]
        k = k * ramp
    k = np.clip(k, floor, 1.0)
    body = np.repeat((k * 255)[..., None], 3, axis=2)
    return A.from_arrays(body, a), small


def edge_light(mask, dx, dy, blur, strength):
    """Light one side of a silhouette: the side facing the middle of the
    screen, where the moon is. A shift in x (`A.rim_light` shifts in y),
    mirrored per side by the draw call rather than by a second sprite.
    """
    moved = ImageChops.offset(mask, int(dx), int(dy))
    edge = ImageChops.subtract(mask, moved)
    edge = edge.filter(ImageFilter.GaussianBlur(blur))
    return edge.point(lambda v: int(min(255, v * strength)))


def rim_sprite(mask, w, h, dx=-9, dy=5, blur=3.4, strength=1.5):
    """The moonward edge of a mask, as a white RGBA at `w` by `h`."""
    edge = edge_light(mask, dx * SS, dy * SS, blur * SS, strength)
    edge = edge.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(edge)
    return out


# ---------------------------------------------------------------------------
# The trees
# ---------------------------------------------------------------------------

def make_trees():
    bodies, rims, hangs = [], [], []
    for i in range(TREE_N):
        mask, hang = tree_mask(1000 + i * 37)
        body, _ = body_from_mask(mask, 400 + i, gradient=0.22)
        bodies.append(body)
        rims.append(rim_sprite(mask, TREE_W // RIM_DIV, TREE_H // RIM_DIV))
        hangs.append(hang)
    return bodies, rims, hangs


def bough_from(img):
    """A tree turned into a bough: its root and the foot of its trunk faded
    out.

    A bough is the tree sprite hung upside down, and the trunk's foot would
    otherwise end in a straight cut in the sky. The fade covers the root flare
    and lower trunk and stops below the lowest bough (`tree_mask` starts those
    two ninths of the way up).
    """
    a = np.asarray(img, dtype=np.float32).copy()
    h = a.shape[0]
    up = 1.0 - np.linspace(0.0, 1.0, h, dtype=np.float32)     # 0 at the root
    t = np.clip((up - 0.10) / 0.24, 0.0, 1.0)
    a[..., 3] *= (t * t * (3.0 - 2.0 * t))[:, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


# Eight silhouettes. `lean` is how far it goes over, `bend` whether it comes
# back, `wid` its base width as a share of the frame, `boughs` how many leave
# it, `fork` whether it splits into two near the top, and `burl` how lumpy the
# taper is.
TRUNK_KINDS = (
    # lean  bend   wid   boughs  fork  burl
    (0.02, False, 0.46, 3, False, 0.06),   # heavy and near-straight
    (0.20, False, 0.34, 4, False, 0.12),   # leaning
    (0.26, True,  0.38, 4, False, 0.10),   # leans and recovers: an S
    (0.05, False, 0.42, 2, True,  0.08),   # forked into two at the top
    (0.12, True,  0.26, 6, False, 0.16),   # slender, many boughs
    (0.04, False, 0.56, 2, False, 0.26),   # squat, wide, badly burled
    (0.30, False, 0.30, 5, True,  0.20),   # leaning hard and forked
    (0.14, True,  0.48, 3, False, 0.05),   # broad, gently sinuous
)


def trunk_mask(seed, kind):
    """A trunk that fills the frame and leaves the top of it, read by its
    edges: how it swells, where a bough leaves it, whether it forks.
    """
    lean, bend, widf, boughs, fork, burlk = kind
    rng = np.random.default_rng(seed)
    w, h = TRUNK_W * SS, TRUNK_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)

    base_x = w * 0.5 - lean * h * (0.22 if not bend else 0.0)
    base_y = h + 4 * SS
    wid = w * widf * rng.uniform(0.92, 1.08)

    n = 11
    elbow = int(rng.integers(3, n - 3)) if bend else n
    side = 1 if rng.random() < 0.5 else -1
    pts, widths = [], []
    x, y = base_x, base_y
    for i in range(n):
        t = i / (n - 1)
        # Swelling rather than tapering: two cosines out of phase give it a
        # waist and a shoulder.
        k = (1.0 - 0.26 * t) * (1.0 + burlk * math.cos(t * 5.5 + seed % 5)
                                + burlk * 0.5 * math.cos(t * 11.0 + seed % 3))
        pts.append((x, y))
        widths.append(wid * k)
        y -= h / (n - 1)
        x += side * lean * (h / (n - 1)) * (1 if i < elbow else -1) \
             + rng.normal(0, 10 * SS)
    tapered(d, pts, widths)

    # A fork: the trunk splits and both halves leave the top of the frame.
    if fork:
        i = int(n * rng.uniform(0.45, 0.62))
        fx, fy = pts[i]
        for s2 in (-1, 1):
            fp, fw = [(fx, fy)], [widths[i] * 0.66]
            px, py, pa = fx, fy, -90 + s2 * rng.uniform(14, 30)
            for _k in range(5):
                pa += rng.normal(0, 7) - s2 * 2
                px += math.cos(math.radians(pa)) * h * 0.13
                py += math.sin(math.radians(pa)) * h * 0.13
                fp.append((px, py))
                fw.append(widths[i] * 0.66 * (1 - len(fw) / 9))
            tapered(d, fp, fw)

    # Root flare, wide and shallow.
    for k in range(int(rng.integers(6, 9))):
        rside = 1 if (k % 2 == 0) else -1
        rl = rng.uniform(0.16, 0.36) * w * rside
        rw = wid * rng.uniform(0.28, 0.50)
        rx = base_x + rng.normal(0, 16 * SS)
        tapered(d,
                [(rx, base_y - wid * 0.9),
                 (rx + rl * 0.5, base_y - wid * 0.34),
                 (rx + rl, base_y + 8 * SS)],
                [rw, rw * 0.66, rw * 0.24])

    # Boughs, every one leaving the frame, so no branch tip the size of a
    # bullet ends in the foreground.
    for k in range(boughs):
        t = rng.uniform(0.22, 0.94)
        i = int(t * (n - 1))
        bx, by = pts[i]
        bside = 1 if (k % 2 == 0) else -1
        ang = -90 + bside * rng.uniform(52, 96)
        limb(d, rng, bx, by, ang, w * rng.uniform(0.9, 1.6),
             widths[i] * rng.uniform(0.30, 0.52), 1, [], taper=0.4,
             segs=4, wobble=9.0)

    # Only the sides are windowed: the trunk is *meant* to be cut off at the
    # top, and it is meant to reach the ground at the bottom.
    return soft_border(mask, sides="lr", frac=0.03)


def make_trunks():
    bodies, rims = [], []
    for i in range(TRUNK_N):
        mask = trunk_mask(5500 + i * 29, TRUNK_KINDS[i % len(TRUNK_KINDS)])
        body, _ = body_from_mask(mask, 5600 + i, floor=0.30, gradient=0.30)
        bodies.append(body)
        rims.append(rim_sprite(mask, TRUNK_W // RIM_DIV, TRUNK_H // RIM_DIV,
                               dx=-11, dy=6, blur=4.0, strength=1.4))
    return bodies, rims


def leaf_cluster(d, rng, w, h):
    """A clump of ivy on a stem: pointed-oval leaves off a curving runner,
    drawn as a mass.
    """
    sx, sy = w * 0.06, h * 0.5
    run = [(sx, sy)]
    x, y, a = sx, sy, rng.uniform(-24, 24)
    for _ in range(5):
        a += rng.normal(0, 20)
        x += math.cos(math.radians(a)) * w * 0.19
        y += math.sin(math.radians(a)) * w * 0.19
        run.append((x, y))
    tapered(d, run, [5 * SS] * len(run))

    for i in range(int(rng.integers(9, 15))):
        t = rng.uniform(0.08, 1.0)
        j = min(len(run) - 2, int(t * (len(run) - 1)))
        bx, by = run[j]
        ang = rng.uniform(0, 360)
        ll = h * rng.uniform(0.16, 0.30)
        lw = ll * rng.uniform(0.52, 0.78)
        cx = bx + math.cos(math.radians(ang)) * ll * 0.55
        cy = by + math.sin(math.radians(ang)) * ll * 0.55
        # A pointed oval: an ellipse plus a triangle for the tip.
        d.ellipse([cx - lw * 0.5, cy - ll * 0.4, cx + lw * 0.5, cy + ll * 0.4],
                  fill=255)
        tipx = cx + math.cos(math.radians(ang)) * ll * 0.55
        tipy = cy + math.sin(math.radians(ang)) * ll * 0.55
        perp = ang + 90
        d.polygon([(cx + math.cos(math.radians(perp)) * lw * 0.36,
                    cy + math.sin(math.radians(perp)) * lw * 0.36),
                   (cx - math.cos(math.radians(perp)) * lw * 0.36,
                    cy - math.sin(math.radians(perp)) * lw * 0.36),
                   (tipx, tipy)], fill=255)


def make_leaves():
    out = []
    for i in range(LEAF_N):
        rng = np.random.default_rng(6600 + i * 17)
        w, h = LEAF_W * SS, LEAF_H * SS
        mask = Image.new("L", (w, h), 0)
        leaf_cluster(ImageDraw.Draw(mask), rng, w, h)
        mask = soft_border(mask, sides="lrt", frac=0.04)
        body, _ = body_from_mask(mask, 6700 + i, floor=0.48)
        out.append(body)
    return out


# ---------------------------------------------------------------------------
# What is hanging in them
#
# The charms are the only thing in the stage with a second hue. Each ships as
# a body and a `lit` layer; the lit layer is drawn additively, so the carving
# glows and the wood doesn't.
# ---------------------------------------------------------------------------

def charm_cord(d, x0, y0, x1, y1, w=3.0):
    d.line([(x0, y0), (x1, y1)], fill=255, width=max(1, int(w * SS)))


def charm_plaque(d, lit, cx, top, rng):
    """A rune cut into a hanging shield of bark."""
    charm_cord(d, cx, 0, cx, top)
    r = 58 * SS
    pts = [(cx - r * 0.74, top), (cx + r * 0.74, top),
           (cx + r * 0.88, top + r * 0.9), (cx, top + r * 1.9),
           (cx - r * 0.88, top + r * 0.9)]
    d.polygon(pts, fill=255)
    # The rune: three thin strokes, spread over a large plaque so the glyph
    # doesn't fill in.
    ld = ImageDraw.Draw(lit)
    ld.line([(cx, top + r * 0.30), (cx, top + r * 1.56)], fill=255,
            width=int(3.5 * SS))
    ld.line([(cx - r * 0.46, top + r * 0.50), (cx, top + r * 0.86)],
            fill=255, width=int(3.5 * SS))
    ld.line([(cx + r * 0.46, top + r * 0.86), (cx, top + r * 1.22)],
            fill=255, width=int(3.5 * SS))


def charm_bones(d, lit, cx, top, rng):
    """A bundle of long bones tied crosswise."""
    charm_cord(d, cx, 0, cx, top)
    # Three long bones, knuckled at both ends and shorter than the frame is
    # wide.
    for k, ang in enumerate((-52, 4, 54)):
        L = 86 * SS * (1.0 - 0.12 * (k % 2))
        ax = math.cos(math.radians(ang + 90)) * L
        ay = math.sin(math.radians(ang + 90)) * L
        x0, y0 = cx - ax * 0.32, top + 26 * SS - ay * 0.32
        x1, y1 = cx + ax * 0.68, top + 26 * SS + ay * 0.68
        d.line([(x0, y0), (x1, y1)], fill=255, width=int(6 * SS))
        for (ex, ey), rr in (((x0, y0), 6.5 * SS), ((x1, y1), 5.0 * SS)):
            d.ellipse([ex - rr * 1.5, ey - rr, ex + rr * 1.5, ey + rr],
                      fill=255)
            d.ellipse([ex - rr, ey - rr * 1.4, ex + rr, ey + rr * 1.4],
                      fill=255)
    # The binding.
    d.ellipse([cx - 15 * SS, top + 16 * SS, cx + 15 * SS, top + 38 * SS],
              fill=255)


def charm_ring(d, lit, cx, top, rng):
    """A hoop with chords strung across it and a bead at the crossing."""
    charm_cord(d, cx, 0, cx, top)
    r = 50 * SS
    cy = top + r
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255,
              width=int(7 * SS))
    for a in (18, 78, 140):
        ax = math.cos(math.radians(a)) * r
        ay = math.sin(math.radians(a)) * r
        d.line([(cx - ax, cy - ay), (cx + ax, cy + ay)], fill=255,
               width=int(3 * SS))
    ld = ImageDraw.Draw(lit)
    br = 11 * SS
    ld.ellipse([cx - br, cy - br, cx + br, cy + br], fill=255)
    # Three teeth on cords under it.
    for k, ox in enumerate((-26, 2, 28)):
        x = cx + ox * SS
        y0 = cy + r * 0.86
        y1 = y0 + (30 + 12 * (k % 2)) * SS
        d.line([(x, y0), (x, y1)], fill=255, width=int(2.4 * SS))
        d.polygon([(x - 3.5 * SS, y1), (x + 3.5 * SS, y1),
                   (x, y1 + 26 * SS)], fill=255)


def charm_skull(d, lit, cx, top, rng):
    """A small beast's skull, hung by the horn. The eyes are what light."""
    charm_cord(d, cx, 0, cx, top)
    w = 40 * SS
    h = 44 * SS
    cy = top + h * 0.7
    d.ellipse([cx - w, cy - h * 0.72, cx + w, cy + h * 0.55], fill=255)
    # Muzzle, narrow (a wide one reads as a jaw).
    d.polygon([(cx - w * 0.34, cy + h * 0.26), (cx + w * 0.34, cy + h * 0.26),
               (cx + w * 0.21, cy + h * 1.52), (cx - w * 0.21, cy + h * 1.52)],
              fill=255)
    # Horns, long enough to leave the head's outline (short ones read as ears).
    for sgn in (-1, 1):
        limb(d, rng, cx + sgn * w * 0.72, cy - h * 0.40,
             -90 + sgn * 46, 92 * SS, 11 * SS, 1, [], taper=0.55, segs=4,
             wobble=7.0)
    # Small sockets, so the eyes don't read as a face looking out.
    ld = ImageDraw.Draw(lit)
    for sgn in (-1, 1):
        ex = cx + sgn * w * 0.42
        ey = cy + h * 0.02
        ld.ellipse([ex - 6 * SS, ey - 5 * SS, ex + 6 * SS, ey + 5 * SS],
                   fill=255)


def charm_fetish(d, lit, cx, top, rng):
    """Feathers and leaves bound to a stick. No light in it at all."""
    charm_cord(d, cx, 0, cx, top)
    d.line([(cx - 44 * SS, top + 6 * SS), (cx + 44 * SS, top - 2 * SS)],
           fill=255, width=int(6 * SS))
    for k in range(5):
        x = cx + (k - 2) * 20 * SS
        y = top + 4 * SS
        L = (54 + 20 * ((k * 5) % 3)) * SS
        d.line([(x, y), (x + rng.normal(0, 5 * SS), y + L)], fill=255,
               width=int(2.6 * SS))
        d.polygon([(x - 9 * SS, y + L * 0.55), (x + 9 * SS, y + L * 0.62),
                   (x + 1 * SS, y + L)], fill=255)


def charm_spine(d, lit, cx, top, rng):
    """A string of vertebrae. The joints glow."""
    charm_cord(d, cx, 0, cx, top)
    ld = ImageDraw.Draw(lit)
    y = top
    for k in range(6):
        r = (16 - k) * SS
        d.ellipse([cx - r, y - r * 0.7, cx + r, y + r * 0.7], fill=255)
        d.line([(cx - r * 1.5, y), (cx + r * 1.5, y)], fill=255,
               width=int(3 * SS))
        if k % 2 == 0:
            ld.ellipse([cx - 4 * SS, y - 4 * SS, cx + 4 * SS, y + 4 * SS],
                       fill=255)
        y += 30 * SS


def charm_lantern(d, lit, cx, top, rng):
    """A witch-light in a cage of ribs. The one charm that is a lamp."""
    charm_cord(d, cx, 0, cx, top)
    w, h = 34 * SS, 54 * SS
    cy = top + h
    for s in (-1, 1):
        d.line([(cx + s * w * 0.2, top + 4 * SS), (cx + s * w, cy),
                (cx + s * w * 0.3, cy + h * 0.8)], fill=255,
               width=int(5 * SS), joint="curve")
    d.line([(cx - w, cy), (cx + w, cy)], fill=255, width=int(4 * SS))
    d.ellipse([cx - w * 0.8, cy + h * 0.66, cx + w * 0.8, cy + h * 1.0],
              fill=255)
    # A small light, so the cage still reads as a cage; the bloom at draw time
    # does the reaching.
    ld = ImageDraw.Draw(lit)
    ld.ellipse([cx - w * 0.30, cy - h * 0.20, cx + w * 0.30, cy + h * 0.20],
               fill=255)


CHARMS = (charm_plaque, charm_bones, charm_ring, charm_skull, charm_fetish,
          charm_spine, charm_lantern)


def make_charms():
    bodies, lits = [], []
    for i, fn in enumerate(CHARMS):
        rng = np.random.default_rng(7000 + i)
        w, h = CHARM_W * SS, CHARM_H * SS
        mask = Image.new("L", (w, h), 0)
        lit = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(mask)
        fn(d, lit, w * 0.5, h * 0.20, rng)

        body, small = body_from_mask(mask, 7100 + i, floor=0.55)
        # The body carries the lit parts too, so the carving isn't a hole when
        # the accent is faint; the additive pass is what makes them burn.
        bodies.append(body)

        glow = lit.resize((CHARM_W, CHARM_H), Image.LANCZOS)
        soft = glow.filter(ImageFilter.GaussianBlur(5.0)) \
                   .point(lambda v: int(v * 0.85))
        out = Image.new("RGBA", (CHARM_W, CHARM_H), (255, 255, 255, 0))
        out.putalpha(ImageChops.lighter(glow, soft))
        lits.append(out)
    return bodies, lits


# ---------------------------------------------------------------------------
# Undergrowth
# ---------------------------------------------------------------------------

def make_bushes():
    """Low fern masses that pass close to the camera along the path, which is
    where most of the sense of speed comes from.
    """
    bodies, rims = [], []
    for i in range(BUSH_N):
        rng = np.random.default_rng(2400 + i * 13)
        w, h = BUSH_W * SS, BUSH_H * SS
        mask = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(mask)
        base_y = h - 2 * SS
        # A clump first, then the fronds off it.
        for _ in range(int(rng.integers(6, 10))):
            cx = rng.uniform(0.10, 0.90) * w
            cw = rng.uniform(0.10, 0.20) * w
            ch = rng.uniform(0.05, 0.13) * h
            d.ellipse([cx - cw, base_y - ch * 2, cx + cw, base_y + ch],
                      fill=255)
        for _ in range(int(rng.integers(20, 28))):
            x = rng.uniform(0.06, 0.94) * w
            a = -90 + rng.normal(0, 38)
            L = rng.uniform(0.40, 0.96) * h
            frond = [(x, base_y)]
            fw = [rng.uniform(5, 9) * SS]
            fx, fy, fa = x, base_y, a
            for s in range(4):
                fa += rng.normal(0, 9) + (12 if a > -90 else -12)
                fx += math.cos(math.radians(fa)) * L / 4
                fy += math.sin(math.radians(fa)) * L / 4
                frond.append((fx, fy))
                fw.append(fw[0] * (1 - (s + 1) / 4 * 0.85))
            tapered(d, frond, fw)
            # Leaflets, which is what makes a stroke read as a fern.
            for k in range(1, 4):
                lx, ly = frond[k]
                for s in (-1, 1):
                    ll = 16 * SS * (1 - k / 5)
                    d.line([(lx, ly),
                            (lx + s * ll, ly + ll * 0.5)],
                           fill=255, width=int(2.6 * SS))
        mask = soft_border(mask, sides="lr", frac=0.05)
        body, _ = body_from_mask(mask, 2500 + i, floor=0.40, gradient=0.30)
        bodies.append(body)
        rims.append(rim_sprite(mask, BUSH_W // RIM_DIV, BUSH_H // RIM_DIV,
                               dx=-7, dy=6, blur=2.6, strength=1.35))
    return bodies, rims


# ---------------------------------------------------------------------------
# The understorey
#
# Six plants, each a solid mass before anything else (see `BRUSH_N`).
# ---------------------------------------------------------------------------

def _clump_base(d, rng, w, h, n=10, lo=0.20, hi=0.80, low=0.14, high=0.34):
    """The body a plant stands on: overlapping ellipses along the foot of the
    frame, drawn below the bottom edge so the mass is solid down to it. The
    spread is kept well inside the frame, since `soft_border` only softens a
    cut and can't fix a body that doesn't fit.
    """
    base = h * 1.02
    for _ in range(n):
        cx = rng.uniform(lo, hi) * w
        cw = rng.uniform(0.07, 0.15) * w
        ch = rng.uniform(low, high) * h
        d.ellipse([cx - cw, base - ch, cx + cw, base + ch * 0.4], fill=255)


def _brush_bramble(d, rng, w, h):
    """A low thicket with canes arching well clear of it (the dome is lower
    than the canes are long, so the tangle shows).
    """
    _clump_base(d, rng, w, h, n=13, low=0.18, high=0.40)
    for _ in range(24):
        x = rng.uniform(0.16, 0.84) * w
        turn = rng.uniform(7, 17) * (1 if rng.random() < 0.5 else -1)
        pts = sweep(d, x, h * 0.94, -90 + rng.normal(0, 30), turn,
                    rng.uniform(0.50, 0.86) * h, 7 * SS, 2.2 * SS, steps=7)
        for (px, py) in pts[2::2]:
            r = rng.uniform(5, 11) * SS
            d.ellipse([px - r, py - r * 0.8, px + r, py + r * 0.8], fill=255)


def _brush_bracken(d, rng, w, h):
    """Broad fronds off a low base, drawn as paired triangles off a spine so
    each frond has area.
    """
    _clump_base(d, rng, w, h, n=9, low=0.14, high=0.28)
    for _ in range(12):
        x = rng.uniform(0.20, 0.80) * w
        turn = rng.uniform(3, 9) * (1 if x > w * 0.5 else -1)
        pts = sweep(d, x, h * 0.94, -90 + rng.normal(0, 30), turn,
                    rng.uniform(0.42, 0.72) * h, 6 * SS, 2 * SS, steps=6)
        for i, (px, py) in enumerate(pts):
            t = 1 - i / len(pts)
            ll = 30 * SS * t + 6 * SS
            for sgn in (-1, 1):
                d.polygon([(px, py), (px + sgn * ll, py + ll * 0.42),
                           (px + sgn * ll * 0.35, py + ll * 0.78)], fill=255)


def _brush_log(d, rng, w, h):
    """A fallen trunk with things growing on it: the one wide, low silhouette
    in the set.
    """
    # Thin and tapered, so it reads as a log rather than a mound.
    y = h * 0.74
    r = h * 0.155
    d.polygon([(w * 0.18, y - r), (w * 0.82, y - r * 0.74),
               (w * 0.82, y + r * 0.74), (w * 0.18, y + r)], fill=255)
    d.ellipse([w * 0.10, y - r, w * 0.26, y + r], fill=255)
    d.ellipse([w * 0.76, y - r * 0.74, w * 0.88, y + r * 0.74], fill=255)
    for _ in range(8):                      # shelf fungus along the top
        cx = rng.uniform(0.24, 0.78) * w
        fw = rng.uniform(0.04, 0.09) * w
        fh = rng.uniform(0.05, 0.11) * h
        d.ellipse([cx - fw, y - r - fh, cx + fw, y - r + fh * 0.6], fill=255)
    # Litter at the ends only, so the middle of the log keeps its own outline.
    _clump_base(d, rng, w, h, n=5, lo=0.14, hi=0.32, low=0.08, high=0.18)
    _clump_base(d, rng, w, h, n=5, lo=0.68, hi=0.86, low=0.08, high=0.18)
    for _ in range(22):                     # grass standing through it
        x = rng.uniform(0.14, 0.86) * w
        sweep(d, x, y + r * 0.7, -90 + rng.normal(0, 26), rng.uniform(-8, 8),
              rng.uniform(0.34, 0.66) * h, 4.5 * SS, 1.0 * SS, steps=4)


def _brush_saplings(d, rng, w, h):
    """A stand of thin stems with leaf clusters at the top."""
    _clump_base(d, rng, w, h, n=10, low=0.12, high=0.24)
    for _ in range(7):
        x = rng.uniform(0.20, 0.80) * w
        pts = sweep(d, x, h * 0.95, -90 + rng.normal(0, 11), rng.normal(0, 3),
                    rng.uniform(0.50, 0.80) * h, 6 * SS, 2 * SS, steps=5)
        tx, ty = pts[-1]
        for _ in range(int(rng.integers(5, 9))):
            a = rng.uniform(0, 360)
            rr = rng.uniform(0.04, 0.12) * h
            cx = tx + math.cos(math.radians(a)) * rr
            cy = ty + math.sin(math.radians(a)) * rr * 0.8
            lw = rng.uniform(0.032, 0.062) * w
            d.ellipse([cx - lw, cy - lw * 0.62, cx + lw, cy + lw * 0.62],
                      fill=255)


def _brush_tussock(d, rng, w, h):
    """A fan of blades off a solid crown. The spikiest of the six."""
    _clump_base(d, rng, w, h, n=8, lo=0.16, hi=0.84, low=0.18, high=0.32)
    for _ in range(48):
        x = rng.uniform(0.18, 0.82) * w
        sweep(d, x, h * 0.94, -90 + rng.normal(0, 38), rng.uniform(-9, 9),
              rng.uniform(0.26, 0.66) * h, 5.5 * SS, 0.9 * SS, steps=5)


def _brush_dock(d, rng, w, h):
    """Big flat leaves on short stems. The most solid of the six."""
    _clump_base(d, rng, w, h, n=9, low=0.12, high=0.24)
    for _ in range(14):
        x = rng.uniform(0.20, 0.80) * w
        ang = -90 + rng.normal(0, 40)
        pts = sweep(d, x, h * 0.94, ang, rng.uniform(-6, 6),
                    rng.uniform(0.22, 0.44) * h, 5 * SS, 3 * SS, steps=4)
        ex, ey = pts[-1]
        lw = rng.uniform(0.06, 0.12) * w
        lh = rng.uniform(0.14, 0.26) * h
        cx = ex + math.cos(math.radians(ang)) * lh * 0.45
        cy = ey + math.sin(math.radians(ang)) * lh * 0.45
        d.ellipse([cx - lw, cy - lh * 0.5, cx + lw, cy + lh * 0.5], fill=255)


BRUSHES = (_brush_bramble, _brush_bracken, _brush_log, _brush_saplings,
           _brush_tussock, _brush_dock)


def make_brush():
    bodies, rims = [], []
    for i, fn in enumerate(BRUSHES):
        rng = np.random.default_rng(8800 + i * 23)
        w, h = BRUSH_W * SS, BRUSH_H * SS
        mask = Image.new("L", (w, h), 0)
        fn(ImageDraw.Draw(mask), rng, w, h)
        # A wider window than the trees get, so a long bramble cane fades out
        # rather than being cut off.
        mask = soft_border(mask, sides="lrt", frac=0.07)
        body, _ = body_from_mask(mask, 8900 + i, floor=0.32, gradient=0.44)
        bodies.append(body)
        rims.append(rim_sprite(mask, BRUSH_W // RIM_DIV, BRUSH_H // RIM_DIV,
                               dx=-8, dy=6, blur=3.0, strength=1.45))
    return bodies, rims


# ---------------------------------------------------------------------------
# The hedgerow
# ---------------------------------------------------------------------------

def _bush_mass(d, rng, cx, base, bw, bh):
    """One bush in a hedgerow: overlapping leaf masses of several sizes, with a
    fringe of small circles along the top so the outline isn't smooth.
    """
    lobes = []
    for _ in range(int(rng.integers(5, 10))):
        lx = cx + rng.uniform(-0.42, 0.42) * bw
        # Taller toward the middle of the bush, so a mass has a crown.
        centre = 1 - abs(lx - cx) / max(1.0, bw * 0.5)
        lh = bh * (0.45 + 0.55 * centre) * rng.uniform(0.70, 1.0)
        lw = bw * rng.uniform(0.20, 0.36)
        ey0, ey1 = base - lh, base + lh * 0.2
        d.ellipse([lx - lw, ey0, lx + lw, ey1], fill=255)
        lobes.append((lx, (ey0 + ey1) * 0.5, lw, (ey1 - ey0) * 0.5))
    # The fringe sits *on* each lobe's upper arc and stands proud of it by its
    # own radius, which is what a leaf at the edge of a bush does.
    for (lx, ly, rx, ry) in lobes:
        for _ in range(int(rng.integers(6, 12))):
            a = math.radians(rng.uniform(195, 345))
            r = rng.uniform(0.04, 0.09) * bh + 2 * SS
            fx = lx + math.cos(a) * rx * rng.uniform(0.75, 1.0)
            fy = ly + math.sin(a) * ry * rng.uniform(0.85, 1.0)
            d.ellipse([fx - r, fy - r, fx + r, fy + r], fill=255)


def _scrub_draw(d, w, h):
    """A hedgerow along the foot of the far wood.

    A low mat of many overlapping ellipses, so the coverage has no gap: its
    crown must stay above the horizon everywhere, which
    `check_scrub_covers_horizon` measures on the shipped PNG. Over it, a few
    dozen bushes of different heights, whose crowns give the hedge its rhythm,
    and a few saplings with leafy heads.
    """
    for i in range(3):
        off = i * w
        rng = np.random.default_rng(5252)      # the same hedge, three times
        base = h * 1.04
        # The mat, which is the part that may not have a gap in it.
        for _ in range(110):
            cx = rng.uniform(0, w) + off
            cw = rng.uniform(0.020, 0.042) * w
            ch = rng.uniform(0.54, 0.70) * h
            d.ellipse([cx - cw, base - ch, cx + cw, base + ch * 0.3], fill=255)
        # The bushes, spaced along the band rather than scattered, so the
        # crowns have a rhythm and the mat isn't left bare in places.
        n = 34
        for k in range(n):
            cx = (k + rng.uniform(0.15, 0.85)) * w / n + off
            bw = rng.uniform(0.028, 0.062) * w
            # Capped at 0.86 so the tallest crown and its fringe clear the
            # top of the canvas; floored at 0.68 so every bush stands above
            # the mat.
            bh = (0.68 + 0.18 * rng.random() ** 1.3) * h
            _bush_mass(d, rng, cx, base, bw, bh)
        # A handful of saplings above the line, with heads.
        for _ in range(9):
            x = rng.uniform(0, w) + off
            pts = sweep(d, x, base - 0.3 * h, -90 + rng.normal(0, 8),
                        rng.normal(0, 3), rng.uniform(0.40, 0.60) * h,
                        7 * SS, 2.5 * SS, steps=5)
            tx, ty = pts[-1]
            for _ in range(int(rng.integers(7, 12))):
                a = rng.uniform(0, 360)
                rr = rng.uniform(0.03, 0.10) * h
                cx = tx + math.cos(math.radians(a)) * rr
                cy = ty + math.sin(math.radians(a)) * rr * 0.8
                lw = rng.uniform(7, 14) * SS
                d.ellipse([cx - lw, cy - lw * 0.75, cx + lw, cy + lw * 0.75],
                          fill=255)


def make_scrub():
    """The band, and the moonlight on its crown. Its foot dissolves into the
    litter and its crown stays hard against the sky.
    """
    mask = wrapped(SCRUB_W, SCRUB_H, _scrub_draw)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    h, w = arr.shape

    # Moonlight on the top of it and nothing at all in the mass, plus a
    # two-scale grain so a hedge fifty metres long is not one value.
    ramp = np.linspace(1.0, 0.30, h, dtype=np.float32)[:, None]
    grain = np.asarray(
        Image.fromarray((np.clip(fbm2(256, 5253, octaves=5, base=6), 0, 1)
                         * 255).astype(np.uint8), "L")
             .resize((w, h), Image.LANCZOS), dtype=np.float32) / 255.0
    val = np.clip(ramp * (0.66 + 0.62 * grain), 0.16, 1.0)
    body = np.repeat((val * 255)[..., None], 3, axis=2)

    foot = np.clip(np.linspace(1.0, 0.0, h, dtype=np.float32) * 6.0,
                   0, 1)[:, None]
    band = A.from_arrays(body, arr * foot)

    # The moonward crown. This mask is already at final size, so the edge is
    # taken here rather than through `rim_sprite` (which works at SS).
    edge = edge_light(mask, -6, 5, 2.6, 1.5)
    rim = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    rim.putalpha(edge)
    rim = rim.resize((w // RIM_DIV, h // RIM_DIV), Image.LANCZOS)
    return band, rim


# ---------------------------------------------------------------------------
# The floor
# ---------------------------------------------------------------------------

def fbm2(n, seed, octaves=5, base=4):
    """Value noise periodic in both axes, as a 0..1 array `n` square: the noise
    grid's first row and first column are repeated at the far edges before
    upsampling (`A.fbm_field` only does rows).
    """
    rng = np.random.default_rng(seed)
    acc = np.zeros((n, n), dtype=np.float32)
    amp, total, freq = 1.0, 0.0, float(base)
    for _ in range(octaves):
        g = max(2, int(round(freq)))
        cell = rng.random((g, g), dtype=np.float32)
        cell = np.vstack([cell, cell[:1]])
        cell = np.hstack([cell, cell[:, :1]])
        layer = np.asarray(
            Image.fromarray((cell * 255).astype(np.uint8), "L")
                 .resize((n, n), Image.BICUBIC), dtype=np.float32) / 255.0
        acc += layer * amp
        total += amp
        amp *= 0.5
        freq *= 2
    return acc / max(1e-6, total)


def _floor_marks(d, n, rng):
    """Litter, roots and stones, drawn at every offset of plus and minus one
    tile and cropped to the middle, so anything crossing an edge arrives back
    at the opposite one. Nothing may be more than a tile across.
    """
    state = rng.bit_generator.state
    for oy in (-n, 0, n):
        for ox in (-n, 0, n):
            rng.bit_generator.state = state

            # Roots: long, low ribbons crossing the tile, the one element with
            # a direction.
            for _ in range(5):
                x = rng.uniform(0, n) + ox
                y = rng.uniform(0, n) + oy
                a = rng.uniform(0, 360)
                pts, ws = [(x, y)], [rng.uniform(7, 15)]
                for _k in range(7):
                    a += rng.normal(0, 17)
                    x += math.cos(math.radians(a)) * n * 0.11
                    y += math.sin(math.radians(a)) * n * 0.11
                    pts.append((x, y))
                    ws.append(ws[0] * rng.uniform(0.5, 1.0))
                tapered(d, pts, ws, fill=210)

            # Leaf litter. Small ovals at every angle, in drifts rather than
            # evenly -- leaves collect.
            for _ in range(26):
                cx = rng.uniform(0, n) + ox
                cy = rng.uniform(0, n) + oy
                for _k in range(int(rng.integers(4, 12))):
                    lx = cx + rng.normal(0, n * 0.045)
                    ly = cy + rng.normal(0, n * 0.045)
                    lw = rng.uniform(5, 13)
                    lh = lw * rng.uniform(0.45, 0.75)
                    d.ellipse([lx - lw, ly - lh, lx + lw, ly + lh],
                              fill=int(rng.uniform(170, 255)))

            # Twigs: thin and dark, the only thing below the earth's base
            # value.
            for _ in range(22):
                x = rng.uniform(0, n) + ox
                y = rng.uniform(0, n) + oy
                a = rng.uniform(0, 360)
                L = rng.uniform(14, 46)
                d.line([(x, y),
                        (x + math.cos(math.radians(a)) * L,
                         y + math.sin(math.radians(a)) * L)],
                       fill=70, width=2)

            # Stones.
            for _ in range(9):
                x = rng.uniform(0, n) + ox
                y = rng.uniform(0, n) + oy
                r = rng.uniform(4, 11)
                d.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=245)


def make_floor():
    """The forest floor, in luminance: a texture with things placed in it,
    since a ground plane shaded per screen row can only produce horizontal
    bands.
    """
    n = FLOOR
    earth = fbm2(n, 4321, octaves=5, base=3)
    fine = fbm2(n, 8765, octaves=4, base=14)
    base = 0.40 + 0.30 * earth + 0.16 * fine

    # Moss in patches, thresholded so it has edges.
    moss = np.clip((fbm2(n, 2468, octaves=4, base=4) - 0.50) * 4.2, 0, 1)
    base = base * (1 - moss * 0.45) + moss * 0.78

    layer = Image.fromarray(
        np.clip(base * 255, 0, 255).astype(np.uint8), "L")

    marks = Image.new("L", (n, n), 0)
    _floor_marks(ImageDraw.Draw(marks), n, np.random.default_rng(1357))
    dark = Image.new("L", (n, n), 0)
    # The marks carry their own value; composite them over the earth by
    # brightness rather than pasting, so a twig at 70 darkens and a stone at
    # 245 lifts.
    m = np.asarray(marks, dtype=np.float32) / 255.0
    hit = m > 0.01
    arr = np.asarray(layer, dtype=np.float32) / 255.0
    arr = np.where(hit, arr * 0.35 + m * 0.65, arr)
    arr = arr * (0.90 + 0.20 * fbm2(n, 999, octaves=3, base=30))

    body = np.repeat(np.clip(arr, 0.16, 1.0)[..., None] * 255, 3, axis=2)
    return A.from_arrays(body, np.ones((n, n), dtype=np.float32))


# ---------------------------------------------------------------------------
# The moon
# ---------------------------------------------------------------------------

def make_moon():
    """A full moon, in luminance: a disc with structure (maria at half value, a
    limb that darkens toward the edge, and craters) rather than a flat lamp.
    """
    n = MOON
    dx, dy, r = A.grid(n, n)
    disc = np.clip((0.985 - r) * (n * 0.5) / 3.0, 0, 1)

    # Limb darkening, so the edge isn't a hard bright line.
    lam = np.clip(1.0 - r ** 2, 0, 1) ** 0.42
    val = 0.62 + 0.38 * lam

    # The maria: large, soft dark blotches of thresholded noise.
    sea = np.asarray(A.fbm_field(n, n, 555, octaves=4, base=3),
                     dtype=np.float32) / 255.0
    val *= 1.0 - 0.30 * np.clip((sea - 0.46) * 3.4, 0, 1)

    grain = np.asarray(A.fbm_field(n, n, 771, octaves=3, base=26),
                       dtype=np.float32) / 255.0
    val *= 0.90 + 0.20 * grain

    img = Image.fromarray(
        np.clip(val * 255, 0, 255).astype(np.uint8), "L")
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(31337)
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        rr = math.sqrt(rng.random()) * n * 0.44
        cx = n / 2 + math.cos(a) * rr
        cy = n / 2 + math.sin(a) * rr
        cr = rng.uniform(3, 15)
        v = int(np.clip(val[int(cy), int(cx)] * 255, 0, 255))
        d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr],
                  fill=max(0, v - 26))
        d.arc([cx - cr, cy - cr, cx + cr, cy + cr], 200, 340,
              fill=min(255, v + 30), width=2)

    body = np.repeat(np.asarray(img, dtype=np.float32)[..., None], 3, axis=2)

    # Black wherever the disc is not: a PNG keeps colour in fully transparent
    # pixels, and a blend that ignores source alpha (such as `bm_subtract`)
    # would draw the whole square. Thresholded rather than premultiplied, so
    # the disc's soft edge isn't dimmed by its alpha twice.
    body = body * (disc > 0.004)[..., None]
    return A.from_arrays(body, disc)


# ---------------------------------------------------------------------------
# The bands: a far treeline, a canopy overhead, and mist
#
# Periodic in x rather than y, because the distant world slides sideways
# rather than down: a band is drawn three times at -W, 0 and +W and cropped
# to the middle.
# ---------------------------------------------------------------------------

def wrapped(w, h, draw_fn):
    """Draw a band three times side by side and keep the middle copy, so
    anything crossing an edge arrives from the other side (the x-axis
    counterpart of `shade_wrapped` in `make_bg.py`).
    """
    big = Image.new("L", (w * SS * 3, h * SS), 0)
    d = ImageDraw.Draw(big)
    draw_fn(d, w * SS, h * SS)
    mid = big.crop((w * SS, 0, 2 * w * SS, h * SS))
    return mid.resize((w, h), Image.LANCZOS)


def _treeline_draw(d, w, h):
    """The far wall of wood, as a row of whole trees behind the moon.

    Each tree is a trunk carrying its width up to a fork, and two or three
    limbs dividing twice and tapering to nothing, so nothing ends bluntly. One
    trunk per stratum of the tile, so the moon shows between trees rather than
    through a mesh.
    """
    n = 22
    for i in range(3):
        off = i * w
        rng = np.random.default_rng(9090)      # the same wood, three times
        for k in range(n):
            x = (k + rng.uniform(0.15, 0.85)) * w / n + off
            th = rng.uniform(0.52, 0.94) * h          # how tall this tree is
            fork = th * rng.uniform(0.42, 0.60)       # where its trunk divides
            tw = rng.uniform(16, 34) * SS             # trunk width at the root
            lean = rng.normal(0, 5)
            fx = x + math.tan(math.radians(lean)) * fork
            fy = h - fork
            tapered(d, [(x, h + 8 * SS),
                        ((x + fx) * 0.5 + rng.normal(0, 3 * SS),
                         h - fork * 0.5),
                        (fx, fy)],
                    [tw, tw * 0.80, tw * 0.62])
            kids = 2 if rng.random() < 0.55 else 3
            spread = rng.uniform(34, 52)
            for j in range(kids):
                t = (j / (kids - 1)) - 0.5 if kids > 1 else 0.0
                limb(d, rng, fx, fy, -90 + lean + t * spread * 2
                     + rng.normal(0, 5),
                     (th - fork) * rng.uniform(0.72, 0.95),
                     tw * 0.62 * rng.uniform(0.62, 0.80), 2, [],
                     taper=0.62, segs=4, wobble=6.0)


def make_treeline():
    """The wall of wood at the far end of the corridor: one band standing on
    the horizon, so the ground doesn't meet the sky along a ruled line.
    """
    mask = wrapped(TREELINE_W, TREELINE_H, _treeline_draw)
    # The tallest crowns reach the top of the band, so it is windowed there.
    mask = soft_border(mask, sides="t", frac=0.10)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    # The feet of it go into the haze rather than ending on a line.
    ramp = np.linspace(1.0, 0.18, TREELINE_H, dtype=np.float32)[:, None]
    body = np.full((TREELINE_H, TREELINE_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, arr * ramp)


def _canopy_draw(d, w, h):
    for i in range(3):
        off = i * w
        rng = np.random.default_rng(4141)
        # Heavy boughs first, so the top of the frame is closed: `limb`s
        # reaching sideways out of the top edge at thirty-five to sixty-five
        # degrees off vertical, forking twice.
        for _ in range(10):
            x = rng.uniform(0, w) + off
            side = 1 if rng.random() < 0.5 else -1
            limb(d, rng, x, -30 * SS, 90 + side * rng.uniform(35, 65),
                 rng.uniform(0.50, 0.80) * h,
                 rng.uniform(30, 54) * SS, 2, [], taper=0.62, segs=5,
                 wobble=7.0)
        # Branches reaching sideways and ending well short of the band's
        # bottom edge.
        for _ in range(15):
            x = rng.uniform(0, w) + off
            limb(d, rng, x, -10 * SS, 90 + rng.normal(0, 44),
                 rng.uniform(0.28, 0.52) * h,
                 rng.uniform(7, 18) * SS, 2, [], taper=0.6, segs=4,
                 wobble=8.0)


def make_canopy():
    """Branches reaching in over the top of the frame, so the corridor has a
    ceiling and the moon doesn't sit in an empty sky.
    """
    mask = wrapped(CANOPY_W, CANOPY_H, _canopy_draw)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    # The alpha reaches zero at the last row (the band's bottom edge would
    # otherwise be a straight line across the field), easing out over the
    # lower half.
    t = np.clip((np.linspace(0.0, 1.0, CANOPY_H, dtype=np.float32) - 0.40)
                / 0.55, 0.0, 1.0)
    ramp = (1.0 - t * t * (3.0 - 2.0 * t))[:, None]
    body = np.full((CANOPY_H, CANOPY_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, arr * ramp)


def make_mist():
    """A soft band of fog, periodic in x. White, because it is always drawn
    additively, so it can't hide a bullet.
    """
    # Periodic in x: `fbm_field` wraps in y, so the field is generated
    # transposed and turned back.
    f = np.asarray(A.fbm_field(MIST_H, MIST_W, 606, octaves=4, base=3,
                               wrap_y=True), dtype=np.float32).T / 255.0

    # Clipped before the power: `sin(pi)` comes back slightly negative in
    # float32, and a negative base to a fractional power is NaN.
    win = np.clip(np.sin(np.linspace(0, math.pi, MIST_H,
                                     dtype=np.float32)), 0, 1) ** 1.4
    alpha = np.clip((f - 0.30) * 1.7, 0, 1) * win[:, None]
    body = np.full((MIST_H, MIST_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, alpha)


# ---------------------------------------------------------------------------
# The spell background's one motif
# ---------------------------------------------------------------------------

def make_antler():
    """An antler, for the bottom corners of the grove's spell background: a
    contour rising out of the frame, like Ziggy's horns.
    """
    w, h = ANTLER_W * SS, ANTLER_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)

    # Hand-placed: one heavy beam that leans, and brow, bez and trez tines
    # leaving the same side of it, each shorter than the last. Every number is
    # a fraction of the frame. The beam ends short of the top edge because no
    # `soft_border` is applied; the antler rises out of a bottom corner of the
    # field, so its own bottom is meant to be cut.
    def stroke(pts, w0, w1):
        px = [(x * w, y * h) for x, y in pts]
        n = len(px)
        tapered(d, px, [w0 + (w1 - w0) * i / (n - 1) for i in range(n)])

    stroke([(0.50, 1.02), (0.46, 0.80), (0.44, 0.62), (0.47, 0.45),
            (0.55, 0.30), (0.65, 0.18), (0.75, 0.09)], 46 * SS, 10 * SS)
    stroke([(0.46, 0.80), (0.34, 0.70), (0.22, 0.63), (0.11, 0.59)],
           21 * SS, 3.5 * SS)
    stroke([(0.44, 0.62), (0.31, 0.51), (0.19, 0.43), (0.09, 0.38)],
           19 * SS, 3.5 * SS)
    stroke([(0.47, 0.45), (0.35, 0.34), (0.25, 0.25), (0.18, 0.19)],
           16 * SS, 3.5 * SS)
    stroke([(0.65, 0.18), (0.59, 0.09), (0.56, 0.03)], 12 * SS, 3 * SS)
    stroke([(0.75, 0.09), (0.80, 0.03)], 10 * SS, 3 * SS)

    body, _ = body_from_mask(mask, 8124, floor=0.45)
    return body


# ---------------------------------------------------------------------------
# The generated table
# ---------------------------------------------------------------------------

TABLE = """\
/// @desc The Hollow Grove's scenery numbers -- GENERATED by
///       tools/make_grove.py. Do not edit.
///
/// Where a charm can be tied: the branch tips are found where the trees are
/// drawn and written out here, as `bullet_table` does for hit radii. Each
/// entry is one tree frame's list of `[u, v]` in the sprite's own box, 0..1
/// from its top-left. A frame may have none.

function grove_table_init() {
    global.grove_hang = [
%s
    ];
}

/// @desc How many places tree frame `_f` offers. Zero is a real answer.
function grove_hang_count(_f) {
    return array_length(global.grove_hang[_f]);
}

/// @desc The `_i`th of them, as `[u, v]`.
function grove_hang_at(_f, _i) {
    return global.grove_hang[_f][_i];
}
"""


def write_table(hangs):
    rows = []
    for frame in hangs:
        pts = ", ".join("[%.4f, %.4f]" % (u, v) for u, v in frame)
        rows.append("        [%s]," % pts)
    path = os.path.join(A.ROOT, "scripts", "grove_table", "grove_table.gml")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    gm_new.write(path, TABLE % "\n".join(rows))
    gm_new.script("grove_table")
    print("grove_table.gml: %d tree frames, %d hang points"
          % (len(hangs), sum(len(f) for f in hangs)))


# ---------------------------------------------------------------------------

def main():
    gm_new.folder("Sprites/scn")
    folder = "Sprites/scn"

    trees, tree_rims, hangs = make_trees()
    boughs = [bough_from(t) for t in trees]
    bough_rims = [bough_from(r) for r in tree_rims]
    trunks, trunk_rims = make_trunks()
    leaves = make_leaves()
    charms, charm_lits = make_charms()
    bushes, bush_rims = make_bushes()
    brush, brush_rims = make_brush()

    gm_new.sprite("spr_scn_tree", trees,
                  origin=(TREE_W // 2, TREE_H), folder=folder)
    gm_new.sprite("spr_scn_tree_rim", tree_rims,
                  origin=(TREE_W // RIM_DIV // 2, TREE_H // RIM_DIV),
                  folder=folder)
    gm_new.sprite("spr_scn_bough", boughs,
                  origin=(TREE_W // 2, TREE_H), folder=folder)
    gm_new.sprite("spr_scn_bough_rim", bough_rims,
                  origin=(TREE_W // RIM_DIV // 2, TREE_H // RIM_DIV),
                  folder=folder)
    gm_new.sprite("spr_scn_charm", charms,
                  origin=(CHARM_W // 2, 0), folder=folder)
    gm_new.sprite("spr_scn_charm_lit", charm_lits,
                  origin=(CHARM_W // 2, 0), folder=folder)
    gm_new.sprite("spr_scn_trunk", trunks,
                  origin=(TRUNK_W // 2, TRUNK_H), folder=folder)
    gm_new.sprite("spr_scn_trunk_rim", trunk_rims,
                  origin=(TRUNK_W // RIM_DIV // 2, TRUNK_H // RIM_DIV),
                  folder=folder)
    gm_new.sprite("spr_scn_leaf", leaves,
                  origin=(int(LEAF_W * 0.06), LEAF_H // 2), folder=folder)
    gm_new.sprite("spr_scn_bush", bushes,
                  origin=(BUSH_W // 2, BUSH_H), folder=folder)
    gm_new.sprite("spr_scn_bush_rim", bush_rims,
                  origin=(BUSH_W // RIM_DIV // 2, BUSH_H // RIM_DIV),
                  folder=folder)
    gm_new.sprite("spr_scn_brush", brush,
                  origin=(BRUSH_W // 2, BRUSH_H), folder=folder)
    gm_new.sprite("spr_scn_brush_rim", brush_rims,
                  origin=(BRUSH_W // RIM_DIV // 2, BRUSH_H // RIM_DIV),
                  folder=folder)

    moon = make_moon()
    gm_new.sprite("spr_scn_moon", [moon], origin="center", folder=folder)

    floor = make_floor()
    gm_new.sprite("spr_scn_floor", [floor], origin="topleft", folder=folder)

    treeline = make_treeline()
    scrub, scrub_rim = make_scrub()
    canopy = make_canopy()
    mist = make_mist()
    gm_new.sprite("spr_scn_treeline", [treeline], origin="topleft",
                  folder=folder)
    gm_new.sprite("spr_scn_scrub", [scrub], origin="topleft", folder=folder)
    gm_new.sprite("spr_scn_scrub_rim", [scrub_rim], origin="topleft",
                  folder=folder)
    gm_new.sprite("spr_scn_canopy", [canopy], origin="topleft", folder=folder)
    gm_new.sprite("spr_scn_mist", [mist], origin="topleft", folder=folder)

    antler = make_antler()
    gm_new.sprite("spr_scn_antler", [antler],
                  origin=(ANTLER_W // 2, ANTLER_H), folder=folder)

    write_table(hangs)

    # The previews, each over a dark ground and a light one.
    shown, labels = [], []
    for i, img in enumerate(trees):
        shown.append(img.resize((TREE_W // 3, TREE_H // 3), Image.LANCZOS))
        labels.append("tree %d" % i)
    for i, img in enumerate(trunks):
        shown.append(img.resize((TRUNK_W // 4, TRUNK_H // 4), Image.LANCZOS))
        labels.append("trunk %d" % i)
    A.preview(shown, os.path.join(A.PREVIEW, "grove_trees.png"), cols=6,
              bg=(12, 16, 26), labels=labels)

    shown, labels = [], []
    for i, img in enumerate(charms):
        lit = A.add(img, charm_lits[i])
        shown.append(lit.resize((CHARM_W, CHARM_H), Image.LANCZOS))
        labels.append(CHARMS[i].__name__[6:])
    for i, img in enumerate(bushes):
        shown.append(img.resize((BUSH_W // 2, BUSH_H // 2), Image.LANCZOS))
        labels.append("bush %d" % i)
    for i, img in enumerate(brush):
        shown.append(img.resize((BRUSH_W // 2, BRUSH_H // 2), Image.LANCZOS))
        labels.append(BRUSHES[i].__name__[7:])
    for i, img in enumerate(leaves):
        shown.append(img.resize((LEAF_W, LEAF_H), Image.LANCZOS))
        labels.append("ivy %d" % i)
    A.preview(shown, os.path.join(A.PREVIEW, "grove_props.png"), cols=6,
              bg=(12, 16, 26), labels=labels)

    A.preview([floor, floor], os.path.join(A.PREVIEW, "grove_floor.png"),
              cols=2, bg=(12, 16, 26), labels=["floor", "floor (tiled)"])

    A.preview([moon.resize((256, 256), Image.LANCZOS),
               treeline.resize((TREELINE_W // 3, TREELINE_H // 3),
                               Image.LANCZOS),
               scrub.resize((SCRUB_W // 3, SCRUB_H // 3), Image.LANCZOS),
               canopy.resize((CANOPY_W // 3, CANOPY_H // 3), Image.LANCZOS),
               mist.resize((MIST_W // 3, MIST_H // 3), Image.LANCZOS),
               antler.resize((ANTLER_W // 3, ANTLER_H // 3), Image.LANCZOS)],
              os.path.join(A.PREVIEW, "grove_bands.png"), cols=2,
              bg=(12, 16, 26),
              labels=["moon", "treeline", "scrub", "canopy", "mist",
                      "antler"])

    print("grove: %d trees, %d trunks, %d ivy, %d charms, %d bushes, "
          "%d brush, 6 bands"
          % (len(trees), len(trunks), len(leaves), len(charms), len(bushes),
             len(brush)))


if __name__ == "__main__":
    main()
