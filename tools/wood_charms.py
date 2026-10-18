#!/usr/bin/env python3
"""The witch charms that hang in the wood's trees (`tools/make_wood.py`
writes them out), after the owner's Velka commission and the grove's
sprites: a horned skull under crossed bones with a triple spiral on its
brow, bones bound in tiers like a ladder, an iron ring with a spiral worked
across it, a cage lantern, an arrowhead of bone with a rune, a leather
pouch, a star of bones, a string of vertebrae, and a stick figure.

Each charm hangs from its cord, a dark rope with knots in it: its origin is
where the cord is tied under the limb, and it hangs down -y, facing -z
(toward the camera flying up +z). The wood winds a turn of rope round the
limb there (`rope_wrap`). Parts are textured from the charm sheet
(`wood_tex.charm_sheet`): bone, old wood, cord and iron, one quadrant each.
The parts that glow (a skull's sockets and its spiral, a carved rune, a
lantern's light) are `KIND_GLOW` vertices, drawn as their own light; the
wood also puts a point light there (`glow` in the table).

Charms are triangle lists rather than strips (a marching-cubes skull is a
soup of triangles).
"""
import math

import numpy as np
from skimage import measure

import wood_mesh as M

# The charm sheet's quadrants, as texture rectangles (u0, v0, u1, v1).
BONE = (0.0, 0.0, 0.5, 0.5)
WOOD = (0.5, 0.0, 1.0, 0.5)
CORD = (0.0, 0.5, 0.5, 1.0)
IRON = (0.5, 0.5, 1.0, 1.0)

GLOW_TINT = (1.0, 1.0, 1.0)


def strip_to_list(v):
    """A strip's triangles as a list, dropping the joins (triangles with two
    of the same vertex). A vertex is its position and its texture
    coordinates together: a ribbon's two edges share a position until the
    shader spreads them apart, and only their side tells them apart."""
    if len(v) < 3:
        return v[:0]
    key = np.concatenate([v["pos"], v["uv"]], axis=1)
    idx = []
    for i in range(len(v) - 2):
        a, b, c = i, i + 1, i + 2
        if (np.allclose(key[a], key[b]) or np.allclose(key[b], key[c])
                or np.allclose(key[a], key[c])):
            continue
        idx.extend((a, b, c))
    return v[np.array(idx, int)]


def remap_uv(v, rect, scale=1.0):
    """Squeeze a part's texture coordinates (taken as 0..1, repeating) into
    a quadrant of the sheet, wrapped so they stay inside it."""
    u0, v0, u1, v1 = rect
    out = v.copy()
    uu = np.mod(v["uv"][:, 0] * scale, 1.0)
    vv = np.mod(v["uv"][:, 1] * scale, 1.0)
    pad = 0.02
    out["uv"][:, 0] = u0 + (u1 - u0) * (pad + (1 - 2 * pad) * uu)
    out["uv"][:, 1] = v0 + (v1 - v0) * (pad + (1 - 2 * pad) * vv)
    return out


class Charm:
    def __init__(self):
        self.parts = []
        self.glow = None      # where its light is, in its own space

    def add(self, v):
        if v is not None and len(v):
            self.parts.append(v)

    def build(self):
        return np.concatenate(self.parts) if self.parts else np.zeros(0, M.VERTEX)


def tube_part(pts, radii, sides, rect, tint=(1, 1, 1), kind=M.KIND_SOLID,
              ao=1.0, sway=0.0, uscale=1.0):
    """A tube as triangles, textured from a quadrant. A part is kept within
    its quadrant by wrapping per vertex, so a tube's u runs 0..1 once round
    and its v by length."""
    P = np.asarray(pts, float)
    R = np.asarray(radii, float)
    # Once round and once along, so nothing wraps inside the quadrant.
    length = float(M.arclen(P)[-1])
    v = M.tube(P, R, sides, np.asarray(tint, float), ao=np.full(len(P), ao),
               u_tile=2 * math.pi * max(R.max(), 0.1),
               v_tile=max(length * 1.02, 1.0),
               sway=np.full(len(P), sway), kind=kind)
    v = strip_to_list(v)
    # Seam: the wrap would smear across the last column; keep u < 1.
    v["uv"][:, 0] = np.clip(v["uv"][:, 0], 0, 0.999)
    return remap_uv(v, rect)


