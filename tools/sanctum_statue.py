#!/usr/bin/env python3
"""The Bastet as a solid, for Mika's hall. Imported by `make_sanctum.py`.

She is modelled as a signed-distance field. Each part of her (body, haunch,
chest, head, ears, forelegs, hind paws, tail, base) is a rounded solid, and
the parts are joined with a smooth union, so a leg grows out of the chest
through a fillet instead of meeting it at a seam. Most parts are made by
inflating an outline from the reference (`make_sanctum.BASTET_*`): the solid
is as thick at each point as the outline's inner distance allows, up to the
part's own half-depth, so from the side she is her outline and from
anywhere else she is rounded. The tail is a tube along a path in 3D.

The field is turned into a mesh (`skimage.measure.marching_cubes`), reduced
(`fast_simplification`), given smooth normals from the field's gradient and
an occlusion baked per vertex, and written as a small binary that
`bg_sanctum` loads (`write`).

Her frame is her card's (the sprite `make_sanctum.bastet` draws her colour
into): x across, 0 at the card's middle; y up, 0 at the card's foot and 1 at
its head; z her depth, negative on her near side (toward the camera). All in
units of the card's height.
"""
import math
import struct

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

STEP = 1.0 / 260          # the field's grid spacing
SUB = 4                   # outlines are rasterised this many times finer
TRIANGLES = 24000         # what the mesh is reduced to
ZMAX = 0.20               # the grid's reach in depth, either side


def smin(a, b, k):
    """A smooth union of two fields, blending over `k`."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


class Frame:
    """The grid, and the mapping from the reference's frame into it."""

    def __init__(self, to_sprite, aspect):
        self.to_sprite = to_sprite
        self.aspect = aspect
        pad = 0.03
        self.x0, self.x1 = -aspect / 2 - pad, aspect / 2 + pad
        self.y0, self.y1 = -pad, 1 + pad
        self.nx = int(math.ceil((self.x1 - self.x0) / STEP)) + 1
        self.ny = int(math.ceil((self.y1 - self.y0) / STEP)) + 1
        self.nz = int(math.ceil(2 * ZMAX / STEP)) + 1
        xs = self.x0 + np.arange(self.nx) * STEP
        ys = self.y0 + np.arange(self.ny) * STEP
        zs = -ZMAX + np.arange(self.nz) * STEP
        self.X = xs[:, None, None]
        self.Y = ys[None, :, None]
        self.Z = zs[None, None, :]
        self.xs, self.ys, self.zs = xs, ys, zs

    def unit(self, p):
        """A reference point in her frame (x, y)."""
        su, sv = self.to_sprite(p)
        return ((su - 0.5) * self.aspect, 1 - sv)

    def y_of(self, v):
        return self.unit((0.5, v))[1]

    def x_of(self, u):
        return self.unit((u, 0.5))[0]

    def field2d(self, polys, holes=(), clip_top=None):
        """The signed distance to an outline (positive inside) on the grid's
        (x, y), from polygons of reference points: `polys` filled, `holes`
        cut out, and everything above reference height `clip_top` cut off.
        Rasterised `SUB` times finer and sampled back, so the distance is
        smooth."""
        fw = self.nx * SUB
        fh = self.ny * SUB
        m = Image.new("L", (fw, fh), 0)
        d = ImageDraw.Draw(m)

        def px(p):
            x, y = self.unit(p)
            return ((x - self.x0) / STEP * SUB, (self.y1 - y) / STEP * SUB)

        for poly in polys:
            d.polygon([px(p) for p in poly], fill=255)
        for poly in holes:
            d.polygon([px(p) for p in poly], fill=0)
        if clip_top is not None:
            d.rectangle([0, 0, fw, px((0.5, clip_top))[1]], fill=0)
        a = np.asarray(m) > 127
        inside = ndimage.distance_transform_edt(a)
        outside = ndimage.distance_transform_edt(~a)
        sd = (inside - outside) * (STEP / SUB)          # image rows run down
        # sample back at the grid's points (x across, y up)
        gi = (np.arange(self.nx) * SUB)[:, None] + 0.0
        gj = ((self.y1 - self.ys) / STEP * SUB)[None, :]
        gi = np.broadcast_to(gi, (self.nx, self.ny))
        gj = np.broadcast_to(gj, (self.nx, self.ny))
        return ndimage.map_coordinates(sd, [gj, gi], order=1, mode="nearest")


