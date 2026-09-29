#!/usr/bin/env python3
"""Stage three's foes and its midboss, drawn as 2D sprites in their own
colours (`cel_art`): cel-shaded parts with line work, over the 3D hall.

Nothing in a wave is a creature (owner's rule): these are animated objects.

- `spr_foe_hall_sphere` (12 frames): an armillary sphere. A glass heart with
  a sun burning in it, on a tipped gold axis with finials, inside three gilt
  rings: the equator, set with turquoise and lapis beads; a meridian through
  the axis; and the ecliptic, tipped off the equator. The outer two turn
  opposite ways. Each ring is drawn in two halves, the far one behind the
  heart and the near one over it.
- `spr_foe_hall_book` (8 frames): a spellbook flying on its boards, which beat
  like wings. Lapis leather painted with a double gilt border, gold mounts
  set with turquoise, half a winged sun on each board and an ankh under it,
  foreshortened onto each board as it folds back; a banded spine with a
  carnelian boss; gilt page edges; a silk marker.
- `spr_foe_hall_wisp` (8 frames): a soul-flame, turquoise with a white heart
  and a dark lapis fringe, with an ankh charm hanging in it.
- The sand golem (`scripts/sanctum_golem`), a sand elemental:
  `spr_golem_body` (8 frames: a hulking torso of wind-blown sand with a
  gold-and-carnelian amulet for a heart), `spr_golem_glow` (8 frames, drawn
  added: its eyes, its heart and the seams of light in the sand), and
  `spr_golem_fist` (8 frames: a clenched clump of sand).
- Pieces: `spr_fx_page` (3 loose leaves), `spr_fx_gilt` (3 shards of gold),
  `spr_fx_grit` (3 grains of sand), and `spr_fx_summon` (the glyph a foe
  materialises out of: white, tinted where it is drawn).

Hit radii for the foes are `HALL_*_R` in `scripts/sanctum_foes`; the golem's
part offsets are `GOLEM_*` in `scripts/sanctum_golem`. Change them with the
art.

Usage:
    python tools/make_sanctum_foes.py            # write the sprites
    python tools/make_sanctum_foes.py --preview  # only the preview sheets
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import cel_art as C
import sanctum_glyphs as GL
import sanctum_relief as SR

SS = C.SS


def rot(v, ax, deg):
    """Rotate a 3D point about axis `ax` ("x", "y" or "z") by `deg`. Used
    only to work out where a ring's line runs before it is drawn flat."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    if ax == "x":
        return (x, y * c - z * s, y * s + z * c)
    if ax == "y":
        return (x * c + z * s, y, -x * s + z * c)
    return (x * c - y * s, x * s + y * c, z)


def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


# ---------------------------------------------------------------------------
# The armillary sphere
# ---------------------------------------------------------------------------

SPHERE_SIZE = 108
SPHERE_FRAMES = 12


def _ring_runs(r, u, v, n=400):
    """A ring's line as runs of points, split where it passes behind the
    middle: returns (far runs, near runs), each a list of point lists."""
    far, near = [], []
    cur, cur_near = [], None
    for k in range(n + 1):
        t = 2 * math.pi * k / n
        p = tuple(r * (math.cos(t) * u[i] + math.sin(t) * v[i])
                  for i in range(3))
        is_near = p[2] >= 0
        if cur_near is None or is_near == cur_near:
            cur.append((p[0], p[1]))
        else:
            (near if cur_near else far).append(cur)
            cur = [cur[-1], (p[0], p[1])]
        cur_near = is_near
    (near if cur_near else far).append(cur)
    return far, near


def sphere_frame(f, frames=SPHERE_FRAMES):
    sh = C.Sheet(SPHERE_SIZE, SPHERE_SIZE)
    turn = 180.0 * f / frames              # a ring maps onto itself at 180

    # The axis, its top tipped toward the viewer and a little right.
    axis = norm(rot(rot((0, -1, 0), "x", -24), "z", 14))
    side = norm(cross(axis, (0, 0, 1)))
    front = norm(cross(side, axis))

    def comb(a, b, ca, cb):
        return tuple(ca * a[i] + cb * b[i] for i in range(3))

    t = math.radians(turn)
    mer_u = comb(side, front, math.cos(t), math.sin(t))
    e1 = comb(side, front, math.cos(-t), math.sin(-t))
    e2 = cross(axis, e1)
    tip = math.radians(23.4)
    ecl_v = comb(e2, axis, math.cos(tip), math.sin(tip))

    rings = [
        # (radius, u, v, width)
        (33.0, side, front, 5.2),
        (39.5, mer_u, axis, 4.2),
        (45.5, e1, ecl_v, 3.8),
    ]
    runs = [_ring_runs(r, u, v) for r, u, v, _ in rings]

    # The far halves, dimmer, behind everything.
    for (r, u, v, w), (far, near) in zip(rings, runs):
        m = np.zeros((sh.H, sh.W), np.float32)
        for run in far:
            if len(run) > 1:
                m = np.maximum(m, sh.stroke(run, w))
        sh.part(m, C.GOLD_DIM, band=1.3, rim=0.6, line=1.0, wash=0.2)

    # The rod.
    ax2 = (axis[0], axis[1])
    rod = sh.stroke([(-ax2[0] * 50, -ax2[1] * 50), (ax2[0] * 50, ax2[1] * 50)],
                    3.4)
    sh.part(rod, C.GOLD, band=1.0, rim=0.5, line=0.9)

    # The heart: glass with a sun in it.
    hr = 17.0
    m = sh.circle(0, 0, hr)
    stops = [(0.0, (255, 252, 226)), (0.22, (255, 226, 120)),
             (0.55, (250, 150, 44)), (0.82, (200, 76, 20)),
             (1.0, (110, 30, 8))]
    col = np.empty(sh.X.shape + (3,), np.float32)
    xs = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    # The sun sits a little up and left of middle.
    r2 = np.sqrt((sh.X + 2.5) ** 2 + (sh.Y + 2.5) ** 2) / hr
    for c in range(3):
        col[..., c] = np.interp(np.clip(r2, 0, 1), xs, cs[:, c])
    sh.over(col, m)
    # Glass: a gloss on the upper left, a reflected glint lower right.
    gl = sh.ellipse(-6.5, -7.5, 6.5, 3.8, -38) * m
    sh.over((255, 255, 255), sh.soften(gl, 0.4) * 0.55)
    sh.over((255, 236, 190), sh.circle(7, 8, 2.2) * m * 0.6)
    sh.over(C.GOLD.line, sh.ring(m, 1.2))

    # The near halves, over the heart, each with a glint along its lit edge.
    for (r, u, v, w), (far, near) in zip(rings, runs):
        m = np.zeros((sh.H, sh.W), np.float32)
        gl = np.zeros((sh.H, sh.W), np.float32)
        for run in near:
            if len(run) > 1:
                m = np.maximum(m, sh.stroke(run, w))
                gl = np.maximum(gl, sh.stroke(
                    [(x + C.LIGHT[0] * w * 0.22, y + C.LIGHT[1] * w * 0.22)
                     for x, y in run], w * 0.22))
        sh.part(m, C.GOLD, band=1.5, rim=0.7, line=1.1, wash=0.25)
        sh.over(C.GOLD.glint, gl * m * 0.7)

    # Beads on the equator's near half.
    for k in range(12):
        a = math.radians(k * 30 + turn * 2)
        p = tuple(33.0 * (math.cos(a) * side[i] + math.sin(a) * front[i])
                  for i in range(3))
        if p[2] < -2:
            continue
        ramp = C.TURQUOISE if k % 2 == 0 else C.LAPIS
        bm = sh.circle(p[0], p[1], 2.9)
        sh.part(bm, ramp, band=1.0, rim=0.5, line=0.8, wash=0.3)
        sh.over(ramp.glint, sh.circle(p[0] - 0.9, p[1] - 0.9, 0.8) * 0.9)

    # Finials at both ends of the rod.
    for s in (1, -1):
        cx, cy = ax2[0] * 50 * s, ax2[1] * 50 * s
        tipm = sh.poly([(cx + ax2[0] * s * 10, cy + ax2[1] * s * 10),
                        (cx - ax2[1] * 2.4, cy + ax2[0] * 2.4),
                        (cx + ax2[1] * 2.4, cy - ax2[0] * 2.4)])
        sh.part(tipm, C.GOLD, band=0.8, rim=0.4, line=0.8)
        sh.part(sh.circle(cx, cy, 4.6), C.GOLD, band=1.4, rim=0.7, line=1.0)

    sh.outline(1.2, (14, 8, 4), 0.75)
    return sh.finish()


