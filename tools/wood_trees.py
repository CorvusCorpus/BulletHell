#!/usr/bin/env python3
"""The wood's trees, grown (`tools/make_wood.py` writes them out).

Each tree is grown as a skeleton of branches, every branch a polyline with a
radius at each point, and then skinned: branches thick enough to have a body
are tubes (`wood_mesh.tube`), the fine twigs ribbons (`wood_mesh.ribbon`),
which the shader widens to face the camera.

Growth is a random walk with memory: each branch carries a slowly turning
bend and is knocked about at every step (`gnarl`), pulled up or down
(`tropism`) and toward the side it reaches for (`reach`, local +x, which the
wood turns to face the path), so the limbs of the trees beside the path
arch over it as the corridor's did. A trunk flares into buttresses at its
foot and sends roots out over the ground.

All lengths are world units (the camera flies 250 above the path).
"""
import math

import numpy as np

import wood_mesh as M
import wood_tex as TX

GOLDEN = math.pi * (3.0 - math.sqrt(5.0))

# Below this radius a branch is a ribbon rather than a tube.
RIBBON_R = 2.4

# Ivy up a trunk (`Tree.ivy`): the chance a tree of each species has it.
IVY_ODDS = {"oak": 0.6, "ancient": 0.85, "snag": 0.5, "crook": 0.3,
            "weeper": 0.3, "sapling": 0.0}

# Hanging vines (`Tree.vine_sites`): the chance a point along a limb has
# one, how long they are, and how far toward the path (local +x) one may
# hang (a vine over the path hung in front of the camera like a scratch on
# the picture).
VINE_ODDS = 0.05
VINE_LEN = (110.0, 380.0)
VINE_X = 60.0

# Where a charm can hang (`Tree.hang_sites`): how far below the tie it
# needs open air, how wide that air must be, how far apart two sites must
# be, and the heights a tie can be at.
HANG_DROP = 300.0
HANG_CLEAR = 55.0
HANG_APART = 120.0
HANG_Y = (420.0, 1050.0)


class Branch:
    def __init__(self, pts, rad, level, parent=-1, broken=False, root=False):
        self.pts = np.asarray(pts, float)
        self.rad = np.asarray(rad, float)
        self.level = level
        self.parent = parent
        self.broken = broken
        self.root = root
        self.v0 = 0.0          # the texture's offset along it


def smooth(P, iters=2, keep=1):
    """Laplacian smoothing of a polyline, its first `keep` and last points
    held."""
    P = P.copy()
    for _ in range(iters):
        Q = P.copy()
        Q[keep:-1] = 0.25 * P[keep - 1:-2] + 0.5 * P[keep:-1] + 0.25 * P[keep + 1:]
        P = Q
    return P


def perp(d, rng):
    """A random unit vector perpendicular to `d`."""
    v = np.cross(d, rng.normal(size=3))
    return v / max(np.linalg.norm(v), 1e-9)


def walk(rng, start, d0, length, seg, gnarl, tropism, reach=None, reach_k=0.0,
         kink=0.0, bend=0.5, droop=0.0):
    """A branch's path: `length` in steps of about `seg`, its direction
    knocked by `gnarl` radians a step about a random axis, turning steadily
    about a slowly wandering axis (`bend` times `gnarl` a step), pulled up by
    `tropism` (down if negative), toward `reach` by `reach_k`, and, with
    `droop`, more and more downward toward its end (a weeping limb)."""
    n = max(2, int(math.ceil(length / seg)))
    step = length / n
    d = np.asarray(d0, float)
    d = d / np.linalg.norm(d)
    axis = perp(d, rng)
    rate = rng.normal(0, gnarl * bend)
    pts = [np.asarray(start, float)]
    for i in range(n):
        t = (i + 1) / n
        ax = perp(d, rng)
        ang = rng.normal(0, gnarl)
        if kink > 0 and rng.random() < kink:
            ang += rng.choice([-1.0, 1.0]) * rng.uniform(0.35, 0.75)
        d = M.rot_axis(ax, ang) @ d
        axis = axis - np.dot(axis, d) * d
        axis = axis / max(np.linalg.norm(axis), 1e-9)
        axis = M.rot_axis(d, rng.normal(0, 0.3)) @ axis
        d = M.rot_axis(axis, rate) @ d
        pull = tropism - droop * t * t
        d = d + np.array([0.0, pull, 0.0]) * (step / 100.0)
        if reach is not None and reach_k:
            d = d + np.asarray(reach, float) * reach_k * (step / 100.0)
        d = d / max(np.linalg.norm(d), 1e-9)
        pts.append(pts[-1] + d * step)
    return np.array(pts)


