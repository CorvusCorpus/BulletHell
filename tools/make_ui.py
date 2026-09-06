#!/usr/bin/env python3
"""The furniture the HUD is built out of: filigree, rules, marks and material.

**Everything here is drawn white and tinted at draw time**, exactly as the
fodder sprites are. The console is one colour today and will be another when a
stage in a vampire's hall wants cold silver instead of warm iron, and a set of
ornaments baked in one hue is a set that has to be regenerated per stage. What
survives tinting is *structure* -- a bright edge, a dark groove, a highlight
that sits on one side of a line -- so every shape here is built out of value
rather than out of colour, and the alpha channel is the whole of the art.

Why any of it is art at all
---------------------------

The console this replaces was drawn entirely from GML primitives: rectangles,
one-pixel rules and a roundrect. Photographed at 1:1 that is exactly what it
looked like -- a grey nothing beside a picture -- and it is the same finding
`make_bg.py` records about the first version of the stage. Primitives are fine
for anything whose shape is a fact (a bar's length *is* the number), and they
cannot do the one thing chrome has to: read as a made object, cut from a
material, by somebody who cared.

So the split is: **anything that carries a value is a primitive, and anything
that carries a style is a sprite.** The gauge bodies, the rules' straight runs
and the panel's flat ground are drawn in GML because they stretch to fit; the
corner pieces, the divider ornaments and the attack marks are drawn here
because they are shapes, and a shape drawn with `draw_rectangle` is a shape
that looks drawn with `draw_rectangle`.

**None of it is bright.** The console sits beside a playfield carrying two
thousand lit bullets, and every point of value spent on furniture is a point
the bullets no longer have -- the same budget `make_bg.py` spends the rock out
of. The ornaments are tinted to `COL_SLATE` at draw time and mostly land under
a fifth of full brightness; what makes them read at all is that they have a
*lit edge and a dark one*, which the eye completes into relief.

Usage:
    python tools/make_ui.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

PREVIEW = os.path.join(A.PREVIEW, "ui.png")

# The ornaments are drawn in white and tinted, so these are *values* rather
# than colours: how bright the lit face of an engraved line is, how dark its
# shadowed face is, and what the flat of the metal sits at.
LIT = 255
FACE = 150
DARK = 64


def _alpha_only(img):
    """Force a layer to pure white ink, keeping its alpha.

    Every ornament is tinted with `draw_sprite_ext`'s blend colour, which
    *multiplies*. A shape drawn at 60% grey therefore tints to 60% of the
    requested colour and no call site can get it back, so the value has to live
    in the alpha channel and nowhere else. Drawing in greys and converting here
    is much easier to author than drawing in alpha directly, and this is the
    one line that keeps the two honest.
    """
    r, g, b, a = img.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    # value * coverage: a mid-grey pixel at full coverage becomes a white pixel
    # at half coverage, which is the same thing once it is being tinted.
    out = Image.new("RGBA", img.size, (255, 255, 255, 0))
    out.putalpha(Image.fromarray(
        (np.asarray(lum, dtype=np.float32)
         * np.asarray(a, dtype=np.float32) / 255.0).astype(np.uint8), "L"))
    return out


# ---------------------------------------------------------------------------
# The corner
# ---------------------------------------------------------------------------

def _taper(c, x, y, dx, dy, length, w0, w1, a0, a1, v, steps=160):
    """A bar along one axis that changes width and fades as it goes.

    **Built out of thin quads rather than out of dots.** The first version of
    the corner walked a circle along each arm, and at 26 steps over 92 pixels
    the circles did not overlap: what came back was a string of beads. Stepping
    finely enough to overlap is one fix and the wrong one -- it makes the arm's
    edge scalloped instead of dotted. A quad per step has a straight edge by
    construction, and 160 of them over 92 pixels at SS=4 is a solid taper.
    """
    px, py = -dy, dx                    # the perpendicular
    for t in range(steps):
        f = t / (steps - 1.0)
        f2 = (t + 1.2) / (steps - 1.0)
        w = (w0 + (w1 - w0) * f) * 0.5
        a = int(a0 + (a1 - a0) * f)
        if a <= 2:
            continue
        ax, ay = x + dx * length * f, y + dy * length * f
        bx, by = x + dx * length * f2, y + dy * length * f2
        c.polygon([(ax - px * w, ay - py * w), (bx - px * w, by - py * w),
                   (bx + px * w, by + py * w), (ax + px * w, ay + py * w)],
                  fill=(v, v, v, a))


def _scroll(c, x, y, r, turns, a0, width, v, alpha, steps=90, taper=True):
    """A volute: a line spiralling inward, thinning as it goes.

    **This is the one shape that says "made by hand".** A frame built out of
    straight runs and right angles reads as a border no matter how many studs
    are on it; a curve that tightens is a thing somebody drew. Gilt bookbinding
    is almost entirely volutes, and so is the corner ornament on every fantasy
    interface worth stealing from.

    It failed once as a *full* spiral, which at 132 pixels is a letter -- it
    read as a P. What makes it read as ornament instead is stopping at about
    three quarters of a turn and letting it taper to nothing: an open curl is a
    flourish, a closed one is a glyph.
    """
    prev = None
    for i in range(steps):
        f = i / (steps - 1.0)
        ang = math.radians(a0 + f * turns * 360)
        rad = r * (1.0 - f * 0.82)
        px = x + math.cos(ang) * rad
        py = y + math.sin(ang) * rad
        if prev is not None:
            w = width * (1.0 - f * 0.7) if taper else width
            c.line([prev, (px, py)], fill=(v, v, v, alpha), width=max(0.6, w))
        prev = (px, py)


def _star4(c, x, y, r, v, alpha, waist=0.16):
    """A four-pointed sparkle. The one celestial mark that reads at 12 pixels.

    Six- and eight-pointed stars need size to be told apart from a blob; four
    points with a tight waist is unmistakable at any scale, which is why every
    piece of magical interface art in the last decade uses it.
    """
    pts = []
    for i in range(8):
        ang = math.radians(i * 45 - 90)
        rr = r if i % 2 == 0 else r * waist
        pts.append((x + math.cos(ang) * rr, y + math.sin(ang) * rr))
    c.polygon(pts, fill=(v, v, v, alpha))


def corner(size=132):
    """One top-left corner piece: a gilded volute over a mitred bracket.

    **It is drawn for one orientation and used at four**, flipped rather than
    redrawn, which is what keeps the four corners of a frame identical -- an
    ornament whose four corners are subtly different reads as four ornaments.

    The shape is a bracket first and a flourish second. A frame's corner has a
    job: it says the two rules meeting there are one object rather than two
    lines that happen to cross. So the heavy part is the L and the chamfer, and
    the volutes and the set stone are what stop it being a right angle.

    **The first version was only the bracket, and it read as a border rather
    than as goldwork.** What separates gilt filigree from a mitred frame is
    curvature: straight runs and studs say *machined*, and a volute that
    tightens as it goes says somebody drew it. There are two here, one off each
    arm, plus a four-pointed star where the light catches.
    """
    c = A.Canvas(size, size)
    o = 11.0                            # how far the outer rule sits in
    chamfer = 26.0                      # where the 45-degree cut crosses

    # The two heavy arms, starting past the chamfer and running out to nothing.
    for dx, dy in ((1, 0), (0, 1)):
        sx = o + dx * chamfer
        sy = o + dy * chamfer
        _taper(c, sx, sy, dx, dy, size - o - chamfer - 6,
               5.0, 1.2, 235, 0, FACE + 30)

    # The chamfer itself: the corner cut off at 45 degrees, heavier than the
    # arms it joins so the elbow reads as cast rather than as mitred tape.
    d = 1.0 / math.sqrt(2.0)
    _taper(c, o + d * 2.4, o + chamfer - d * 2.4, d, -d,
           chamfer * math.sqrt(2.0) - 4.8, 5.6, 5.6, 245, 245, FACE + 40)

    # A lit hairline inboard of everything, at a constant offset -- which is
    # what turns two grey stripes into a bevelled edge. It runs about half the
    # length of the arms and stops, because a second full-length rule is just a
    # thicker first one.
    inset = 9.5
    run = (size - o - chamfer) * 0.52
    _taper(c, o + chamfer + 3, o + inset, 1, 0, run, 1.3, 1.0, 150, 0, LIT)
    _taper(c, o + inset, o + chamfer + 3, 0, 1, run, 1.3, 1.0, 150, 0, LIT)

    # The volutes. One curling off each arm, inward, mirrored about the
    # chamfer's axis so the piece is symmetrical about its own diagonal --
    # which is what lets one drawing serve four corners without any of them
    # looking like it is leaning.
    _scroll(c, o + 40, o + 22, 13.0, 0.72, 155, 2.6, FACE + 30, 255)
    _scroll(c, o + 22, o + 40, 13.0, -0.72, -65, 2.6, FACE + 30, 255)

    # Two smaller curls further out, so the ornament thins along the arm
    # instead of stopping. Ornament that stops dead reads as damage.
    _scroll(c, o + 74, o + 17, 7.0, 0.6, 150, 1.7, FACE, 220)
    _scroll(c, o + 17, o + 74, 7.0, -0.6, -60, 1.7, FACE, 220)

    # A four-pointed catch of light out along each arm.
    _star4(c, o + 58, o + 19, 5.4, LIT, 210)
    _star4(c, o + 19, o + 58, 5.4, LIT, 210)

    # The set stone, on the chamfer's own axis. Dark surround, bright centre --
    # the one place on the piece with real contrast.
    mid = o + chamfer * 0.5
    for r, v, a in ((10.0, DARK, 255), (7.0, FACE, 255), (3.6, LIT, 255)):
        c.polygon([(mid, mid - r), (mid + r, mid), (mid, mid + r),
                   (mid - r, mid)], fill=(v, v, v, a))

    img = _alpha_only(c.finish())
    # One small blur so the piece is engraved rather than plotted. It is drawn
    # at four times size and lands on Lanczos already; this softens the last of
    # the hard edges the quad joints leave.
    return img.filter(ImageFilter.GaussianBlur(0.45))


def rule(w=416, h=30):
    """A section divider: a crescent moon between two tapering hairlines.

    **It fades out at both ends rather than stopping.** A rule with hard ends
    is a rule that has to be positioned to the pixel against whatever is beside
    it; one that fades is right wherever it is put, which is what a HUD wants
    of a piece used at four widths.

    The lozenge in the middle became a crescent because a lozenge is a shape
    and a crescent is a *motif* -- it belongs to the same family as the stars
    in the fascia and the moon over the console's head, and a set of ornaments
    that share a vocabulary reads as designed where a set of neutral geometry
    reads as assembled.
    """
    c = A.Canvas(w, h)
    cy = h / 2.0

    # The line itself, in two values: a bright run and a shadow under it.
    steps = 240
    for t in range(steps):
        f = t / (steps - 1.0)
        x = f * w
        # Zero at both ends, and hollowed in the middle where the motif is.
        edge = math.sin(math.pi * f) ** 0.55
        gap = min(1.0, abs(f - 0.5) / 0.085)
        a = int(215 * edge * gap)
        if a <= 2:
            continue
        c.rect((x, cy - 0.5, x + w / steps + 0.6, cy + 0.5),
               fill=(FACE + 45, FACE + 45, FACE + 45, a))
        c.rect((x, cy + 0.5, x + w / steps + 0.6, cy + 1.4),
               fill=(DARK, DARK, DARK, int(a * 0.8)))

    # The crescent: a disc with a second disc bitten out of it. Drawn on its
    # own layer so the bite can be a true hole rather than a fill of whatever
    # happens to be behind.
    r = h * 0.30
    cx = w / 2.0
    moon = A.new_layer(c)
    md = A.layer_draw(moon)
    s = c.ss
    md.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s],
               fill=(FACE + 60, FACE + 60, FACE + 60, 255))
    md.ellipse([(cx - r * 0.32) * s, (cy - r * 1.05) * s,
                (cx + r * 1.7) * s, (cy + r * 1.05) * s], fill=(0, 0, 0, 0))
    c.paste_full(moon)

    # Two four-pointed sparks flanking it, at the width the lozenge used to
    # occupy, so the motif still reads as one cluster.
    for sx in (-1, 1):
        _star4(c, cx + sx * r * 2.2, cy, r * 0.62, LIT, 235)

    return _alpha_only(c.finish())


def crest(w=360, h=58):
    """The console headpiece: a crescent in a low arch, with a spread of rays.

    **A console needs a top.** Every reference this was drawn against -- gilt
    bookbinding, an illuminated page, a profile card -- puts something at the
    head of the panel that says "this is the top and here is what it is". Four
    identical corners and nothing else gives a panel no orientation: the eye
    has to find the reading order rather than being handed it.

    It is a crescent because the crescent is this interface mark, and it is the
    same one in the divider rules. One motif at two sizes is a house style; two
    motifs is a collection.

    **Wide and short, which is the only shape that fits.** The first version
    was 300 by 86 and drawn at the top of the plate, where it printed itself
    straight through the stage name -- a headpiece tall enough to be a
    headpiece leaves nothing above the first line of text. Spread along the
    column instead of stacked up it reads as a band, which is what an
    illuminated page puts at the head of a section anyway.
    """
    c = A.Canvas(w, h)
    cx = w / 2.0
    base = h - 8.0
    my = base - 20.0

    # The arch: two volutes sweeping in to the centre from either side, low
    # and wide so the whole piece stays under sixty pixels.
    _scroll(c, cx - 96, base - 6, 20.0, 0.5, 25, 2.6, FACE + 20, 240)
    _scroll(c, cx + 96, base - 6, 20.0, -0.5, 155, 2.6, FACE + 20, 240)

    # The sweep between them, drawn as a taper so it has weight at the middle
    # and thins into the volutes.
    pts = []
    for i in range(72):
        f = i / 71.0
        pts.append((cx - 96 + f * 192,
                    base - 4 - math.sin(f * math.pi) * 13))
    for i in range(len(pts) - 1):
        f = i / (len(pts) - 2.0)
        c.line([pts[i], pts[i + 1]],
               fill=(FACE + 40, FACE + 40, FACE + 40, 255),
               width=1.5 + 2.2 * math.sin(f * math.pi))

    # A long hairline either side, running out to nothing, so the band spans
    # the column rather than stopping where the ornament does.
    for sx in (-1, 1):
        _taper(c, cx + sx * 108, base - 5, sx, 0, w * 0.5 - 108,
               1.6, 0.8, 190, 0, FACE + 30)

    # The rays behind the crescent -- short, uneven, upper half only, so it
    # reads as light coming off it rather than as a sun.
    for i in range(11):
        a = -168 + i * 13.6
        r0 = 15.0
        r1 = r0 + (11.0 if i % 2 == 0 else 7.0)
        c.line([(cx + math.cos(math.radians(a)) * r0,
                 my + math.sin(math.radians(a)) * r0),
                (cx + math.cos(math.radians(a)) * r1,
                 my + math.sin(math.radians(a)) * r1)],
               fill=(FACE, FACE, FACE, 165), width=1.4)

    # The crescent itself, on its own layer so the bite is a true hole rather
    # than a fill of whatever happens to be behind it.
    r = 13.0
    moon = A.new_layer(c)
    md = A.layer_draw(moon)
    ss = c.ss
    md.ellipse([(cx - r) * ss, (my - r) * ss, (cx + r) * ss, (my + r) * ss],
               fill=(LIT, LIT, LIT, 255))
    md.ellipse([(cx - r * 0.30) * ss, (my - r * 1.06) * ss,
                (cx + r * 1.75) * ss, (my + r * 1.06) * ss], fill=(0, 0, 0, 0))
    c.paste_full(moon)

    # A spark out at each volute, and two smaller ones further along the band.
    _star4(c, cx - 118, base - 12, 5.4, LIT, 215)
    _star4(c, cx + 118, base - 12, 5.4, LIT, 215)
    _star4(c, cx - 152, base - 5, 3.4, LIT, 150)
    _star4(c, cx + 152, base - 5, 3.4, LIT, 150)

    return _alpha_only(c.finish()).filter(ImageFilter.GaussianBlur(0.4))


# ---------------------------------------------------------------------------
# The attack marks
# ---------------------------------------------------------------------------

def marks(size=30):
    """Three frames: a lozenge, a rosette, and the empty socket for both.

    **A count of remaining attacks is read off marks, not off a number.** It is
    the one readout in the console whose value is small enough to be seen
    rather than parsed -- five is a shape, `5` is a glyph -- and it is what the
    genre has always drawn there.

    The two frames differ in *silhouette* and not in size, because they are
    read at 30 pixels in a row and a rosette that is merely a fancier lozenge
    is a lozenge. A spell is the pointed one: it has arms, and arms is what
    says "this one is named".
    """
    out = []

    lz = A.Canvas(size, size)
    h = size / 2.0
    lz.polygon([(h, 3), (size - 6, h), (h, size - 3), (6, h)],
               fill=(FACE - 20, FACE - 20, FACE - 20, 255))
    lz.polygon([(h, 8), (size - 10, h), (h, size - 8), (10, h)],
               fill=(LIT, LIT, LIT, 255))
    out.append(_alpha_only(lz.finish()))

    ro = A.Canvas(size, size)
    pts = []
    for i in range(16):
        ang = math.radians(i * 22.5 - 90)
        rad = (h - 2.0) if i % 2 == 0 else (h - 2.0) * 0.40
        pts.append((h + math.cos(ang) * rad, h + math.sin(ang) * rad))
    ro.polygon(pts, fill=(FACE - 30, FACE - 30, FACE - 30, 255))
    pts = []
    for i in range(16):
        ang = math.radians(i * 22.5 - 90)
        rad = (h - 2.0) * 0.62 if i % 2 == 0 else (h - 2.0) * 0.24
        pts.append((h + math.cos(ang) * rad, h + math.sin(ang) * rad))
    ro.polygon(pts, fill=(LIT, LIT, LIT, 255))
    out.append(_alpha_only(ro.finish()))

    # **The socket: an encounter that has not happened yet.**
    #
    # It is a hollow of the lozenge rather than a third shape, because a row of
    # marks has to read as one row with some of it filled in -- a different
    # silhouette for "not yet" makes the empty half look like a different
    # readout. Hollow *and* dim, because dim alone at this size is a smudge and
    # hollow alone is as loud as a filled one.
    so = A.Canvas(size, size)
    so.polygon([(h, 4), (size - 7, h), (h, size - 4), (7, h)],
               fill=(FACE, FACE, FACE, 255))
    so.polygon([(h, 9), (size - 12, h), (h, size - 9), (12, h)],
               fill=(0, 0, 0, 0))
    out.append(_alpha_only(so.finish()))

    return out


# ---------------------------------------------------------------------------
# The material
# ---------------------------------------------------------------------------

def grain(size=192):
    """A seamless tile of mineral glint, laid additively over the console.

    **Seamless in both axes**, because it tiles across a 464x992 plate and a
    seam in furniture is worse than a seam in scenery: scenery moves and
    furniture does not, so a join sits in the same place for the whole session
    until the player finds it.

    The trick is the same one `fbm_field(wrap_y=True)` uses -- make the thing
    being interpolated periodic rather than the thing doing the interpolating.
    Here that is easier still: the noise is generated once and rolled, and the
    two copies are cross-faded by a window that is itself periodic, which is
    exactly the fix `make_bg.py` records as *not* being enough for a shading
    ramp. It is enough here, because this is a texture of independent specks
    rather than a field with structure across the join -- there is nothing for
    the two halves to disagree *about*.

    It is extremely faint by design. At the alpha `hud_draw_plate` uses it is
    a suggestion of tooling under the light, and turned up far enough to see
    on its own it reads as dirt.
    """
    rng = np.random.default_rng(20260906)

    # Fine specks: a sparse scatter of bright points, which is what catches
    # light on a cast surface. Uniform noise reads as television.
    speck = rng.random((size, size), dtype=np.float32)
    speck = np.clip((speck - 0.86) / 0.14, 0.0, 1.0) ** 1.6

    # A broad, soft mottle so the plate is not evenly lit. Built at an eighth
    # of the size and tiled by `np.tile` before the resize, which is periodic
    # by construction.
    small = rng.random((size // 24, size // 24), dtype=np.float32)
    broad = np.asarray(
        Image.fromarray((np.tile(small, (2, 2)) * 255).astype(np.uint8), "L")
             .resize((size * 2, size * 2), Image.BICUBIC),
        dtype=np.float32)[:size, :size] / 255.0

    # Horizontal tooling: the marks a plate carries from being drawn out.
    ys = np.arange(size, dtype=np.float32)[:, None]
    tool = 0.5 + 0.5 * np.sin(ys * (2 * math.pi * 6 / size))

    # Weighted heavily toward the specks. The broad mottle is what makes a
    # tile *look* tiled -- a blob is a landmark and a landmark repeats
    # visibly -- so it is here only to stop the specks reading as uniform, at
    # an amplitude too low to recognise.
    field = speck * 0.80 + broad * broad * 0.08 + tool * 0.045
    a = np.clip(field * 255.0, 0, 255).astype(np.uint8)

    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(Image.fromarray(a, "L"))
    return img


# ---------------------------------------------------------------------------

def main():
    co = corner()
    ru = rule()
    mk = marks()
    gr = grain()
    cr = crest()

    gm_new.sprite("spr_ui_corner", [co], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_rule", [ru], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_mark", mk, origin="center", folder="Sprites/ui")
    gm_new.sprite("spr_ui_grain", [gr], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_crest", [cr], origin="topleft", folder="Sprites/ui")

    print("corner %dx%d  rule %dx%d  mark %dx%d x%d  grain %dx%d  crest %dx%d"
          % (co.width, co.height, ru.width, ru.height,
             mk[0].width, mk[0].height, len(mk), gr.width, gr.height,
             cr.width, cr.height))

    # **Previewed on the console's own ground, not on a checker.** Every one of
    # these is a dark ornament tinted to `COL_SLATE`, and the only question
    # worth asking of the sheet is whether it reads at all against the near
    # black it will actually sit on.
    ground = A.mix(A.ARCANE, (0, 0, 0), 0.35)
    tint = A.GILT

    def on_ground(img, scale=1.0):
        w = int(img.width * scale)
        h = int(img.height * scale)
        cell = Image.new("RGBA", (w + 16, h + 16), tuple(ground) + (255,))
        col = Image.new("RGBA", (img.width, img.height), tuple(tint) + (0,))
        col.putalpha(img.getchannel("A"))
        cell.alpha_composite(col.resize((w, h), Image.LANCZOS), (8, 8))
        return cell

    tiled = Image.new("RGBA", (gr.width * 2, gr.height * 2))
    for ty in range(2):
        for tx in range(2):
            tiled.paste(gr, (tx * gr.width, ty * gr.height))
    lit = Image.new("RGBA", tiled.size, tuple(ground) + (255,))
    lit = A.add(lit, tiled)

    A.preview([on_ground(co), on_ground(cr), on_ground(ru),
               on_ground(mk[0], 2.0), on_ground(mk[1], 2.0),
               on_ground(mk[2], 2.0), lit],
              PREVIEW, cols=4, bg=(10, 8, 20),
              labels=["corner", "crest", "rule", "lozenge", "rosette",
                      "socket", "grain x4"])
    print("->  %s" % os.path.relpath(PREVIEW, A.ROOT))


if __name__ == "__main__":
    main()
