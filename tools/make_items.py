#!/usr/bin/env python3
"""The pickups: three cut stones, ray-traced and spun, and the two small
effects that go with them.

    spr_item_red    a ruby, round brilliant cut        life
    spr_item_blue   a sapphire, double-terminated      sigil
    spr_item_gold   a citrine, octahedron              points
    spr_fx_glint    the twinkle a stone throws off now and then
    spr_fx_shard    a sliver of crystal, for the burst when one is caught

**Each stone is a different cut, not the same shape in three colours**, so the
three read apart by silhouette before they read apart by hue: a diamond ◆ for
points, a tall hexagonal crystal for the sigil, a brilliant 💎 for life. Hue
alone would leave a colour-blind player guessing, and at twenty pixels the
silhouette is the first thing anybody reads.

How they are drawn
------------------

**A real stone, traced.** Each cut is a convex solid written as the facet
planes a gem cutter would name -- a table, bezels, stars, pavilion mains -- and
every pixel fires a ray into it: a Fresnel reflection off the face it enters,
then up to six bounces inside, refracting out wherever it can and reflecting
where it cannot. That internal bouncing is where a gem's sparkle comes from and
no flat shading imitates it: the same facet is dark in one frame and blazing in
the next because the light it is carrying came in through a *different* face.

**Two environments, one for each half of the light.** What a facet reflects
off its surface is a black room with a few small hard lamps in it, so the
surface contributes only sharp glints and never a grey sheen; what is seen
*through* the stone also gets a broad soft light from above and behind, so the
body glows from inside. Traced against one ordinary environment the first set
came back pale and grey, which is a stone photographed under an office light.

**Traced in luminance and coloured by a gradient map.** The trace is neutral;
its brightness is then run through a ramp from a deep jewel tone up through the
hue to white. That keeps all the structure the optics produce and puts the
palette under direct control, and the ramp's floor is held well above black so
a facet turned away from the light still reads as stone rather than as a hole
-- the first pass let the dark facets go nearly black and translucent, and on a
dark stage half of every stone vanished.

**Semi-transparent in the body, solid at the edge.** The alpha follows the
brightness -- dark facets are about half opaque, lit ones solid -- which is
what glass does and what keeps a shower of these from being a sheet of colour
over the field. The silhouette carries a one-pixel rim that is bright on the
side facing the lamp and a mid tone on the far side, so the outline never
depends on what is behind it.

**What keeps them from reading as bullets** is the rendering itself. Every
bullet is flat and emissive -- a white core, a saturated rim, a hard near-black
contour, no light direction anywhere. These are the opposite on every count:
shaded, lit from one side, no white core, no dark contour, translucent, and
turning. They are also drawn *under* the bullets (`obj_game`'s Draw), and kept
small: the brilliant is the largest at about twenty-two pixels across.

The spin
--------

**Twelve frames per symmetry period, not per turn.** The citrine is four-fold,
so a quarter turn brings it back to the same picture; the sapphire is six-fold
and the brilliant eight-fold. Twelve frames across that period is 7.5 degrees a
frame at the coarsest, which is smooth, and the loop is exact because the lamps
are fixed to the camera. How fast each one turns is `item_draw`'s business --
see `ITEM_SPIN_*` in `constants`.

Usage:
    python tools/make_items.py                # sprites + preview
    python tools/make_items.py --preview-only
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

FRAMES = 12          # per symmetry period; see the docstring
SS = 8               # supersampling for the trace


# ---------------------------------------------------------------------------
# Cuts. A cut is a list of planes (n, d), the stone being every point with
# n . x <= d for all of them -- so a facet is just a plane, and which facets
# end up visible, and where their edges fall, is decided by the intersection
# rather than being worked out by hand.
# ---------------------------------------------------------------------------

def _unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def _plane(n, p):
    n = _unit(n)
    return n, float(np.dot(n, p))


def _facet(az, lean, r, y, up=True):
    """A facet whose normal leans `lean` degrees off the axis at azimuth `az`,
    passing through the point at radius `r` and height `y` on that azimuth."""
    a, t = math.radians(az), math.radians(lean)
    n = (math.cos(a) * math.sin(t), math.cos(t) if up else -math.cos(t),
         math.sin(a) * math.sin(t))
    return _plane(n, (r * math.cos(a), y, r * math.sin(a)))


def cut_octahedron(h=1.45):
    """The citrine: four faces up and four down, meeting at a square girdle."""
    lean = math.degrees(math.atan2(h, 1.0))
    planes = []
    for k in range(4):
        planes.append(_facet(45 + 90 * k, lean, 0.0, h, up=True))
        planes.append(_facet(45 + 90 * k, lean, 0.0, -h, up=False))
    return planes


def cut_quartz(r=1.0, body=1.3, term=0.95):
    """The sapphire: six prism faces and a six-sided point at each end --
    the double-terminated crystal every game's mana crystal is drawn from."""
    lean = 90 - math.degrees(math.atan2(term, r))
    planes = []
    for k in range(6):
        a = math.radians(60 * k)
        planes.append(_plane((math.cos(a), 0, math.sin(a)),
                             (r * math.cos(a), 0, r * math.sin(a))))
        planes.append(_facet(60 * k, lean, r, body, up=True))
        planes.append(_facet(60 * k, lean, r, -body, up=False))
    return planes


