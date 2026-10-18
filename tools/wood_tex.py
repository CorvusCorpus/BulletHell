#!/usr/bin/env python3
"""Texture synthesis for the 3D wood (`tools/make_wood.py`).

Every surface texture here tiles in both directions, because the wood's
textures are separate texture pages that the GPU repeats (`For3D` sprites),
so a trunk's bark or the forest floor runs on without seams. The noise is
spectral (filtered white noise through an FFT, which is periodic by
construction) and the cell patterns are Voronoi diagrams of points copied into
the eight neighbouring tiles.

Albedos are in display values (0..255 sRGB). Normal maps are tangent space,
+x along u, +y along v (the texture's rows run downward, so the green channel
is flipped to the usual "y up" convention by `normal_map`), z out.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import cKDTree


# ---------------------------------------------------------------------------
# Noise
# ---------------------------------------------------------------------------

def spectral(n, seed, beta=2.0, aniso=(1.0, 1.0), fmin=0.0, fmax=None,
             m=None):
    """Tileable noise of size `n` x `m` (rows x columns, `m` defaults to `n`)
    with a power spectrum falling as 1/f^beta. `aniso` scales the frequency
    along (x, y): a larger y factor suppresses vertical frequencies, so the
    features stretch vertically. Returned zero-mean, unit deviation.
    """
    m = n if m is None else m
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((n, m))
    spec = np.fft.fft2(white)
    fy = np.fft.fftfreq(n) * n
    fx = np.fft.fftfreq(m) * m
    gx, gy = np.meshgrid(fx, fy)
    r = np.sqrt((gx * aniso[0]) ** 2 + (gy * aniso[1]) ** 2)
    r[0, 0] = 1.0
    amp = r ** (-beta * 0.5)
    amp[0, 0] = 0.0
    if fmin > 0:
        amp *= 1.0 - np.exp(-(r / fmin) ** 2)
    if fmax is not None:
        amp *= np.exp(-(r / fmax) ** 2)
    out = np.real(np.fft.ifft2(spec * amp))
    out -= out.mean()
    s = out.std()
    return out / (s if s > 1e-9 else 1.0)


def unit(a):
    """Rescale to [0, 1]."""
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / max(hi - lo, 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def voronoi(n, count, seed, stretch=(1.0, 1.0), warp=None, m=None, k=3):
    """A tileable Voronoi diagram over an `n` x `m` grid: the distances to the
    nearest `k` points (F1, F2, ...) and the index of the nearest. `stretch`
    scales the metric along (x, y) (a small y factor elongates cells
    vertically). `warp` is an optional (dx, dy) pair of arrays in tile units,
    added to each pixel's position first.
    """
    m = n if m is None else m
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2))
    offs = np.array([(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1)], float)
    allp = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2)
    s = np.array(stretch, float)
    tree = cKDTree(allp * s)
    ys, xs = np.mgrid[0:n, 0:m]
    gx = (xs + 0.5) / m
    gy = (ys + 0.5) / n
    if warp is not None:
        gx = gx + warp[0]
        gy = gy + warp[1]
    gx = np.mod(gx, 1.0)
    gy = np.mod(gy, 1.0)
    q = np.stack([gx.ravel(), gy.ravel()], axis=1) * s
    d, idx = tree.query(q, k=k)
    d = d.reshape(n, m, k)
    cell = (idx[:, 0] % count).reshape(n, m)
    return d, cell


def blur_wrap(a, sigma):
    return ndimage.gaussian_filter(a, sigma, mode="wrap")


def normal_map(height, strength):
    """Tangent-space normals from a tileable height field (wrapping at the
    edges), packed to RGB bytes. `strength` is how many texels of rise one
    unit of height stands for."""
    hx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    hy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -hx * strength
    # Rows run down the image; "up" in tangent space is toward row 0.
    ny = hy * strength
    nz = np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return np.clip(rgb * 127.5 + 127.5, 0, 255).astype(np.uint8)


def cavity(height, sigma):
    """How much lower a texel is than its neighbourhood: 0 on a crest, up to
    1 in a crack. A cheap stand-in for ambient occlusion in a texture."""
    c = blur_wrap(height, sigma) - height
    return np.clip(c / max(1e-6, np.percentile(np.abs(c), 99)), 0, 1)


def to_img(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        return Image.fromarray(rgb, "RGB").convert("RGBA")
    a = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, a]), "RGBA")


def lerp3(a, b, t):
    """Lerp colour arrays/tuples by a field `t` (H x W)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    return a + (b - a) * t[..., None]


