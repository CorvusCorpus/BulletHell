#!/usr/bin/env python3
"""The wood's ground cover (`tools/make_wood.py` writes it out): ferns and
dead bracken, grass, heather, mossy rocks, skulls and bones half sunk in the
litter, fallen logs, stumps, and standing stones, after the owner's Velka
commission and the grove's undergrowth.

Small things are gathered into patches, each one vertex list placed whole
(`wood_props` in `scripts/bg_wood`); every prop in a patch carries its own
anchor, so it stands on the ground under itself. Standing stones are placed
on their own.

Cards (fronds, grass, heather) and the opaque props' stone and bone come
from the foliage sheet (`wood_tex.foliage_sheet`), as `KIND_CARD` and
`KIND_ATLAS`; logs and stumps are bark, from the bark texture like the
trees, and the shader grows moss on them as it does on the trees.
"""
import math

import numpy as np

import wood_charms as WC
import wood_mesh as M
import wood_tex as TX

INSET = 0.04


def to_list(v):
    """A strip as a triangle list (the patches are lists)."""
    return WC.strip_to_list(v)


def with_anchor(v, ax, az, conform=None):
    """Give every vertex the anchor `(ax, az)` (the ground under it), and
    optionally a conform value."""
    v = v.copy()
    v["ex"][:, 0] = ax
    v["ex"][:, 1] = az
    if conform is not None:
        kind = np.floor(v["ex"][:, 2] / 4.0 + 1e-3)
        v["ex"][:, 2] = kind * 4 + conform
    return v


def cell_uv(v, name):
    """Squeeze texture coordinates (0..1) into a sheet cell."""
    u0, v0, u1, v1 = TX.cell_rect(name, INSET)
    v = v.copy()
    v["uv"][:, 0] = u0 + (u1 - u0) * np.clip(v["uv"][:, 0], 0, 1)
    v["uv"][:, 1] = v0 + (v1 - v0) * np.clip(v["uv"][:, 1], 0, 1)
    return v


def set_kind(v, kind):
    v = v.copy()
    conf = v["ex"][:, 2] - np.floor(v["ex"][:, 2] / 4.0 + 1e-3) * 4
    v["ex"][:, 2] = kind * 4 + conf
    return v


# ---------------------------------------------------------------------------
# Cards
# ---------------------------------------------------------------------------

def frond(base, ang, lean, length, width, cell, rng, tint=(1, 1, 1)):
    """One fern frond: a card standing out of `base` toward azimuth `ang`,
    leaning out by `lean` (radians from upright) and arching over, its
    picture's foot at the base."""
    rows = 5
    up = np.array([0.0, 1.0, 0.0])
    out = np.array([math.cos(ang), 0.0, math.sin(ang)])
    side = np.cross(up, out)
    pts = []
    for i in range(rows + 1):
        t = i / rows
        a = lean + t * t * 0.9          # it arches over toward its tip
        d = out * math.sin(a) + up * math.cos(a)
        if i == 0:
            p = np.asarray(base, float)
        else:
            p = pts[-1] + d * length / rows
        pts.append(p)
    corners_l = [p - side * width * 0.5 for p in pts]
    corners_r = [p + side * width * 0.5 for p in pts]
    bend = [(corners_l[i], corners_r[i]) for i in range(1, rows)]
    c = M.card((corners_l[0], corners_r[0], corners_r[-1], corners_l[-1]),
               (0.0, 0.0, 1.0, 1.0), np.asarray(tint, float), ao=1.0,
               sway=(0.0, 0.25, 0.6, 1.0), bend=bend)
    return cell_uv(to_list(c), cell)


def fern_clump(rng, at, dead):
    """Fronds springing from one crown, in a ring, leaning out and
    arching."""
    parts = []
    n = int(rng.integers(6, 11))
    a0 = rng.random() * math.tau
    size = rng.uniform(0.75, 1.25)
    for k in range(n):
        ang = a0 + k * math.tau / n + rng.normal(0, 0.25)
        cell = ("bracken%d" if dead else "fern%d") % int(rng.integers(0, 2))
        tint = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.8, 1.1)
        parts.append(frond(at, ang, rng.uniform(0.35, 0.8), rng.uniform(70, 120) * size,
                           rng.uniform(38, 52) * size, cell, rng, tint))
    v = np.concatenate(parts)
    return with_anchor(v, at[0], at[2], 0.0)


