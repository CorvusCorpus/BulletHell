#!/usr/bin/env python3
"""Build the game, photograph a posed scene, and copy the PNG out.

The counterpart to `tools/test.py`. That one proves the rules are right; this
one is the only way to see whether the screen actually *reads* -- which for a
bullet hell is most of the game. A pattern that is correct and illegible is a
bug, and no assertion can see it.

The game poses itself -- see `objects/obj_shot` -- so what comes back is the
real bullet system running the real pattern, not a mock-up.

**The scene name is passed as a second argument, not fused into the flag**, so
`obj_boot` can refuse one it does not know. Wordsearch fused them, and a scene
whose switch nothing read did not fail: the game opened its menu and sat there
until the 120-second timeout, with nothing in the output to say the scene
simply did not exist.

GameMaker's sandbox puts `screen_save` output in the per-game save area rather
than beside the executable, so the file is fetched from there.

Usage:
    python tools/shot.py                # -> tools/_preview/stage.png
    python tools/shot.py boss
    python tools/shot.py boss out.png
    python tools/shot.py --all          # every scene, one after another
    python tools/shot.py bomb --burst 0,20,40,70,110
                                        # one launch, five frames, one sheet
"""
import contextlib
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build

# Save files the game seeds during a posed shot, so panels are photographed
# populated rather than empty.
#
# **The `.tmp` siblings are listed too, and they matter.** Saving is atomic --
# the game builds the new file beside the live one and swaps -- so a seeded run
# leaves a `.tmp` full of fabricated progress. Left behind, that is precisely
# what the recovery path restores the next time a live file is missing, which
# would quietly write the screenshot's data into a real player's save.
SEEDED = ("progress.json", "progress.json.tmp")

# What can be photographed. Each is a scene `obj_shot` knows how to pose; the
# game refuses a name that is not in its own list, so this and that one cannot
# drift apart silently.
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
    "pause",        # the pause menu over a live field
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
    "mika",          # his opening non-spell: one ring on a long lead
    "aperture",      # Gilded Aperture, from inside the middle band
    "circuit",       # Ashiah's Circuit: current strung between two rings

    # The hall itself, at the two ends of its reveal. **Two pictures of the
    # same room**, and the only difference between them is where the camera
    # is: phase A is nine hundred units up aimed at the marble, phase B is at
    # flying height and level. Nothing else in the stage changes, which is the
    # whole argument for making the reveal a camera move rather than a scene
    # change -- and it is why both have to be photographed, because "the hall
    # is hidden" is a claim about a frame and not about a number.
    "hall_a",        # the approach: aimed at the floor, the hall off-frame
    "hall_b",        # the reveal: level, the room open
    "hall_turn",     # ...and half way between them, off the review card
    "hall_arrive",   # ...and the dark it all comes up out of
)

EXE = os.path.join(build.BUILD, "out", build.project_name() + ".exe")

# **GameMaker sanitises the save directory name, and this project has a space
# in its own.** `screen_save` is sandboxed into `%LOCALAPPDATA%\<game>`, and
# the game there is `Bullet_Hell` rather than `Bullet Hell` -- so a harness
# using the project name verbatim looks in a directory that does not exist,
# finds no screenshot, and reports the run as having failed to save one. The
# game had saved it perfectly well.
SAVE_DIR = os.path.join(os.environ.get("LOCALAPPDATA", ""),
                        build.project_name().replace(" ", "_"))

TIMEOUT = 120

# GameMaker's run-time error banner. **A scene can produce a screenshot and
# still have crashed**, and that is not a corner case: `obj_shot` calls
# `screen_save` from its Step event, `game_end()` lets the current frame finish,
# and a throw in the Draw event that follows happens *after* the file is on
# disk. The first time a boss threw floating text the game died exactly there,
# every scene's PNG was written, and this tool reported fifteen successes.
GAME_ERROR = re.compile(r"^ERROR!!!|^ERROR in action number", re.M)


@contextlib.contextmanager
def saves_set_aside(directory, names):
    """Move save files out of the way, and put them back afterwards.

    **The player's real saves are not ours to delete.** Renaming and restoring
    gets a clean slate for the shot and gives the save back, including when the
    run crashes. A file that did not exist beforehand must not exist afterwards
    either -- the posed run *writes* these, and a version that only restored
    what it had moved left seeded progress sitting in the real save directory.
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
    """Tile a burst into one sheet, so a sequence can be read at a glance.

    A bomb is four seconds of sigil, theft, seals and bursts; six PNGs in a
    folder is six things to open in order and hold in your head, and one sheet
    is the sequence. Same argument every generator's preview makes.
    """
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
    """Photograph one scene.

    **Windowed by default, and that reverses an earlier decision.** Full screen
    made a screenshot 1920x1080 exactly, so a photographed pixel was a design
    pixel -- but this tool is run every few minutes while somebody is working on
    something else, and eighteen scenes each seizing the display, changing the
    display mode and rearranging every other window is a far worse cost than
    the one it bought. Windowed, GameMaker clamps to 1864x1048: 97% of design
    size, scaled together, and nothing here measures a screenshot. Pass
    ``--fullscreen`` when a photographed pixel really has to be a design pixel.
    """
    names = (["shot_%d.png" % i for i in range(len(burst))] if burst
             else ["shot.png"])
    shots = [os.path.join(SAVE_DIR, n) for n in names]
    # Remove any previous shot first, or a run that failed to save one leaves
    # the last good image in place and the failure looks like success.
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
            # Minimised and un-activated unless somebody asked to watch it.
            # `--fullscreen` is the one run that wants the display, so it is
            # the one run that gets shown. See `build.run_game`.
            proc = build.run_game(cmd, TIMEOUT, show=fullscreen)
            output = (proc.stdout or "") + (proc.stderr or "")
            missing = [p for p in shots if not os.path.exists(p)]
            if missing:
                print("FAILED (%s): no screenshot at %s"
                      % (scene, ", ".join(missing)))
                print("\n".join(output.splitlines()[-25:]))
                return 1
            # **The screenshot is not the verdict**, for the reason spelled
            # out above `GAME_ERROR`: `screen_save` runs in Step and a throw
            # in the Draw event that follows lands after the file is on
            # disk. That check was written down and never called, so this
            # tool has been grading a crashed scene by whether it managed to
            # photograph itself before dying -- which is the exact failure
            # the comment says once cost fifteen false successes.
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
        # A summary, because eighteen scenes is more output than fits on a
        # screen and a failure in the middle of it scrolls away.
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