# ---------------------------------------------------------------------------
# The spellbook
# ---------------------------------------------------------------------------
#
# Seen spine-on, flying: the boards beat back from the spine like wings. Each
# board's cover is painted once, flat, and foreshortened onto the board's
# outline for each frame, as a 2D artist would redraw a panel turning away;
# the board turned away from the light darkens as it folds.

BOOK_W, BOOK_H = 116, 108
BOOK_ORIGIN = (58, 50)
BOARD_W = 46          # one board, spine to fore-edge
BOARD_H = 66
SPINE_HALF = 6.5
BOOK_FRAMES = 8


def cover_art():
    """One board's cover, flat, spine on the left: lapis leather, a double
    gilt border, gold mounts at the fore-edge corners set with turquoise,
    half a winged sun whose disc is the spine's boss, and an ankh. The two
    boards are mirror images. Returned at `SS` times size, for warping."""
    sh = C.Sheet(BOARD_W, BOARD_H, origin=(0, 0))
    W, H = BOARD_W, BOARD_H

    leather = sh.poly([(0, 0), (W, 0), (W, H), (0, H)])
    sh.part(leather, C.LAPIS, band=5, rim=1.0, line=0, wash=0.45, deep=0.3)
    # A fine grain in the leather.
    grain = np.asarray(A.fbm_field(sh.W, sh.H, 51, octaves=4, base=36),
                       np.float32) / 255.0
    sh.rgb *= (0.86 + 0.24 * grain)[..., None]

    # The double border (not along the joint at the spine).
    for inset, wid in ((2.4, 1.3), (5.2, 0.8)):
        pts = [(inset + 1.2, inset), (W - inset, inset), (W - inset, H - inset),
               (inset + 1.2, H - inset), (inset + 1.2, inset)]
        sh.part(sh.stroke(pts, wid), C.GOLD, band=0.4, rim=0.3, line=0.5,
                wash=0.1)

    # The mounts: a quarter-ring of scallops in each fore-edge corner, set
    # with a turquoise.
    for top in (True, False):
        pts = [(W, 0 if top else H)]
        for k in range(15):
            fk = k / 14.0
            a = math.radians(90 * fk)
            rr = 14.5 + 1.8 * math.cos(fk * math.pi * 5)
            y = rr * math.cos(a)
            pts.append((W - rr * math.sin(a), y if top else H - y))
        sh.part(sh.poly(pts), C.GOLD, band=1.6, rim=0.6, line=0.8)
        cy = 5.6 if top else H - 5.6
        st = sh.circle(W - 5.6, cy, 2.5)
        sh.part(st, C.TURQUOISE, band=0.8, rim=0.4, line=0.6)
        sh.over(C.TURQUOISE.glint, sh.circle(W - 6.3, cy - 0.7, 0.6))

    # Half of a winged sun, drawn across both boards and halved.
    both = Image.new("L", (sh.W * 2, sh.H), 0)
    SR.winged_disc(ImageDraw.Draw(both), sh.W, sh.H * 0.45, sh.W * 1.78,
                   ink=255, feathers=9)
    wing = np.asarray(both.crop((sh.W, 0, sh.W * 2, sh.H)),
                      np.float32) / 255.0
    # The disc itself is the spine's boss; keep it off the board.
    wing *= (1 - sh.circle(0, H * 0.45, 7.5))
    sh.part(wing, C.GOLD, band=0.7, rim=0.4, line=0.5, wash=0.3)

    # An ankh under the wing.
    ank, da = sh.canvas()
    GL.draw_glyph(da, "ankh", sh.W * 0.38, sh.H * 0.64, sh.W * 0.28,
                  sh.H * 0.25, ink=255)
    sh.part(sh.m(ank), C.GOLD, band=0.7, rim=0.4, line=0.6)

    rgb = sh.rgb / np.maximum(sh.a, 1e-6)[..., None]
    return A.from_arrays(rgb, sh.a)


_COVER = []


