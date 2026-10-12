"""A study, not wired into the game: Mika's head and bust drawn from scratch
as vector art (SVG), three-quarter view, in anime-furry conventions (heavy
outer lines and fine inner ones, hard-edged cel shadows, a cool rim light,
half-lidded anime eyes), with his markings from the owner's sheet.

Usage:
    python tools/studies/mika_bust.py out.html
then open the page, or screenshot it (Chromium) to a PNG."""
import math
import sys

OUT = sys.argv[1]

INK = "#0a0810"
FUR = "#221f2c"
FUR_SH = "#121019"
FUR_HI = "#3a3750"
RIM = "#7d86d8"
INNER = "#33304a"
INNER_TIP = "#6b6a90"
GOLD = "#ffb21c"
GOLD_SH = "#c97a06"
GOLD_HI = "#ffe7a0"
GOLD_INK = "#5a2c00"


def tufts(pts, depth, every=1, lean=0.35, start=0):
    """A path through `pts` where every segment bulges out into a pointed tuft
    `depth` to the left of the direction of travel."""
    d = ""
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1
        nx, ny = dy / L, -dx / L
        dep = depth * (0.7 + 0.6 * (((i + start) * 37) % 11) / 10)
        tx, ty = mx + nx * dep + dx * lean, my + ny * dep + dy * lean
        d += f" Q {x0 + nx * dep * 0.25:.1f} {y0 + ny * dep * 0.25:.1f} {tx:.1f} {ty:.1f}"
        d += f" Q {mx + dx * 0.25:.1f} {my + dy * 0.25:.1f} {x1:.1f} {y1:.1f}"
    return d


def arc_pts(cx, cy, rx, ry, a0, a1, n):
    return [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))
            for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]]


svg = []
add = svg.append

add(f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 860" width="800" height="860">
<defs>
  <linearGradient id="iris" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#062a6e"/><stop offset="0.45" stop-color="#0b62d6"/>
    <stop offset="1" stop-color="#48c2ff"/>
  </linearGradient>
  <radialGradient id="eyeglow"><stop offset="0" stop-color="#2fa0ff" stop-opacity="0.55"/>
    <stop offset="1" stop-color="#2fa0ff" stop-opacity="0"/></radialGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{GOLD_HI}"/><stop offset="0.35" stop-color="{GOLD}"/>
    <stop offset="1" stop-color="{GOLD_SH}"/></linearGradient>
  <clipPath id="eyeN"><path d="M 268 428 C 292 404 340 404 368 436 C 344 452 296 452 268 428 Z"/></clipPath>
  <clipPath id="eyeF"><path d="M 424 436 C 446 410 480 404 500 418 C 486 444 452 452 424 436 Z"/></clipPath>
</defs>
""")

# -- the ears, behind -----------------------------------------------------------
near_ear = ("M 322 334 C 296 246 238 144 150 56 "
            + "C 134 104 124 156 126 204" + tufts([(126, 204), (136, 252), (152, 296), (174, 338), (204, 376), (240, 408)], 20)
            + " Z")
add(f'<path d="{near_ear}" fill="{FUR}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>')
inner_near = ("M 306 340 C 282 262 232 170 164 100 "
              + "C 160 150 166 204 184 252" + tufts([(184, 252), (206, 290), (232, 324), (260, 354), (290, 380)], 16, start=3)
              + " Z")
add(f'<path d="{inner_near}" fill="{INNER}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
for (x0, y0, x1, y1) in ((206, 300, 236, 318), (224, 330, 252, 342), (196, 268, 222, 290)):
    add(f'<path d="M {x0} {y0} Q {x0 + 18} {y0 - 4} {x1} {y1}" fill="none" stroke="{INNER_TIP}" stroke-width="3" stroke-linecap="round" opacity="0.7"/>')
add(f'<path d="M 152 62 C 186 100 216 146 242 196 C 222 150 192 108 156 84 Z" fill="url(#gold)" stroke="{GOLD_INK}" stroke-width="2"/>')
add(f'<path d="M 258 300 C 238 286 240 262 258 256 C 274 252 282 268 270 276" fill="none" stroke="url(#gold)" stroke-width="7" stroke-linecap="round"/>')

far_ear = ("M 444 320 C 486 246 556 146 652 66 "
           + "C 664 114 664 166 652 214" + tufts([(652, 214), (634, 264), (606, 308), (574, 346), (536, 378)], 17, start=5)
           + " Z")
add(f'<path d="{far_ear}" fill="{FUR}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>')
inner_far = ("M 462 328 C 500 258 556 180 636 110 "
             + "C 636 156 626 204 606 246" + tufts([(606, 246), (582, 284), (552, 316), (518, 342)], 14, start=7)
             + " Z")
add(f'<path d="{inner_far}" fill="{INNER}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
add(f'<path d="M 648 72 C 618 104 592 140 568 186 C 590 146 618 112 644 92 Z" fill="url(#gold)" stroke="{GOLD_INK}" stroke-width="2"/>')
add(f'<path d="M 520 300 C 538 288 536 266 520 262 C 506 260 500 274 510 280" fill="none" stroke="url(#gold)" stroke-width="6" stroke-linecap="round"/>')

# -- shoulders and the chest ruff --------------------------------------------------
add(f"""<path d="M 110 860 C 118 760 160 690 240 652 C 290 630 340 620 400 620 C 470 620 524 634 574 660
   C 648 696 684 770 692 860 Z" fill="{FUR}" stroke="{INK}" stroke-width="6"/>""")
