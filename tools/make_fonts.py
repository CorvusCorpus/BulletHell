#!/usr/bin/env python3
"""Generate the sprite-font atlases the game draws its text with.

The fonts are sprites (one frame per glyph, loaded with
`font_add_sprite_ext`) rather than GameMaker font assets, so they need no IDE
step and no installed typeface. Cinzel and Spectral are SIL Open Font
License and bundled in `tools/fonts/` with their licences; don't use the
system's Microsoft fonts, whose licences don't allow shipping them.

    fnt_small   Spectral Regular 26
    fnt_ui      Spectral SemiBold 36
    fnt_num     Cinzel Bold 56
    fnt_head    Cinzel Bold 66
    fnt_spell   Cinzel Bold 84
    fnt_title   Cinzel Bold 132

Glyphs are white (tinted at draw time) and every frame is the same size; the
game passes `prop = true`, so spacing comes from each glyph's ink. There is
no kerning.

Usage:
    python tools/make_fonts.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw

import art_common as A
import gm_new

# ASCII 32..126 (the order `ui_init` assumes).
FIRST = 32
LAST = 126
GLYPHS = "".join(chr(i) for i in range(FIRST, LAST + 1))

PREVIEW = os.path.join(A.PREVIEW, "fonts.png")

# Sizes are pixels on the 1920x1080 design canvas; 26 is the smallest text.
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
    """One image per glyph, all the same size (measured across the whole
    character set), glyphs drawn white.
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
            # Proportional spacing measures each frame's ink, so a fully
            # transparent space would be zero wide. A bar at alpha 1 is
            # invisible but still gives it a width.
            advance = max(1, int(round(f.getlength(" "))))
            d.rectangle([pad, ch_ - pad - 1, pad + advance - 1, ch_ - pad - 1],
                        fill=(255, 255, 255, 1))
        else:
            # Every glyph uses the same origin, so they share a baseline.
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
