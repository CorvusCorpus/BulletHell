#!/usr/bin/env python3
"""The system sprites: sparks, glows, rings, lasers, shards, and the two marks
that tell the player where they actually are.

Everything here is drawn white or near-white and **tinted at draw time**, which
is why there is one bloom and not fourteen. A tint is one multiply on a sprite
the texture page already holds; a hue baked per colour would be fourteen copies
of the same disc.

The exceptions are the three pickups, which are baked in their own colours
because they are **objects** rather than light. They are cut bodies, drawn with
`art_common`'s `Cut` and shaded by `cut_shade` as the bullets are -- and they
are two materials at once, a coloured stone in a gilt setting, which is the one
thing a tint could not have produced under any circumstances: a tint is a
multiply over the whole sprite, and the housing has to stay brass while the
stone changes.

Usage:
    python tools/make_fx.py
"""
import math
import os
import sys

import numpy as np
from PIL import ImageChops, Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import gm_new

SS = A.SS


# ---------------------------------------------------------------------------
# Light
# ---------------------------------------------------------------------------

def make_bloom(size=128):
    """The soft round glow everything additive is built out of."""
    return A.soft_glow(size, (255, 255, 255), falloff=2.9)


def make_spark(w=34, h=14):
    """A streak. Oriented, so it points right and `fx_spark` can hand it a
    direction directly."""
    dx, dy, _ = A.grid(w, h)
    # An ellipse in a stretched metric, brightest at the leading (right) end,
    # so a spark reads as travelling rather than as a floating pill.
    r = np.hypot(dx / (w / 2.0), dy / (h / 2.0))
    a = np.clip(1 - r, 0, 1) ** 1.5
    lead = np.clip(0.45 + 0.55 * (dx / (w / 2.0) * 0.5 + 0.5), 0, 1)
    body = np.zeros((h, w, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a * lead)


def make_ring(size=256, thick=0.055):
    """A shockwave: a bright annulus with light falling off both ways."""
    _, _, r = A.grid(size, size)
    edge = 0.86
    d = np.abs(r - edge)
    a = np.clip(1 - d / thick, 0, 1) ** 1.6
    # A little haze inside the ring, so the wave looks like it is pushing air
    # rather than being a wire hoop.
    a = np.maximum(a, np.clip(1 - r / edge, 0, 1) ** 5 * 0.30)
    a = np.where(r >= 1.0, 0, a)
    body = np.zeros((size, size, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a)


def make_laser_body(w=64, h=48):
    """A cross-section, uniform along its length, so it can be stretched to any
    length without the texture stretching with it.

    **The origin is middle-left**, so `draw_sprite_ext(x, y, len/w, wid/h, dir)`
    lays the bar from (x, y) forward. Centring it would put half of every beam
    behind the thing that cast it.
    """
    ys = np.arange(h, dtype=np.float32)
    t = np.abs(ys - (h - 1) / 2.0) / ((h - 1) / 2.0)
    prof = np.clip(1 - t, 0, 1) ** 1.9
    prof = prof * 0.55 + np.clip(1 - t / 0.30, 0, 1) ** 2 * 0.45
    a = np.repeat(prof[:, None], w, axis=1)
    body = np.zeros((h, w, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    return A.from_arrays(body, a)


def make_laser_node(size=48):
    return A.soft_glow(size, (255, 255, 255), falloff=2.1)


# ---------------------------------------------------------------------------
# The player's marks
# ---------------------------------------------------------------------------

def make_pshot(w=72, h=30):
    """Szuix's shot: a bolt of imp-fire with a hot head and a drawn-out tail.

    **It points right**, like every oriented thing in this project, because
    GameMaker's angle 0 is right -- see the note at the top of `make_bullets`.

    Three times the area the first version had. At 34x14 it was a sliver: two
    of them left his hands sixty times a second and what reached the screen was
    a faint blue dotted line, which for the thing the player spends the entire
    game holding down is far too little to show for it. A shot has to read as
    something *thrown*.

    Drawn head-first rather than as a symmetric lens. A symmetric bolt has no
    direction and reads as a bead; a head with a tail behind it reads as
    travel, and travel is the whole of what the player is being told.
    """
    ss = 3
    W, H = w * ss, h * ss
    dx, dy, _ = A.grid(W, H)

    # x from 0 at the tail to 1 at the head. The profile is fat just behind the
    # head and tapers away, so the silhouette is a teardrop lying on its side.
    tx = np.clip((dx + W / 2.0) / W, 0, 1)
    half = (H / 2.0) * np.clip(np.sin(np.pi * tx ** 0.62), 0, 1) ** 0.7
    ry = np.abs(dy) / np.maximum(half, 1e-6)

    a = np.clip(1 - ry, 0, 1) ** 0.75
    # The head is solid; the last quarter of the tail thins into nothing, which
    # is what stops the bolt ending in a blunt edge.
    a *= np.clip(tx / 0.22, 0, 1) ** 1.2

    # A white core running down the axis, brightest at the head. This is the
    # same core-inside-rim rule the bullets are built on, and it is here for
    # the same reason: a flat blue bolt over a lit background is a smudge.
    core = np.clip(1 - ry / 0.52, 0, 1) ** 1.6 * np.clip(tx / 0.5, 0, 1) ** 0.8

    body = np.zeros((H, W, 3), dtype=np.float32)
    body[:] = A.SZUIX_LIT
    body += core[..., None] * 210.0
    # ...and a hotter kick right at the head, so the front of the bolt is where
    # the eye lands rather than the middle of it.
    nose = np.clip(1 - np.hypot((dx - W * 0.30) / (W * 0.20),
                                dy / (H * 0.34)), 0, 1) ** 2
    body += nose[..., None] * 150.0

    img = A.from_arrays(body, a)
    return img.resize((w, h), Image.LANCZOS)


def make_hitbox(size=32):
    """**The truth about where the player is.**

    Drawn at exactly `PLAYER_R * 2` by the game, so what is shown is what is
    tested. A ring rather than a disc: a solid dot at eight pixels across is a
    smudge, and the ring's hole is what makes the centre findable.
    """
    _, _, r = A.grid(size * SS, size * SS)
    outer = np.clip(1 - np.abs(r - 0.78) / 0.20, 0, 1) ** 1.4
    core = np.clip(1 - r / 0.34, 0, 1) ** 1.6
    a = np.clip(outer + core, 0, 1)
    body = np.zeros((size * SS, size * SS, 3), dtype=np.float32)
    body[:] = (255, 255, 255)
    # A pink cast on the ring only, so it can never be mistaken for a bullet's
    # white core -- the one white thing on the field the player must not dodge.
    body[..., 1] -= (outer * 90)[...]
    body[..., 2] -= (outer * 40)[...]
    img = A.from_arrays(body, a)
    return img.resize((size, size), Image.LANCZOS)


def make_focus_ring(size=96):
    """The reticle that appears while focused. Ticks rather than a plain
    circle, so it reads as an instrument being brought to bear."""
    cv = A.Canvas(size, size)
    c = size / 2.0
    cv.ellipse([c - size * 0.40, c - size * 0.40, c + size * 0.40, c + size * 0.40],
               outline=(255, 255, 255, 170), width=1.6)
    cv.ellipse([c - size * 0.27, c - size * 0.27, c + size * 0.27, c + size * 0.27],
               outline=(255, 255, 255, 90), width=1.0)
    for i in range(8):
        ang = math.radians(i * 45)
        r0, r1 = size * 0.40, size * 0.49
        cv.line([(c + math.cos(ang) * r0, c + math.sin(ang) * r0),
                 (c + math.cos(ang) * r1, c + math.sin(ang) * r1)],
                fill=(255, 255, 255, 200), width=2.2)
    return cv.finish()


# ---------------------------------------------------------------------------
# Pickups
# ---------------------------------------------------------------------------

# The pickup. Small on purpose -- see `make_item`.
ITEM_W, ITEM_H = 30, 24

# A blunt octagon and the stone set inside it. **Nothing here comes to a
# point**, which is the one hard rule the shape has to obey.
_BEZEL = [(6.5, 2.0), (22.5, 2.0), (27.0, 6.5), (27.0, 16.5), (22.5, 21.0),
          (6.5, 21.0), (2.0, 16.5), (2.0, 6.5)]
_STONE = [(8.4, 4.4), (20.6, 4.4), (24.6, 8.4), (24.6, 14.6), (20.6, 18.6),
          (8.4, 18.6), (4.4, 14.6), (4.4, 8.4)]
_TABLE = [(22.0, 11.5), (14.5, 7.0), (7.0, 11.5), (14.5, 16.0)]


def make_item(rim):
    """A pickup: a dark cut stone in a gilt bezel.

    **Four goes, and each failure was a different way of drawing a bullet.**
    The original was five flat polygons with a highlight line -- a pentagon
    token in three tints. The second was a cut quartz point, which was a bullet
    that happened to be collectable: same `Cut`, same saturated hue, same hot
    core, and against Ziggy's amber volleys a gold one was indistinguishable.
    The third was a jewelled pendant, and being handsome was the problem twice
    over -- **bright and pointed downward**, which is to say pointed at the
    player, which is what a bullet *is*; and at 42x46 larger than every bullet
    on the field, so a shower of them after a bomb hid the pattern underneath.
    The fourth was flat enamel, which fixed all of that and stopped reading as
    a gemstone at all.

    So: still a cut stone, and none of the four things that make a cut stone
    read as ammunition.

    - **Small.** Thirty by twenty-four of drawing, smaller than the `orb` half
      this boss's patterns are made of. It is drawn *over* the field, so the
      near-parallax rule applies: nothing that is not a bullet may be big
      enough to hide one.
    - **Blunt.** No point anywhere. A shape that comes to a point aimed down
      the screen is aimed at the player, and nobody is going to stop mid-dodge
      to check whether this particular one is friendly.
    - **Dark.** The stone is the hue at under half strength, which puts the
      whole token below the value of anything being dodged. Every point of
      brightness out here is a point the bullets no longer have.
    - **Lit rather than emissive, and that is the rule worth keeping.** Every
      bullet in the game is a light: no direction to its brightness, and a
      white core burning in the middle of it. This has no core at all and one
      small hard glint up and to the left -- an *object catching* light. That
      is precisely the specular this whole redesign took off the bullets, put
      back on the one thing that should have had it, and it inverts the single
      most recognisable property of a bullet in about four pixels.

    What makes it *findable* is not the token, it is the soft additive bloom
    `item_draw` lays under it. That is the right division of labour: a coloured
    glow is a mark the scenery makes constantly and no bullet can make at all,
    so it attracts without ever being mistaken for something to dodge.

    The bezel is gilt because gilt is the console's palette and the console
    belongs to the player rather than to the stage -- a pickup is loot Szuix is
    taking, so it wears his furniture. It is also a colour no bullet can reach:
    every hue in `BULLET_HUES` is above 240 in its dominant channel and this is
    a muted brass.
    """
    bezel = A.Cut(ITEM_W, ITEM_H)
    bezel.poly("body", _BEZEL)
    bezel.line("groove", _STONE + [_STONE[0]], 1.1)
    bezel.line("core", [(10.5, 3.2), (18.5, 3.2)], 0.9, v=120)
    bezel.blur("core", 0.40)

    stone = A.Cut(ITEM_W, ITEM_H)
    stone.poly("body", _STONE)
    # The crown: a table with eight facets breaking away to the girdle. Dense
    # for a stone twenty pixels across, and that density *is* the read -- a cut
    # gem has no curvature anywhere, and what the eye takes for sparkle is
    # flat planes disagreeing about which way they face.
    stone.poly("bevel", _TABLE, v=70)
    stone.line("groove", _TABLE + [_TABLE[0]], 1.0)
    for (tx, ty), corners in ((_TABLE[0], (_STONE[2], _STONE[3])),
                              (_TABLE[1], (_STONE[0], _STONE[1])),
                              (_TABLE[2], (_STONE[6], _STONE[7])),
                              (_TABLE[3], (_STONE[4], _STONE[5]))):
        for c in corners:
            stone.line("groove", [(tx, ty), c], 0.9)
    # The glint. **No `core` layer anywhere on this sprite**: a core goes to
    # white, and white in the middle of a shape is the one mark every bullet in
    # the game carries. A second, brighter `bevel` is a highlight on a facet
    # instead -- warm, hard-edged, and four pixels of it.
    stone.poly("bevel", [(10.2, 10.5), (13.8, 8.6), (14.8, 9.5),
                         (11.2, 11.4)], v=255)

    body = A.over(A.cut_shade(bezel.parts(), A.GILT, lit_t=0.06, bevel_t=0.20,
                              deep_t=0.26),
                  A.cut_shade(stone.parts(), A.shade(rim, -0.46), lit_t=0.0,
                              bevel_t=0.74, deep_t=0.44, groove_k=0.42))
    return A.cut_finish(body, ITEM_W, ITEM_H, rim,
                        contour=2.0, bloom=0.34, bloom_r=2.4)


# ---------------------------------------------------------------------------
# The boss sigil
# ---------------------------------------------------------------------------

def make_sigil(size=320):
    """The magic circle under a boss.

    Drawn as *rings and runes* rather than as a picture, because it is tinted
    to whoever is standing on it and stretched into an ellipse by the game --
    anything representational would shear.
    """
    cv = A.Canvas(size, size)
    c = size / 2.0
    for rad, wid, alpha in ((0.47, 2.4, 190), (0.41, 1.0, 110),
                            (0.28, 1.6, 150), (0.10, 1.0, 90)):
        r = size * rad
        cv.ellipse([c - r, c - r, c + r, c + r],
                   outline=(255, 255, 255, alpha), width=wid)

    # Ticks round the outer ring, and a ring of glyph-like marks inside it.
    for i in range(36):
        ang = math.radians(i * 10)
        r0 = size * (0.44 if i % 3 else 0.41)
        r1 = size * 0.47
        cv.line([(c + math.cos(ang) * r0, c + math.sin(ang) * r0),
                 (c + math.cos(ang) * r1, c + math.sin(ang) * r1)],
                fill=(255, 255, 255, 150), width=1.4)

    rnd = np.random.default_rng(11)
    for i in range(12):
        ang = math.radians(i * 30 + 15)
        rr = size * 0.345
        gx, gy = c + math.cos(ang) * rr, c + math.sin(ang) * rr
        for _ in range(3):
            ox, oy = rnd.uniform(-5, 5), rnd.uniform(-6, 6)
            cv.line([(gx + ox, gy + oy - 4), (gx + ox + rnd.uniform(-3, 3),
                                              gy + oy + 4)],
                    fill=(255, 255, 255, 165), width=1.3)

    # A triangle and its inverse -- the one figure that says "circle of power"
    # without needing to be read.
    for turn in (0, 60):
        pts = [(c + math.cos(math.radians(turn + i * 120)) * size * 0.28,
                c + math.sin(math.radians(turn + i * 120)) * size * 0.28)
               for i in range(3)]
        cv.polygon(pts + [pts[0]], outline=(255, 255, 255, 110))

    return cv.finish()


# ---------------------------------------------------------------------------
# Spell backgrounds
#
# **A spell background is drawn in code and these are the pieces it is drawn
# out of.** A painted background per spell is a 1920x1080 sprite per spell,
# eleven of them for one boss and a texture page nobody can budget -- so what
# ships is a handful of tintable, tileable *motifs* and a function per boss
# that arranges them. A new boss costs one function and, if it wants one, one
# motif; it does not cost a background.
#
# Both of these are white-on-transparent and are drawn additively and tinted at
# run time, which is what lets one sprite serve a red imp and, later, a violet
# vampire.
# ---------------------------------------------------------------------------

def make_spell_veins(size=1024, seed=9):
    """A network of cracks radiating from the centre.

    Ziggy's spell background is the inside of a furnace and this is the shell
    of it: black rock fracturing outward from wherever he is standing, lit from
    behind. **Radial rather than random**, because a random crack field is
    scenery and a radial one has a *source* -- and the source is the boss, which
    is the whole thing a spell background is trying to say.

    The width tapers with distance from the centre, so the cracks read as
    opening rather than as a spider's web drawn on glass.
    """
    ss = 2
    S = size * ss
    img = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    c = S / 2.0
    rnd = np.random.default_rng(seed)

    def crack(x, y, ang, reach, wide, depth):
        pts = [(x, y)]
        steps = 16
        for i in range(steps):
            ang += rnd.normal(0, 7)
            step = reach / steps
            x += math.cos(math.radians(ang)) * step
            y += math.sin(math.radians(ang)) * step
            pts.append((x, y))
            # Taper: each segment a little thinner than the last, so the crack
            # dies out instead of stopping.
            w = max(1.0, wide * (1 - i / steps) ** 0.8)
            d.line([pts[-2], pts[-1]], fill=255, width=int(w * ss))
            # Branches, and only near the start -- a crack that forks at its
            # own tip reads as a plant.
            if depth > 0 and i in (3, 7) and rnd.random() < 0.8:
                crack(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(28, 55),
                      reach * 0.45, wide * 0.55, depth - 1)

    for i in range(26):
        a = i * (360 / 26) + rnd.uniform(-6, 6)
        r0 = S * 0.055
        crack(c + math.cos(math.radians(a)) * r0,
              c + math.sin(math.radians(a)) * r0,
              a, S * rnd.uniform(0.30, 0.48), rnd.uniform(3.0, 7.0), 2)

    # Two copies: the crack itself, and a wide bloom saying the rock either
    # side of it is hot. Composited here rather than at draw time, so the game
    # pays for one sprite instead of two.
    # **The bloom is kept low, and the reason is the scale it is drawn at.**
    # The game stretches this to 2600 pixels across, so a blur of sixteen here
    # is a blur of forty on screen and its alpha covers most of the frame --
    # photographed at 0.55 the spell background was an amber fog with the
    # danmaku somewhere inside it, which is precisely the gold-on-gold failure
    # the whole subtraction rule exists to prevent. The crack should be the
    # bright thing and the space between cracks should be black.
    core = img.filter(ImageFilter.GaussianBlur(ss * 1.4))
    wide = img.filter(ImageFilter.GaussianBlur(ss * 16)).point(
        lambda v: int(min(255, v * 2.4)))
    a = ImageChops.lighter(core, wide.point(lambda v: int(v * 0.22)))

    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(a)
    return out.resize((size, size), Image.LANCZOS)


def make_spell_horn(w=640, h=600, seed=4):
    """One horn, growing from the bottom-left of its own canvas.

    **A silhouette on a black background is nothing at all**, which is the trap
    a "huge dark shape looming" always sets: the spell wash is near-black by
    design, so a black shape drawn on it is invisible and a grey one is a grey
    smear. What actually reads is the *rim* -- a bright contour with nothing
    much behind it, which the eye completes into a mass.

    **The root is at the foot and the tip curls up and to the right**, which is
    the one thing about this that is easy to get backwards: the origin is the
    root, the game pins that to a bottom corner of the screen, and the horn has
    to grow *out of* that corner. The first version had the broad end at the
    top and drew a horn hanging into the frame point-first.

    Spine, then thickness along it, rather than an arc of a circle. A real horn
    leaves the skull steeply and bends forward as it grows, so the curvature is
    not constant -- and a constant-curvature horn reads as a croissant.
    """
    ss = 2
    W, H = w * ss, h * ss
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)

    n = 48

    def spine(t):
        return (W * 0.06 + W * 0.86 * t ** 1.45,
                H * 0.97 - H * 0.92 * t ** 0.72)

    inner, outer = [], []
    for i in range(n + 1):
        t = i / n
        px, py = spine(t)
        qx, qy = spine(min(1.0, t + 0.02))
        ang = math.atan2(qy - py, qx - px)
        # **Broad at the root.** The first attempt was a third this thick and
        # came back as a bundle of parallel arcs: a horn is a cone that happens
        # to bend, and with no obvious taper the banding across it is all that
        # is left, which reads as rope.
        half = W * 0.19 * (1 - t) ** 1.1 + W * 0.006
        nx, ny = math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2)
        inner.append((px - nx * half, py - ny * half))
        outer.append((px + nx * half, py + ny * half))
    d.polygon(inner + outer[::-1], fill=255)

    # Growth rings, the way a real horn is laid down in bands.
    ridge = Image.new("L", (W, H), 0)
    rd = ImageDraw.Draw(ridge)
    for i in range(8):
        j = int((0.08 + i * 0.108) * n)
        rd.line([inner[j], outer[j]], fill=255, width=int(ss * 9))

    # **Three layers, because a rim on its own is a wire.** The body is a dim
    # wash saying there is a mass here at all; the rim is the contour facing up
    # and out, where the fire below would catch it; the bands say the mass is
    # horn rather than rock. Drawn additively over a near-black spell wash the
    # body reads as the dull red of something barely lit, and the rim picks out
    # its shape -- which together is the whole effect.
    body = mask.filter(ImageFilter.GaussianBlur(ss * 7)).point(
        lambda v: int(v * 0.19))
    lit = ImageChops.subtract(mask, ImageChops.offset(mask, 24 * ss, 22 * ss))
    lit = lit.filter(ImageFilter.GaussianBlur(ss * 4.0))
    bands = ImageChops.multiply(ridge.filter(ImageFilter.GaussianBlur(ss * 4)),
                                mask).point(lambda v: int(v * 0.34))
    a = ImageChops.lighter(ImageChops.lighter(body, lit), bands)

    out = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    out.putalpha(a)
    return out.resize((w, h), Image.LANCZOS)


# The point on the sprite the horn grows from, as a fraction of its size. The
# game pins this to a bottom corner of the screen, so it has to be the root.
HORN_ROOT = (0.06, 0.97)


# ---------------------------------------------------------------------------

def main():
    gm_new.folder("Sprites/fx")
    gm_new.folder("Sprites/ui")

    made = []

    def emit(name, img, origin="center", folder="Sprites/fx", label=None):
        gm_new.sprite(name, [img], origin=origin, folder=folder)
        made.append((label or name, img))

    emit("spr_fx_bloom", make_bloom())
    emit("spr_fx_spark", make_spark())
    emit("spr_fx_ring", make_ring())
    emit("spr_laser_node", make_laser_node())

    body = make_laser_body()
    gm_new.sprite("spr_laser_body", [body], origin=(0, body.height // 2),
                  folder="Sprites/fx")
    made.append(("spr_laser_body", body))

    # **The origin sits well forward on the bolt, not in the middle of it.**
    # A shot is spawned clear of Szuix's head and travels head-first, so what
    # the spawn point should mean is "where the front of the bolt is" -- with a
    # centred origin half the sprite is drawn *ahead* of the point that hits,
    # and a bolt that visibly leads its own collision is a bolt that appears to
    # pass through the first thing it kills. Same argument as the flame
    # bullet's origin in `make_bullets`.
    pshot = make_pshot()
    gm_new.sprite("spr_pshot", [pshot],
                  origin=(int(pshot.width * 0.74), pshot.height // 2),
                  folder="Sprites/ui")
    made.append(("spr_pshot", pshot))
    emit("spr_hitbox", make_hitbox(), folder="Sprites/ui")
    emit("spr_focus_ring", make_focus_ring(), folder="Sprites/ui")
    emit("spr_boss_sigil", make_sigil(), folder="Sprites/fx")
    emit("spr_spell_veins", make_spell_veins(), folder="Sprites/fx")
    # Origin at the root of the horn, which is the corner of the screen it is
    # pinned to -- so the game positions it by naming a corner rather than by
    # working out where half of it is.
    horn = make_spell_horn()
    gm_new.sprite("spr_spell_horn", [horn],
                  origin=(int(horn.width * HORN_ROOT[0]),
                          int(horn.height * HORN_ROOT[1])),
                  folder="Sprites/fx")
    made.append(("spr_spell_horn", horn))

    # **Thirty-six, up from thirty.** A cut point wants a ridge, a girdle and a
    # lit facet in it, and at thirty pixels two of those are the same pixel.
    # `ITEM_R` is the collection radius and is unrelated, so this is a picture
    # change and not a reach change.
    for name, col in (("red", A.LIFE), ("blue", A.MANA), ("gold", A.GRAZE)):
        emit("spr_item_" + name, make_item(col), folder="Sprites/ui")

    A.preview([i for _, i in made],
              os.path.join(A.PREVIEW, "fx.png"),
              cols=5, bg=(26, 28, 42),
              labels=[n.replace("spr_", "") for n, _ in made])
    print("fx: %d sprites" % len(made))


if __name__ == "__main__":
    main()
