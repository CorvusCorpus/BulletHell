"""Pattern sketches: try a danmaku pattern in the browser before building it.

The sketches live in `tools/sketch/` (`engine.js`, and a set of patterns per
file in `sets/`). This script opens them, and renders them headlessly through
Playwright driving the installed Microsoft Edge.

    python tools/sketch.py                         open the first set
    python tools/sketch.py mika_n1                 open a set
    python tools/sketch.py mika_n1 "Sand disc"     open it on one pattern
    python tools/sketch.py --list                  sets and their patterns
    python tools/sketch.py mika_n1 "Sand disc" --gif
    python tools/sketch.py mika_n1 --burst 300,500,660

`--gif` writes one exact loop of the pattern (its `loop`, or `--loop N`
frames), after `--warm` frames so the field has filled. `--burst` writes a
sheet of the given frames, one row per pattern (or just the one named). Both
go to `tools/_preview/sketch_<set>[_<pattern>].gif|png`. `--opt ID` switches
on one of the set's toggles; repeat it for more.
"""

import argparse
import base64
import io
import os
import sys
import webbrowser
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PAGE = HERE / "sketch" / "sketch.html"
OUT = HERE / "_preview"


def page_url(query):
    q = "&".join(f"{k}={v}" for k, v in query.items() if v)
    return PAGE.as_uri() + (("?" + q) if q else "")


def png(data_url):
    return Image.open(io.BytesIO(base64.b64decode(data_url.split(",", 1)[1]))).convert("RGB")


def slug(s):
    out = "".join(c if c.isalnum() else "_" for c in s.lower())
    return "_".join(p for p in out.split("_") if p)


class Page:
    """The sketch page in headless Edge, driven a frame at a time."""

    def __init__(self, pw, set_id):
        self.browser = pw.chromium.launch(channel="msedge", headless=True)
        self.page = self.browser.new_page()
        self.page.goto(page_url({"set": set_id, "capture": "1"}))
        self.page.wait_for_function("window.sketchReady === true", timeout=15000)

    def js(self, expr, arg=None):
        return self.page.evaluate(expr, arg)

    def patterns(self):
        return self.js("Sketch.current.patterns.map(p => p.name)")

    def choose(self, name, opts, scale, label):
        self.js("""([n, opts, scale, label]) => {
            for (const k of Object.keys(Sketch.opts)) delete Sketch.opts[k];
            for (const k of opts) Sketch.opts[k] = true;
            Sketch.capture.prepare(scale, label);
            return Sketch.choose(n);
        }""", [name, opts, scale, label])

    def advance(self, n):
        self.js("n => Sketch.capture.advance(n)", n)

    def frame(self):
        return png(self.js("Sketch.capture.frame()"))

    def close(self):
        self.browser.close()


def resolve(names, want):
    if want is None:
        return None
    if want.isdigit() and int(want) < len(names):
        return names[int(want)]
    for n in names:
        if slug(n) == slug(want):
            return n
    sys.exit(f"no pattern {want!r}; the set has: {', '.join(names)}")


def make_gif(pg, set_id, name, args):
    pg.choose(name, args.opt, args.scale, args.label or f"{pg.js('Sketch.current.name')}  ·  {name}")
    loop = args.loop or pg.js("Sketch.loop")
    if loop % args.every:
        sys.exit(f"the loop ({loop} frames) isn't a multiple of --every {args.every}")
    pg.advance(args.warm)
    frames = []
    for _ in range(loop // args.every):
        frames.append(pg.frame())
        pg.advance(args.every)

    # One palette for the whole loop, so colours don't shimmer between frames.
    w, h = frames[0].size
    picks = frames[:: max(1, len(frames) // 4)][:4]
    strip = Image.new("RGB", (w, h * len(picks)))
    for k, f in enumerate(picks):
        strip.paste(f, (0, h * k))
    pal = strip.quantize(colors=96, method=Image.Quantize.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]

    # GIF delays are in hundredths of a second; at every 2 frames, 30/30/40 ms
    # averages the 33.3 ms the sim takes, so it plays at game speed.
    ms = args.every * 1000 / 60
    if args.every == 2:
        dur = [40 if i % 3 == 2 else 30 for i in range(len(q))]
    else:
        dur = [round(ms / 10) * 10] * len(q)
    path = OUT / f"sketch_{set_id}_{slug(name)}.gif"
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0,
              disposal=1)
    print(f"gif -> {path.relative_to(HERE.parent)}  ({len(q)} frames, "
          f"{loop} sim frames, {os.path.getsize(path) / 1e6:.1f} MB)")


def make_burst(pg, set_id, names, args, one):
    at = sorted(int(x) for x in args.burst.split(","))
    rows = []
    for name in names:
        pg.choose(name, args.opt, args.scale, args.label or name)
        row, t = [], 0
        for f in at:
            pg.advance(f - t)
            t = f
            row.append(pg.frame())
        rows.append(row)
    w, h = rows[0][0].size
    sheet = Image.new("RGB", (w * len(at), h * len(rows)))
    for r, row in enumerate(rows):
        for c, im in enumerate(row):
            sheet.paste(im, (c * w, r * h))
    path = OUT / (f"sketch_{set_id}_{slug(one)}.png" if one else f"sketch_{set_id}.png")
    sheet.save(path)
    print(f"burst -> {path.relative_to(HERE.parent)}  (frames {','.join(map(str, at))})")


def set_ids():
    text = (HERE / "sketch" / "sets" / "index.js").read_text(encoding="utf-8")
    return [s.split("'")[1] for s in text.splitlines() if s.strip().startswith("'")]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("set", nargs="?", help="a set in tools/sketch/sets")
    ap.add_argument("pattern", nargs="?", help="a pattern's name or index")
    ap.add_argument("--list", action="store_true", help="list sets and patterns")
    ap.add_argument("--gif", action="store_true", help="render one loop as a GIF")
    ap.add_argument("--burst", help="frames to photograph, e.g. 300,500,660")
    ap.add_argument("--loop", type=int, help="frames in the loop (default: the pattern's)")
    ap.add_argument("--warm", type=int, default=1800, help="frames run before a GIF starts")
    ap.add_argument("--every", type=int, default=2, help="sim frames per GIF frame")
    ap.add_argument("--scale", type=float, default=1.5, help="1 is 680x496")
    ap.add_argument("--opt", action="append", default=[], help="switch on a set's toggle")
    ap.add_argument("--label", help="caption drawn in the corner")
    args = ap.parse_args()

    ids = set_ids()
    set_id = args.set or ids[0]
    if set_id not in ids:
        sys.exit(f"no set {set_id!r}; sets: {', '.join(ids)}")

    if not (args.list or args.gif or args.burst):
        webbrowser.open(page_url({"set": set_id, "pattern": args.pattern and slug(args.pattern)}))
        return

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit("rendering needs Playwright: python -m pip install playwright")

    OUT.mkdir(exist_ok=True)
    with sync_playwright() as pw:
        for sid in (ids if args.list else [set_id]):
            pg = Page(pw, sid)
            try:
                names = pg.patterns()
                if args.list:
                    print(f"{sid}: {pg.js('Sketch.current.name')}")
                    for i, n in enumerate(names):
                        print(f"  {i}  {n}")
                    continue
                one = resolve(names, args.pattern)
                if args.gif:
                    if not one:
                        sys.exit("--gif needs a pattern")
                    make_gif(pg, set_id, one, args)
                if args.burst:
                    make_burst(pg, set_id, [one] if one else names, args, one)
            finally:
                pg.close()


if __name__ == "__main__":
    main()
