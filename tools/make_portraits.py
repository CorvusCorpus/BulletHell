#!/usr/bin/env python3
"""The standing portraits a conversation is played with (`talk_functions`):
Szuix and Mika, cut out of the owner's own drawings.

Both are PLACEHOLDERS: one drawing each, where a finished portrait would have
a pose per expression. A replacement keeps the contract below and nothing
else has to change.

- Szuix is `tools/source/szuix_ref.png` (the owner's drawing, on a painted
  wall). The wall is keyed by colour: it is the only dark purple on the
  page, and his line work is black, so each edge pixel is re-matted as a mix
  of line and wall.
- Mika is the same sheet his sprite is cut from (`make_mika.py`, whose
  keying this borrows).

The contract: a sprite of two frames, as drawn and with the eyes shut (the
blink), transparent round the figure, its origin midway between the eyes.
The figure runs down to about the knee and fades out there; a conversation
stands it behind its plate, which hides the fade. `scripts/talk_table` says
where the eyes are.

Usage:
    python tools/make_portraits.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import ConvexHull

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new
import make_mika as M

FOLDER = "Sprites/talk"

# Game pixels per source pixel. Chosen so the two faces are about one size
# on screen (his sheet is much larger than Szuix's page).
SZUIX_SCALE = 0.68
MIKA_SCALE = 0.30

# How far down each source the portrait runs (source rows), and the height
# (game pixels) its foot fades out over.
SZUIX_FOOT = 1570
MIKA_FOOT = 4700
FOOT_FADE = 70

# The colour a conversation lights each speaker in: their blade, their rim
# and their end of the plate. Szuix's is brighter than his skin, so his rim
# shows against it; Mika's is the gold of his markings.
SZUIX_TINT = (84, 150, 255)
MIKA_TINT = (255, 186, 40)

LINE_INK = (4, 4, 8)


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

def resample(arr, scale):
    """A float RGBA array scaled by `scale`, filtered premultiplied so the
    transparent ground's colour never bleeds into an edge."""
    h, w = arr.shape[:2]
    size = (max(1, int(round(w * scale))), max(1, int(round(h * scale))))
    a = arr[..., 3:4] / 255.0
    pre = np.concatenate([arr[..., :3] * a, arr[..., 3:4]], axis=2)
    chans = [Image.fromarray(np.ascontiguousarray(pre[..., i], np.float32), "F")
             .resize(size, Image.LANCZOS) for i in range(4)]
    out = np.stack([np.asarray(c, np.float32) for c in chans], axis=2)
    oa = np.clip(out[..., 3:4], 0, 255)
    out[..., :3] = np.clip(out[..., :3] / np.maximum(oa, 1.0) * 255.0, 0, 255)
    out[..., 3:4] = oa
    return out


def fade_foot(arr):
    """Fade the last `FOOT_FADE` rows out, so the figure has no cut edge."""
    h = arr.shape[0]
    rows = np.arange(h, dtype=np.float32)
    k = np.clip((h - 1 - rows) / float(FOOT_FADE), 0.0, 1.0)
    arr[..., 3] *= (k * k * (3 - 2 * k))[:, None]
    return arr


def finish(frames, anchor, scale):
    """Scale a list of same-sized float RGBA frames, fade their feet and trim
    them to the figure. Returns `(images, origin)`, the origin being `anchor`
    (source pixels) in the trimmed sprite."""
    small = [fade_foot(resample(f, scale)) for f in frames]
    solid = np.max([s[..., 3] for s in small], axis=0) > 3
    ys, xs = np.nonzero(solid)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    images = [Image.fromarray(np.clip(s[y0:y1, x0:x1], 0, 255)
                              .astype(np.uint8), "RGBA") for s in small]
    origin = (int(round(anchor[0] * scale - x0)),
              int(round(anchor[1] * scale - y0)))
    return images, origin


def eye_rows(eyes, anchor, scale):
    """Each eye as `(x, y, rx, ry)` in game pixels from the origin."""
    out = []
    for e in eyes:
        x0, y0, x1, y1 = e["box"]
        out.append(((e["c"][0] - anchor[0]) * scale,
                    (e["c"][1] - anchor[1]) * scale,
                    (x1 - x0) * 0.5 * scale, (y1 - y0) * 0.5 * scale))
    return out


def midpoint(eyes):
    return ((eyes[0]["c"][0] + eyes[1]["c"][0]) * 0.5,
            (eyes[0]["c"][1] + eyes[1]["c"][1]) * 0.5)


# ---------------------------------------------------------------------------
# Szuix
# ---------------------------------------------------------------------------