ROPE = (0.16, 0.13, 0.11)
ROPE_KNOT = (0.26, 0.21, 0.17)


def cord(length, r=1.1, tint=ROPE, kinks=0.0, rng=None, top=(0.0, 0.0, 0.0)):
    """The rope a charm hangs by, from its tie (`top`, the origin unless
    given) down `length`: dark, thick enough to read against the fog, with a
    knot or two along it."""
    n = max(3, int(length / 8))
    pts = np.zeros((n, 3))
    pts[:, 1] = -np.linspace(0, length, n)
    pts += np.asarray(top, float)
    if rng is not None and kinks:
        pts[1:-1, 0] += rng.normal(0, kinks, n - 2)
        pts[1:-1, 2] += rng.normal(0, kinks, n - 2)
    parts = [strip_to_list(M.ribbon(pts, np.full(n, r), np.asarray(tint, float),
                                    ao=1.0, sway=np.zeros(n)))]
    if rng is not None and length > 30:
        for f in rng.uniform(0.3, 0.8, 1 if length < 60 else 2):
            parts.append(sphere_part(pts[0] + (0, -length * f, 0), r * 1.9,
                                     CORD, ROPE_KNOT, n=6, sy=0.8))
    return np.concatenate(parts)


def sphere_part(c, r, rect, tint=(1, 1, 1), kind=M.KIND_SOLID, n=10, sy=1.0):
    """A small sphere (a bead, a knot, a skull's eye-light)."""
    c = np.asarray(c, float)
    pts = [c + np.array([0, -r * sy, 0]) * (1 - 2 * t) for t in np.linspace(0, 1, n)]
    t = np.linspace(0, 1, n)
    radii = r * np.sin(np.pi * np.clip(t, 0.001, 0.999)) ** 0.9
    return tube_part(np.array(pts)[::-1] * 1.0, radii[::-1], n, rect, tint, kind)


# ---------------------------------------------------------------------------
# Signed distance helpers for the skull
# ---------------------------------------------------------------------------

def sd_ellipsoid(p, c, r):
    q = (p - c) / r
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def sd_capsule(p, a, b, ra, rb):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    pa = p - a
    ba = b - a
    h = np.clip(np.sum(pa * ba, axis=-1) / np.dot(ba, ba), 0, 1)
    r = ra + (rb - ra) * h
    return np.linalg.norm(pa - ba * h[..., None], axis=-1) - r


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def skull_sdf(p):
    """An animal skull, about 46 long, horned like a goat: the brain case,
    the long face, sockets, the nasal opening, and two horns sweeping up and
    back."""
    d = sd_ellipsoid(p, np.array([0.0, 2.0, 0.0]), np.array([9.0, 8.5, 10.0]))
    snout = sd_capsule(p, (0, -1.0, -6.0), (0, -6.0, -24.0), 6.2, 3.0)
    d = smin(d, snout, 4.0)
    # Cheekbones.
    for s in (-1, 1):
        cheek = sd_capsule(p, (s * 7.5, -1.0, -3.0), (s * 4.0, -3.5, -14.0), 2.2, 1.6)
        d = smin(d, cheek, 2.0)
    # The sockets, the nasal opening, a dip between the eyes.
    for s in (-1, 1):
        eye = sd_ellipsoid(p, np.array([s * 6.4, 1.5, -6.5]), np.array([3.6, 3.4, 3.6]))
        d = smax(d, -eye, 1.0)
    nose = sd_ellipsoid(p, np.array([0.0, -4.5, -21.5]), np.array([2.2, 2.6, 4.5]))
    d = smax(d, -nose, 0.8)
    # The horns: segments along a curve, thinning to a point.
    for s in (-1, 1):
        prev = np.array([s * 4.5, 7.5, -1.0])
        r0 = 2.8
        for k in range(1, 9):
            t = k / 8
            ang = t * 1.5
            pt = np.array([s * (4.5 + 9.0 * t + 4.0 * t * t),
                           7.5 + 22.0 * math.sin(ang) * (1.0 - 0.25 * t),
                           -1.0 + 14.0 * t * t])
            r1 = 2.8 * (1.0 - t) + 0.35
            d = smin(d, sd_capsule(p, prev, pt, r0, r1), 0.8)
            prev, r0 = pt, r1
    return d