def book_frame(f, frames=BOOK_FRAMES):
    if not _COVER:
        _COVER.append(cover_art())
    cover = _COVER[0]
    sh = C.Sheet(BOOK_W, BOOK_H, origin=BOOK_ORIGIN)
    ph = 2 * math.pi * f / frames
    fold = 0.5 - 0.5 * math.cos(ph)            # 0 flat open .. 1 folded
    phi = math.radians(10 + 50 * fold)
    hh = BOARD_H / 2.0

    for s in (-1, 1):
        reach = BOARD_W * math.cos(phi)
        # The fore-edge, further away as it folds, is drawn a little shorter
        # and a little higher: the board is turning away.
        far = math.sin(phi)
        x0 = s * SPINE_HALF
        x1 = s * (SPINE_HALF + reach)
        quad = [(x0, -hh), (x1, -hh + 5 * far), (x1, hh - 2 * far), (x0, hh)]
        if s < 0:
            # The cover is painted spine-left; mirror it for the left board
            # and list its corners so the spine side comes first.
            src = cover.transpose(Image.FLIP_LEFT_RIGHT)
            q = [quad[1], quad[0], quad[3], quad[2]]
        else:
            src = cover
            q = quad

        # The gilt edge of the pages, showing under the board's foot.
        foot = sh.poly([(x0, hh - 1), (x1, hh - 2 * far - 1),
                        (x1 - s * 1.5, hh - 2 * far + 2.6),
                        (x0, hh + 3.0)])
        sh.part(foot, C.GOLD_DIM, band=0.6, rim=0.3, line=0.7, wash=0.1)
        # The board's thickness along its fore-edge.
        edge = sh.poly([(x1, -hh + 5 * far), (x1 + s * 2.0, -hh + 5 * far + 1),
                        (x1 + s * 2.0, hh - 2 * far + 1), (x1, hh - 2 * far)])
        sh.part(edge, C.LAPIS, band=0.8, rim=0, line=0.8, wash=0)

        img = C.warp_quad(src, (sh.W, sh.H), [sh.p(x, y) for x, y in q])
        arr = np.asarray(img, np.float32)
        rgb, a = arr[..., :3], arr[..., 3] / 255.0
        # Turned away from the light, it darkens; toward it, it brightens.
        k = (1 + 0.12 * far) if s < 0 else (1 - 0.42 * far)
        sh.over(rgb * k, a)
        sh.over(C.LAPIS.line, sh.ring((a > 0.5).astype(np.float32), 1.1))

    # The spine: leather between raised gold bands, a boss with a carnelian.
    spine = sh.poly([(-SPINE_HALF, -hh - 1), (SPINE_HALF, -hh - 1),
                     (SPINE_HALF, hh + 1), (-SPINE_HALF, hh + 1)])
    sh.part(spine, C.LAPIS, band=4.2, rim=1.2, line=1.0, wash=0.4)
    for k in range(6):
        y = -hh + 3 + k * (BOARD_H - 6) / 5.0
        band = sh.ellipse(0, y, SPINE_HALF + 1.2, 2.0)
        sh.part(band, C.GOLD, band=1.2, rim=0.6, line=0.8, wash=0.3)
    by = BOARD_H * 0.45 - hh
    sh.part(sh.circle(0, by, 8.6), C.GOLD, band=2.6, rim=1.0, line=1.0)
    sh.part(sh.circle(0, by, 5.2), C.CARNELIAN, band=1.8, rim=0.8, line=0.8)
    sh.over(C.CARNELIAN.glint, sh.circle(-1.6, by - 1.8, 1.3) * 0.9)

    # The marker, waving from the foot of the spine, with a gold tag.
    rib = [(math.sin(ph - t * 3.2) * 6.5 * t + 1.5 * t, hh + 1 + t * 20)
           for t in [k / 24.0 for k in range(25)]]
    sh.part(sh.stroke(rib, 3.0, 2.4), C.CRIMSON, band=1.0, rim=0.5, line=0.8)
    tx, ty = rib[-1]
    sh.part(sh.poly([(tx, ty - 1), (tx + 2.6, ty + 2.4), (tx, ty + 5.6),
                     (tx - 2.6, ty + 2.4)]), C.GOLD, band=0.8, rim=0.4,
            line=0.7)

    sh.outline(1.2, (8, 6, 18), 0.8)
    return sh.finish()


# ---------------------------------------------------------------------------
# The soul-flame
# ---------------------------------------------------------------------------
#
# A flame is a density field: a round heart and three tongues tapering
# upward, their sides pushed about by a sum of travelling waves that grow
# with height (the waves' phases step a whole number of turns over the loop,
# so it repeats seamlessly). Its colour runs in soft bands from a dark lapis
# fringe, which is the dark edge every bullet and foe here has, through teal
# and turquoise to a white heart. An ankh hangs in the heart, dark against
# the light behind it.

WISP_W, WISP_H = 92, 124
WISP_ORIGIN = (46, 76)          # the heart
WISP_FRAMES = 8

WISP_RAMP = [(0.00, (18, 26, 92)), (0.16, (22, 70, 150)),
             (0.34, (22, 150, 188)), (0.56, (58, 226, 222)),
             (0.78, (180, 252, 244)), (1.00, (255, 255, 255))]