def cut_brilliant(table=0.56, crown=34.5, star=22.0, ugird=42.0, pav=41.0,
                  lgird=43.5, g=0.03, girdle_n=32):
    """The ruby: a round brilliant with its proper facets -- a table, eight
    bezels and eight stars on the crown, sixteen upper and sixteen lower girdle
    halves, eight pavilion mains -- at the textbook angles. At twenty pixels
    they are not individually visible; what they buy is that the stone
    sparkles in small pieces rather than flashing in large ones."""
    th = g + (1 - table / math.cos(math.radians(22.5))) \
        * math.tan(math.radians(crown)) * 0.98
    planes = [_plane((0, 1, 0), (0, th, 0))]
    for k in range(8):
        az = 45 * k
        planes.append(_facet(az, crown, 1.0, g, up=True))
        planes.append(_facet(az + 22.5, star, table, th, up=True))
        planes.append(_facet(az, pav, 1.0, -g, up=False))
        for s in (-1, 1):
            planes.append(_facet(az + 22.5 + s * 11.25, ugird, 1.0, g, up=True))
            planes.append(_facet(az + 22.5 + s * 11.25, lgird, 1.0, -g,
                                 up=False))
    for k in range(girdle_n):
        a = math.radians(360.0 * k / girdle_n)
        planes.append(_plane((math.cos(a), 0, math.sin(a)),
                             (math.cos(a), 0, math.sin(a))))
    return planes


# ---------------------------------------------------------------------------
# Light
# ---------------------------------------------------------------------------

def _lamp(d, power, width):
    return (_unit(d), power, width)


def _sharp_lamps(seed=5):
    """The small hard lamps: a key up and to the left, a rim behind on the
    right, a low bounce, and a scatter of pinpoints for the stone to pick up
    as it turns. Everything the *surface* of a stone reflects."""
    rng = np.random.default_rng(seed)
    lamps = [_lamp((-0.55, 0.70, 0.45), 10.0, 0.020),
             _lamp((0.70, 0.40, -0.60), 6.0, 0.010),
             _lamp((-0.20, -0.30, 0.93), 2.0, 0.050)]
    for _ in range(16):
        v = _unit(rng.normal(size=3))
        v[1] = abs(v[1]) * 0.8 + 0.1
        lamps.append(_lamp(v, 8.0, 0.0022))
    return lamps


# The room seen *through* the stone: broad and soft, from above and behind.
BROAD = [_lamp((0.0, 1.0, -0.4), 1.6, 0.35),
         _lamp((-0.5, 0.6, 0.6), 1.0, 0.25),
         _lamp((0.3, -0.2, -1.0), 0.9, 0.30)]
SHARP = _sharp_lamps()


