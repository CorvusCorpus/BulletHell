#!/usr/bin/env python3
"""Geometry for the 3D wood (`tools/make_wood.py`): the trees, the
undergrowth and the charms, built as vertex data GameMaker loads as is.

Every mesh is one triangle strip (`pr_trianglestrip`): each part (a tube, a
ribbon, a card) is a strip of its own, and parts are joined by repeating the
last vertex of one and the first of the next, which makes triangles of no
area. A strip needs far fewer vertices than a list, which keeps the files
small. Nothing is culled by winding, so the parity of the joins doesn't
matter.

The vertex is 52 bytes, in GameMaker's order (`wood_format` in
`scripts/bg_wood`):

    position    3 x f32   in the mesh's own space, y up, the root at 0
    normal      3 x f32   a solid's normal; a ribbon's direction along itself
    colour      4 x u8    rgb a tint the texture is multiplied by; a the
                          baked occlusion (1 open, 0 shut in)
    texcoord    2 x f32   the texture's u, v (a ribbon's side, -1 or 1, and
                          its radius)
    extra       4 x f32   the anchor's x and z (what the ground under it is
                          measured at), `kind * 4 + conform`, and how much the
                          wind moves it

`kind` is 0 for a lit solid (bark), 1 for a ribbon (a twig, widened to face
the camera in the shader), 2 for a card (a leaf or a frond, cut out by the
foliage sheet's alpha), 3 for something that glows. `conform` 1 means the
vertex follows the ground under its own position rather than under its
anchor, so a root runs over a bump instead of through it.
"""
import math
import struct
import zlib

import numpy as np

KIND_SOLID = 0
KIND_RIBBON = 1
KIND_CARD = 2
KIND_GLOW = 3

VERTEX = np.dtype([
    ("pos", "<f4", 3),
    ("nrm", "<f4", 3),
    ("col", "u1", 4),
    ("uv", "<f4", 2),
    ("ex", "<f4", 4),
])
assert VERTEX.itemsize == 52


def norm(v, axis=-1):
    n = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.maximum(n, 1e-9)


class Strip:
    """A mesh under construction: a list of parts, each a strip of vertices
    (a structured array)."""

    def __init__(self):
        self.parts = []

    def add(self, verts):
        if verts is not None and len(verts) >= 3:
            self.parts.append(verts)

    def extend(self, other):
        self.parts.extend(other.parts)

    def build(self):
        """One strip: the parts joined by degenerate triangles."""
        out = []
        for i, p in enumerate(self.parts):
            if i > 0:
                out.append(out[-1][-1:])        # repeat the last vertex
                out.append(p[:1])                # ...and the next's first
            out.append(p)
        if not out:
            return np.zeros(0, VERTEX)
        return np.concatenate(out)

    def count(self):
        return sum(len(p) for p in self.parts)


def verts(pos, nrm, col, uv, ex):
    """Pack arrays (n x 3, n x 3, n x 4 floats 0..1, n x 2, n x 4) into
    vertices."""
    n = len(pos)
    v = np.zeros(n, VERTEX)
    v["pos"] = pos
    v["nrm"] = nrm
    v["col"] = np.clip(np.round(np.asarray(col) * 255), 0, 255).astype(np.uint8)
    v["uv"] = uv
    v["ex"] = ex
    return v