def inflate(fr, d2, half, round_r, zc=0.0):
    """A solid from an outline's distance field `d2`: at each point it is
    `half` deep either side of `zc` (a number, or an array over x, y),
    rounding over from the outline's edge across `round_r`."""
    d = np.maximum(d2, 0)
    r = np.maximum(round_r, 1e-4)
    t = np.clip(d / r, 0, 1)
    h = half * np.sqrt(np.clip(1 - (1 - t) ** 2, 0, 1))
    h = np.broadcast_to(h, d2.shape)
    return np.maximum(np.abs(fr.Z - zc) - h[:, :, None], -d2[:, :, None])


def tube(fr, path, r0, r1):
    """A tube along a path of `(x, y, z)` points in her frame, its radius
    running from `r0` to `r1`."""
    f = np.full((fr.nx, fr.ny, fr.nz), 10.0, np.float32)
    n = len(path) - 1
    for i in range(n):
        a = np.array(path[i], np.float32)
        b = np.array(path[i + 1], np.float32)
        ab = b - a
        L2 = float(ab @ ab)
        px = fr.X - a[0]
        py = fr.Y - a[1]
        pz = fr.Z - a[2]
        t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / L2, 0, 1)
        dx = px - ab[0] * t
        dy = py - ab[1] * t
        dz = pz - ab[2] * t
        r = r0 + (r1 - r0) * (i + t) / n
        f = np.minimum(f, np.sqrt(dx * dx + dy * dy + dz * dz) - r)
    return f


def box(fr, x0, x1, y0, y1, zh, r):
    """A box with its edges rounded by `r`."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
    qx = np.abs(fr.X - cx) - hx + r
    qy = np.abs(fr.Y - cy) - hy + r
    qz = np.abs(fr.Z) - zh + r
    out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2
                  + np.maximum(qz, 0) ** 2)
    ins = np.minimum(np.maximum(np.maximum(qx, qy), qz), 0)
    return out + ins - r


def by_height(fr, table):
    """A half-depth that varies with reference height: `table` is
    `[(v, half), ...]`, returned as an array over the grid's (x, y)."""
    ys = [fr.y_of(v) for v, _ in table]
    hs = [h for _, h in table]
    order = np.argsort(ys)
    col = np.interp(fr.ys, np.array(ys)[order], np.array(hs)[order])
    return np.broadcast_to(col[None, :], (fr.nx, fr.ny))


def field(fr, parts):
    """Her whole field. `parts` is the outlines, by name, from
    `make_sanctum` (see `make_sanctum.bastet_statue_parts`)."""
    P = parts
    sp = P["spline"]

    # --- the torso: body, haunch, chest and head, each blended into the next
    body_d = fr.field2d([sp(P["ref"])],
                        holes=[sp(P["arch"]), P["legcut"]], clip_top=0.112)
    body_half = by_height(fr, [
        (0.11, 0.030), (0.16, 0.040), (0.22, 0.044), (0.27, 0.042),
        (0.34, 0.050), (0.42, 0.064), (0.50, 0.080), (0.60, 0.098),
        (0.70, 0.110), (0.80, 0.116), (0.87, 0.112), (0.92, 0.100)])
    F = inflate(fr, body_d, body_half, np.maximum(body_half, 0.02))

    haunch = inflate(fr, fr.field2d([sp(P["haunch"])]), 0.136, 0.085)
    F = smin(F, haunch, 0.030)

    chest = inflate(fr, fr.field2d([sp(P["chest"])]), 0.066, 0.045)
    F = smin(F, chest, 0.030)

    head_d = fr.field2d([sp(P["head"])])
    # the muzzle narrows to the nose
    xn0, xn1 = fr.x_of(0.860), fr.x_of(0.945)
    k = np.clip((fr.xs - xn0) / (xn1 - xn0), 0, 1)[:, None]
    head_half = np.broadcast_to(0.058 - 0.026 * k * k, head_d.shape)
    head = inflate(fr, head_d, head_half, 0.042)
    F = smin(F, head, 0.024)

    # --- the ears, one either side of the skull
    for key, zc in (("near_ear", -0.030), ("far_ear", 0.030)):
        ear = inflate(fr, fr.field2d([sp(P[key])]), 0.013, 0.010, zc)
        F = smin(F, ear, 0.012)

    # --- the forelegs, growing out of the chest; and the hind paws
    for key, zc in (("near_leg", -0.031), ("far_leg", 0.031)):
        d = fr.field2d([sp(P[key])])
        leg = inflate(fr, d, 0.023, 0.023, zc)
        F = smin(F, leg, 0.022)
    for zc in (-0.080, 0.080):
        paw = inflate(fr, fr.field2d([sp(P["hind_paw"])]), 0.024, 0.020, zc)
        F = smin(F, paw, 0.016)

    # --- the tail, round her near side from the rump
    path = [(fr.unit((u, v))[0], fr.unit((u, v))[1], z)
            for (u, v, z) in P["tail_path"]]
    F = smin(F, tube(fr, path, 0.015, 0.010), 0.010)

    # --- the base slab she sits on
    x0, x1 = fr.x_of(0.076), fr.x_of(0.965)
    y0, y1 = fr.y_of(0.996), fr.y_of(0.916)
    F = smin(F, box(fr, x0, x1, y0, y1, 0.170, 0.010), 0.006)
    return F.astype(np.float32)