def _env(d, inside):
    y = d[..., 1]
    if inside:
        base = 0.05 + 0.20 * np.clip(y * 0.5 + 0.5, 0, 1) ** 2
        lamps = SHARP + BROAD
    else:
        base = 0.01 + 0.04 * np.clip(y, 0, 1) ** 2
        lamps = SHARP
    out = base.copy()
    for (l, power, width) in lamps:
        out = out + np.exp(np.clip((d @ l - 1.0) / width, -60, 0)) * power
    return out


def _rotation(spin, tilt):
    """Spin about the stone's own axis, then lean its top toward the camera."""
    s, t = math.radians(spin), math.radians(tilt)
    ry = np.array([[math.cos(s), 0, math.sin(s)], [0, 1, 0],
                   [-math.sin(s), 0, math.cos(s)]])
    rx = np.array([[1, 0, 0], [0, math.cos(t), -math.sin(t)],
                   [0, math.sin(t), math.cos(t)]])
    return rx @ ry


def trace(planes, R, W, H, scale, ior, absorb, bounces=6):
    """Trace one frame. Returns luminance, coverage and the id of the facet
    each pixel entered through, all at W x H."""
    n = np.array([p[0] for p in planes]) @ R.T
    d = np.array([p[1] for p in planes])
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
    P = np.stack([(xs - (W - 1) / 2) / scale, -(ys - (H - 1) / 2) / scale,
                  np.full(xs.shape, 10.0)], -1).reshape(-1, 3)
    v = np.array([0.0, 0.0, -1.0])

    # Entry and exit against every plane at once: a ray is inside a convex
    # solid between the last plane it crosses going in and the first going out.
    den = n @ v
    num = d[None, :] - P @ n.T
    with np.errstate(divide="ignore", invalid="ignore"):
        s = num / den[None, :]
    enter = den < 0
    s_in_all = np.where(enter[None, :], s, -np.inf)
    s_in = s_in_all.max(1)
    face = s_in_all.argmax(1)
    s_out = np.where(~enter[None, :], s, np.inf).min(1)
    hit = s_in < s_out

    lum = np.zeros(P.shape[0])
    fid = np.full(P.shape[0], -1)
    idx = np.nonzero(hit)[0]
    if len(idx):
        fid[idx] = face[idx]
        nf = n[face[idx]]
        cos_i = -(nf @ v)
        r0 = ((ior - 1) / (ior + 1)) ** 2
        F = r0 + (1 - r0) * (1 - cos_i) ** 5
        out = F * _env(v[None, :] + 2 * cos_i[:, None] * nf, inside=False)

        eta = 1.0 / ior
        k = 1 - eta ** 2 * (1 - cos_i ** 2)
        t = _unit(eta * v[None, :]
                  + (eta * cos_i - np.sqrt(np.clip(k, 0, None)))[:, None] * nf)
        pos = P[idx] + s_in[idx, None] * v
        thr = 1 - F
        for _ in range(bounces):
            den2 = t @ n.T
            num2 = d[None, :] - pos @ n.T
            with np.errstate(divide="ignore", invalid="ignore"):
                s2 = np.where(den2 > 1e-9, num2 / den2, np.inf)
            s2 = np.where(s2 < 1e-7, np.inf, s2)
            ex = s2.argmin(1)
            L = s2[np.arange(len(ex)), ex]
            L = np.where(np.isfinite(L), L, 0)
            pos = pos + t * L[:, None]
            thr = thr * np.exp(-absorb * L)
            ne = n[ex]
            ci = np.einsum("ij,ij->i", ne, t)
            k2 = 1 - ior ** 2 * (1 - ci ** 2)
            tir = k2 < 0
            t_out = _unit(ior * t + (np.sqrt(np.clip(k2, 0, None))
                                     - ior * ci)[:, None] * ne)
            Fe = np.where(tir, 1.0,
                          r0 + (1 - r0) * (1 - np.sqrt(np.clip(k2, 0, None))) ** 5)
            out = out + thr * (1 - Fe) * _env(t_out, inside=True)
            thr = thr * Fe
            t = _unit(t - 2 * ci[:, None] * ne)
            pos = pos - ne * 1e-6
        lum[idx] = out + thr * 0.05
    return lum.reshape(H, W), hit.reshape(H, W), fid.reshape(H, W)


