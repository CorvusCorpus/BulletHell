#!/usr/bin/env python3
"""The fodder: a wisp, a grimoire, a cut gem and a stone sentry.

Nothing in a wave is a creature (owner's rule): the fodder is animated
objects.

They are drawn greyscale and tinted at draw time (`enemy_draw`), so one set
serves every stage. Like the bullets, each has a bright core and a darker
rim so the tint keeps its shape, and a hard dark contour.

Each is three layers multiplied together:

body      the silhouette, shaded by depth (`shade_shape`)
facets    a value per plane, so the form reads as planes rather than a bulge
detail    grooves, grain and inlay

Usage:
    python tools/make_enemies.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SS = A.SS

# The near-white the greyscale art is built in: a hint of blue keeps the dark
# parts cool after tinting.
PALE = (236, 240, 252)

# The dark ring, in final pixels. Same argument as the bullets'.
CONTOUR = 2.0


def _mask(w, h):
    img = Image.new("L", (int(w * SS), int(h * SS)), 0)
    return img, ImageDraw.Draw(img)


# The facet-map value that leaves a plane unchanged, and the most a facet may
# brighten one by. Neutral is high and the ceiling low because the body is
# already nearly white at its core; painting mostly below neutral darkens
# planes rather than clipping them to flat white.
FACET_NEUTRAL = 190.0
FACET_MAX = 1.15


def _facets(w, h):
    """A canvas for plane values; FACET_NEUTRAL leaves a plane unchanged."""
    img = Image.new("L", (int(w * SS), int(h * SS)), int(FACET_NEUTRAL))
    return img, ImageDraw.Draw(img)


# ---------------------------------------------------------------------------
# The wisp -- a flame with a core and a tail of embers
# ---------------------------------------------------------------------------

def wisp(w, h, frame, frames):
    """A flame: round at the foot, widest low down, tapering to a point."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames

    pts_l, pts_r = [], []
    n = 46
    for i in range(n + 1):
        t = i / n                              # 0 at the foot, 1 at the tip
        y = H * 0.86 - t * H * 0.78
        taper = (1.0 - t) ** 1.7               # convex fall to the point
        foot = min(1.0, (0.10 + t) / 0.26)     # rounds the very bottom off
        half = W * 0.32 * taper * foot + W * 0.012
        # The tip wanders and the base does not, so it flickers.
        lick = math.sin(t * 3.4 + ph) * W * 0.09 * (t ** 2)
        pts_l.append((cx + lick - half, y))
        pts_r.append((cx + lick + half, y))
    d.polygon(pts_l + pts_r[::-1], fill=255)

    # A ring of embers orbiting it.
    for i in range(5):
        ang = ph + i * 2 * math.pi / 5
        ex = cx + math.cos(ang) * W * 0.40
        ey = H * 0.58 + math.sin(ang) * H * 0.17
        er = W * (0.045 + 0.018 * math.cos(ang * 2))
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=255)

    return img


def wisp_facets(w, h, frame, frames):
    """The flame's lit and shaded sides, and a bright ring round its hollow."""
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames
    # The far side (right, away from the light), darkened.
    d.polygon([(cx + W * 0.02, H * 0.90), (cx + W * 0.06, H * 0.10),
               (cx + W * 0.34, H * 0.55), (cx + W * 0.26, H * 0.88)],
              fill=86)
    # ...and the sheet of brightest flame just inside the leading edge.
    d.polygon([(cx - W * 0.13, H * 0.82), (cx - W * 0.06, H * 0.22),
               (cx + W * 0.02, H * 0.60), (cx - W * 0.02, H * 0.86)],
              fill=214)
    # A bright ring round the dark hollow (the "eye" of the wisp).
    ey = H * 0.60 + math.sin(ph) * H * 0.02
    rx, ry = W * 0.26, H * 0.22
    d.ellipse([cx - rx, ey - ry, cx + rx, ey + ry], fill=218)
    return img.filter(ImageFilter.GaussianBlur(SS * 1.6))


