#!/usr/bin/env python3
"""Mika: stage three's boss, cut from the artist's own reference sheet.

**The game's owner drew this one**, which is the whole reason it can ship --
see the note in `make_player.py` about what may and may not. Szuix came in as a
55x45 pixel sheet; Mika comes in as a full-resolution reference sheet with a
legend down one side, so the work here is *extraction* rather than drawing: key
the flat background out, find the figure, scale him to a boss.

**The version this replaced was drawn from primitives and it was wrong four
times over.** The plumes at his sides are a fur mantle from the shoulders, not
tails; he has one tail; he has digitigrade legs and a tabard; and the ring
markings are an interlace that crosses itself rather than a row of separate
links. Every one of those was a reading of the sheet, and every one of them was
a reading the sheet already answered. When the reference exists, use it.

**The animation is a skinned rig.** Szuix's six frames are drawn; there is one
drawing of Mika, so he is given bones and every pixel is displaced by a blend
of what they do -- see "The rig" below, and the two things that came before it
and did not work. It is not a substitute for drawn poses, and the contract it
fills is exactly what a drawn set would: the same ink height as the other boss,
the origin on his body, facing the player.

The extraction is two ideas:

- **The background is keyed on the sheet's own corner pixel.** A tolerance and
  a feather, so the anti-aliased edge comes out as partial alpha rather than as
  a brown fringe -- the premultiplication trap `make_player.py` records,
  arriving from the other direction.
- **The figure is found by flood fill, not by cropping.** The legend runs down
  the left of the sheet and his raised hand reaches back under it, so there is
  no vertical line that separates the two. What does separate them is that he
  is one connected mass and the legend is forty small ones: the fill runs on a
  downscaled mask from a seed in his chest, and the component it reaches is
  him.

Usage:
    python tools/make_mika.py
"""
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

# **Either name, because the sheet arrived under the other one.** A generator
# that refuses a file sitting right beside it over a spelling is a generator
# that wastes somebody's time for nothing.
SOURCE_NAMES = ("mika_ref.png", "mika_sheet.png")

# **How big he is, measured off Ziggy rather than chosen.** Ziggy's sprite is a
# 260x250 box and his *ink* is 198x208: most of a boss sprite is empty margin,
# so matching the box put Mika -- whose cut-out is tight to his outline -- a
# fifth larger than the other boss on the rack, and it was reported that way.
# What has to agree between two characters is how much of the screen each one
# covers, which is the ink. The sheet's own resolution is no guide at all; it is
# a reference page, drawn as large as it needed to be.
H = 208

# **Twelve frames, which is not Ziggy's six.** `boss_draw` holds every frame for
# seven game frames whatever the sprite says, so six is a seven-tenths-of-a-
# second loop -- a wingbeat, and right for him. A hovering mage wants an idle
# nearer a second and a half, and the only way to buy that is more frames.
FRAMES = 12
CARD_W, CARD_H = 1280, 420

# Keying. `KEY_TOL` is how far a pixel may be from the sheet's background
# colour and still count as background; `KEY_SOFT` is the band above it that
# comes out as partial alpha.
KEY_TOL = 26.0
KEY_SOFT = 34.0

# Where to start looking for him, as a fraction of the sheet. It only has to
# land somewhere inside the one large connected mass.
SEED = (0.46, 0.50)

GOLD = (245, 176, 30)


# ---------------------------------------------------------------------------
# Getting him off the sheet
# ---------------------------------------------------------------------------

def source_path():
    for _name in SOURCE_NAMES:
        p = os.path.join(A.ROOT, "tools", "source", _name)
        if os.path.exists(p):
            return p
    return None


def load_sheet():
    src = source_path()
    if src is None:
        raise SystemExit(
            "tools/source/mika_ref.png is missing.\n"
            "\n"
            "This generator does not draw Mika -- it cuts him out of the\n"
            "reference sheet. Save the full-body sheet (the one with the\n"
            "legend down the left) as:\n"
            "\n"
            "    tools/source/mika_ref.png\n"
            "\n"
            "...and run this again. Any resolution will do; he is scaled to\n"
            "%d pixels tall, and the background may be any flat colour."
            % H)
    return Image.open(src).convert("RGBA")


