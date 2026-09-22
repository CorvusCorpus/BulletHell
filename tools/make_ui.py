#!/usr/bin/env python3
"""The HUD's furniture: filigree, rules, marks, medals and material.

Everything here is drawn white and tinted at draw time (mostly `COL_GILT`),
so every shape is built from value rather than colour: a lit edge beside a
dark one reads as relief once tinted. Anything that carries a value (a
gauge's length, a rule's straight run, the panel's ground) is drawn in GML
so it can stretch; the shapes are sprites made here.

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

# Values, not colours (the ornaments are tinted): the lit face of an engraved
# line, its shadowed face, and the flat of the metal.
LIT = 255
FACE = 150
DARK = 64


def _alpha_only(img):
    """Force a layer to pure white ink, keeping its value in the alpha.

    `draw_sprite_ext`'s blend colour multiplies, so a shape drawn at 60% grey
    would tint to 60% of the requested colour. Drawing in greys and converting
    here is easier than drawing in alpha directly.
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
    """A bar along one axis that changes width and fades as it goes, built from
    thin quads (a quad per step has a straight edge; stepped dots leave beads).
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
    """A volute: a line spiralling inward, thinning as it goes. It stops at
    about three quarters of a turn and tapers to nothing; a full spiral reads
    as a letter.
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
    """A four-pointed sparkle, the motif that still reads at 12 pixels."""
    pts = []
    for i in range(8):
        ang = math.radians(i * 45 - 90)
        rr = r if i % 2 == 0 else r * waist
        pts.append((x + math.cos(ang) * rr, y + math.sin(ang) * rr))
    c.polygon(pts, fill=(v, v, v, alpha))