def skull_mesh(step=1.4):
    lo = np.array([-26.0, -14.0, -32.0])
    hi = np.array([26.0, 34.0, 18.0])
    n = np.ceil((hi - lo) / step).astype(int) + 1
    xs = lo[0] + np.arange(n[0]) * step
    ys = lo[1] + np.arange(n[1]) * step
    zs = lo[2] + np.arange(n[2]) * step
    G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1)
    vol = skull_sdf(G)
    verts, faces, normals, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step),
                                                       gradient_direction="ascent")
    verts = verts + lo
    normals = -normals
    tri = verts[faces].reshape(-1, 3)
    nrm = normals[faces].reshape(-1, 3)
    # Bone: a projection along the face (x, y), so the texture's stains
    # run over it; the sockets darker by how far into them a point is.
    uv = np.stack([(tri[:, 0] + 26) / 52.0, (tri[:, 1] + 14) / 48.0], axis=1)
    ao = np.clip(0.55 + 0.45 * np.clip(-skull_sdf(tri + nrm * 3.0) / 3.0, -1, 1) * -1, 0.35, 1.0)
    ao = np.clip(1.0 - np.clip(-skull_sdf(tri + nrm * 2.5), 0, 3) / 3.0 * 0.6, 0.35, 1.0)
    n = len(tri)
    col = np.ones((n, 4))
    col[:, :3] = (0.92, 0.88, 0.80)
    col[:, 3] = ao
    ex = np.zeros((n, 4))
    ex[:, 2] = M.KIND_SOLID * 4
    v = M.verts(tri, nrm, col, uv, ex)
    return remap_uv(v, BONE)


def eye_lights():
    out = []
    for s in (-1, 1):
        out.append(sphere_part((s * 6.0, 1.4, -6.8), 2.1, BONE, GLOW_TINT,
                               kind=M.KIND_GLOW, n=8))
    return np.concatenate(out)


def flat_strip(path, width, z_off, normal, kind=M.KIND_GLOW, tint=GLOW_TINT):
    """A flat band of `width` along a polyline in the plane facing `normal`
    (a carved or painted line), as triangles."""
    P = np.asarray(path, float)
    n = len(P)
    nrm = np.asarray(normal, float)
    nrm = nrm / np.linalg.norm(nrm)
    tris = []
    for i in range(n - 1):
        d = P[i + 1] - P[i]
        side = np.cross(nrm, d)
        side = side / max(np.linalg.norm(side), 1e-9) * width * 0.5
        a0, a1 = P[i] - side, P[i] + side
        b0, b1 = P[i + 1] - side, P[i + 1] + side
        tris.extend([a0, a1, b1, a0, b1, b0])
    tris = np.array(tris) + nrm * z_off
    k = len(tris)
    col = np.ones((k, 4))
    col[:, :3] = tint
    ex = np.zeros((k, 4))
    ex[:, 2] = kind * 4
    v = M.verts(tris, np.tile(nrm, (k, 1)), col, np.full((k, 2), 0.5), ex)
    return remap_uv(v, BONE)


def triskelion(centre, size, normal, up):
    """Three spiral arms turning out of one centre (the Celtic triple
    spiral), in the plane facing `normal`, as a glowing painted line."""
    c = np.asarray(centre, float)
    nrm = np.asarray(normal, float) / np.linalg.norm(normal)
    u = np.asarray(up, float)
    u = u - np.dot(u, nrm) * nrm
    u /= np.linalg.norm(u)
    r = np.cross(nrm, u)
    out = []
    for k in range(3):
        a0 = k * math.tau / 3
        pts = []
        for t in np.linspace(0.0, 1.0, 26):
            # Out from the centre, then curling back on itself at the end.
            rad = size * (0.15 + 0.85 * math.sin(t * math.pi * 0.62))
            ang = a0 + t * 4.2
            pts.append(c + (math.cos(ang) * r + math.sin(ang) * u) * rad)
        out.append(flat_strip(pts, size * 0.16, 0.3, nrm))
    return np.concatenate(out)