# ---------------------------------------------------------------------------
# Bark
# ---------------------------------------------------------------------------

def bark(n=1024, seed=11):
    """Old furrowed bark, tiling both ways, its grain running down the
    texture (along the branch). Deep furrows between long interlacing plates,
    the plates cracked across, fibrous, grey-brown and weathered silver on
    their crests, with lichen crusting the crests and moss in the furrows.

    Returns (albedo RGBA with height in alpha, normal RGB, moss mask).
    """
    # The furrow network: Voronoi cells drawn out along the grain and
    # warped, so the furrows wander, fork and rejoin as real ones do.
    count = 34
    wx = spectral(n, seed + 1, beta=3.2) * 0.022
    wy = spectral(n, seed + 2, beta=3.2) * 0.050
    d, cell = voronoi(n, count, seed, stretch=(1.0, 0.22), warp=(wx, wy))
    # The distance to the cell's border as a share of the cell's own size,
    # so big and small plates have the same profile.
    edge = (d[..., 1] - d[..., 0]) / np.maximum(d[..., 1] + d[..., 0], 1e-6)
    rng = np.random.default_rng(seed + 3)
    cell_h = rng.uniform(0.80, 1.0, count)[cell]
    cell_tone = rng.uniform(-1, 1, count)[cell]

    # A plate's profile: a dark furrow, steep sides, a broad crest.
    plate = smoothstep(0.02, 0.30, edge) ** 0.8
    # Fine fibres along the grain, and the plates' cross cracks (a second
    # diagram drawn out across the grain, so its borders run across it).
    fib = spectral(n, seed + 4, beta=1.6, aniso=(1.0, 10.0), fmin=8)
    fib2 = spectral(n, seed + 5, beta=1.0, aniso=(1.0, 5.0), fmin=40)
    d2, _ = voronoi(n, 120, seed + 6, stretch=(0.20, 1.0))
    e2 = (d2[..., 1] - d2[..., 0]) / np.maximum(d2[..., 1] + d2[..., 0], 1e-6)
    crack = 1.0 - smoothstep(0.0, 0.035, e2)
    crack *= smoothstep(0.35, 0.8, plate)          # only across the plates
    lump = spectral(n, seed + 7, beta=2.6, fmin=2)

    h = plate * cell_h
    h += 0.035 * fib * plate + 0.015 * fib2 + 0.04 * lump
    h -= 0.22 * crack
    h = blur_wrap(h, 0.7)
    h = unit(h)

    cav = cavity(h, 6.0)

    # Colour. Dead wood at night: grey-brown in the body, weathering to
    # silver-grey on the crests, near black down in the furrows.
    deep = np.array([24, 20, 18], float)
    body = np.array([78, 68, 58], float)
    crest = np.array([128, 122, 112], float)
    t = smoothstep(0.15, 0.95, h)
    col = lerp3(deep, body, smoothstep(0.0, 0.45, h))
    col = lerp3(col, crest, smoothstep(0.55, 1.0, h) * (0.55 + 0.25 * unit(lump)))
    col *= (1.0 + 0.10 * cell_tone)[..., None]
    col *= (0.92 + 0.10 * unit(fib))[..., None]
    col *= (1.0 - 0.55 * cav)[..., None]

    # Lichen: pale crusts in patches on the crests.
    lpatch = unit(spectral(n, seed + 8, beta=2.4, fmin=3))
    lgrain = unit(spectral(n, seed + 9, beta=0.6, fmin=60))
    lichen = smoothstep(0.62, 0.78, lpatch + 0.10 * lgrain) * smoothstep(0.45, 0.8, h)
    lichen *= smoothstep(0.35, 0.65, lgrain)
    col = lerp3(col, np.array([150, 156, 138], float) * (0.85 + 0.3 * lgrain)[..., None],
                lichen * 0.85)

    # Moss: dark olive in the furrows, in patches. Returned separately too,
    # so the shader can hold it back (the wood's one bright green is ivy).
    mpatch = unit(spectral(n, seed + 10, beta=2.8, fmin=2))
    moss = smoothstep(0.50, 0.70, mpatch) * smoothstep(0.55, 0.15, h)
    mgrain = unit(spectral(n, seed + 12, beta=0.5, fmin=80))
    moss *= 0.6 + 0.4 * mgrain
    col = lerp3(col, np.array([44, 52, 34], float) * (0.7 + 0.5 * mgrain)[..., None],
                moss * 0.75)

    # The height in alpha (kept above zero: a sprite with a fully clear
    # texel can trip GameMaker's empty-frame logic).
    alpha = 32 + h * 223
    hn = h + 0.25 * moss * mgrain
    nrm = normal_map(hn, 7.0)
    return to_img(col, alpha), Image.fromarray(nrm, "RGB"), moss