def taper(n, r0, r1, power=1.0):
    t = np.linspace(0.0, 1.0, n)
    return r0 + (r1 - r0) * t ** power


# ---------------------------------------------------------------------------
# Species
# ---------------------------------------------------------------------------
#
# Per level (0 trunk, 1 limbs, 2 branches, 3 twigs, 4 fine twigs): how many
# children, where along the parent they start, their angle off it (degrees),
# their length against the parent's, their radius against the parent's there,
# and the step and knock of their walk.

SPECIES = {
    # A broad old oak gone grey: a short thick trunk, heavy limbs thrown out
    # sideways and twisting, a dense crown of crooked twigs.
    "oak": dict(
        height=(860, 1060), r0=(48, 62), lean=10, gnarl0=0.075, tropism0=0.30,
        limbs=(4, 6), limb_t=(0.24, 0.82), limb_ang=(52, 86),
        limb_len=(0.80, 1.10), limb_r=(0.48, 0.66), reach_k=0.30,
        limb_shrink=0.30, trunk_frac=0.78,
        kids=[(0, 0), (4, 6), (4, 6), (3, 5), (2, 3)],
        kid_t=[(0, 0), (0.25, 0.95), (0.25, 0.95), (0.20, 0.95), (0.3, 0.95)],
        kid_ang=[(0, 0), (32, 70), (28, 62), (24, 55), (22, 50)],
        kid_len=[(0, 0), (0.48, 0.72), (0.42, 0.66), (0.40, 0.62), (0.45, 0.65)],
        kid_r=[(0, 0), (0.50, 0.72), (0.50, 0.72), (0.48, 0.70), (0.5, 0.7)],
        seg=[32, 26, 20, 14, 10], gnarl=[0.075, 0.15, 0.18, 0.22, 0.26],
        tropism=[0.30, 0.03, 0.08, 0.12, 0.10], levels=5,
        buttress=(0.55, 5, 70), roots=(5, 7), broken=0.12, kink=0.06,
    ),
    # A thin tree grown crooked and leaning, its few limbs clawing.
    "crook": dict(
        height=(680, 900), r0=(24, 34), lean=18, gnarl0=0.12, tropism0=0.22,
        limbs=(3, 4), limb_t=(0.38, 0.85), limb_ang=(30, 60),
        limb_len=(0.50, 0.75), limb_r=(0.50, 0.68), reach_k=0.45,
        kids=[(0, 0), (3, 4), (3, 5), (2, 4), (2, 3)],
        kid_t=[(0, 0), (0.35, 0.95), (0.30, 0.95), (0.25, 0.95), (0.3, 0.95)],
        kid_ang=[(0, 0), (30, 65), (30, 60), (26, 58), (24, 52)],
        kid_len=[(0, 0), (0.45, 0.70), (0.42, 0.66), (0.42, 0.62), (0.45, 0.65)],
        kid_r=[(0, 0), (0.52, 0.72), (0.50, 0.72), (0.48, 0.70), (0.5, 0.7)],
        seg=[30, 22, 18, 13, 10], gnarl=[0.09, 0.17, 0.21, 0.25, 0.28],
        tropism=[0.25, 0.10, 0.12, 0.14, 0.10], levels=5,
        buttress=(0.35, 4, 40), roots=(3, 5), broken=0.18, kink=0.10,
    ),
    # A dead giant, mostly trunk: tall, nearly straight, a few broken limbs
    # and a snapped crown. These are the trunks that pass by the camera.
    "snag": dict(
        height=(1500, 1900), r0=(52, 74), lean=4, gnarl0=0.03, tropism0=0.5,
        limbs=(4, 6), limb_t=(0.42, 0.92), limb_ang=(48, 80),
        limb_len=(0.24, 0.40), limb_r=(0.30, 0.46), reach_k=0.25,
        kids=[(0, 0), (2, 4), (3, 5), (2, 4), (2, 3)],
        kid_t=[(0, 0), (0.30, 0.95), (0.25, 0.95), (0.20, 0.95), (0.3, 0.95)],
        kid_ang=[(0, 0), (30, 60), (28, 58), (26, 55), (22, 50)],
        kid_len=[(0, 0), (0.45, 0.70), (0.42, 0.66), (0.40, 0.62), (0.45, 0.65)],
        kid_r=[(0, 0), (0.50, 0.70), (0.50, 0.72), (0.48, 0.70), (0.5, 0.7)],
        seg=[40, 26, 20, 14, 10], gnarl=[0.03, 0.12, 0.16, 0.22, 0.26],
        tropism=[0.5, 0.0, 0.08, 0.10, 0.08], levels=5,
        buttress=(0.75, 6, 110), roots=(6, 8), broken=0.40, kink=0.04,
        top_broken=True,
    ),
    # A weeping tree: limbs that arch out and down, hung with long strands.
    "weeper": dict(
        height=(760, 900), r0=(32, 42), lean=5, gnarl0=0.05, tropism0=0.4,
        limbs=(5, 7), limb_t=(0.45, 0.90), limb_ang=(38, 70),
        limb_len=(0.62, 0.85), limb_r=(0.46, 0.62), reach_k=0.25,
        kids=[(0, 0), (4, 6), (4, 6), (3, 5), (0, 0)],
        kid_t=[(0, 0), (0.25, 0.95), (0.20, 0.95), (0.15, 0.95), (0, 0)],
        kid_ang=[(0, 0), (25, 55), (25, 55), (20, 45), (0, 0)],
        kid_len=[(0, 0), (0.50, 0.75), (0.55, 0.85), (0.8, 1.3), (0, 0)],
        kid_r=[(0, 0), (0.50, 0.70), (0.50, 0.70), (0.45, 0.65), (0, 0)],
        seg=[32, 24, 18, 14, 10], gnarl=[0.05, 0.10, 0.13, 0.12, 0.2],
        tropism=[0.4, 0.10, -0.15, -0.6, 0.0], levels=4,
        droop=[0.0, 0.5, 1.2, 2.5, 0.0],
        buttress=(0.45, 5, 60), roots=(4, 6), broken=0.05, kink=0.03,
    ),
    # An ancient: a huge low bole on great buttresses, splitting into three
    # stems that wander.
    "ancient": dict(
        height=(1000, 1150), r0=(84, 100), lean=3, gnarl0=0.04, tropism0=0.4,
        limbs=(3, 3), limb_t=(0.20, 0.32), limb_ang=(18, 36),
        limb_len=(1.70, 2.10), limb_r=(0.58, 0.70), reach_k=0.20,
        limb_shrink=0.0,
        kids=[(0, 0), (4, 6), (4, 6), (3, 5), (2, 3)],
        kid_t=[(0, 0), (0.30, 0.95), (0.25, 0.95), (0.20, 0.95), (0.3, 0.95)],
        kid_ang=[(0, 0), (30, 62), (28, 58), (26, 55), (22, 50)],
        kid_len=[(0, 0), (0.45, 0.66), (0.42, 0.66), (0.40, 0.62), (0.45, 0.65)],
        kid_r=[(0, 0), (0.50, 0.70), (0.50, 0.72), (0.48, 0.70), (0.5, 0.7)],
        seg=[34, 26, 20, 14, 10], gnarl=[0.04, 0.11, 0.16, 0.22, 0.26],
        tropism=[0.4, 0.12, 0.10, 0.12, 0.10], levels=5,
        buttress=(0.85, 6, 140), roots=(7, 9), broken=0.15, kink=0.05,
        trunk_frac=0.34,
    ),
    # A dead sapling: one thin stem and a few whips.
    "sapling": dict(
        height=(260, 420), r0=(5, 8), lean=10, gnarl0=0.10, tropism0=0.3,
        limbs=(2, 4), limb_t=(0.35, 0.85), limb_ang=(25, 55),
        limb_len=(0.35, 0.55), limb_r=(0.5, 0.7), reach_k=0.3,
        kids=[(0, 0), (1, 3), (1, 2), (0, 0), (0, 0)],
        kid_t=[(0, 0), (0.3, 0.9), (0.3, 0.9), (0, 0), (0, 0)],
        kid_ang=[(0, 0), (25, 55), (25, 50), (0, 0), (0, 0)],
        kid_len=[(0, 0), (0.45, 0.7), (0.45, 0.6), (0, 0), (0, 0)],
        kid_r=[(0, 0), (0.55, 0.75), (0.5, 0.7), (0, 0), (0, 0)],
        seg=[20, 14, 10, 10, 10], gnarl=[0.10, 0.18, 0.24, 0.25, 0.25],
        tropism=[0.3, 0.15, 0.12, 0.1, 0.1], levels=3,
        buttress=(0.2, 3, 15), roots=(0, 0), broken=0.2, kink=0.08,
    ),
}