# ---------------------------------------------------------------------------
# The look
# ---------------------------------------------------------------------------

def _ramp(stops, t):
    ts = [s for s, _ in stops]
    cs = np.array([c for _, c in stops], dtype=np.float64)
    return np.stack([np.interp(t, ts, cs[:, k]) for k in range(3)], -1)


# Deep jewel tone -> the hue -> white. Only the top few per cent reach white,
# and only on a facet catching a lamp.
RUBY = [(0.00, (30, 0, 10)), (0.20, (92, 2, 22)), (0.42, (170, 10, 38)),
        (0.62, (228, 36, 62)), (0.80, (255, 112, 120)),
        (0.93, (255, 206, 206)), (1.00, (255, 255, 255))]
SAPPHIRE = [(0.00, (4, 10, 44)), (0.20, (12, 34, 120)), (0.42, (26, 84, 208)),
            (0.62, (62, 146, 255)), (0.80, (146, 204, 255)),
            (0.93, (216, 238, 255)), (1.00, (255, 255, 255))]
CITRINE = [(0.00, (44, 20, 0)), (0.20, (118, 62, 4)), (0.42, (206, 126, 12)),
           (0.62, (252, 190, 36)), (0.80, (255, 228, 116)),
           (0.93, (255, 248, 204)), (1.00, (255, 255, 255))]

# The lamp, seen from the screen, for the rim: up and to the left (y down).
RIM_FROM = _unit(np.array([-0.62, -0.78]))


def gem_frames(planes, sym, tilt, scale_px, ior, absorb, stops, edge=0.0,
               mid=0.45, floor=0.18, pad=2, a0=0.42, ak=0.62):
    """Every frame of one stone, cropped to a canvas that fits all of them.

    `scale_px` is how many screen pixels one unit of the cut spans; `edge`
    lifts the facet boundaries a little, which the two simple cuts want and
    the brilliant, with ninety facets, does not. Exposure is set from the
    trace itself -- the median lit pixel lands at `mid` -- so the three stones
    come out at the same value whatever their optics do.
    """
    probe = int(6 * scale_px) * SS
    scale = scale_px * SS
    raws = [trace(planes, _rotation(360.0 / sym * k / FRAMES, tilt),
                  probe, probe, scale, ior, absorb)
            for k in range(FRAMES)]

    covered = np.any([r[1] for r in raws], axis=0)
    ys, xs = np.nonzero(covered)
    c = (probe - 1) / 2
    w = int(math.ceil(max(c - xs.min(), xs.max() - c) / SS + pad)) * 2
    h = int(math.ceil(max(c - ys.min(), ys.max() - c) / SS + pad)) * 2
    x0, y0 = int(round(c - w * SS / 2)), int(round(c - h * SS / 2))

    lit = np.concatenate([r[0][r[1]] for r in raws])
    expo = -math.log(1 - mid) / max(float(np.median(lit)), 1e-6)

    frames = []
    for lum, hit, fid in raws:
        crop = (slice(y0, y0 + h * SS), slice(x0, x0 + w * SS))
        lum, hit, fid = lum[crop], hit[crop], fid[crop]
        cov = hit.astype(np.float64)
        L = floor + (1 - floor) * (1 - np.exp(-lum * expo))

        if edge:
            e = np.zeros_like(cov)
            e[:, 1:] += fid[:, 1:] != fid[:, :-1]
            e[1:, :] += fid[1:, :] != fid[:-1, :]
            e = _grey(np.clip(e, 0, 1)).filter(ImageFilter.MaxFilter(5))
            e = np.asarray(e, dtype=np.float64) / 255 * cov
            L = L + edge * e * (1 - L)

        # The rim: one final pixel inside the silhouette, lit by which way the
        # outline faces.
        m = _grey(cov)
        band = cov - np.asarray(m.filter(ImageFilter.MinFilter(SS * 2 + 1)),
                                dtype=np.float64) / 255
        soft = np.asarray(m.filter(ImageFilter.GaussianBlur(SS * 1.5)),
                          dtype=np.float64) / 255
        gy, gx = np.gradient(soft)
        facing = -(gx * RIM_FROM[0] + gy * RIM_FROM[1]) \
            / (np.hypot(gx, gy) + 1e-9)
        rim = np.interp(np.clip(facing, -1, 1), [-1, 0, 1], [0.32, 0.50, 0.92])
        on_rim = band > 0
        L = np.where(on_rim, rim, L)

        col = _ramp(stops, np.clip(L, 0, 1))
        a = cov * np.clip(a0 + ak * L, 0, 1)
        a = np.where(on_rim, np.maximum(a, 0.85), a)
        frames.append(A.from_arrays(col, a).resize((w, h), Image.LANCZOS))
    return frames


