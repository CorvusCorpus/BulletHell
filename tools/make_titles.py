#!/usr/bin/env python3
"""The stages' title cards (`scripts/title_card`): each stage's name in gilt
capitals, its subtitle, its number, and the rules the card is framed by.

One frame per stage, in the order of `CARDS` (a stage def's `card` is its
frame). The names and subtitles here must match the stage defs;
`check_project.py` compares them (`check_title_cards_agree`).

- `spr_card_title`: the name in Cinzel Bold capitals, spaced optically (the
  gap between each pair of letters is measured from their ink, since the
  layout here has no kerning), filled with a gold that darkens across a
  horizon line below its middle, bevelled (lit along the upper left, shaded
  along the lower right), with a dark line round it and a soft shadow under.
- `spr_card_title_lit`: the same letters in white-gold, which the card adds
  over the name for the bright edge that uncovers it and the sheen that
  crosses it.
- `spr_card_sub`: the subtitle, in Spectral, parchment on a soft shadow.
- `spr_card_label`: "STAGE" and its numeral, spaced wide, between two small
  four-pointed stars.
- `spr_card_rule`: frame 0 is the rule over the name: a crescent holding a
  four-pointed star at its middle, with a double line tapering from it each
  way, set with beads and ending in small curls. Frame 1 is the plainer rule
  under the name.

All are top-left origin (the card draws them in parts from their middles).

Usage:
    python tools/make_titles.py
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import art_common as A
import cel_art as C

SS = 4

# (name, subtitle, numeral). Must match the stage defs (checked).
CARDS = [
    ("THE BRIMSTONE REACH", "Ziggy's proving ground", "I"),
    ("THE HOLLOW GROVE", "a wood that keeps its dead", "II"),
    ("ARCHIVE OF BEQUEATHED MEMORIES", "the death-god's hall of rings",
     "III"),
]

TITLE_W, TITLE_H = 1180, 150        # every frame of the name
TITLE_PX = 80                       # the capitals' size, before fitting
TITLE_FIT = 1100                    # a name wider than this is shrunk to it
SUB_W, SUB_H = 900, 60
LABEL_W, LABEL_H = 420, 50
RULE_W, RULE_H = 1060, 48

GOLD_STOPS = [(0.00, (255, 246, 206)), (0.28, (252, 222, 136)),
              (0.52, (228, 170, 66)), (0.56, (150, 88, 26)),
              (0.70, (196, 130, 44)), (1.00, (244, 196, 104))]
INK = (34, 14, 28)                  # the line round the letters


def _font(name, px, weight=None):
    return A.font(name, int(px * SS), weight)


def glyph_mask(ch, fnt):
    """One glyph's ink as a 0..1 array, tightly cropped, and where its
    baseline falls within that crop."""
    asc, desc = fnt.getmetrics()
    img = Image.new("L", (int(fnt.size * 2), asc + desc + 8), 0)
    d = ImageDraw.Draw(img)
    d.text((fnt.size // 2, 4), ch, font=fnt, fill=255)
    arr = np.asarray(img, np.float32) / 255.0
    cols = np.nonzero(arr.max(axis=0) > 0.02)[0]
    if len(cols) == 0:
        return None, 0
    return arr[:, cols[0]:cols[-1] + 1], 4


def set_line(text, fnt, gap, track, space):
    """Lay out `text` as a mask, each pair of glyphs spaced so that their
    ink comes no closer than `gap` pixels (measured on profiles softened
    through the height, so a hollow like A-V isn't closed right up), plus
    `track`. Returns the mask."""
    glyphs = [glyph_mask(ch, fnt) if ch != " " else (None, 0) for ch in text]
    h = max(g[0].shape[0] for g in glyphs if g[0] is not None)
    placed = []
    end = 0.0               # the right edge of the last glyph placed
    pending = 0.0           # word space owed before the next glyph
    prev = None
    for (g, _), ch in zip(glyphs, text):
        if g is None:
            pending += space
            prev = None
            continue
        if prev is None:
            x = (end + pending) if placed else 0.0
        else:
            pg, px = prev
            # The right profile of the previous glyph and the left of this
            # one, row by row, softened through the height.
            rows = min(pg.shape[0], g.shape[0])
            big = 1e4
            right = np.full(rows, -big)
            left = np.full(rows, big)
            for r in range(rows):
                c = np.nonzero(pg[r] > 0.3)[0]
                if len(c):
                    right[r] = c[-1]
                c = np.nonzero(g[r] > 0.3)[0]
                if len(c):
                    left[r] = c[0]
            both = (right > -big) & (left < big)
            if both.any():
                # Distance if this glyph started at 0 right after the last.
                need = (right - left)[both]
                need = np.sort(need)[::-1]
                # Not the single tightest row: the mean of the tightest few,
                # so a serif doesn't hold two letters apart alone.
                k = max(1, len(need) // 12)
                start = px + need[:k].mean() + gap
            else:
                start = px + pg.shape[1] + gap * 0.6
            x = start + track
        pending = 0.0
        placed.append((g, x))
        prev = (g, x)
        end = x + g.shape[1]
    w = int(max(px + g.shape[1] for g, px in placed)) + 4
    out = np.zeros((h, w), np.float32)
    for g, px in placed:
        ix = int(round(px))
        out[:g.shape[0], ix:ix + g.shape[1]] = np.maximum(
            out[:g.shape[0], ix:ix + g.shape[1]], g)
    return out


def _paste_centre(canvas, m):
    """`m` centred on the canvas array (cropped if it overhangs)."""
    H, W = canvas.shape
    h, w = m.shape
    y0 = (H - h) // 2
    x0 = (W - w) // 2
    ys = slice(max(0, y0), min(H, y0 + h))
    xs = slice(max(0, x0), min(W, x0 + w))
    canvas[ys, xs] = m[ys.start - y0:ys.stop - y0, xs.start - x0:xs.stop - x0]
    return canvas


def _grad(stops, t):
    xs = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, xs, cs[:, c])
    return out


def _shift(m, dx, dy):
    return ndimage.shift(m, (dy, dx), order=1, mode="constant", cval=0.0)


def gilt(mask, cap_top, cap_h):
    """Gild a mask of letters (at `SS`): a gold that darkens across a
    horizon below the capitals' middle, lit along the upper left and shaded
    along the lower right, with a dark line round it and a shadow under.
    Returns (colour, alpha) at `SS`."""
    H, W = mask.shape
    ys = np.arange(H, dtype=np.float32)[:, None].repeat(W, 1)
    t = np.clip((ys - cap_top) / max(1.0, cap_h), 0, 1)
    col = _grad(GOLD_STOPS, t)

    # The bevel: bright where the letter's edge faces the light...
    b = 1.6 * SS
    away = _shift(mask, b * 0.62, b * 0.78)
    lit = np.clip(mask - away, 0, 1)
    col += (np.array((255, 252, 230), np.float32) - col) * (lit * 0.85)[..., None]
    # ...and shaded where it faces away.
    toward = _shift(mask, -b * 0.62, -b * 0.78)
    dark = np.clip(mask - toward, 0, 1)
    col += (np.array((110, 58, 16), np.float32) - col) * (dark * 0.75)[..., None]

    inside = mask > 0.5
    dist = ndimage.distance_transform_edt(~inside) / SS
    line = np.clip(2.4 - dist + 0.5, 0, 1) * (~inside)
    shadow = ndimage.gaussian_filter(_shift(mask, 3 * SS, 5 * SS), 5 * SS)

    out = np.zeros((H, W, 3), np.float32)
    a = np.zeros((H, W), np.float32)

    def over(c, al):
        nonlocal out, a
        c = np.asarray(c, np.float32)
        if c.ndim == 1:
            c = c[None, None, :]
        out = c * al[..., None] + out * (1 - al[..., None])
        a = al + a * (1 - al)

    over((6, 2, 10), shadow * 0.75)
    over(INK, line)
    over(col, mask)
    return out, a


def reduce(col, a):
    """Premultiplied box filter from `SS` down to final pixels."""
    H, W = a.shape
    h, w = H // SS, W // SS
    col = col[:h * SS, :w * SS]
    a = a[:h * SS, :w * SS]
    pre = (col * a[..., None]).reshape(h, SS, w, SS, 3).mean(axis=(1, 3))
    al = a.reshape(h, SS, w, SS).mean(axis=(1, 3))
    return A.from_arrays(pre / np.maximum(al, 1e-6)[..., None], al)


def title_frames():
    fnt = _font(A.CINZEL, TITLE_PX, 700)
    lines = [set_line(n, fnt, gap=0.10 * TITLE_PX * SS,
                      track=0.02 * TITLE_PX * SS,
                      space=0.34 * TITLE_PX * SS) for n, _, _ in CARDS]
    gilt_out, lit_out = [], []
    for m in lines:
        # Each name fitted on its own, so a long one doesn't shrink the rest.
        k = min(1.0, TITLE_FIT / (m.shape[1] / SS))
        if k < 1:
            m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize(
                (int(m.shape[1] * k), int(m.shape[0] * k)), Image.LANCZOS),
                np.float32) / 255.0
        canvas = np.zeros((TITLE_H * SS, TITLE_W * SS), np.float32)
        _paste_centre(canvas, m)
        rows = np.nonzero(canvas.max(axis=1) > 0.3)[0]
        cap_top, cap_h = rows[0], rows[-1] - rows[0]
        col, a = gilt(canvas, cap_top, cap_h)
        gilt_out.append(reduce(col, a))
        white = np.empty(canvas.shape + (3,), np.float32)
        white[:] = (255, 244, 214)
        lit_out.append(reduce(white, ndimage.gaussian_filter(canvas, 0.6 * SS)))
    return gilt_out, lit_out


def sub_frames():
    fnt = _font(A.SPECTRAL_MED, 34)
    out = []
    for _, sub, _ in CARDS:
        m = set_line(sub, fnt, gap=0.07 * 34 * SS, track=0.01 * 34 * SS,
                     space=0.26 * 34 * SS)
        canvas = np.zeros((SUB_H * SS, SUB_W * SS), np.float32)
        _paste_centre(canvas, m)
        shadow = ndimage.gaussian_filter(_shift(canvas, 2 * SS, 3 * SS),
                                         3 * SS)
        col = np.zeros(canvas.shape + (3,), np.float32)
        a = np.zeros(canvas.shape, np.float32)
        col[:] = (8, 4, 14)
        a = shadow * 0.85
        par = np.array((238, 226, 204), np.float32)
        col = par * canvas[..., None] + col * (1 - canvas[..., None])
        a = canvas + a * (1 - canvas)
        out.append(reduce(col, a))
    return out


def _star(sh, cx, cy, r, ramp):
    pts = []
    for k in range(8):
        a = math.radians(-90 + k * 45)
        rr = r if k % 2 == 0 else r * 0.3
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    sh.part(sh.poly(pts), ramp, band=1.0, rim=0.5, line=1.0, wash=0.3)


def label_frames():
    fnt = _font(A.CINZEL, 26, 600)
    out = []
    for _, _, num in CARDS:
        sh = C.Sheet(LABEL_W, LABEL_H)
        # The word spaced wide, the numeral set close (spaced like the word,
        # III would read as three separate strokes).
        word = set_line("STAGE", fnt, gap=0.34 * 26 * SS, track=0.10 * 26 * SS,
                        space=0)
        numeral = set_line(num, fnt, gap=0.12 * 26 * SS, track=0, space=0)
        sep = int(0.62 * 26 * SS)
        h = max(word.shape[0], numeral.shape[0])
        m = np.zeros((h, word.shape[1] + sep + numeral.shape[1]), np.float32)
        m[:word.shape[0], :word.shape[1]] = word
        m[:numeral.shape[0], word.shape[1] + sep:] = numeral
        canvas = np.zeros((sh.H, sh.W), np.float32)
        _paste_centre(canvas, m)
        sh.part(canvas, C.GOLD, band=0.8, rim=0.5, line=1.4, wash=0.4)
        cols = np.nonzero(canvas.max(axis=0) > 0.3)[0]
        half = (cols[-1] - cols[0]) / 2.0 / SS
        for s in (-1, 1):
            _star(sh, s * (half + 26), 0, 9, C.GOLD)
        out.append(sh.finish())
    return out


def rule_frames():
    frames = []
    for style in (0, 1):
        sh = C.Sheet(RULE_W, RULE_H)
        half = RULE_W / 2.0 - 16
        # A double line tapering from the middle to each end.
        m = np.zeros((sh.H, sh.W), np.float32)
        for s in (-1, 1):
            if style == 0:
                for dy, w0 in ((-3.2, 2.6), (3.2, 1.6)):
                    m = np.maximum(m, sh.stroke([(s * 34, dy), (s * half, dy * 0.3)],
                                                w0, 0.4))
            else:
                m = np.maximum(m, sh.stroke([(s * 14, 0), (s * half * 0.8, 0)],
                                            2.0, 0.4))
        sh.part(m, C.GOLD, band=0.7, rim=0.4, line=1.0, wash=0.2)
        if style == 0:
            # Beads along it, and a curl at each end.
            for s in (-1, 1):
                for k in range(1, 7):
                    x = s * (34 + k * (half - 60) / 7.0)
                    r = 3.4 - k * 0.3
                    pts = [(x - r * 1.6, 0), (x, -r), (x + r * 1.6, 0), (x, r)]
                    sh.part(sh.poly(pts), C.GOLD, band=0.8, rim=0.5,
                            line=0.8, wash=0.3)
                cx = s * (half + 4)
                curl = [(cx - s * 14 + s * 14 * math.cos(t) * (1 - t / 9),
                         math.sin(t) * 7 * (1 - t / 9))
                        for t in np.linspace(0, 5.5, 30)]
                sh.part(sh.stroke(curl, 2.2, 0.8), C.GOLD, band=0.6, rim=0.4,
                        line=0.8)
            # The crescent holding a star.
            outer = sh.circle(0, 2, 17)
            bite = sh.circle(0, -5, 15)
            cres = np.clip(outer - bite, 0, 1)
            sh.part(cres, C.GOLD, band=2.0, rim=0.9, line=1.1, wash=0.4)
            _star(sh, 0, -6, 12, C.GOLD)
            gem = sh.circle(0, -6, 2.6)
            sh.part(gem, C.TURQUOISE, band=0.8, rim=0.4, line=0.6)
        else:
            pts = [(-9, 0), (0, -5), (9, 0), (0, 5)]
            sh.part(sh.poly(pts), C.GOLD, band=1.0, rim=0.5, line=0.9,
                    wash=0.3)
        frames.append(sh.finish())
    return frames


def main():
    import gm_new
    titles, lits = title_frames()
    subs = sub_frames()
    labels = label_frames()
    rules = rule_frames()

    gm_new.folder("Sprites/ui")
    for name, frames in (("spr_card_title", titles),
                         ("spr_card_title_lit", lits),
                         ("spr_card_sub", subs),
                         ("spr_card_label", labels),
                         ("spr_card_rule", rules)):
        if "--preview" not in sys.argv:
            gm_new.sprite(name, frames, origin="topleft", folder="Sprites/ui",
                          fps=1.0)
        print("%-20s %d frames of %dx%d" % (name, len(frames),
                                           frames[0].width, frames[0].height))

    # A preview of each card as the game lays it out.
    shots = []
    for i in range(len(CARDS)):
        c = Image.new("RGBA", (1360, 420), (30, 22, 44, 255))
        band = Image.new("RGBA", (1360, 330), (14, 8, 26, 170))
        c.alpha_composite(band, (0, 45))
        cy = 210
        c.alpha_composite(labels[i], (680 - LABEL_W // 2, cy - 118 - LABEL_H // 2))
        c.alpha_composite(rules[0], (680 - RULE_W // 2, cy - 76 - RULE_H // 2))
        c.alpha_composite(titles[i], (680 - TITLE_W // 2, cy - TITLE_H // 2))
        c.alpha_composite(rules[1], (680 - RULE_W // 2, cy + 66 - RULE_H // 2))
        c.alpha_composite(subs[i], (680 - SUB_W // 2, cy + 108 - SUB_H // 2))
        shots.append(c)
    sheet = Image.new("RGBA", (1360, 420 * len(shots)))
    for i, s in enumerate(shots):
        sheet.paste(s, (0, 420 * i))
    path = os.path.join(A.PREVIEW, "title_cards.png")
    sheet.save(path)
    print("->", os.path.relpath(path, A.ROOT))


if __name__ == "__main__":
    main()
