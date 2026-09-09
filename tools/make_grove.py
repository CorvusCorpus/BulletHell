#!/usr/bin/env python3
"""The Hollow Grove: a forest that is flown *through* rather than over.

**This stage is not a parallax stack and none of its art tiles.** Stage one is
a floor seen from above, so its world is three sprites the size of the field
scrolling down the screen; the grove is a corridor seen from inside, so its
world is a handful of *billboards* that the camera passes. Everything here is
therefore a prop drawn at a size and a position the game works out at run time
from a depth -- see `scripts/bg_corridor` for the projection and
`scripts/bg_grove` for what is arranged in it.

That difference is why nothing in this file is `spr_bg_*`. `check_bg_seams`
and `check_bg_keepout` in `tools/check_project.py` measure every sprite under
that prefix, and both of them are asking questions about a *scrolling tile*:
does its last row match its first, and does it keep out of the middle of a
layer that is drawn over the field. Neither question means anything about a
tree. The prefix here is `spr_scn_` -- scenery -- and the rules those checks
enforce are enforced for this stage where they can be: the corridor's
foreground is additive by construction, so it cannot hide a bullet at any
alpha (see `grove_draw_front`).

Everything is drawn as **luminance and tinted at draw time**, which is the same
decision `tools/make_ui.py` records and it is load-bearing twice over here. The
grove is lit by one moon, and half way through the stage that moon turns to
blood -- so every tree, every hanging charm, every fern and the mist between
them has to change colour together. A painted-in hue would mean a second copy
of the entire stage.

Each solid thing therefore ships as two sprites:

`spr_scn_thing`      the body, white, with its own internal value structure.
                     Tinted dark at draw time; it is a silhouette in fog.
`spr_scn_thing_rim`  the moonward edge, white, drawn **additively** in
                     whatever the moon currently is.

**A dark mass with no rim is a hole in the picture** -- the same finding
`A.rim_light` exists for -- and splitting the rim out rather than baking it in
is what lets the body be night-blue while the light on it is bone-white, and
then crimson, without redrawing anything.

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
# **A billboard is authored at the size it is biggest on screen, not bigger.**
# The corridor scales a tree up to about 1.6 times this at its closest, which
# is a whisker of softening on a shape that is a near-black silhouette in fog;
# authoring it at the closest size instead would put five frames of 1200x1900
# on a texture page for two seconds of screen time each.
# ---------------------------------------------------------------------------

TREE_W, TREE_H = 480, 780
TREE_N = 6

# **The rim ships at half the body's resolution and nothing has to know.** It
# is a blurred edge a few pixels wide -- there is no detail in it a half-scale
# copy could lose -- and it saves as much texture page as the bodies cost. The
# draw side derives the factor from the two sprites' own widths rather than
# being told it, so the two cannot be edited apart.
RIM_DIV = 2

# **The trunk of a tree the camera goes past, rather than a whole tree seen
# from across a clearing.** The wood was six frames of complete tree and it
# photographed as a hedge: at any distance where a whole tree fits in the
# frame, nothing in the picture is *near*, and a forest you are flying through
# is mostly the thing you are about to hit. A trunk is drawn as a fragment --
# it leaves the top of its own frame, so the tree it belongs to is always
# bigger than the screen.
TRUNK_W, TRUNK_H = 460, 1020

# **Eight, and they are eight different trees rather than eight seeds.** Four
# near-identical heavy columns read as one sprite pasted over and over, which
# is what they were: the generator varied a lean and a width and every frame
# came out a slightly different post. What tells two trunks apart at a glance
# is the *silhouette* -- whether it forks, whether it leans and recovers,
# whether it is squat or slender, where its boughs leave -- so the frames are
# a list of those and the randomness is what fills each one in.
TRUNK_N = 8

# Ivy. The one green thing in the wood, and the reason the palette is not two
# colours.
LEAF_W, LEAF_H = 230, 180
LEAF_N = 5

CHARM_W, CHARM_H = 136, 260
CHARM_N = 7

BUSH_W, BUSH_H = 380, 210
BUSH_N = 4

# The forest floor. **One tile, periodic in both axes**, laid down the
# corridor in bands -- see `grove_draw_floor`. It is square because it is
# tiled sideways as well as forward, which is the whole difference between a
# floor and a set of stripes.
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
    """A polyline drawn as a ribbon that narrows along its length.

    **A branch is a taper, not a line of constant width**, and PIL has no
    stroke with a width per point -- so the ribbon is built as one polygon
    from the two offset edges. Round joints are then unnecessary: consecutive
    quads share their end points exactly, so the seam is not a seam.
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
    """A stroke that curves at a constant rate. Returns its points.

    `limb` wobbles, because a branch is grown; this does not, because the
    things it draws -- an antler's beam and its tines -- are *bone*, and bone
    is smooth. A wobbled antler reads as a stick.
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

    `hangs` collects the tips a charm could be tied to. **The hang points are
    worked out here and written into `scripts/grove_table`**, for the same
    reason a bullet's hit radius is: the branch and the thing hanging off it
    are one fact, and a number describing a picture that lives in a different
    language from the picture is a number that will be edited apart from it
    within a week.
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
        # A tip. Only the ones reaching sideways and downward are worth
        # hanging anything from -- a charm tied to a branch pointing straight
        # up hangs back across the branch it is tied to.
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
    """Fade a mask to nothing at the sprite's own edge.

    **A billboard's edge is a hard clip**, so a branch that reaches the border
    is not a branch that ran out -- it is a branch sliced flat along a
    perfectly straight vertical line, which at any depth in a forest of
    silhouettes reads as a rectangle. It is the same defect `cut_pad` was
    written for one file over, and it has the same two possible answers: leave
    a margin, or window the edge.

    The window is the one that cannot be got wrong. A margin is arithmetic --
    every branch length, every lean and every recursion depth staying inside a
    budget -- and the first version of this tree missed it on four frames out
    of six.

    The bottom is never windowed: that is where the tree meets the ground, and
    a root fading out before it lands is a tree hovering.
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

    Bare and gnarled rather than leafy. The reference for this stage is a
    forest somebody has hung things in, and things hang off *branches* -- a
    canopy would hide every one of them, and a canopy at night is a black
    blob with nothing in it to read.
    """
    rng = np.random.default_rng(seed)
    w, h = TREE_W * SS, TREE_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    hangs = []

    base_x = TREE_W * 0.5 * SS
    base_y = h - 2 * SS

    # The trunk.
    #
    # **It leans, and then it changes its mind**, which is the whole of what
    # separates a witch-forest tree from a telegraph pole. The first version
    # of this had one lean per tree and a little wobble on top, and six of
    # them side by side read as six upright poles with a slight list --
    # accurate, characterless, and exactly the "drawn by a script" the
    # brimstone rock was rebuilt to escape. What is here instead is an elbow:
    # the lean is applied one way below a node picked at random and the other
    # way above it, so the trunk goes out and comes back.
    #
    # The width is authored at the base and taken down hard, because these are
    # a heavy root and a thin crown.
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
        # A burl or two: the width does not fall off smoothly, it swells where
        # a bough was lost. One cosine is enough to stop the taper reading as
        # a cone.
        burl = 1.0 + 0.16 * math.cos(t * 7.0 + seed % 7)
        pts.append((x, y))
        widths.append(wid * (1.0 - 0.70 * t ** 0.80) * burl)
        y -= step
        x += lean * step * (1 if i < elbow else -1) + rng.normal(0, 11 * SS)
    tapered(d, pts, widths)

    # Root flare. Wedges going *down and out* into the ground, which is what
    # stops a trunk reading as a post pushed into a floor -- and which the
    # first version did not draw at all, because it handed `limb` an angle
    # measured the wrong way round and half the roots went up the trunk.
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

    # The crown. Boughs off the upper half of the trunk, and a pair off the
    # very top, so the silhouette spreads rather than forking once.
    #
    # **They reach out before they reach up.** A bough leaving the trunk at
    # thirty degrees off vertical draws a fir; the trees in this wood hold
    # their arms out, so the spread starts nearer sixty and the ones low on
    # the trunk are allowed to droop past horizontal.
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

    # Hanging vines. Thin, drooping, and never structural -- they are what
    # makes the silhouette read as *overgrown* rather than as dead. Started a
    # little back along the branch rather than at its very tip, because a
    # vine hung off the last pixel of a two-pixel twig reads as a stroke
    # floating in mid-air.
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
    """The value field a trunk is textured with, 0..1.

    Two scales, because one reads as film noise and two as a surface -- the
    same finding the brimstone rock is built on, turned on its side. **Bark
    runs up**, so the field is generated short and stretched vertically: a
    noise field squashed in y has features elongated in y, which is a
    striation. Generated wide and stretched sideways -- which is the mistake
    the first version of this made -- it has features elongated in x, and what
    that draws is a tree with tide marks across it.
    """
    def band(rows, base, s):
        return np.asarray(
            A.fbm_field(w, max(3, rows), s, octaves=3, base=base)
             .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0

    coarse = band(max(3, h // 12), 9, seed)
    fine = band(max(3, h // 5), 30, seed + 91)
    return np.clip(0.50 + 0.36 * coarse + 0.22 * fine, 0.32, 1.0)


def body_from_mask(mask, seed, floor=0.35, gradient=0.0):
    """A white body carrying its own value structure, at final size.

    White because it is **tinted at draw time** -- see the note at the top of
    this file. The structure lives in the value, so a body multiplied by a
    near-black night colour is a near-black tree that still has bark on it.
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
    """Light one *side* of a silhouette.

    `A.rim_light` drops the mask straight down, because the brimstone stage is
    lit from underneath by its own cracks. This forest is lit by a single moon
    sitting on the horizon in the middle of the screen, so the lit edge of a
    tree is the edge facing the middle -- which is a shift in x, and mirrored
    per side by the draw call rather than by a second sprite.
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


# Eight silhouettes, and every column of this table is a thing the eye can see
# from across the screen. `lean` is how far it goes over, `bend` whether it
# comes back, `wid` its base width as a share of the frame, `boughs` how many
# leave it, `fork` whether it splits into two near the top, and `burl` how
# lumpy the taper is.
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
    """A trunk that fills the frame and leaves the top of it.

    **The silhouette is doing something different from `tree_mask`'s.** A whole
    tree is read by its crown; a trunk passing the camera is read by its
    *edges* -- how it swells, where a bough leaves it, whether it forks --
    because at that size the crown is off screen entirely.
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
        # Swelling rather than tapering: over the height of one frame a trunk
        # this wide barely narrows, and what the eye reads instead is the
        # irregularity. Two cosines out of phase give it a waist and a
        # shoulder without either being placed by hand.
        k = (1.0 - 0.26 * t) * (1.0 + burlk * math.cos(t * 5.5 + seed % 5)
                                + burlk * 0.5 * math.cos(t * 11.0 + seed % 3))
        pts.append((x, y))
        widths.append(wid * k)
        y -= h / (n - 1)
        x += side * lean * (h / (n - 1)) * (1 if i < elbow else -1) \
             + rng.normal(0, 10 * SS)
    tapered(d, pts, widths)

    # A fork: the trunk splits and both halves leave the top of the frame.
    # **The one variation that changes the whole silhouette**, which is why two
    # of the eight have it.
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

    # Root flare, wide and shallow -- at this size it is a third of what says
    # "this is standing in the ground", and the ground is right at the bottom
    # of the frame.
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

    # Boughs, and **every one of them leaves the frame**. A bough that ended
    # inside the picture would put a branch tip the size of a bullet in the
    # foreground, which is the one thing scenery may never look like.
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
    """A clump of ivy on a stem.

    Six to fourteen leaves off a curving runner, each a simple pointed oval.
    **Drawn as a mass rather than as leaves**: at the size these are seen the
    individual leaf is two pixels, and what has to read is a ragged green
    patch with a stem going into it.
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
        # A pointed oval: an ellipse plus a triangle for the tip, which is the
        # cheapest thing that stops a leaf reading as a pebble.
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
# **The charms are the one place in this stage allowed a second hue.** The
# forest is one colour and a moon; a hex burning on a cord is the only thing in
# it somebody *made*, and it is what says this wood belongs to somebody. Each
# ships as a body and a `lit` layer, and the lit layer is drawn additively --
# so what glows is the carving, never the wood it is carved into.
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
    # The rune. Three strokes, struck rather than drawn -- a closed glyph at
    # this size fills in and reads as a blob, which is what the first pass of
    # it did anyway because the strokes were as wide as the gaps between
    # them. Thin, and spread over a plaque half again as big.
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
    # **Long, and knuckled at both ends.** The first pass drew four short
    # struts with big balls on them and what that is a picture of is a
    # molecule. A long bone is mostly shaft: the shaft went up by half and
    # the knuckles came down by a third, and it reads immediately.
    # Three, not four, and shorter than the frame is wide. At four they
    # radiated evenly from one point, which is a picture of a jack; at the
    # length they were, the outer two were sliced off by the sprite's own
    # edge, which on a billboard is a hard vertical cut through a bone.
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
    # Three teeth on cords under it. Movement without motion.
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
    # Muzzle. Narrow -- a wide one reads as a jaw and the whole thing becomes
    # a face rather than a skull.
    d.polygon([(cx - w * 0.34, cy + h * 0.26), (cx + w * 0.34, cy + h * 0.26),
               (cx + w * 0.21, cy + h * 1.52), (cx - w * 0.21, cy + h * 1.52)],
              fill=255)
    # Horns, because a skull with horns reads as a skull at twenty pixels and
    # a skull without them reads as a stone. Long enough to leave the head's
    # own outline -- at the length they started they read as ears.
    for sgn in (-1, 1):
        limb(d, rng, cx + sgn * w * 0.72, cy - h * 0.40,
             -90 + sgn * 46, 92 * SS, 11 * SS, 1, [], taper=0.55, segs=4,
             wobble=7.0)
    # **Sockets, not headlamps.** At half again this size the two of them
    # were the brightest thing in the charm and it read as a face looking at
    # you rather than as a skull hanging in a tree.
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
    # **Small, so the cage is still a cage.** At the size this started, the
    # light filled the ribs and the charm was a white ball on a string --
    # which is what a bullet is, and a piece of scenery may never be one. The
    # bloom at draw time does the reaching; the drawn core does not have to.
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
        # The body carries the lit parts too, or the carving is a hole in the
        # charm whenever the accent is faint. It is the *additive* pass that
        # makes them burn.
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
    """Low fern masses that pass close to the camera along the path.

    **Most of the sense of speed lives down here**, because a thing near the
    bottom of the screen is close, and a close thing crosses the frame in a
    handful of frames. The trees say where you are; the ferns say how fast.
    """
    bodies, rims = [], []
    for i in range(BUSH_N):
        rng = np.random.default_rng(2400 + i * 13)
        w, h = BUSH_W * SS, BUSH_H * SS
        mask = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(mask)
        base_y = h - 2 * SS
        # **A clump, then the fronds off it.** Without the mass at the foot
        # these were a handful of scratches with holes between them -- read at
        # speed, that is not undergrowth, it is a scribble. The clump is what
        # the eye gets; the fronds are what tells it what the clump is.
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
# The floor
# ---------------------------------------------------------------------------

def fbm2(n, seed, octaves=5, base=4):
    """Value noise periodic in **both** axes, as a 0..1 array `n` square.

    `A.fbm_field` repeats the noise grid's first row at its bottom, which makes
    it periodic in y and is all a scrolling parallax layer needs. A floor tiled
    down a corridor is laid sideways as well, so the same trick has to be
    applied to the first *column* too -- and it has to be the grid that is made
    periodic rather than the upsampled field, for the reason that function's
    own docstring records: making the interpolation periodic is not the same as
    making the thing being interpolated periodic.
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
    """Litter, roots and stones, drawn nine times so everything wraps.

    Anything that crosses an edge of the tile has to arrive back at the
    opposite edge, and the cheapest way to be sure of that is to draw the whole
    lot at every offset of plus and minus one tile and keep the middle. It is
    `wrapped` in two dimensions, and the cost is that nothing may be more than
    a tile across -- which nothing on a forest floor is.
    """
    state = rng.bit_generator.state
    for oy in (-n, 0, n):
        for ox in (-n, 0, n):
            rng.bit_generator.state = state

            # Roots. Long, low ribbons crossing the tile -- the one element
            # here with a *direction*, and the reason the floor does not read
            # as gravel.
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

            # Twigs: thin, dark, and the only thing here that is *below* the
            # base value. A floor made entirely of things lighter than the
            # earth reads as a scattering on a surface rather than as one.
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
    """The forest floor, in luminance.

    **The ground was the last thing in this stage still being drawn as a
    formula**, and it was reported the way a formula always is: a flat expanse
    with props tossed on it. A ground plane shaded per screen row can only
    ever produce horizontal bands, because a row *is* a depth -- so however
    carefully the bands are tuned, what they draw is a set of stripes across
    the screen, which the eye reads as water. The fix is not a better formula.
    It is a texture with things in it that have positions.
    """
    n = FLOOR
    earth = fbm2(n, 4321, octaves=5, base=3)
    fine = fbm2(n, 8765, octaves=4, base=14)
    base = 0.40 + 0.30 * earth + 0.16 * fine

    # Moss, in patches. Thresholded so it has edges: moss grows in a place and
    # stops, where a smooth blend of two greens is a stain.
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
    """A full moon, in luminance. **Never white and never flat.**

    It is the brightest thing in the stage and it sits behind the middle of the
    playfield, which makes it the one piece of scenery a bullet has to read
    against. So it is drawn as a *disc with structure* rather than as a lamp:
    maria at half value, a limb that darkens toward the edge, and craters. The
    draw side then holds the whole thing well under white -- but a flat pale
    disc would have had to be held so far under to keep the field legible that
    it would have stopped reading as a moon.
    """
    n = MOON
    dx, dy, r = A.grid(n, n)
    disc = np.clip((0.985 - r) * (n * 0.5) / 3.0, 0, 1)

    # Limb darkening. A real one goes as roughly the cosine of the angle from
    # the centre; what matters here is that the edge is *not* a hard bright
    # line, because a hard bright circle is a UI element.
    lam = np.clip(1.0 - r ** 2, 0, 1) ** 0.42
    val = 0.62 + 0.38 * lam

    # The maria: large dark blotches. Thresholded noise rather than painted,
    # and deliberately soft -- crisp seas read as a texture map.
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

    # **Black wherever the disc is not, and this is not tidiness.** A PNG keeps
    # its colour channels in fully transparent pixels, and a luminance field
    # generated across the whole canvas is bright in every one of them -- so
    # this sprite was a bright grey square with a disc-shaped alpha channel.
    # Under any blend that does not weight the source by its alpha, and
    # GameMaker's `bm_subtract` is one, what draws is the *square*. It shipped
    # as a grey rectangle gliding across the sky during the eclipse.
    #
    # Thresholded rather than premultiplied, so the disc's own soft edge keeps
    # its colour instead of being dimmed by its alpha twice.
    body = body * (disc > 0.004)[..., None]
    return A.from_arrays(body, disc)