def key_background(img):
    """Alpha from distance to the sheet's own background colour."""
    arr = np.asarray(img, dtype=np.float32)
    bg = arr[0, 0, :3]
    dist = np.sqrt(((arr[..., :3] - bg[None, None, :]) ** 2).sum(axis=2))
    alpha = np.clip((dist - KEY_TOL) / KEY_SOFT, 0.0, 1.0)
    # Anything the sheet already drew as transparent stays that way.
    alpha *= arr[..., 3] / 255.0
    return alpha


def largest_mass(alpha, scale=8):
    """The connected component the seed lands in, as a full-size mask.

    **Run on a downscaled copy.** A flood fill over four million pixels in
    Python is slow enough to notice and the answer does not need that
    resolution: what is being separated is one figure from a column of small
    labels, and at an eighth scale the figure is still hundreds of cells across
    while a letter is three.
    """
    h, w = alpha.shape
    sh, sw = max(1, h // scale), max(1, w // scale)
    small = np.asarray(
        Image.fromarray((alpha * 255).astype(np.uint8), "L")
             .resize((sw, sh), Image.BILINEAR), dtype=np.float32) / 255.0
    solid = small > 0.35

    sy, sx = int(sh * SEED[1]), int(sw * SEED[0])
    if not solid[sy, sx]:
        # Nudge outward until the seed lands on ink, so a sheet whose figure
        # sits a little differently still works.
        best = None
        for y in range(sh):
            for x in range(sw):
                if not solid[y, x]:
                    continue
                d = (y - sy) ** 2 + (x - sx) ** 2
                if best is None or d < best[0]:
                    best = (d, y, x)
        if best is None:
            raise SystemExit("nothing solid found on the sheet to cut out")
        sy, sx = best[1], best[2]

    seen = np.zeros_like(solid)
    seen[sy, sx] = True
    q = deque([(sy, sx)])
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if (0 <= ny < sh and 0 <= nx < sw
                    and solid[ny, nx] and not seen[ny, nx]):
                seen[ny, nx] = True
                q.append((ny, nx))

    # Grown by one cell before it is enlarged, so the eighth-scale boundary
    # does not shave his outline once it is back at full size.
    grown = Image.fromarray((seen * 255).astype(np.uint8), "L") \
                 .filter(ImageFilter.MaxFilter(3)) \
                 .resize((w, h), Image.BILINEAR)
    return np.asarray(grown, dtype=np.float32) / 255.0


def cut_out():
    """The sheet, keyed and masked to the figure, cropped tight."""
    sheet = load_sheet()
    alpha = key_background(sheet)
    alpha = alpha * largest_mass(alpha)

    arr = np.asarray(sheet, dtype=np.float32).copy()
    arr[..., 3] = alpha * 255.0
    cut = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    box = cut.getbbox()
    if box is None:
        raise SystemExit("the cut-out came back empty")
    return cut.crop(box)


def cut_figure(cut):
    """...scaled to the height a boss is drawn at, and given a rim.

    **The rim is not decoration and the sheet cannot supply it.** He is drawn
    for a mid-brown page, where near-black fur reads as a shape; this stage is
    near-black too, and a dark mass with no lit edge is a hole in the picture
    rather than a character in it. Every solid thing in the grove ships as a
    body and a rim for exactly this reason, and Ziggy and Szuix both get one.

    It is cool rather than warm -- his fur is blue-black and the gold on him is
    the only warm thing, so a warm rim would put a second one round his whole
    outline and flatten the one contrast the design has.
    """
    scale = H / cut.height
    small = cut.resize((max(1, int(round(cut.width * scale))), H),
                       Image.LANCZOS)

    solid = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rim = A.rim_light(solid, (118, 112, 158), drop=3, blur=1.4, strength=0.55)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), solid))
    return A.add(small, rim)


