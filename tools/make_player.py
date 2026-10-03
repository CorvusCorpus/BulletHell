#!/usr/bin/env python3
"""Prepare Szuix from the commissioned pixel sheet, and draw his aura. (His
sigil cut-in's portrait is `make_portraits.py`'s.)

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
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageFilter

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

    A.preview(frames, os.path.join(A.PREVIEW, "player.png"), cols=6,
              bg=(30, 34, 52))
    over = [A.over(A.checker(w, h, (196, 176, 150), (176, 156, 132)), f)
            for f in frames]
    A.preview(over, os.path.join(A.PREVIEW, "player_bright.png"), cols=6,
              bg=(200, 190, 170))
    print("szuix: %d frames of %dx%d" % (len(frames), w, h))


if __name__ == "__main__":
    main()