def wisp_cuts(w, h, frame, frames):
    """The dark hollow at the flame's heart."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx = W / 2.0
    ph = 2 * math.pi * frame / frames
    cy = H * 0.60 + math.sin(ph) * H * 0.02
    rx, ry = W * 0.15, H * 0.13
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    return img


# ---------------------------------------------------------------------------
# The grimoire -- an open tome seen from above, pages lifting
# ---------------------------------------------------------------------------
#
# Seen from above so the two halves are splayed quadrilaterals separated by a
# gutter (open and face-on it read as a bowtie; shut, as a door). At this size
# an object is recognised by its silhouette and proportions, not its detail.


def _tome_pages(W, H):
    """The two page panels, as (left, right) point lists, splayed from a gutter
    down the middle and wider at their outer edges.
    """
    cx, cy = W / 2.0, H / 2.0
    gut = W * 0.045                       # half the gutter
    out = W * 0.44                        # how far the outer edge reaches
    left = [(cx - gut, cy - H * 0.24), (cx - out, cy - H * 0.14),
            (cx - out, cy + H * 0.24), (cx - gut, cy + H * 0.26)]
    right = [(cx + gut, cy - H * 0.24), (cx + out, cy - H * 0.14),
             (cx + out, cy + H * 0.24), (cx + gut, cy + H * 0.26)]
    return left, right


def grimoire(w, h, frame, frames):
    """An open tome held flat in the air, with loose pages lifting off it."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    beat = math.sin(2 * math.pi * frame / frames)

    left, right = _tome_pages(W, H)

    # The boards, behind and a little below the pages (thickness).
    for pts in (left, right):
        d.polygon([(x + (W * 0.012 if x > cx else -W * 0.012), y + H * 0.030)
                   for x, y in pts], fill=255)
    d.polygon(left, fill=255)
    d.polygon(right, fill=255)

    # Loose pages lifting off the outer corners (the animation).
    for sign, pts in ((-1, left), (1, right)):
        for i in range(3):
            spread = (i + 1) / 3.0
            lift = (beat * 0.5 + 0.5) * spread
            rx = cx + sign * (W * 0.30 + W * 0.10 * spread)
            ry = cy - H * 0.20 - H * 0.20 * lift
            d.polygon([(rx - sign * W * 0.10, ry + H * 0.14),
                       (rx + sign * W * 0.12, ry - H * 0.03),
                       (rx + sign * W * 0.15, ry + H * 0.09),
                       (rx - sign * W * 0.05, ry + H * 0.20)], fill=255)

    # A rune hanging over the gutter, pulsing.
    rr = W * (0.085 + 0.012 * beat)
    ry = cy - H * 0.40
    pts = []
    for i in range(8):
        ang = math.radians(-90 + i * 45)
        rad = rr if i % 2 == 0 else rr * 0.34
        pts.append((cx + math.cos(ang) * rad, ry + math.sin(ang) * rad))
    d.polygon(pts, fill=255)
    return img