def _ramp(stops, t):
    xs = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, xs, cs[:, c])
    return out


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def wisp_frame(f, frames=WISP_FRAMES):
    sh = C.Sheet(WISP_W, WISP_H, origin=WISP_ORIGIN)
    X, Y = sh.X, sh.Y
    ph = 2 * math.pi * f / frames

    up = np.clip(-Y / 62.0, 0, 1.5)
    # Travelling waves up the flame: (spatial frequency, turns per loop,
    # amplitude, phase).
    waves = [(0.090, 1, 5.5, 0.0), (0.170, 2, 3.0, 1.7), (0.050, 1, 4.0, 4.1),
             (0.260, 3, 1.4, 2.6)]
    wx = np.zeros_like(X)
    for k, turns, amp, off in waves:
        wx += amp * np.sin(Y * k + turns * ph + off)
    wx *= up ** 1.25
    breathe = 1 + 0.04 * math.sin(ph * 2)

    def tongue(cx, lean, tip, width):
        """Density of one tongue: a teardrop from the heart up to `tip`
        pixels high, `width` wide at its root, leaning `lean` at its tip."""
        h = np.clip(-Y / tip, 0, None)
        xx = X + wx - cx - lean * h * h
        half = np.where(Y < 0, width * np.clip(1 - h, 0, 1) ** 0.85,
                        np.sqrt(np.clip(width ** 2 - Y ** 2, 0, None)))
        return (1 - (xx / np.maximum(half, 1e-3)) ** 2
                - np.clip(h - 1, 0, None) * 50)

    d = tongue(0, 0, 66, 18.0 * breathe)
    d = np.maximum(d, tongue(-7, -8, 44, 11.0) - 0.05)
    d = np.maximum(d, tongue(7, 8, 38, 10.0) - 0.05)
    band = 0.5 + 0.5 * np.sin(Y * 0.30 + 3 * ph + X * 0.08)

    alpha = _smooth(0.0, 0.40, d)
    core = np.exp(-(X ** 2 + (Y - 4) ** 2) / (2 * 6.0 ** 2))
    t = (np.clip(d, 0, 1) ** 1.5) * (1 - 0.40 * np.clip(up, 0, 1)) \
        * (0.80 + 0.20 * band) * 0.78
    t = np.clip(t + core * 0.42, 0, 1)
    # Painted in bands rather than a smooth ramp: each tone eased into the
    # next over a narrow step.
    steps = 6.0
    q = np.floor(t * steps) / steps
    fracp = t * steps - np.floor(t * steps)
    t = q + _smooth(0.55, 1.0, fracp) / steps
    sh.over(_ramp(WISP_RAMP, t), alpha)

    # The ankh, dark against the light behind it, lit along its top edges.
    ank, da = sh.canvas()
    aw, ah = 13 * SS, 25 * SS
    cx, cy = sh.p(0, -9 + math.sin(ph))
    GL.draw_glyph(da, "ankh", cx - aw / 2, cy - ah / 2, aw, ah, ink=255)
    am = sh.soften(sh.m(ank), 0.3)
    halo = sh.soften(sh.m(ank), 2.2)
    sh.add((60, 40, 10), halo * (1 - am) * alpha)
    sh.part(am, C.Ramp((40, 26, 8), (70, 48, 18), (96, 68, 26),
                       (200, 230, 180), line=(10, 30, 50)),
            band=0.8, rim=0.7, line=0.6, wash=0.2)
    return sh.finish()


# ---------------------------------------------------------------------------
# The sand golem: a sand elemental
# ---------------------------------------------------------------------------
#
# It is painted as sand in motion: under everything, the dark of its hollow
# body with a banked fire toward its heart; over that, ribbons of sand laid
# along the currents that make it up (swirling round each shoulder and round
# the cowl of its head, and running down its body into the column it stands
# on), in layers from dark to light, each ribbon cel-shaded with its own line.
# Between the ribbons the dark and the fire show. Frame to frame each ribbon
# slides along its current, so the whole of it streams; streamers of sand
# blow off its shoulders and cowl in the wind.

GOLEM_W, GOLEM_H = 380, 340
GOLEM_ORIGIN = (190, 170)        # the heart
GOLEM_FRAMES = 8

FIST_SIZE = 124
FIST_FRAMES = 8

# Where its masses turn (final pixels from the heart).
GOLEM_SHOULDERS = ((-112, -62), (112, -62))
GOLEM_FACE = (0, -118)

SAND_DARK = C.Ramp((50, 26, 12), (92, 56, 28), (132, 88, 46), (178, 130, 74),
                   (214, 170, 110), (34, 16, 6))
SAND_MID = C.Ramp((70, 40, 18), (126, 82, 40), (176, 128, 72), (220, 178, 114),
                  (246, 216, 160), (40, 20, 8))
HOLLOW = (44, 20, 8)
EMBER = np.array((255, 128, 40), np.float32)


def _grains(sh, mask, f, frames, n, seed, drift=(1.5, 2.5)):
    """Specks of darker and lighter sand over a mass, streaming a little
    each frame."""
    r = np.random.default_rng(seed)
    x0, x1 = float(sh.X.min()), float(sh.X.max())
    y0, y1 = float(sh.Y.min()), float(sh.Y.max())
    x = r.uniform(x0, x1, n) + drift[0] * f / frames * 8
    y = r.uniform(y0, y1, n) + drift[1] * f / frames * 8
    img_d, dd = sh.canvas()
    img_l, dl = sh.canvas()
    for i in range(n):
        px, py = sh.p(x[i], y[i])
        rr = r.uniform(0.35, 0.8) * sh.ss
        (dd if i % 3 else dl).ellipse([px - rr, py - rr, px + rr, py + rr],
                                      fill=255)
    sh.over(C.SAND.deep, sh.m(img_d) * mask * 0.45)
    sh.over(C.SAND.glint, sh.m(img_l) * mask * 0.45)


def _loose(sh, mask, f, frames, n, seed, wind=(1.0, -0.5)):
    """Grains blown off the edges of a mass, drifting with the wind."""
    r = np.random.default_rng(seed)
    inside = mask > 0.5
    d = ndimage.distance_transform_edt(~inside) / sh.ss
    ys, xs = np.nonzero((d > 0.5) & (d < 10))
    if len(xs) == 0:
        return
    pick = r.choice(len(xs), size=min(n, len(xs)), replace=False)
    img, dr = sh.canvas()
    ph = f / float(frames)
    for i in pick:
        age = (ph + r.uniform(0, 1)) % 1.0
        px = xs[i] + wind[0] * age * 16 * sh.ss
        py = ys[i] + wind[1] * age * 16 * sh.ss
        rr = r.uniform(0.4, 0.95) * sh.ss * (1 - age * 0.5)
        dr.ellipse([px - rr, py - rr, px + rr, py + rr],
                   fill=int(255 * (1 - age)))
    g = sh.m(img)
    sh.over(C.SAND.light, g * 0.9)


def _warp(sh, mask, f, frames, amp=3.0, seed=0):
    """A mask pushed about by a looping field of waves: the churn."""
    ph = 2 * math.pi * f / frames
    r = np.random.default_rng(seed)
    dx = np.zeros_like(sh.X)
    dy = np.zeros_like(sh.X)
    for _ in range(4):
        kx, ky = r.uniform(0.03, 0.09, 2)
        off = r.uniform(0, 2 * math.pi)
        turns = int(r.integers(1, 3))
        dx += np.sin(sh.Y * ky + sh.X * kx * 0.5 + turns * ph + off)
        dy += np.cos(sh.X * kx + sh.Y * ky * 0.5 - turns * ph + off * 1.3)
    dx *= amp / 4.0 * sh.ss
    dy *= amp / 4.0 * sh.ss
    ys, xs = np.mgrid[0:sh.H, 0:sh.W].astype(np.float32)
    return ndimage.map_coordinates(mask, [ys + dy, xs + dx], order=1,
                                   mode="constant", cval=0.0)


