#!/usr/bin/env python3
"""Mika's ring: `spr_ring`, and the layers drawn with it.

The pattern is the ring marking on the owner's reference sheet (the bands on
Mika's tail, wrists and ankle): a black cuff with a gold rail at each edge,
two glossy black bands, and between them a sunken channel carrying a gold
chain. Each link of the chain is an oval with a pointed lens inside it, and
the links are joined by small ring-shaped knots. The colours are baked in.

A ring turns, and light painted onto its pattern would turn with it. So the
ring is four sprites of the same size and origin (`ring_draw` in
`scripts/ring_functions`):

- `spr_ring`, drawn at the ring's angle: the pattern, with only the light
  that looks the same at every angle (each rail and wire lit from the front,
  shadow in every crevice).
- `spr_ring_sheen`, drawn unrotated and additively: reflections in the black
  lacquer and on the four rails. The rails and bands are round, so this layer
  knows where they are at any angle.
- `spr_ring_glint`, drawn unrotated as `dst * (1 + src)` over the channel.
  The chain turns under it, so it can't know where the wires are; brightening
  in proportion to what is there flares the gold and leaves the black floor
  black.
- `spr_ring_heat`, drawn at the ring's angle, additively, in the attack's
  colour while the ring is charged.

The sprite is drawn at a little under half size (`RING_R / R`), so every
line in it is at least two texels wide.

The band is computed as a field of (radius, angle). `BAND_FRAC` must match
`RING_BAND_FRAC` in `constants` and `R / (SIZE / 2)` must match
`RING_SPR_LINE`, so the drawn metal and the band that blocks shots are the
same shape.

Usage:
    python tools/make_rings.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SIZE = 384
SS = 4
R = 150.0                    # the band's centre line, in final pixels
HALF = 24.0                  # half its thickness
BAND_FRAC = HALF / R         # 0.16 -- must match RING_BAND_FRAC
SPR_LINE = R / (SIZE / 2)    # 0.78125 -- must match RING_SPR_LINE

# Across the band, in units of HALF (`a` is |u|: 0 on the centre line, 1 at
# the edge). Rails are (centre, half-width).
EDGE_RAIL = (0.93, 0.07)
CHAN_RAIL = (0.40, 0.065)
BAND_IN = CHAN_RAIL[0] + CHAN_RAIL[1]           # the lacquer bands
BAND_OUT = EDGE_RAIL[0] - EDGE_RAIL[1]
FLOOR_OUT = CHAN_RAIL[0] - CHAN_RAIL[1]         # the channel's floor

# Heights of the relief, in the same units. They only set how steeply things
# are lit.
RAIL_CREST = 0.11
BAND_BASE = 0.05
BAND_DOME = 0.05
WIRE_CREST = 0.06

# The chain: links round the ring, then each part's size in units of HALF.
LINKS = 28
OVAL = (0.48, 0.24, 0.10)            # semi-axes along and across, wire width
LENS = (0.48, 0.095, 0.055, 0.55)    # half-length, bulge, wire, reach past
KNOT = (0.17, 0.11, 0.085)           # semi-axes, wire width

# Past the metal: a thin dark contour, then a soft shadow round both edges.
CONTOUR = 0.07
HALO = 0.55
HALO_ALPHA = 0.36

# How hot each part of a charged ring runs (the gold is 1), and how far the
# heat spills past the edges, in units of HALF.
HEAT_LACQUER = 0.55
HEAT_FLOOR = 0.40
HEAT_SPILL = 0.60

# Materials, at the value the front light leaves them.
GOLD = (240, 170, 36)                # the reference's secondary colour
GOLD_DEEP = (150, 88, 16)            # the same gold turned away from view
GOLD_HI = (255, 238, 176)
JET = (12, 11, 15)                   # lacquer
JET_RIM = (34, 34, 48)               # lacquer seen edge-on
FLOOR = (8, 7, 11)                   # the channel, sunk and matte
INK = (5, 4, 8)                      # the contour and halo

# The room the metal reflects, as directions from the ring toward each light
# (x right, y down, z toward the viewer): (direction, colour, strength, and
# the radius in degrees where it is full and where it has faded out). Gold
# reflects it blurred by `ROUGH` degrees more.
LIGHTS = [
    ((-0.40, -0.48, 0.78), (255, 246, 232), 1.00, 17.0, 25.0),  # key
    ((0.52, -0.42, 0.74), (190, 186, 226), 0.30, 6.0, 15.0),    # fill
    ((0.55, 0.55, 0.63), A.RUNE, 0.62, 8.0, 19.0),              # cyan rim
    ((-0.20, 0.75, 0.63), (255, 186, 90), 0.22, 10.0, 26.0),    # bounce
]
ROUGH = 9.0
SKY = (20, 20, 32)                   # everything else, above the ring
GOLD_TINT = (1.0, 0.80, 0.46)        # what gold does to a reflection


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

def fields():
    """Radius and angle for every supersampled pixel, in final pixels."""
    n = SIZE * SS
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) * 0.5
    dx = (xs - c) / SS
    dy = (ys - c) / SS
    return np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)


def shrink(arr):
    """Box-filter a supersampled array down to final size."""
    n = SIZE
    if arr.ndim == 2:
        return arr.reshape(n, SS, n, SS).mean(axis=(1, 3))
    return arr.reshape(n, SS, n, SS, arr.shape[2]).mean(axis=(1, 3))


def blur(arr, sigma):
    """Gaussian blur by FFT (the tools don't use scipy). The edges wrap, which
    is harmless here: the border of every field is empty.
    """
    h, w = arr.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.fft.irfft2(np.fft.rfft2(arr) * g, s=arr.shape).astype(np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def dome(d, half, crest):
    """A rounded bead: `crest` high on its centre line, zero at `half` away,
    and absent (-inf) past that so it unions with `max`.
    """
    t = np.abs(d) / half
    return np.where(t <= 1.0, crest * np.cos(t * (math.pi * 0.5)), -np.inf)


# ---------------------------------------------------------------------------
# The relief
# ---------------------------------------------------------------------------

def profile(a):
    """The cuff's cross-section: height at |u| = `a`, and which part is on
    top. Parts: 0 floor, 1 lacquer, 2 rail. Round, so the same at any angle.
    """
    floor = np.where(a <= 1.0, 0.0, -np.inf)
    t = (a - (BAND_IN + BAND_OUT) * 0.5) / ((BAND_OUT - BAND_IN) * 0.5)
    band = np.where(np.abs(t) <= 1.0,
                    BAND_BASE + BAND_DOME * (1.0 - t * t), -np.inf)
    rail = np.maximum(dome(a - EDGE_RAIL[0], EDGE_RAIL[1], RAIL_CREST),
                      dome(a - CHAN_RAIL[0], CHAN_RAIL[1], RAIL_CREST))
    h = np.maximum(np.maximum(floor, band), rail)
    part = np.where(rail >= h, 2, np.where(band >= h, 1, 0))
    return h, part


def profile_slope(a):
    """d(height)/d(a), by sampling the profile finely."""
    ag = np.linspace(0.0, 1.0, 8001)
    hg, _ = profile(ag)
    sg = np.gradient(hg, ag)
    return np.interp(a, ag, sg)


def chain_coords(u, th):
    """Where a pixel is along its link (`x`, 0 at the oval's middle) and along
    its knot (`xk`, 0 at the knot's middle), in units of HALF.
    """
    period = 2.0 * math.pi * R / HALF / LINKS
    s = th * LINKS / (2.0 * math.pi)           # links travelled
    x = (np.mod(s + 0.5, 1.0) - 0.5) * period
    xk = (np.mod(s, 1.0) - 0.5) * period
    return x, xk


def ellipse_dist(x, y, ax, ay):
    """Distance to an ellipse outline (first order: good near the line)."""
    q = np.sqrt((x / ax) ** 2 + (y / ay) ** 2)
    g = np.sqrt((x / (ax * ax)) ** 2 + (y / (ay * ay)) ** 2)
    return np.abs(q - 1.0) * q / np.maximum(g, 1e-6)


def arc_dist(x, y, half_len, bulge, reach):
    """Distance to the arc through (-half_len, 0), (0, bulge), (half_len, 0),
    carried on to |x| = `reach` so a pair of them crosses at each end.
    """
    rho = (half_len * half_len + bulge * bulge) / (2.0 * bulge)
    cy = bulge - rho
    d = np.abs(np.sqrt(x * x + (y - cy) ** 2) - rho)
    ex = reach
    ey = cy + math.sqrt(max(rho * rho - ex * ex, 0.0))
    end = np.sqrt((np.abs(x) - ex) ** 2 + (y - ey) ** 2)
    return np.where(np.abs(x) <= ex, d, end)


def chain(u, th):
    """Height of the chain's wires (-inf where there is none)."""
    x, xk = chain_coords(u, th)
    oval = dome(ellipse_dist(x, u, OVAL[0], OVAL[1]), OVAL[2] * 0.5,
                WIRE_CREST)
    lens = np.maximum(
        dome(arc_dist(x, u, LENS[0], LENS[1], LENS[3]), LENS[2] * 0.5,
             WIRE_CREST * 0.8),
        dome(arc_dist(x, -u, LENS[0], LENS[1], LENS[3]), LENS[2] * 0.5,
             WIRE_CREST * 0.8))
    knot = dome(ellipse_dist(xk, u, KNOT[0], KNOT[1]), KNOT[2] * 0.5,
                WIRE_CREST)
    return np.maximum(np.maximum(oval, lens), knot)


def normals(slope_r, th):
    """Unit normals of a surface that rises outward by `slope_r` per unit of
    HALF (a round relief, so the slope is all radial).
    """
    nx = -slope_r * np.cos(th)
    ny = -slope_r * np.sin(th)
    k = 1.0 / np.sqrt(nx * nx + ny * ny + 1.0)
    return nx * k, ny * k, k


def environment(nx, ny, nz, widen=0.0, tint=(1.0, 1.0, 1.0)):
    """What the metal reflects toward the viewer: the lights in `LIGHTS`, each
    widened by `widen` degrees, plus a dim sky above. RGB on a 0..255 scale.
    """
    # The view direction reflected about the normal.
    rx, ry, rz = 2.0 * nz * nx, 2.0 * nz * ny, 2.0 * nz * nz - 1.0
    out = np.zeros(nx.shape + (3,), dtype=np.float32)
    for d, col, k, r_in, r_out in LIGHTS:
        m = math.sqrt(sum(v * v for v in d))
        dot = (rx * d[0] + ry * d[1] + rz * d[2]) / m
        lobe = smoothstep(math.cos(math.radians(r_out + widen)),
                          math.cos(math.radians(r_in + widen * 0.5)), dot) * k
        for i in range(3):
            out[..., i] += lobe * col[i] * tint[i]
    sky = np.clip(0.5 - 0.6 * ry, 0.0, 1.0) * np.clip(rz, 0.0, 1.0)
    for i in range(3):
        out[..., i] += sky * SKY[i] * tint[i]
    return out


# ---------------------------------------------------------------------------
# The sprites
# ---------------------------------------------------------------------------

def rgba(col, alpha):
    """Final-size RGBA from supersampled straight colour and coverage."""
    a = shrink(alpha)
    c = shrink(col * alpha[..., None]) / np.maximum(a, 1e-6)[..., None]
    out = np.concatenate([np.clip(c, 0, 255), a[..., None] * 255.0], axis=2)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def relief(rr, th):
    """The pattern as a height field: `u` across the band, `a` = |u|, the
    height `h`, which `part` of the cuff is on top, where the chain's wires
    are, and where there is metal at all.
    """
    u = (rr - R) / HALF
    a = np.abs(u)
    h, part = profile(a)
    wire = chain(u, th)
    on_wire = (wire >= h) & (a < FLOOR_OUT)
    h = np.where(on_wire, wire, h)
    metal = a <= 1.0
    h = np.where(metal, h, 0.0).astype(np.float32)
    return u, a, h, part, on_wire, metal


def make_ring(rr, th):
    """The pattern, lit only from the front."""
    u, a, h, part, on_wire, metal = relief(rr, th)

    # Normals from the relief (units of HALF per supersampled pixel).
    gy, gx = np.gradient(h, 1.0 / (HALF * SS))
    nz = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)

    # Shadow in the crevices: how far below its neighbourhood each point is.
    cavity = np.clip(blur(h, 0.06 * HALF * SS) - h, 0.0, None)
    ao = np.clip(1.0 - 9.0 * cavity, 0.45, 1.0)

    gold = on_wire | (part == 2)
    face = smoothstep(0.15, 0.95, nz)
    glint = np.clip((nz - 0.93) / 0.07, 0.0, 1.0) ** 2 * 0.45
    edge_on = (1.0 - nz) ** 2

    col = np.empty(h.shape + (3,), dtype=np.float32)
    for i in range(3):
        au = GOLD_DEEP[i] + (GOLD[i] - GOLD_DEEP[i]) * face
        au = au + (GOLD_HI[i] - au) * glint
        jet = JET[i] * (0.75 + 0.35 * nz) + JET_RIM[i] * edge_on
        c = np.where(gold, au, np.where(part == 1, jet, FLOOR[i]))
        col[..., i] = np.where(metal, c * ao, INK[i])

    # Outside the metal: the contour, then the halo, on both edges.
    past = a - 1.0
    contour = smoothstep(CONTOUR + 0.03, CONTOUR - 0.01, past) * 0.92
    halo = HALO_ALPHA * np.clip(1.0 - (past - CONTOUR) / HALO, 0.0, 1.0) ** 2
    alpha = np.where(metal, 1.0, np.maximum(contour, halo)).astype(np.float32)
    return rgba(col, alpha)


def make_heat(rr, th):
    """The charge, drawn at the ring's angle, additively, in the attack's
    colour: white, with alpha for how hot each part runs. The gold burns
    brightest, the lacquer glows, and the heat spills a little past both
    edges.
    """
    u, a, h, part, on_wire, metal = relief(rr, th)
    gold = on_wire | (part == 2)
    inside = np.where(gold, 1.0, np.where(part == 1, HEAT_LACQUER,
                                          HEAT_FLOOR))
    past = np.clip((a - 1.0) / HEAT_SPILL, 0.0, 1.0)
    spill = HEAT_LACQUER * (1.0 - past) ** 2
    alpha = np.where(metal, inside, spill).astype(np.float32)
    return rgba(np.full(h.shape + (3,), 255.0, dtype=np.float32), alpha)


def make_sheen(rr, th):
    """Reflections in the lacquer and the rails, fixed to the screen. Drawn
    additively, so it is colour at full alpha wherever there is metal.
    """
    u = (rr - R) / HALF
    a = np.abs(u)
    _, part = profile(a)
    slope = profile_slope(a) * np.sign(u)
    nx, ny, nz = normals(slope, th)

    lacquer = environment(nx, ny, nz)
    fres = (0.80 + 0.20 * (1.0 - nz) ** 2)[..., None]
    gilt = environment(nx, ny, nz, ROUGH, GOLD_TINT) * 0.95

    # The floor is flat; dishing it slightly gives it the soft reflections of
    # a polished surface, on the far side from the bands' (it is sunk).
    fx, fy, fz = normals(np.clip(u / FLOOR_OUT, -1.0, 1.0) * 0.18, th)
    floor = environment(fx, fy, fz, ROUGH) * 0.30

    col = np.where((part == 2)[..., None], gilt,
                   np.where((part == 1)[..., None], lacquer * fres, floor))
    alpha = (a <= 1.0).astype(np.float32)
    return rgba(col, alpha)


def make_glint(rr, th):
    """How much to brighten the chain, fixed to the screen: as if the chain
    were one rounded wire along the channel, so its outer wires catch the key
    light above left and its inner wires below right. Only over the channel.
    """
    u = (rr - R) / HALF
    a = np.abs(u)
    tilt = -np.clip(u / FLOOR_OUT, -1.0, 1.0)          # up to 45 degrees
    nx, ny, nz = normals(tilt, th)
    env = environment(nx, ny, nz, ROUGH)
    lift = np.clip(env / 255.0, 0.0, 1.0) * np.array([1.0, 0.82, 0.55])
    lift = lift * 255.0 * 0.85
    mask = smoothstep(FLOOR_OUT + 0.02, FLOOR_OUT - 0.04, a)
    return rgba(lift * mask[..., None], (a <= 1.0).astype(np.float32))


# ---------------------------------------------------------------------------
# Preview: the sprites composited the way `ring_draw` does it, sampled the
# way the GPU does (bilinear, no mipmaps).
# ---------------------------------------------------------------------------

def gpu_draw(dst, img, cx, cy, scale, ang, mode, col=(1.0, 1.0, 1.0),
             alpha=1.0):
    """Draw `img` into the float RGB array `dst` centred at (cx, cy), scaled
    and turned `ang` degrees anticlockwise as `draw_sprite_ext` does, with
    `mode` one of "normal", "add" or "dest" (`bm_dest_colour, bm_one`).
    """
    tex = np.asarray(img, dtype=np.float32) / 255.0
    th, tw = tex.shape[:2]
    reach = int(math.ceil(max(th, tw) * scale * 0.75)) + 2
    x0, x1 = max(0, int(cx) - reach), min(dst.shape[1], int(cx) + reach)
    y0, y1 = max(0, int(cy) - reach), min(dst.shape[0], int(cy) + reach)
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xs + 0.5 - cx, ys + 0.5 - cy
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    tx = (dx * c - dy * s) / scale + tw * 0.5 - 0.5
    ty = (dx * s + dy * c) / scale + th * 0.5 - 0.5

    ix, iy = np.floor(tx).astype(int), np.floor(ty).astype(int)
    fx, fy = (tx - ix)[..., None], (ty - iy)[..., None]

    def at(jx, jy):
        ok = (jx >= 0) & (jx < tw) & (jy >= 0) & (jy < th)
        v = tex[np.clip(jy, 0, th - 1), np.clip(jx, 0, tw - 1)]
        return v * ok[..., None]

    smp = (at(ix, iy) * (1 - fx) * (1 - fy) + at(ix + 1, iy) * fx * (1 - fy)
           + at(ix, iy + 1) * (1 - fx) * fy + at(ix + 1, iy + 1) * fx * fy)
    rgb = smp[..., :3] * np.array(col, dtype=np.float32)
    sa = smp[..., 3:4] * alpha
    d = dst[y0:y1, x0:x1]
    if mode == "normal":
        d[...] = rgb * sa + d * (1.0 - sa)
    elif mode == "add":
        d[...] = np.clip(d + rgb * sa, 0.0, 1.0)
    else:
        d[...] = np.clip(d + d * rgb, 0.0, 1.0)


def draw_ring(dst, layers, cx, cy, ang, charge=0.0, hue=(1.0, 1.0, 1.0)):
    """One ring as `ring_draw` draws it (less the charge's bloom)."""
    k = 72.0 / R                                     # RING_R / R
    gpu_draw(dst, layers["ring"], cx, cy, k, ang, "normal")
    gpu_draw(dst, layers["sheen"], cx, cy, k, 0.0, "add")
    gpu_draw(dst, layers["glint"], cx, cy, k, 0.0, "dest")
    if charge > 0:
        gpu_draw(dst, layers["heat"], cx, cy, k, ang, "add", hue, charge * 0.9)


def preview_ground(w, h, seed=7):
    fbm = np.asarray(A.fbm_field(w, h, seed, octaves=4, base=5),
                     dtype=np.float32) / 255.0
    g = np.zeros((h, w, 3), dtype=np.float32)
    g[..., 0] = 0.05 + fbm * 0.16
    g[..., 1] = 0.05 + fbm * 0.10
    g[..., 2] = 0.10 + fbm * 0.22
    return g


def to_img(arr):
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8),
                           "RGB").convert("RGBA")


