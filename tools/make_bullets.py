#!/usr/bin/env python3
"""Generate every bullet sprite, and the table the engine reads them through.

**One sprite per shape, one frame per colour.** Eighteen shapes across fourteen
hues is 252 combinations, and 252 GameMaker sprites would be 252 `.yy` files,
252 entries in the `.yyp`, and a texture atlas nobody could reason about. So a
shape is one sprite whose frames are its colours, and drawing a bullet is
`draw_sprite_ext(spr, colour, ...)`. Animated shapes fold both axes into the
one index: `frame = colour * frames + tick`, which `bullet_frame` in
`danmaku_functions` is the only thing allowed to compute.

**Oriented shapes point RIGHT at angle zero**, because GameMaker's `direction`
0 is right and `image_angle` is measured the same way. Drawing them pointing up
-- which is how a Touhou sheet is usually laid out -- would mean every draw
call carrying a `- 90`, and the one that forgets it is a bullet that is
visually sideways while being mechanically correct, which is the worst kind of
bug to look at.

**This file is the single source of truth for a bullet's hit radius**, not just
its picture, and it writes `scripts/bullet_table/bullet_table.gml` to say so.
The radius and the sprite have to agree -- a 36px ball with an 11px radius is a
promise about where the player may fly, and if the number lived in GML while
the picture lived here the two would be edited apart within a week. The flame
is the case that proves it: it is 30x46 of picture and 7 of hitbox, because the
tail is not the bullet.

Usage:
    python tools/make_bullets.py          # -> sprites + bullet_table.gml
    python tools/make_bullets.py --preview-only
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


# ---------------------------------------------------------------------------
# Masks. Every one draws at SS resolution into an L image, and every oriented
# one points right.
# ---------------------------------------------------------------------------

def _mask(w, h):
    img = Image.new("L", (int(w * SS), int(h * SS)), 0)
    return img, ImageDraw.Draw(img)


def m_disc(w, h, inset=0.0, **_):
    img, d = _mask(w, h)
    p = inset * SS
    d.ellipse([p, p, img.width - 1 - p, img.height - 1 - p], fill=255)
    return img


def m_ring(w, h, inset=0.0, thick=0.30, **_):
    img, d = _mask(w, h)
    p = inset * SS
    d.ellipse([p, p, img.width - 1 - p, img.height - 1 - p], fill=255)
    q = p + min(img.width, img.height) * thick
    d.ellipse([q, q, img.width - 1 - q, img.height - 1 - q], fill=0)
    return img


def m_dart(w, h, inset=0.0, **_):
    """A kunai: a chevron head on a short shaft, pointing right.

    Drawn as a chevron rather than a filled triangle because a triangle at
    30x20 reads as a wedge of colour and a chevron reads as an arrow -- the
    notch at the back is the whole of the difference, and it is the only part
    of the silhouette that survives being 20 pixels tall.
    """
    img, d = _mask(w, h)
    p = inset * SS
    W, H = img.width - 1 - p, img.height - 1 - p
    cy = (H + p) / 2.0
    shaft = (H - p) * 0.17
    d.polygon([(p, cy - shaft), (W * 0.62, cy - shaft),
               (W * 0.62, cy + shaft), (p, cy + shaft)], fill=255)
    d.polygon([(W, cy), (W * 0.44, p), (W * 0.58, cy), (W * 0.44, H)],
              fill=255)
    return img


def m_needle(w, h, inset=0.0, **_):
    """A lens: two arcs meeting in a point at each end."""
    img, d = _mask(w, h)
    W, H = img.width - 1 - inset * SS, img.height - 1
    p = inset * SS
    pts = []
    n = 40
    for i in range(n + 1):
        t = i / n
        x = p + (W - p) * t
        pts.append((x, H / 2.0 - (H / 2.0 - p) * math.sin(math.pi * t) ** 0.62))
    for i in range(n, -1, -1):
        t = i / n
        x = p + (W - p) * t
        pts.append((x, H / 2.0 + (H / 2.0 - p) * math.sin(math.pi * t) ** 0.62))
    d.polygon(pts, fill=255)
    return img


def m_card(w, h, inset=0.0, **_):
    """An ofuda: a paper strip, clipped at the leading corners."""
    img, d = _mask(w, h)
    p = inset * SS
    W, H = img.width - 1 - p, img.height - 1 - p
    cut = (H - p) * 0.30
    d.polygon([(W - cut, p), (W, p + cut), (W, H - cut), (W - cut, H),
               (p, H), (p, p)], fill=255)
    return img


def m_star(w, h, points=5, inner=0.45, inset=0.0, turn=-90.0, **_):
    img, d = _mask(w, h)
    cx, cy = (img.width - 1) / 2.0, (img.height - 1) / 2.0
    R = min(cx, cy) - inset * SS
    pts = []
    for i in range(points * 2):
        ang = math.radians(turn + i * 180.0 / points)
        rad = R if i % 2 == 0 else R * inner
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    d.polygon(pts, fill=255)
    return img


def m_crystal(w, h, inset=0.0, **_):
    """A cut gem, elongated along its travel."""
    img, d = _mask(w, h)
    p = inset * SS
    W, H = img.width - 1 - p, img.height - 1 - p
    cy = (H + p) / 2.0
    d.polygon([(W, cy), (W * 0.66, p), (p + W * 0.20, p),
               (p, cy), (p + W * 0.20, H), (W * 0.66, H)], fill=255)
    return img


def m_heart(w, h, inset=0.0, **_):
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    p = inset * SS
    r = (W - 2 * p) / 4.0
    d.ellipse([p, p + H * 0.06, p + 2 * r, p + H * 0.06 + 2 * r], fill=255)
    d.ellipse([W - p - 2 * r, p + H * 0.06, W - p, p + H * 0.06 + 2 * r],
              fill=255)
    d.polygon([(p + r * 0.16, H * 0.44), (W / 2.0, H - p),
               (W - p - r * 0.16, H * 0.44)], fill=255)
    return img


def m_butterfly(w, h, frame=0, frames=4, inset=0.0, **_):
    """Wings that beat. Oriented, so the body runs left-to-right."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    cx, cy = W / 2.0, H / 2.0
    # 0 is fully open, 1 fully closed; a beat is a full there-and-back.
    beat = abs(math.sin(math.pi * frame / frames))
    spread = 1.0 - 0.58 * beat
    # **The waist is what makes it a butterfly.** Wings that meet on the centre
    # line fuse into one blob at 34 pixels wide, whatever shape they are; held
    # off it by a hair, with the body drawn between, the silhouette has a pinch
    # in the middle and the eye reads two pairs of wings.
    # **One swept wing per side, not a forewing and a hindwing.** Four lobes is
    # what a butterfly has and four lobes at 34 pixels wide is a blob with
    # notches in it -- the gaps between them are sub-pixel after the downsample,
    # so all the detail buys is a ragged silhouette. One wing per side keeps the
    # outline readable and the beat is still legible, because what animates is
    # the span rather than the count.
    gap = H * 0.04
    for sign in (-1, 1):
        root = cy + sign * gap
        d.polygon([(cx + W * 0.26, root),
                   (cx - W * 0.08, root + sign * H * 0.46 * spread),
                   (cx - W * 0.42, root + sign * H * 0.13 * spread),
                   (cx - W * 0.18, root)], fill=255)
    d.ellipse([cx - W * 0.30, cy - H * 0.08, cx + W * 0.36, cy + H * 0.08],
              fill=255)
    return img