class Currents:
    """The directions the sand runs in, over a silhouette: along its
    contours (so ribbons wrap the form), stirred into whirls round given
    centres, and pulled along `drift`. Sampled at final-pixel resolution."""

    def __init__(self, sh, mask, whirls, drift=(0.0, 0.0), wrap=1.0,
                 stir=0.0, seed=0):
        k = sh.ss
        small = mask[::k, ::k] > 0.5
        self.inside = small
        self.ox, self.oy = sh.ox, sh.oy
        d = ndimage.distance_transform_edt(small).astype(np.float32)
        d = ndimage.gaussian_filter(d, 2.0)
        gy, gx = np.gradient(d)
        l = np.maximum(1e-4, np.hypot(gx, gy))
        # Along the contour, one way round.
        tx, ty = -gy / l, gx / l
        ys, xs = np.mgrid[0:small.shape[0], 0:small.shape[1]].astype(np.float32)
        X = xs + 0.5 - sh.ox
        Y = ys + 0.5 - sh.oy
        vx = tx * wrap + drift[0]
        vy = ty * wrap + drift[1]
        for (cx, cy, r, sense, gain) in whirls:
            rx, ry = X - cx, Y - cy
            dd = np.maximum(1e-3, np.hypot(rx, ry))
            w = np.exp(-(dd / r) ** 2) * gain
            vx += -ry / dd * w * sense
            vy += rx / dd * w * sense
        # Turbulence: the curl of a few crossed waves, so no two currents
        # run quite parallel.
        if stir > 0:
            rng_ = np.random.default_rng(seed)
            psi = np.zeros_like(X)
            for _ in range(5):
                kx, ky = rng_.uniform(0.03, 0.11, 2)
                psi += np.sin(X * kx + rng_.uniform(0, 6)) * np.cos(
                    Y * ky + rng_.uniform(0, 6)) / (kx + ky)
            py_, px_ = np.gradient(psi)
            vx += py_ * stir
            vy += -px_ * stir
        l = np.maximum(1e-4, np.hypot(vx, vy))
        self.vx, self.vy = vx / l, vy / l

    def at(self, x, y):
        i = int(round(y + self.oy - 0.5))
        j = int(round(x + self.ox - 0.5))
        if i < 0 or j < 0 or i >= self.vx.shape[0] or j >= self.vx.shape[1]:
            return None
        return self.vx[i, j], self.vy[i, j], self.inside[i, j]

    def trace(self, x, y, steps=22, step=2.6, spill=3):
        """A streamline through (x, y), both ways, stopping `spill` steps
        after it leaves the silhouette."""
        pts = [(x, y)]
        for sgn in (1, -1):
            px, py = x, y
            out = 0
            run = []
            for _ in range(steps):
                v = self.at(px, py)
                if v is None:
                    break
                vx, vy, inside = v
                if not inside:
                    out += 1
                    if out > spill:
                        break
                px += vx * step * sgn
                py += vy * step * sgn
                run.append((px, py))
            pts = (run[::-1] + pts) if sgn < 0 else (pts + run)
        return pts


def _ribbon_layers(sh, cur, mask, f, frames, n_layers, spacing, width,
                   seed, length=0.62):
    """Ribbons of sand along the currents: streamlines seeded on a jittered
    grid over the mask, each carrying one dash that slides along it over the
    loop, sorted into layers. Returns a mask per layer, back to front."""
    r = np.random.default_rng(seed)
    small = cur.inside
    layers = [np.zeros((sh.H, sh.W), np.float32) for _ in range(n_layers)]
    ph = f / float(frames)
    for gy in np.arange(0, small.shape[0], spacing):
        for gx in np.arange(0, small.shape[1], spacing):
            x = gx + r.uniform(0, spacing) - sh.ox
            y = gy + r.uniform(0, spacing) - sh.oy
            v = cur.at(x, y)
            if v is None or not v[2]:
                continue
            path = cur.trace(x, y)
            if len(path) < 6:
                continue
            n = len(path)
            off = r.uniform(0, 1)
            start = ((off + ph) % 1.0) * n - n * length * 0.5
            i0 = int(max(0, start))
            i1 = int(min(n - 1, start + n * length))
            if i1 - i0 < 3:
                continue
            w = width * r.uniform(0.5, 1.35)
            m = sh.stroke(path[i0:i1 + 1], w, w * r.uniform(0.3, 0.8),
                          taper=0.9)
            li = int(r.integers(0, n_layers))
            layers[li] = np.maximum(layers[li], m)
    return layers


def golem_silhouette(sh):
    """The elemental's outline (unchurned): a torso narrowing into the
    column it stands on, a mass at each shoulder, and a cowl of sand round
    a hollow face."""
    torso = sh.poly([(-150, -56), (-120, -94), (-56, -100), (0, -94),
                     (56, -100), (120, -94), (150, -56), (140, -18),
                     (100, 20), (74, 58), (44, 96), (16, 128), (-16, 128),
                     (-44, 96), (-74, 58), (-100, 20), (-140, -18)],
                    smooth=True)
    shoulders = np.maximum(sh.circle(GOLEM_SHOULDERS[0][0],
                                     GOLEM_SHOULDERS[0][1], 50),
                           sh.circle(GOLEM_SHOULDERS[1][0],
                                     GOLEM_SHOULDERS[1][1], 50))
    cowl = sh.poly([(-44, -92), (-50, -122), (-40, -150), (-16, -168),
                    (10, -170), (34, -158), (50, -132), (48, -100),
                    (26, -86), (-24, -86)], smooth=True)
    face = sh.ellipse(GOLEM_FACE[0], GOLEM_FACE[1] + 2, 25, 21)
    return np.maximum.reduce([torso, shoulders, cowl]), face