def torso_origin(img):
    """Where his hit circle goes, as (x, y) in the sprite.

    **Not the middle of the box.** The tail is nearly half the width of the
    frame, so the box's centre lands somewhere between his hip and the base of
    it -- and the origin is what `enemy_take_shots` measures against, so a
    boss posed that way is one whose hitbox is a body-width to the side of his
    body. `make_player.py` records the same finding about Szuix, whose wings
    put the box's centre above his shoulders.

    His head is found rather than guessed: the ears are the topmost ink, so the
    alpha-weighted mean column of the top slice is the line he stands on.
    """
    a = np.asarray(img.getchannel("A"), dtype=np.float32)
    top = a[:max(1, int(a.shape[0] * 0.16))]
    weight = top.sum(axis=0)
    if weight.sum() <= 0:
        return img.width // 2, img.height // 2
    xs = np.arange(img.width, dtype=np.float32)
    cx = float((xs * weight).sum() / weight.sum())
    # Down from the head to the chest, which is where a shot should land.
    return int(round(cx)), int(round(img.height * 0.40))


# ---------------------------------------------------------------------------
# The rig
#
# **Skinned, not cut into layers, and that is the third attempt.** The first
# ran the whole figure through a travelling horizontal shear -- correctly
# reported as a piece of paper flapping in the wind, because a shear is one
# deformation applied to a body with no joints. The second cut him into parts
# and turned each about its own pivot, which is the textbook answer for a
# single illustration and which produced a new defect every time a boundary
# moved: his head splitting, an ear tip left behind, a shoulder coming away, a
# foot travelling with the cape.
#
# **Every one of those is the same fault, and it is not a misplaced polygon --
# it is the cut itself.** A hard boundary through solid fur shows the moment
# the two sides move differently, and a figure like this has no narrow necks to
# hide one in: his head runs into his ruff, his ruff into his shoulder, his leg
# into his foot. Moving the seam moves the problem.
#
# So there are no layers. Each part is a *bone* -- a region, a pivot and an
# angle -- and every pixel is displaced by the **weighted average** of what
# those bones would do to it, with the weights blending smoothly from one to
# the next. That is skinning, it is what every 2D rig in the industry does with
# artwork it cannot redraw, and its whole point here is that a weighted average
# of two rigid motions is continuous: there is nowhere left for a seam to be.
#
# What it costs is that nothing can pass in front of anything else, so the
# bones have to keep to small angles and none of them may cross. At the four to
# five degrees this idle uses, that is not a constraint anybody would notice.
#
# Three things still make it read as animation rather than as wobble:
#
# - **Every bone lags the one it hangs from.** The head follows the body, the
#   ears follow the head, the tail follows the hips, each by a fraction of a
#   cycle. Follow-through is what separates a rig from a set of independent
#   sine waves and it costs one number per bone.
# - **The pivot is the attachment point.** Turning about a part's middle drags
#   its root about; turning about the root moves the tip, which is what a limb
#   does.
# - **The weights are wide.** A tight falloff is a soft-edged cut and behaves
#   like one; a wide one means the ear's base is half ear and half head, which
#   is what an ear's base actually is.
#
# The regions are authored, because a rig is authored -- and they are far more
# forgiving than a cut was, since a polygon that is a little off now blends
# instead of tearing. `MIKA_RIG_DEBUG=1` draws them over the art, which is the
# only way to check them that has ever worked: read off a grid over the whole
# figure they were wrong every time, because his head is centred at x 0.34 and
# a box that includes a raised hand at one edge and a tail at the other makes
# it look like 0.29.
# ---------------------------------------------------------------------------

