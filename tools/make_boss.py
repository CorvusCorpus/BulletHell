#!/usr/bin/env python3
"""Ziggy: the first boss, and the eye card his spells announce themselves with.

**This is the one generator making art that is expected to be replaced.** The
brief says character art may be commissioned later, so what this guarantees is
the *contract* -- the size, the frame count, the frame order, the origin, and
that he is drawn facing the player -- rather than the drawing. Point
`gm_new.sprite` at a painted PNG of the same dimensions and nothing else in the
project changes. The same promise `tools/make_chars.py` makes in the Wordsearch
project, for the same reason.

**He faces down the screen and Szuix faces up it.** The player sprite is a back
view -- the commission is of him flying away from the camera -- so the boss has
to be a front view or the two of them are looking the same way and the fight
reads as a race. It is also why the eye card works at all: the eyes it shows in
close-up are eyes the player has been looking at for five minutes.

Ziggy is short, stocky and red, with black hair, pale curved horns, bat wings
and a skull at his belt. He is Szuix's friend and rival, so he is drawn
grinning rather than snarling -- the first fight in the game should not look
like a murder.

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

    # The leading arm, then the scalloped trailing edge back to the body --
    # the scallops are the whole reason a bat wing reads as a bat wing.
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
    """Torso, head, arms and legs, as one silhouette so they share a contour."""
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
    # Arms: out and a little down, hands open -- he is showing off.
    for sign in (-1, 1):
        d.line([(cx + sign * W * SS * 0.115, cy - H * SS * 0.020),
                (cx + sign * W * SS * 0.215, cy + H * SS * 0.055),
                (cx + sign * W * SS * 0.255, cy - H * SS * 0.010)],
               fill=255, width=int(W * SS * 0.052), joint="curve")
        d.ellipse([cx + sign * W * SS * 0.255 - W * SS * 0.040,
                   cy - H * SS * 0.010 - W * SS * 0.040,
                   cx + sign * W * SS * 0.255 + W * SS * 0.040,
                   cy - H * SS * 0.010 + W * SS * 0.040], fill=255)
    # Head, and the neck under it. **Held clear of the shoulders**: an ellipse
    # overlapping the torso merges into one blob under the distance-field
    # shading, and what that produces is a boss with no neck and no chin --
    # which at 260 pixels is a red mass with a face painted on it.
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
    """Two horns sweeping up and curling back in over the head.

    **A quadratic through three named points, not an angle swept round a
    circle.** The first version parameterised the curl as `cos(t * 2.1)`
    against a growing radius, which is a formula whose shape nobody can
    predict -- what it produced was a scatter of pale lumps across the top of
    his skull that read as a crown of teeth. Three control points can be
    reasoned about: where it leaves the head, how far out it goes, and where
    the tip ends up.
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
        # The brow: one angled stroke, and the whole of his expression.
        cv.line([(cx - sign * rx * 1.5, cy - ry * 1.9),
                 (cx + sign * rx * 1.5, cy - ry * 2.9)],
                fill=A.rgba(HAIR, 235), width=W * 0.011)

    # The grin, with two fangs. Wide, because he is enjoying this.
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

    # The contour and the rim, exactly as the player gets them, so the two
    # characters sit in the same light.
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


# ---------------------------------------------------------------------------
# The eye card
# ---------------------------------------------------------------------------