def rand(rng, lo_hi):
    lo, hi = lo_hi
    return lo + (hi - lo) * rng.random()


def randi(rng, lo_hi):
    lo, hi = lo_hi
    return int(rng.integers(lo, hi + 1))


class Tree:
    """One grown tree: its branches, where a charm can hang, and the numbers
    the wood places it by."""

    def __init__(self, species, seed):
        self.species = species
        self.seed = seed
        self.sp = SPECIES[species]
        self.rng = np.random.default_rng(seed)
        self.branches = []
        self.hangs = []
        self.height = 0.0
        self.r0 = 0.0
        self.grow()

    # -- growth -------------------------------------------------------------

    def grow(self):
        sp, rng = self.sp, self.rng
        H = rand(rng, sp["height"])
        r0 = rand(rng, sp["r0"])
        self.r0 = r0
        reach = np.array([1.0, 0.0, 0.0])
        lean = math.radians(sp["lean"]) * rng.uniform(0.5, 1.0)
        # Lean toward the reach side, give or take.
        la = rng.uniform(-0.7, 0.7)
        d0 = np.array([math.sin(lean) * math.cos(la), math.cos(lean),
                       math.sin(lean) * math.sin(la)])
        trunk_len = H * sp.get("trunk_frac", 0.92)
        pts = walk(rng, (0.0, -40.0, 0.0), d0, trunk_len + 40, sp["seg"][0],
                   sp["gnarl0"], sp["tropism0"], reach, 0.06,
                   kink=sp["kink"] * 0.5, bend=0.6)
        pts = smooth(pts, 2)
        n = len(pts)
        top_r = r0 * (0.10 if not sp.get("top_broken") else 0.42)
        rad = taper(n, r0, top_r, 0.85)
        trunk = Branch(pts, rad, 0, broken=bool(sp.get("top_broken")))
        self.branches.append(trunk)
        self.height = float(pts[:, 1].max())

        # The limbs off the trunk.
        nl = randi(rng, sp["limbs"])
        ts = np.sort(rng.uniform(*sp["limb_t"], nl))
        az = rng.random() * math.tau
        T, N, B = M.frames(pts)
        s = M.arclen(pts)
        for t in ts:
            az += GOLDEN + rng.normal(0, 0.35)
            i = int(np.clip(round(t * (n - 1)), 1, n - 2))
            ang = math.radians(rand(rng, sp["limb_ang"]))
            side = math.cos(az) * N[i] + math.sin(az) * B[i]
            # Favour the reach side: blend the azimuth's direction toward it.
            side = side + reach * sp["reach_k"] * rng.uniform(0.5, 1.5)
            side = side - np.dot(side, T[i]) * T[i]
            side /= max(np.linalg.norm(side), 1e-9)
            d = math.cos(ang) * T[i] + math.sin(ang) * side
            ln = (trunk_len * rand(rng, sp["limb_len"])
                  * (1.0 - sp.get("limb_shrink", 0.45) * t))
            rr = rad[i] * rand(rng, sp["limb_r"])
            self.limb(1, pts[i], d, ln, rr, 0, reach, s[i])
        self.roots(trunk)
        self.height = float(max(b.pts[:, 1].max() for b in self.branches))
        self.hangs = self.hang_sites()
        self.vines = self.vine_sites()

    # -- where charms hang ----------------------------------------------------

    def hang_sites(self, drop=HANG_DROP, clear=HANG_CLEAR, apart=HANG_APART):
        """Where a charm can be tied: on a limb or branch thick enough to be
        seen (a tube, not a twig), where it runs near level, high enough to
        be seen from the path, with `drop` of open air below it, `clear` wide
        (a charm and its swing). The point is the branch's underside, so the
        cord starts on the bark. No two within `apart` of each other."""
        A, B, RR = [], [], []
        for b in self.branches:
            for i in range(len(b.pts) - 1):
                # Hairline twigs are no obstacle: a charm brushes through.
                if max(b.rad[i], b.rad[i + 1]) < 1.2:
                    continue
                A.append(b.pts[i])
                B.append(b.pts[i + 1])
                RR.append(max(b.rad[i], b.rad[i + 1]))
        A = np.array(A)
        B = np.array(B)
        RR = np.array(RR)
        AB = B - A
        L2 = np.maximum(np.sum(AB * AB, axis=1), 1e-9)

        def open_below(p):
            # Points down the line a charm would hang along, from below its
            # own limb: each must be clear of every branch by `clear`.
            ys = np.linspace(p[1] - clear - 40.0, p[1] - drop, 10)
            Q = np.stack([np.full(10, p[0]), ys, np.full(10, p[2])], axis=1)
            AQ = Q[:, None, :] - A[None, :, :]
            t = np.clip(np.sum(AQ * AB[None], axis=2) / L2[None], 0, 1)
            C = A[None] + AB[None] * t[..., None]
            d = np.linalg.norm(Q[:, None, :] - C, axis=2) - RR[None]
            return float(d.min()) > clear

        sites = []
        for b in self.branches:
            if b.root or b.level == 0 or b.level > 2:
                continue
            P, R = b.pts, b.rad
            n = len(P)
            if n < 4 or R[0] < 3.0:
                continue
            Tn, _, _ = M.frames(P)
            for i in range(int(n * 0.25), int(n * 0.9)):
                r = float(R[i])
                if r < 2.8 or r > 18.0 or abs(Tn[i][1]) > 0.55:
                    continue
                if not (HANG_Y[0] < P[i][1] < HANG_Y[1]):
                    continue
                p = P[i] - np.array([0.0, r * 0.9, 0.0])
                if any(np.linalg.norm(p - q["p"]) < apart for q in sites):
                    continue
                if not open_below(p):
                    continue
                t = Tn[i] / max(np.linalg.norm(Tn[i]), 1e-9)
                sites.append({"p": p, "axis": P[i].copy(), "r": r, "t": t})
        return sites

    # -- what hangs from the limbs ---------------------------------------------

    def vine_sites(self):
        """Strands hanging from the limbs, as in a wood gone wild: from
        points along limbs and branches with room below, each a length that
        stops short of the ground."""
        rng = np.random.default_rng(self.seed + 4242)
        out = []
        for b in self.branches:
            if b.root or b.level == 0 or b.level > 2:
                continue
            P, R = b.pts, b.rad
            n = len(P)
            if n < 4:
                continue
            for i in range(int(n * 0.2), n - 1):
                if R[i] < 1.0 or rng.random() > VINE_ODDS:
                    continue
                if P[i][0] > VINE_X:
                    continue
                y = P[i][1]
                if y < 260:
                    continue
                ln = min(rng.uniform(*VINE_LEN), y - 140.0)
                if ln < 60:
                    continue
                out.append((P[i] - np.array([0.0, R[i] * 0.8, 0.0]), ln,
                            rng.uniform(0.7, 1.3), rng.random()))
        return out

    def limb(self, level, start, d, length, r, parent, reach, v0=0.0):
        sp, rng = self.sp, self.rng
        droop = sp.get("droop", [0] * 5)[level]
        broken = rng.random() < sp["broken"] * (1.0 if level <= 2 else 0.3)
        if broken:
            length *= rng.uniform(0.35, 0.7)
        pts = walk(rng, start, d, length, sp["seg"][level], sp["gnarl"][level],
                   sp["tropism"][level], reach, sp["reach_k"] * 0.4,
                   kink=sp["kink"], droop=droop)
        pts = smooth(pts, 2)
        n = len(pts)
        r_end = r * (0.38 if broken else 0.10)
        rad = taper(n, r, r_end, 0.9)
        # A collar where it leaves its parent.
        k = min(n, 3)
        rad[:k] *= np.linspace(1.22, 1.0, k)
        b = Branch(pts, rad, level, parent, broken=broken)
        b.v0 = v0
        idx = len(self.branches)
        self.branches.append(b)

        if broken or level + 1 >= sp["levels"]:
            return
        lo, hi = sp["kids"][level + 1]
        if hi <= 0:
            return
        nk = randi(rng, (lo, hi))
        ts = np.sort(rng.uniform(*sp["kid_t"][level + 1], nk))
        T, N, B = M.frames(pts)
        s = M.arclen(pts)
        az = rng.random() * math.tau
        for t in ts:
            az += GOLDEN + rng.normal(0, 0.4)
            i = int(np.clip(round(t * (n - 1)), 1, n - 1))
            if rad[i] < 0.45:
                continue
            ang = math.radians(rand(rng, sp["kid_ang"][level + 1]))
            side = math.cos(az) * N[i] + math.sin(az) * B[i]
            dd = math.cos(ang) * T[i] + math.sin(ang) * side
            ln = length * rand(rng, sp["kid_len"][level + 1]) * (1.0 - 0.35 * t)
            rr = rad[i] * rand(rng, sp["kid_r"][level + 1])
            if ln < 12:
                continue
            self.limb(level + 1, pts[i], dd, ln, rr, idx, reach, v0 + s[i])

    def roots(self, trunk):
        """Roots out of the buttresses: running out over the ground and
        diving into it."""
        sp, rng = self.sp, self.rng
        nr = randi(rng, sp["roots"])
        if nr <= 0:
            return
        az0 = rng.random() * math.tau
        r0 = trunk.rad[0]
        for k in range(nr):
            a = az0 + k * math.tau / nr + rng.normal(0, 0.25)
            d = np.array([math.cos(a), -0.10, math.sin(a)])
            start = np.array([math.cos(a) * r0 * 0.5, rng.uniform(10, 30),
                              math.sin(a) * r0 * 0.5])
            ln = r0 * rng.uniform(2.2, 4.0)
            pts = walk(rng, start, d, ln, 14, 0.10, -0.55, None, 0.0, bend=0.4)
            pts = smooth(pts, 2)
            n = len(pts)
            rad = taper(n, r0 * rng.uniform(0.36, 0.5), r0 * 0.05, 0.8)
            b = Branch(pts, rad, 1, 0, root=True)
            self.branches.append(b)
        self.lobes = (az0, nr)

    # -- skinning -------------------------------------------------------------

    def mesh(self, lod=0):
        """The tree as a strip. `lod` 1 is the far version: fewer sides, no
        fine twigs."""
        sp, rng = self.sp, np.random.default_rng(self.seed + 999)
        strip = M.Strip()
        tint = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.85, 1.05)
        twig_tint = tint * 0.80
        H = max(self.height, 1.0)
        but_f, but_n, but_h = sp["buttress"]
        az0, nr = getattr(self, "lobes", (0.0, 0))
        lobe_az = [az0 + k * math.tau / max(nr, 1) for k in range(max(nr, but_n))]

        for bi, b in enumerate(self.branches):
            P, R = b.pts, b.rad
            r_base = float(R[0])
            y = P[:, 1]
            # Baked occlusion: the foot of the tree and the crotches are
            # darker, as is the inside of the crown.
            ao = 0.45 + 0.55 * np.clip((y + 20) / 160.0, 0, 1) ** 0.7
            rxz = np.sqrt(P[:, 0] ** 2 + P[:, 2] ** 2)
            ao *= 1.0 - 0.22 * np.exp(-rxz / 220.0) * np.clip((y - 200) / 300, 0, 1)
            if b.level > 0 and not b.root:
                s = M.arclen(P)
                ao *= 0.62 + 0.38 * np.clip(s / max(3.0 * r_base, 1.0), 0, 1)
            # The wind moves the outer branches; the trunk and roots never.
            if b.root or b.level == 0:
                sway = np.zeros(len(P))
            else:
                sway = np.clip((b.level - 1) * 0.22 + np.linspace(0, 0.25, len(P)), 0, 1)
                sway *= np.clip(y / H, 0.2, 1.0)
            conform = np.zeros(len(P))
            if b.root:
                conform = np.clip(1.0 - (y + 10) / 60.0, 0, 1) * 0 + 1.0
            elif b.level == 0:
                conform = np.clip(1.0 - (y + 40) / 120.0, 0, 1)

            if r_base < RIBBON_R:
                if lod >= 1:
                    continue
                strip.add(M.ribbon(P, R, twig_tint, ao=ao, sway=sway))
                continue
            if lod >= 1 and b.level >= 3:
                continue

            sides = int(np.clip(round(r_base * 0.42 + 4), 4, 20))
            if lod >= 1:
                sides = max(4, sides // 2)
            lobe = None
            if b.level == 0 and not b.root and but_f > 0:
                def lobe(th, i, P=P, R=R):
                    h = P[i, 1] + 40.0
                    f = but_f * math.exp(-max(h, 0.0) / but_h)
                    acc = np.zeros_like(th)
                    for a in lobe_az:
                        da = np.angle(np.exp(1j * (th - a)))
                        acc += np.exp(-(da / 0.32) ** 2)
                    return 1.0 + f * (0.35 + 1.4 * acc)
            strip.add(M.tube(P, R, sides, tint, ao=ao, lobe=lobe,
                             conform=conform, sway=sway, v0=b.v0,
                             u_tile=170.0, v_tile=340.0))
            # A broken limb ends in a jagged cap.
            if b.broken:
                T, N, B = M.frames(P)
                strip.add(M.cap(P[-1], T[-1], N[-1], B[-1], float(R[-1]),
                                sides, tint * 0.9, ao=float(ao[-1]) * 0.8,
                                jag=0.9, rng=rng, sway=float(sway[-1])))
            else:
                # A thin tube's tip goes on as a short ribbon, so the twig
                # tapers to nothing rather than ending in a stub.
                if lod == 0 and float(R[-1]) < RIBBON_R * 2.5:
                    T, N, B = M.frames(P)
                    tip_len = max(10.0, float(R[-1]) * 10)
                    tip = np.array([P[-1], P[-1] + T[-1] * tip_len * 0.5,
                                    P[-1] + T[-1] * tip_len])
                    strip.add(M.ribbon(tip, [float(R[-1]), float(R[-1]) * 0.5, 0.05],
                                       twig_tint, ao=float(ao[-1]),
                                       sway=float(sway[-1])))
        if lod == 0:
            irng = np.random.default_rng(self.seed + 777)
            if irng.random() < IVY_ODDS.get(self.species, 0.0):
                for part in self.ivy(irng):
                    strip.add(part)
            # Leafy vines hanging from the limbs: a stem that curls a little
            # as it falls and turns up at its end, ivy leaves along it.
            vrng = np.random.default_rng(self.seed + 5151)
            vt = np.array([0.30, 0.32, 0.22]) * tint
            for top, ln, w, ph in self.vines:
                k = max(4, int(ln / 14))
                t = np.linspace(0.0, 1.0, k)
                curl = np.stack([np.sin(t * 2.6 + ph * 6.0) * ln * 0.06,
                                 -t * ln + ln * 0.08 * t ** 6,
                                 np.cos(t * 2.1 + ph * 6.0) * ln * 0.05], 1)
                pts = top[None, :] + curl
                strip.add(M.ribbon(pts, (0.75 - 0.3 * t) * w, vt, ao=0.85,
                                   sway=0.25 + 0.75 * t))
                for j in range(1, k):
                    f = j / (k - 1)
                    for side in (-1.0, 1.0):
                        if vrng.random() > 0.8:
                            continue
                        c = pts[j] + np.array([side * 3.0, 0.0, vrng.normal(0, 2.0)])
                        size = vrng.uniform(8.0, 12.0) * (1.0 - 0.25 * f)
                        yaw = vrng.uniform(0.0, math.tau)
                        nrm = np.array([math.cos(yaw), 0.35, math.sin(yaw)])
                        nrm /= np.linalg.norm(nrm)
                        right = np.cross(np.array([0.0, 1.0, 0.0]), nrm)
                        right /= max(np.linalg.norm(right), 1e-9)
                        up = np.cross(nrm, right)
                        h = size * 0.5
                        corners = (c - right * h - up * h, c + right * h - up * h,
                                   c + right * h + up * h, c - right * h + up * h)
                        cell = "ivy%d" % vrng.integers(0, 4)
                        sw = 0.25 + 0.75 * f
                        strip.add(M.card(corners, TX.cell_rect(cell, 0.04),
                                         np.array([1.0, 1.0, 1.0]) * vrng.uniform(0.75, 1.05),
                                         normal=nrm, ao=0.9, sway=(sw, sw, sw, sw)))
        return strip

    def ivy(self, rng):
        """Ivy climbing the trunk: a stem winding up from near the foot,
        its leaves laid on the bark round it, thinning out toward the top.
        Leaves are cards from the foliage sheet's ivy cells."""
        trunk = self.branches[0]
        P, R = trunk.pts, trunk.rad
        s = M.arclen(P)
        T, N, B = M.frames(P)
        y0 = 25.0
        i0 = int(np.searchsorted(P[:, 1], y0))
        if i0 >= len(P) - 2:
            return []
        top = min(rng.uniform(300, 820), float(P[-1, 1]) * 0.8)
        th = rng.random() * math.tau
        turn = rng.uniform(0.004, 0.009) * (1 if rng.random() < 0.5 else -1)
        stem, leaves = [], []
        a = float(s[i0])
        while True:
            i = int(np.clip(np.searchsorted(s, a) - 1, 0, len(P) - 2))
            f = (a - s[i]) / max(s[i + 1] - s[i], 1e-6)
            c = P[i] + (P[i + 1] - P[i]) * f
            if c[1] > top:
                break
            r = R[i] + (R[i + 1] - R[i]) * f
            # The buttresses swell the foot.
            r *= 1.0 + 0.5 * math.exp(-max(c[1] + 40.0, 0.0) / 90.0)
            th += turn * 9.0 + rng.normal(0, 0.05)
            out = math.cos(th) * N[i] + math.sin(th) * B[i]
            p = c + out * (r + 1.2)
            stem.append(p)
            up_frac = (c[1] - y0) / max(top - y0, 1.0)
            for k in range(2):
                if rng.random() > 0.85 - 0.45 * up_frac:
                    continue
                aa = th + rng.normal(0, 0.35)
                o2 = math.cos(aa) * N[i] + math.sin(aa) * B[i]
                lc = c + o2 * (r + 2.2) + T[i] * rng.normal(0, 6.0)
                size = rng.uniform(9.0, 15.0) * (1.0 - 0.3 * up_frac)
                right = np.cross(o2, T[i])
                right /= max(np.linalg.norm(right), 1e-9)
                tilt = rng.normal(0, 0.5)
                up = T[i] * math.cos(tilt) + right * math.sin(tilt)
                right = np.cross(o2, up)
                nrm = o2 + up * rng.uniform(0.0, 0.5)
                nrm /= np.linalg.norm(nrm)
                h = size * 0.5
                corners = (lc - right * h - up * h, lc + right * h - up * h,
                           lc + right * h + up * h, lc - right * h + up * h)
                cell = "ivy%d" % rng.integers(0, 4)
                tint = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.75, 1.1)
                v = M.card(corners, TX.cell_rect(cell, 0.04), tint,
                           normal=nrm, ao=0.9, sway=(0.05, 0.08, 0.1, 0.12))
                leaves.append(v)
            a += 9.0
        parts = []
        if len(stem) >= 2:
            st = np.array(stem)
            parts.append(M.ribbon(st, np.full(len(st), 1.1), np.array([0.30, 0.32, 0.22]),
                                  ao=0.8))
        parts.extend(leaves)
        return parts

    def info(self):
        """What the wood needs to place it: its height, the trunk's radius
        at the foot, how far it spreads from its axis (for culling), and its
        hang points."""
        allp = np.concatenate([b.pts for b in self.branches])
        spread = float(np.sqrt(allp[:, 0] ** 2 + allp[:, 2] ** 2).max())
        hangs = [tuple(float(v) for v in (*h["p"], h["r"], *h["t"]))
                 for h in self.hangs]
        return dict(height=self.height, r0=self.r0, spread=spread, hangs=hangs)