# Every polygon and pivot is in **normalised figure coordinates**: 0..1 across
# the tight bounding box of the cut-out, so they survive the sheet being
# re-exported at another size.
BONES = [
    {
        "name": "tail",
        "poly": [(0.660, -0.05), (1.05, -0.05), (1.05, 1.05), (0.700, 1.05),
                 (0.615, 0.88), (0.548, 0.79), (0.515, 0.735),
                 (0.550, 0.68), (0.598, 0.60), (0.640, 0.50),
                 (0.655, 0.32)],
        "pivot": (0.55, 0.74),
        "swing": 4.0,        # degrees either side
        "lag": 0.22,         # of a cycle, behind the body
    },
    {
        "name": "ear_l",
        "poly": [(0.115, 0.120), (0.175, -0.05), (0.255, -0.05),
                 (0.325, 0.075), (0.330, 0.185), (0.270, 0.235),
                 (0.160, 0.220), (0.105, 0.170)],
        "pivot": (0.250, 0.215),
        "swing": 5.0,
        "lag": 0.12,
    },
    {
        # **The other way round.** Two ears turning together are one shape with
        # a notch in it; turning against each other they are two ears.
        "name": "ear_r",
        "poly": [(0.362, 0.130), (0.400, -0.05), (0.470, -0.05),
                 (0.545, 0.050), (0.570, 0.165), (0.520, 0.235),
                 (0.398, 0.225)],
        "pivot": (0.452, 0.218),
        "swing": -5.0,
        "lag": 0.17,
    },
    {
        "name": "arm_l",        # the raised hand, our left
        "poly": [(-0.05, 0.175), (0.070, 0.160), (0.155, 0.245),
                 (0.238, 0.385), (0.215, 0.450), (0.120, 0.425),
                 (-0.05, 0.300)],
        "pivot": (0.215, 0.435),
        "swing": 2.4,
        "lag": 0.15,
    },
    {
        "name": "arm_r",        # the clawed hand, our right
        "poly": [(0.450, 0.295), (0.560, 0.285), (0.655, 0.325),
                 (0.660, 0.435), (0.560, 0.485), (0.450, 0.460)],
        "pivot": (0.468, 0.455),
        "swing": -2.2,
        "lag": 0.19,
    },
    {
        "name": "head",
        "poly": [(0.115, 0.11), (0.245, 0.040), (0.435, 0.040),
                 (0.575, 0.135), (0.605, 0.290), (0.375, 0.345),
                 (0.155, 0.305), (0.095, 0.20)],
        "pivot": (0.340, 0.320),      # the neck
        "swing": 1.5,
        "lag": 0.07,
    },
    {
        # **The fur at each ankle, and both of them on purpose.** An earlier rig
        # had the right-hand one half inside the tail's region, so half of it
        # swung and half did not -- reported as a fault, and then, once it was
        # explained, asked for deliberately on both sides. Drapery is the part
        # of a standing figure that should still be moving after the body has
        # stopped, and two of them lagging by different amounts is most of what
        # sells a heavy coat.
        "name": "hem_l",
        "poly": [(0.075, 0.690), (0.245, 0.665), (0.268, 0.795),
                 (0.235, 0.860), (0.090, 0.870), (0.050, 0.780)],
        "pivot": (0.165, 0.675),
        "swing": 3.6,
        "lag": 0.30,         # drapery lags further behind than a limb does
    },
    {
        "name": "hem_r",
        "poly": [(0.415, 0.745), (0.545, 0.728), (0.638, 0.800),
                 (0.632, 0.900), (0.430, 0.905)],
        "pivot": (0.490, 0.742),
        "swing": -3.2,
        "lag": 0.36,
    },
]

# The body does not turn. It bobs and breathes, and every bone rides that plus
# its own lag -- which is what gives the figure one centre of gravity rather
# than eight.
BODY_BOB = 3.2           # pixels at the final size
BODY_BREATHE = 0.012     # of its own height

# **How far a bone's influence reaches past its own outline**, as a fraction of
# the figure's height. This is the number that makes skinning skinning: at zero
# it is a hard cut with all the tearing that implies, and wide it is a limb
# whose base belongs partly to what it hangs off. Twenty pixels at this size.
RIG_BLEND = 0.045

# Room for a bone to swing into without clipping. The ears sit on the top edge
# of the tight crop.
PAD_FRAC = 0.07

RIG_DEBUG = os.environ.get("MIKA_RIG_DEBUG") == "1"


def _bone_field(poly, size, pad, box, blur_px):
    """One bone's influence, before normalising."""
    w, h = size
    bw, bh = box
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(
        [(pad + x * bw, pad + y * bh) for x, y in poly], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(blur_px))
    return np.asarray(m, dtype=np.float32) / 255.0