def m_flame(w, h, frame=0, frames=4, inset=0.0, **_):
    """A head with a tail streaming *behind* it -- so it points right, and the
    tail is to the left. The head is the whole of the hitbox."""
    img, d = _mask(w, h)
    W, H = img.width - 1, img.height - 1
    head_r = H * 0.30
    hx, hy = W - head_r - inset * SS, H / 2.0
    d.ellipse([hx - head_r, hy - head_r, hx + head_r, hy + head_r], fill=255)

    wob = math.sin(2 * math.pi * frame / frames)
    n = 28
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        x = hx - t * (hx - inset * SS)
        thick = head_r * (1.0 - t) ** 0.72
        sway = math.sin(t * 5.0 + wob * 2.2) * H * 0.12 * t
        top.append((x, hy + sway - thick))
        bot.append((x, hy + sway + thick))
    d.polygon(top + bot[::-1], fill=255)
    return img


def m_mote(w, h, frame=0, frames=4, inset=0.0, **_):
    """A four-point sparkle that pulses. The wisps' ammunition."""
    img, d = _mask(w, h)
    cx, cy = (img.width - 1) / 2.0, (img.height - 1) / 2.0
    R = min(cx, cy) - inset * SS
    puls = 0.82 + 0.18 * math.cos(2 * math.pi * frame / frames)
    for turn in (-90.0, -45.0):
        arm = R * (1.0 if turn == -90.0 else 0.62) * puls
        pts = []
        for i in range(8):
            ang = math.radians(turn + i * 45.0)
            rad = arm if i % 2 == 0 else arm * 0.22
            pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
        d.polygon(pts, fill=255)
    d.ellipse([cx - R * 0.26, cy - R * 0.26, cx + R * 0.26, cy + R * 0.26],
              fill=255)
    return img