def golem_currents(sh, body):
    return Currents(sh, body, [
        (GOLEM_SHOULDERS[0][0], GOLEM_SHOULDERS[0][1], 46, 1, 2.2),
        (GOLEM_SHOULDERS[1][0], GOLEM_SHOULDERS[1][1], 46, -1, 2.2),
        (GOLEM_FACE[0], GOLEM_FACE[1], 38, 1, 2.0),
        (0, 30, 70, -1, 0.9),
    ], drift=(0.0, 0.35), wrap=0.7, stir=0.9, seed=5)


def _streamers(sh, f, frames):
    """Sand blown off its shoulders and cowl, curling up and away: each a
    point list, root first."""
    ph = 2 * math.pi * f / float(frames)
    out = []
    roots = [(-158, -66, -1, 1.0), (-146, -92, -1, 0.8), (-120, -108, -1, 0.7),
             (158, -66, 1, 1.0), (146, -92, 1, 0.8), (120, -108, 1, 0.7),
             (-30, -166, -1, 0.6), (26, -170, 1, 0.7), (44, -156, 1, 0.5)]
    for k, (x, y, s, size) in enumerate(roots):
        pts = []
        for j in range(16):
            t = j / 15.0
            curl = math.sin(t * 2.6 + ph + k * 1.7) * 9 * t
            pts.append((x + s * (t * 64 * size + curl),
                        y - t * 30 * size - t * t * 34 * size))
        out.append((pts, size))
    return out


def golem_body_frame(f, frames=GOLEM_FRAMES):
    sh = C.Sheet(GOLEM_W, GOLEM_H, origin=GOLEM_ORIGIN)
    body, face = golem_silhouette(sh)
    body = _warp(sh, body, f, frames, 2.2, 1)
    # Its foot thins into the column it stands on (drawn in the game).
    fade = np.clip((128 - sh.Y) / 46.0, 0, 1)
    cur = golem_currents(sh, body)

    # The hollow under the sand, and the fire banked in it toward the heart.
    under = body * fade
    sh.over(HOLLOW, under)
    d = np.hypot(sh.X, sh.Y - 22)
    sh.add(EMBER * 0.55, np.exp(-(d / 70.0) ** 2) * under)
    sh.add(EMBER * 0.25, np.exp(-(d / 140.0) ** 2) * under)

    # The streamers behind everything else: wisps of sand thinning to
    # nothing, and fading as they go.
    for pts, size in _streamers(sh, f, frames):
        x0, y0 = pts[0]
        x1, y1 = pts[-1]
        along = ((sh.X - x0) * (x1 - x0) + (sh.Y - y0) * (y1 - y0)) / max(
            1.0, (x1 - x0) ** 2 + (y1 - y0) ** 2)
        fadeout = np.clip(1.05 - along, 0, 1) ** 1.5
        # A few thin strands, fanning apart as they go.
        m = np.zeros((sh.H, sh.W), np.float32)
        for j, spread in enumerate((-1.0, 0.0, 1.0)):
            strand = [(x + spread * t * 7, y + spread * t * 5)
                      for t, (x, y) in zip(np.linspace(0, 1, len(pts)), pts)]
            m = np.maximum(m, sh.stroke(strand, (4.2 - abs(spread)) * size + 1,
                                        0.4))
        sh.part(m * fadeout, SAND_MID, band=1.2, rim=0.7, line=0.5,
                wash=0.35, alpha=0.8, line_alpha=0.3)

    # The ribbons, dark layers first; the fire inside lights the ribbons
    # near the heart from beneath.
    layers = _ribbon_layers(sh, cur, body, f, frames, 6, 9, 6.8, 101,
                            length=0.42)
    ramps = [SAND_DARK, SAND_DARK, SAND_MID, SAND_MID, C.SAND, C.SAND]
    firelit = np.exp(-(np.hypot(sh.X, sh.Y - 22) / 85.0) ** 2)
    for k, (m, rp) in enumerate(zip(layers, ramps)):
        sh.part(m * fade, rp, band=2.2, rim=1.0, line=0.9, wash=0.35,
                deep=0.35, soft=0.3, line_alpha=0.7)
        sh.add(EMBER * 0.30, m * fade * firelit)
    _heart(sh)

    # The face: a hollow in the cowl, and the eyes burning in it.
    face_m = _warp(sh, face, f, frames, 1.2, 7)
    sh.over(HOLLOW, sh.soften(face_m, 1.0) * 0.96)
    sh.add(EMBER * 0.35, sh.soften(face_m, 4.0) * face_m)
    for s in (-1, 1):
        eye = sh.poly([(s * 5, -117), (s * 20, -123), (s * 21, -118),
                       (s * 7, -112)])
        sh.over((255, 168, 70), sh.soften(eye, 0.3))

    _grains(sh, body * fade, f, frames, 1500, 12)
    _loose(sh, body * fade, f, frames, 340, 21)
    sh.outline(1.1, (28, 12, 4), 0.55)
    return sh.finish()


def _heart(sh):
    """The one hard thing in it: a small winged amulet of gold set with a
    carnelian, which binds the sand."""
    hy = 22
    for s in (-1, 1):
        for k in range(5):
            a = math.radians(-8 + k * 11)
            ln = 30 - k * 4
            x0, y0 = s * 12, hy - 2 + k * 1.5
            x1 = x0 + s * ln * math.cos(a)
            y1 = y0 - ln * math.sin(a) * 0.7 + k * 1.2
            fm = sh.stroke([(x0, y0), (x1, y1)], 5.5 - k * 0.5, 1.4)
            sh.part(fm, C.GOLD, band=1.2, rim=0.6, line=0.8, wash=0.3)
    sh.part(sh.circle(0, hy, 15), C.GOLD, band=3.2, rim=1.2, line=1.2)
    sh.part(sh.circle(0, hy, 10.5), C.CARNELIAN, band=3, rim=1.2, line=1.0)
    sh.over(C.CARNELIAN.glint, sh.soften(sh.circle(-3.5, hy - 4, 2.4), 0.3))