add(f'<path d="M 524 644 C 606 676 664 756 678 860 L 692 860 C 684 770 648 696 574 660 Z" fill="{FUR_SH}"/>')
add(f'<path d="M 130 860 C 140 770 176 700 244 666" fill="none" stroke="{RIM}" stroke-width="3" opacity="0.5"/>')
add(f"""<path d="M 330 520 C 330 560 320 600 300 630 L 500 630 C 482 600 470 560 470 520 Z" fill="{FUR_SH}"/>""")
ruff = ("M 300 560 " + tufts([(300, 560), (282, 604), (284, 652), (304, 696), (336, 730), (376, 752),
                               (420, 750), (460, 730), (490, 696), (508, 652), (506, 604), (492, 560)], 24)
        + " C 460 590 340 590 300 560 Z")
add(f'<path d="{ruff}" fill="{FUR}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>')
add(f'<path d="M 472 610 C 490 650 486 694 456 726 L 474 714 C 500 680 504 638 492 600 Z" fill="{FUR_SH}"/>')
for (x0, y0, x1, y1) in ((330, 626, 344, 676), (372, 640, 380, 698), (414, 638, 412, 690), (450, 622, 442, 664)):
    add(f'<path d="M {x0} {y0} Q {(x0 + x1) / 2 - 6} {(y0 + y1) / 2} {x1} {y1}" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" opacity="0.8"/>')