# ---------------------------------------------------------------------------
# The catalogue
#
# w/h are the FINAL sprite size and include the margin the halo needs; `hit` is
# the radius the engine collides with and is a property of the drawn body, not
# of the canvas. `round` shapes go through `orb_field`, which has a specular
# and a halo tuned in closed form; everything else goes through `shade_shape`.
# ---------------------------------------------------------------------------

# **Half again the size the first version of this table was, and the reason is
# a screenshot.** The stage's background carries drifting embers -- additive
# orange blobs a few pixels across -- and at 14 pixels the pellet was the same
# object: same size, same hue, same soft edge. A player cannot be asked to tell
# an obstacle from scenery by *watching which one moves*, so the bullets grew
# until they were unmistakably a different class of thing. `CONTOUR` below is
# the other half of that fix and the more important one.
#
# **The hitboxes grew by less than the pictures did** -- about a third against
# a half -- because the picture's job is to be seen and the hitbox's job is to
# be fair. Growing them together would have made a legibility fix into a
# difficulty change, which is not what was asked for.
SHAPES = [
    # name        w   h  hit  orient frames  mask          kwargs
    ("pellet",    24, 24, 4.2, False, 1, None,        dict(radius=0.64, core_at=0.30, glow=0.30)),
    ("orb",       34, 34, 7.0, False, 1, None,        dict(radius=0.74, core_at=0.34, glow=0.22)),
    ("ball",      54, 54, 15.0, False, 1, None,       dict(radius=0.80, core_at=0.36, glow=0.16)),
    ("sphere",    88, 88, 29.0, False, 1, None,       dict(radius=0.84, core_at=0.40, glow=0.12)),
    ("ring",      46, 46, 12.5, False, 1, m_ring,     dict(inset=2.0, thick=0.21)),
    ("bubble",    76, 76, 26.0, False, 1, m_ring,     dict(inset=3.0, thick=0.15)),
    ("rice",      34, 22, 5.6, True,  1, m_disc,      dict(inset=2.0)),
    ("oval",      48, 30, 9.0, True,  1, m_disc,      dict(inset=3.0)),
    ("dart",      46, 30, 7.6, True,  1, m_dart,      dict(inset=2.0)),
    ("needle",    64, 18, 5.6, True,  1, m_needle,    dict(inset=1.5)),
    ("card",      46, 30, 9.0, True,  1, m_card,      dict(inset=3.0)),
    ("star",      44, 44, 10.5, False, 1, m_star,     dict(inset=3.0, points=5, inner=0.44)),
    ("star6",     54, 54, 14.0, False, 1, m_star,     dict(inset=3.5, points=6, inner=0.54)),
    ("crystal",   44, 32, 9.0, True,  1, m_crystal,   dict(inset=3.0)),
    ("heart",     42, 38, 10.5, False, 1, m_heart,    dict(inset=3.0)),
    ("butterfly", 58, 48, 10.5, True,  4, m_butterfly, dict(inset=3.0)),
    ("flame",     66, 42, 9.5, True,  4, m_flame,     dict(inset=3.0)),
    ("mote",      30, 30, 5.6, False, 4, m_mote,      dict(inset=1.5)),
]

