#!/usr/bin/env python3
"""The 3D wood: Velka's forest of the dead rebuilt as real geometry
(`scripts/bg_wood` draws it).

Writes:

- the wood's textures, as sprites of their own texture page (`For3D`) in
  the mipmapped `Wood` group, so the GPU repeats them: bark, the forest
  floor and the path (each with a normal map), the moon, clouds, a glow, a
  star and mist puffs;
- the trees, grown in `tools/wood_trees.py` and skinned in
  `tools/wood_mesh.py`, as zlib-compressed vertex strips in
  `datafiles/wood/` (GameMaker loads each straight into a vertex buffer),
  with the charms and their rope (`tools/wood_charms.py`) and the ground
  cover and standing stones (`tools/wood_props.py`) beside them;
- `scripts/wood_table`: the list of meshes and what the wood places them by
  (height, spread, where a charm can hang);
- previews in `tools/_preview/wood_*.png`.

Usage:
    python tools/make_wood.py            # everything
    python tools/make_wood.py --tex      # textures only
    python tools/make_wood.py --mesh     # meshes and the table only
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new
import wood_charms as WC
import wood_mesh as M
import wood_props as WP
import wood_tex as TX
import wood_trees as WT

ROOT = A.ROOT
DATA = os.path.join(ROOT, "datafiles", "wood")
GROUP = "Wood"
FOLDER = "Sprites/wood"

# The trees the wood is planted with: (species, seed). The wood picks among
# them by species (`wood_table`'s `species`), so the order is free.
TREES = [
    ("oak", 101), ("oak", 202), ("oak", 303),
    ("crook", 111), ("crook", 212),
    ("snag", 121), ("snag", 222),
    ("weeper", 131), ("weeper", 232),
    ("ancient", 141),
    ("sapling", 151), ("sapling", 252),
]


def sprite(name, img):
    gm_new.sprite(name, [img], origin="topleft", folder=FOLDER,
                  texgroup=GROUP, for3d=True)


def make_textures():
    os.makedirs(A.PREVIEW, exist_ok=True)
    print("bark")
    alb, nrm, _ = TX.bark(1024)
    sprite("spr_wood_bark", alb)
    sprite("spr_wood_bark_n", nrm.convert("RGBA"))
    print("floor")
    flo, flo_n = TX.litter(1024, 21)
    sprite("spr_wood_floor", flo)
    sprite("spr_wood_floor_n", flo_n.convert("RGBA"))
    print("path")
    pat, pat_n = TX.litter(1024, 61, path=True)
    sprite("spr_wood_path", pat)
    sprite("spr_wood_path_n", pat_n.convert("RGBA"))
    print("sky")
    sprite("spr_wood_moon", TX.moon(1024))
    sprite("spr_wood_cloud", TX.clouds(1024, 512))
    sprite("spr_wood_glow", TX.glow(256))
    sprite("spr_wood_star", TX.star(64))
    sprite("spr_wood_puff", TX.puffs(512))
    sprite("spr_wood_charm", TX.charm_sheet(512))
    sprite("spr_wood_foliage", TX.foliage_sheet())
    sprite("spr_wood_flat_n", TX.flat_normal(8))
    sprite("spr_wood_ring", TX.ring(512))

    sheet = [alb.convert("RGB"), nrm, flo.convert("RGB"), flo_n,
             pat.convert("RGB"), pat_n]
    A.preview([im.convert("RGBA").resize((384, 384)) for im in sheet],
              os.path.join(A.PREVIEW, "wood_textures.png"), cols=6,
              labels=["bark", "bark n", "floor", "floor n", "path", "path n"])


def gml_num(v):
    return "%.1f" % v


# A charm hangs on the path side of its tree (local +x, which the wood turns
# toward the path).
HANG_SIDE = 0.10


def hang_points(info):
    """The tree's hang sites a charm may use (`Tree.hang_sites`), the
    furthest over the path first."""
    out = [h for h in info["hangs"] if h[0] > HANG_SIDE * info["spread"]]
    out.sort(key=lambda h: -h[0])
    return out[:12]


def make_meshes():
    os.makedirs(DATA, exist_ok=True)
    rows = []
    total = 0
    for i, (sp, seed) in enumerate(TREES):
        tree = WT.Tree(sp, seed)
        info = tree.info()
        near = tree.mesh(0).build()
        far = tree.mesh(1).build()
        name = "tree_%02d" % i
        for suffix, v in (("", near), ("_far", far)):
            fn = name + suffix + ".vbuf"
            data = M.pack(v)
            with open(os.path.join(DATA, fn), "wb") as f:
                f.write(data)
            gm_new.included_file(fn, "datafiles/wood")
            total += len(data)
        hangs = hang_points(info)
        rows.append((name, sp, info, len(near), len(far), hangs))
        print("%s %-8s verts %6d far %5d  h %5.0f spread %4.0f hangs %d"
              % (name, sp, len(near), len(far), info["height"],
                 info["spread"], len(hangs)))
    charms = []
    for name, v, glow, drop in WC.build_all():
        fn = "charm_%s.vbuf" % name
        data = M.pack(v)
        with open(os.path.join(DATA, fn), "wb") as f:
            f.write(data)
        gm_new.included_file(fn, "datafiles/wood")
        total += len(data)
        charms.append((name, fn, glow, drop, len(v)))
        print("charm %-8s verts %5d glow %s" % (name, len(v),
                                                 tuple(round(float(g), 1) for g in glow)))
    # The ground cover: patches, and standing stones.
    patches, stones = WP.build_all()
    props = []
    for k, (kind, seed, v, rad) in enumerate(patches):
        fn = "patch_%02d.vbuf" % k
        data = M.pack(v)
        with open(os.path.join(DATA, fn), "wb") as f:
            f.write(data)
        gm_new.included_file(fn, "datafiles/wood")
        total += len(data)
        props.append((fn, kind, rad))
        print("patch %s %-7s verts %5d  radius %4.0f" % (fn, kind, len(v), rad))
    for k, (v, h) in enumerate(stones):
        fn = "stone_%02d.vbuf" % k
        data = M.pack(v)
        with open(os.path.join(DATA, fn), "wb") as f:
            f.write(data)
        gm_new.included_file(fn, "datafiles/wood")
        total += len(data)
        props.append((fn, "stone", h))
        print("stone %s verts %5d  height %4.0f" % (fn, len(v), h))

    # The rope wound round a limb where a charm is tied.
    data = M.pack(WC.rope_wrap())
    with open(os.path.join(DATA, "charm_wrap.vbuf"), "wb") as f:
        f.write(data)
    gm_new.included_file("charm_wrap.vbuf", "datafiles/wood")
    total += len(data)
    # A charm kind that is no longer made leaves no file behind.
    made = {"charm_%s.vbuf" % c[0] for c in charms} | {"charm_wrap.vbuf"}
    for fn in os.listdir(DATA):
        if fn.startswith("charm_") and fn not in made:
            os.remove(os.path.join(DATA, fn))
            drop_included(fn)
    print("mesh data %.2f MB" % (total / 1e6))
    write_table(rows, charms, props)


def drop_included(fn):
    """Take a file out of the project's included files."""
    text = gm_new.read(gm_new.YYP)
    lines = [ln for ln in text.split("\n")
             if not ('"$GMIncludedFile"' in ln and '"%s"' % fn in ln)]
    gm_new.write(gm_new.YYP, "\n".join(lines))