def build_rig(figure):
    """Bone weights over the padded figure, normalised so they sum to one.

    **The body is a bone too, and it is the one that does nothing.** Giving it
    a weight rather than treating "no bone" as a special case is what makes the
    blend fall off to *stillness* at the edge of every region instead of to an
    average of whatever else is nearby.
    """
    bw, bh = figure.size
    pad = int(round(bh * PAD_FRAC))
    w, h = bw + pad * 2, bh + pad * 2

    padded = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    padded.alpha_composite(figure, (pad, pad))

    blur = max(1.0, bh * RIG_BLEND)
    raw = [_bone_field(b["poly"], (w, h), pad, (bw, bh), blur) for b in BONES]

    stack = np.stack(raw, axis=0)
    rest = np.clip(1.0 - stack.sum(axis=0), 0.0, 1.0)
    total = stack.sum(axis=0) + rest
    weights = stack / np.maximum(total, 1e-6)

    rig = {
        "size": (w, h), "pad": pad, "box": (bw, bh),
        "img": padded, "weights": weights,
    }

    if RIG_DEBUG:
        dbg = Image.new("RGBA", (w, h), (24, 22, 30, 255))
        dbg.alpha_composite(padded)
        d = ImageDraw.Draw(dbg)
        cols = [(255, 60, 60), (60, 255, 120), (80, 160, 255), (255, 210, 60),
                (230, 90, 240), (60, 255, 240), (255, 140, 40), (200, 200, 255)]
        lw = max(1, h // 200)
        for i, b in enumerate(BONES):
            c = cols[i % len(cols)] + (255,)
            pts = [(pad + x * bw, pad + y * bh) for x, y in b["poly"]]
            d.line(pts + [pts[0]], fill=c, width=lw)
            px = pad + b["pivot"][0] * bw
            py = pad + b["pivot"][1] * bh
            r = lw * 3
            d.ellipse([px - r, py - r, px + r, py + r], fill=c,
                      outline=(0, 0, 0, 255))
        rig["debug"] = dbg

    return rig


def _sample(src, sx, sy):
    """Bilinear lookup of a premultiplied RGBA array at float coordinates."""
    h, w, _ = src.shape
    x0 = np.floor(sx).astype(np.int32)
    y0 = np.floor(sy).astype(np.int32)
    fx = (sx - x0)[..., None]
    fy = (sy - y0)[..., None]

    inside = (sx >= 0) & (sx <= w - 1) & (sy >= 0) & (sy <= h - 1)
    x0c = np.clip(x0, 0, w - 1)
    y0c = np.clip(y0, 0, h - 1)
    x1c = np.clip(x0 + 1, 0, w - 1)
    y1c = np.clip(y0 + 1, 0, h - 1)

    top = src[y0c, x0c] * (1 - fx) + src[y0c, x1c] * fx
    bot = src[y1c, x0c] * (1 - fx) + src[y1c, x1c] * fx
    out = top * (1 - fy) + bot * fy
    return out * inside[..., None]


def pose(rig, phase, blink=0.0):
    """One frame: the whole figure warped by one blended displacement field.

    **One field and one resample.** Every bone contributes what it would do to
    a pixel, weighted; the sum is where that pixel came from. Nothing is cut,
    composited or drawn twice, so there is no seam to place and no ghost to
    avoid -- and the alpha channel comes through at full strength rather than
    losing a few per cent at every boundary, which the layered version did.

    Sampled **premultiplied**, the trap `make_player.py` records: a bilinear
    filter mixes colour without reference to alpha, so a half-covered pixel
    contributes its full colour and every edge haloes.
    """
    w, h = rig["size"]
    bw, bh = rig["box"]
    pad = rig["pad"]

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = np.zeros((h, w), dtype=np.float32)
    dy = np.zeros((h, w), dtype=np.float32)

    for i, bone in enumerate(BONES):
        ang = bone["swing"] * math.sin(2 * math.pi * (phase - bone["lag"]))
        if abs(ang) < 1e-4:
            continue
        th = math.radians(ang)
        ca, sa = math.cos(th), math.sin(th)
        px = pad + bone["pivot"][0] * bw
        py = pad + bone["pivot"][1] * bh
        ox, oy = xs - px, ys - py
        wgt = rig["weights"][i]
        dx += wgt * ((ca * ox - sa * oy) - ox)
        dy += wgt * ((sa * ox + ca * oy) - oy)

    # The whole figure bobs, and breathes from the feet up: a scale about the
    # centre would have him growing out of the floor in both directions, which
    # on a figure that is hovering is the one motion that says "this is an
    # image being resized".
    bob = BODY_BOB * math.sin(2 * math.pi * phase)
    k = 1.0 + BODY_BREATHE * math.sin(2 * math.pi * (phase - 0.25))
    floor = pad + bh
    dy += (ys - floor) * (k - 1.0) + bob

    arr = np.asarray(rig["img"], dtype=np.float32)
    a = arr[..., 3:4] / 255.0
    pre = np.concatenate([arr[..., :3] * a, arr[..., 3:4]], axis=2)

    out = _sample(pre, xs - dx, ys - dy)
    oa = np.maximum(out[..., 3:4], 1.0) / 255.0
    out[..., :3] = np.clip(out[..., :3] / oa, 0, 255)
    frame = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")

    if blink > 0.001:
        frame = close_eyes(frame, blink, pad, (bw, bh))
    return frame

def close_eyes(frame, amount, pad, box):
    """Shut his eyes by `amount`, 0 open to 1 closed.

    **The eyes are found by being blue, every frame, in the posed image.**
    Nothing else on him is -- he is two colours and a pair of eyes -- so this
    needs no authored region and, more usefully, it keeps working after the
    head has been rotated and bobbed, because it is looking at the frame that
    was actually drawn rather than at the drawing it came from.

    **Only the eye's own pixels are painted.** Covering a rectangle would put
    fur over the gold that rings each eye, which at this size is most of what
    makes his face a face; masking to the blue means the lid can only ever
    close over the thing a lid closes over.

    The colour is sampled from the darkest part of the fur just above each eye,
    so the lid is his own brow rather than a constant somebody picked -- and
    picking the dark quartile is what stops it sampling the gold marking that
    sits there.
    """
    arr = np.asarray(frame, dtype=np.float32).copy()
    h, w, _ = arr.shape
    blue = ((arr[..., 2] > 140) & (arr[..., 2] - arr[..., 0] > 60)
            & (arr[..., 2] - arr[..., 1] > 25) & (arr[..., 3] > 128))
    if not blue.any():
        return frame

    ys, xs = np.nonzero(blue)
    mid = (float(xs.min()) + float(xs.max())) * 0.5
    rows = np.arange(h, dtype=np.float32)[:, None]

    for side in (xs < mid, xs >= mid):
        if not side.any():
            continue
        ex0, ex1 = int(xs[side].min()), int(xs[side].max())
        ey0, ey1 = int(ys[side].min()), int(ys[side].max())
        eh = max(1, ey1 - ey0)
        eye = blue & (np.arange(w)[None, :] >= ex0) \
                   & (np.arange(w)[None, :] <= ex1)

        band = arr[max(0, ey0 - int(eh * 1.3)):max(1, ey0), ex0:ex1 + 1, :3]
        if band.size:
            lum = band.reshape(-1, 3).sum(axis=1)
            pick = band.reshape(-1, 3)[lum <= np.percentile(lum, 30)]
            lid_col = pick.mean(axis=0) if len(pick) else np.array([26, 24, 32])
        else:
            lid_col = np.array([26, 24, 32], dtype=np.float32)

        reach = amount * eh * 0.56
        shut = eye & (((rows - ey0) < reach) | ((ey1 - rows) < reach))
        arr[shut, :3] = lid_col

        if amount > 0.9:
            crease = eye & (np.abs(rows - (ey0 + ey1) * 0.5)
                            <= max(1.0, eh * 0.07))
            arr[crease, :3] = lid_col * 0.45

    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# **A blink is three frames and it is not on the beat.** One frame of shut eyes
# is a glitch and five is a doze; three -- half, closed, half -- is what reads
# at eight frames a second. It is placed off the bob's own extremes so the two
# cycles do not land together, which is the difference between a character with
# two habits and a character with one.
BLINK = {8: 0.55, 9: 1.0, 10: 0.5}


# ---------------------------------------------------------------------------
# The eye card
# ---------------------------------------------------------------------------

def head_crop(cut):
    """His head out of the full figure, and where his eyes are in it.

    **Cropping the top third of the figure is not cropping his head**, and the
    first card did exactly that: the tail rises nearly as high as his skull, so
    the top slice of the frame contains a head on the left and a plume on the
    right, and `getbbox` on it returns both. What came back was a card with his
    face pushed into the left third and half the plate empty.

    So the head is found rather than assumed. At the very top of the figure the
    only ink is his ears, so their span is the head's span; the crop is a
    window of that span, widened a little for the ruff.

    **And the eyes are found by being blue.** Nothing else on him is -- he is
    two colours and a pair of eyes -- so the centroid of strongly blue pixels
    is the eye line to a few pixels, which is what the card has to put on its
    own centre line. Placing the head by a fraction of its height instead is a
    number that has to be retuned every time the crop changes, and it was
    wrong the first time.
    """
    a = np.asarray(cut.getchannel("A"), dtype=np.float32)
    h, w = a.shape

    ear_rows = a[:max(1, int(h * 0.07))]
    cols = np.nonzero(ear_rows.sum(axis=0) > 0)[0]
    if len(cols) == 0:
        x0, x1 = 0, w
    else:
        span = cols[-1] - cols[0]
        pad = span * 0.28
        x0 = int(max(0, cols[0] - pad))
        x1 = int(min(w, cols[-1] + pad))

    y1 = int(h * 0.34)
    head = cut.crop((x0, 0, x1, y1))

    arr = np.asarray(head, dtype=np.float32)
    blue = ((arr[..., 2] > 140) & (arr[..., 2] - arr[..., 0] > 60)
            & (arr[..., 2] - arr[..., 1] > 25) & (arr[..., 3] > 128))
    if blue.any():
        ys, xs = np.nonzero(blue)
        eye = (float(xs.mean()), float(ys.mean()))
    else:
        eye = (head.width * 0.5, head.height * 0.62)
    return head, eye


def eye_card(cut):
    """The close-up a spell of his is declared with.

    **A crop of the drawing rather than a second drawing.** Ziggy's card is
    built in card space because his sprite is 260 pixels of primitives and
    scaling that up is mush; Mika's source is a full-resolution sheet, so the
    honest card is his own face at the size it was drawn. The rules are the
    same as Ziggy's: the head runs off all four edges, the eyes are the
    brightest thing in it, and the ground is opaque.
    """
    cx, cy = CARD_W / 2.0, CARD_H / 2.0
    head, eye = head_crop(cut)

    scale = (CARD_H * 1.75) / head.height
    head = head.resize((max(1, int(head.width * scale)),
                        max(1, int(head.height * scale))), Image.LANCZOS)
    eye = (eye[0] * scale, eye[1] * scale)

    # **The ground and the ornament on it are two layers, because PIL does not
    # blend.** `ImageDraw` on an RGBA image *replaces* the pixel it writes, so
    # a ring drawn straight onto the plate at low alpha punches a nearly
    # transparent stroke through it, and the card comes back with a white line
    # wherever a gold one was meant to be. Which is what the first one did.
    ground = A.Canvas(CARD_W, CARD_H, ss=2)
    ground.rect([0, 0, CARD_W, CARD_H], fill=A.rgba((7, 6, 11), 255))
    for i in range(30):
        t = 1.0 - i / 29.0
        r = CARD_H * (0.20 + 1.7 * t)
        ground.ellipse([cx - r * 2.2, cy - r, cx + r * 2.2, cy + r],
                       fill=A.rgba(A.mix((7, 6, 11), (34, 26, 12), 1 - t),
                                   255))

    # Concentric rings rather than rays, because he is the ring caster and the
    # card is the one place his motif can be the whole composition.
    deco = A.Canvas(CARD_W, CARD_H, ss=2)
    for i in range(24):
        a = math.radians(i * 15 + 7)
        r0, r1 = CARD_H * 0.30, CARD_H * 2.2
        wide = CARD_H * 0.030
        deco.polygon([(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
                      (cx + math.cos(a) * r1 - math.sin(a) * wide,
                       cy + math.sin(a) * r1 + math.cos(a) * wide),
                      (cx + math.cos(a) * r1 + math.sin(a) * wide,
                       cy + math.sin(a) * r1 - math.cos(a) * wide)],
                     fill=A.rgba(GOLD, 60))
    for i in range(9):
        r = CARD_H * (0.30 + i * 0.30)
        deco.ellipse([cx - r * 1.5, cy - r, cx + r * 1.5, cy + r],
                     outline=A.rgba(GOLD, 150),
                     width=max(1, int(CARD_H * 0.008)))

    out = ground.finish()
    out.alpha_composite(deco.finish())
    # **Placed by his eyes, not by his box.** The card's centre line is what
    # the banner and the timer are laid out round, so that is where the eyes
    # go -- and it is the one landmark that stays put however the crop moves.
    out.alpha_composite(head, (int(cx - eye[0]), int(cy - eye[1])))

    ys, xs = np.mgrid[0:CARD_H, 0:CARD_W].astype(np.float32)
    edge = np.minimum(np.minimum(xs, CARD_W - 1 - xs) / (CARD_W * 0.13),
                      np.minimum(ys, CARD_H - 1 - ys) / (CARD_H * 0.16))
    fade = np.clip(edge, 0, 1) ** 0.9
    arr = np.asarray(out, dtype=np.float32)
    arr[..., 3] *= fade
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def write_gif(frames, path, scale=2, ground=(28, 20, 48)):
    """The idle as a shareable loop.

    **Composited onto an opaque ground rather than shipped transparent.** GIF
    has one bit of alpha, so a figure whose whole outline is a soft rim comes
    out with a ragged fringe -- and the ground it is meant to be seen against
    is dark anyway, so laying it on the console's own indigo is both truer to
    the game and the thing that makes the format work.

    **One palette for every frame, built from all of them.** Quantising each
    frame on its own gives each a slightly different 256 colours, and what that
    looks like is the whole image shimmering between frames -- a defect
    introduced entirely by the export, on art that has none. No dithering
    either: his flats stay flat, which also makes the file a third of the size.

    The frame time is `boss_draw`'s own: it holds every frame for seven game
    frames at 60Hz, which is 116.7ms. **GIF stores hundredths and PIL floors
    rather than rounds**, so asking for 117 writes 110 -- six per cent fast --
    and asking for 120 writes 120, which is three per cent slow and the nearest
    the format can get. Neither is visible; the point is knowing which way it
    went rather than assuming the number asked for is the number stored.
    """
    shots = []
    for f in frames:
        bg = Image.new("RGBA", f.size, tuple(ground) + (255,))
        bg.alpha_composite(f)
        rgb = bg.convert("RGB")
        if scale != 1:
            rgb = rgb.resize((rgb.width * scale, rgb.height * scale),
                             Image.LANCZOS)
        shots.append(rgb)

    w, h = shots[0].size
    montage = Image.new("RGB", (w * len(shots), h))
    for i, im in enumerate(shots):
        montage.paste(im, (i * w, 0))
    palette = montage.quantize(colors=255, method=Image.MEDIANCUT)

    out = [im.quantize(palette=palette, dither=Image.Dither.NONE)
           for im in shots]
    out[0].save(path, save_all=True, append_images=out[1:],
                duration=120, loop=0, optimize=True)
    return out[0].size


def main():
    gm_new.folder("Sprites/boss")

    cut = cut_out()
    figure = cut_figure(cut)
    rig = build_rig(figure)
    frames = [pose(rig, i / FRAMES, BLINK.get(i, 0.0))
              for i in range(FRAMES)]
    origin = torso_origin(frames[0])
    gm_new.sprite("spr_boss_mika", frames, origin=origin,
                  folder="Sprites/boss", fps=8.0)

    if RIG_DEBUG:
        rig["debug"].save(os.path.join(A.PREVIEW, "mika_rig.png"))

    card = eye_card(cut)
    gm_new.sprite("spr_eye_mika", [card], origin="center",
                  folder="Sprites/boss")

    A.preview(frames, os.path.join(A.PREVIEW, "boss_mika.png"), cols=6,
              bg=(18, 16, 22))
    gif = write_gif(frames, os.path.join(A.PREVIEW, "mika_idle.gif"))
    card.save(os.path.join(A.PREVIEW, "eye_mika.png"))
    print("mika: %d rigged frames of %dx%d cut from the sheet, "
          "origin %d,%d, eye card %dx%d, loop %dx%d"
          % (len(frames), frames[0].width, frames[0].height,
             origin[0], origin[1], card.width, card.height, gif[0], gif[1]))


if __name__ == "__main__":
    main()
