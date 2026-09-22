#!/usr/bin/env python3
"""Mika, stage three's boss, cut out of the owner's own reference sheet, plus
his eye card and an idle GIF.

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
# The eye card
# ---------------------------------------------------------------------------

def head_crop(cut):
    """His head from the full figure, and where his eyes are in it. The head's
    horizontal span is taken from the ears (the topmost ink; a plain top slice
    also catches the tail), and the eye line is the centroid of the strongly
    blue pixels.
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
    """His eye card: a crop of his own face at the resolution it was drawn,
    centred on his eyes, over a dark ground with gold rays and rings, fading at
    the edges.
    """
    cx, cy = CARD_W / 2.0, CARD_H / 2.0
    head, eye = head_crop(cut)

    scale = (CARD_H * 1.75) / head.height
    head = head.resize((max(1, int(head.width * scale)),
                        max(1, int(head.height * scale))), Image.LANCZOS)
    eye = (eye[0] * scale, eye[1] * scale)

    # The ground and its ornament are separate layers, then composited:
    # `ImageDraw` on RGBA replaces pixels rather than blending, so drawing
    # translucent rings directly on the ground would punch holes in it.
    ground = A.Canvas(CARD_W, CARD_H, ss=2)
    ground.rect([0, 0, CARD_W, CARD_H], fill=A.rgba((7, 6, 11), 255))
    for i in range(30):
        t = 1.0 - i / 29.0
        r = CARD_H * (0.20 + 1.7 * t)
        ground.ellipse([cx - r * 2.2, cy - r, cx + r * 2.2, cy + r],
                       fill=A.rgba(A.mix((7, 6, 11), (34, 26, 12), 1 - t),
                                   255))

    # Rays and concentric rings (his ring motif).
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
    # Placed so his eyes are at the card's centre.
    out.alpha_composite(head, (int(cx - eye[0]), int(cy - eye[1])))

    ys, xs = np.mgrid[0:CARD_H, 0:CARD_W].astype(np.float32)
    edge = np.minimum(np.minimum(xs, CARD_W - 1 - xs) / (CARD_W * 0.13),
                      np.minimum(ys, CARD_H - 1 - ys) / (CARD_H * 0.16))
    fade = np.clip(edge, 0, 1) ** 0.9
    arr = np.asarray(out, dtype=np.float32)
    arr[..., 3] *= fade
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


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