def write_table(rows, charms, props):
    lines = [
        "/// @desc The 3D wood's meshes -- GENERATED by tools/make_wood.py. Do",
        "///       not edit.",
        "///",
        "/// Each tree is a vertex strip in `datafiles/wood/` (the near version",
        "/// and a far one without the fine twigs), and what the wood places it",
        "/// by: its species, its height, the trunk's radius at the foot, how far",
        "/// it spreads from its axis, and the points a charm can hang from, in",
        "/// its own space (y up, the foot at the origin, reaching toward +x):",
        "/// each `[x, y, z, r, tx, ty, tz]`, the underside of a limb of radius",
        "/// `r` running along `t`. The charms are triangle lists (the trees are",
        "/// strips).",
        "",
        "function wood_table_init() {",
        "    global.wood_trees = [",
    ]
    for name, sp, info, nv, nf, hangs in rows:
        hl = ", ".join("[%s]" % ", ".join(gml_num(c) if i < 4 else "%.3f" % c
                                           for i, c in enumerate(h))
                       for h in hangs[:24])
        lines.append('        { file: "wood/%s.vbuf", far: "wood/%s_far.vbuf",'
                     % (name, name))
        lines.append('          species: "%s", height: %s, r0: %s, spread: %s,'
                     % (sp, gml_num(info["height"]), gml_num(info["r0"]),
                        gml_num(info["spread"])))
        lines.append("          hangs: [%s] }," % hl)
    lines.append("    ];")
    lines.append("")
    lines.append("    // The charms: each hangs from its origin (where its cord is tied),")
    lines.append("    // down -y, facing -z; `glow` is where its light is, in its own space.")
    lines.append("    global.wood_charms = [")
    for name, fn, glow, drop, nv in charms:
        lines.append('        { name: "%s", file: "wood/%s", glow: [%s, %s, %s], drop: %s },'
                     % ((name, fn) + tuple(gml_num(float(g)) for g in glow)
                        + (gml_num(drop),)))
    lines.append("    ];")
    lines.append("")
    lines.append("    // The rope wound round a limb where a charm is tied, round its x axis")
    lines.append("    // at radius 1 (the wood scales it by the limb's radius).")
    lines.append('    global.wood_wrap = "wood/charm_wrap.vbuf";')
    lines.append("")
    lines.append("    // The ground cover: patches of small things (a triangle list each,")
    lines.append("    // `size` the radius it spreads to) and standing stones (`size` their")
    lines.append("    // height), each in its own space with the ground at y = 0.")
    lines.append("    global.wood_props = [")
    for fn, kind, size in props:
        lines.append('        { file: "wood/%s", kind: "%s", size: %s },'
                     % (fn, kind, gml_num(size)))
    lines.append("    ];")
    lines.append("}")
    lines.append("")
    body = "\n".join(lines)
    gm_new.script("wood_table", body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", action="store_true")
    ap.add_argument("--mesh", action="store_true")
    args = ap.parse_args()
    both = not (args.tex or args.mesh)
    gm_new.texture_group(GROUP, mips=6, autocrop=False, border=0)
    gm_new.folder(FOLDER)
    if args.tex or both:
        make_textures()
    if args.mesh or both:
        make_meshes()


if __name__ == "__main__":
    main()
