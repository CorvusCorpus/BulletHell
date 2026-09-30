#!/usr/bin/env python3
"""Mika, stage three's boss, cut out of the owner's own reference sheet, plus
his spell cut-in portrait and an idle GIF.

The source is `tools/source/mika_ref.png` (the owner's drawing; reproduce it
faithfully). The work is extraction: key out the flat background, find the
figure, scale it, add a rim light, and animate it with a skinned rig (see
"The rig"). The sprite keeps the boss contract: the same ink height as
Ziggy, the origin on his body, facing the player.

Extraction:

- The background is keyed on the sheet's corner pixel, with a tolerance and
  a feathered band so edges come out as partial alpha.
- The figure is found by flood fill from a seed in his chest (on a
  downscaled mask), not by cropping: the legend down the left of the sheet
  overlaps his raised hand horizontally, but he is one connected mass and
  the legend is many small ones.

Usage:
    python tools/make_mika.py
"""
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import ConvexHull

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

# The sheet is accepted under either name.
SOURCE_NAMES = ("mika_ref.png", "mika_sheet.png")

# His height in pixels, matched to Ziggy's ink height (208; Ziggy's sprite box
# is 260x250 but his ink is 198x208), so both bosses cover the same screen
# area.
H = 208

# Twelve frames: `boss_draw` holds each frame for seven game frames, so this
# is an idle loop of about 1.4 seconds.
FRAMES = 12