def skull_surface(p0, d):
    """Where a ray from `p0` along `d` first meets the skull, and the
    surface's normal there."""
    d = np.asarray(d, float) / np.linalg.norm(d)
    p = np.asarray(p0, float)
    for _ in range(200):
        s = float(skull_sdf(p[None, :])[0])
        if s < 0.05:
            break
        p = p + d * max(s * 0.8, 0.05)
    e = 0.05
    g = np.array([float(skull_sdf((p + np.array(o))[None, :])[0]
                        - skull_sdf((p - np.array(o))[None, :])[0])
                  for o in ((e, 0, 0), (0, e, 0), (0, 0, e))])
    return p, g / max(np.linalg.norm(g), 1e-9)


# ---------------------------------------------------------------------------
# The charms
# ---------------------------------------------------------------------------

def charm_skull(rng):
    """A horned skull hung under two crossed bones, a triple spiral painted
    on its brow, its sockets lit."""
    c = Charm()
    drop = rng.uniform(26, 40)
    c.add(cord(drop, rng=rng, kinks=0.5))
    # Two bones crossed and bound where the cord comes down.
    y = -drop
    for s in (-1, 1):
        a = np.array([-16.0 * s, y + 9.0, -1.0])
        b = np.array([16.0 * s, y - 9.0, 1.0])
        c.add(bone(a, b, 1.9))
    c.add(sphere_part((0, y, -0.5), 3.2, CORD, ROPE_KNOT))
    c.add(cord(14, rng=rng, top=(0, y - 2, 0)))
    for s in (-1, 1):
        c.add(strip_to_list(M.ribbon(np.array([[0, y - 14, 0],
                                               [s * 10, y - 26, 4]]),
                                     np.array([0.9, 0.9]), np.array(ROPE))))
    sk = skull_mesh()
    rot = M.rot_axis(np.array([1.0, 0.0, 0.0]), math.radians(-12))
    off = np.array([0.0, y - 40.0, 0.0])
    sc = 1.35
    c.add(M.transform(sk, rot, off, sc))
    c.add(M.transform(eye_lights(), rot, off, sc))
    # The spiral on its brow.
    p, nrm = skull_surface((0.0, 7.5, -30.0), (0.0, -0.05, 1.0))
    tri = triskelion(p, 4.2, nrm, (0.0, 1.0, 0.0))
    c.add(M.transform(tri, rot, off, sc))
    c.glow = (0.0, y - 38.0, -12.0)
    return c


