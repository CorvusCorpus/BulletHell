#!/usr/bin/env python3
"""Build the game, pose a scene, save a screenshot, and copy the PNG out.

The game poses the scene itself (`objects/obj_shot`, `scripts/shot_scenes`)
and saves the screenshot with `screen_save`, which writes into the game's
save area; this fetches it from there. The scene name is passed as a
separate argument, so the game can refuse an unknown one.

Usage:
    python tools/shot.py                # -> tools/_preview/stage.png
    python tools/shot.py boss
    python tools/shot.py boss out.png
    python tools/shot.py bomb --burst 0,20,40,70,110
                                        # one launch, several frames, one sheet
    python tools/shot.py --all          # every scene (slow)
    python tools/shot.py boss --fullscreen   # design-size pixels
"""
import contextlib
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build

# Save files a posed shot may write, set aside for the run and restored after
# (`saves_set_aside`). The `.tmp` sibling is included because the save
# loader falls back to it.
SEEDED = ("progress.json", "progress.json.tmp")

# Scene names. Must match `shot_scene_list()` in `scripts/shot_scenes`; the
# game refuses a name it doesn't know.
SCENES = (
    "title",        # the stage-select screen
    "practice",     # the attack list: every attack of a stage's bosses
    "stage",        # mid-stage: fodder waves, player shooting, items falling
    "focus",        # focused: hitbox shown, slow, grazing
    "bomb",         # the special going off
    "hit",          # the player struck: iframe flicker, shards scattering
    "peril",        # one hit from death: the heartbeat warning, in a pattern
    "midboss",      # the midboss and its pattern
    "declare",      # the boss introduction splash
    "spell",        # a named spell: banner, eye card, changed background
    "boss",         # a boss non-spell pattern with the health bar mid-fight
    "laser",        # telegraphed beam lasers, warning lines live
    "rays",         # moving ray lasers
    "clear",        # the phase-clear burst, bullets converting to shards
    "items",        # the three pickups over a live pattern, some being caught
    "pause",        # the pause menu over a live field
    "rank",         # the rank card: the medal an ended encounter throws up
    "result",       # the post-stage result screen
    "practice_ready",   # the count before a practised attack opens
    "practice_result",  # the end of a practice attempt: grade and menu
    "bullets",      # every bullet kind and colour, laid out as a chart
    "motion",       # every behaviour a bullet can be given: arcs, wakes,
                    # splits, timed fades, a graphic change in flight
    "drafts",       # the rack with the drafting table selected
    "draft_attacks",   # its attack list: the unclaimed patterns
    "draft_spell",  # one of them being fought, through the game's own machinery
    "hex_draw",     # `Demon Sealing Hex`: the ward half inscribed
    "hex_seal",     # ...closed, turning, and being fired into
    "hex_scatter",  # ...coming apart, every bead its own way
    "hex_gaps",     # ...the blue one, whose gaps are the whole design
    "hex_burst",    # ...and the collapse detonating
    "grove",         # stage two by moonlight: the corridor, and fodder in it
    "grove_arrive",  # ...the fog it opens in, half lifted
    "grove_turn",    # ...at totality, with the wood's only light gone
    "grove_blood",   # ...with the wavefront part way down the corridor
    "grove_boss",    # Velka over the turned wood, danmaku across the moon
    "grove_spell",   # her caster's background: bone circle, antlers, wash
    "sanctum",       # stage three: two gateposts standing in a live wave
    "mika_attacks",  # its attack list, scrolled half way down Mika's fifteen

    # Stage three's hall: before the reveal, after it, partway, and the
    # opening fade.
    "hall_a",        # the approach: aimed at the floor, the hall off-frame
    "hall_b",        # the reveal: level, the room open
    "hall_turn",     # ...and half way between them, off the review card
    "hall_arrive",   # ...and the dark it all comes up out of

    # Temporary: Chakram Blitz rope variants side by side.
    "rope_lab",
)

# One scene per slot of Mika's table (`mika_n1`, `mika_s1`, ... `mika_s8`),
# generated as the game generates them: his attack in that slot, practised,
# photographed four seconds in (`--burst` offsets count from there).
MIKA_NONSPELLS = 7
SCENES += tuple(
    name
    for k in range(1, MIKA_NONSPELLS + 1)
    for name in ("mika_n%d" % k, "mika_s%d" % k)
) + ("mika_s%d" % (MIKA_NONSPELLS + 1),)

EXE = os.path.join(build.BUILD, "out", build.project_name() + ".exe")

# `screen_save` writes into `%LOCALAPPDATA%\<game>`, where GameMaker has
# replaced the project name's space with an underscore.
SAVE_DIR = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                        build.project_name().replace(" ", "_"))

TIMEOUT = 120

# GameMaker's run-time error banner. A scene can save its screenshot and still
# crash (the screenshot is saved in Step; a throw in the following Draw
# happens after the file exists), so the output is checked for this too.
GAME_ERROR = re.compile(r"^ERROR!!!|^ERROR in action number", re.M)