# ---------------------------------------------------------------------------
# The bands: a far treeline, a canopy overhead, and mist
#
# **These three are periodic in x, not in y**, which is the whole difference
# between this stage and stage one. Nothing here scrolls down the screen; the
# distant world slides *sideways* as the camera bores through it, so a band is
# drawn three times at -W, 0 and +W and cropped to the middle.
# ---------------------------------------------------------------------------

def wrapped(w, h, draw_fn):
    """Draw a band three times side by side and keep the middle copy.

    **The middle one, not the sum of the three.** Folding the thirds together
    -- which is what the first version did -- puts three copies of every tree
    in the same tile and saturates the mask; what is wanted is one copy whose
    neighbours have been drawn so that anything crossing an edge arrives from
    the other side. Cropping the middle third of three identical draws is
    exactly that, and it is the x-axis counterpart of `shade_wrapped` in
    `make_bg.py`.
    """
    big = Image.new("L", (w * SS * 3, h * SS), 0)
    d = ImageDraw.Draw(big)
    draw_fn(d, w * SS, h * SS)
    mid = big.crop((w * SS, 0, 2 * w * SS, h * SS))
    return mid.resize((w, h), Image.LANCZOS)


def _treeline_draw(d, w, h):
    """The far wall of wood.

    **Trunks first, and they are the point.** The first version was fifty
    branchy saplings, and against the moon that photographed as a scribble --
    a lace of two-pixel twigs with light coming through all of it, which reads
    as a texture rather than as a wood. What closes a distance is *mass*: a
    row of solid verticals with the moon showing between them, and the twigs
    laid over the top of that as the thing which stops the mass being a fence.
    """
    for i in range(3):
        off = i * w
        rng = np.random.default_rng(9090)      # the same wood, three times
        # The mass.
        for _ in range(30):
            x = rng.uniform(0, w) + off
            hh = rng.uniform(0.42, 0.98) * h
            tw = rng.uniform(26, 62) * SS
            tapered(d, [(x, h + 8 * SS),
                        (x + rng.normal(0, 8 * SS), h - hh * 0.5),
                        (x + rng.normal(0, 14 * SS), h - hh)],
                    [tw, tw * 0.72, tw * 0.34])
        # ...and the crowns over it.
        for _ in range(46):
            x = rng.uniform(0, w) + off
            hh = rng.uniform(0.34, 0.95) * h
            limb(d, rng, x, h + 6 * SS, -90 + rng.normal(0, 8), hh,
                 rng.uniform(8, 20) * SS, 2, [], taper=0.55, segs=4,
                 wobble=10.0)


