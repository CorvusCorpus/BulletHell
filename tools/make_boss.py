#!/usr/bin/env python3
"""Ziggy (the first boss). Placeholder art drawn from primitives. (His spells
show Mika's cut-in portrait until he has his own: see `make_mika.py`.)

Any replacement must keep the contract: the sprite's size, frame count, frame
order and origin, and drawn facing the player (down the screen; Szuix is a
back view facing up it). A painted PNG of the same dimensions can be dropped
in through `gm_new.sprite` with nothing else changing.

Ziggy: short, stocky and red, black hair, pale curved horns, bat wings, a
skull at his belt, grinning.

Usage:
    python tools/make_boss.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SS = A.SS

W, H = 260, 250          # the final sprite
FRAMES = 6

SKIN = (214, 58, 48)
SKIN_LIT = (255, 128, 92)
SKIN_DARK = (128, 26, 26)
HORN = (232, 222, 200)
HAIR = (28, 22, 30)
MEMBRANE = (168, 40, 40)
BONE = (238, 232, 216)
EYE = (255, 206, 72)
BELT = (44, 34, 40)


def canvas():
    img = Image.new("L", (W * SS, H * SS), 0)
    return img, ImageDraw.Draw(img)


def shaded(mask, colour, core=0.34, halo=0.0):
    """One body part, with volume, from a mask."""
    return A.shade_shape(mask, colour, core=A.shade(colour, 0.55),
                         core_frac=core, edge_frac=0.30, spec=False, halo=halo)


def wing_mask(sign, spread):
    """One bat wing. `spread` runs 0 (folded) to 1 (open)."""
    img, d = canvas()
    sx, sy = W * SS * 0.5, H * SS * 0.40          # the shoulder
    reach = W * SS * (0.20 + 0.26 * spread)
    rise = H * SS * (0.10 + 0.24 * spread)

    # The leading arm, then the scalloped trailing edge back to the body.
    tip = (sx + sign * reach * 1.55, sy - rise * 1.15)
    knuckles = [
        (sx + sign * reach * 1.30, sy - rise * 0.10),
        (sx + sign * reach * 0.95, sy + rise * 0.55),
        (sx + sign * reach * 0.58, sy + rise * 0.95),
    ]
    pts = [(sx, sy - H * SS * 0.02), tip]
    prev = tip
    for k in knuckles:
        mid = ((prev[0] + k[0]) * 0.5 - sign * reach * 0.10,
               (prev[1] + k[1]) * 0.5 + rise * 0.34)
        pts.append(mid)
        pts.append(k)
        prev = k
    pts.append((sx, sy + H * SS * 0.10))
    d.polygon(pts, fill=255)
    return img, (sx, sy), tip, knuckles


def wing_bones(sign, spread):
    img, d = canvas()
    _, (sx, sy), tip, knuckles = wing_mask(sign, spread)
    wide = max(2, int(W * SS * 0.008))
    d.line([(sx, sy), tip], fill=255, width=wide)
    for k in knuckles:
        d.line([(sx, sy), k], fill=255, width=wide)
    return img


def body_mask(bob):
    """Torso, head, arms and legs as one silhouette, sharing a contour."""
    img, d = canvas()
    cx = W * SS * 0.5
    cy = H * SS * 0.50 + bob

    # Torso: stocky, wider at the chest than the waist.
    d.ellipse([cx - W * SS * 0.135, cy - H * SS * 0.055,
               cx + W * SS * 0.135, cy + H * SS * 0.155], fill=255)
    # Legs: short and bent, which is most of what "stocky" means.
    for sign in (-1, 1):
        d.ellipse([cx + sign * W * SS * 0.005 - W * SS * 0.055,
                   cy + H * SS * 0.10,
                   cx + sign * W * SS * 0.005 + W * SS * 0.075,
                   cy + H * SS * 0.235], fill=255)
        d.ellipse([cx + sign * W * SS * 0.055 - W * SS * 0.050,
                   cy + H * SS * 0.195,
                   cx + sign * W * SS * 0.055 + W * SS * 0.050,
                   cy + H * SS * 0.255], fill=255)
    # Arms: out and a little down, hands open.
    for sign in (-1, 1):
        d.line([(cx + sign * W * SS * 0.115, cy - H * SS * 0.020),
                (cx + sign * W * SS * 0.215, cy + H * SS * 0.055),
                (cx + sign * W * SS * 0.255, cy - H * SS * 0.010)],
               fill=255, width=int(W * SS * 0.052), joint="curve")
        d.ellipse([cx + sign * W * SS * 0.255 - W * SS * 0.040,
                   cy - H * SS * 0.010 - W * SS * 0.040,
                   cx + sign * W * SS * 0.255 + W * SS * 0.040,
                   cy - H * SS * 0.010 + W * SS * 0.040], fill=255)
    # Head, and the neck under it, kept clear of the shoulders (overlapping
    # ellipses merge into one blob under the distance-field shading).
    hx, hy = cx, cy - H * SS * 0.165
    d.ellipse([hx - W * SS * 0.100, hy - H * SS * 0.092,
               hx + W * SS * 0.100, hy + H * SS * 0.088], fill=255)
    d.rectangle([hx - W * SS * 0.032, hy + H * SS * 0.055,
                 hx + W * SS * 0.032, cy - H * SS * 0.030], fill=255)
    # Ears, swept back.
    for sign in (-1, 1):
        d.polygon([(hx + sign * W * SS * 0.086, hy - H * SS * 0.018),
                   (hx + sign * W * SS * 0.172, hy - H * SS * 0.052),
                   (hx + sign * W * SS * 0.092, hy + H * SS * 0.036)],
                  fill=255)
    return img, (cx, cy), (hx, hy)


def tail_mask(bob, phase):
    img, d = canvas()
    cx = W * SS * 0.5
    cy = H * SS * 0.50 + bob
    pts = []
    n = 18
    for i in range(n + 1):
        t = i / n
        ang = math.radians(-40 + 150 * t + math.sin(phase) * 14 * t)
        r = W * SS * 0.26 * t
        pts.append((cx + W * SS * 0.06 + math.cos(ang) * r * 0.9,
                    cy + H * SS * 0.13 + math.sin(ang) * r))
    d.line(pts, fill=255, width=int(W * SS * 0.022), joint="curve")
    # The spade.
    ex, ey = pts[-1]
    d.polygon([(ex + W * SS * 0.045, ey), (ex - W * SS * 0.010, ey - W * SS * 0.045),
               (ex - W * SS * 0.005, ey), (ex - W * SS * 0.010, ey + W * SS * 0.045)],
              fill=255)
    return img


def horns_mask(hx, hy):
    """Two horns sweeping up and curling back over the head, each a quadratic
    through three control points (where it leaves the head, how far out, where
    the tip ends).
    """
    img, d = canvas()
    for sign in (-1, 1):
        p0 = (hx + sign * W * SS * 0.072, hy - H * SS * 0.052)   # root
        p1 = (hx + sign * W * SS * 0.165, hy - H * SS * 0.135)   # the bend
        p2 = (hx + sign * W * SS * 0.088, hy - H * SS * 0.205)   # tip, curled in
        n = 22
        for i in range(n + 1):
            t = i / n
            u = 1 - t
            px = u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]
            py = u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]
            rr = W * SS * (0.036 * (1 - t) ** 0.85 + 0.004)
            d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=255)
    return img


def hair_mask(hx, hy):
    img, d = canvas()
    d.ellipse([hx - W * SS * 0.100, hy - H * SS * 0.096,
               hx + W * SS * 0.100, hy + H * SS * 0.004], fill=255)
    # Spikes, out to the sides and up. Uneven, from a fixed seed.
    rnd = np.random.default_rng(4)
    for i in range(9):
        t = i / 8.0
        ax = hx + (t - 0.5) * W * SS * 0.22
        ay = hy - H * SS * 0.078 + abs(t - 0.5) * H * SS * 0.040
        lift = H * SS * rnd.uniform(0.045, 0.085)
        lean = W * SS * rnd.uniform(-0.03, 0.03)
        d.polygon([(ax - W * SS * 0.028, ay + H * SS * 0.02),
                   (ax + lean, ay - lift),
                   (ax + W * SS * 0.028, ay + H * SS * 0.02)], fill=255)
    return img


def loincloth_mask(cx, cy):
    img, d = canvas()
    d.rounded_rectangle([cx - W * SS * 0.125, cy + H * SS * 0.075,
                         cx + W * SS * 0.125, cy + H * SS * 0.125],
                        radius=W * SS * 0.012, fill=255)
    d.polygon([(cx - W * SS * 0.10, cy + H * SS * 0.12),
               (cx + W * SS * 0.10, cy + H * SS * 0.12),
               (cx + W * SS * 0.075, cy + H * SS * 0.20),
               (cx - W * SS * 0.075, cy + H * SS * 0.20)], fill=255)
    return img


def skull_mask(cx, cy):
    """The skull at his belt -- the one piece of detail that says *imp* rather
    than *small red person*."""
    img, d = canvas()
    sx, sy = cx, cy + H * SS * 0.10
    r = W * SS * 0.036
    d.ellipse([sx - r, sy - r, sx + r, sy + r * 0.75], fill=255)
    d.rounded_rectangle([sx - r * 0.55, sy + r * 0.4, sx + r * 0.55, sy + r * 1.15],
                        radius=r * 0.2, fill=255)
    return img


def face_layer(hx, hy, blink):
    """Eyes and grin, drawn straight rather than shaded -- they are markings,
    not volumes, and shading them makes them read as holes."""
    cv = A.Canvas(W, H)
    ex = hx / SS
    ey = hy / SS
    for sign in (-1, 1):
        cx = ex + sign * W * 0.042
        cy = ey - H * 0.012
        rx, ry = W * 0.032, H * 0.027 * (0.16 if blink else 1.0)
        cv.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=A.rgba(EYE, 255))
        if not blink:
            # A slit pupil, and a specular that makes the eye wet.
            cv.ellipse([cx - rx * 0.20, cy - ry * 0.86,
                        cx + rx * 0.20, cy + ry * 0.86],
                       fill=(20, 12, 16, 255))
            cv.ellipse([cx - rx * 0.55, cy - ry * 0.66,
                        cx - rx * 0.10, cy - ry * 0.14],
                       fill=(255, 255, 255, 210))
        # The brow: one angled stroke.
        cv.line([(cx - sign * rx * 1.5, cy - ry * 1.9),
                 (cx + sign * rx * 1.5, cy - ry * 2.9)],
                fill=A.rgba(HAIR, 235), width=W * 0.011)

    # The grin, with two fangs.
    mw, mh = W * 0.062, H * 0.027
    my = ey + H * 0.042
    cv.pieslice([ex - mw, my - mh, ex + mw, my + mh], 8, 172,
                fill=(46, 16, 20, 255))
    for sign in (-1, 1):
        fx = ex + sign * mw * 0.62
        cv.polygon([(fx - W * 0.011, my + H * 0.001),
                    (fx + W * 0.011, my + H * 0.001),
                    (fx, my + H * 0.020)], fill=A.rgba(BONE, 255))
    return cv.finish()


def build_frame(i, frames):
    """Composite one frame, back to front."""
    beat = math.sin(2 * math.pi * i / frames)
    spread = 0.55 + 0.45 * beat
    bob = beat * H * SS * 0.012
    blink = (i == frames - 2)

    out = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))

    for sign in (-1, 1):
        wm, _, _, _ = wing_mask(sign, spread)
        out.alpha_composite(shaded(wm, MEMBRANE, core=0.20))
        bones = wing_bones(sign, spread)
        bone_layer = Image.new("RGBA", out.size, A.rgba(SKIN_DARK, 0))
        bone_layer.putalpha(ImageChops.multiply(bones, wm))
        out.alpha_composite(bone_layer)

    out.alpha_composite(shaded(tail_mask(bob, i * 1.1), SKIN, core=0.22))

    body, (cx, cy), (hx, hy) = body_mask(bob)
    out.alpha_composite(shaded(body, SKIN, core=0.30))
    out.alpha_composite(shaded(loincloth_mask(cx, cy), BELT, core=0.24))
    out.alpha_composite(shaded(skull_mask(cx, cy), BONE, core=0.40))
    out.alpha_composite(shaded(horns_mask(hx, hy), HORN, core=0.38))
    out.alpha_composite(shaded(hair_mask(hx, hy), HAIR, core=0.16))

    small = out.resize((W, H), Image.LANCZOS)
    small.alpha_composite(face_layer(hx, hy, blink))

    # The same contour and rim treatment as the player sprite.
    solid = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    ring = ImageChops.subtract(solid.filter(ImageFilter.MaxFilter(5)), solid)
    contour = Image.new("RGBA", small.size, (10, 6, 12, 0))
    contour.putalpha(ring.filter(ImageFilter.GaussianBlur(0.7))
                         .point(lambda v: int(v * 0.80)))

    result = Image.new("RGBA", small.size, (0, 0, 0, 0))
    result.alpha_composite(contour)
    result.alpha_composite(small)
    rim = A.rim_light(solid, SKIN_LIT, drop=3, blur=1.2, strength=0.45)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), solid))
    return A.add(result, rim)


def main():
    gm_new.folder("Sprites/boss")

    frames = [build_frame(i, FRAMES) for i in range(FRAMES)]
    gm_new.sprite("spr_boss_ziggy", frames, origin="center",
                  folder="Sprites/boss", fps=8.0)

    A.preview(frames, os.path.join(A.PREVIEW, "boss_ziggy.png"), cols=6,
              bg=(26, 20, 26))
    print("ziggy: %d frames of %dx%d" % (len(frames), W, H))


if __name__ == "__main__":
    main()