# The spell cut-in's portrait (`scripts/spell_cutin`): his face from the
# sheet, scaled by `CUTIN_SCALE` game pixels per sheet pixel. Its centre (the
# origin) sits on the band's centre line, `CUTIN_LIFT` sheet pixels above the
# midpoint of his eyes, so the band shows his forehead ring down to his nose.
# It is larger than the band so the band can slide and zoom over it.
CUTIN_W, CUTIN_H = 1500, 640
CUTIN_SCALE = 1.22
CUTIN_LIFT = 40

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
    """The connected component the seed lands in, as a full-size mask. Run on a
    downscaled copy for speed.
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


def keyed_sheet():
    """The whole sheet as a float array, its alpha keyed and masked to the
    figure (not cropped, so it keeps the sheet's coordinates), and the
    background colour that was keyed out."""
    sheet = load_sheet()
    alpha = key_background(sheet)
    alpha = alpha * largest_mass(alpha)

    arr = np.asarray(sheet, dtype=np.float32).copy()
    arr[..., 3] = alpha * 255.0
    return arr, arr[0, 0, :3].copy()


def cut_out():
    """The sheet, keyed and masked to the figure, cropped tight."""
    arr, _ = keyed_sheet()
    cut = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    box = cut.getbbox()
    if box is None:
        raise SystemExit("the cut-out came back empty")
    return cut.crop(box)


def cut_figure(cut):
    """Scale the cut-out to boss height and add a cool rim light (the sheet was
    drawn for a mid-brown page; his near-black fur needs a lit edge against
    this stage's dark background).
    """
    scale = H / cut.height
    small = cut.resize((max(1, int(round(cut.width * scale))), H),
                       Image.LANCZOS)

    solid = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rim = A.rim_light(solid, (118, 112, 158), drop=3, blur=1.4, strength=0.55)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), solid))
    return A.add(small, rim)


def torso_origin(img):
    """Where his origin (hit circle) goes, as (x, y) in the sprite. Not the
    box's centre, which his tail pulls sideways: the column is the
    alpha-weighted mean of the top slice (his ears, over his head), and the
    height is 40% down (his chest).
    """
    a = np.asarray(img.getchannel("A"), dtype=np.float32)
    top = a[:max(1, int(a.shape[0] * 0.16))]
    weight = top.sum(axis=0)
    if weight.sum() <= 0:
        return img.width // 2, img.height // 2
    xs = np.arange(img.width, dtype=np.float32)
    cx = float((xs * weight).sum() / weight.sum())
    # Down from the head to the chest.
    return int(round(cx)), int(round(img.height * 0.40))


# ---------------------------------------------------------------------------
# The rig
#
# Skinned: each part is a bone (a region, a pivot and a swing angle), and
# every pixel is displaced by the weighted average of what the bones would do
# to it, with the weights blending smoothly between regions. A weighted
# average of rigid motions is continuous, so there are no seams. (Cutting him
# into separately rotated layers tore at every boundary, because his parts
# run into each other with no narrow necks to hide a cut.) The cost is that
# nothing can pass in front of anything else, so the swings stay small.
#
# - Each bone lags the body by a fraction of a cycle (`lag`), for
#   follow-through.
# - Each bone pivots about its attachment point.
# - The weights blend over a wide band (`RIG_BLEND`).
#
# `MIKA_RIG_DEBUG=1` draws the regions and pivots over the art; use it to
# check them.
# ---------------------------------------------------------------------------

# Polygons and pivots are in normalised figure coordinates: 0..1 across the
# tight bounding box of the cut-out.
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
        # The other way round from the left ear, so the ears move apart.
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
        # The fur at each ankle; the owner asked for both hems to swing
        # (lagging more than a limb does).
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

# The body doesn't turn: it bobs and breathes, and every bone rides that plus
# its own lag.
BODY_BOB = 3.2           # pixels at the final size
BODY_BREATHE = 0.012     # of its own height

# How far a bone's influence reaches past its outline, as a fraction of the
# figure's height (0 would be a hard cut).
RIG_BLEND = 0.045

# Padding for bones to swing into (the ears touch the top of the crop).
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
    """Bone weights over the padded figure, normalised to sum to one. The body
    is a bone that doesn't move, so the blend falls off to stillness outside
    every region.
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
    """One frame: the figure warped by a single blended displacement field and
    resampled once (nothing is cut or composited). Sampled premultiplied, so
    edges don't halo.
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

    # The whole figure bobs, and breathes as a scale about the feet.
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
    """Shut his eyes by `amount` (0 open, 1 closed). The eyes are found in the
    posed frame by being blue (nothing else on him is), and only those pixels
    are painted, in a colour sampled from the dark fur just above each eye.
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


# A blink over three frames (half, closed, half), placed away from the bob's
# extremes.
BLINK = {8: 0.55, 9: 1.0, 10: 0.5}


# ---------------------------------------------------------------------------
# The spell cut-in
#
# Two frames of his face for `scripts/spell_cutin`: frame 0 with his eyes shut,
# frame 1 as the sheet draws him. The cut-in snaps from one to the other, as
# anime does, so a commissioned pair can replace these one for one. Each
# frame is transparent round his head, where the band's own ground shows.
# ---------------------------------------------------------------------------

LID_INK = (14, 10, 18)       # the sheet's line work


def find_eyes(arr):
    """His two eyes on the keyed sheet, left one first: each the connected
    mass of strongly blue pixels (nothing else on him is blue, and the
    legend's swatch is keyed away with the page). Each is `{box, mask, c}`:
    its bounding box, its pixels inside that box, and its centre."""
    blue = ((arr[..., 2] > 140) & (arr[..., 2] - arr[..., 0] > 60)
            & (arr[..., 2] - arr[..., 1] > 25) & (arr[..., 3] > 128))
    lab, n = ndimage.label(blue)
    if n < 2:
        raise SystemExit("couldn't find both of his eyes on the sheet")
    sizes = ndimage.sum(blue, lab, range(1, n + 1))
    eyes = []
    for sl, i in ((ndimage.find_objects(lab)[k], k + 1)
                  for k in np.argsort(sizes)[::-1][:2]):
        m = lab[sl] == i
        ys, xs = np.nonzero(m)
        eyes.append({
            "box": (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop),
            "mask": m,
            "c": (sl[1].start + xs.mean(), sl[0].start + ys.mean()),
        })
    eyes.sort(key=lambda e: e["c"][0])
    return eyes


def eye_glow_colour(arr, eyes):
    """The blue his eyes glow: the mean of their brightest pixels."""
    px = []
    for e in eyes:
        x0, y0, x1, y1 = e["box"]
        px.append(arr[y0:y1, x0:x1, :3][e["mask"]])
    px = np.concatenate(px)
    lum = px.sum(axis=1)
    return tuple(int(v) for v in px[lum >= np.percentile(lum, 75)].mean(0))


def shut_eye(arr, eye, outer_left, glow):
    """Paint one eye shut, in place.

    The eye, the line round it and the blue haze it throws are painted over
    with fur: a plane fitted to the fur round the eye (gold and line work left
    out of the fit), feathered in. The closed lid is then one bold tapered
    line low across the eye, heaviest toward the outer corner and flicking up
    past it. His fur is nearly as dark as the line, so the lid's fold is lit
    above it and a thread of his eyes' glow shows in the seam under it.
    `outer_left` says which end is the outer corner.
    """
    pad = 34
    x0, y0, x1, y1 = eye["box"]
    patch = arr[y0 - pad:y1 + pad, x0 - pad:x1 + pad]
    rgb = patch[..., :3]
    ph, pw = rgb.shape[:2]

    # The eye's whole almond: the convex hull of its blue, since the slit
    # pupil isn't blue and opens onto the rim.
    ey, ex = np.nonzero(eye["mask"])
    hull = ConvexHull(np.stack([ex, ey], 1))
    ss = 4
    hm = Image.new("L", (pw * ss, ph * ss), 0)
    ImageDraw.Draw(hm).polygon(
        [((ex[v] + pad + 0.5) * ss, (ey[v] + pad + 0.5) * ss)
         for v in hull.vertices], fill=255)
    em = np.asarray(hm.resize((pw, ph), Image.BOX)) > 127

    # Gold, and the warm edge where gold is anti-aliased into the fur.
    gold = rgb[..., 0] - rgb[..., 2] > 22
    lum = rgb.mean(axis=2)
    bluish = rgb[..., 2] - rgb[..., 0] > 14
    # Everything near the eye but gold: the line round it is thick under the
    # markings, and a remnant of it outlines the almond again.
    region = ((ndimage.binary_dilation(em, iterations=12)
               | (ndimage.binary_dilation(em, iterations=18) & bluish))
              & ~gold)
    feather = np.clip(ndimage.distance_transform_edt(region) / 3.0, 0, 1)

    ring = (ndimage.binary_dilation(region, iterations=10) & ~region & ~gold
            & ~bluish & (lum >= 16) & (lum < 70))
    ry, rx = np.nonzero(ring)
    basis = np.stack([rx, ry, np.ones_like(rx)], 1).astype(np.float32)
    coef = np.linalg.lstsq(basis, rgb[ring], rcond=None)[0]
    gy, gx = np.mgrid[0:ph, 0:pw].astype(np.float32)
    fur = gx[..., None] * coef[0] + gy[..., None] * coef[1] + coef[2]
    # A little grain, or the patch is smoother than the painted fur round it.
    rnd = np.random.default_rng(int(x0))
    fur += (ndimage.gaussian_filter(rnd.normal(0, 1, (ph, pw)), 1.3)
            * 3.0)[..., None]
    rgb[...] = rgb * (1 - feather[..., None]) + fur * feather[..., None]

    # The lid line: a smooth curve across the middle of the eye, a little
    # nearer its lower rim, corner to corner.
    ys, xs = np.nonzero(em)
    cols = np.arange(xs.min(), xs.max() + 1).astype(np.float32)
    top = np.array([ys[xs == c].min() for c in cols.astype(int)], np.float32)
    bot = np.array([ys[xs == c].max() for c in cols.astype(int)], np.float32)
    line_y = np.polyval(np.polyfit(cols, bot - 0.40 * (bot - top), 2), cols)
    pts = np.stack([cols, line_y], 1)
    u = np.linspace(0.0, 1.0, len(cols))
    along = u if outer_left else 1 - u          # 0 at the outer corner
    w = 1.6 + 8.5 * np.sin(np.pi * along) ** 0.65 * (1.0 - 0.4 * along)

    d = np.gradient(pts, axis=0)
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    stroke = [tuple(p) for p in pts + nrm * (w / 2)[:, None]] +              [tuple(p) for p in (pts - nrm * (w / 2)[:, None])[::-1]]

    # The flick: on past the outer corner, turning upward, tapering out.
    k = 0 if outer_left else len(pts) - 1
    end = pts[k]
    back = pts[min(len(pts) - 1, max(0, k + (10 if outer_left else -10)))]
    fd = (end - back) / max(np.linalg.norm(end - back), 1e-6)
    fd = fd + np.array([0.0, -0.6])
    fd /= np.linalg.norm(fd)
    fn = np.array([-fd[1], fd[0]])
    flick = [tuple(end + fn * 2.0), tuple(end - fn * 2.0),
             tuple(end + fd * 26.0)]

    m = Image.new("L", (pw * ss, ph * ss), 0)
    dr = ImageDraw.Draw(m)
    for poly in (stroke, flick):
        dr.polygon([(x * ss, y * ss) for x, y in poly], fill=255)
    line = np.asarray(m.resize((pw, ph), Image.BOX), np.float32) / 255.0

    def shifted(a, dy):
        return ndimage.shift(a, (dy, 0.0), order=1)

    fold = np.clip(ndimage.gaussian_filter(shifted(line, -5.0), 2.5) - line,
                   0, 1) * 0.55 * feather
    # The glow is strongest mid-eye and gone at the corners.
    across = np.zeros(pw, np.float32)
    ci = cols.astype(int)
    across[ci] = np.sin(np.pi * u) ** 0.8
    seam = np.clip(shifted(line, 1.8) - line, 0, 1) * across[None, :]
    halo = ndimage.gaussian_filter(seam, 3.5) * 0.45
    lit = np.asarray(fur.mean(axis=(0, 1)), np.float32) + (38, 36, 54)
    hot = np.asarray(glow, np.float32)
    thread = hot + (255 - hot) * 0.35

    def over(col, a):
        rgb[...] = rgb * (1 - a[..., None]) + np.asarray(col) * a[..., None]

    over(lit, fold)
    rgb[...] = rgb + hot * halo[..., None]
    over(np.array(LID_INK, np.float32), line)
    rgb[...] = rgb + thread * (seam * 0.8)[..., None]
    np.clip(rgb, 0, 255, out=rgb)


def clean_edge(arr, bg):
    """Take the page's colour out of his outline. The key gives full alpha to
    anything much darker than the page, so the outline's anti-aliasing comes
    out brown. There the foreground is always his black line work, so each
    pixel near the edge is re-matted as a mix of line and page."""
    a = arr[..., 3] / 255.0
    near = (ndimage.binary_dilation(a < 0.5, iterations=4) & (a > 0.0))
    ink = np.array(LID_INK, np.float32)
    axis = ink - bg
    c = arr[..., :3] - bg[None, None, :]
    t = (c @ axis) / float(axis @ axis)
    off = np.linalg.norm(c - t[..., None] * axis[None, None, :], axis=2)
    # His fur lies on the same line, most of the way to the ink, so only
    # pixels clearly paler than it are re-matted.
    fix = near & (off < 48) & (t < 0.8)
    arr[..., 3] = np.where(fix, np.clip(t / 0.8, 0, 1) * 255.0, arr[..., 3])
    arr[..., :3] = np.where(fix[..., None], ink[None, None, :], arr[..., :3])


def cutin_frames(arr, bg):
    """The two frames, eyes shut then open, and his eyes measured in the
    frame: `(frames, eyes, glow)` where each eye is `(x, y, rx, ry)` from the
    frame's centre in game pixels."""
    eyes = find_eyes(arr)
    mx = (eyes[0]["c"][0] + eyes[1]["c"][0]) * 0.5
    my = (eyes[0]["c"][1] + eyes[1]["c"][1]) * 0.5
    ax, ay = mx, my - CUTIN_LIFT
    hw, hh = CUTIN_W / CUTIN_SCALE * 0.5, CUTIN_H / CUTIN_SCALE * 0.5
    x0, y0 = int(math.floor(ax - hw)) - 2, int(math.floor(ay - hh)) - 2
    x1, y1 = int(math.ceil(ax + hw)) + 2, int(math.ceil(ay + hh)) + 2
    box = (ax - hw - x0, ay - hh - y0, ax + hw - x0, ay + hh - y0)

    glow = eye_glow_colour(arr, eyes)
    open_ = arr[y0:y1, x0:x1].copy()
    clean_edge(open_, bg)
    shut = open_.copy()
    for k, e in enumerate(eyes):
        ex0, ey0, ex1, ey1 = e["box"]
        local = dict(e, box=(ex0 - x0, ey0 - y0, ex1 - x0, ey1 - y0))
        shut_eye(shut, local, (k == 0), glow)

    frames = []
    for src in (shut, open_):
        a = src[..., 3:4] / 255.0
        pre = np.concatenate([src[..., :3] * a, src[..., 3:4]], axis=2)
        chans = [Image.fromarray(pre[..., i].astype(np.float32), "F")
                 .resize((CUTIN_W, CUTIN_H), Image.LANCZOS, box=box)
                 for i in range(4)]
        out = np.stack([np.asarray(c, np.float32) for c in chans], axis=2)
        oa = np.clip(out[..., 3:4], 0, 255)
        out[..., :3] = np.clip(out[..., :3] / np.maximum(oa, 1.0) * 255.0,
                               0, 255)
        out[..., 3:4] = oa
        frames.append(Image.fromarray(out.astype(np.uint8), "RGBA"))

    measured = []
    for e in eyes:
        ex0, ey0, ex1, ey1 = e["box"]
        measured.append(((e["c"][0] - ax) * CUTIN_SCALE,
                         (e["c"][1] - ay) * CUTIN_SCALE,
                         (ex1 - ex0) * 0.5 * CUTIN_SCALE,
                         (ey1 - ey0) * 0.5 * CUTIN_SCALE))
    return frames, measured, glow


CUTIN_TABLE = """/// @desc The spell cut-in's portraits -- GENERATED by tools/make_mika.py. Do
///       not edit: these are measured from the art.
///
/// `cutin_art(_spr)`: where a portrait's eyes are, for the light the cut-in
/// puts on them as they open. Each eye is `[x, y, rx, ry]`: its centre in
/// pixels from the sprite's origin, and its half-width and half-height.
/// `glow` is the colour they shine.

function cutin_art(_spr) {
    if (_spr == spr_cutin_mika) {
        return {
            eyes: [%s],
            glow: %s,
        };
    }
    return { eyes: [], glow: c_white };
}
"""


def write_cutin_table(eyes, glow):
    rows = ", ".join("[%d, %d, %d, %d]" % tuple(int(round(v)) for v in e)
                     for e in eyes)
    path = os.path.join(A.ROOT, "scripts", "cutin_table", "cutin_table.gml")
    gm_new.script("cutin_table", CUTIN_TABLE % (rows, A.gm_hex(glow)),
                  folder="Scripts/ui")
    return path


def write_gif(frames, path, scale=2, ground=(28, 20, 48)):
    """The idle as a shareable GIF: composited onto an opaque ground (GIF has
    1-bit alpha), one shared palette for all frames (per-frame palettes
    shimmer), no dithering. The frame time is 120ms (`boss_draw` holds frames
    for 116.7ms; GIF stores hundredths and PIL floors, so 117 would become
    110).
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

    sheet, bg = keyed_sheet()
    cutin, eyes, glow = cutin_frames(sheet, bg)
    gm_new.sprite("spr_cutin_mika", cutin, origin="center",
                  folder="Sprites/boss")
    write_cutin_table(eyes, glow)

    A.preview(frames, os.path.join(A.PREVIEW, "boss_mika.png"), cols=6,
              bg=(18, 16, 22))
    gif = write_gif(frames, os.path.join(A.PREVIEW, "mika_idle.gif"))
    A.preview(cutin, os.path.join(A.PREVIEW, "cutin_mika.png"), cols=1,
              bg=(40, 22, 58), labels=["eyes shut", "eyes open"])
    print("mika: %d rigged frames of %dx%d cut from the sheet, "
          "origin %d,%d, loop %dx%d; cut-in %dx%d, eyes %s"
          % (len(frames), frames[0].width, frames[0].height,
             origin[0], origin[1], gif[0], gif[1], cutin[0].width,
             cutin[0].height, [tuple(int(v) for v in e) for e in eyes]))


if __name__ == "__main__":
    main()