def szuix_cut():
    """His page as a float RGBA array with the wall keyed out, down to
    `SZUIX_FOOT` (above the floor he stands on, which is not keyed)."""
    path = os.path.join(A.ROOT, "tools", "source", "szuix_ref.png")
    if not os.path.exists(path):
        raise SystemExit("tools/source/szuix_ref.png is missing: the owner's "
                         "drawing of Szuix this cuts his portrait from")
    a = np.asarray(Image.open(path).convert("RGB"), np.float32)[:SZUIX_FOOT]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]

    # The wall: dark, and redder than it is green. His darks are blue-black
    # (hair, horns, kilt) and his line work is black.
    wall = ((r - g >= 5) & (g <= 24) & (b >= 24) & (b <= 84) & (r <= 64)
            & (b - r >= 6))
    # Specks of the same colour inside him (a shaded fold of wing) are his.
    lab, n = ndimage.label(wall)
    big = np.zeros(n + 1, bool)
    big[1:] = ndimage.sum(wall, lab, range(1, n + 1)) >= 900
    wall = big[lab]
    lab, n = ndimage.label(~wall)
    fig = lab == (1 + int(np.argmax(ndimage.sum(~wall, lab, range(1, n + 1)))))

    # The wall's colour everywhere, from the wall itself.
    w = wall.astype(np.float32)
    near = np.stack([ndimage.gaussian_filter(a[..., i] * w, 12)
                     for i in range(3)], 2)
    near /= np.maximum(ndimage.gaussian_filter(w, 12), 1e-3)[..., None]

    # In a band round his outline every pixel is line over wall: its alpha is
    # how far it is from the wall's colour toward black, and its colour the
    # line's.
    d_in = ndimage.distance_transform_edt(fig)
    d_out = ndimage.distance_transform_edt(~fig)
    band = ((d_in <= 2.5) & fig) | ((d_out <= 2.5) & ~fig)
    t = (a * near).sum(2) / np.maximum((near * near).sum(2), 1.0)
    off = np.linalg.norm(a - t[..., None] * near, axis=2)
    mixed = band & (off < 14) & (t < 1.15)

    alpha = fig.astype(np.float32)
    alpha = np.where(mixed, np.clip(1.0 - t, 0, 1), alpha)
    alpha = np.where(~fig & (d_out > 2.5), 0.0, alpha)
    rgb = a.copy()
    rgb[mixed] = LINE_INK
    return np.dstack([rgb, alpha * 255.0])


def szuix_eyes(arr):
    """His two eyes, left first: the masses of pale cyan (nothing else on him
    is). Each is `{box, mask, c}` as `make_mika.find_eyes` gives."""
    pale = (arr[..., 1] > 150) & (arr[..., 2] > 200) & (arr[..., 3] > 128)
    lab, n = ndimage.label(pale)
    if n < 2:
        raise SystemExit("couldn't find both of Szuix's eyes on his page")
    sizes = ndimage.sum(pale, lab, range(1, n + 1))
    eyes = []
    for k in np.argsort(sizes)[::-1][:2]:
        sl = ndimage.find_objects(lab)[k]
        m = lab[sl] == (k + 1)
        ys, xs = np.nonzero(m)
        eyes.append({
            "box": (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop),
            "mask": m,
            "c": (sl[1].start + xs.mean(), sl[0].start + ys.mean()),
        })
    eyes.sort(key=lambda e: e["c"][0])
    return eyes


def szuix_shut_eye(arr, eye):
    """Paint one eye shut, in place: the lid drawn down over it in his skin's
    colour, a little in shadow, and the lashes as one line along its lower
    rim. The line over the eye is left as it is drawn."""
    pad = 12
    x0, y0, x1, y1 = eye["box"]
    patch = arr[y0 - pad:y1 + pad, x0 - pad:x1 + pad]
    rgb = patch[..., :3]
    ph, pw = rgb.shape[:2]

    # The whole almond: the hull of its cyan, since the slit pupil is black.
    ey, ex = np.nonzero(eye["mask"])
    hull = ConvexHull(np.stack([ex, ey], 1))
    ss = 4
    hm = Image.new("L", (pw * ss, ph * ss), 0)
    ImageDraw.Draw(hm).polygon(
        [((ex[v] + pad + 0.5) * ss, (ey[v] + pad + 0.5) * ss)
         for v in hull.vertices], fill=255)
    em = np.asarray(hm.resize((pw, ph), Image.BOX)) > 127
    # The lid reaches a little past the almond, over the pale edge the eye's
    # anti-aliasing leaves on the line round it.
    lid = np.clip(ndimage.gaussian_filter(
        ndimage.binary_dilation(em, iterations=3).astype(np.float32), 0.8)
        * 1.6 - 0.3, 0.0, 1.0)
    # ...and over the white of the eye, which shows past its corner.
    white = ndimage.binary_dilation(
        (rgb[..., 1] > 130) & (rgb[..., 2] > 170), iterations=2)
    lid = np.maximum(lid, ndimage.gaussian_filter(white.astype(np.float32),
                                                  0.7))

    # His skin, from what is round the eye: blue, and not line or hair.
    skin = (rgb[..., 2] > 120) & (rgb[..., 0] < 80) & (rgb[..., 1] < 90) & ~em
    tone = (np.median(rgb[skin], axis=0) if skin.any()
            else np.array([44.0, 57.0, 150.0]))
    gy = np.linspace(0.0, 1.0, ph, dtype=np.float32)[:, None, None]
    shade = tone[None, None, :] * (0.80 + 0.12 * gy)
    rgb[...] = rgb * (1 - lid[..., None]) + shade * lid[..., None]

    # The lashes: the almond's lower rim, corner to corner, heaviest in the
    # middle.
    ys, xs = np.nonzero(em)
    cols = np.arange(xs.min(), xs.max() + 1)
    bot = np.array([ys[xs == c].max() for c in cols], np.float32)
    fit = np.polyval(np.polyfit(cols, bot, 2), cols)
    u = np.linspace(0.0, 1.0, len(cols))
    wid = 1.2 + 2.6 * np.sin(np.pi * u) ** 0.7
    pts = [(c + 0.5, y - w * 0.5) for c, y, w in zip(cols, fit, wid)] + \
          [(c + 0.5, y + w * 0.5) for c, y, w in zip(cols, fit, wid)][::-1]
    lm = Image.new("L", (pw * ss, ph * ss), 0)
    ImageDraw.Draw(lm).polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    line = np.asarray(lm.resize((pw, ph), Image.BOX), np.float32) / 255.0
    rgb[...] = (rgb * (1 - line[..., None])
                + np.array(LINE_INK, np.float32) * line[..., None])


