#!/usr/bin/env python3
"""Generate the bitmap font atlases the game draws all of its text with.

**The fonts are sprites, not GameMaker font assets.** A `GMFont` bakes glyph
metrics into a `.yy` that only the IDE knows how to produce, and `font_add`
needs the typeface installed on the player's machine. A sprite with one frame
per glyph, handed to `font_add_sprite_ext`, needs neither: the atlas ships in
the texture page like any other art and renders identically everywhere.

Both typefaces are SIL Open Font License, which matters because this atlas is a
redistribution of the outlines. Cinzel and Spectral are bundled in
`tools/fonts/` with their licences; the Microsoft faces installed on this
machine are deliberately not used, since baking one into a shipped game is not
something their licence allows.

    fnt_small   Spectral Regular 18   floating text, footnotes
    fnt_ui      Spectral SemiBold 25  HUD labels, menu rows
    fnt_num     Cinzel Bold 34        counters -- score, graze, health
    fnt_head    Cinzel Bold 46        panel and section headings
    fnt_spell   Cinzel Bold 62        the spell card name
    fnt_title   Cinzel Bold 104       the boss declaration and the title screen

Glyphs are rendered white so the game can tint them, and every frame in a
sprite is the same size because GameMaker requires it -- `font_add_sprite_ext`
is passed `prop = true`, which measures each glyph's real ink and spaces the
text proportionally regardless of the cell it was drawn in.

Usage:
    python tools/make_fonts.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw

import art_common as A
import gm_new

# ASCII 32..126. Spell names want the em dash, which is not in that range and
# is therefore transliterated to "--" at the call site rather than widening
# every atlas by a glyph nothing else uses.
FIRST = 32
LAST = 126
GLYPHS = "".join(chr(i) for i in range(FIRST, LAST + 1))

PREVIEW = os.path.join(A.PREVIEW, "fonts.png")

# **These are points on a 1920x1080 canvas, and the first set of them were
# points on nothing in particular.** 18, 25 and 34 are sensible sizes for a
# 1280-wide window and this game is drawn at 1920 and played full screen, so
# every readout in it arrived about two thirds the size it needed to be -- the
# score, the graze count, the attack counter and the timer all ended up as
# small grey text pushed against the edge of the frame, which is exactly what
# a HUD should never be.
#
# The rule used here: the smallest text in the game is 26px, which is about
# where a serif face stops being readable at a glance on a 1080p display from
# across a desk, and everything else is a step up from it. The one thing that
# did not grow is the *number* of readouts.
FONTS = [
    # name,       file,             size, weight
    ("fnt_small", A.SPECTRAL, 26, None),
    ("fnt_ui", A.SPECTRAL_SEMI, 36, None),
    ("fnt_num", A.CINZEL, 56, 700),
    ("fnt_head", A.CINZEL, 66, 700),
    ("fnt_spell", A.CINZEL, 84, 700),
    ("fnt_title", A.CINZEL, 132, 700),
]


def atlas(font_file, size, weight):
    """One image per glyph, all the same size, glyphs drawn white.

    The cell is measured across the whole character set rather than guessed: a
    cell too small clips descenders silently, and one too large wastes a
    texture page.
    """
    f = A.font(font_file, size, weight)

    boxes = []
    for ch in GLYPHS:
        box = f.getbbox(ch)
        boxes.append(box if box else (0, 0, 0, 0))

    left = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    right = max(b[2] for b in boxes)
    bottom = max(b[3] for b in boxes)

    pad = 2
    cw = right - left + pad * 2
    ch_ = bottom - top + pad * 2

    frames = []
    for glyph in GLYPHS:
        img = Image.new("RGBA", (cw, ch_), (255, 255, 255, 0))
        d = ImageDraw.Draw(img)

        if glyph == " ":
            # **A space has no ink, and proportional spacing measures ink.**
            # `font_add_sprite_ext` with `prop = true` takes each glyph's width
            # from its non-transparent bounding box, so a fully transparent
            # frame is zero pixels wide and every space in the game vanishes.
            # A bar at alpha 1 is invisible on screen and still bounds the box.
            advance = max(1, int(round(f.getlength(" "))))
            d.rectangle([pad, ch_ - pad - 1, pad + advance - 1, ch_ - pad - 1],
                        fill=(255, 255, 255, 1))
        else:
            # Every glyph is placed against the *same* origin, so the baseline
            # is common to all of them. Centring each glyph in its own cell
            # would make the text bounce as the letters changed.
            d.text((pad - left, pad - top), glyph, font=f,
                   fill=(255, 255, 255, 255))

        frames.append(img)

    return frames, cw, ch_


def main():
    gm_new.folder("Sprites/fonts")

    previews = []
    for name, file, size, weight in FONTS:
        frames, cw, ch_ = atlas(file, size, weight)
        gm_new.sprite("spr_" + name, frames, origin="topleft",
                      folder="Sprites/fonts")
        print("%-10s %2d glyph cells of %dx%d" % (name, len(frames), cw, ch_))

        sample = Image.new("RGBA", (cw * 9, ch_), (0, 0, 0, 0))
        for i, glyph in enumerate("Danmaku 5"):
            sample.alpha_composite(frames[GLYPHS.index(glyph)], (i * cw, 0))
        previews.append(sample)

    A.preview(previews, PREVIEW, cols=1, bg=(24, 26, 40))
    print("->  %s" % os.path.relpath(PREVIEW, A.ROOT))


if __name__ == "__main__":
    main()