def grimoire_facets(w, h, frame, frames):
    """The two page planes (one lit, one turned away), the gutter between them
    (darkest), and the boards under.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    left, right = _tome_pages(W, H)

    # Loose paper first (palest), then covered by everything else.
    d.rectangle([0, 0, W, H], fill=216)
    # The boards: dark leather under the paper.
    for pts in (left, right):
        d.polygon([(x + (W * 0.012 if x > cx else -W * 0.012), y + H * 0.030)
                   for x, y in pts], fill=72)
    # The left page catches the light; the right one is turned away from it.
    d.polygon(left, fill=200)
    d.polygon(right, fill=132)
    # The gutter, in shadow.
    d.rectangle([cx - W * 0.055, cy - H * 0.25, cx + W * 0.055, cy + H * 0.27],
                fill=76)
    return img.filter(ImageFilter.GaussianBlur(SS * 0.9))


def grimoire_cuts(w, h, frame, frames):
    """Text on the pages (ruled lines, since glyphs at this size are smudges),
    and the leaves stacked under each page.
    """
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0

    for sign in (-1, 1):
        for i in range(5):
            t = (i + 1) / 6.0
            y = cy - H * 0.17 + t * H * 0.36
            x0 = cx + sign * W * 0.075
            x1 = cx + sign * (W * 0.36 - W * 0.03 * i)
            d.line([(x0, y), (x1, y)], fill=210,
                   width=max(2, int(H * 0.011)))

    # The leaves in the block, along the outer edge of each page.
    for sign in (-1, 1):
        for i in range(4):
            x = cx + sign * (W * 0.40 - W * 0.011 * i)
            d.line([(x, cy - H * 0.10), (x, cy + H * 0.21)], fill=150,
                   width=max(2, int(W * 0.006)))

    # And the gutter itself, cut deep.
    d.rectangle([cx - W * 0.020, cy - H * 0.24, cx + W * 0.020, cy + H * 0.25],
                fill=255)
    return img


# ---------------------------------------------------------------------------
# The gem -- an octahedron, turning
# ---------------------------------------------------------------------------

def _gem_outline(W, H, frame, frames):
    cx, cy = W / 2.0, H / 2.0
    turn = 2 * math.pi * frame / frames
    half = W * 0.32 * abs(math.cos(turn)) + W * 0.085
    waist = H * 0.16
    return cx, cy, half, waist


def gem(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
        # Turning about its vertical axis: the silhouette narrows and swells.
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    d.polygon([(cx, cy - H * 0.42), (cx + half, cy - waist),
               (cx + half * 0.82, cy + waist), (cx, cy + H * 0.42),
               (cx - half * 0.82, cy + waist), (cx - half, cy - waist)],
              fill=255)
    return img


def gem_facets(w, h, frame, frames):
    """Six flat faces, each its own value: crown bright, girdle mid, pavilion
    dark, lit from the left.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    top = (cx, cy - H * 0.42)
    bot = (cx, cy + H * 0.42)
    l_up, r_up = (cx - half, cy - waist), (cx + half, cy - waist)
    l_dn = (cx - half * 0.82, cy + waist)
    r_dn = (cx + half * 0.82, cy + waist)
    mid_up, mid_dn = (cx, cy - waist * 0.4), (cx, cy + waist * 0.6)

    # Crown: two faces, the left one catching.
    d.polygon([top, l_up, mid_up], fill=218)
    d.polygon([top, r_up, mid_up], fill=152)
    # Girdle band.
    d.polygon([l_up, mid_up, mid_dn, l_dn], fill=175)
    d.polygon([r_up, mid_up, mid_dn, r_dn], fill=99)
    # Pavilion: darkest, because it is pointing away and down.
    d.polygon([l_dn, mid_dn, bot], fill=114)
    d.polygon([r_dn, mid_dn, bot], fill=61)
    # Barely blurred: facets meet at hard lines.
    return img.filter(ImageFilter.GaussianBlur(SS * 0.35))