def crossed(rng, at, cell, h, w, n=3, tint=(1, 1, 1)):
    """A tuft as `n` upright cards crossed through one point."""
    parts = []
    a0 = rng.random() * math.pi
    for k in range(n):
        a = a0 + k * math.pi / n
        side = np.array([math.cos(a), 0.0, math.sin(a)]) * w * 0.5
        b = np.asarray(at, float)
        top = b + np.array([rng.normal(0, 4), h, rng.normal(0, 4)])
        c = M.card((b - side, b + side, top + side, top - side),
                   (0.0, 0.0, 1.0, 1.0), np.asarray(tint, float), ao=1.0,
                   sway=(0.0, 0.3, 0.7, 1.0))
        parts.append(cell_uv(to_list(c), cell))
    return with_anchor(np.concatenate(parts), at[0], at[2], 0.0)


# ---------------------------------------------------------------------------
# Solids
# ---------------------------------------------------------------------------

def blob(rng, at, r, sy, rough, cell, seg=10, sink=0.35, tint=(0.62, 0.62, 0.62)):
    """A rock: a sphere pushed about by noise, squashed, and sunk part way
    into the ground. Textured from a sheet cell by its direction from its
    middle."""
    nu, nv = seg * 2, seg
    ph = rng.uniform(0, math.tau, 6)
    fr = rng.uniform(1.5, 3.5, 6)

    def surf(th, phi):
        d = np.array([math.cos(phi) * math.cos(th), math.sin(phi),
                      math.cos(phi) * math.sin(th)])
        k = 1.0
        for i in range(3):
            k += rough * 0.18 * math.sin(fr[i] * th + ph[i]) * math.cos(fr[i + 3] * phi + ph[i + 3])
        return d * r * k * np.array([1.0, sy, 1.0])

    tris = []
    for i in range(nu):
        for j in range(nv):
            t0, t1 = i / nu * math.tau, (i + 1) / nu * math.tau
            p0, p1 = -math.pi / 2 + j / nv * math.pi, -math.pi / 2 + (j + 1) / nv * math.pi
            q = [surf(t0, p0), surf(t1, p0), surf(t1, p1), surf(t0, p1)]
            uvq = [(i / nu, 1 - j / nv), ((i + 1) / nu, 1 - j / nv),
                   ((i + 1) / nu, 1 - (j + 1) / nv), (i / nu, 1 - (j + 1) / nv)]
            for k in (0, 1, 2, 0, 2, 3):
                tris.append((q[k], uvq[k]))
    P = np.array([t[0] for t in tris])
    UV = np.array([t[1] for t in tris])
    # Normals: from the faces, averaged by position.
    F = P.reshape(-1, 3, 3)
    fn = np.cross(F[:, 1] - F[:, 0], F[:, 2] - F[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    N = np.repeat(fn, 3, axis=0)
    out = P / np.maximum(np.linalg.norm(P, axis=1, keepdims=True), 1e-9)
    N = np.where(np.sum(N * out, axis=1, keepdims=True) < 0, -N, N)
    N = 0.5 * N + 0.5 * out
    N /= np.linalg.norm(N, axis=1, keepdims=True)
    P = P + np.asarray(at, float) + np.array([0.0, -r * sy * sink, 0.0])
    n = len(P)
    col = np.ones((n, 4))
    col[:, :3] = tint
    # Darker where it meets the ground.
    col[:, 3] = np.clip(0.45 + 0.55 * (P[:, 1] - at[1]) / (r * sy * 0.6), 0.45, 1.0)
    ex = np.zeros((n, 4))
    ex[:, 0] = at[0]
    ex[:, 1] = at[2]
    ex[:, 2] = M.KIND_ATLAS * 4
    return cell_uv(M.verts(P, N, col, UV, ex), cell)


def bone_on_ground(rng, at, length, r):
    a = rng.random() * math.tau
    d = np.array([math.cos(a), 0.0, math.sin(a)]) * length * 0.5
    base = np.asarray(at, float) + np.array([0.0, r * 0.4, 0.0])
    v = WC.bone(base - d, base + d, r, tint=(0.5, 0.48, 0.44))
    v = set_kind(v, M.KIND_ATLAS)
    # Its picture from the foliage sheet's bone (the charm sheet's bone is
    # its top left quarter, so the coordinates are doubled back to 0..1).
    v["uv"] = np.clip(v["uv"] * 2.0, 0.0, 1.0)
    v = cell_uv(v, "bone")
    return with_anchor(v, at[0], at[2], 0.0)


def skull_on_ground(rng, at):
    """A skull settled in the litter, tipped over, half sunk."""
    sk = WC.skull_mesh(step=1.8)
    sk = set_kind(sk, M.KIND_ATLAS)
    # Bone from the foliage sheet, by its own projection.
    p = sk["pos"]
    sk["uv"] = np.stack([(p[:, 0] + 26) / 52, (p[:, 1] + 14) / 48], 1)
    sk = cell_uv(sk, "bone")
    tilt = M.rot_axis(np.array([0.0, 0.0, 1.0]), rng.uniform(-0.5, 0.5))
    yaw = M.rot_y(rng.uniform(0, 360))
    rot = yaw @ tilt
    sc = rng.uniform(1.15, 1.45)
    v = M.transform(sk, rot, np.asarray(at, float) + np.array([0.0, 2.0 * sc, 0.0]), sc)
    v["col"][:, :3] = np.clip(v["col"][:, :3].astype(float) * 0.55, 0, 255).astype(np.uint8)
    return with_anchor(v, at[0], at[2], 0.0)


def log(rng, at, length, r):
    """A fallen trunk lying across the ground, following its bumps, broken
    at both ends."""
    a = rng.random() * math.tau
    d = np.array([math.cos(a), 0.0, math.sin(a)])
    n = max(4, int(length / 30))
    t = np.linspace(-0.5, 0.5, n)
    P = np.asarray(at, float)[None, :] + d[None, :] * (t * length)[:, None]
    P[:, 1] += r * 0.55 + rng.normal(0, 2, n)
    R = r * (1.0 - 0.15 * (t + 0.5)) * (1 + 0.04 * rng.normal(size=n))
    v = M.tube(P, R, 12, np.array([0.85, 0.82, 0.78]), ao=np.full(n, 0.85),
               conform=np.ones(n), u_tile=170.0, v_tile=340.0)
    T, N, B = M.frames(P)
    caps = [M.cap(P[-1], T[-1], N[-1], B[-1], float(R[-1]), 12,
                  np.array([0.6, 0.52, 0.44]), ao=0.7, jag=0.8, rng=rng),
            M.cap(P[0], -T[0], N[0], -B[0], float(R[0]), 12,
                  np.array([0.6, 0.52, 0.44]), ao=0.7, jag=0.8, rng=rng)]
    parts = [to_list(v)] + [to_list(c) for c in caps]
    out = np.concatenate(parts)
    # Each vertex follows the ground under itself (it lies along it).
    out["ex"][:, 0] = out["pos"][:, 0]
    out["ex"][:, 1] = out["pos"][:, 2]
    out["ex"][:, 2] = np.floor(out["ex"][:, 2] / 4.0 + 1e-3) * 4 + 1.0
    return out


def stump(rng, at, r, h):
    """A broken stump with a ragged top."""
    n = 5
    P = np.asarray(at, float)[None, :] + np.stack(
        [rng.normal(0, 3, n), np.linspace(-20, h, n), rng.normal(0, 3, n)], 1)
    R = r * np.linspace(1.25, 0.9, n)
    flare = lambda th, i: 1.0 + 0.35 * max(0.0, 1 - i / 2) * (1 + 0.6 * np.cos(th * 4))
    v = M.tube(P, R, 14, np.array([0.85, 0.8, 0.76]), ao=np.linspace(0.5, 0.9, n),
               lobe=flare, u_tile=170.0, v_tile=340.0)
    T, N, B = M.frames(P)
    c = M.cap(P[-1], T[-1], N[-1], B[-1], float(R[-1]), 14,
              np.array([0.55, 0.47, 0.40]), ao=0.75, jag=1.6, rng=rng)
    out = np.concatenate([to_list(v), to_list(c)])
    return with_anchor(out, at[0], at[2], 0.0)


def standing_stone(rng):
    """A standing stone: a tall rough slab, a little out of true, worn at the
    top, sunk in the ground, mossy at the foot."""
    h = rng.uniform(240, 420)
    w = rng.uniform(70, 110)
    dpt = w * rng.uniform(0.45, 0.65)
    lean = rng.normal(0, 0.06)
    rows, cols = 10, 16
    tris = []
    ph = rng.uniform(0, math.tau, 4)

    def point(t, a):
        # A rounded rectangle in section, narrowing and wearing toward the top.
        y = -40 + t * (h + 40)
        k = 1.0 - 0.22 * t ** 1.5
        ca, sa = math.cos(a), math.sin(a)
        sq = 4.0
        sx = np.sign(ca) * abs(ca) ** (2 / sq)
        sz = np.sign(sa) * abs(sa) ** (2 / sq)
        bump = 1.0 + 0.05 * math.sin(a * 3 + ph[0] + t * 5) + 0.04 * math.sin(t * 9 + ph[1])
        top = 1.0 - 0.6 * max(0.0, t - 0.85) / 0.15
        return np.array([sx * w * 0.5 * k * bump * top + lean * y, y,
                         sz * dpt * 0.5 * k * bump * top])

    grid = [[point(i / rows, j / cols * math.tau) for j in range(cols + 1)]
            for i in range(rows + 1)]
    for i in range(rows):
        for j in range(cols):
            q = [grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]]
            uvq = [(j / cols, 1 - i / rows), ((j + 1) / cols, 1 - i / rows),
                   ((j + 1) / cols, 1 - (i + 1) / rows), (j / cols, 1 - (i + 1) / rows)]
            for k in (0, 1, 2, 0, 2, 3):
                tris.append((q[k], uvq[k], i / rows))
    # The cap.
    top = point(1.0, 0.0) * np.array([0, 1, 0]) + np.array([lean * h, 0, 0])
    for j in range(cols):
        for q, uv in ((grid[rows][j], (j / cols, 0.0)), (grid[rows][j + 1], ((j + 1) / cols, 0.0)),
                      (top, (0.5, 0.05))):
            tris.append((q, uv, 1.0))
    P = np.array([t[0] for t in tris])
    UV = np.array([t[1] for t in tris])
    hgt = np.array([t[2] for t in tris])
    F = P.reshape(-1, 3, 3)
    fn = np.cross(F[:, 1] - F[:, 0], F[:, 2] - F[:, 0])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    N = np.repeat(fn, 3, axis=0)
    ctr = np.stack([P[:, 1] * lean, P[:, 1], np.zeros(len(P))], 1)
    out = P - ctr
    N = np.where(np.sum(N * out, axis=1, keepdims=True) < 0, -N, N)
    n = len(P)
    col = np.ones((n, 4))
    col[:, :3] = 0.62
    col[:, 3] = np.clip(0.5 + 0.5 * (P[:, 1] + 10) / 120.0, 0.5, 1.0)
    ex = np.zeros((n, 4))
    ex[:, 2] = M.KIND_ATLAS * 4
    v = M.verts(P, N, col, UV, ex)
    # Mossy at the foot: the lower vertices take the mossy stone.
    low = hgt < 0.22
    stone = cell_uv(v, "stone")
    moss = cell_uv(v, "moss_stone")
    stone["uv"][low] = moss["uv"][low]
    return stone, h


# ---------------------------------------------------------------------------
# Patches
# ---------------------------------------------------------------------------

def scatter(rng, n, radius):
    """`n` points over a disc of `radius`, none too close together."""
    pts = []
    tries = 0
    while len(pts) < n and tries < n * 40:
        tries += 1
        a = rng.random() * math.tau
        r = radius * math.sqrt(rng.random())
        p = np.array([math.cos(a) * r, 0.0, math.sin(a) * r])
        if all(np.linalg.norm(p - q) > radius * 0.28 for q in pts):
            pts.append(p)
    return pts


def patch(kind, seed):
    """One patch of ground cover (about 500 across), by kind."""
    rng = np.random.default_rng(seed)
    parts = []
    R = 230.0
    if kind == "ferns":
        for p in scatter(rng, int(rng.integers(4, 7)), R):
            parts.append(fern_clump(rng, p, rng.random() < 0.55))
        for p in scatter(rng, 2, R):
            parts.append(blob(rng, p, rng.uniform(16, 30), 0.65, 1.0,
                              "moss_stone" if rng.random() < 0.6 else "stone"))
        for p in scatter(rng, 3, R):
            parts.append(crossed(rng, p, "grass%d" % rng.integers(0, 2), 45, 50))
    elif kind == "rocks":
        for p in scatter(rng, int(rng.integers(3, 5)), R):
            parts.append(blob(rng, p, rng.uniform(18, 46), 0.6, 1.2,
                              "moss_stone" if rng.random() < 0.5 else "stone"))
        for p in scatter(rng, 4, R):
            parts.append(crossed(rng, p, "grass%d" % rng.integers(0, 2), 50, 56))
        for p in scatter(rng, 2, R):
            parts.append(crossed(rng, p, "heather", 36, 60, 2))
    elif kind == "bones":
        c = np.array([0.0, 0.0, 0.0])
        parts.append(skull_on_ground(rng, c))
        for p in scatter(rng, 4, 110):
            parts.append(bone_on_ground(rng, p, rng.uniform(26, 44), rng.uniform(2.0, 3.0)))
        for p in scatter(rng, 3, R):
            parts.append(crossed(rng, p, "grass%d" % rng.integers(0, 2), 50, 56))
        parts.append(fern_clump(rng, np.array([120.0, 0, -90.0]), True))
    elif kind == "log":
        parts.append(log(rng, np.array([0.0, 0.0, 0.0]), rng.uniform(280, 440),
                         rng.uniform(18, 28)))
        for p in scatter(rng, 3, R):
            parts.append(fern_clump(rng, p, rng.random() < 0.5))
        for p in scatter(rng, 2, R):
            parts.append(crossed(rng, p, "heather", 34, 60, 2))
    elif kind == "stump":
        parts.append(stump(rng, np.array([0.0, 0.0, 0.0]), rng.uniform(28, 44),
                           rng.uniform(60, 140)))
        for p in scatter(rng, 3, R):
            parts.append(fern_clump(rng, p, rng.random() < 0.6))
        for p in scatter(rng, 3, R):
            parts.append(crossed(rng, p, "grass%d" % rng.integers(0, 2), 50, 56))
    elif kind == "heather":
        for p in scatter(rng, 6, R):
            parts.append(crossed(rng, p, "heather" if rng.random() < 0.6 else "heather1",
                                 rng.uniform(30, 44), 64, 2))
        for p in scatter(rng, 3, R):
            parts.append(crossed(rng, p, "grass%d" % rng.integers(0, 2), 46, 52))
        for p in scatter(rng, 1, R):
            parts.append(blob(rng, p, rng.uniform(16, 26), 0.6, 1.0, "moss_stone"))
    v = np.concatenate(parts)
    rad = float(np.sqrt(v["pos"][:, 0] ** 2 + v["pos"][:, 2] ** 2).max())
    return v, rad


PATCHES = [("ferns", 11), ("ferns", 12), ("rocks", 21), ("bones", 31),
           ("bones", 32), ("log", 41), ("stump", 51), ("heather", 61),
           ("ferns", 13), ("rocks", 22)]


def build_all():
    out = []
    for kind, seed in PATCHES:
        v, rad = patch(kind, seed)
        out.append((kind, seed, v, rad))
    stones = []
    for k in range(3):
        v, h = standing_stone(np.random.default_rng(71 + k))
        stones.append((v, h))
    return out, stones