def sample(F, fr, pts):
    """The field at points in her frame (trilinear)."""
    c = [(pts[:, 0] - fr.x0) / STEP, (pts[:, 1] - fr.y0) / STEP,
         (pts[:, 2] + ZMAX) / STEP]
    return ndimage.map_coordinates(F, c, order=1, mode="nearest")


def mesh(fr, F):
    """The field's surface as a mesh: `(points, faces, normals, occlusion)`,
    reduced to about `TRIANGLES`."""
    from skimage.measure import marching_cubes
    import fast_simplification

    v, f, _, _ = marching_cubes(F, level=0.0, spacing=(STEP, STEP, STEP))
    v = v + np.array([fr.x0, fr.y0, -ZMAX], np.float32)
    keep = 1.0 - TRIANGLES / max(1, len(f))
    if keep > 0:
        v, f = fast_simplification.simplify(v.astype(np.float32),
                                            f.astype(np.int64),
                                            target_reduction=keep)
    v = np.asarray(v, np.float32)
    f = np.asarray(f, np.int64)

    # normals from the field's gradient, which is smooth where the mesh is
    # faceted
    g = np.gradient(F, STEP)
    c = [(v[:, 0] - fr.x0) / STEP, (v[:, 1] - fr.y0) / STEP,
         (v[:, 2] + ZMAX) / STEP]
    n = np.stack([ndimage.map_coordinates(gi, c, order=1, mode="nearest")
                  for gi in g], axis=1)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)

    # occlusion: how far the field falls short of open space a little way
    # out along the normal
    occ = np.zeros(len(v), np.float32)
    wsum = 0.0
    for i, dist in enumerate((0.010, 0.020, 0.036, 0.060)):
        w = 0.5 ** i
        s = sample(F, fr, v + n * dist)
        occ += w * np.clip((dist - s) / dist, 0, 1)
        wsum += w
    ao = np.clip(1.0 - 0.85 * occ / wsum, 0.30, 1.0)
    return v, f, n, ao


def eye_faces(v, f, n, to_sprite_xy, box):
    """The faces of her eyes: those whose middle falls in `box` (the eye's
    bounds in the sprite, `(u0, v0, u1, v1)`) on a side of her head."""
    mid = v[f].mean(axis=1)
    su, sv = to_sprite_xy(mid[:, 0], mid[:, 1])
    nz = np.abs(n[f].mean(axis=1)[:, 2])
    sel = ((su >= box[0]) & (su <= box[2]) & (sv >= box[1]) & (sv <= box[3])
           & (nz > 0.30))
    return f[sel]


MAGIC = b"BSTM"
VERSION = 1