def bone(a, b, r, tint=(0.90, 0.86, 0.78)):
    """A long bone: a shaft with knobbed ends."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    t = np.linspace(0, 1, 9)
    pts = a[None, :] + (b - a)[None, :] * t[:, None]
    radii = r * (0.62 + 0.55 * (np.exp(-(t / 0.10) ** 2) + np.exp(-((1 - t) / 0.10) ** 2)))
    radii[0] *= 0.6
    radii[-1] *= 0.6
    return tube_part(pts, radii, 7, BONE, tint)


def charm_bones(rng):
    """A star of six bones bound at the middle, a light in the knot."""
    c = Charm()
    drop = rng.uniform(30, 50)
    c.add(cord(drop, rng=rng, kinks=0.5))
    ctr = np.array([0.0, -drop - 22.0, 0.0])
    n = 6
    for k in range(n):
        a = k * math.tau / n + rng.normal(0, 0.12)
        d = np.array([math.cos(a), math.sin(a), rng.normal(0, 0.1)])
        c.add(bone(ctr + d * 3, ctr + d * rng.uniform(18, 24), rng.uniform(1.6, 2.1)))
    c.add(sphere_part(ctr + (0, 0, -1.5), 4.2, CORD, ROPE_KNOT))
    c.add(sphere_part(ctr + (0, 0, -4.8), 2.2, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = tuple(ctr + (0, 0, -6.0))
    return c


def charm_ladder(rng):
    """Bones bound across a cord in tiers, like rungs, two small bones
    dangling from the lowest."""
    c = Charm()
    drop = rng.uniform(24, 36)
    tiers = 3
    gap = 22.0
    c.add(cord(drop + gap * (tiers - 1) + 6, rng=rng, kinks=0.3))
    for k in range(tiers):
        y = -drop - k * gap
        ln = rng.uniform(15, 19) * (1.0 - 0.08 * k)
        tw = rng.normal(0, 0.12)
        a = np.array([-ln * math.cos(tw), y + ln * math.sin(tw) * 0.3, -ln * math.sin(tw)])
        b = -a + np.array([0, 2 * y, 0])
        c.add(bone(a, b, rng.uniform(1.7, 2.1)))
        c.add(sphere_part((0, y, -0.4), 2.6, CORD, ROPE_KNOT))
    y = -drop - (tiers - 1) * gap
    for s in (-1, 1):
        top = np.array([s * 13.0, y, 0.0])
        ln = rng.uniform(8, 14)
        c.add(strip_to_list(M.ribbon(np.array([top, top + (0, -ln, 0)]),
                                     np.array([0.6, 0.6]), np.array(ROPE))))
        c.add(bone(top + (0, -ln, 0), top + (s * 2, -ln - 13, 0), 1.2))
    c.add(sphere_part((0, y - 9, -1.0), 2.0, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (0.0, y - 9.0, -3.0)
    return c


def charm_ring(rng):
    """A hand-forged iron ring hung from a bone bar, a spiral rune worked
    across it that glows, and a hook hanging under it."""
    c = Charm()
    drop = rng.uniform(26, 40)
    c.add(cord(drop, rng=rng, kinks=0.4))
    y = -drop
    c.add(bone((-14.0, y, 0.0), (14.0, y + 1.0, 0.0), 1.8))
    c.add(sphere_part((0, y, -0.4), 2.6, CORD, ROPE_KNOT))
    R = 17.0
    ctr = np.array([0.0, y - 6.0 - R, 0.0])
    for s in (-1, 1):
        c.add(strip_to_list(M.ribbon(np.array([[s * 9.0, y, 0.0],
                                               [s * 4.0, ctr[1] + R - 1.0, 0.0]]),
                                     np.array([0.7, 0.7]), np.array(ROPE))))
    th = np.linspace(0, math.tau, 33)
    wob = 1.0 + 0.03 * np.sin(th * 3.0 + rng.random() * 6)
    ring = ctr[None, :] + np.stack([np.cos(th) * R * wob, np.sin(th) * R * wob,
                                    np.zeros_like(th)], 1)
    c.add(tube_part(ring, np.full(len(th), 1.7), 6, IRON, (0.55, 0.53, 0.52)))
    # The spiral across it, an S-curl as on the old charms.
    sp = []
    for t in np.linspace(-1.0, 1.0, 40):
        a = t * 3.6
        rr = R * 0.62 * abs(t) ** 0.8
        sgn = 1.0 if t >= 0 else -1.0
        sp.append(ctr + np.array([math.cos(a) * rr * sgn, math.sin(a) * rr * sgn, 0.0]))
    c.add(flat_strip(sp, 1.7, 0.6, (0.0, 0.0, -1.0)))
    # The hook below.
    hook = np.array([[0, ctr[1] - R, 0], [0, ctr[1] - R - 7, 0], [2, ctr[1] - R - 11, 0],
                     [4.5, ctr[1] - R - 9, 0]])
    c.add(tube_part(hook, np.array([0.9, 0.8, 0.7, 0.4]), 4, IRON, (0.5, 0.48, 0.47)))
    c.glow = tuple(ctr + (0, 0, -3.0))
    return c


def charm_lantern(rng):
    """An iron cage lantern: bars bowed between a cap and a foot; the
    witch-light inside."""
    c = Charm()
    drop = rng.uniform(25, 40)
    c.add(cord(drop, rng=rng))
    top = -drop
    h = 34.0
    ctr = np.array([0.0, top - h * 0.55, 0.0])
    n = 6
    rmax = 11.0
    for k in range(n):
        a = k * math.tau / n
        t = np.linspace(0, 1, 9)
        rr = 3.5 + (rmax - 3.5) * np.sin(np.pi * t) ** 0.8
        pts = np.stack([np.cos(a) * rr, top - 6 - t * h, np.sin(a) * rr], 1)
        c.add(tube_part(pts, np.full(9, 0.9), 4, IRON, (0.55, 0.52, 0.5)))
    cap = np.array([[0, top, 0], [0, top - 3, 0], [0, top - 7, 0]])
    c.add(tube_part(cap, np.array([1.5, 4.5, 4.0]), 8, IRON, (0.5, 0.48, 0.46)))
    foot = np.array([[0, top - 6 - h + 1, 0], [0, top - 6 - h - 2, 0], [0, top - 6 - h - 6, 0]])
    c.add(tube_part(foot, np.array([4.2, 3.0, 0.5]), 8, IRON, (0.5, 0.48, 0.46)))
    c.add(sphere_part(ctr, 6.5, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = tuple(ctr)
    return c


def charm_plaque(rng):
    """An arrowhead of pale bone hung point down, a rune cut in its face
    that glows."""
    c = Charm()
    drop = rng.uniform(28, 44)
    c.add(cord(drop, rng=rng, kinks=0.3))
    th = 2.4
    y0 = -drop - 2.0
    outline = np.array([[-9.0, y0], [9.0, y0], [13.0, y0 - 12.0],
                        [0.0, y0 - 40.0], [-13.0, y0 - 12.0]])
    w, hgt = 26.0, 40.0
    tris = []
    for z, nz in ((-th, -1.0), (th, 1.0)):
        for i in range(1, len(outline) - 1):
            for q in (outline[0], outline[i], outline[i + 1]):
                tris.append((q[0], q[1], z, 0, 0, nz))
    m = len(outline)
    for i in range(m):
        a, b = outline[i], outline[(i + 1) % m]
        e = b - a
        nn = np.array([e[1], -e[0], 0.0])
        nn /= np.linalg.norm(nn)
        for q, z in ((a, -th), (b, -th), (b, th), (a, -th), (b, th), (a, th)):
            tris.append((q[0], q[1], z, nn[0], nn[1], nn[2]))
    tris = np.array(tris)
    n = len(tris)
    uv = np.stack([(tris[:, 0] + w / 2) / w, (y0 - tris[:, 1]) / hgt], 1)
    col = np.ones((n, 4))
    col[:, :3] = (0.92, 0.88, 0.78)
    ex = np.zeros((n, 4))
    ex[:, 2] = M.KIND_SOLID * 4
    c.add(remap_uv(M.verts(tris[:, :3], tris[:, 3:], col, uv, ex), BONE))
    # The rune: a stem with a crossbar and two branches up.
    strokes = [[(0, y0 - 7), (0, y0 - 31)], [(-6, y0 - 12), (6, y0 - 12)],
               [(0, y0 - 18), (-6.5, y0 - 10)], [(0, y0 - 18), (6.5, y0 - 10)]]
    for st in strokes:
        pts = [(x, yy, 0.0) for x, yy in st]
        c.add(flat_strip(pts, 1.8, th + 0.3, (0.0, 0.0, -1.0)))
    c.glow = (0.0, y0 - 16, -8.0)
    return c


def charm_pouch(rng):
    """A dark leather pouch cinched at the neck, a pale stone tied on."""
    c = Charm()
    drop = rng.uniform(30, 46)
    c.add(cord(drop + 4, rng=rng, kinks=0.4))
    y = -drop
    prof = [(0.5, 0.0), (2.6, -1.5), (4.0, -3.0), (2.8, -4.5), (3.4, -6.5),
            (7.5, -10.0), (10.0, -15.0), (10.6, -20.0), (9.4, -25.0),
            (6.0, -28.5), (0.4, -30.0)]
    pts = np.array([[0.0, y + yy, 0.0] for _, yy in prof])
    radii = np.array([r for r, _ in prof])
    v = tube_part(pts, radii, 10, CORD, (0.42, 0.30, 0.24))
    # Lumps: push each vertex out a little by a pattern round it.
    p = v["pos"]
    ang = np.arctan2(p[:, 2], p[:, 0])
    k = 1.0 + 0.10 * np.sin(ang * 3 + p[:, 1] * 0.4) * np.clip((-(p[:, 1] - y) - 8) / 10, 0, 1)
    v["pos"][:, 0] *= k
    v["pos"][:, 2] *= k
    c.add(v)
    c.add(sphere_part((0.0, y - 4.0, 0.0), 3.6, CORD, ROPE_KNOT, sy=0.6))
    # A stone on a short tie at the neck, glowing.
    c.add(strip_to_list(M.ribbon(np.array([[3.0, y - 4.0, -2.0], [7.0, y - 14.0, -4.0]]),
                                 np.array([0.5, 0.5]), np.array(ROPE))))
    c.add(sphere_part((7.5, y - 16.0, -4.5), 2.4, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (7.5, y - 16.0, -7.0)
    return c


def charm_spine(rng):
    """Vertebrae strung on a cord, each with its wings of bone."""
    c = Charm()
    drop = rng.uniform(15, 30)
    n = 6
    length = drop + n * 11
    c.add(cord(length, rng=rng))
    for k in range(n):
        y = -drop - k * 11
        s = 1.0 - k * 0.07
        c.add(sphere_part((0, y, 0), 4.6 * s, BONE, (0.88, 0.84, 0.76), sy=0.55))
        wing = np.array([[-9 * s, y + 1, 0], [0, y, 0], [9 * s, y + 1, 0]])
        c.add(tube_part(wing, np.array([0.6, 1.8, 0.6]), 5, BONE, (0.86, 0.82, 0.74)))
        spike = np.array([[0, y, 0], [0, y + 1, 5 * s]])
        c.add(tube_part(spike, np.array([1.4, 0.3]), 4, BONE, (0.86, 0.82, 0.74)))
    c.add(sphere_part((0, -drop - n * 11 + 2, 0), 2.8, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (0.0, -drop - n * 11, -3.0)
    return c


def charm_effigy(rng):
    """A stick figure of twigs bound with cord: a body, arms, legs, a head
    of a knot, hung by its neck."""
    c = Charm()
    drop = rng.uniform(25, 40)
    c.add(cord(drop, rng=rng))
    y = -drop
    tint = (0.55, 0.46, 0.38)
    body = np.array([[0, y - 4, 0], [0.5, y - 22, 0], [0, y - 40, 0]])
    c.add(tube_part(body, np.array([1.8, 1.6, 1.4]), 5, WOOD, tint))
    arms = np.array([[-18, y - 10, 0], [0, y - 13, 0], [17, y - 9, 0]])
    c.add(tube_part(arms, np.array([1.1, 1.4, 1.0]), 5, WOOD, tint))
    for s in (-1, 1):
        leg = np.array([[0, y - 38, 0], [s * 8, y - 52, 0], [s * 10, y - 62, 0]])
        c.add(tube_part(leg, np.array([1.3, 1.1, 0.8]), 5, WOOD, tint))
    c.add(sphere_part((0, y - 3, 0), 4.2, CORD, ROPE_KNOT))
    for yy in (y - 13, y - 38):
        c.add(sphere_part((0, yy, 0), 2.3, CORD, ROPE_KNOT))
    c.add(sphere_part((0, y - 3, -3.5), 1.6, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (0.0, y - 4, -6.0)
    return c


def rope_wrap(seed=3):
    """Rope wound round a limb where a charm is tied: three turns round the
    local x axis (the limb's direction), of radius a little over 1, so the
    wood scales it by the limb's own radius."""
    rng = np.random.default_rng(seed)
    n = 110
    t = np.linspace(0.0, 1.0, n)
    ang = t * 3.0 * math.tau + math.pi * 0.5
    x = -1.0 + 2.0 * t
    rr = 1.12 + 0.03 * rng.normal(size=n)
    pts = np.stack([x, np.cos(ang) * rr, np.sin(ang) * rr], 1)
    return tube_part(pts, np.full(n, 0.20), 6, CORD, np.array(ROPE) * 1.5)


CHARMS = [
    ("skull", charm_skull), ("ladder", charm_ladder), ("ring", charm_ring),
    ("lantern", charm_lantern), ("plaque", charm_plaque),
    ("pouch", charm_pouch), ("bones", charm_bones), ("spine", charm_spine),
    ("effigy", charm_effigy),
]


def build_all(seed=7):
    out = []
    for i, (name, fn) in enumerate(CHARMS):
        rng = np.random.default_rng(seed + i * 31)
        c = fn(rng)
        v = c.build()
        lo = v["pos"].min(axis=0)
        out.append((name, v, c.glow, float(-lo[1])))
    return out