# ---------------------------------------------------------------------------
# The forest floor
# ---------------------------------------------------------------------------

LEAF_TONES = [
    (92, 64, 40), (110, 78, 48), (78, 58, 40), (120, 96, 62),
    (70, 52, 38), (98, 84, 64), (84, 76, 62), (64, 48, 34),
    (132, 104, 66), (104, 70, 44),
]


def _leaf_poly(cx, cy, length, width, ang, kind, rng):
    """A fallen leaf's outline: kind 0 an oval with a point, 1 a lobed oak
    leaf, 2 a narrow willow leaf. Points in pixels."""
    pts = []
    steps = 22
    for i in range(steps + 1):
        t = i / steps                          # 0 tip .. 1 stalk
        if kind == 2:
            w = width * 0.45 * math.sin(math.pi * t) ** 0.8
        else:
            w = width * 0.5 * math.sin(math.pi * t) ** 0.7 * (1.0 + 0.15 * (t - 0.5))
        if kind == 1:
            w *= 1.0 + 0.30 * math.sin(t * math.pi * 7.0) ** 2
        pts.append((t, w))
    out = []
    ca, sa = math.cos(ang), math.sin(ang)
    for t, w in pts:
        x = (t - 0.5) * length
        out.append((cx + x * ca - w * sa, cy + x * sa + w * ca))
    for t, w in reversed(pts):
        x = (t - 0.5) * length
        out.append((cx + x * ca + w * sa, cy + x * sa - w * ca))
    return out


def _leaf_half(poly):
    """One half of a leaf from `_leaf_poly`'s outline: its first side and
    back down the midrib (the outline's first point is the tip and its
    middle the stalk)."""
    k = len(poly) // 2
    tip = poly[0]
    stalk = poly[k - 1]
    side = poly[:k]
    rib = [(tip[0] + (stalk[0] - tip[0]) * f, tip[1] + (stalk[1] - tip[1]) * f)
           for f in np.linspace(1.0, 0.0, 6)]
    return side + rib