# How thick a dark contour every bullet is traced with, in final pixels.
#
# **This is the single thing that separates a bullet from a light.** Everything
# else on this screen that is small, round and orange -- a background ember, a
# graze spark, the halo under an enemy -- is drawn *additively*, and additive
# light has no edge by construction: it can only ever make what is behind it
# brighter. A hard dark ring is therefore a mark nothing in the scenery is able
# to produce, and a shape wearing one reads as an object sitting in front of
# the world rather than as a light shining out of it.
#
# It doubles as the guarantee `trace_outline` was written for and never wired
# up to: a bullet drawn over a spell background of its own colour has nothing
# but this ring to be seen by, and a boss picks its own background.
CONTOUR = 2.0

# The flame's hitbox is its head, and the head is at the right-hand end. The
# origin has to sit on the hitbox or the bullet pivots about its tail, which
# looks like a bullet that swings when it turns. Anything not named here is
# centred.
ORIGINS = {
    "flame": lambda w, h: (int(w - h * 0.30 - 2), h // 2),
}


def build_shape(spec):
    """Every frame of one shape: colours outermost, animation innermost."""
    name, w, h, _hit, _orient, frames, mask_fn, kw = spec
    out = []
    for _, rim in A.BULLET_HUES:
        for f in range(frames):
            if mask_fn is None:
                img = A.orb_field(w * SS, rim, **kw)
                # orb_field is square; a round bullet always is.
                assert w == h, "round shape %s must be square" % name
            else:
                mask = mask_fn(w, h, frame=f, frames=frames, **kw)
                img = A.shade_shape(mask, rim, halo=0.45)
            out.append(_contoured(img, w, h))
    return out


def _contoured(img, w, h):
    """Downsample one bullet and lay the dark contour round its body.

    **Traced at the final size, not at SS and shrunk with everything else.** A
    two-pixel ring drawn at four times scale and resized is a two-pixel ring at
    a quarter of its alpha, which over a bright background is not a contour but
    a smudge -- being crisp at 1x is the whole of what makes it read as an edge
    rather than as more glow.

    **And traced around the body rather than around the alpha.** Every bullet
    here carries a soft halo -- `glow` on the round ones, `halo` on the rest --
    so its alpha channel does not end at the silhouette, it trails off over
    several pixels. `trace_outline` run on that draws a ring around the *fog*,
    which is both in the wrong place and too faint to see. Thresholding first
    recovers the shape the halo is hanging off, which is the thing the eye
    reads as the bullet.

    The ring goes *under* the body, so it occupies the pixels outside the
    silhouette rather than eating into it. Over the top it would take a bite
    out of the saturated rim -- the one band carrying the hue -- and fourteen
    colours would come back looking like three.
    """
    small = img.resize((w, h), Image.LANCZOS)
    solid = small.getchannel("A").point(lambda v: 255 if v >= 150 else 0)
    body = small.copy()
    body.putalpha(solid)
    ring = A.trace_outline(body, width=CONTOUR, colour=(0, 0, 0, 235))
    ring = ring.filter(ImageFilter.GaussianBlur(0.55))
    return A.over(ring, small)


def main():
    preview_only = "--preview-only" in sys.argv

    sheets = []
    labels = []
    table = []

    for spec in SHAPES:
        name, w, h, hit, orient, frames, _fn, _kw = spec
        images = build_shape(spec)
        sprite = "spr_bul_%s" % name

        if not preview_only:
            origin = ORIGINS.get(name, lambda a, b: "center")(w, h)
            gm_new.sprite(sprite, images, origin=origin,
                          folder="Sprites/bullets", fps=1.0)

        table.append((name, sprite, hit, orient, frames, w, h))

        # One row of the preview per shape: every hue, first animation frame.
        for i, (hue_name, _) in enumerate(A.BULLET_HUES):
            sheets.append(images[i * frames])
            labels.append("%s/%s" % (name, hue_name) if i == 0 else hue_name)

    A.preview(sheets, os.path.join(A.PREVIEW, "bullets.png"),
              cols=len(A.BULLET_HUES), bg=(18, 20, 30))

    # ...and the same again over a bright, busy ground, because the whole point
    # of the core-inside-rim rule is that a bullet reads against *both*, and a
    # sheet on black only ever proves half of it.
    bright = _bright_ground(sheets, len(A.BULLET_HUES))
    bright.save(os.path.join(A.PREVIEW, "bullets_bright.png"))

    if not preview_only:
        write_table(table)
    print("bullets: %d shapes x %d hues -> %d frames"
          % (len(SHAPES), len(A.BULLET_HUES), sum(len(build_shape(s)) for s in SHAPES)))


def _bright_ground(images, cols, pad=10):
    """The preview again over something a bullet could get lost in."""
    rows = (len(images) + cols - 1) // cols
    cw = max(i.width for i in images)
    ch = max(i.height for i in images)
    w = cols * (cw + pad) + pad
    h = rows * (ch + pad) + pad

    field = A.fbm_field(w, h, seed=7, octaves=5, base=5)
    arr = np.asarray(field, dtype=np.float32)[..., None] / 255.0
    warm = np.array([210, 150, 90], dtype=np.float32)
    cool = np.array([120, 190, 210], dtype=np.float32)
    sheet = A.from_arrays(warm * arr + cool * (1 - arr),
                          np.ones((h, w), dtype=np.float32))

    for i, img in enumerate(images):
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (ch + pad)
        sheet.alpha_composite(img, (x + (cw - img.width) // 2,
                                    y + (ch - img.height) // 2))
    return sheet


TABLE_HEADER = '''/// @desc The bullet catalogue -- GENERATED by tools/make_bullets.py.
///
/// **Do not edit this file.** A bullet's hit radius and its picture have to
/// agree, and the picture is drawn in Python; a radius maintained by hand here
/// would drift from the sprite it describes within a week. Change
/// `tools/make_bullets.py` and re-run it.
///
/// A shape is one sprite whose frames are its colours. An animated shape folds
/// both axes into the one index, and `bullet_frame` is the only thing allowed
/// to compute it.

'''


def write_table(table):
    lines = [TABLE_HEADER]

    for i, (name, _spr, _hit, _o, _f, _w, _h) in enumerate(table):
        lines.append("#macro BSHAPE_%s %d" % (name.upper(), i))
    lines.append("#macro BSHAPE_COUNT %d" % len(table))
    lines.append("")

    for i, (name, _) in enumerate(A.BULLET_HUES):
        lines.append("#macro BCOL_%s %d" % (name.upper(), i))
    lines.append("#macro BCOL_COUNT %d" % len(A.BULLET_HUES))
    lines.append("")

    lines.append("/// @desc Fill in the shape table. Called once, from obj_boot.")
    lines.append("function bullet_table_init() {")
    lines.append("    global.bshape_sprite = [")
    for name, spr, _h, _o, _f, _w, _hh in table:
        lines.append("        %s," % spr)
    lines.append("    ];")

    for field, idx, fmt in (("radius", 2, "%s"), ("oriented", 3, "%s"),
                            ("frames", 4, "%d"), ("w", 5, "%d"), ("h", 6, "%d")):
        lines.append("    global.bshape_%s = [" % field)
        row = []
        for rec in table:
            v = rec[idx]
            if field == "oriented":
                row.append("true" if v else "false")
            elif field == "radius":
                row.append("%.1f" % v)
            else:
                row.append("%d" % v)
        lines.append("        " + ", ".join(row) + ",")
        lines.append("    ];")

    lines.append("}")
    lines.append("")

    path = os.path.join(A.ROOT, "scripts", "bullet_table", "bullet_table.gml")
    gm_new.write(path, "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