def corner(size=132):
    """One top-left corner piece: a gilded volute over a mitred bracket. Drawn
    for one orientation and flipped for the other three, so the four corners
    are identical. The L and the chamfer are the heavy part; volutes, smaller
    curls, sparks and a set stone are the ornament.
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

    # The chamfer: the corner cut off at 45 degrees, heavier than the arms it
    # joins.
    d = 1.0 / math.sqrt(2.0)
    _taper(c, o + d * 2.4, o + chamfer - d * 2.4, d, -d,
           chamfer * math.sqrt(2.0) - 4.8, 5.6, 5.6, 245, 245, FACE + 40)

    # A lit hairline inboard at a constant offset, which turns the stripes into
    # a bevelled edge. It runs about half the length of the arms.
    inset = 9.5
    run = (size - o - chamfer) * 0.52
    _taper(c, o + chamfer + 3, o + inset, 1, 0, run, 1.3, 1.0, 150, 0, LIT)
    _taper(c, o + inset, o + chamfer + 3, 0, 1, run, 1.3, 1.0, 150, 0, LIT)

    # The volutes: one curling inward off each arm, mirrored about the
    # chamfer's axis so the piece is symmetric about its diagonal.
    _scroll(c, o + 40, o + 22, 13.0, 0.72, 155, 2.6, FACE + 30, 255)
    _scroll(c, o + 22, o + 40, 13.0, -0.72, -65, 2.6, FACE + 30, 255)

    # Two smaller curls further out, so the ornament thins along the arm
    # instead of stopping.
    _scroll(c, o + 74, o + 17, 7.0, 0.6, 150, 1.7, FACE, 220)
    _scroll(c, o + 17, o + 74, 7.0, -0.6, -60, 1.7, FACE, 220)

    # A four-pointed catch of light out along each arm.
    _star4(c, o + 58, o + 19, 5.4, LIT, 210)
    _star4(c, o + 19, o + 58, 5.4, LIT, 210)

    # The set stone, on the chamfer's axis: a dark surround, a bright centre.
    mid = o + chamfer * 0.5
    for r, v, a in ((10.0, DARK, 255), (7.0, FACE, 255), (3.6, LIT, 255)):
        c.polygon([(mid, mid - r), (mid + r, mid), (mid, mid + r),
                   (mid - r, mid)], fill=(v, v, v, a))

    img = _alpha_only(c.finish())
    # One small blur, to soften the hard edges the quad joints leave.
    return img.filter(ImageFilter.GaussianBlur(0.45))


def rule(w=416, h=30):
    """A section divider: a crescent between two hairlines that taper and fade
    out at both ends (so it needn't be positioned to the pixel), flanked by two
    four-pointed sparks.
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

    # The crescent: a disc with a second disc bitten out of it, on its own
    # layer so the bite is a true hole.
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

    # Two four-pointed sparks flanking it.
    for sx in (-1, 1):
        _star4(c, cx + sx * r * 2.2, cy, r * 0.62, LIT, 235)

    return _alpha_only(c.finish())


def crest(w=360, h=58):
    """The console headpiece: a crescent in a low arch, with a spread of rays.
    Wide and short, so it spans the column as a band.
    """
    c = A.Canvas(w, h)
    cx = w / 2.0
    base = h - 8.0
    my = base - 20.0

    # The arch: two volutes sweeping in to the centre, low and wide.
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

    # The rays behind the crescent: short, uneven and upper half only, so they
    # read as light coming off it rather than as a sun.
    for i in range(11):
        a = -168 + i * 13.6
        r0 = 15.0
        r1 = r0 + (11.0 if i % 2 == 0 else 7.0)
        c.line([(cx + math.cos(math.radians(a)) * r0,
                 my + math.sin(math.radians(a)) * r0),
                (cx + math.cos(math.radians(a)) * r1,
                 my + math.sin(math.radians(a)) * r1)],
               fill=(FACE, FACE, FACE, 165), width=1.4)

    # The crescent itself, on its own layer so the bite is a true hole.
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
    """Three frames for the console's row of attack marks: a lozenge
    (non-spell), a rosette (spell) and the empty socket. The two filled marks
    differ in silhouette rather than size, so they tell apart at 30 pixels.
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

    # The socket, for an encounter not yet reached: the lozenge hollowed and
    # dimmed, so a row of marks reads as one row partly filled.
    so = A.Canvas(size, size)
    so.polygon([(h, 4), (size - 7, h), (h, size - 4), (7, h)],
               fill=(FACE, FACE, FACE, 255))
    so.polygon([(h, 9), (size - 12, h), (h, size - 9), (12, h)],
               fill=(0, 0, 0, 0))
    out.append(_alpha_only(so.finish()))

    return out




# ---------------------------------------------------------------------------
# The boss's rig
#
# The boss's health is a gilded rail hung on two chains from the top of the
# frame, so it can be lowered into view when a boss arrives. The rail carries
# a value and stretches to the field's width, so it is drawn in GML; the
# chain, the hangers, the plaque and the dial are drawn here.
# ---------------------------------------------------------------------------

CHAIN_W = 20                       # the sprite's width
CHAIN_PITCH = 12                   # one link
CHAIN_PERIOD = CHAIN_PITCH * 2     # the sprite's height: two links


def _link(c, cx, cy, rx, ry, wid):
    """One link, in three passes offset by under a pixel: a shadow down-right,
    the metal, and a highlight up-left (the light comes from above), which
    makes a ring of one value read as a round bar.
    """
    def ring(dx, dy, v, a, wd):
        c.ellipse((cx - rx + dx, cy - ry + dy, cx + rx + dx, cy + ry + dy),
                  outline=(v, v, v, a), width=wd)

    ring(0.9, 1.0, DARK, 255, wid)
    ring(0.0, 0.0, FACE + 25, 255, wid)
    ring(-0.7, -0.8, LIT, 215, max(1.0, wid * 0.45))


def chain(w=CHAIN_W, period=CHAIN_PERIOD):
    """One period of hanging chain: two links, one face-on and one edge-on.

    Periodic in y by construction, since it is tiled down whatever gap there is
    between the frame and the rail: the links are drawn at every pitch from one
    below the canvas to one above it, and the canvas is exactly two pitches
    tall.
    """
    c = A.Canvas(w, period)
    cx = w / 2.0
    for i in range(-1, 4):
        cy = i * CHAIN_PITCH
        if i % 2 == 0:
            _link(c, cx, cy, w * 0.37, CHAIN_PITCH * 0.68, 3.2)
        else:
            _link(c, cx, cy, w * 0.15, CHAIN_PITCH * 0.68, 3.0)
    return _alpha_only(c.finish())


HANGER_W = 40
HANGER_H = 46
HANGER_RAIL_CY = 30.0     # where the rail's own centre line crosses the piece
HANGER_EYE_CY = 8.0       # where the chain attaches


def hanger(w=HANGER_W, h=HANGER_H, rail_cy=HANGER_RAIL_CY, rail_h=22.0):
    """The terminal at one end of the rail: a collar round it, a lug, and an
    eye for the chain.

    The collar is narrower than the rail is deep, so it reads as wrapped round
    the bar, and it takes the rail's own section (dark contour, lit bevel,
    shadowed underside). It is symmetric, so one drawing serves both ends
    unflipped. Its origin is on the rail's centre line, not the sprite's, so a
    call site places it at the rail.
    """
    c = A.Canvas(w, h)
    cx = w / 2.0
    eye_cy = HANGER_EYE_CY
    top = rail_cy - rail_h * 0.5 - 2.0
    bot = rail_cy + rail_h * 0.5 + 2.0
    half = 6.5                                   # the collar's own half-width

    # The lug: a tapered tongue from the collar up to the eye, so the chain
    # pulls on something rather than resting on the rail.
    c.polygon([(cx - 4.4, top + 2), (cx + 4.4, top + 2),
               (cx + 3.0, eye_cy + 4), (cx - 3.0, eye_cy + 4)],
              fill=(FACE - 10, FACE - 10, FACE - 10, 255))
    c.line([(cx - 2.6, top + 1), (cx - 1.9, eye_cy + 4)],
           fill=(LIT, LIT, LIT, 200), width=1.3)
    c.line([(cx + 3.4, top + 1), (cx + 2.4, eye_cy + 4)],
           fill=(DARK, DARK, DARK, 235), width=1.3)

    # The collar, cut to the rail's section: bands, with the highlight above
    # the middle and the underside dark.
    band = [(-1.00, DARK), (-0.82, LIT), (-0.50, FACE + 35),
            (0.10, FACE - 25), (0.62, DARK + 26), (0.88, FACE + 5),
            (1.00, DARK)]
    for i in range(len(band) - 1):
        t0, v0 = band[i]
        t1, v1 = band[i + 1]
        y0 = rail_cy + t0 * (bot - top) * 0.5
        y1 = rail_cy + t1 * (bot - top) * 0.5
        steps = 6
        for k in range(steps):
            f0, f1 = k / steps, (k + 1) / steps
            v = int(v0 + (v1 - v0) * (f0 + f1) * 0.5)
            c.rect((cx - half, y0 + (y1 - y0) * f0,
                    cx + half, y0 + (y1 - y0) * f1 + 0.4),
                   fill=(v, v, v, 255))

    # A keeper at each end of the collar: a hairline just inside it.
    for sy in (top + 3.4, bot - 3.4):
        c.line([(cx - half + 0.6, sy), (cx + half - 0.6, sy)],
               fill=(DARK, DARK, DARK, 210), width=1.1)

    # A small, low volute at each side, springing off the collar onto the rail.
    for sx in (-1, 1):
        _scroll(c, cx + sx * (half + 4.0), rail_cy - 1.5, 6.0, 0.55,
                200 if sx > 0 else -20, 1.9, FACE + 20, 225)

    # The eye, last and on its own layer, so its hole is a true hole.
    r = 6.6
    eye = A.new_layer(c)
    ed = A.layer_draw(eye)
    s = c.ss
    ed.ellipse([(cx - r) * s, (eye_cy - r) * s,
                (cx + r) * s, (eye_cy + r) * s],
               fill=(DARK + 30, DARK + 30, DARK + 30, 255))
    ed.ellipse([(cx - r + 0.9) * s, (eye_cy - r + 0.8) * s,
                (cx + r - 0.9) * s, (eye_cy + r - 1.2) * s],
               fill=(FACE + 45, FACE + 45, FACE + 45, 255))
    ed.ellipse([(cx - r + 1.5) * s, (eye_cy - r + 1.2) * s,
                (cx + r - 2.2) * s, (eye_cy + r - 3.0) * s],
               fill=(LIT, LIT, LIT, 235))
    ed.ellipse([(cx - r * 0.42) * s, (eye_cy - r * 0.42) * s,
                (cx + r * 0.42) * s, (eye_cy + r * 0.42) * s],
               fill=(0, 0, 0, 0))
    c.paste_full(eye)

    return _alpha_only(c.finish())


DIAL_D = 84


def dial(d=None):
    """The bezel the attack's clock runs inside, at the rail's other end.

    It matches the plaque: the same band and section, and the same four-pointed
    spark as an index mark. Hollow, because the face and the arc that sweeps
    round it are values, drawn in GML. Two lugs at three and nine o'clock clamp
    it onto the rail.
    """
    d = d or DIAL_D
    c = A.Canvas(d, d)
    cx = cy = d / 2.0
    r = d / 2.0 - 1.5

    # The lugs first, so the bezel is drawn over their roots. Only their
    # inboard ends show, since the rail they clamp is behind the dial.
    for sx in (-1, 1):
        x0 = cx + sx * (r - 9.0)
        x1 = cx + sx * (r + 0.5)
        c.round_rect((min(x0, x1), cy - 6.0, max(x0, x1), cy + 6.0), 3,
                     fill=(FACE - 20, FACE - 20, FACE - 20, 255))
        c.line([(min(x0, x1) + 1, cy - 3.8), (max(x0, x1) - 1, cy - 3.8)],
               fill=(LIT, LIT, LIT, 200), width=1.3)
        c.line([(min(x0, x1) + 1, cy + 4.2), (max(x0, x1) - 1, cy + 4.2)],
               fill=(DARK, DARK, DARK, 220), width=1.3)

    # The bezel as a section: a dark contour outside, a hot line just inside
    # it, the body, and a shadowed inner lip.
    _ring(c, cx, cy, r - 0.6, 1.4, DARK, 255)
    _ring(c, cx, cy, r - 2.0, 2.2, LIT, 235)
    _ring(c, cx, cy, r - 4.4, 3.4, FACE + 20, 255)
    _ring(c, cx, cy, r - 7.0, 1.6, DARK + 20, 235)

    # The graduation inside the bezel: twelve marks, the quarters long.
    for i in range(12):
        ang = math.radians(i * 30 - 90)
        long = (i % 3 == 0)
        r0 = r - 8.5
        r1 = r0 - (5.0 if long else 2.8)
        c.line([(cx + math.cos(ang) * r0, cy + math.sin(ang) * r0),
                (cx + math.cos(ang) * r1, cy + math.sin(ang) * r1)],
               fill=(LIT, LIT, LIT, 215 if long else 140),
               width=1.6 if long else 1.1)

    # The index mark at noon.
    _star4(c, cx, cy - r + 2.2, 4.4, LIT, 240)

    return _alpha_only(c.finish())


PLAQUE_W = 178
PLAQUE_H = 50
PLAQUE_CHAMF = 16


def plaque(w=PLAQUE_W, h=PLAQUE_H):
    """The cartouche the boss's health percentage is set in: a tablet with
    angled ends, a four-pointed spark in each. Hollow, because the dark ground
    behind it is drawn in GML (a tinted sprite multiplies, so it can't darken
    what is already there).
    """
    c = A.Canvas(w, h)
    cy = h / 2.0
    chamf = PLAQUE_CHAMF
    m = 1.5

    def tablet(inset):
        return [(inset, cy),
                (inset + chamf, inset + m),
                (w - inset - chamf, inset + m),
                (w - inset, cy),
                (w - inset - chamf, h - inset - m),
                (inset + chamf, h - inset - m)]

    # The moulding, punched hollow: an outer band of metal with the field cut
    # out of it, so what the plate frames is whatever is drawn behind it.
    lay = A.new_layer(c)
    ld = A.layer_draw(lay)
    s = c.ss
    ld.polygon([(x * s, y * s) for x, y in tablet(0.0)],
               fill=(FACE - 10, FACE - 10, FACE - 10, 255))
    ld.polygon([(x * s, y * s) for x, y in tablet(7.0)], fill=(0, 0, 0, 0))
    c.paste_full(lay)

    # Lit along the top of the band and shadowed along the bottom, which is
    # what turns a flat outline into a moulding.
    edge = tablet(1.2)
    c.line([edge[0], edge[1], edge[2], edge[3]], fill=(LIT, LIT, LIT, 225),
           width=1.6)
    c.line([edge[3], edge[4], edge[5], edge[0]], fill=(DARK, DARK, DARK, 235),
           width=1.8)
    inner = tablet(6.2)
    c.line(inner + [inner[0]], fill=(DARK, DARK, DARK, 200), width=1.2)
    c.line([inner[5], inner[0], inner[1]],
           fill=(FACE + 30, FACE + 30, FACE + 30, 180), width=1.0)

    # The sparks, in the two apexes.
    _star4(c, 10.5, cy, 5.0, LIT, 230)
    _star4(c, w - 10.5, cy, 5.0, LIT, 230)

    # Studs in pairs off the ends (evenly spaced studs read as a dotted line).
    for sx in (chamf + 8, w - chamf - 8):
        for sy in (3.4, h - 3.4):
            c.ellipse((sx - 1.7, sy - 1.7, sx + 1.7, sy + 1.7),
                      fill=(LIT, LIT, LIT, 210))

    return _alpha_only(c.finish())

# ---------------------------------------------------------------------------
# The medal
# ---------------------------------------------------------------------------

def _ring(c, cx, cy, r, w, v, alpha, steps=240):
    """A circular band of constant width, drawn as quads so its value can vary
    round the circle (`ellipse(outline=)` can't taper, fade or change value).
    """
    prev = None
    for i in range(steps + 1):
        a = i / float(steps) * math.tau
        ca, sa = math.cos(a), math.sin(a)
        ww = w(a) if callable(w) else w
        vv = v(a) if callable(v) else v
        aa = alpha(a) if callable(alpha) else alpha
        vv, aa = int(vv), int(max(0, min(255, aa)))
        cur = ((cx + ca * (r - ww * 0.5), cy + sa * (r - ww * 0.5)),
               (cx + ca * (r + ww * 0.5), cy + sa * (r + ww * 0.5)),
               vv, aa)
        if prev is not None and (aa > 2 or prev[3] > 2):
            c.polygon([prev[0], cur[0], cur[1], prev[1]],
                      fill=(vv, vv, vv, max(aa, prev[3])))
        prev = cur


def _bevel(c, cx, cy, r, w, lit=1.0):
    """An edge that catches light from up and to the left: a bright band beside
    a dark one, which reads as a slope. The light is a raised cosine of the
    angle, so the two faces swap over smoothly rather than at a seam.
    """
    key = math.radians(-135.0)

    def face(a, phase):
        # 1 at the lit side, 0 at the shaded one.
        return 0.5 + 0.5 * math.cos(a - key + phase)

    # The outer chamfer: bright where it faces the light.
    _ring(c, cx, cy, r, w * 0.5,
          lambda a: LIT if face(a, 0) > 0.5 else FACE,
          lambda a: (60 + 195 * face(a, 0)) * lit)
    # The inner chamfer, half a turn out of phase, so the rim has two faces.
    _ring(c, cx, cy, r - w * 0.5, w * 0.5,
          lambda a: FACE if face(a, math.pi) > 0.5 else DARK,
          lambda a: (30 + 150 * face(a, math.pi)) * lit)


def _gem(c, cx, cy, r, facets, rough=False, star=False):
    """A cut stone: a girdle, a ring of crown facets, and a table. Every face
    is a polygon at one flat value, and neighbouring faces are forced apart in
    value so the cut reads. `rough` draws an uncut lump instead: an irregular
    girdle, two big cleavage planes, and no table.
    """
    key = math.radians(-135.0)

    if rough:
        # An uncut lump. The girdle wanders, so nothing about it is regular.
        pts = []
        for i in range(9):
            a = math.radians(-90 + i * 40.0)
            rr = r * (0.80 + 0.30 * math.sin(i * 2.7) * math.cos(i * 1.3))
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        c.polygon(pts, fill=(DARK + 30, DARK + 30, DARK + 30, 255))
        # Two cleavage planes, one catching the light and one not.
        c.polygon(pts[7:] + pts[:3] + [(cx, cy)],
                  fill=(FACE + 30, FACE + 30, FACE + 30, 255))
        c.polygon(pts[2:5] + [(cx, cy)],
                  fill=(DARK + 6, DARK + 6, DARK + 6, 255))
        return

    girdle = []
    table = []
    for i in range(facets):
        a = math.radians(-90 + i * 360.0 / facets)
        b = a + math.pi / facets
        girdle.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        table.append((cx + math.cos(b) * r * 0.50,
                      cy + math.sin(b) * r * 0.50))

    for i in range(facets):
        j = (i + 1) % facets
        # Where this pair of faces points, and therefore how lit they are.
        a = math.radians(-90 + i * 360.0 / facets) + math.pi / facets
        f = 0.5 + 0.5 * math.cos(a - key)
        base = DARK + (LIT - DARK) * (0.10 + 0.90 * f)
        # ...pushed hard apart, so no two neighbours are ever close.
        v1 = int(max(DARK - 30, min(LIT, base + (46 if i % 2 == 0 else -46))))
        v2 = int(max(DARK - 30, min(LIT, base + (-38 if i % 2 == 0 else 38))))
        c.polygon([girdle[i], girdle[j], table[i]], fill=(v1, v1, v1, 255))
        c.polygon([girdle[i], table[i - 1], table[i]], fill=(v2, v2, v2, 255))

    # The table: the flat top, brightest on its lit half.
    c.polygon(table, fill=(LIT - 26, LIT - 26, LIT - 26, 255))
    half = [table[k % facets] for k in range(facets // 2, facets + 1)]
    if len(half) >= 3:
        c.polygon(half, fill=(FACE - 4, FACE - 4, FACE - 4, 255))

    if star:
        # A star cut across the table: short alternating facets from its
        # centre to its corners.
        for i in range(facets):
            j = (i + 1) % facets
            v = LIT if i % 2 == 0 else FACE + 26
            c.polygon([table[i], table[j], (cx, cy)], fill=(v, v, v, 255))
        c.ellipse([cx - r * 0.10, cy - r * 0.10, cx + r * 0.10,
                   cy + r * 0.10], fill=(LIT, LIT, LIT, 255))


def _rays(c, cx, cy, r0, r1, n, v, alpha, long_every=2, phase=0.0):
    """Light coming off the piece. Uneven, or it is a sun."""
    for i in range(n):
        a = math.radians(phase + i * 360.0 / n)
        rr = r1 if (i % long_every == 0) else r0 + (r1 - r0) * 0.55
        c.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
                (cx + math.cos(a) * rr, cy + math.sin(a) * rr)],
               fill=(v, v, v, alpha), width=1.6)


def _crescent(c, cx, cy, r, v=LIT):
    """The interface's crescent, at the head of the medal, on its own layer so
    the bite is a true hole.
    """
    moon = A.new_layer(c)
    md = A.layer_draw(moon)
    ss = c.ss
    md.ellipse([(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss],
               fill=(v, v, v, 255))
    md.ellipse([(cx - r * 0.28) * ss, (cy - r * 1.06) * ss,
                (cx + r * 1.34) * ss, (cy + r * 1.06) * ss],
               fill=(0, 0, 0, 0))
    c.paste_full(moon)


def medals(size=176):
    """One frame per rung of the ladder, plus ABSOLUTE AMETHYST.

    One medal with more ornament at each rung (beading, volutes, a crescent,
    rays), drawn white and tinted at draw time (`mark_colour`). Drawn at 176
    for the rank card; the ornament is built from bands and masses rather than
    hairlines so it survives being scaled down.
    """
    out = []
    n = size / 2.0

    # How much ornament each rung gets; the gem's facet count climbs with it.
    SPEC = [
        # ticks volutes crescent rays facets rough  star   halo
        (0,     False,  False,   0,   0,     True,  False, False),  # STONE
        (16,    False,  False,   0,   6,     False, False, False),  # BRONZE
        (20,    True,   False,   0,   7,     False, False, False),  # SILVER
        (24,    True,   True,    0,   8,     False, True,  False),  # GOLD
        (28,    True,   True,    20,  9,     False, True,  False),  # AMETHYST
        (36,    True,   True,    36,  10,    False, True,  True),   # ABSOLUTE
    ]

    for ticks, volutes, crescent, rays, facets, rough, star, halo in SPEC:
        c = A.Canvas(size, size)
        cx = cy = n
        r_out = n - 8.0

        # The rays go first, behind everything, so the medal sits on them.
        if rays:
            _rays(c, cx, cy, r_out - 2, n - 1.0, rays, FACE, 150)
            _rays(c, cx, cy, r_out - 2, n - 5.0, rays, LIT, 90,
                  long_every=3, phase=360.0 / (rays * 2))

        # The field: the flat of the medal, dark so everything on it reads.
        c.ellipse([cx - r_out + 3, cy - r_out + 3, cx + r_out - 3,
                   cy + r_out - 3], fill=(DARK - 20, DARK - 20, DARK - 20, 235))

        # The struck edge.
        if rough:
            # Stone is the same medal badly cast: the rim wobbles, the bevel is
            # weak and the light on it is patchy.
            _ring(c, cx, cy, r_out,
                  lambda a: 9.5 + 3.4 * math.sin(a * 5.0 + 1.1)
                            + 1.8 * math.sin(a * 11.0),
                  lambda a: FACE + 40 * math.cos(a - math.radians(-135.0)),
                  245)
            # Pits, which is what a bad cast has instead of a bevel.
            for i in range(26):
                a = i * 2.39996
                rr = r_out - 4.0 - 7.0 * ((i * 0.37) % 1.0)
                px, py = cx + math.cos(a) * rr, cy + math.sin(a) * rr
                sz = 1.4 + 2.2 * ((i * 0.61) % 1.0)
                c.ellipse([px - sz, py - sz, px + sz, py + sz],
                          fill=(DARK - 30, DARK - 30, DARK - 30, 235))
        else:
            _bevel(c, cx, cy, r_out, 9.0)

        # A course of beading inside the rim.
        if ticks:
            rb = r_out - 11.0
            for i in range(ticks):
                a = math.radians(i * 360.0 / ticks)
                bx, by = cx + math.cos(a) * rb, cy + math.sin(a) * rb
                f = 0.5 + 0.5 * math.cos(a - math.radians(-135.0))
                v = int(FACE + (LIT - FACE) * f)
                c.ellipse([bx - 2.6, by - 2.6, bx + 2.6, by + 2.6],
                          fill=(v, v, v, 235))
            # An engraved circle under the beading: a dark hairline with a pale
            # one beside it.
            _ring(c, cx, cy, rb - 5.0, 1.6, DARK, 190)
            _ring(c, cx, cy, rb - 6.6, 1.2, LIT, 120)

        # Volutes either side.
        if volutes:
            _scroll(c, cx - r_out + 13, cy + 2, 13.0, 0.62, 200, 2.4,
                    FACE + 30, 225)
            _scroll(c, cx + r_out - 13, cy + 2, 13.0, -0.62, -20, 2.4,
                    FACE + 30, 225)

        # The crescent at the head of the field.
        if crescent:
            _crescent(c, cx, cy - r_out + 22, 8.5)

        # ABSOLUTE AMETHYST gets a second rim and a wreath, so it is clearly
        # distinct from AMETHYST.
        if halo:
            _ring(c, cx, cy, n - 2.5, 2.2, LIT, 210)
            _ring(c, cx, cy, r_out - 17.0, 1.4, LIT, 130)
            for i in range(2):
                sgn = 1 if i == 0 else -1
                for k in range(11):
                    a = math.radians(108 + sgn * (k * 15.4) + (0 if i else 0))
                    rr = r_out - 22.0
                    lx, ly = cx + math.cos(a) * rr, cy + math.sin(a) * rr
                    c.polygon([(lx, ly - 5.5), (lx + sgn * 4.2, ly),
                               (lx, ly + 5.5)],
                              fill=(FACE + 50, FACE + 50, FACE + 50, 190))

        # The stone.
        _gem(c, cx, cy + (3 if crescent else 0), n * 0.335, max(facets, 3),
             rough=rough, star=star)

        # A four-pointed spark on the table.
        if rays:
            for sx, sy, ln in ((0, 0, 13.0),):
                gx, gy = cx + sx - n * 0.10, cy + sy - n * 0.10
                c.polygon([(gx, gy - ln), (gx + ln * 0.20, gy),
                           (gx, gy + ln), (gx - ln * 0.20, gy)],
                          fill=(LIT, LIT, LIT, 255))
                c.polygon([(gx - ln, gy), (gx, gy - ln * 0.20),
                           (gx + ln, gy), (gx, gy + ln * 0.20)],
                          fill=(LIT, LIT, LIT, 255))

        out.append(_alpha_only(c.finish()))

    return out

# ---------------------------------------------------------------------------
# The material
# ---------------------------------------------------------------------------

def grain(size=192):
    """A seamless tile of mineral glint, laid additively over the console, and
    kept very faint.

    Seamless in both axes: the noise is generated once and rolled, and the two
    copies are cross-faded by a periodic window. That is enough here because
    the texture is independent specks, with no structure across the join.
    """
    rng = np.random.default_rng(20260906)

    # Fine specks: a sparse scatter of bright points.
    speck = rng.random((size, size), dtype=np.float32)
    speck = np.clip((speck - 0.86) / 0.14, 0.0, 1.0) ** 1.6

    # A broad, soft mottle so the plate isn't evenly lit, built small and
    # tiled with `np.tile` before the resize (periodic by construction).
    small = rng.random((size // 24, size // 24), dtype=np.float32)
    broad = np.asarray(
        Image.fromarray((np.tile(small, (2, 2)) * 255).astype(np.uint8), "L")
             .resize((size * 2, size * 2), Image.BICUBIC),
        dtype=np.float32)[:size, :size] / 255.0

    # Horizontal tooling: the marks a plate carries from being drawn out.
    ys = np.arange(size, dtype=np.float32)[:, None]
    tool = 0.5 + 0.5 * np.sin(ys * (2 * math.pi * 6 / size))

    # Weighted heavily toward the specks: the mottle only breaks up their
    # uniformity, too faintly to be recognised as it repeats.
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
    md = medals()
    ch = chain()
    hg = hanger()
    pl = plaque()
    dl = dial()

    gm_new.sprite("spr_ui_corner", [co], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_rule", [ru], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_mark", mk, origin="center", folder="Sprites/ui")
    gm_new.sprite("spr_ui_grain", [gr], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_crest", [cr], origin="topleft", folder="Sprites/ui")
    gm_new.sprite("spr_ui_medal", md, origin="center", folder="Sprites/ui")
    # The chain's origin is its top-left: it is tiled downward from a fixed
    # ceiling, so the links' phase stays put while the rail moves.
    gm_new.sprite("spr_ui_chain", [ch], origin="topleft", folder="Sprites/ui")
    # The hanger's origin is on the rail's centre line, so a call site puts it
    # where the rail is.
    gm_new.sprite("spr_ui_hanger", [hg],
                  origin=(HANGER_W // 2, int(HANGER_RAIL_CY)),
                  folder="Sprites/ui")
    gm_new.sprite("spr_ui_plaque", [pl], origin="center", folder="Sprites/ui")
    gm_new.sprite("spr_ui_dial", [dl], origin="center", folder="Sprites/ui")

    print("corner %dx%d  rule %dx%d  mark %dx%d x%d  grain %dx%d  crest %dx%d"
          % (co.width, co.height, ru.width, ru.height,
             mk[0].width, mk[0].height, len(mk), gr.width, gr.height,
             cr.width, cr.height))
    print("medal %dx%d x%d" % (md[0].width, md[0].height, len(md)))
    print("chain %dx%d  hanger %dx%d  plaque %dx%d  dial %dx%d"
          % (ch.width, ch.height, hg.width, hg.height, pl.width, pl.height,
             dl.width, dl.height))

    # Previewed tinted gilt on the console's own ground, not on a checker.
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

    # The chain is previewed tiled, so a seam would show.
    stack = Image.new("RGBA", (ch.width, ch.height * 5))
    for ty in range(5):
        stack.paste(ch, (0, ty * ch.height))

    A.preview([on_ground(co), on_ground(cr), on_ground(ru),
               on_ground(mk[0], 2.0), on_ground(mk[1], 2.0),
               on_ground(mk[2], 2.0), lit,
               on_ground(stack, 2.0), on_ground(hg, 2.0), on_ground(pl),
               on_ground(dl, 2.0)],
              PREVIEW, cols=4, bg=(10, 8, 20),
              labels=["corner", "crest", "rule", "lozenge", "rosette",
                      "socket", "grain x4", "chain x5", "hanger", "plaque",
                      "dial"])
    print("->  %s" % os.path.relpath(PREVIEW, A.ROOT))

    # The medals get their own sheet in their own colours, at full size and at
    # 34px.
    tints = [A.STONE, A.BRONZE, A.SILVER, A.GRAZE, A.AMETHYST,
             A.mix(A.AMETHYST, (255, 255, 255), 0.45)]
    names = ["STONE", "BRONZE", "SILVER", "GOLD", "AMETHYST", "ABSOLUTE"]

    def tinted(img, col, scale):
        w = max(1, int(img.width * scale))
        h = max(1, int(img.height * scale))
        cell = Image.new("RGBA", (w + 16, h + 16), tuple(ground) + (255,))
        lay = Image.new("RGBA", img.size, tuple(col) + (0,))
        lay.putalpha(img.getchannel("A"))
        cell.alpha_composite(lay.resize((w, h), Image.LANCZOS), (8, 8))
        return cell

    A.preview([tinted(md[i], tints[i], 1.0) for i in range(len(md))]
              + [tinted(md[i], tints[i], 0.20) for i in range(len(md))],
              os.path.join(A.PREVIEW, "ui_medals.png"), cols=6, bg=(10, 8, 20),
              labels=names + [n.lower() + " @34" for n in names])
    print("->  %s" % os.path.relpath(os.path.join(A.PREVIEW,
                                                  "ui_medals.png"), A.ROOT))


if __name__ == "__main__":
    main()