def transform(v, m3=None, offset=(0, 0, 0), scale=1.0):
    """A copy of vertices rotated by `m3` (3 x 3), scaled and moved. Normals
    (and a ribbon's direction) are rotated; anchors are moved with their
    vertices; a ribbon's radius is scaled."""
    out = v.copy()
    m3 = np.eye(3) if m3 is None else np.asarray(m3, float)
    off = np.asarray(offset, float)
    out["pos"] = (v["pos"] @ m3.T) * scale + off
    out["nrm"] = norm(v["nrm"] @ m3.T)
    anc = np.stack([v["ex"][:, 0], np.zeros(len(v)), v["ex"][:, 1]], axis=1)
    anc = (anc @ m3.T) * scale + off
    out["ex"][:, 0] = anc[:, 0]
    out["ex"][:, 1] = anc[:, 2]
    rib = (np.floor(v["ex"][:, 2] / 4.0 + 1e-3) == KIND_RIBBON)
    out["uv"][rib, 1] = v["uv"][rib, 1] * scale
    return out


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_axis(axis, ang):
    """Rodrigues: the rotation by `ang` radians about unit `axis`."""
    x, y, z = axis
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([
        [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, c + z * z * C],
    ])


# ---------------------------------------------------------------------------
# Frames along a curve
# ---------------------------------------------------------------------------

def frames(P, up_hint=None):
    """Tangents, normals and binormals along a polyline, the normal carried
    along by parallel transport so a tube doesn't twist."""
    k = len(P)
    T = np.zeros((k, 3))
    T[1:-1] = P[2:] - P[:-2]
    T[0] = P[1] - P[0]
    T[-1] = P[-1] - P[-2]
    T = norm(T)
    a = np.array([0.0, 0.0, 1.0]) if up_hint is None else np.asarray(up_hint, float)
    if abs(np.dot(a, T[0])) > 0.9:
        a = np.array([1.0, 0.0, 0.0])
    N = np.zeros((k, 3))
    N[0] = norm(np.cross(T[0], a))
    for i in range(1, k):
        v = np.cross(T[i - 1], T[i])
        s = np.linalg.norm(v)
        n = N[i - 1]
        if s > 1e-8:
            ang = math.atan2(s, float(np.dot(T[i - 1], T[i])))
            n = rot_axis(v / s, ang) @ n
        n = n - np.dot(n, T[i]) * T[i]
        N[i] = n / max(np.linalg.norm(n), 1e-9)
    B = np.cross(T, N)
    return T, N, B


def arclen(P):
    d = np.linalg.norm(np.diff(P, axis=0), axis=1)
    return np.concatenate([[0.0], np.cumsum(d)])


# ---------------------------------------------------------------------------
# Tubes, ribbons, cards
# ---------------------------------------------------------------------------