def litter(n=1024, seed=21, density=1.0, path=False):
    """The forest floor (or, with `path`, the trodden path): soil, fallen
    leaves in overlapping layers with their shadows, twigs, pebbles and moss.
    Drawn at twice the size and wrapped at the edges so it tiles.

    Returns (albedo RGBA, height in alpha), normal RGB.
    """
    ss = 2
    N = n * ss
    rng = np.random.default_rng(seed)

    # The soil and humus under everything.
    soil_n = unit(spectral(n, seed + 1, beta=2.2, fmin=2))
    grain = unit(spectral(n, seed + 2, beta=0.7, fmin=90))
    if path:
        # Trodden earth: damp, darker hollows, and fine grit.
        damp = smoothstep(0.45, 0.75, unit(spectral(n, seed + 3, beta=2.8, fmin=2)))
        grit = unit(spectral(n, seed + 4, beta=0.2, fmin=200))
        soil = lerp3(np.array([44, 38, 32], float), np.array([76, 68, 58], float),
                     0.50 * soil_n + 0.30 * grain + 0.20 * grit)
        soil *= (1.0 - 0.32 * damp)[..., None]
        soil *= (0.90 + 0.22 * smoothstep(0.75, 0.95, grit))[..., None]
    else:
        soil = lerp3(np.array([24, 20, 16], float), np.array([48, 40, 30], float),
                     0.6 * soil_n + 0.4 * grain)
    height = 0.10 * soil_n + 0.05 * grain

    # Leaves and twigs, drawn into big canvases (colour, height), each shape
    # also drawn at its wrapped positions.
    col_img = Image.new("RGB", (N, N), (0, 0, 0))
    hgt_img = Image.new("L", (N, N), 0)
    cov_img = Image.new("L", (N, N), 0)
    shd_img = Image.new("L", (N, N), 0)
    dc = ImageDraw.Draw(col_img)
    dh = ImageDraw.Draw(hgt_img)
    dv = ImageDraw.Draw(cov_img)
    ds = ImageDraw.Draw(shd_img)

    def wrapped(poly, fn):
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        for ox in (-N, 0, N):
            if max(xs) + ox < 0 or min(xs) + ox > N:
                continue
            for oy in (-N, 0, N):
                if max(ys) + oy < 0 or min(ys) + oy > N:
                    continue
                fn([(x + ox, y + oy) for x, y in poly])

    count = int((1300 if not path else 260) * density)
    layers = 5
    for layer in range(layers):
        lift = 40 + layer * 40
        for _ in range(count // layers):
            cx, cy = rng.random() * N, rng.random() * N
            kind = rng.choice([0, 0, 1, 1, 2])
            length = rng.uniform(34, 70) * ss * (0.8 if path else 1.0)
            width = length * rng.uniform(0.45, 0.7) * (0.55 if kind == 2 else 1.0)
            ang = rng.random() * math.tau
            poly = _leaf_poly(cx, cy, length, width, ang, kind, rng)
            tone = np.array(LEAF_TONES[rng.integers(len(LEAF_TONES))], float)
            tone *= rng.uniform(0.75, 1.1)
            if path:
                tone = tone * 0.7 + np.array([40, 36, 32]) * 0.3
            # Its shadow, offset down and right, then the leaf.
            sh = [(x + 3 * ss, y + 4 * ss) for x, y in poly]
            wrapped(sh, lambda p: ds.polygon(p, fill=110))
            c = tuple(int(v) for v in np.clip(tone * 0.80, 0, 255))
            wrapped(poly, lambda p, c=c: dc.polygon(p, fill=c))
            wrapped(poly, lambda p, l=lift: dh.polygon(p, fill=l))
            wrapped(poly, lambda p: dv.polygon(p, fill=255))
            # The half turned toward the light is lighter, as a curled leaf
            # catches it, and stands a little higher.
            half = _leaf_half(poly)
            lit = rng.uniform(1.05, 1.32)
            hc = tuple(int(v) for v in np.clip(tone * lit * 0.80, 0, 255))
            wrapped(half, lambda p, c=hc: dc.polygon(p, fill=c))
            wrapped(half, lambda p, l=lift + 12: dh.polygon(p, fill=l))
            # The midrib, a thin darker line.
            mx0 = cx - math.cos(ang) * length * 0.48
            my0 = cy - math.sin(ang) * length * 0.48
            mx1 = cx + math.cos(ang) * length * 0.50
            my1 = cy + math.sin(ang) * length * 0.50
            rib = tuple(int(v * 0.72) for v in c)
            wrapped([(mx0, my0), (mx1, my1)],
                    lambda p, r=rib: dc.line(p, fill=r, width=max(1, ss)))

        # Twigs between the layers.
        for _ in range((60 if not path else 25)):
            x0, y0 = rng.random() * N, rng.random() * N
            a = rng.random() * math.tau
            ln = rng.uniform(40, 160) * ss
            pts = [(x0, y0)]
            for s in range(5):
                a += rng.normal(0, 0.25)
                x0 += math.cos(a) * ln / 5
                y0 += math.sin(a) * ln / 5
                pts.append((x0, y0))
            w = int(rng.uniform(2, 5) * ss)
            tc = tuple(int(v) for v in rng.uniform(0.7, 1.0) * np.array([60, 48, 38]))
            wrapped([(x + 3 * ss, y + 4 * ss) for x, y in pts],
                    lambda p, w=w: ds.line(p, fill=120, width=w + ss))
            wrapped(pts, lambda p, w=w, tc=tc: dc.line(p, fill=tc, width=w))
            wrapped(pts, lambda p, w=w, l=lift + 30: dh.line(p, fill=l, width=w))
            wrapped(pts, lambda p, w=w: dv.line(p, fill=255, width=w))

    # Pebbles, half sunk in the soil: a dark body, a lit cap toward the
    # upper left, and a shadow.
    for _ in range((30 if not path else 90)):
        cx, cy = rng.random() * N, rng.random() * N
        r = rng.uniform(3, 11) ** 1.0 * ss
        g = rng.uniform(46, 92)
        warm = rng.uniform(0.86, 1.0)
        c = (int(g), int(g * (0.96 + 0.03 * warm)), int(g * 0.90 * warm))
        cl = tuple(int(min(255, v * 1.35)) for v in c)
        el = rng.uniform(0.65, 0.9)
        box = [cx - r, cy - r * el, cx + r, cy + r * el]
        cap = [cx - r * 0.78, cy - r * el * 0.85, cx + r * 0.42, cy + r * el * 0.30]
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                b = [box[0] + ox, box[1] + oy, box[2] + ox, box[3] + oy]
                k = [cap[0] + ox, cap[1] + oy, cap[2] + ox, cap[3] + oy]
                ds.ellipse([b[0] + 2 * ss, b[1] + 3 * ss, b[2] + 2 * ss, b[3] + 3 * ss], fill=130)
                dc.ellipse(b, fill=c)
                dc.ellipse(k, fill=cl)
                dh.ellipse(b, fill=150)
                dh.ellipse(k, fill=185)
                dv.ellipse(b, fill=255)

    down = lambda im: np.asarray(im.resize((n, n), Image.LANCZOS), float)
    lc = down(col_img)
    lh = down(hgt_img) / 255.0
    lv = down(cov_img) / 255.0
    shadow = blur_wrap(down(shd_img) / 255.0, 2.0)

    col = soil * (1 - lv[..., None]) + lc * lv[..., None] / np.maximum(lv, 1e-3)[..., None] * lv[..., None]
    col = np.where(lv[..., None] > 0.02, col, soil)
    # Shadows fall on what is under each leaf (approximately: darken where
    # the shadow layer is and the leaf on top is lower).
    col *= (1.0 - 0.45 * shadow * (1.0 - 0.6 * lv))[..., None]
    height = height + lh * 0.9

    # Moss in patches over the litter (on the floor only).
    if not path:
        mp = unit(spectral(n, seed + 5, beta=2.6, fmin=2))
        mg = unit(spectral(n, seed + 6, beta=0.4, fmin=120))
        moss = smoothstep(0.60, 0.78, mp + 0.08 * mg)
        col = lerp3(col, np.array([40, 50, 30], float) * (0.7 + 0.6 * mg)[..., None],
                    moss * 0.85)
        height = height * (1 - moss * 0.6) + moss * (0.5 + 0.15 * mg)

    # Fine grain over everything.
    fg = spectral(n, seed + 7, beta=0.3, fmin=150)
    col *= (1.0 + 0.06 * fg)[..., None]
    height = blur_wrap(height, 0.7)
    cav = cavity(height, 4.0)
    col *= (1.0 - 0.35 * cav)[..., None]
    h = unit(height)
    nrm = normal_map(h, 5.0 if not path else 3.5)
    return to_img(col, 32 + h * 223), Image.fromarray(nrm, "RGB")


# ---------------------------------------------------------------------------
# The sky
# ---------------------------------------------------------------------------

# The near side's seas, roughly where they lie on the real moon (x right, y
# up, the disc's radius 1): centre, radii, and how dark.
MARIA = [
    ((-0.30, 0.42), (0.27, 0.22), 0.95),    # Imbrium
    ((0.24, 0.42), (0.16, 0.15), 1.00),     # Serenitatis
    ((0.40, 0.16), (0.20, 0.15), 0.95),     # Tranquillitatis
    ((0.72, 0.30), (0.10, 0.08), 1.00),     # Crisium
    ((0.62, -0.10), (0.11, 0.15), 0.85),    # Fecunditatis
    ((0.40, -0.25), (0.08, 0.08), 0.85),    # Nectaris
    ((-0.62, 0.05), (0.24, 0.42), 0.80),    # Procellarum
    ((-0.42, 0.28), (0.18, 0.14), 0.75),
    ((-0.15, -0.30), (0.17, 0.13), 0.80),   # Nubium
    ((-0.50, -0.38), (0.09, 0.08), 0.90),   # Humorum
    ((0.05, 0.20), (0.08, 0.06), 0.75),     # Vaporum
    ((-0.20, 0.06), (0.10, 0.07), 0.60),    # Insularum
    ((0.00, 0.72), (0.38, 0.05), 0.80),     # Frigoris
    ((0.48, 0.58), (0.10, 0.06), 0.70),
]

# Bright young craters with rays: centre, radius, ray length, brightness.
RAYED = [
    ((-0.15, -0.68), 0.030, 0.95, 1.00),    # Tycho
    ((-0.30, 0.18), 0.032, 0.42, 0.70),     # Copernicus
    ((-0.56, 0.14), 0.018, 0.30, 0.60),     # Kepler
    ((-0.70, 0.36), 0.012, 0.18, 0.90),     # Aristarchus
    ((0.62, -0.02), 0.014, 0.25, 0.45),
]


def moon(n=1024, seed=31):
    """A full moon as it looks to the eye: pale highlands, the darker seas
    laid out as on the real near side (`MARIA`), soft-edged and mottled, a
    few bright craters throwing rays (`RAYED`) and a scatter of small ones,
    gentle limb darkening, and a crisp anti-aliased edge. Luminance only,
    tinted by the shader (pale, then blood)."""
    rng = np.random.default_rng(seed)
    ss = 2
    N = n * ss
    ys, xs = np.mgrid[0:N, 0:N]
    R = 0.94
    u = ((xs + 0.5) / N * 2 - 1) / R
    v = -((ys + 0.5) / N * 2 - 1) / R            # y up
    r = np.sqrt(u * u + v * v)
    inside = r < 1.0
    z = np.sqrt(np.clip(1 - r * r, 0, 1))

    def field(scale, seed2, beta):
        f = spectral(N // scale, seed2, beta=beta, fmin=1.0)
        img = Image.fromarray(unit(f).astype(np.float32))
        return np.asarray(img.resize((N, N), Image.BICUBIC))

    warp_x = (field(8, seed + 1, 3.0) - 0.5) * 0.16
    warp_y = (field(8, seed + 2, 3.0) - 0.5) * 0.16
    shore = field(8, seed + 5, 2.6)
    mott = field(4, seed + 3, 2.0)
    fine = field(2, seed + 4, 1.0)

    # The seas: each an ellipse with a wandering, softened edge.
    sea = np.zeros((N, N))
    uu, vv = u + warp_x, v + warp_y
    for (cx, cy), (rx, ry), dark in MARIA:
        d = np.sqrt(((uu - cx) / (rx * 1.15)) ** 2 + ((vv - cy) / (ry * 1.15)) ** 2)
        edge = 1.0 - smoothstep(0.78, 1.08, d + (shore - 0.5) * 0.30)
        sea = np.maximum(sea, edge * dark)
    sea = np.clip(blur_wrap(sea, N * 0.0015) * 1.04, 0, 1)
    alb = 0.80 - 0.30 * sea
    # Mottling: the highlands rough, the seas smoother and a little varied.
    alb += (mott - 0.5) * (0.10 - 0.05 * sea) + (fine - 0.5) * 0.06

    # A scatter of small craters, mostly as albedo: a slightly darker floor,
    # a lighter rim, nothing like a drawn ring.
    for i in range(160):
        cx, cy = rng.uniform(-0.95, 0.95, 2)
        if cx * cx + cy * cy > 0.92:
            continue
        cr = 0.006 + 0.035 * rng.random() ** 2.5
        x0 = int(((cx * R) + 1) * 0.5 * N - cr * R * N * 2)
        x1 = int(((cx * R) + 1) * 0.5 * N + cr * R * N * 2) + 1
        y0 = int((1 - cy * R) * 0.5 * N - cr * R * N * 2)
        y1 = int((1 - cy * R) * 0.5 * N + cr * R * N * 2) + 1
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, N), min(y1, N)
        if x1 <= x0 or y1 <= y0:
            continue
        sub_u = u[y0:y1, x0:x1]
        sub_v = v[y0:y1, x0:x1]
        d = np.sqrt((sub_u - cx) ** 2 + (sub_v - cy) ** 2) / cr
        rim = np.exp(-((d - 1.0) / 0.25) ** 2)
        floor = np.clip(1 - d, 0, 1) ** 0.5
        k = rng.uniform(0.3, 1.0)
        alb[y0:y1, x0:x1] += k * (0.035 * rim - 0.035 * floor * (1 - 0.5 * sea[y0:y1, x0:x1]))

    # The rayed craters: a bright splash, and streaks out of it across the
    # face, thinning with distance.
    for (cx, cy), cr, ln, br in RAYED:
        d = np.sqrt((u - cx) ** 2 + (v - cy) ** 2)
        ang = np.arctan2(v - cy, u - cx)
        ray = np.zeros_like(d)
        for k in range(12):
            a = rng.random() * math.tau
            w = rng.uniform(0.05, 0.13)
            da = np.angle(np.exp(1j * (ang - a)))
            ray += np.exp(-(da / w) ** 2) * rng.uniform(0.3, 1.0)
        reach = ln * rng.uniform(0.7, 1.0)
        streak = ray * np.exp(-d / reach) * smoothstep(cr * 1.2, cr * 4.0, d)
        streak *= 0.7 + 0.6 * mott
        splash = np.exp(-(d / (cr * 2.6)) ** 2)
        alb += br * (0.055 * np.clip(streak, 0, 1.5) + 0.20 * splash)
        alb -= br * 0.10 * np.exp(-(d / (cr * 0.7)) ** 2)

    limb = 0.62 + 0.38 * z ** 0.5
    lum = np.clip(alb * limb, 0, 1)
    img = np.where(inside, lum, 0.0)
    a = np.clip((1.0 - r) * R * N * 0.5 + 0.5, 0, 1)
    out = Image.fromarray(np.dstack(
        [np.clip(img * 255, 0, 255).astype(np.uint8)] * 3
        + [np.clip(a * 255, 0, 255).astype(np.uint8)]), "RGBA")
    return out.resize((n, n), Image.LANCZOS)


def clouds(w=1024, h=512, seed=41):
    """Thin night clouds: long streaks drawn out sideways, soft-edged, their
    density in alpha and a little internal shading in the colour (thicker
    is darker), for cards in the sky that the shader lights from behind."""
    f = spectral(h, seed, beta=2.8, aniso=(1.0, 7.0), fmin=1.2, m=w)
    f2 = spectral(h, seed + 1, beta=2.0, aniso=(1.0, 5.0), fmin=4, m=w)
    d = unit(f + 0.30 * f2)
    ys, xs = np.mgrid[0:h, 0:w]
    ex = np.minimum(xs, w - 1 - xs) / (w * 0.30)
    ey = np.minimum(ys, h - 1 - ys) / (h * 0.42)
    edge = smoothstep(0.0, 1.0, np.minimum(ex, ey))
    dens = smoothstep(0.52, 0.90, d) * edge
    dens = blur_wrap(dens, 1.2)
    shade = 1.0 - 0.5 * smoothstep(0.6, 0.95, d)
    rgb = np.dstack([shade * 255] * 3)
    return to_img(rgb, np.clip(dens / max(dens.max(), 1e-6), 0, 1) * 255)


def glow(n=256, falloff=2.2):
    """A soft round glow, white, its brightness in alpha (premultiplied use:
    the shader takes the alpha as the amount)."""
    ys, xs = np.mgrid[0:n, 0:n]
    r = np.sqrt(((xs + 0.5) / n * 2 - 1) ** 2 + ((ys + 0.5) / n * 2 - 1) ** 2)
    a = np.clip(1 - r, 0, 1) ** falloff
    a = a * 0.75 + np.exp(-(r / 0.10) ** 2) * 0.25
    a = np.clip(a / a.max(), 0, 1)
    return to_img(np.full((n, n, 3), 255.0), a * 255)


def star(n=64):
    """A star: a tight core, a soft halo and four faint spikes."""
    ys, xs = np.mgrid[0:n, 0:n]
    u = (xs + 0.5) / n * 2 - 1
    v = (ys + 0.5) / n * 2 - 1
    r = np.sqrt(u * u + v * v)
    a = np.exp(-(r / 0.10) ** 2) + 0.25 * np.exp(-(r / 0.35) ** 2)
    a += 0.18 * (np.exp(-(u / 0.035) ** 2) + np.exp(-(v / 0.035) ** 2)) * np.clip(1 - r, 0, 1) ** 2
    a = np.clip(a / a.max(), 0, 1) * np.clip((1 - r) * 4, 0, 1)
    return to_img(np.full((n, n, 3), 255.0), a * 255)


def puffs(n=512, seed=51):
    """Four soft mist puffs in a 2 x 2 sheet (density in alpha), for the
    mist cards and the motes."""
    out = np.zeros((n, n), float)
    q = n // 2
    for k in range(4):
        f = unit(spectral(q, seed + k, beta=2.2, fmin=1.0))
        f2 = unit(spectral(q, seed + 10 + k, beta=1.2, fmin=4.0))
        ys, xs = np.mgrid[0:q, 0:q]
        u = (xs + 0.5) / q * 2 - 1
        v = (ys + 0.5) / q * 2 - 1
        r = np.sqrt(u * u * (0.8 if k % 2 else 1.0) + v * v * (1.6 if k < 2 else 1.1))
        fall = np.clip(1 - r, 0, 1) ** 1.6
        d = fall * smoothstep(0.25, 0.85, 0.65 * f + 0.35 * f2 + 0.35 * fall)
        d = d / max(d.max(), 1e-6)
        oy, ox = (k // 2) * q, (k % 2) * q
        out[oy:oy + q, ox:ox + q] = d
    return to_img(np.full((n, n, 3), 255.0), out * 255)


# ---------------------------------------------------------------------------
# The charms' sheet
# ---------------------------------------------------------------------------

def charm_sheet(n=512, seed=71):
    """Four materials, a quadrant each (see `wood_charms`): bone (top left),
    old wood (top right), cord (bottom left) and iron (bottom right)."""
    q = n // 2
    out = np.zeros((n, n, 3))

    # Bone: off-white, porous, stained brown in its pores and cracks.
    por = unit(spectral(q, seed, beta=0.9, fmin=30))
    stain = unit(spectral(q, seed + 1, beta=2.6, fmin=2))
    d, _ = voronoi(q, 40, seed + 2)
    crack = 1.0 - smoothstep(0.0, 0.004, d[..., 1] - d[..., 0])
    bone = lerp3(np.array([214, 206, 186], float), np.array([150, 128, 98], float),
                 smoothstep(0.55, 0.95, stain) * 0.8)
    bone *= (0.86 + 0.18 * por)[..., None]
    bone *= (1.0 - 0.35 * crack * smoothstep(0.4, 0.7, stain))[..., None]
    out[:q, :q] = bone

    # Old wood: grey, its grain running down.
    g1 = spectral(q, seed + 3, beta=1.6, aniso=(1.0, 12.0), fmin=6)
    g2 = spectral(q, seed + 4, beta=2.4, aniso=(1.0, 5.0), fmin=2)
    t = unit(g1 * 0.7 + g2 * 0.5)
    wood = lerp3(np.array([70, 62, 54], float), np.array([140, 128, 112], float), t)
    out[:q, q:] = wood

    # Cord: twisted fibre, stripes running diagonally.
    ys, xs = np.mgrid[0:q, 0:q]
    tw = 0.5 + 0.5 * np.sin((xs + ys * 0.9) / q * math.tau * 9)
    fib = unit(spectral(q, seed + 5, beta=0.8, fmin=40))
    cord = lerp3(np.array([58, 46, 36], float), np.array([118, 98, 76], float),
                 0.65 * tw + 0.35 * fib)
    out[q:, :q] = cord

    # Iron: dark, pitted, rust in patches.
    pit = unit(spectral(q, seed + 6, beta=0.7, fmin=50))
    rust = smoothstep(0.55, 0.85, unit(spectral(q, seed + 7, beta=2.4, fmin=2)))
    iron = lerp3(np.array([44, 44, 48], float), np.array([96, 54, 32], float), rust * 0.7)
    iron *= (0.8 + 0.35 * pit)[..., None]
    out[q:, q:] = iron
    return to_img(out)


def flat_normal(n=8):
    """A normal map that bends nothing (for parts without one)."""
    return Image.new("RGBA", (n, n), (128, 128, 255, 255))


def ring(n=512, r=0.893, width=0.035):
    """A thin soft ring of light (the rim round the moon at totality, and the
    ring that leaves it as it turns), its brightness in alpha."""
    ys, xs = np.mgrid[0:n, 0:n]
    d = np.sqrt(((xs + 0.5) / n * 2 - 1) ** 2 + ((ys + 0.5) / n * 2 - 1) ** 2)
    a = np.exp(-((d - r) / width) ** 2) + 0.35 * np.exp(-((d - r) / (width * 3.5)) ** 2)
    a *= np.clip((1.0 - d) * 12, 0, 1)
    a = np.clip(a / a.max(), 0, 1)
    return to_img(np.full((n, n, 3), 255.0), a * 255)