def golem_glow_frame(f, frames=GOLEM_FRAMES):
    """What of it burns, drawn added over the body: its eyes, its heart,
    and the fire in the gaps between the ribbons, pulsing outward from the
    heart."""
    sh = C.Sheet(GOLEM_W, GOLEM_H, origin=GOLEM_ORIGIN)
    body, face = golem_silhouette(sh)
    body = _warp(sh, body, f, frames, 2.2, 1)
    fade = np.clip((128 - sh.Y) / 46.0, 0, 1)
    cur = golem_currents(sh, body)
    ph = 2 * math.pi * f / frames

    # The gaps: the body where the front ribbons are not.
    layers = _ribbon_layers(sh, cur, body, f, frames, 6, 9, 6.8, 101,
                            length=0.42)
    cover = np.clip(np.maximum.reduce(layers[2:]) * 1.2, 0, 1)
    gaps = body * fade * (1 - cover)
    d = np.hypot(sh.X, sh.Y - 22)
    pulse = 0.55 + 0.45 * np.cos(d / 26.0 - ph * 2)
    fire = gaps * np.exp(-(d / 120.0) ** 2) * pulse
    sh.over((255, 120, 36), sh.soften(fire, 1.0) * 0.8)

    eyes = np.zeros((sh.H, sh.W), np.float32)
    for s in (-1, 1):
        eyes = np.maximum(eyes, sh.poly([(s * 5, -117), (s * 20, -123),
                                         (s * 21, -118), (s * 7, -112)]))
    sh.over((255, 140, 40), sh.soften(eyes, 3.0) * 0.8)
    sh.over((255, 240, 190), sh.soften(eyes, 0.3))

    sh.over((255, 110, 40), sh.soften(sh.circle(0, 22, 10.5), 4.0) * 0.6)
    sh.over((255, 210, 150), sh.soften(sh.circle(-1, 20, 6), 1.5) * 0.7)
    return sh.finish()


def fist_frame(f, frames=FIST_FRAMES):
    """The left fist: sand wound into a clenched fist, knuckles, fingers and
    a thumb across them, its wrist streaming up to the arm. (The game
    mirrors it for the right.)"""
    sh = C.Sheet(FIST_SIZE, FIST_SIZE)
    palm = sh.poly([(-34, -20), (-8, -26), (26, -24), (38, -10), (40, 16),
                    (26, 36), (-6, 40), (-32, 30), (-40, 6)], smooth=True)
    wrist = sh.poly([(-22, -18), (22, -18), (14, -60), (-12, -60)])
    wrist *= np.clip((sh.Y + 62) / 30.0, 0, 1)
    knuckles = [sh.circle(x, -20, 10.5) for x in (-25, -8, 9, 26)]
    thumb = sh.stroke([(-38, 8), (-18, 18), (4, 20)], 15, 12)
    fist = np.maximum.reduce([palm, wrist, thumb] + knuckles)
    fist = _warp(sh, fist, f, frames, 1.4, 42)

    # The dark inside it, with a little of the fire.
    sh.over(HOLLOW, fist)
    sh.add(EMBER * 0.30, np.exp(-(np.hypot(sh.X, sh.Y - 4) / 30.0) ** 2)
           * fist)

    # Sand running round it and up the wrist...
    cur = Currents(sh, fist, [(0, 6, 34, 1, 1.4)], drift=(0, -0.4), wrap=1.0)
    layers = _ribbon_layers(sh, cur, fist, f, frames, 3, 7, 5.0, 202,
                            length=0.45)
    for m, rp in zip(layers[:2], [SAND_DARK, SAND_MID]):
        sh.part(m, rp, band=1.8, rim=0.8, line=0.8, wash=0.3, deep=0.3,
                line_alpha=0.7)
    # ...the fist's own forms over it, so it reads as a fist: the palm and
    # thumb, then the knuckles standing proud of them...
    for k, m in enumerate([palm, thumb]):
        sh.part(_warp(sh, m, f, frames, 1.0, 45 + k), SAND_MID, band=5,
                rim=1.4, line=1.1, wash=0.55, deep=0.4, alpha=0.9)
    sh.part(layers[2] * palm * 0.7, C.SAND, band=1.4, rim=0.7, line=0.6,
            wash=0.3, deep=0.3, line_alpha=0.5)
    for k, m in enumerate(knuckles):
        sh.part(_warp(sh, m, f, frames, 0.8, 47 + k), C.SAND, band=4,
                rim=1.6, line=1.2, wash=0.6, deep=0.45)
    # The creases between the fingers.
    for x in (-16.5, 0.5, 17.5):
        sh.over(C.SAND.deep, sh.stroke([(x, -18), (x + 1, -2)], 1.4, 0.6,
                                       taper=0.5) * palm * 0.6)
    _grains(sh, fist, f, frames, 200, 51, drift=(0, -2))
    _loose(sh, fist, f, frames, 90, 52, wind=(0.3, -1.0))
    sh.outline(1.1, (28, 12, 4), 0.55)
    return sh.finish()


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------

def page_frames():
    """Three loose leaves: parchment, a few lines of text, a gilt edge."""
    out = []
    for k in range(3):
        sh = C.Sheet(24, 28)
        a = math.radians([-8, 6, 14][k])
        c, s = math.cos(a), math.sin(a)

        def R(x, y):
            return (x * c - y * s, x * s + y * c)

        w, h = 7.5, 10
        pts = [R(-w, -h), R(w, -h + 1), R(w + 0.6, h), R(-w + 0.8, h - 1)]
        m = sh.poly(pts)
        sh.part(m, C.PARCHMENT, band=2.0, rim=0.8, line=0.8, wash=0.4)
        for j in range(4):
            yy = -6 + j * 3.6
            ln = sh.stroke([R(-4.5, yy), R(4.5 - (j % 2) * 2, yy + 0.3)], 0.9)
            sh.over((90, 70, 44), ln * m * 0.7)
        sh.over(C.GOLD.base, sh.stroke([pts[1], pts[2]], 1.4) * 0.9)
        out.append(sh.finish())
    return out


def gilt_frames():
    """Three shards of gold."""
    shapes = [[(-6, -3), (5, -5), (7, 2), (-2, 5)],
              [(-5, -5), (6, -1), (1, 6), (-6, 2)],
              [(-7, 0), (-1, -5), (7, -2), (3, 4), (-3, 4)]]
    out = []
    for pts in shapes:
        sh = C.Sheet(18, 14)
        m = sh.poly(pts)
        sh.part(m, C.GOLD, band=1.8, rim=1.0, line=0.8, wash=0.5)
        sh.over(C.GOLD.glint, sh.stroke([pts[0], pts[1]], 0.8) * m * 0.8)
        out.append(sh.finish())
    return out