def szuix_frames():
    arr = szuix_cut()
    eyes = szuix_eyes(arr)
    anchor = midpoint(eyes)

    px = np.concatenate([arr[e["box"][1]:e["box"][3],
                             e["box"][0]:e["box"][2], :3][e["mask"]]
                         for e in eyes])
    glow = tuple(int(v) for v in px.mean(0))

    shut = arr.copy()
    for e in eyes:
        szuix_shut_eye(shut, e)

    images, origin = finish([arr, shut], anchor, SZUIX_SCALE)
    return (images, origin, eye_rows(eyes, anchor, SZUIX_SCALE), glow,
            SZUIX_TINT)


# ---------------------------------------------------------------------------
# Mika
# ---------------------------------------------------------------------------

def mika_frames():
    sheet, bg = M.keyed_sheet()
    ys, xs = np.nonzero(sheet[..., 3] > 8)
    x0, x1 = max(0, xs.min() - 4), xs.max() + 5
    y0, y1 = max(0, ys.min() - 4), MIKA_FOOT
    arr = sheet[y0:y1, x0:x1].copy()
    del sheet

    eyes = []
    for e in M.find_eyes(arr):
        eyes.append(e)
    anchor = midpoint(eyes)
    glow = M.eye_glow_colour(arr, eyes)

    M.clean_edge(arr, bg)
    shut = arr.copy()
    for k, e in enumerate(eyes):
        M.shut_eye(shut, e, (k == 0), glow)

    images, origin = finish([arr, shut], anchor, MIKA_SCALE)
    return (images, origin, eye_rows(eyes, anchor, MIKA_SCALE), glow,
            MIKA_TINT)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

TABLE = """/// @desc The conversation portraits -- GENERATED by tools/make_portraits.py.
///       Do not edit: these are measured from the art.
///
/// `talk_art(_spr)`: where a portrait's eyes are, for the light put on them
/// when its owner is named. Each eye is `[x, y, rx, ry]`: its centre in
/// pixels from the sprite's origin (which is midway between them), and its
/// half-width and half-height. `glow` is the colour they shine. `tint` is
/// the colour its owner is lit in while they speak, or -1 for none of its
/// own.

function talk_art(_spr) {
%s    return { eyes: [], glow: c_white, tint: -1 };
}
"""

ENTRY = """    if (_spr == %s) {
        return {
            eyes: [%s],
            glow: %s,
            tint: %s,
        };
    }
"""


def write_table(rows):
    body = ""
    for name, eyes, glow, tint in rows:
        body += ENTRY % (
            name,
            ", ".join("[%d, %d, %d, %d]" % tuple(int(round(v)) for v in e)
                      for e in eyes),
            A.gm_hex(glow), A.gm_hex(tint))
    gm_new.script("talk_table", TABLE % body, folder="Scripts/ui")


def main():
    gm_new.folder(FOLDER)

    rows = []
    sheets = []
    for name, make in (("spr_talk_szuix", szuix_frames),
                       ("spr_talk_mika", mika_frames)):
        images, origin, eyes, glow, tint = make()
        gm_new.sprite(name, images, origin=origin, folder=FOLDER)
        rows.append((name, eyes, glow, tint))
        sheets += images
        print("%s: 2 frames of %dx%d, origin %d,%d, eyes %s"
              % (name, images[0].width, images[0].height, origin[0],
                 origin[1], [tuple(int(round(v)) for v in e) for e in eyes]))
    write_table(rows)

    out = os.path.join(A.PREVIEW, "portraits.png")
    A.preview(sheets, out, cols=4, bg=(36, 26, 74),
              labels=["szuix", "szuix, eyes shut", "mika", "mika, eyes shut"])
    print("->  %s" % os.path.relpath(out, A.ROOT))


if __name__ == "__main__":
    main()