def tube(P, R, sides, tint, ao=None, u_tile=150.0, v_tile=300.0, v0=0.0,
         lobe=None, conform=None, sway=None, anchor=(0.0, 0.0),
         kind=KIND_SOLID, rings_ao=None):
    """A generalised cylinder along `P` (k x 3) with radii `R` (k), as one
    strip: band by band, each band a zigzag round the ring with the seam
    column repeated, joined to the next band by two repeated vertices.

    `lobe(theta, i)` optionally scales the radius round ring `i` (the
    buttresses at a trunk's foot). `ao`, `conform` and `sway` are per ring.
    `tint` is an RGB triple 0..1. The texture repeats a whole number of times
    round the tube (so the seam is invisible) and runs along it by arc
    length from `v0`.
    """
    P = np.asarray(P, float)
    R = np.asarray(R, float)
    k = len(P)
    if k < 2:
        return None
    T, N, B = frames(P)
    th = np.linspace(0.0, 2 * math.pi, sides + 1)
    ct, st = np.cos(th), np.sin(th)
    rad = np.repeat(R[:, None], sides + 1, axis=1)
    if lobe is not None:
        for i in range(k):
            rad[i] *= lobe(th, i)
    dirs = ct[None, :, None] * N[:, None, :] + st[None, :, None] * B[:, None, :]
    pos = P[:, None, :] + rad[..., None] * dirs

    # Normals from the surface itself (so lobes and tapers shade right):
    # across the ring and along the tube.
    du = np.roll(pos[:, :-1], -1, axis=1) - np.roll(pos[:, :-1], 1, axis=1)
    du = np.concatenate([du, du[:, :1]], axis=1)
    dv = np.zeros_like(pos)
    dv[1:-1] = pos[2:] - pos[:-2]
    dv[0] = pos[1] - pos[0]
    dv[-1] = pos[-1] - pos[-2]
    nrm = np.cross(du, dv)
    nl = np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = np.where(nl > 1e-6, nrm / np.maximum(nl, 1e-9), dirs)
    # Point outward.
    flip = np.sum(nrm * dirs, axis=-1) < 0
    nrm[flip] *= -1

    s = arclen(P)
    rep = max(1, int(round(2 * math.pi * max(float(R[0]), 0.5) / u_tile)))
    u = th / (2 * math.pi) * rep
    v = (v0 + s) / v_tile

    ao = np.ones(k) if ao is None else np.asarray(ao, float)
    conform = np.zeros(k) if conform is None else np.asarray(conform, float)
    sway = np.zeros(k) if sway is None else np.asarray(sway, float)

    out = []
    for i in range(k - 1):
        # Band i: (i, j), (i + 1, j) for each j round the ring.
        idx_i = np.arange(sides + 1)
        p = np.empty((2 * (sides + 1), 3))
        p[0::2] = pos[i]
        p[1::2] = pos[i + 1]
        n = np.empty_like(p)
        n[0::2] = nrm[i]
        n[1::2] = nrm[i + 1]
        uv = np.empty((2 * (sides + 1), 2))
        uv[0::2, 0] = u
        uv[1::2, 0] = u
        uv[0::2, 1] = v[i]
        uv[1::2, 1] = v[i + 1]
        c = np.empty((2 * (sides + 1), 4))
        c[:, :3] = tint
        c[0::2, 3] = ao[i]
        c[1::2, 3] = ao[i + 1]
        if rings_ao is not None:
            c[0::2, 3] *= rings_ao[i][idx_i]
            c[1::2, 3] *= rings_ao[i + 1][idx_i]
        ex = np.empty((2 * (sides + 1), 4))
        ex[:, 0] = anchor[0]
        ex[:, 1] = anchor[1]
        ex[0::2, 2] = kind * 4 + conform[i]
        ex[1::2, 2] = kind * 4 + conform[i + 1]
        ex[0::2, 3] = sway[i]
        ex[1::2, 3] = sway[i + 1]
        band = verts(p, n, c, uv, ex)
        if out:
            out.append(out[-1][-1:])
            out.append(band[:1])
        out.append(band)
    return np.concatenate(out)


def cap(P_end, T_end, N_end, B_end, r, sides, tint, ao=1.0, jag=0.0, rng=None,
        anchor=(0.0, 0.0), sway=0.0):
    """A closing cap over a tube's end (a broken branch): a fan from the
    ring to a point a little proud of it, jagged if `jag`."""
    th = np.linspace(0.0, 2 * math.pi, sides + 1)
    ring = (P_end[None, :] + r * (np.cos(th)[:, None] * N_end[None, :]
                                  + np.sin(th)[:, None] * B_end[None, :]))
    if jag > 0 and rng is not None:
        ring = ring + T_end[None, :] * (rng.uniform(-1, 1, sides + 1) * jag * r)[:, None]
        ring[-1] = ring[0]
    tip = P_end + T_end * r * 0.25
    p = np.empty((2 * (sides + 1), 3))
    p[0::2] = ring
    p[1::2] = tip
    n = np.repeat(T_end[None, :], len(p), axis=0)
    uv = np.zeros((len(p), 2))
    uv[0::2, 0] = np.cos(th) * 0.3
    uv[0::2, 1] = np.sin(th) * 0.3
    c = np.empty((len(p), 4))
    c[:, :3] = tint
    c[:, 3] = ao
    ex = np.zeros((len(p), 4))
    ex[:, 0] = anchor[0]
    ex[:, 1] = anchor[1]
    ex[:, 2] = KIND_SOLID * 4
    ex[:, 3] = sway
    return verts(p, n, c, uv, ex)


