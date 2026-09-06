#!/usr/bin/env python3
"""Prepare Szuix from the commissioned sheet.

**This is the one asset in the project that is not drawn here**, and the whole
job of this script is to get it to the game without damaging it. The source is
`tools/source/szuix_sheet.png`: six frames of 55x45, hard-alpha pixel art, a
back view of him flying. Everything else on screen is generated smooth at 1920
x1080, so the sprite has two problems -- it is small, and it is the only
aliased thing in the frame.

**Upscaling it is not a resize.** A LANCZOS enlargement of hard-alpha pixel art
is mush: the filter has nothing to interpolate between but a pixel and its
neighbour, so every edge becomes a four-pixel gradient and the character loses
his silhouette. And a NEAREST enlargement keeps the silhouette and keeps the
staircase, which against smooth bullets and a painted background reads as a
sprite from a different game.

So it goes up hard and comes back down soft: NEAREST to six times, one blur at
that size to round the corners the staircase left, then LANCZOS down to two
times. The blur happens where a pixel of the original is six pixels wide, so it
softens *within* an original pixel rather than across several -- which is the
difference between an anti-aliased edge and a blurred one.

Then two things are added that the source could not have: a dark contour, so he
survives being flown across a bright background for the same reason every
bullet has one, and a cool rim along his upward-facing edges, so he sits in the
same light as everything else on the field.

If the commission is ever redone at a higher resolution, point `SOURCE` at it
and set `SCALE` to 1 -- the rest of this still applies.

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

# Final size is SCALE times the source. At 2x he is 110x90, which is about
# eight per cent of the screen's height -- the same share a Touhou player
# sprite occupies at 640x480, which is the proportion the whole genre's sense
# of "how much room have I got" is calibrated on.
SCALE = 2
OVERSAMPLE = 6


def smooth_upscale(img, scale, oversample=OVERSAMPLE, soften=2.4):
    """Enlarge pixel art without either mushing it or keeping its staircase.

    **Premultiplied, and that is not a detail.** Every transparent pixel in the
    commissioned sheet is *white* -- it was drawn on white and the background
    erased, which is invisible while the alpha is hard and 0 or 255. Blur it
    unpremultiplied and PIL blurs the colour channels too, so that white bleeds
    into every edge: the first run of this came out with a pale grey halo all
    round him, which read as a badly cut-out sticker. Multiplying the colour by
    the alpha first means what bleeds in is *nothing*, which is the truth.
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

    # The contour. Traced from a *hardened* copy of the alpha: tracing the
    # feathered edge directly puts the line halfway into the character and
    # thickens him by a pixel all round, which across six frames reads as him
    # pulsing.
    solid = out.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    grown = solid.filter(ImageFilter.MaxFilter(5))
    ring = ImageChops.subtract(grown, solid).filter(
        ImageFilter.GaussianBlur(0.8))
    contour = Image.new("RGBA", out.size, (6, 8, 20, 0))
    contour.putalpha(ring.point(lambda v: int(v * 0.78)))

    result = Image.new("RGBA", out.size, (0, 0, 0, 0))
    result.alpha_composite(contour)
    result.alpha_composite(out)

    # The rim: the same trick the background layers use, applied to a
    # character. It gives every upward-facing edge a lit side, which is what
    # stops a dark blue silhouette reading as a hole in a dark blue night.
    rim = A.rim_light(solid, A.SZUIX_LIT, drop=3, blur=1.2, strength=0.55)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), solid))
    result = A.add(result, rim)
    return result


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

    A.preview(frames, os.path.join(A.PREVIEW, "player.png"), cols=6,
              bg=(30, 34, 52))
    over = [A.over(A.checker(w, h, (196, 176, 150), (176, 156, 132)), f)
            for f in frames]
    A.preview(over, os.path.join(A.PREVIEW, "player_bright.png"), cols=6,
              bg=(200, 190, 170))
    print("szuix: %d frames of %dx%d" % (len(frames), w, h))


if __name__ == "__main__":
    main()