def eye_card(w=1280, h=420):
    """The close-up that flashes when a spell is declared.

    **A close-up of his whole face, not a pair of eyes on a field.** An early
    draft floated two eyes over some rays, which is a graphic rather than a
    portrait -- the reference cards this is modelled on push the camera into
    the character's face until the head runs off all four edges, and the eyes
    dominate because they are the brightest thing in it, not because they are
    the only thing in it. Horns leaving the top of the frame and ears leaving
    the sides are what say "this is a crop", and the crop is what says "close
    up".

    Drawn in card space rather than by scaling the sprite. At five times its
    size the 260px sprite is mush, and a face wants different proportions in
    close-up anyway: the sprite's head is a readable icon at forty pixels on a
    moving field, and this is a portrait.
    """
    cx, cy = w / 2.0, h / 2.0

    # **The ground is opaque and the glow comes off the eyes alone.** An early
    # version drew everything onto one transparent canvas and then took the
    # glow from *that canvas's* alpha -- which by then was opaque everywhere,
    # so it added gold to every pixel and the whole card came back the colour
    # of the eyes. A glow is a property of the thing that is glowing.
    ground = A.Canvas(w, h, ss=2)
    ground.rect([0, 0, w, h], fill=A.rgba((14, 6, 9), 255))
    for i in range(30):
        t = 1.0 - i / 29.0
        r = h * (0.20 + 1.7 * t)
        ground.ellipse([cx - r * 2.2, cy - r, cx + r * 2.2, cy + r],
                       fill=A.rgba(A.mix((14, 6, 9), SKIN_DARK, 1 - t), 26))
    for i in range(28):
        ang = math.radians(i * 12.85 + 6)
        r0, r1 = h * 0.14, h * 2.4
        wide = h * 0.048
        ground.polygon([(cx + math.cos(ang) * r0, cy + math.sin(ang) * r0),
                        (cx + math.cos(ang) * r1 - math.sin(ang) * wide,
                         cy + math.sin(ang) * r1 + math.cos(ang) * wide),
                        (cx + math.cos(ang) * r1 + math.sin(ang) * wide,
                         cy + math.sin(ang) * r1 - math.cos(ang) * wide)],
                       fill=A.rgba(SKIN, 26))

    S = 2.0

    def px(v):
        return v * S

    # ---- the face, as one silhouette so it shades as one head -------------
    fm = Image.new("L", (int(w * S), int(h * S)), 0)
    fd = ImageDraw.Draw(fm)

    # The skull is deliberately taller than the card, so it crops top and
    # bottom. `hcy` sits well below centre, which puts the eyes on the upper
    # third of the head *and* in the middle of the card -- where each belongs.
    hcx, hcy = cx, cy + h * 0.60
    hrx, hry = w * 0.215, h * 1.02
    fd.ellipse([px(hcx - hrx), px(hcy - hry), px(hcx + hrx), px(hcy + hry)],
               fill=255)

    # Ears, huge and swept back, running off the sides of the frame.
    for sign in (-1, 1):
        fd.polygon([(px(hcx + sign * hrx * 0.88), px(cy - h * 0.24)),
                    (px(hcx + sign * hrx * 1.76), px(cy - h * 0.62)),
                    (px(hcx + sign * hrx * 1.62), px(cy - h * 0.02)),
                    (px(hcx + sign * hrx * 0.94), px(cy + h * 0.14))],
                   fill=255)
    face = A.shade_shape(fm, SKIN, core=A.shade(SKIN, 0.45), core_frac=0.30,
                         edge_frac=0.26, spec=False)

    # Horns, over the skull and out of the top of the frame.
    hm = Image.new("L", (int(w * S), int(h * S)), 0)
    hd = ImageDraw.Draw(hm)
    for sign in (-1, 1):
        p0 = (hcx + sign * hrx * 0.66, cy - h * 0.30)
        p1 = (hcx + sign * hrx * 1.70, cy - h * 0.78)
        p2 = (hcx + sign * hrx * 0.90, cy - h * 1.20)
        for i in range(30):
            t = i / 29.0
            u = 1 - t
            qx = u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]
            qy = u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]
            rr = (h * 0.115) * (1 - t) ** 0.8 + h * 0.012
            hd.ellipse([px(qx - rr), px(qy - rr), px(qx + rr), px(qy + rr)],
                       fill=255)
    horns = A.shade_shape(hm, HORN, core=A.shade(HORN, 0.45), core_frac=0.34,
                          edge_frac=0.28, spec=False)

    # Hair: a mass across the crown with spikes out of the top of the frame.
    am = Image.new("L", (int(w * S), int(h * S)), 0)
    ad = ImageDraw.Draw(am)
    ad.ellipse([px(hcx - hrx * 1.02), px(cy - h * 0.90),
                px(hcx + hrx * 1.02), px(cy - h * 0.22)], fill=255)
    rnd = np.random.default_rng(9)
    for i in range(11):
        t = i / 10.0
        ax = hcx + (t - 0.5) * hrx * 2.1
        ay = cy - h * 0.52 + abs(t - 0.5) * h * 0.30
        lift = h * rnd.uniform(0.30, 0.55)
        lean = w * rnd.uniform(-0.02, 0.02)
        ad.polygon([(px(ax - w * 0.030), px(ay + h * 0.10)),
                    (px(ax + lean), px(ay - lift)),
                    (px(ax + w * 0.030), px(ay + h * 0.10))], fill=255)
    hair = A.shade_shape(am, (74, 62, 82), core=(120, 108, 132),
                         core_frac=0.22, edge_frac=0.34, spec=False)

    # ---- the eyes ---------------------------------------------------------
    eyes = A.Canvas(w, h, ss=2)
    for sign in (-1, 1):
        ex = cx + sign * w * 0.132
        ey = cy + h * 0.02
        rx, ry = w * 0.100, h * 0.175

        # **Built at the right-hand eye and mirrored for the left.** Building
        # it at `ex` -- which is already the left-hand centre -- and *then*
        # mirroring about the card reflects it back across to the right, so
        # both lids land on top of each other and the left eye is a slit with
        # no eye round it. Which is exactly what the first render showed.
        rex = cx + w * 0.132
        lid = [(rex - rx, ey + ry * 0.12),
               (rex - rx * 0.42, ey - ry),
               (rex + rx * 0.58, ey - ry * 0.78),
               (rex + rx, ey + ry * 0.28),
               (rex + rx * 0.32, ey + ry),
               (rex - rx * 0.58, ey + ry * 0.86)]
        if sign < 0:
            lid = [(2 * cx - qx, qy) for qx, qy in lid]
        eyes.polygon(lid, fill=A.rgba(EYE, 255))
        eyes.polygon(lid + [lid[0]], outline=A.rgba((52, 18, 14), 255))
        eyes.ellipse([ex - rx * 0.12, ey - ry * 0.88,
                      ex + rx * 0.12, ey + ry * 0.88],
                     fill=(14, 7, 10, 255))
        # The specular sits on the side the light comes from, which mirrors
        # with the eye -- so the box has to be sorted, or PIL refuses one of
        # the two.
        sx0 = ex - sign * rx * 0.44
        sx1 = ex - sign * rx * 0.12
        eyes.ellipse([min(sx0, sx1), ey - ry * 0.56,
                      max(sx0, sx1), ey - ry * 0.06],
                     fill=(255, 255, 255, 215))

    # Brows, heavy and angled in. In the hair's colour, so they read as part of
    # the hair rather than as a third material.
    brows = A.Canvas(w, h, ss=2)
    for sign in (-1, 1):
        ex = cx + sign * w * 0.132
        ey = cy + h * 0.02
        rx, ry = w * 0.100, h * 0.175
        brows.polygon([(ex - sign * rx * 1.05, ey - ry * 1.42),
                       (ex + sign * rx * 1.10, ey - ry * 2.00),
                       (ex + sign * rx * 1.12, ey - ry * 1.52),
                       (ex - sign * rx * 1.00, ey - ry * 1.02)],
                      fill=A.rgba((32, 24, 36), 255))

    # The grin, low in the frame and running off the bottom. The crop is what
    # makes this a close-up rather than a portrait of a small head.
    mouth = A.Canvas(w, h, ss=2)
    mw, mh = w * 0.20, h * 0.20
    my = cy + h * 0.46
    mouth.pieslice([cx - mw, my - mh, cx + mw, my + mh], 6, 174,
                   fill=(40, 12, 16, 255))
    for i in range(5):
        t = (i + 0.5) / 5.0
        fx = cx - mw * 0.78 + t * mw * 1.56
        drop = h * (0.085 - abs(t - 0.5) * 0.075)
        mouth.polygon([(fx - w * 0.019, my + h * 0.004),
                       (fx + w * 0.019, my + h * 0.004),
                       (fx, my + drop + h * 0.02)], fill=A.rgba(BONE, 255))

    eye_img = eyes.finish()
    glow = Image.new("RGBA", (w, h), A.rgba(EYE, 0))
    glow.putalpha(eye_img.getchannel("A")
                         .filter(ImageFilter.GaussianBlur(30))
                         .point(lambda v: int(v * 0.62)))

    out = ground.finish()
    out.alpha_composite(face.resize((w, h), Image.LANCZOS))
    out.alpha_composite(mouth.finish())
    out.alpha_composite(hair.resize((w, h), Image.LANCZOS))
    out.alpha_composite(horns.resize((w, h), Image.LANCZOS))
    out = A.add(out, glow)
    out.alpha_composite(eye_img)
    out.alpha_composite(brows.finish())

    # A vignette, so the card fades into whatever it is drawn over instead of
    # ending in a hard rectangle across the middle of the screen.
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xs, w - 1 - xs) / (w * 0.13),
                      np.minimum(ys, h - 1 - ys) / (h * 0.16))
    fade = np.clip(edge, 0, 1) ** 0.9
    arr = np.asarray(out, dtype=np.float32)
    arr[..., 3] *= fade
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def main():
    gm_new.folder("Sprites/boss")

    frames = [build_frame(i, FRAMES) for i in range(FRAMES)]
    gm_new.sprite("spr_boss_ziggy", frames, origin="center",
                  folder="Sprites/boss", fps=8.0)

    card = eye_card()
    gm_new.sprite("spr_eye_ziggy", [card], origin="center",
                  folder="Sprites/boss")

    A.preview(frames, os.path.join(A.PREVIEW, "boss_ziggy.png"), cols=6,
              bg=(26, 20, 26))
    card.save(os.path.join(A.PREVIEW, "eye_ziggy.png"))
    print("ziggy: %d frames of %dx%d, eye card %dx%d"
          % (len(frames), W, H, card.width, card.height))


if __name__ == "__main__":
    main()
