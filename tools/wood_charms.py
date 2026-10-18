#!/usr/bin/env python3
"""The witch charms that hang in the wood's trees (`tools/make_wood.py`
writes them out), modelled after the grove's sprites: a horned skull, a star
of bones, a ring strung like a web, a lantern, a rune plaque, a mobile of
blades, a string of vertebrae, and a stick figure.

Each charm hangs from its cord: its origin is where the cord is tied to the
branch, and it hangs down -y, facing -z (toward the camera flying up +z).
Parts are textured from the charm sheet (`wood_tex.charm_sheet`): bone, old
wood, cord and iron, one quadrant each. The parts that glow (a skull's eyes,
a carved rune, a lantern's light) are `KIND_GLOW` vertices, drawn as their
own light; the wood also puts a point light there (`glow` in the table).

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
    corners in one place)."""
    if len(v) < 3:
        return v[:0]
    idx = []
    p = v["pos"]
    for i in range(len(v) - 2):
        a, b, c = i, i + 1, i + 2
        if (np.allclose(p[a], p[b]) or np.allclose(p[b], p[c])
                or np.allclose(p[a], p[c])):
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


def cord(length, r=0.55, tint=(0.30, 0.26, 0.22), kinks=0.0, rng=None):
    """The cord a charm hangs by, from its tie (the origin) down."""
    n = max(3, int(length / 8))
    pts = np.zeros((n, 3))
    pts[:, 1] = -np.linspace(0, length, n)
    if rng is not None and kinks:
        pts[1:-1, 0] += rng.normal(0, kinks, n - 2)
        pts[1:-1, 2] += rng.normal(0, kinks, n - 2)
    v = M.ribbon(pts, np.full(n, r), np.asarray(tint, float), ao=1.0,
                 sway=np.linspace(0, 0.0, n))
    return strip_to_list(v)


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


# ---------------------------------------------------------------------------
# The charms
# ---------------------------------------------------------------------------

def charm_skull(rng):
    c = Charm()
    drop = rng.uniform(40, 70)
    c.add(cord(drop - 8, rng=rng, kinks=0.6))
    # Two short ties to the horn tips.
    for s in (-1, 1):
        c.add(strip_to_list(M.ribbon(np.array([[0, -drop + 8, 0],
                                               [s * 10, -drop - 4, 4]]),
                                     np.array([0.5, 0.5]),
                                     np.array([0.30, 0.26, 0.22]))))
    sk = skull_mesh()
    # Hung by the horns: the skull below the tie, its face toward -z and
    # tipped a little down.
    rot = M.rot_axis(np.array([1.0, 0.0, 0.0]), math.radians(-12))
    off = np.array([0.0, -drop - 26.0, 0.0])
    c.add(M.transform(sk, rot, off, 1.35))
    c.add(M.transform(eye_lights(), rot, off, 1.35))
    c.glow = (0.0, -drop - 24.0, -9.0)
    return c