# The necklace: chain links down to a ring pendant with its side bars.
for i, t in enumerate([i / 13 for i in range(14)]):
    x = 300 + (500 - 300) * t
    y = 588 + 72 * math.sin(math.pi * t) ** 1.2
    if abs(t - 0.5) < 0.06:
        continue
    if i % 2:
        add(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="8" ry="4.5" fill="none" stroke="url(#gold)" stroke-width="3.5" transform="rotate({(t - 0.5) * 50:.1f} {x:.1f} {y:.1f})"/>')
    else:
        add(f'<path d="M {x - 5:.1f} {y:.1f} L {x + 5:.1f} {y:.1f}" stroke="url(#gold)" stroke-width="4" stroke-linecap="round"/>')
add(f'<path d="M 360 668 C 368 662 378 662 384 668 M 416 668 C 422 662 432 662 440 668" fill="none" stroke="url(#gold)" stroke-width="5" stroke-linecap="round"/>')
add(f'<circle cx="400" cy="670" r="15" fill="none" stroke="{GOLD_INK}" stroke-width="10"/>')
add(f'<circle cx="400" cy="670" r="15" fill="none" stroke="url(#gold)" stroke-width="7"/>')

# -- the head ----------------------------------------------------------------------
head = ("M 404 300 C 452 300 498 318 524 356 C 544 386 552 420 548 448 "
        + tufts([(548, 448), (574, 466), (590, 490), (572, 504), (552, 522)], 18)
        + " C 524 548 470 560 430 556 C 400 552 376 548 360 548 "
        + tufts([(360, 548), (324, 552), (290, 546), (260, 530), (234, 508), (222, 484), (244, 474)], 18)
        + " C 252 456 252 428 262 398 C 280 340 336 300 404 300 Z")
add(f'<path d="{head}" fill="{FUR}" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>')
# Cel shadow: the far side of the face and under the jaw, a hard-edged shape.
add(f"""<path d="M 470 312 C 520 330 548 380 548 448 C 560 468 578 488 570 504 C 544 528 504 548 452 554
   C 490 532 512 496 516 452 C 520 404 504 352 470 312 Z" fill="{FUR_SH}"/>""")
# A soft light on the brow and the near cheek.
add(f'<path d="M 300 360 C 330 322 380 312 420 318 C 380 330 340 350 318 380 Z" fill="{FUR_HI}" opacity="0.7"/>')
add(f'<path d="M 256 466 C 262 492 280 512 304 524 C 284 506 270 488 264 462 Z" fill="{FUR_HI}" opacity="0.6"/>')
# The rim light down the far side.
add(f'<path d="M 520 360 C 540 392 548 420 548 450" fill="none" stroke="{RIM}" stroke-width="3" stroke-linecap="round" opacity="0.75"/>')

# The muzzle: a fennec's short, fine snout, turned toward the near side.
snout = ("M 382 446 C 372 466 348 488 312 506 C 300 512 300 524 312 530 C 334 542 366 548 394 544 "
         "C 420 540 440 528 444 508 C 446 488 432 466 416 448 Z")
add(f'<path d="{snout}" fill="{FUR}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>')
add(f'<path d="M 382 448 C 372 468 350 488 318 506 C 344 500 370 486 392 462 Z" fill="{FUR_HI}" opacity="0.75"/>')
add(f'<path d="M 444 508 C 440 528 420 540 394 544 C 418 534 432 520 436 498 Z" fill="{FUR_SH}"/>')
add(f'<path d="M 300 512 C 304 500 318 496 330 500 C 336 510 328 520 314 522 C 304 522 298 518 300 512 Z" fill="{INK}"/>')
add(f'<ellipse cx="311" cy="506" rx="5" ry="2.6" fill="#6a6688"/>')
add(f'<path d="M 318 528 C 340 538 372 540 404 534 C 418 530 428 522 430 512" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round"/>')
add(f'<path d="M 404 534 L 410 540" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>')

# -- the eyes: half-lidded, a sly look -------------------------------------------------
for cx, cy, r, clip, s in ((322, 432, 26, "eyeN", 1.0), (462, 430, 22, "eyeF", 0.85)):
    add(f'<ellipse cx="{cx}" cy="{cy + 6}" rx="{46 * s}" ry="{30 * s}" fill="url(#eyeglow)"/>')
    add(f'<g clip-path="url(#{clip})">')
    add(f'<rect x="200" y="380" width="400" height="100" fill="#0b2f78"/>')
    add(f'<circle cx="{cx}" cy="{cy + 6}" r="{r}" fill="url(#iris)"/>')
    add(f'<ellipse cx="{cx + 1}" cy="{cy + 6}" rx="{r * 0.2}" ry="{r * 0.62}" fill="#04122e"/>')
    add(f'<ellipse cx="{cx - r * 0.38}" cy="{cy - r * 0.05}" rx="{r * 0.24}" ry="{r * 0.17}" fill="#ffffff" transform="rotate(-20 {cx - r * 0.38} {cy})"/>')
    add(f'<circle cx="{cx + r * 0.36}" cy="{cy + r * 0.62}" r="{r * 0.09}" fill="#d8f2ff"/>')
    # The upper lid's shadow across the top of the eye.
    add(f'<rect x="200" y="380" width="400" height="{cy - 380 - r * 0.15}" fill="#020818" opacity="0.55"/>')
    add('</g>')
add(f'<path d="M 268 428 C 292 404 340 404 368 436" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>')
add(f'<path d="M 262 424 L 254 416" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>')
add(f'<path d="M 278 440 C 306 452 344 452 366 438" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>')
add(f'<path d="M 424 436 C 446 410 480 404 500 418" fill="none" stroke="{INK}" stroke-width="6.5" stroke-linecap="round"/>')
add(f'<path d="M 503 414 L 512 408" stroke="{INK}" stroke-width="4.5" stroke-linecap="round"/>')
add(f'<path d="M 430 440 C 452 450 478 446 496 426" fill="none" stroke="{INK}" stroke-width="2.2" stroke-linecap="round"/>')

# -- the gold markings ------------------------------------------------------------
def gold_path(d, w):
    add(f'<path d="{d}" fill="none" stroke="{GOLD_INK}" stroke-width="{w + 3}" stroke-linecap="round" stroke-linejoin="round"/>')
    add(f'<path d="{d}" fill="none" stroke="url(#gold)" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>')


def gold_fill(d):
    add(f'<path d="{d}" fill="url(#gold)" stroke="{GOLD_INK}" stroke-width="2.5" stroke-linejoin="round"/>')


# The eyeliner swoops: from the inner corner over the eye, out to a curl.
gold_fill("M 368 420 C 350 396 304 386 270 398 C 252 404 240 392 248 380 C 256 368 274 372 270 384 "
          "C 268 376 258 376 256 384 C 254 394 268 398 282 392 C 312 380 352 388 368 420 Z")
gold_fill("M 424 420 C 444 394 476 384 500 392 C 516 396 526 386 520 376 C 514 368 500 370 504 380 "
          "C 506 374 514 374 514 380 C 514 388 502 392 492 388 C 470 382 442 392 424 420 Z")
# Cheek curls under each eye.
gold_path("M 288 462 C 270 468 266 488 278 496 C 290 502 300 492 292 484", 5)
gold_path("M 488 462 C 502 468 506 484 496 492 C 486 498 478 488 486 482", 4.5)
# The forehead ring with its flames: one rising and curling one way, one falling the other.
add(f'<circle cx="400" cy="366" r="13" fill="none" stroke="{GOLD_INK}" stroke-width="11"/>')
add(f'<circle cx="400" cy="366" r="13" fill="none" stroke="url(#gold)" stroke-width="7.5"/>')
gold_fill("M 398 352 C 392 336 396 318 410 306 C 404 320 406 334 414 344 C 408 344 402 348 398 352 Z")
gold_fill("M 402 380 C 408 394 404 408 392 416 C 396 404 392 394 386 388 C 392 388 398 384 402 380 Z")
# Brow curls toward the ears.
gold_path("M 334 350 C 320 336 322 318 336 314 C 346 312 350 324 342 328", 5)
gold_path("M 470 346 C 484 334 484 318 472 314 C 462 312 458 324 466 328", 4.5)

add("</svg>")

html = "<html><body style='margin:0;background:#3c2e46'>" + "\n".join(svg) + "</body></html>"
with open(OUT, "w") as f:
    f.write(html)