def write(path, v, f, n, ao, eyes):
    """The binary `bg_sanctum` reads (`hall_build_statue`): a header
    (`BSTM`, version, vertices, faces, eye faces, all u32), then each vertex
    as three f32 (x, y, z), three s8 (the normal) and a u8 (its occlusion),
    then the faces and the eye faces as u16 indices. Little-endian."""
    if len(v) > 65535:
        raise SystemExit("bastet mesh: %d vertices won't index in 16 bits"
                         % len(v))
    out = [MAGIC, struct.pack("<4I", VERSION, len(v), len(f), len(eyes))]
    nn = np.clip(np.round(n * 127), -127, 127).astype(np.int8)
    aa = np.clip(np.round(ao * 255), 0, 255).astype(np.uint8)
    rec = np.zeros(len(v), dtype=[("p", "<f4", 3), ("n", "i1", 3),
                                  ("a", "u1")])
    rec["p"] = v
    rec["n"] = nn
    rec["a"] = aa
    out.append(rec.tobytes())
    out.append(np.asarray(f, "<u2").tobytes())
    out.append(np.asarray(eyes, "<u2").tobytes())
    with open(path, "wb") as fh:
        fh.write(b"".join(out))


def render(v, f, n, ao, yaw, pitch, size=300, albedo=None, uv=None):
    """A quick software render of the mesh, for the preview sheet: an
    orthographic view turned `yaw` about the vertical and tipped `pitch`
    toward looking down, lit from the upper left, with its occlusion."""
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # yaw about y, then pitch about x
    x1 = v[:, 0] * cy + v[:, 2] * sy
    z1 = -v[:, 0] * sy + v[:, 2] * cy
    y2 = v[:, 1] * cp - z1 * sp
    z2 = v[:, 1] * sp + z1 * cp
    nx1 = n[:, 0] * cy + n[:, 2] * sy
    nz1 = -n[:, 0] * sy + n[:, 2] * cy
    ny2 = n[:, 1] * cp - nz1 * sp
    nz2 = n[:, 1] * sp + nz1 * cp
    L = np.array([-0.45, 0.65, -0.62])
    L /= np.linalg.norm(L)
    lam = np.clip(nx1 * L[0] + ny2 * L[1] + nz2 * L[2], 0, 1)
    spec = np.clip(nz2 * -1, 0, 1) ** 12 * 0.0
    shade = (0.14 + 0.86 * lam) * ao + spec
    sc = size * 0.9
    ox, oy = size / 2, size * 0.95
    X = ox + x1 * sc
    Y = oy - y2 * sc + (size * 0.45 * sp)
    img = np.full((size, size), 0.12, np.float32)
    zb = np.full((size, size), 1e9, np.float32)
    for tri in f:
        xs, ys, zs = X[tri], Y[tri], z2[tri]
        i0, i1 = int(max(0, xs.min())), int(min(size - 1, xs.max() + 1))
        j0, j1 = int(max(0, ys.min())), int(min(size - 1, ys.max() + 1))
        if i1 < i0 or j1 < j0:
            continue
        gi, gj = np.meshgrid(np.arange(i0, i1 + 1) + 0.5,
                             np.arange(j0, j1 + 1) + 0.5)
        d = ((ys[1] - ys[2]) * (xs[0] - xs[2])
             + (xs[2] - xs[1]) * (ys[0] - ys[2]))
        if abs(d) < 1e-9:
            continue
        a = ((ys[1] - ys[2]) * (gi - xs[2]) + (xs[2] - xs[1]) * (gj - ys[2])) / d
        b = ((ys[2] - ys[0]) * (gi - xs[2]) + (xs[0] - xs[2]) * (gj - ys[2])) / d
        c = 1 - a - b
        ins = (a >= 0) & (b >= 0) & (c >= 0)
        if not ins.any():
            continue
        z = a * zs[0] + b * zs[1] + c * zs[2]
        s = a * shade[tri[0]] + b * shade[tri[1]] + c * shade[tri[2]]
        sub = zb[j0:j1 + 1, i0:i1 + 1]
        win = ins & (z < sub)
        sub[win] = z[win]
        img[j0:j1 + 1, i0:i1 + 1][win] = s[win]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "L")