def bone(a, b, r):
    """A long bone: a shaft with knobbed ends."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    t = np.linspace(0, 1, 9)
    pts = a[None, :] + (b - a)[None, :] * t[:, None]
    radii = r * (0.62 + 0.55 * (np.exp(-(t / 0.10) ** 2) + np.exp(-((1 - t) / 0.10) ** 2)))
    radii[0] *= 0.6
    radii[-1] *= 0.6
    return tube_part(pts, radii, 7, BONE, (0.90, 0.86, 0.78))


def charm_bones(rng):
    c = Charm()
    drop = rng.uniform(35, 60)
    c.add(cord(drop, rng=rng, kinks=0.5))
    ctr = np.array([0.0, -drop - 26.0, 0.0])
    n = 6
    for k in range(n):
        a = k * math.tau / n + rng.normal(0, 0.12)
        d = np.array([math.cos(a), math.sin(a), rng.normal(0, 0.1)])
        c.add(bone(ctr + d * 3, ctr + d * rng.uniform(22, 30), rng.uniform(1.8, 2.4)))
    # The binding knot, and a glowing bead in it.
    c.add(sphere_part(ctr + (0, 0, -1.5), 4.2, CORD, (0.45, 0.36, 0.30)))
    c.add(sphere_part(ctr + (0, 0, -4.8), 2.2, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = tuple(ctr + (0, 0, -6.0))
    return c


def charm_ring(rng):
    """A bent-willow ring strung with a web, cords hanging from it with
    beads, a light at its heart."""
    c = Charm()
    drop = rng.uniform(30, 55)
    c.add(cord(drop, rng=rng, kinks=0.4))
    R = 22.0
    ctr = np.array([0.0, -drop - R, 0.0])
    th = np.linspace(0, math.tau, 25)
    ring = ctr[None, :] + np.stack([np.cos(th) * R, np.sin(th) * R, np.zeros_like(th)], 1)
    c.add(tube_part(ring, np.full(len(th), 1.9), 6, WOOD, (0.62, 0.52, 0.42)))
    # The web: spokes and a spiral of thread, as ribbons.
    for k in range(7):
        a = k * math.tau / 7
        p = np.array([ctr, ctr + np.array([math.cos(a) * R, math.sin(a) * R, 0])])
        c.add(strip_to_list(M.ribbon(p, np.array([0.28, 0.28]), np.array([0.7, 0.68, 0.62]))))
    sp = []
    for t in np.linspace(0, 1, 60):
        a = t * math.tau * 3.0
        rr = R * (0.18 + 0.75 * t)
        sp.append(ctr + np.array([math.cos(a) * rr, math.sin(a) * rr, 0]))
    c.add(strip_to_list(M.ribbon(np.array(sp), np.full(60, 0.22), np.array([0.7, 0.68, 0.62]))))
    # Hanging cords with beads and a feather-like blade at the end.
    for k, a in enumerate((-110, -90, -70)):
        a = math.radians(a)
        top = ctr + np.array([math.cos(a) * R, math.sin(a) * R, 0])
        ln = rng.uniform(26, 40)
        p = np.array([top, top + (0, -ln, 0)])
        c.add(strip_to_list(M.ribbon(p, np.array([0.4, 0.4]), np.array([0.3, 0.26, 0.22]))))
        c.add(sphere_part(top + (0, -ln * 0.45, 0), 2.0, BONE, (0.85, 0.8, 0.72)))
        blade = np.array([top + (0, -ln, 0), top + (0, -ln - 12, 0)])
        c.add(tube_part(blade, np.array([2.0, 0.2]), 4, BONE, (0.8, 0.76, 0.7)))
    c.add(sphere_part(ctr + (0, 0, -1.0), 3.4, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = tuple(ctr + (0, 0, -3.0))
    return c


def charm_lantern(rng):
    """An iron cage lantern: a ring at the top and bottom, bars bowed
    between them, a cap and a hook; the witch-light inside."""
    c = Charm()
    drop = rng.uniform(25, 45)
    c.add(cord(drop, r=0.7, rng=rng))
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
    # Cap and foot.
    cap = np.array([[0, top, 0], [0, top - 3, 0], [0, top - 7, 0]])
    c.add(tube_part(cap, np.array([1.5, 4.5, 4.0]), 8, IRON, (0.5, 0.48, 0.46)))
    foot = np.array([[0, top - 6 - h + 1, 0], [0, top - 6 - h - 2, 0], [0, top - 6 - h - 6, 0]])
    c.add(tube_part(foot, np.array([4.2, 3.0, 0.5]), 8, IRON, (0.5, 0.48, 0.46)))
    c.add(sphere_part(ctr, 6.5, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = tuple(ctr)
    return c


def charm_plaque(rng):
    """A pentagon of old wood, a rune cut in its face that glows."""
    c = Charm()
    drop = rng.uniform(30, 55)
    for s in (-1, 1):
        p = np.array([[0, 0, 0], [s * 12, -drop, 0]])
        c.add(strip_to_list(M.ribbon(p, np.array([0.55, 0.55]), np.array([0.3, 0.26, 0.22]))))
    w, hgt, th = 30.0, 42.0, 3.0
    y0 = -drop
    outline = np.array([[-w / 2, y0], [w / 2, y0], [w / 2, y0 - hgt * 0.6],
                        [0, y0 - hgt], [-w / 2, y0 - hgt * 0.6]])
    tris = []
    # Front and back faces as fans, and the edge as quads.
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
    col[:, :3] = (0.62, 0.54, 0.46)
    ex = np.zeros((n, 4))
    ex[:, 2] = M.KIND_SOLID * 4
    c.add(remap_uv(M.verts(tris[:, :3], tris[:, 3:], col, uv, ex), WOOD))
    # The rune: three strokes, just proud of the front face.
    z = -th - 0.4
    strokes = [((0, y0 - 9), (0, y0 - 33)), ((0, y0 - 16), (-8, y0 - 9)),
               ((0, y0 - 22), (8, y0 - 15)), ((0, y0 - 28), (-6, y0 - 22))]
    for (ax, ay), (bx, by) in strokes:
        d = np.array([bx - ax, by - ay])
        d /= np.linalg.norm(d)
        nx = np.array([-d[1], d[0]]) * 1.3
        quad = [(ax - nx[0], ay - nx[1]), (bx - nx[0], by - nx[1]),
                (bx + nx[0], by + nx[1]), (ax + nx[0], ay + nx[1])]
        tri = np.array([[quad[i][0], quad[i][1], z] for i in (0, 1, 2, 0, 2, 3)])
        cc = np.ones((6, 4))
        exx = np.zeros((6, 4))
        exx[:, 2] = M.KIND_GLOW * 4
        c.add(remap_uv(M.verts(tri, np.tile([0, 0, -1.0], (6, 1)), cc,
                               np.full((6, 2), 0.5), exx), BONE))
    c.glow = (0.0, y0 - 20, -8.0)
    return c


def charm_fetish(rng):
    """A crossbar hung with blades of bone on threads."""
    c = Charm()
    drop = rng.uniform(25, 45)
    c.add(cord(drop, rng=rng))
    y = -drop
    bar = np.array([[-26, y + 1.5, 0], [0, y, 0], [26, y + 2, 0]])
    c.add(tube_part(bar, np.array([1.8, 2.0, 1.6]), 6, WOOD, (0.6, 0.5, 0.42)))
    for k, x in enumerate(np.linspace(-22, 22, 5)):
        ln = rng.uniform(10, 22)
        p = np.array([[x, y, 0], [x, y - ln, 0]])
        c.add(strip_to_list(M.ribbon(p, np.array([0.35, 0.35]), np.array([0.3, 0.26, 0.22]))))
        blade = np.array([[x, y - ln, 0], [x, y - ln - 8, 0], [x, y - ln - 20, 0]])
        c.add(tube_part(blade, np.array([0.6, 3.2, 0.3]), 4, BONE, (0.86, 0.82, 0.74)))
    c.add(sphere_part((0, y - 3, -1.5), 2.6, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (0.0, y - 4, -4.0)
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
    drop = rng.uniform(25, 45)
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
    c.add(sphere_part((0, y - 3, 0), 4.2, CORD, (0.45, 0.36, 0.30)))
    for yy in (y - 13, y - 38):
        c.add(sphere_part((0, yy, 0), 2.3, CORD, (0.45, 0.36, 0.30)))
    c.add(sphere_part((0, y - 3, -3.5), 1.6, BONE, GLOW_TINT, kind=M.KIND_GLOW))
    c.glow = (0.0, y - 4, -6.0)
    return c


CHARMS = [
    ("skull", charm_skull), ("bones", charm_bones), ("ring", charm_ring),
    ("lantern", charm_lantern), ("plaque", charm_plaque),
    ("fetish", charm_fetish), ("spine", charm_spine), ("effigy", charm_effigy),
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