def grit_frames():
    """Three grains of sand."""
    shapes = [[(-3, -2), (2, -3), (3, 1), (-1, 3)],
              [(-3, 0), (0, -3), (3, -1), (2, 3), (-2, 2)],
              [(-2, -3), (3, -2), (2, 2), (-3, 2)]]
    out = []
    for pts in shapes:
        sh = C.Sheet(12, 12)
        m = sh.poly(pts, smooth=True)
        sh.part(m, C.SAND, band=1.3, rim=0.7, line=0.7, wash=0.4)
        out.append(sh.finish())
    return out


def _glyph_at(sh, name, x, y, w, h, angle):
    """A glyph's mask, `w` by `h` final pixels, centred on (x, y) and turned
    `angle` degrees."""
    g = Image.new("L", (int(w * SS), int(h * SS)), 0)
    GL.draw_glyph(ImageDraw.Draw(g), name, 0, 0, w * SS, h * SS, ink=255)
    g = g.rotate(-angle, expand=True, resample=Image.BICUBIC)
    img, _ = sh.canvas()
    cx, cy = sh.p(x, y)
    img.paste(255, (int(cx - g.width / 2), int(cy - g.height / 2)), g)
    return sh.m(img)


def summon_frame():
    """The glyph a foe steps out of: two rings with a band of glyphs between
    them, four ankhs round an eye inside. White; tinted in the game."""
    sh = C.Sheet(192, 192)
    white = (255, 255, 255)
    for r, w in ((90, 2.4), (80, 1.2), (58, 1.6)):
        pts = [(math.cos(t) * r, math.sin(t) * r)
               for t in np.linspace(0, 2 * math.pi, 180)]
        sh.over(white, sh.stroke(pts, w))
    names = ["ankh", "djed", "was", "nefer"]
    for k in range(16):
        a = 2 * math.pi * k / 16
        sh.over(white, _glyph_at(sh, names[k % 4], math.cos(a) * 69,
                                 math.sin(a) * 69, 8, 16,
                                 math.degrees(a) + 90))
    for k in range(4):
        a = 2 * math.pi * k / 4 + math.pi / 4
        sh.over(white, _glyph_at(sh, "ankh", math.cos(a) * 36,
                                 math.sin(a) * 36, 10, 22,
                                 math.degrees(a) + 90))
    sh.over(white, _glyph_at(sh, "eye", 0, 0, 32, 24, 0))
    return sh.finish()


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

def preview_on(img, bg=(24, 20, 34), scale=2):
    big = img.resize((img.width * scale, img.height * scale), Image.LANCZOS)
    c = Image.new("RGBA", big.size, tuple(bg) + (255,))
    c.alpha_composite(big)
    return c


def build_all():
    return {
        "spr_foe_hall_sphere": [sphere_frame(f) for f in range(SPHERE_FRAMES)],
        "spr_foe_hall_book": [book_frame(f) for f in range(BOOK_FRAMES)],
        "spr_foe_hall_wisp": [wisp_frame(f) for f in range(WISP_FRAMES)],
        "spr_golem_body": [golem_body_frame(f) for f in range(GOLEM_FRAMES)],
        "spr_golem_glow": [golem_glow_frame(f) for f in range(GOLEM_FRAMES)],
        "spr_golem_fist": [fist_frame(f) for f in range(FIST_FRAMES)],
        "spr_fx_page": page_frames(),
        "spr_fx_gilt": gilt_frames(),
        "spr_fx_grit": grit_frames(),
        "spr_fx_summon": [summon_frame()],
    }


ORIGINS = {
    "spr_foe_hall_wisp": WISP_ORIGIN,
    "spr_foe_hall_book": BOOK_ORIGIN,
    "spr_golem_body": GOLEM_ORIGIN,
    "spr_golem_glow": GOLEM_ORIGIN,
}


def preview(sprites):
    """The foes on a dark ground, the golem put together as the game puts
    it, and the pieces."""
    tiles = []
    for name in ("spr_foe_hall_sphere", "spr_foe_hall_book",
                 "spr_foe_hall_wisp"):
        for fr in sprites[name][:4]:
            tiles.append(preview_on(fr))
    A.preview(tiles, os.path.join(A.PREVIEW, "hall_foes.png"), cols=4,
              bg=(18, 14, 26))

    body = sprites["spr_golem_body"][0]
    glow = sprites["spr_golem_glow"][0]
    fist = sprites["spr_golem_fist"][0]
    W, H = 640, 420
    c = Image.new("RGBA", (W, H), (22, 18, 30, 255))
    ox, oy = W // 2, 190
    x0, y0 = ox - GOLEM_ORIGIN[0], oy - GOLEM_ORIGIN[1]
    c.alpha_composite(body, (x0, y0))
    arr = np.asarray(c, np.float32).copy()
    gl = np.asarray(glow, np.float32)
    arr[y0:y0 + gl.shape[0], x0:x0 + gl.shape[1], :3] += (
        gl[..., :3] * gl[..., 3:4] / 255.0)
    c = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    for s in (-1, 1):
        fi = fist if s < 0 else fist.transpose(Image.FLIP_LEFT_RIGHT)
        c.alpha_composite(fi, (ox + s * 208 - FIST_SIZE // 2,
                               oy + 64 - FIST_SIZE // 2))
    c.save(os.path.join(A.PREVIEW, "hall_golem.png"))

    extras = (sprites["spr_fx_page"] + sprites["spr_fx_gilt"]
              + sprites["spr_fx_grit"])
    A.preview([preview_on(e, scale=4) for e in extras]
              + [preview_on(sprites["spr_fx_summon"][0], scale=1)],
              os.path.join(A.PREVIEW, "hall_pieces.png"), cols=10,
              bg=(18, 14, 26))


def main():
    only_preview = "--preview" in sys.argv
    sprites = build_all()
    preview(sprites)
    print("-> tools/_preview/hall_foes.png, hall_golem.png, hall_pieces.png")
    if only_preview:
        return

    import gm_new
    gm_new.folder("Sprites/foes")
    gm_new.folder("Sprites/fx")
    for name, frames in sprites.items():
        folder = "Sprites/fx" if name.startswith("spr_fx_") else "Sprites/foes"
        gm_new.sprite(name, frames, origin=ORIGINS.get(name, "center"),
                      folder=folder, fps=10.0)
        print("%-22s %2d frames of %dx%d" % (name, len(frames),
                                             frames[0].width,
                                             frames[0].height))


if __name__ == "__main__":
    main()