def _grey(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")


# name, cut, symmetry, tilt, scale, ior, absorption, ramp, edge
STONES = [
    ("red",  cut_brilliant(),     8, 22, 11.5, 1.76, 0.36, RUBY,     0.00),
    ("blue", cut_quartz(),        6, 14,  5.5, 1.62, 0.45, SAPPHIRE, 0.20),
    ("gold", cut_octahedron(),    4, 16,  6.75, 1.66, 0.35, CITRINE, 0.20),
]


# ---------------------------------------------------------------------------
# The effects
# ---------------------------------------------------------------------------

def make_glint(size=40):
    """The twinkle: a lens star, drawn additively and tinted.

    **Hairline rays, long and short, with a tiny hot centre** -- the flare a
    point of light makes in a lens. The `mote` bullet is a four-pointed star
    too, but a *fat* one with a body; this has almost no area at all, which
    is what makes it read as light glancing off something rather than as a
    thing. Two long rays on the axes, two short ones on the diagonals.
    """
    dx, dy, r = A.grid(size * SS, size * SS)
    ax, ay = np.abs(dx) / (size * SS / 2.0), np.abs(dy) / (size * SS / 2.0)
    rr = r
    long_ = (np.exp(-(ay / 0.022) ** 2) * np.clip(1 - ax, 0, 1) ** 1.6
             + np.exp(-(ax / 0.022) ** 2) * np.clip(1 - ay, 0, 1) ** 1.6)
    u = (ax + ay) / math.sqrt(2)
    v = np.abs(ax - ay) / math.sqrt(2)
    short = np.exp(-(v / 0.018) ** 2) * np.clip(1 - u / 0.55, 0, 1) ** 2.0
    core = np.clip(1 - rr / 0.16, 0, 1) ** 2.2
    halo = np.clip(1 - rr / 0.45, 0, 1) ** 3 * 0.35
    a = np.clip(long_ + short * 0.7 + core + halo, 0, 1)
    body = np.full(a.shape + (3,), 255.0)
    return A.from_arrays(body, a).resize((size, size), Image.LANCZOS)


def make_shard(w=14, h=10):
    """A sliver of crystal, pointing right, for the burst a caught stone
    leaves: a long facet and a short one, the long one lit. White, and tinted
    by the particle -- so one sprite serves all three stones."""
    cv = A.Canvas(w, h)
    tip, tail = (w - 1.0, h * 0.5), (1.0, h * 0.5)
    top, bot = (w * 0.42, 1.0), (w * 0.30, h - 1.0)
    cv.polygon([tail, top, tip], fill=(255, 255, 255, 255))
    cv.polygon([tail, tip, bot], fill=(150, 150, 150, 235))
    cv.line([tail, tip], (255, 255, 255, 255), 0.8)
    return cv.finish()


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

def _bullet_row(names=("pellet", "orb", "rice", "crystal", "star")):
    """A few real bullets, first frame of three hues, for scale."""
    out = []
    for nm in names:
        d = os.path.join(A.ROOT, "sprites", "spr_bul_" + nm)
        if not os.path.isdir(d):
            continue
        # GameMaker's .yy is not strict JSON (trailing commas), so the frame
        # order is read straight out of the text.
        yy = open(os.path.join(d, "spr_bul_%s.yy" % nm)).read()
        frames = re.findall(r'"\$GMSpriteFrame":"v1","%Name":"([^"]+)"', yy)
        per = len(frames) // len(A.BULLET_HUES)
        for hue in ("crimson", "azure", "amber"):
            i = A.HUE_INDEX[hue] * per
            out.append(Image.open(os.path.join(d, frames[i] + ".png"))
                       .convert("RGBA"))
    return out


def _preview(stones, glint, shard):
    """Three bands: every frame of every stone at 6x on dark; the same on a
    bright busy ground; and 1:1 beside real bullets, which is the only size
    that matters."""
    zoom = 6
    rows = []
    for name, frames in stones:
        w, h = frames[0].size
        row = Image.new("RGBA", (FRAMES * (w * zoom + 6), h * zoom), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            row.alpha_composite(f.resize((w * zoom, h * zoom), Image.NEAREST),
                                (i * (w * zoom + 6), 0))
        rows.append(row)
    W = max(r.width for r in rows) + 24
    H = sum(r.height + 12 for r in rows) + 12

    dark = Image.new("RGBA", (W, H), (12, 12, 22, 255))
    def field(seed):
        return np.asarray(A.fbm_field(W, H, seed, base=6),
                          dtype=np.float64) / 255
    bright = A.from_arrays(
        np.stack([field(7) * 150 + 60, field(8) * 120 + 40,
                  field(9) * 150 + 70], -1),
        np.ones((H, W)))
    for ground in (dark, bright):
        y = 12
        for r in rows:
            ground.alpha_composite(r, (12, y))
            y += r.height + 12

    # 1:1 against the bullets, with the in-game glow under each stone.
    strip = Image.new("RGBA", (W, 120), (18, 14, 24, 255))
    x = 16
    glow = A.soft_glow(56, (255, 255, 255), falloff=2.9)
    hues = {"red": A.LIFE, "blue": A.MANA, "gold": A.GRAZE}
    for name, frames in stones:
        for f in (frames[0], frames[FRAMES // 3]):
            gl = Image.new("RGBA", glow.size, A.rgba(hues[name], 0))
            gl.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.36)))
            strip = A.add(strip, _place(strip.size, gl, x + 14, 40))
            strip.alpha_composite(f, (x + 14 - f.width // 2, 40 - f.height // 2))
            x += 36
    for b in _bullet_row():
        strip.alpha_composite(b, (x + 14 - b.width // 2, 40 - b.height // 2))
        x += max(36, b.width + 6)
    strip.alpha_composite(glint, (16, 80))
    strip.alpha_composite(shard.resize((shard.width * 3, shard.height * 3),
                                       Image.LANCZOS), (70, 86))

    sheet = Image.new("RGBA", (W, dark.height + bright.height + strip.height),
                      (0, 0, 0, 255))
    sheet.alpha_composite(dark, (0, 0))
    sheet.alpha_composite(bright, (0, dark.height))
    sheet.alpha_composite(strip, (0, dark.height + bright.height))
    sheet.save(os.path.join(A.PREVIEW, "stones.png"))


def _place(size, img, cx, cy):
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(img, (cx - img.width // 2, cy - img.height // 2))
    return out


def main():
    preview_only = "--preview-only" in sys.argv
    stones = []
    for name, planes, sym, tilt, scale, ior, absorb, ramp, edge in STONES:
        frames = gem_frames(planes, sym, tilt, scale, ior, absorb, ramp,
                            edge=edge)
        stones.append((name, frames))
        print("spr_item_%s: %dx%d, %d frames"
              % (name, frames[0].width, frames[0].height, len(frames)))
    glint = make_glint()
    shard = make_shard()

    if not preview_only:
        gm_new.folder("Sprites/ui")
        gm_new.folder("Sprites/fx")
        for name, frames in stones:
            gm_new.sprite("spr_item_" + name, frames, origin="center",
                          folder="Sprites/ui")
        gm_new.sprite("spr_fx_glint", [glint], origin="center",
                      folder="Sprites/fx")
        gm_new.sprite("spr_fx_shard", [shard], origin="center",
                      folder="Sprites/fx")
    _preview(stones, glint, shard)


if __name__ == "__main__":
    main()