def ribbon(P, R, tint, ao=1.0, sway=None, anchor=(0.0, 0.0), conform=0.0):
    """A twig: a strip along `P` whose two edges the shader pushes apart
    across the line of sight (at least a pixel or so wide, its alpha cut to
    match its true width). Each vertex carries the twig's direction where a
    solid carries its normal, and its side and radius in the texcoord."""
    P = np.asarray(P, float)
    R = np.asarray(R, float)
    k = len(P)
    if k < 2:
        return None
    T = np.zeros((k, 3))
    T[1:-1] = P[2:] - P[:-2]
    T[0] = P[1] - P[0]
    T[-1] = P[-1] - P[-2]
    T = norm(T)
    p = np.repeat(P, 2, axis=0)
    n = np.repeat(T, 2, axis=0)
    uv = np.zeros((2 * k, 2))
    uv[0::2, 0] = -1.0
    uv[1::2, 0] = 1.0
    uv[:, 1] = np.repeat(R, 2)
    c = np.empty((2 * k, 4))
    c[:, :3] = tint
    c[:, 3] = np.repeat(np.broadcast_to(np.asarray(ao, float), (k,)), 2)
    ex = np.zeros((2 * k, 4))
    ex[:, 0] = anchor[0]
    ex[:, 1] = anchor[1]
    ex[:, 2] = KIND_RIBBON * 4 + conform
    sw = np.zeros(k) if sway is None else np.broadcast_to(np.asarray(sway, float), (k,))
    ex[:, 3] = np.repeat(sw, 2)
    return verts(p, n, c, uv, ex)


def card(corners, uv_rect, tint, normal=None, ao=1.0, sway=(0, 0, 0, 0),
         anchor=(0.0, 0.0), kind=KIND_CARD, conform=0.0, bend=None):
    """A quad (four corners: bottom left, bottom right, top right, top left)
    showing `uv_rect` (u0, v0, u1, v1, with v0 the top of the picture) of
    the foliage sheet. `bend`, if given, is a list of extra rows between
    bottom and top as (left, right) corner pairs, so a frond can arch."""
    rows = [(corners[0], corners[1])]
    if bend:
        rows.extend(bend)
    rows.append((corners[3], corners[2]))
    m = len(rows)
    u0, v0, u1, v1 = uv_rect
    p = np.empty((2 * m, 3))
    uv = np.empty((2 * m, 2))
    for i, (l, r) in enumerate(rows):
        t = i / (m - 1)
        p[2 * i] = l
        p[2 * i + 1] = r
        uv[2 * i] = (u0, v1 + (v0 - v1) * t)
        uv[2 * i + 1] = (u1, v1 + (v0 - v1) * t)
    if normal is None:
        e1 = np.asarray(corners[1], float) - np.asarray(corners[0], float)
        e2 = np.asarray(corners[3], float) - np.asarray(corners[0], float)
        normal = norm(np.cross(e1, e2))
    n = np.repeat(np.asarray(normal, float)[None, :], 2 * m, axis=0)
    c = np.empty((2 * m, 4))
    c[:, :3] = tint
    c[:, 3] = ao
    ex = np.zeros((2 * m, 4))
    ex[:, 0] = anchor[0]
    ex[:, 1] = anchor[1]
    ex[:, 2] = kind * 4 + conform
    sw = np.interp(np.linspace(0, 1, m), [0, 1 / 3, 2 / 3, 1], sway)
    ex[:, 3] = np.repeat(sw, 2)
    return verts(p, n, c, uv, ex)


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def pack(v):
    """The strip's bytes, zlib-compressed, as `buffer_decompress` reads
    them."""
    return zlib.compress(np.ascontiguousarray(v).tobytes(), 9)


def bounds(v):
    p = v["pos"]
    return p.min(axis=0), p.max(axis=0)