def build():
    """The four sprites, by name."""
    rr, th = fields()
    return {"ring": make_ring(rr, th), "sheen": make_sheen(rr, th),
            "glint": make_glint(rr, th), "heat": make_heat(rr, th)}


def main():
    gm_new.folder("Sprites/ring")
    layers = build()
    for key, img in layers.items():
        name = "spr_ring" if key == "ring" else "spr_ring_" + key
        gm_new.sprite(name, [img], origin="center", folder="Sprites/ring")

    # Preview: the lit ring large, then at the game's size turning under its
    # light, and charging.
    big = preview_ground(SIZE, SIZE)
    for key, mode in (("ring", "normal"), ("sheen", "add"), ("glint", "dest")):
        gpu_draw(big, layers[key], SIZE / 2, SIZE / 2, 1.0, 0.0, mode)

    small = preview_ground(SIZE, SIZE, seed=11)
    for i, ang in enumerate((0.0, 17.0, 34.0, 51.0)):
        draw_ring(small, layers, 96 + (i % 2) * 192, 96 + (i // 2) * 192, ang)
    hot = preview_ground(SIZE, SIZE, seed=13)
    gold = tuple(np.array(A.BULLET_HUES[A.HUE_INDEX["gold"]][1]) / 255.0)
    for i, c in enumerate((0.3, 0.6, 1.0, 1.0)):
        draw_ring(hot, layers, 96 + (i % 2) * 192, 96 + (i // 2) * 192,
                  20.0 * i, c, gold)

    A.preview([layers["ring"], to_img(big), to_img(small), to_img(hot)],
              os.path.join(A.PREVIEW, "rings.png"), cols=4, bg=(16, 12, 14),
              labels=["pattern", "lit", "in game, turning", "charging"])
    print("rings: %d sprites of %dx%d, band %.3f of radius, line %.5f, "
          "%d links" % (len(layers), SIZE, SIZE, BAND_FRAC, SPR_LINE, LINKS))


if __name__ == "__main__":
    main()