@contextlib.contextmanager
def saves_set_aside(directory, names):
    """Move save files out of the way, and put them back afterwards (also on a
    crash). A file that didn't exist before is deleted afterwards, since the
    posed run may write it.
    """
    moved = []
    absent = []
    for name in names:
        live = os.path.join(directory, name)
        if os.path.exists(live):
            stash = live + ".shotbak"
            if os.path.exists(stash):
                os.remove(stash)
            os.replace(live, stash)
            moved.append((live, stash))
        else:
            absent.append(live)
    try:
        yield
    finally:
        for live in absent:
            if os.path.exists(live):
                os.remove(live)
        for live, stash in moved:
            if os.path.exists(live):
                os.remove(live)
            os.replace(stash, live)


def contact_sheet(paths, labels, out, cols=3, scale=0.42):
    """Tile a burst's screenshots into one labelled sheet."""
    from PIL import Image, ImageDraw

    shots = [Image.open(p).convert("RGB") for p in paths]
    w = int(shots[0].width * scale)
    h = int(shots[0].height * scale)
    rows = (len(shots) + cols - 1) // cols
    pad, lab = 8, 18
    sheet = Image.new("RGB", (cols * (w + pad) + pad,
                              rows * (h + lab + pad) + pad), (18, 16, 26))
    d = ImageDraw.Draw(sheet)
    for i, (img, label) in enumerate(zip(shots, labels)):
        x = pad + (i % cols) * (w + pad)
        y = pad + (i // cols) * (h + lab + pad)
        sheet.paste(img.resize((w, h), Image.LANCZOS), (x, y))
        d.text((x + 4, y + h + 3), label, fill=(190, 196, 220))
    sheet.save(out)
    return out


def take(scene, out, fullscreen=False, burst=None):
    """Photograph one scene. Windowed unless `fullscreen` (a windowed
    screenshot is 1864x1048 on a 1080p desktop; `--fullscreen` gives
    design-size pixels).
    """
    names = (["shot_%d.png" % i for i in range(len(burst))] if burst
             else ["shot.png"])
    shots = [os.path.join(SAVE_DIR, n) for n in names]
    # Remove any previous shot, so a failed save can't pass with an old image.
    for path in shots:
        if os.path.exists(path):
            os.remove(path)

    try:
        with saves_set_aside(SAVE_DIR, SEEDED):
            cmd = [EXE, "-shot", scene]
            if burst:
                cmd += ["-burst", ",".join(str(int(b)) for b in burst)]
            if fullscreen:
                cmd.append("-fullscreen")
            # Minimised without focus, unless `--fullscreen` (see
            # `build.run_game`).
            proc = build.run_game(cmd, TIMEOUT, show=fullscreen)
            output = (proc.stdout or "") + (proc.stderr or "")
            missing = [p for p in shots if not os.path.exists(p)]
            if missing:
                print("FAILED (%s): no screenshot at %s"
                      % (scene, ", ".join(missing)))
                print("\n".join(output.splitlines()[-25:]))
                return 1
            # A saved screenshot isn't enough: fail if the game threw.
            if GAME_ERROR.search(output):
                print("FAILED (%s): the game threw" % scene)
                print("\n".join(output.splitlines()[-25:]))
                return 1
            os.makedirs(os.path.dirname(out), exist_ok=True)
            if burst:
                stem = os.path.splitext(out)[0]
                copies = []
                for path, off in zip(shots, burst):
                    dest = "%s@%+d.png" % (stem, int(off))
                    shutil.copyfile(path, dest)
                    copies.append(dest)
                sheet = contact_sheet(
                    copies, ["%s %+d" % (scene, int(b)) for b in burst],
                    "%s_sheet.png" % stem)
                print("burst -> %s" % os.path.relpath(sheet, build.ROOT))
            else:
                shutil.copyfile(shots[0], out)
    except subprocess.TimeoutExpired:
        print("FAILED (%s): the game did not exit within %ds" % (scene, TIMEOUT))
        print("A run-time throw is a modal box, which from here is a hang.")
        return 1

    print("shot -> %s" % os.path.relpath(out, build.ROOT))
    return 0


def main():
    args = list(sys.argv[1:])
    every = "--all" in args
    if every:
        args.remove("--all")
    fullscreen = "--fullscreen" in args
    if fullscreen:
        args.remove("--fullscreen")
    burst = None
    for i, a in enumerate(list(args)):
        if a == "--burst" and i + 1 < len(args):
            burst = sorted(int(v) for v in args[i + 1].split(",") if v.strip())
            del args[i:i + 2]
            break

    scene = "stage"
    if args and not args[0].endswith(".png"):
        scene = args.pop(0)
        if scene not in SCENES:
            raise SystemExit("unknown scene %r. Known: %s"
                             % (scene, ", ".join(SCENES)))

    argv, sys.argv = sys.argv, ["build.py"]
    try:
        if build.main() != 0:
            return 1
    finally:
        sys.argv = argv

    preview = os.path.join(build.ROOT, "tools", "_preview")
    if every:
        failed = []
        for s in SCENES:
            if take(s, os.path.join(preview, "%s.png" % s), fullscreen) != 0:
                failed.append(s)
        # A summary at the end.
        print()
        if failed:
            print("%d of %d scenes FAILED: %s"
                  % (len(failed), len(SCENES), ", ".join(failed)))
            return 1
        print("all %d scenes rendered" % len(SCENES))
        return 0

    out = args[0] if args else os.path.join(preview, "%s.png" % scene)
    return take(scene, out, fullscreen, burst)


if __name__ == "__main__":
    sys.exit(main())