def gem_cuts(w, h, frame, frames):
    """The grooves where facets meet, subtracted from the body."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy, half, waist = _gem_outline(W, H, frame, frames)
    wide = max(2, int(W * 0.010))
    d.line([(cx - half, cy - waist), (cx + half, cy - waist)], fill=255,
           width=wide)
    d.line([(cx - half * 0.82, cy + waist), (cx + half * 0.82, cy + waist)],
           fill=255, width=wide)
    d.line([(cx, cy - H * 0.42), (cx, cy + H * 0.42)], fill=190, width=wide)
    return img


# ---------------------------------------------------------------------------
# The sentry -- a carved mask that hangs in the air and watches
# ---------------------------------------------------------------------------

def _sentry_face(W, H):
    cx, cy = W / 2.0, H / 2.0
    return [(cx - W * 0.32, cy - H * 0.31), (cx + W * 0.32, cy - H * 0.31),
            (cx + W * 0.28, cy + H * 0.12), (cx, cy + H * 0.41),
            (cx - W * 0.28, cy + H * 0.12)]


def sentry(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    ph = 2 * math.pi * frame / frames

    d.polygon(_sentry_face(W, H), fill=255)
    # Horns.
    for sign in (-1, 1):
        d.polygon([(cx + sign * W * 0.25, cy - H * 0.29),
                   (cx + sign * W * 0.45, cy - H * 0.47),
                   (cx + sign * W * 0.33, cy - H * 0.18)], fill=255)
    # A collar under the chin.
    d.polygon([(cx - W * 0.22, cy + H * 0.20), (cx + W * 0.22, cy + H * 0.20),
               (cx + W * 0.15, cy + H * 0.36), (cx - W * 0.15, cy + H * 0.36)],
              fill=255)

    # Three orbiting shards.
    for i in range(3):
        ang = ph + i * 2 * math.pi / 3
        ox = cx + math.cos(ang) * W * 0.43
        oy = cy + math.sin(ang) * H * 0.25 + H * 0.06
        r = W * 0.052
        d.polygon([(ox, oy - r * 1.6), (ox + r, oy), (ox, oy + r * 1.6),
                   (ox - r, oy)], fill=255)
    return img


def sentry_facets(w, h, frame, frames):
    """The carved planes of the mask (brow, cheeks, nose, jaw), lit from the
    upper left.
    """
    img, d = _facets(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0

    # The brow, overhanging: the brightest part of the face.
    d.polygon([(cx - W * 0.32, cy - H * 0.31), (cx + W * 0.32, cy - H * 0.31),
               (cx + W * 0.30, cy - H * 0.14), (cx - W * 0.30, cy - H * 0.14)],
              fill=213)
    # Cheeks: the left one turned toward the light, the right away from it.
    d.polygon([(cx - W * 0.30, cy - H * 0.14), (cx, cy - H * 0.08),
               (cx, cy + H * 0.38), (cx - W * 0.28, cy + H * 0.11)], fill=163)
    d.polygon([(cx + W * 0.30, cy - H * 0.14), (cx, cy - H * 0.08),
               (cx, cy + H * 0.38), (cx + W * 0.28, cy + H * 0.11)], fill=87)
    # The nose ridge down the middle, catching.
    d.polygon([(cx - W * 0.045, cy - H * 0.12), (cx + W * 0.045, cy - H * 0.12),
               (cx + W * 0.03, cy + H * 0.14), (cx - W * 0.03, cy + H * 0.14)],
              fill=218)
    # The collar, in shadow under the jaw.
    d.polygon([(cx - W * 0.22, cy + H * 0.20), (cx + W * 0.22, cy + H * 0.20),
               (cx + W * 0.15, cy + H * 0.36), (cx - W * 0.15, cy + H * 0.36)],
              fill=68)
    return img.filter(ImageFilter.GaussianBlur(SS * 0.9))


def sentry_cuts(w, h, frame, frames):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    # Two eye slots and a mouth, cut through.
    for sign in (-1, 1):
        d.polygon([(cx + sign * W * 0.07, cy - H * 0.14),
                   (cx + sign * W * 0.24, cy - H * 0.18),
                   (cx + sign * W * 0.23, cy - H * 0.06),
                   (cx + sign * W * 0.08, cy - H * 0.04)], fill=255)
    d.rectangle([cx - W * 0.12, cy + H * 0.09, cx + W * 0.12, cy + H * 0.15],
                fill=255)
    # Weathering: chips along the brow and a split down one cheek.
    rnd = np.random.default_rng(5)
    for _ in range(7):
        ex = rnd.uniform(cx - W * 0.28, cx + W * 0.28)
        ey = rnd.uniform(cy - H * 0.26, cy + H * 0.16)
        er = rnd.uniform(W * 0.012, W * 0.030)
        d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=120)
    d.line([(cx + W * 0.14, cy - H * 0.24), (cx + W * 0.19, cy + H * 0.06)],
           fill=150, width=max(2, int(W * 0.008)))
    return img


# ---------------------------------------------------------------------------
# The four shapes. Their hit radii are in `enemy_radius` and must be updated if
# these sizes change.
# ---------------------------------------------------------------------------

SHAPES = [
    # name                w    h  frames  body       facets          cuts
    ("spr_foe_wisp",      88, 112, 4, wisp,      wisp_facets,     wisp_cuts),
    ("spr_foe_grimoire", 130, 116, 4, grimoire,  grimoire_facets, grimoire_cuts),
    ("spr_foe_gem",       94, 100, 6, gem,       gem_facets,      gem_cuts),
    ("spr_foe_sentry",   136, 130, 4, sentry,    sentry_facets,   sentry_cuts),
]


def build(spec):
    name, w, h, frames, body_fn, facet_fn, cut_fn = spec
    out = []
    for f in range(frames):
        mask = body_fn(w, h, f, frames)
        # A smaller white core than a bullet's: the tint multiply can only
        # colour what isn't already white.
        img = A.shade_shape(mask, PALE, core_frac=0.30, edge_frac=0.40,
                            halo=0.30)
        arr = np.asarray(img, dtype=np.float32)

        if facet_fn is not None:
            # Planes, multiplied in (FACET_NEUTRAL leaves the depth shading
            # unchanged where the facet map doesn't paint).
            fac = np.asarray(facet_fn(w, h, f, frames),
                             dtype=np.float32) / FACET_NEUTRAL
            arr[..., :3] *= np.minimum(fac, FACET_MAX)[..., None]

        if cut_fn is not None:
            # The grooves darken the body rather than cutting holes in it.
            cut = np.asarray(
                cut_fn(w, h, f, frames).filter(ImageFilter.GaussianBlur(SS * 0.6)),
                dtype=np.float32) / 255.0
            arr[..., :3] *= (1 - cut[..., None] * 0.74)

        # Grain at two scales.
        g1 = np.asarray(A.fbm_field(arr.shape[1], arr.shape[0], hash(name) % 9973,
                                    octaves=3, base=26), dtype=np.float32) / 255.0
        g2 = np.asarray(A.fbm_field(arr.shape[1], arr.shape[0],
                                    hash(name) % 9973 + 71, octaves=2, base=90),
                        dtype=np.float32) / 255.0
        arr[..., :3] *= (0.90 + 0.14 * g1 + 0.08 * g2)[..., None]

        img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        out.append(_contoured(img.resize((w, h), Image.LANCZOS)))
    return out


def _contoured(small):
    """The dark ring, traced at final size around the body (not the halo); as
    `make_bullets._contoured`.
    """
    solid = small.getchannel("A").point(lambda v: 255 if v >= 150 else 0)
    body = small.copy()
    body.putalpha(solid)
    ring = A.trace_outline(body, width=CONTOUR, colour=(0, 0, 0, 230))
    ring = ring.filter(ImageFilter.GaussianBlur(0.55))
    return A.over(ring, small)


def main():
    gm_new.folder("Sprites/foes")

    shown = []
    labels = []
    for spec in SHAPES:
        frames = build(spec)
        gm_new.sprite(spec[0], frames, origin="center", folder="Sprites/foes",
                      fps=10.0)
        for i, f in enumerate(frames):
            shown.append(f)
            labels.append(spec[0].replace("spr_foe_", "") if i == 0 else "")
        print("%-18s %d frames of %dx%d" % (spec[0], len(frames),
                                            spec[1], spec[2]))

    # Previewed tinted, as they appear in game.
    tinted = []
    for _name, col in (("crimson", A.hue("crimson")), ("jade", A.hue("jade")),
                       ("violet", A.hue("violet"))):
        for spec in SHAPES:
            f = build(spec)[0]
            arr = np.asarray(f, dtype=np.float32)
            arr[..., :3] *= np.array(col, dtype=np.float32) / 255.0
            tinted.append(Image.fromarray(arr.astype(np.uint8), "RGBA"))

    A.preview(shown + tinted, os.path.join(A.PREVIEW, "foes.png"),
              cols=6, bg=(22, 24, 36))


if __name__ == "__main__":
    main()