def make_treeline():
    """The wall of wood at the far end of the corridor.

    It is one band and it stands on the horizon. What it is doing is closing
    the picture: without it the ground meets the sky along a ruled line, and a
    ruled line at the vanishing point is the single most generated-looking
    thing a corridor can have.
    """
    mask = wrapped(TREELINE_W, TREELINE_H, _treeline_draw)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    # The feet of it go into the haze rather than ending on a line.
    ramp = np.linspace(1.0, 0.18, TREELINE_H, dtype=np.float32)[:, None]
    body = np.full((TREELINE_H, TREELINE_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, arr * ramp)


def _canopy_draw(d, w, h):
    for i in range(3):
        off = i * w
        rng = np.random.default_rng(4141)
        # Heavy boughs first, so the top of the frame is closed rather than
        # fringed. A canopy of thin branches is a curtain of string.
        for _ in range(11):
            x = rng.uniform(0, w) + off
            tapered(d, [(x, -20 * SS),
                        (x + rng.normal(0, 30 * SS), h * 0.30),
                        (x + rng.normal(0, 50 * SS), h * 0.62)],
                    [rng.uniform(46, 92) * SS, rng.uniform(24, 44) * SS,
                     rng.uniform(8, 18) * SS])
        for _ in range(30):
            x = rng.uniform(0, w) + off
            limb(d, rng, x, -10 * SS, 90 + rng.normal(0, 30),
                 rng.uniform(0.42, 0.98) * h,
                 rng.uniform(7, 22) * SS, 2, [], taper=0.5, segs=4,
                 wobble=15.0)


def make_canopy():
    """Branches reaching in over the top of the frame.

    **A corridor with no ceiling is a road.** The grove has to feel closed in,
    and the cheapest way to say so is one band of black at the top of the sky
    with the moon under it -- which also stops the moon sitting in an empty
    rectangle, which is what it did for the first three screenshots.
    """
    mask = wrapped(CANOPY_W, CANOPY_H, _canopy_draw)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    # **Reaching zero at the last row, not merely getting small.** The band's
    # own bottom edge is a straight horizontal line across the whole field,
    # and a straight horizontal line is the one artefact a picture of a wood
    # cannot have. A ramp that ends at 0.35 leaves it visible.
    ramp = np.linspace(1.0, 0.0, CANOPY_H, dtype=np.float32)[:, None] ** 0.35
    body = np.full((CANOPY_H, CANOPY_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, arr * ramp)


def make_mist():
    """A soft band of fog, periodic in x.

    Drawn **additively** wherever it is used, which is why it is white and why
    nothing in the game ever asks it to be opaque: mist in a moonlit wood is
    light being scattered toward you, and light cannot hide a bullet.
    """
    # **Periodic in x, and the way it is got there is the one that works.**
    # `fbm_field` wraps in *y* -- it repeats the noise grid's first row at its
    # bottom before upsampling, so the thing being interpolated is periodic.
    # There is no x-wrapping flag and there does not need to be one: a field
    # generated transposed and turned back is periodic in the other axis. The
    # tempting alternative -- cross-fading the field with a rolled copy of
    # itself -- is the mistake `fbm_field`'s own docstring records, because it
    # makes the *weight* periodic and leaves the fields to disagree at the
    # join.
    f = np.asarray(A.fbm_field(MIST_H, MIST_W, 606, octaves=4, base=3,
                               wrap_y=True), dtype=np.float32).T / 255.0

    # Clipped before the power: `sin(pi)` comes back a hair *negative* in
    # float32, and a negative base to a fractional power is NaN -- which
    # propagates through the alpha and casts to whatever `uint8` makes of
    # it. One row of garbage along the bottom of the band.
    win = np.clip(np.sin(np.linspace(0, math.pi, MIST_H,
                                     dtype=np.float32)), 0, 1) ** 1.4
    alpha = np.clip((f - 0.30) * 1.7, 0, 1) * win[:, None]
    body = np.full((MIST_H, MIST_W, 3), 255.0, dtype=np.float32)
    return A.from_arrays(body, alpha)


# ---------------------------------------------------------------------------
# The spell background's one motif
# ---------------------------------------------------------------------------

def make_antler():
    """An antler, for the corners of the grove's spell background.

    Ziggy's forge puts his horns in the bottom corners and the reason it works
    is not that they are horns -- it is that a contour rising out of the frame
    is completed by the eye into a mass that is too big to be in the picture.
    The grove's caster wears a stag's skull, so hers are antlers.
    """
    w, h = ANTLER_W * SS, ANTLER_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)

    # **Hand-placed, and after three goes at generating it that is the right
    # answer.** Two versions used `limb` and one used a curved sweep with the
    # tines forked off it by angle, and all three came back as a bundle of
    # sticks -- because an antler is not a procedural shape. It is a specific
    # silhouette that everybody already knows: one heavy beam that leans, and
    # brow, bez and trez tines leaving the *same* side of it, each shorter
    # than the last, none of them forking again. Six polylines is the whole
    # of it, and it is the one place in this file where writing the shape
    # down beats growing it.
    #
    # Every number is a fraction of the frame, so the antler survives the
    # frame being resized -- and the beam ends short of the top edge because
    # `soft_border` is not applied here: this one is drawn rising *out* of the
    # bottom corner of the field, so its own bottom is meant to be cut.
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
///       tools/make_grove.py. **Do not edit.**
///
/// **Where a charm can be tied.** A tree is drawn by a Python script and hung
/// with things by GML, and the two have to agree about where its branches
/// are -- so the branch tips are worked out where the branches are drawn and
/// written out here, exactly as `bullet_table` carries a bullet's hit radius
/// beside the sprite it belongs to. A hang point that lived in GML would be a
/// number describing a picture in a different language from the picture, and
/// it would be wrong the first time a tree was redrawn.
///
/// Each entry is one tree frame's list of `[u, v]` in the sprite's own box,
/// 0..1 from its top-left. Some frames have fewer than others; a tree with no
/// branch reaching sideways has nowhere to hang anything.

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
    trunks, trunk_rims = make_trunks()
    leaves = make_leaves()
    charms, charm_lits = make_charms()
    bushes, bush_rims = make_bushes()

    gm_new.sprite("spr_scn_tree", trees,
                  origin=(TREE_W // 2, TREE_H), folder=folder)
    gm_new.sprite("spr_scn_tree_rim", tree_rims,
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

    moon = make_moon()
    gm_new.sprite("spr_scn_moon", [moon], origin="center", folder=folder)

    floor = make_floor()
    gm_new.sprite("spr_scn_floor", [floor], origin="topleft", folder=folder)

    treeline = make_treeline()
    canopy = make_canopy()
    mist = make_mist()
    gm_new.sprite("spr_scn_treeline", [treeline], origin="topleft",
                  folder=folder)
    gm_new.sprite("spr_scn_canopy", [canopy], origin="topleft", folder=folder)
    gm_new.sprite("spr_scn_mist", [mist], origin="topleft", folder=folder)

    antler = make_antler()
    gm_new.sprite("spr_scn_antler", [antler],
                  origin=(ANTLER_W // 2, ANTLER_H), folder=folder)

    write_table(hangs)

    # The previews. **Every one of these is shown over a dark ground and a
    # light one**, because a silhouette that reads on black and vanishes on
    # the moon is half a sprite -- the same reason `make_bullets.py` writes
    # its sheet twice.
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
               canopy.resize((CANOPY_W // 3, CANOPY_H // 3), Image.LANCZOS),
               mist.resize((MIST_W // 3, MIST_H // 3), Image.LANCZOS),
               antler.resize((ANTLER_W // 3, ANTLER_H // 3), Image.LANCZOS)],
              os.path.join(A.PREVIEW, "grove_bands.png"), cols=2,
              bg=(12, 16, 26),
              labels=["moon", "treeline", "canopy", "mist", "antler"])

    print("grove: %d trees, %d trunks, %d ivy, %d charms, %d bushes, 5 bands"
          % (len(trees), len(trunks), len(leaves), len(charms), len(bushes)))


if __name__ == "__main__":
    main()
