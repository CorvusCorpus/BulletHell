#!/usr/bin/env python3
"""Static integrity checks for the Bullet Hell GameMaker project.

GameMaker is the only real compiler for this project, but a lot of the ways a
hand-edit can break things are visible without one: malformed .yy JSON, event
files that no longer match the object's eventList, resources missing from the
.yyp, and GML that references an asset name that does not exist.

Usage:  python tools/check_project.py
Exits non-zero if anything looks wrong.
"""
import glob
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def _project_name():
    """The project's basename, derived from the .yyp sitting in ROOT."""
    for fn in os.listdir(ROOT):
        if fn.endswith(".yyp"):
            return fn[:-4]
    raise SystemExit("no .yyp found in %s" % ROOT)


PROJECT = _project_name()

# Event file stem -> (eventType, eventNum), for the events this project uses.
EVENT_FILE_TO_KEY = {
    "Create_0": (0, 0),
    "Destroy_0": (1, 0),
    "Step_0": (3, 0),   # Step
    "Step_1": (3, 1),   # Begin Step
    "Step_2": (3, 2),   # End Step
    "Other_4": (7, 4),  # Room Start
    "Draw_0": (8, 0),
    "Draw_64": (8, 64),  # Draw GUI
    "Draw_73": (8, 73),  # Draw End
}

problems = []


def fail(msg):
    problems.append(msg)


def load_yy(path):
    """Parse GameMaker's JSON-with-trailing-commas."""
    with open(path, encoding="utf-8-sig") as fh:
        text = fh.read()
    try:
        return json.loads(re.sub(r",(\s*[}\]])", r"\1", text))
    except json.JSONDecodeError as exc:
        fail("%s: malformed JSON (%s)" % (rel(path), exc))
        return None


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def check_yyp_resources(yyp):
    """Every resource listed in the .yyp must exist on disk, and vice versa."""
    listed = set()
    for res in yyp.get("resources", []):
        path = res["id"]["path"]
        listed.add(path.replace("\\", "/"))
        if not os.path.exists(os.path.join(ROOT, path)):
            fail("%s.yyp lists missing resource: %s" % (PROJECT, path))

    for kind in ("objects", "scripts", "sprites", "rooms", "sounds", "fonts",
                 "tilesets", "animcurves", "sequences"):
        for yy in glob.glob(os.path.join(ROOT, kind, "*", "*.yy")):
            # GameMaker leaves *.old.yy backups behind after format migrations.
            if yy.endswith(".old.yy"):
                continue
            if rel(yy) not in listed:
                fail("%s exists on disk but is not registered in %s.yyp"
                     % (rel(yy), PROJECT))


def check_resource_folders(yyp):
    """Every resource's parent folder must be one the .yyp declares.

    GameMaker's folders are virtual — nothing exists on disk for them, only the
    Folders list in the .yyp — so a resource pointing at a folder that was never
    declared, or declared at different case, looks perfectly fine everywhere
    until the linker refuses to load the project with

        Cannot find folder path 'folders/Objects/Effects.yy'.

    Folder paths are case sensitive to the linker: this project has an *objects*
    folder at folders/Objects/items.yy and a *sprites* one at
    folders/Sprites/Items.yy, and mixing the two up is the easy mistake.
    """
    declared = {f.get("folderPath") for f in yyp.get("Folders", [])}

    for kind in ("objects", "scripts", "sprites", "rooms", "sounds", "fonts",
                 "tilesets", "animcurves", "sequences"):
        for yy_path in glob.glob(os.path.join(ROOT, kind, "*", "*.yy")):
            if yy_path.endswith(".old.yy"):
                continue

            data = load_yy(yy_path)
            if data is None:
                continue

            parent = data.get("parent")
            if not parent:
                continue

            folder = parent.get("path")
            if folder in declared:
                continue

            # A parent that is the .yyp itself means the resource sits at the
            # root of the asset tree rather than in a folder. That is legal and
            # there is nothing in Folders to match it against.
            if folder and folder.endswith(".yyp"):
                continue

            near = [d for d in declared
                    if d and folder and d.lower() == folder.lower()]
            hint = (" (declared as %s — folder paths are case sensitive)" % near[0]
                    if near else "")
            fail("%s is in folder %s, which %s.yyp does not declare%s"
                 % (rel(yy_path), folder, PROJECT, hint))


LEGACY_GLOBALS = ("score", "health", "lives")


def check_legacy_globals():
    """Flag any use of GameMaker's legacy built-in globals as a variable name.

    `score`, `health` and `lives` are built-in *globals* that GameMaker still
    carries from GM8. An instance variable of one of those names splits in two:
    `inst.score = 5` writes an instance variable, and a bare `score` inside
    that object's own events reads the built-in global. The two never see each
    other, and nothing reports it -- the value simply does not arrive.

    This is not hypothetical. obj_game kept a `score`, `play_functions` added
    to it through an instance reference, and the HUD drew the bare name, which
    was always zero. It compiled, it ran, no warning anywhere, and the number
    on screen never moved. The screenshot harness is what caught it.
    """
    comment = re.compile(r"//[^\n]*")
    assign = re.compile(
        r"^\s*(?:%s)\s*(?:=[^=]|\+=|-=|\*=|/=|\+\+|--)" % "|".join(LEGACY_GLOBALS),
        re.M)
    # Only a *simple* receiver counts: `inst.score = 1` is the bug, while
    # `bag[$ word].score = 1` is a plain struct field and perfectly fine. The
    # lookbehind rejects a receiver that ended in a subscript or a call.
    through_ref = re.compile(
        r"(?<![\]\)])\.\s*(?:%s)\s*(?:=[^=]|\+=|-=)" % "|".join(LEGACY_GLOBALS))

    for gml in glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True):
        with open(gml, encoding="utf-8-sig") as fh:
            src = comment.sub("", fh.read())

        for match in assign.finditer(src):
            line = src[:match.start()].count("\n") + 1
            fail("%s:%d assigns to a legacy built-in global (%s) -- "
                 "rename it; instance and global reads of this name disagree"
                 % (rel(gml), line, match.group(0).strip().split()[0]))

        for match in through_ref.finditer(src):
            line = src[:match.start()].count("\n") + 1
            fail("%s:%d writes a legacy built-in global name through an "
                 "instance reference (%s) -- rename it"
                 % (rel(gml), line, match.group(0).strip()))


# Prefixes that mean "this identifier names a GameMaker asset".
ASSET_PREFIXES = ("obj_", "spr_", "snd_", "fnt_", "room_", "tileset_", "ts_")

# Runtime functions that begin with an asset prefix and are not assets.
ALLOWED_NON_ASSETS = frozenset({
    "room_goto", "room_goto_next", "room_goto_previous", "room_restart",
    "room_exists", "room_get_name", "room_first", "room_last", "room_id",
    "room_width", "room_height", "room_speed", "room_persistent",
    "room_transition", "room_transitions", "room_data", "room_name",
    "obj_id",
})

# GameMaker's instance-scope built-ins. `var x` where x is one of these is a
# name that already means something.
GML_BUILTINS = frozenset({
    "x", "y", "xprevious", "yprevious", "xstart", "ystart",
    "hspeed", "vspeed", "direction", "speed", "friction",
    "gravity", "gravity_direction",
    "sprite_index", "sprite_width", "sprite_height",
    "sprite_xoffset", "sprite_yoffset",
    "image_index", "image_speed", "image_number",
    "image_xscale", "image_yscale", "image_angle", "image_alpha", "image_blend",
    "mask_index", "bbox_left", "bbox_right", "bbox_top", "bbox_bottom",
    "depth", "layer", "visible", "solid", "persistent",
    "id", "object_index", "alarm", "path_index", "path_position", "path_speed",
    "timeline_index", "room", "room_width", "room_height", "room_speed",
    "fps", "view_camera", "argument", "argument_count",
    "self", "other", "all", "noone", "global",
})

# Where the installed runtime lives, for its list of built-in function names.
RUNTIME = r"C:\ProgramData\GameMakerStudio2\Cache\runtimes\runtime-2024.14.2.256"

GML_STRING = re.compile(r'"(?:\\.|[^"\\])*"')
GML_COMMENT = re.compile(r"//[^\n]*")
GML_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)

def check_macro_references():
    """Every SHOUTING_IDENTIFIER in the GML must be a macro that exists.

    **GameMaker does not refuse an undefined one.** A bare identifier it has
    never seen is compiled as a variable read, so `PLATE_W` in a draw function
    builds cleanly and then throws at run time -- and a run-time throw in this
    project means a modal error box, which under `tools/shot.py` and
    `tools/test.py` is not a failure but a *hang*: both run the game under a
    timeout and kill it, and what comes back is "the game did not exit within
    120s" with no hint of the cause.

    That is the entire reason this exists. It cost a build to work out that a
    layout constant had been used before it was written, and the compiler had
    nothing to say about it.

    SHOUTING_SNAKE is a safe thing to key on here because GameMaker's own
    built-ins are lower-case almost without exception -- `c_white`, `fa_left`,
    `bm_add`, `vk_escape`, `pr_trianglestrip` -- so an upper-case identifier in
    this codebase is a project macro or a mistake. The handful of upper-case
    built-ins that do exist are listed below rather than guessed at.
    """
    builtin = {"NaN"}

    macros = set()
    enums = set()
    declare = re.compile(r"^\s*#macro\s+([A-Za-z_]\w*)", re.M)
    enum_decl = re.compile(r"\benum\s+(\w+)\s*\{([^}]*)\}", re.S)

    sources = sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True))

    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            src = fh.read()
        macros.update(declare.findall(src))
        for match in enum_decl.finditer(src):
            enums.add(match.group(1))
            for entry in match.group(2).split(","):
                entry = entry.split("=")[0].strip()
                if entry:
                    enums.add(entry)

    if not macros:
        fail("no #macro declarations found — has constants.gml moved?")
        return

    # An enum member is written `TileKind.Normal`, so the shouty pattern never
    # sees one -- but an enum *name* in SHOUTING_SNAKE would be caught, and the
    # members are collected above so that a bare one is not reported either.
    shouty = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b")
    strip_str = re.compile(r'"(?:[^"\\]|\\.)*"')

    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            for lineno, line in enumerate(fh, 1):
                code = strip_str.sub('""', line.split("//", 1)[0])
                for name in shouty.findall(code):
                    if name in macros or name in enums or name in builtin:
                        continue
                    fail("%s:%d uses %s, which is not a #macro anywhere — "
                         "GameMaker will compile it as an unset variable and "
                         "throw at run time" % (rel(gml), lineno, name))


def check_sprite_texture_pages():
    """No sprite may be larger than the texture page it has to fit on.

    GameMaker does not refuse an oversized sprite. It **halves it** and carries
    on, logging one line among hundreds:

        Warning : resource spr_bg_near_... rescaled from 2100,1080 to 1050,540

    The game then runs, looks nearly right, and every one of those sprites is
    at half resolution being scaled back up. The three background layers here
    shipped that way for a while and the symptom was "the background looks a
    bit murky", which is not a symptom anyone traces to a texture page.

    The page also carries a border per sprite, so the usable width is a little
    under the nominal size.
    """
    pages = {}
    for opt in glob.glob(os.path.join(ROOT, "options", "*", "options_*.yy")):
        data = load_yy(opt)
        if data is None:
            continue
        for key, value in data.items():
            if key.endswith("_texture_page") and isinstance(value, str):
                platform = key.split("_")[1]
                try:
                    w, h = (int(v) for v in value.lower().split("x"))
                except ValueError:
                    continue
                pages[platform] = (w, h)

    if not pages:
        return

    # Only the platforms this project actually builds. The mobile pages are
    # deliberately left at 2048 and are not a reason to shrink desktop art.
    desktop = {p: s for p, s in pages.items() if p in ("windows", "linux", "mac")}
    if not desktop:
        return

    limit_w = min(s[0] for s in desktop.values())
    limit_h = min(s[1] for s in desktop.values())
    border = 4

    for yy_path in sorted(glob.glob(os.path.join(ROOT, "sprites", "*", "*.yy"))):
        data = load_yy(yy_path)
        if data is None:
            continue
        w = data.get("width", 0)
        h = data.get("height", 0)
        if w + border > limit_w or h + border > limit_h:
            fail("%s is %dx%d, larger than the %dx%d texture page (less a %dpx "
                 "border) -- GameMaker will silently halve it"
                 % (rel(yy_path), w, h, limit_w, limit_h, border))


def check_run_clears_the_field():
    """`obj_game`'s Create must call `run_clear_field`.

    **Every pool in this game is a global**, allocated once in `obj_boot` and
    reused for the life of the process. That is the right shape for a pool, and
    it is exactly why entering `room_game` says nothing at all about what is on
    the field -- unless something says it.

    For a while nothing did. The clearing lived in `game_reset_stage`, the
    pause menu's restart, so that one route started clean and every other route
    inherited the previous run's field. Finish a stage, take the result screen
    back to the rack, pick a stage: the run opened with the last attempt's
    bullets, lasers, items and enemies still in the pools -- including the
    boss, who carried on stepping his phase table and firing patterns into a
    fight that had not begun.

    It reached the player as two bugs that sounded unrelated: "Ziggy's patterns
    keep firing at the start of the level", and "I take random damage from
    invisible bullets". One cause, and neither reachable down the path that
    happened to be correct.

    `test_run_starts_clean` proves `run_clear_field` empties everything. It
    cannot prove anybody *calls* it, and the bug was not in the clearing -- it
    was in the calling. So that is what this checks, and it is the same shape
    of rule as `check_font_accessors_called`: narrow and absolute, about one
    function that exists to be called from one place.
    """
    create = os.path.join(ROOT, "objects", "obj_game", "Create_0.gml")
    if not os.path.exists(create):
        fail("objects/obj_game/Create_0.gml is missing")
        return

    with open(create, encoding="utf-8-sig") as fh:
        src = _strip_noise(fh.read())
    if "run_clear_field(" not in src:
        fail("obj_game/Create_0.gml never calls run_clear_field() -- every "
             "pool is a global that outlives the room, so a run entered from "
             "the title screen would begin on the previous run's field, boss "
             "included")


# Sprites whose frames are a **catalogue** rather than an animation, where an
# empty entry is a deliberate answer rather than damage. Each carries its
# reason: an allow-list without one is a place to put anything inconvenient.
BLANK_FRAMES_OK = {
    # The light on each of seven charms, one frame per charm. Two of them have
    # none: a bundle of bones and a stick with feathers, whose own generator
    # docstring says "no light in it at all". Drawing an empty frame additively
    # is a no-op, which is exactly the intended behaviour.
    "spr_scn_charm_lit": "two charms have no glowing part; see make_grove.py",
}


def check_sprites_not_blank():
    """No sprite may be entirely transparent.

    **Everything in `sprites/` is generated, and a generated sprite can be
    silently un-generated.** With the project open in the GameMaker IDE, its
    cached copy of a sprite is written back over the one a `make_*` script just
    produced -- reverting the `.yy` to the previous dimensions and, in the
    cases seen so far, leaving every frame blank. Nothing on screen says so.
    The build is clean, because a sprite of the wrong size full of nothing is a
    perfectly valid sprite.

    It was first caught on the fonts, because `check_font_ink_ratio` happens to
    look at the ink in a `W`. That check exists for a completely different
    reason and only covers three sprites, and the next time it happened it took
    `spr_bul_butterfly`, `spr_bul_flame` and `spr_bul_mote` -- fifty-six blank
    frames each -- and the only thing that noticed was a player saying the
    animated bullets had gone.

    So the rule is general: if a sprite has a frame with no ink in it, something
    has eaten it. Re-run the generator that owns it, with the IDE closed.

    **Every frame, and it used to be three.** The old version sampled first,
    middle and last and passed the sprite if *any* of them had ink, on the
    stated grounds that a sprite inked in some frames and blank in others was
    not a failure mode this project produces. It is: the IDE wrote its cached
    six frames back over a freshly generated twelve and left the second half
    empty, so Mika vanished for seven tenths of every second of play and the
    check reported the project sound. What reached a person was "his sprite is
    appearing and disappearing".

    Exhaustive costs 0.9 seconds over the 1129 frames this project ships, which
    is not a budget worth defending against a bug that has now happened three
    times.

    **Some sprites are a catalogue rather than an animation, and an empty entry
    in a catalogue is an answer.** `spr_scn_charm_lit` is the light on each of
    seven charms, drawn frame-per-charm; two of them are a bundle of bones and
    a stick with feathers on it, and `charm_fetish`'s own docstring says "no
    light in it at all". The first exhaustive run reported those as damage,
    which they are not. `BLANK_FRAMES_OK` is the exemption and it carries the
    reason, because an allow-list without one becomes a place to put anything
    inconvenient.
    """
    try:
        from PIL import Image
    except ImportError:
        return

    for yy_path in sorted(glob.glob(os.path.join(ROOT, "sprites", "*", "*.yy"))):
        data = load_yy(yy_path)
        if data is None:
            continue
        frames = [f.get("name") for f in data.get("frames", []) if f.get("name")]
        if not frames:
            fail("%s has no frames at all" % rel(yy_path))
            continue

        folder = os.path.dirname(yy_path)
        missing = []
        blank = []
        for i, fid in enumerate(frames):
            png = os.path.join(folder, fid + ".png")
            if not os.path.exists(png):
                missing.append(i)
                continue
            if not Image.open(png).convert("RGBA").getchannel("A").getbbox():
                blank.append(i)

        if missing:
            fail("%s is missing %d of its frame PNGs -- re-run the generator "
                 "that owns it" % (rel(yy_path), len(missing)))
        name = os.path.splitext(os.path.basename(yy_path))[0]
        if blank and name in BLANK_FRAMES_OK:
            blank = []

        if blank:
            where = ("every one of its %d frames" % len(frames)
                     if len(blank) == len(frames)
                     else "frame(s) %s of %d"
                          % (", ".join(str(b) for b in blank[:8]), len(frames)))
            fail("%s has no ink in %s. Either the generator that owns it never "
                 "draws those frames -- in which case say so in "
                 "BLANK_FRAMES_OK, with the reason -- or something ate them: "
                 "the GameMaker IDE writes its cached copy back over generated "
                 "art when the project is open, which has happened three "
                 "times. Close it, re-run the generator, and check again."
                 % (rel(yy_path), where))


def check_enum_references():
    """Every `SomeEnum.Member` in the project must name a member that exists.

    GameMaker reports this only at compile time —

        enum reference 'Teleporting' does not exist in 'TurnState'

    — which makes it exactly the class of mistake this script exists to catch,
    since nothing here can compile first. It bites hardest when an enum member
    and the code using it are added in separate edits and only one of them
    lands, which is precisely how it went wrong.

    Only identifiers actually declared as enums are checked, so `global.money`
    and `obj_manager.state` are never mistaken for one.
    """
    enums = {}
    declare = re.compile(r"\benum\s+(\w+)\s*\{([^}]*)\}", re.S)
    comment = re.compile(r"//[^\n]*")

    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.gml"))):
        with open(gml, encoding="utf-8-sig") as fh:
            src = comment.sub("", fh.read())

        for match in declare.finditer(src):
            members = set()
            for entry in match.group(2).split(","):
                entry = entry.split("=")[0].strip()
                if entry:
                    members.add(entry)
            enums[match.group(1)] = members

    if not enums:
        fail("no enum declarations found — has constants.gml moved?")
        return

    use = re.compile(r"\b(\w+)\.(\w+)")

    for gml in sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            for lineno, line in enumerate(fh, 1):
                code = line.split("//", 1)[0]

                for enum_name, member in use.findall(code):
                    if enum_name not in enums:
                        continue
                    if member in enums[enum_name]:
                        continue
                    fail("%s:%d references %s.%s, which is not a member of "
                         "that enum" % (rel(gml), lineno, enum_name, member))


def read_macro_number(name, default=None):
    """One #macro's value from constants.gml, integer or decimal.

    `read_macros` is deliberately integers-only -- a layout constant that has
    quietly become a float is usually a mistake. A *fraction* is not, so this
    is the one that reads them.
    """
    path = os.path.join(ROOT, "scripts", "constants", "constants.gml")
    with open(path, encoding="utf-8-sig") as fh:
        src = fh.read()
    match = re.search(r"^\s*#macro\s+%s\s+(-?[\d.]+)\s*(?://.*)?$"
                      % re.escape(name), src, re.M)
    if match is None:
        if default is not None:
            return default
        fail("constants.gml declares no numeric %s" % name)
        return 0.0
    return float(match.group(1))


def read_macros(*names):
    """The integer values of some #macros in constants.gml."""
    path = os.path.join(ROOT, "scripts", "constants", "constants.gml")
    with open(path, encoding="utf-8-sig") as fh:
        src = fh.read()

    out = {}
    for name in names:
        match = re.search(r"^\s*#macro\s+%s\s+(-?\d+)\s*(?://.*)?$" % re.escape(name),
                          src, re.M)
        if match is None:
            fail("constants.gml declares no numeric %s" % name)
            continue
        out[name] = int(match.group(1))
    return out


def newest_sprite_frame(name):
    """A sprite's first frame PNG, by the order its .yy lists them."""
    d = os.path.join(ROOT, "sprites", name)
    yy = os.path.join(d, name + ".yy")
    if not os.path.isfile(yy):
        return None
    with open(yy, encoding="utf-8-sig") as fh:
        text = fh.read()

    block = text.split('"frames":[', 1)
    if len(block) < 2:
        return None

    guids = re.findall(r'"name":"([0-9a-fA-F-]{36})"', block[1])
    for guid in guids:
        png = os.path.join(d, guid + ".png")
        if os.path.isfile(png):
            return png
    return None


def record_tag(node):
    """The key GameMaker discriminates a record by: its $GM* marker, or failing
    that its resourceType."""
    for key in node:
        if key.startswith("$GM"):
            return key
    return node.get("resourceType")


def asset_names(yyp):
    names = set()
    for res in yyp.get("resources", []):
        names.add(res["id"]["name"])
    return names


def check_scripts_registered():
    """Every script .gml on disk must have the .yy that registers it.

    `check_yyp_resources` walks `.yy` files, so a script folder holding only a
    `.gml` is invisible to it -- which is exactly the state `scripts/board_draw`
    was in when a build of it passed cleanly and every call to `draw_board`
    compiled into a call to nothing.
    """
    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.gml"))):
        yy = gml[:-4] + ".yy"
        if not os.path.exists(yy):
            fail("%s has no .yy -- the script is not registered, and every "
                 "call to it compiles into a call to nothing (run "
                 "tools/scaffold.py)" % rel(gml))


def check_brace_balance():
    """Every .gml file must have as many { as }.

    A missing brace is a compile error and nothing else here would notice —
    the JSON stays valid, the event list still matches, every asset name still
    resolves. It earns its place because scripted edits to these files are how
    this project is usually changed, and a regex that eats one line too many
    takes the closing brace of a function with it.

    Strings and comments are stripped first, so a brace inside a description
    or a commented-out block does not count.
    """
    for gml in sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            src = fh.read()

        src = GML_BLOCK_COMMENT.sub("", src)
        src = GML_COMMENT.sub("", src)
        src = GML_STRING.sub('""', src)

        depth = 0
        for char in src:
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth < 0:
                    fail("%s: a closing brace with nothing open" % rel(gml))
                    break

        if depth > 0:
            fail("%s: %d unclosed brace(s)" % (rel(gml), depth))


def check_duplicate_function_definitions():
    """Two scripts defining the same function name is a silent override."""
    seen = {}
    pattern = re.compile(r"^\s*function\s+(\w+)\s*\(", re.MULTILINE)

    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.gml"))):
        with open(gml, encoding="utf-8-sig") as fh:
            for name in pattern.findall(fh.read()):
                if name in seen:
                    fail("function %s() defined in both %s and %s"
                         % (name, seen[name], rel(gml)))
                else:
                    seen[name] = rel(gml)

def collect_record_shapes(node, shapes):
    for child in (node.values() if isinstance(node, dict) else node):
        if isinstance(child, (dict, list)):
            collect_record_shapes(child, shapes)

    if not isinstance(node, dict):
        return
    tag = record_tag(node)
    if not tag:
        return
    name = node.get("name") or node.get("%Name") or "?"
    shapes.setdefault(tag, {}).setdefault(tuple(sorted(node)), []).append(name)


def check_record_shapes():
    """Records of the same kind in one file must all carry the same fields.

    A hand-written record with a misspelled field is valid JSON, resolves every
    asset, and balances every brace — and GameMaker refuses to open the project:

        room_beginning.yy(36,236): Error: Field "isDnd": expected.

    Nothing else here would notice, which is the same argument the brace check
    makes. It bites on exactly the fields whose casing is inconsistent between
    record kinds: a room instance is "isDnd" while an object event is "isDnD",
    and copying one spelling to the other place is the easy mistake.

    Comparing against sibling records rather than a schema is what keeps this
    free: the file already contains a dozen correct examples of whatever is
    being added, and GameMaker's own format is whatever it wrote last.
    """
    for path in [os.path.join(ROOT, PROJECT + ".yyp"),
                 os.path.join(ROOT, PROJECT + ".resource_order")] + [
            yy
            for kind in ("objects", "scripts", "sprites", "rooms", "sounds",
                         "fonts", "tilesets", "animcurves", "sequences")
            for yy in glob.glob(os.path.join(ROOT, kind, "*", "*.yy"))
            if not yy.endswith(".old.yy")]:
        data = load_yy(path)
        if data is None:
            continue

        shapes = {}
        collect_record_shapes(data, shapes)

        for tag, variants in shapes.items():
            if len(variants) < 2:
                continue

            # The majority spelling is whatever most records of this kind use;
            # anything else in the same file is the odd one out.
            ranked = sorted(variants.items(), key=lambda kv: -len(kv[1]))
            common = set(ranked[0][0])

            for keys, names in ranked[1:]:
                missing = sorted(common - set(keys))
                extra = sorted(set(keys) - common)
                fail("%s: %s record(s) %s differ from the other %d: %s%s"
                     % (rel(path), tag, ", ".join(sorted(set(names))[:3]),
                        len(ranked[0][1]),
                        ("missing " + ", ".join(missing)) if missing else "",
                        ("; unexpected " + ", ".join(extra)) if extra else ""))


def check_object_events():
    """eventList entries and .gml files on disk must correspond exactly."""
    for yy_path in sorted(glob.glob(os.path.join(ROOT, "objects", "*", "*.yy"))):
        obj_dir = os.path.dirname(yy_path)
        obj = os.path.basename(obj_dir)
        data = load_yy(yy_path)
        if data is None:
            continue

        declared = set()
        for ev in data.get("eventList", []):
            declared.add((ev["eventType"], ev["eventNum"]))

        on_disk = {}
        for gml in glob.glob(os.path.join(obj_dir, "*.gml")):
            stem = os.path.splitext(os.path.basename(gml))[0]
            key = EVENT_FILE_TO_KEY.get(stem)
            if key is None:
                fail("%s: unrecognised event file name %s.gml" % (obj, stem))
                continue
            on_disk[key] = stem

        for key, stem in on_disk.items():
            if key not in declared:
                fail("%s: %s.gml exists but is not in the object's eventList"
                     % (obj, stem))
        for key in declared:
            if key not in on_disk:
                fail("%s: eventList declares eventType=%d eventNum=%d with no "
                     ".gml file" % (obj, key[0], key[1]))


def check_room_creation_code():
    for yy_path in sorted(glob.glob(os.path.join(ROOT, "rooms", "*", "*.yy"))):
        data = load_yy(yy_path)
        if data is None:
            continue
        cc = data.get("creationCodeFile", "")
        if cc and not os.path.exists(os.path.join(ROOT, cc)):
            fail("%s references missing creation code file: %s"
                 % (rel(yy_path), cc))


def check_room_instances():
    """Every room instance must be in both its layer and instanceCreationOrder.

    GameMaker creates the instances instanceCreationOrder names. An instance
    written into a layer and left out of that list **does not exist in game** —
    the project opens, the room editor draws it exactly where you put it, and it
    is simply never created. Nothing else here would notice: the JSON parses,
    the object resolves, the record has every field its siblings have.

    That is the same shape as an object's eventList and its .gml files, and it
    has now gone wrong the same way: eight braziers and an item placed into
    room_beginning's Entities layer, none of them in the creation order, and the
    only symptom was an empty-looking room. gm_edit.add_room_instance writes both
    lists so it cannot recur; this is what says so when something else does it.

    Creation code is checked here too, because it is a third place the same
    instance appears: hasCreationCode true wants an
    InstanceCreationCode_<name>.gml beside the room, and a file with no instance
    to attach to is dead weight GameMaker ignores in silence.
    """
    for yy_path in sorted(glob.glob(os.path.join(ROOT, "rooms", "*", "*.yy"))):
        data = load_yy(yy_path)
        if data is None:
            continue

        room_dir = os.path.dirname(yy_path)
        room = os.path.basename(room_dir)

        placed = {}
        for layer in data.get("layers", []):
            for inst in layer.get("instances", []):
                name = inst.get("name")
                if name in placed:
                    fail("%s: two instances are both named %s"
                         % (rel(yy_path), name))
                placed[name] = inst

        ordered = [entry.get("name")
                   for entry in data.get("instanceCreationOrder", [])]

        for name in sorted(set(placed) - set(ordered)):
            fail("%s: instance %s is in a layer but not in "
                 "instanceCreationOrder, so GameMaker will not create it"
                 % (rel(yy_path), name))

        for name in sorted(set(ordered) - set(placed)):
            fail("%s: instanceCreationOrder names %s, which is in no layer"
                 % (rel(yy_path), name))

        for name, inst in sorted(placed.items()):
            code = os.path.join(room_dir, "InstanceCreationCode_%s.gml" % name)
            if inst.get("hasCreationCode") and not os.path.exists(code):
                fail("%s: instance %s declares creation code with no %s"
                     % (rel(yy_path), name, os.path.basename(code)))

        for code in glob.glob(os.path.join(room_dir,
                                           "InstanceCreationCode_*.gml")):
            name = os.path.basename(code)[len("InstanceCreationCode_"):
                                          -len(".gml")]
            if name not in placed:
                fail("%s has no instance named %s" % (rel(code), name))
            elif not placed[name].get("hasCreationCode"):
                fail("%s exists but instance %s has hasCreationCode false, so "
                     "it never runs" % (rel(code), name))

def project_function_names():
    """Every `function name(` defined anywhere in this project."""
    names = set()
    for gml in glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True):
        with open(gml, encoding="utf-8-sig") as fh:
            for m in re.finditer(r"function\s+([A-Za-z_]\w*)\s*\(", fh.read()):
                names.add(m.group(1))
    return names


def object_method_names():
    """Names bound to a function in an object's own event.

    `on_boss_beaten = function(_e) {...}` in a Create event is an instance
    method, and calling it bare from that object's Step is ordinary GML. The
    unknown-function check has no notion of instance scope, so without this it
    reports every one of them.
    """
    names = set()
    for gml in glob.glob(os.path.join(ROOT, "objects", "*", "*.gml")):
        with open(gml, encoding="utf-8-sig") as fh:
            for m in re.finditer(r"^\s*([A-Za-z_]\w*)\s*=\s*(?:method\s*\(|function\s*\()",
                                 fh.read(), re.M):
                names.add(m.group(1))
    return names


def check_gml_asset_references(yyp):
    known = asset_names(yyp)

    # **A project function whose name happens to start with an asset prefix is
    # not a missing asset.** `fnt_small()` returns the handle
    # `font_add_sprite_ext` gave back for `spr_fnt_small`, and reading it
    # through an accessor is the point -- a font can then be re-pointed in one
    # place. Without this the check reports every call site of every one.
    known = known | project_function_names()

    # A bare identifier that looks like an asset name. The lookbehind rejects
    # `_g.spr_thing` and the like: a name reached through a dot is a struct
    # field, not an asset reference.
    pattern = re.compile(r"(?<![.\w])((?:%s)\w+)\b" % "|".join(ASSET_PREFIXES))

    for gml in sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            lines = fh.readlines()
        for lineno, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            for name in pattern.findall(code):
                if name in known or name in ALLOWED_NON_ASSETS:
                    continue
                fail("%s:%d references unknown asset %r"
                     % (rel(gml), lineno, name))


def check_script_function_names(yyp):
    """Every script's .gml should live in a folder matching its asset name."""
    for yy_path in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.yy"))):
        folder = os.path.basename(os.path.dirname(yy_path))
        data = load_yy(yy_path)
        if data is None:
            continue
        if data.get("name") != folder:
            fail("%s: asset name %r does not match folder %r"
                 % (rel(yy_path), data.get("name"), folder))
        gml = os.path.join(os.path.dirname(yy_path), folder + ".gml")
        if not os.path.exists(gml):
            fail("%s: missing %s.gml" % (rel(yy_path), folder))


def _runtime_function_names():
    path = os.path.join(RUNTIME, "fnames")
    if not os.path.exists(path):
        return None

    names = set()
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            # Entries look like `abs(val)` or `argument_count`; the name is
            # whatever comes before the first non-identifier character.
            m = re.match(r"([A-Za-z_]\w*)", line)
            if m:
                names.add(m.group(1))
    return names


def check_unknown_functions():
    """Refuse a call to a function that is not defined anywhere.

    **GameMaker compiles a call to a function that does not exist.** It is the
    same trap as an undefined `#macro` -- which `check_macro_references` already
    guards -- and it bites in the same way: the build is clean, and the game
    throws when the line is finally reached, which under `tools/test.py` and
    `tools/shot.py` is a *hang* rather than a failure, since both run the game
    under a timeout and kill it.

    This is not hypothetical. `scripts/board_draw` was written, called from
    `obj_game`'s Draw event, and left unregistered in the `.yyp`; the build
    reported OK. Renaming a function so that missed call sites "become compile
    errors" does not work for the same reason, and this check is what makes that
    argument true after the fact.

    Method names are excluded -- `_fx.parts` and friends are struct fields, and
    a call through a dot is not a call to a global function.

    **String literals are stripped along with comments**, which is not
    fastidiousness: this project's test names read like English, so
    `"a word (uppercased)"` and `"cost per word on board (us)"` scan as calls to
    `word()` and `board()` and produced four false alarms on the first run. A
    check that cries wolf gets its output skimmed, which is the failure mode
    that matters most for a check nothing else can replace.
    """
    builtins = _runtime_function_names()
    if builtins is None:
        # No runtime to read. A hand-maintained list of four thousand names
        # would be wrong by the next update and wrong in the direction that
        # produces false alarms, so this check simply stands down.
        return

    defined = set()
    sources = sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True))
    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            for m in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(", fh.read()):
                defined.add(m.group(1))

    # Control-flow keywords are followed by a parenthesis and are not calls.
    KEYWORDS = {
        "if", "while", "for", "repeat", "with", "switch", "case", "else",
        "do", "until", "return", "new", "delete", "throw", "catch", "function",
    }

    # Instance methods, and functions handed in as arguments. A parameter or
    # local holding a function is called by its own name -- `_maker(_g)`, where
    # `_maker` is an argument -- and this project's convention is that every
    # local and every argument starts with an underscore, so a leading
    # underscore is a reliable "this is a value, not a global function".
    known = builtins | defined | KEYWORDS | object_method_names()
    call = re.compile(r"(?<![\w.$])([a-z]\w*)\s*\(")

    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            lines = fh.readlines()
        for n, line in enumerate(lines, 1):
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line).split("//", 1)[0]
            for m in call.finditer(code):
                name = m.group(1)
                if name in known:
                    continue
                fail("%s:%d calls %s(), which is not defined in this project "
                     "and is not a runtime function -- GameMaker compiles this "
                     "and throws at run time" % (rel(gml), n, name))


def check_shadowed_builtins():
    pattern = re.compile(r"\bvar\s+([A-Za-z_]\w*)")
    for gml in sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            for lineno, line in enumerate(fh, 1):
                code = line.split("//", 1)[0]
                for name in pattern.findall(code):
                    if name in GML_BUILTINS:
                        fail("%s:%d declares `var %s`, which is a builtin"
                             % (rel(gml), lineno, name))

def _split_args(text):
    """Top-level comma count for an argument list, minus the outer parens."""
    depth = 0
    n = 1 if text.strip() else 0
    i = 0
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            n += 1
        i += 1
    return n


def _strip_noise(src):
    """Neutralise comments and string bodies, keeping the file's exact length.

    Comments become spaces and strings become `"xxx"` -- a placeholder rather
    than blank, because an argument list has to stay countable: blanked out,
    `word_is_valid("cat")` reads as a call with no arguments at all, which is
    how the first run of `check_call_arity` reported forty-five faults that
    were entirely its own.

    Length is preserved so that a match offset into the stripped text still
    names the right line in the original.
    """
    out = []
    i = 0
    while i < len(src):
        two = src[i:i + 2]
        if two == "//":
            j = src.find("\n", i)
            j = len(src) if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif two == "/*":
            j = src.find("*/", i)
            j = len(src) if j < 0 else j + 2
            out.append("".join(c if c == "\n" else " " for c in src[i:j]))
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < len(src) and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            end = min(j + 1, len(src))
            out.append('"' + "x" * max(0, end - i - 2)
                       + '"'[:max(0, end - i - 1)])
            i = end
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def check_call_arity():
    """Every call to a project function must pass a number of arguments it takes.

    **This is the third identifier trap and the last of them.** GML does not
    refuse a call with too few arguments -- it binds the missing ones to
    `undefined` and lets the arithmetic run, so the failure surfaces wherever
    that value is finally used rather than where the mistake is. Where that
    happens to be inside a Draw event, no suite can reach it: `tools/test.py`
    runs the rules and never draws a frame.

    That is not hypothetical either. `draw_arc_band` takes a step count as its
    tenth argument and the versus stun ring passed nine; the build was clean,
    all 767 assertions passed, and the game died on the first frame a player
    was ever stunned -- in a mode whose every other rule is covered.

    Only project functions are checked. The runtime's own arities are not in
    `fnames` in any form worth parsing, and the two traps that matter for
    built-ins are already covered by `check_unknown_functions`.
    """
    sig = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(")
    arities = {}

    sources = sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"), recursive=True))
    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            src = _strip_noise(fh.read())
        for m in sig.finditer(src):
            args, _ = _read_call(src, m.end() - 1)
            if args is None:
                continue
            parts = [p.strip() for p in _split_list(args)]
            required = sum(1 for p in parts if p and "=" not in p)
            arities[m.group(1)] = (required, len(parts))

    call = re.compile(r"(?<![\w.$])([a-z_]\w*)\s*\(")
    for gml in sources:
        with open(gml, encoding="utf-8-sig") as fh:
            raw = fh.read()
        src = _strip_noise(raw)

        for m in call.finditer(src):
            name = m.group(1)
            if name not in arities:
                continue

            # The definition itself is not a call to itself.
            before = src[max(0, m.start() - 12):m.start()]
            if before.rstrip().endswith("function"):
                continue

            args, _ = _read_call(src, m.end() - 1)
            if args is None:
                continue
            got = _split_args(args)
            low, high = arities[name]
            if low <= got <= high:
                continue

            line = raw.count("\n", 0, m.start()) + 1
            want = str(low) if low == high else "%d to %d" % (low, high)
            fail("%s:%d calls %s() with %d argument(s); it takes %s -- GML "
                 "binds the missing ones to undefined and throws later, "
                 "possibly in a Draw event no suite can reach"
                 % (rel(gml), line, name, got, want))


def _read_call(src, open_paren):
    """The text between a call's parentheses, and the index just past them."""
    depth = 0
    i = open_paren
    while i < len(src):
        if src[i] in "([{":
            depth += 1
        elif src[i] in ")]}":
            depth -= 1
            if depth == 0:
                return src[open_paren + 1:i], i + 1
        i += 1
    return None, len(src)


def _split_list(text):
    """Top-level comma split, for a parameter list."""
    parts = []
    depth = 0
    at = 0
    for i, c in enumerate(text):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[at:i])
            at = i + 1
    tail = text[at:]
    if tail.strip() or parts:
        parts.append(tail)
    return parts


def check_delta_time_in_rules():
    """No rule may read `delta_time`; it must take the step it is given.

    **In play the two are the same number, which is exactly why this hid.** A
    rule that rolls against `delta_time` behaves correctly at any frame rate,
    because `delta_time` *is* the frame's step -- so nothing is ever wrong on
    screen and no suite that draws frames can see a problem.

    It comes apart under simulation. A balance harness steps a fixed `dt` as
    fast as the machine will go, so `delta_time` there is a few microseconds:
    `cpu_wants_spirit` rolled against it, and the simulated opponent therefore
    essentially never struck its seal. Every figure measured that way was taken
    against a CPU that could not use its vessel, and the only thing that could
    have revealed it was running one match twice at two different speeds.

    So the rules take their step as an argument, always. Objects are exempt: an
    event is where real time legitimately enters, and `var _dt = delta_time /
    1000000` at the top of a Step is how it gets in.
    """
    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.gml"))):
        with open(gml, encoding="utf-8-sig") as fh:
            src = GML_COMMENT.sub("", fh.read())

        for match in re.finditer(r"\bdelta_time\b", src):
            line = src[:match.start()].count("\n") + 1
            fail("%s:%d reads delta_time inside a rule -- take the step as an "
                 "argument instead, so the same code can be simulated; see "
                 "check_delta_time_in_rules" % (rel(gml), line))



def check_font_ink_ratio():
    """`FONT_INK_RATIO` must match what the font atlases actually contain.

    A sprite font's `string_height` returns the *cell*, which carries room for
    an ascender and a descender that a row of capitals never touches. The HUD
    lays itself out in ink, so it multiplies by `FONT_INK_RATIO` — and a
    constant like that is exactly the kind that goes stale silently the next
    time `make_fonts.py` changes a size or a padding.

    Nothing else would notice: the game would still build, still run, and the
    layout tests would still pass while measuring the wrong thing. So the number
    is checked against the PNGs it was derived from.
    """
    try:
        from PIL import Image
    except ImportError:
        return      # Pillow is only needed by the art generators

    declared = None
    consts = os.path.join(ROOT, "scripts", "constants", "constants.gml")
    if not os.path.exists(consts):
        return
    with open(consts, encoding="utf-8-sig") as fh:
        match = re.search(r"#macro\s+FONT_INK_RATIO\s+([0-9.]+)", fh.read())
    if not match:
        fail("constants.gml declares no FONT_INK_RATIO")
        return
    declared = float(match.group(1))

    # 'W' is the widest capital and a full cap-height glyph, so its ink is the
    # extent the layout actually has to clear.
    frame_of_w = ord("W") - 32

    for name in ("spr_fnt_title", "spr_fnt_score", "spr_fnt_head"):
        yy_path = os.path.join(ROOT, "sprites", name, name + ".yy")
        if not os.path.exists(yy_path):
            continue
        data = load_yy(yy_path)
        if data is None:
            continue

        frames = [f.get("name") for f in data.get("frames", [])]
        if len(frames) <= frame_of_w:
            fail("%s has too few frames to hold the ASCII range" % name)
            continue

        png = os.path.join(ROOT, "sprites", name, frames[frame_of_w] + ".png")
        if not os.path.exists(png):
            fail("%s is missing the frame for 'W'" % name)
            continue

        box = Image.open(png).convert("RGBA").getchannel("A").getbbox()
        if box is None:
            fail("%s: the 'W' frame is empty" % name)
            continue

        ratio = (box[3] - box[1]) / data.get("height", 1)
        if abs(ratio - declared) > 0.06:
            fail("%s: a capital's ink is %.2f of the cell, but constants.gml "
                 "declares FONT_INK_RATIO %.2f -- the HUD lays out in ink and "
                 "will get its spacing wrong" % (name, ratio, declared))


def check_font_digit_mid():
    """`FONT_DIGIT_MID_*` must match where the atlases actually put a digit.

    The boss's percentage and the dial's clock are counters: each digit is set
    on a wheel centred in a window, and the window's edges are what the eye
    measures it against. `text_digit_middle_y` centres a digit's ink with these
    two ratios, so a regenerated font that moved its digits would put every
    counter in the game a pixel or two off-centre -- the defect they exist to
    fix, reported first as the percentage sitting two pixels low -- and nothing
    else would notice.

    Measured as the mean over the ten digits of where the ink's middle sits
    above the bottom of the cell, as a fraction of the cell.
    """
    try:
        from PIL import Image
    except ImportError:
        return

    consts = os.path.join(ROOT, "scripts", "constants", "constants.gml")
    if not os.path.exists(consts):
        return
    with open(consts, encoding="utf-8-sig") as fh:
        text = fh.read()

    for macro, sprite in (("FONT_DIGIT_MID_NUM", "spr_fnt_num"),
                          ("FONT_DIGIT_MID_UI", "spr_fnt_ui")):
        match = re.search(r"#macro\s+%s\s+([0-9.]+)" % macro, text)
        if not match:
            fail("constants.gml declares no %s" % macro)
            continue
        declared = float(match.group(1))

        yy_path = os.path.join(ROOT, "sprites", sprite, sprite + ".yy")
        data = load_yy(yy_path) if os.path.exists(yy_path) else None
        if data is None:
            continue
        frames = [f.get("name") for f in data.get("frames", [])]
        mids = []
        for ch in "0123456789":
            i = ord(ch) - 32
            if i >= len(frames):
                break
            png = os.path.join(ROOT, "sprites", sprite, frames[i] + ".png")
            if not os.path.exists(png):
                continue
            im = Image.open(png).convert("RGBA")
            box = im.getchannel("A").getbbox()
            if box is None:
                continue
            h = im.size[1]
            mids.append((h - (box[1] + box[3]) * 0.5) / h)
        if len(mids) < 10:
            fail("%s: could not measure all ten digits" % sprite)
            continue
        measured = sum(mids) / len(mids)
        if abs(measured - declared) > 0.01:
            fail("%s: a digit's ink is centred %.3f of the cell above its "
                 "bottom, but constants.gml declares %s %.3f -- every counter "
                 "set in that face will sit off the middle of its window"
                 % (sprite, measured, macro, declared))


def _bg_layers():
    """Every parallax layer sprite's newest PNG frame."""
    out = []
    for yy in sorted(glob.glob(os.path.join(ROOT, "sprites", "spr_bg_*",
                                            "*.yy"))):
        name = os.path.basename(os.path.dirname(yy))
        png = newest_sprite_frame(name)
        if png:
            out.append((name, png))
    return out


def check_bg_seams():
    """A scrolling layer must tile seamlessly top to bottom.

    The world moves down the screen forever, so every background layer is drawn
    twice -- at `y` and at `y - GAME_H` -- and a discontinuity between its first
    row and its last is a hard horizontal line sweeping up the screen once a
    cycle. It is the one artefact in a scrolling game a player cannot un-see,
    and it is invisible in the generator's own preview, which shows one tile.

    **Measured against the layer's own texture, not against a fixed number.**
    A busy layer has a lot of difference between any two adjacent rows and a
    smooth one has almost none, so the only meaningful question is whether the
    join is worse than an ordinary row boundary. Three times is generous and
    still catches everything that reads as a seam: the first version of these
    layers scored twenty-five times on the rock and the shading was visibly
    stepped.

    This caught two real ones. The rock and near layers were *shaded* at one
    tile's height, so `shade_shape`'s distance field treated the canvas edge as
    the edge of the shape and lit a boulder crossing the join differently at
    each end. And the ground's molten cracks wandered freely down the tile, so
    each one arrived at the bottom several hundred pixels from where it left
    the top.
    """
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return

    for name, png in _bg_layers():
        arr = np.asarray(Image.open(png).convert("RGBA"), dtype=np.float32)
        if arr.shape[0] < 8:
            continue
        join = float(np.abs(arr[0] - arr[-1]).mean())
        h = arr.shape[0]
        adjacent = float(np.mean([
            np.abs(arr[y] - arr[y - 1]).mean()
            for y in (h // 4, h // 2, (3 * h) // 4)
        ]))
        # A perfectly flat layer has an adjacent delta of zero, which no
        # multiple can be taken of; the floor is what keeps that from being an
        # automatic failure.
        budget = max(1.0, adjacent * 3.0)
        if join > budget:
            fail("%s does not tile top to bottom: its join differs by %.2f "
                 "against %.2f between ordinary adjacent rows -- a seam will "
                 "sweep up the screen once a cycle" % (name, join, adjacent))


def check_bg_keepout():
    """The near parallax layer must leave the middle of the screen alone.

    It is drawn *over* the field, so anything it puts in the centre is
    somewhere a bullet can be invisible. The generator enforces this with a
    window that reaches zero at the boundary -- see `make_near` -- and this is
    the check that the window is still there, because the failure is a bullet
    the player never saw rather than anything that looks wrong in a preview.
    """
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return

    frac = read_macro_number("BG_NEAR_EDGE")

    for name, png in _bg_layers():
        if not name.endswith("_near"):
            continue
        alpha = np.asarray(Image.open(png).convert("RGBA").getchannel("A"),
                           dtype=np.uint8)
        w = alpha.shape[1]
        lo = int(w * frac)
        hi = int(w * (1 - frac))
        middle = alpha[:, lo:hi] > 12
        if middle.any():
            cols = np.nonzero(middle.any(axis=0))[0]
            fail("%s puts ink %dpx into the field (columns %d..%d are the "
                 "playfield and a foreground spire there can hide a bullet)"
                 % (name, len(cols), lo, hi))


def check_rotunda_scale_agrees():
    """The far chamber's painting and its quad have to agree about its size.

    `rotunda` in `tools/make_sanctum.py` computes its own perspective: how
    much a gallery ring is foreshortened depends on how far above the eye it
    sits *in the finished frame*, which means the painting has to know how
    many design pixels wide it is going to be hung. That number is
    `HALL_ROT_HW_SCREEN` there and it is derivable here, from the world
    half-width, the distance and the lens.

    Nothing else would notice them drifting apart. The card would still be a
    valid PNG at a valid size on a valid quad, and what it would draw is a
    round room whose rings curve by the wrong amount -- which reads as a
    slightly odd building rather than as a mistake, and which is exactly the
    sort of thing this project has learnt only a measurement finds.
    """
    src_path = os.path.join(ROOT, "tools", "make_sanctum.py")
    with open(src_path, encoding="utf-8") as fh:
        src = fh.read()
    match = re.search(r"^HALL_ROT_HW_SCREEN\s*=\s*([\d.]+)", src, re.M)
    if match is None:
        fail("make_sanctum.py has no HALL_ROT_HW_SCREEN for the far chamber")
        return
    drawn = float(match.group(1))

    field_h = read_macro_number("FIELD_H")
    fov = read_macro_number("HALL_FOV")
    hw = read_macro_number("HALL_ROT_HW")
    z = read_macro_number("HALL_ROT_Z")
    if None in (field_h, fov, hw, z):
        return
    focal = (field_h * 0.5) / math.tan(math.radians(fov * 0.5))
    want = focal * hw / z
    if abs(want - drawn) > 2.0:
        fail("the far chamber is painted %.1f design pixels wide and hung at "
             "%.1f: HALL_ROT_HW_SCREEN in make_sanctum.py disagrees with "
             "HALL_ROT_HW / HALL_ROT_Z in constants.gml"
             % (drawn, want))

def check_scrub_covers_horizon():
    """The hedgerow must never fall below the line it is there to hide.

    The grove's ground plane meets the far wood at one ruled horizontal row
    the full width of the field, and the scrub band is drawn over the join to
    break it. Whether it *does* is a property of the hedge's thinnest stretch
    and not of its average, and it is the sum of four numbers living in three
    files: how tall the band is drawn, how much of it stands above the
    horizon, how far the wave and the dip push it back down, and where the
    art's own crown bottoms out. Every one of them is individually reasonable.
    Nothing was adding them up.

    So the mat in `make_scrub` thinned to a sixth of its height between two
    ellipses, the crown there landed *below* the horizon, and the join showed
    through -- reported as the border peeking out from behind the hedgerow.
    Nothing could have seen it: the build is clean, the sprite is inked, every
    constant is in range, and `tools/shot.py` photographs one frame of a band
    that used to slide, so the bare patch swept past rather than sitting still.

    The near row is what is measured, because it is drawn over the far one and
    is the taller of the two -- so it is the row that does the covering, and
    the check says so rather than assuming it.
    """
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return

    pngs = sorted(glob.glob(os.path.join(ROOT, "sprites", "spr_scn_scrub",
                                         "*.png")))
    pngs = [p for p in pngs if os.sep + "layers" + os.sep not in p]
    if not pngs:
        fail("spr_scn_scrub has no frame to measure")
        return

    alpha = np.asarray(Image.open(pngs[0]).convert("RGBA").getchannel("A"),
                       dtype=np.float32) / 255.0
    height, width = alpha.shape
    solid = alpha > 0.35
    if not solid.any():
        fail("spr_scn_scrub is blank")
        return
    # The lowest crown anywhere along the tile: a column with no ink at all is
    # a hole rather than a low stretch, and scores as the very bottom.
    crown = np.where(solid.any(axis=0), np.argmax(solid, axis=0), height)
    worst = float(crown.max()) / height

    field_w = read_macro_number("FIELD_W")
    rise = read_macro_number("GROVE_SCRUB_RISE")
    wave = read_macro_number("GROVE_SCRUB_WAVE")
    dip = read_macro_number("GROVE_SCRUB_DIP")
    clear = read_macro_number("GROVE_SCRUB_CLEAR")
    near = read_macro_number("GROVE_SCRUB_NEAR")
    far = read_macro_number("GROVE_SCRUB_FAR")

    if near <= far:
        fail("GROVE_SCRUB_NEAR (%g) is not taller than GROVE_SCRUB_FAR (%g), "
             "so the row drawn on top is no longer the row that covers the "
             "horizon and this check is measuring the wrong one" % (near, far))

    # The band as it is actually drawn: `grove_scrub_row` scales the sprite to
    # the field's width times the row's own size, stands `rise` of it above the
    # horizon, and everything below pushes the crown back down.
    band = height * (field_w / width) * near
    margin = band * (worst - rise + dip) + wave
    if margin > -clear:
        where = ("falls %.1fpx *below* the horizon" % margin if margin > 0
                 else "clears the horizon by only %.1fpx" % -margin)
        fail("the hedgerow's thinnest stretch %s, against GROVE_SCRUB_CLEAR "
             "(%gpx) -- the ground/treeline join shows through it. Its lowest "
             "crown is %.0f%% down the canvas against a band %.0fpx tall, "
             "with %gpx of wave and %.0f%% of dip pushing it down; raise the "
             "mat in make_scrub, or spend less on the wave and the dip"
             % (where, clear, worst * 100, band, wave, dip * 100))


IDENT = "[A-Za-z_][A-Za-z_0-9]*"


def check_bands_are_rooted():
    """A scenery band's sideways position is the camera's, or it is the wind.

    The grove's tiled bands -- the far wood, the hedgerow, the canopy -- stand
    on the ground, so the only thing that may move them sideways is the camera
    turning. Each of them nonetheless shipped with a share of an accumulator
    that only ever grows, and the canopy then shipped with a sinusoid, and both
    were reported: a wall of wood panning left for ever in a stage flying
    straight ahead, and branches overhead sliding left and right under their
    own clock while everything else in the frame answered to the player.

    The rule is invisible at the call site -- every one of those arguments is a
    perfectly ordinary number -- which is exactly the case a comment cannot
    hold. So the x of a band draw has to be `grove_rooted_x(...)`, or a
    parameter passed straight through from a caller that is itself checked, and
    `_b.drift` is allowed only in `grove_draw_mist`, because fog is the one
    thing out there that really does travel.

    **Found by scanning rather than by matching**, because this guard's first
    version carried a literal backspace where it meant a word boundary -- an
    escape that survived review, compiled, ran against three deliberate
    violations and reported all three as clean. Which is the `GAME_ERROR`
    lesson exactly: the only thing that separates a guard from a comment is
    watching it fail.
    """
    path = os.path.join(ROOT, "scripts", "bg_grove", "bg_grove.gml")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8-sig") as fh:
        src = fh.read()

    # Which argument of each call carries the band's x.
    where = {"corridor_draw_band": 2, "corridor_draw_band_wave": 2,
             "grove_scrub_row": 3}
    word = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")

    def enclosing(at):
        found = "?"
        for hit in re.finditer("^function (" + IDENT + ")", src, re.M):
            if hit.start() > at:
                break
            found = hit.group(1)
        return found

    for name, index in sorted(where.items()):
        at = -1
        while True:
            at = src.find(name + "(", at + 1)
            if at < 0:
                break
            # A whole word, and not the function's own definition.
            if at and src[at - 1] in word:
                continue
            if src[max(0, at - 9):at] == "function ":
                continue
            depth, args, arg = 0, [], ""
            for ch in src[at + len(name):]:
                if ch in "([":
                    depth += 1
                    if depth == 1:
                        continue
                elif ch in ")]":
                    depth -= 1
                    if depth == 0:
                        args.append(arg)
                        break
                if depth == 1 and ch == ",":
                    args.append(arg)
                    arg = ""
                else:
                    arg += ch
            if len(args) <= index:
                continue
            x = " ".join(args[index].split())
            host = enclosing(at)
            if "grove_rooted_x" in x:
                continue
            if x and all(c in word for c in x):      # passed through by a caller
                continue
            if "drift" in x and host == "grove_draw_mist":
                continue
            fail("%s in %s() takes its x from `%s`, which is neither "
                 "grove_rooted_x nor the mist's drift -- a rooted band may "
                 "only move when the camera turns. See grove_rooted_x"
                 % (name, host, x))


def check_font_accessors_called():
    """A font accessor must be *called*, never passed by name.

    `fnt_small` is a function returning the handle `font_add_sprite_ext` gave
    back for `spr_fnt_small`. Written without its parentheses it is a perfectly
    valid expression -- a reference to the function itself -- which GML happily
    hands to `draw_set_font`, which then throws:

        draw_set_font argument 1 incorrect type (script) expecting a font

    **Nothing else in this project's tooling can see it.** The build is clean
    because the expression is legal. `check_unknown_functions` only looks at
    `name(` and so never considers it. `check_gml_asset_references` was *taught*
    that `fnt_*` names are project functions rather than missing assets, which
    is correct and is precisely what stops it reporting this. And the throw
    happens in a Draw event, which no suite reaches -- this one shipped as a
    crash the first time a boss threw floating text, and was found by a person
    playing the game.

    A general "function referenced without being called" check would be wrong
    here: passing a function by name is ordinary in this codebase -- every
    wave's fire routine and every boss attack is handed over exactly that way.
    What makes the font accessors different is that they exist *only* to be
    called, so for this one family the rule is absolute.
    """
    # **The word boundary is load-bearing.** Without it `\w*` simply backtracks
    # until the negative lookahead succeeds, so `fnt_small(` matches as
    # `fnt_smal` followed by `l(` -- and the check reports every correct call
    # site in the project as a fault. It did, on its first run.
    bare = re.compile(r"(?<![\w.$])(fnt_[a-z_]\w*)\b(?!\s*\()")

    for gml in sorted(glob.glob(os.path.join(ROOT, "**", "*.gml"),
                                recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            lines = fh.readlines()
        for n, line in enumerate(lines, 1):
            code = GML_STRING.sub('""', line).split("//", 1)[0]
            code = re.sub(r"^\s*///.*", "", code)
            for m in bare.finditer(code):
                name = m.group(1)
                # `global.fnt_x = ...` in `ui_init` is the assignment the
                # accessors read; the lookbehind already rejects the dotted
                # form, and this catches the declaration line itself.
                if re.search(r"function\s+%s\s*\(" % re.escape(name), code):
                    continue
                fail("%s:%d uses %s without calling it -- it is a function, "
                     "and `draw_set_font` throws on a script handle. Write "
                     "%s()." % (rel(gml), n, name, name))


def check_sprite_draws_are_explicit():
    """Every sprite draw states its own blend colour and alpha.

    `draw_sprite` is the bare form: it draws with whatever `draw_set_colour`
    and `draw_set_alpha` happen to be set to. That is fine in a routine that
    just set them and a trap everywhere else, because the state it inherits
    can have been left by a *different event on the previous frame*.

    It shipped exactly that. The two `draw_sprite` calls that laid down the
    parallax ground layer were the only bare ones in the game; everything else
    passes `c_white, 1` explicitly. The stage-name splash fades its title text
    out over 34 frames and `draw_text_outline` returned without putting the
    alpha back, so the GUI event ended each of those frames with the alpha
    wound down toward zero -- and the first thing the next frame's Draw event
    does is lay down the ground. The world faded out under the splash and
    snapped back to full the frame the splash stopped drawing.

    **No suite could have caught it and no screenshot scene did either.**
    `tools/test.py` never draws a frame, and every scene `tools/shot.py` poses
    is photographed long after the splash has gone. It was found by a person
    watching the game start.

    The rule is cheap because the codebase already keeps it everywhere else:
    the fix is `draw_sprite_ext(..., c_white, 1)`.
    """
    bare = re.compile(r"(?<![\w.$])draw_sprite\s*\(")

    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gml"),
                                recursive=True)
                      + glob.glob(os.path.join(ROOT, "objects", "**", "*.gml"),
                                  recursive=True)):
        with open(gml, encoding="utf-8-sig") as fh:
            lines = fh.readlines()
        for n, line in enumerate(lines, 1):
            code = GML_STRING.sub('""', line).split("//", 1)[0]
            code = re.sub(r"^\s*///.*", "", code)
            if bare.search(code):
                fail("%s:%d uses bare draw_sprite -- it inherits whatever "
                     "blend colour and alpha were last set, which may be from "
                     "the previous frame's GUI event. Use draw_sprite_ext "
                     "with an explicit colour and alpha."
                     % (rel(gml), n))


def check_rings_block_before_enemies():
    """`obj_game`'s Step must block shots on rings *before* the enemies take
    them.

    A ring stops the player's fire along its metal, and the whole of what makes
    that true is an ordering: `ring_block_shots` removes a shot from the pool,
    so anything that runs after it never sees that shot. Run it the other way
    round and the boss behind a ring takes every hit exactly as if the ring
    were not there -- and the picture is *identical*, because the ring is still
    drawn, the shots still spark on it, and the only difference is a health bar
    going down at the normal rate.

    Nothing else can see it. `test_rings` proves the blocking works and cannot
    prove anybody calls it first; the build is clean either way; and a
    screenshot of a boss being shot through a ring looks like a screenshot of a
    boss being shot. Same shape of rule as `check_run_clears_the_field`, and
    the same reason for it: the bug was never going to be in the function.
    """
    step = os.path.join(ROOT, "objects", "obj_game", "Step_0.gml")
    if not os.path.exists(step):
        fail("objects/obj_game/Step_0.gml is missing")
        return

    with open(step, encoding="utf-8-sig") as fh:
        src = _strip_noise(fh.read())

    block = src.find("ring_block_shots(")
    take = src.find("enemy_take_shots(")
    if block < 0:
        fail("obj_game/Step_0.gml never calls ring_block_shots() -- a ring "
             "that does not eat the player's fire is scenery with a spark "
             "effect on it")
        return
    if take < 0:
        fail("obj_game/Step_0.gml never calls enemy_take_shots()")
        return
    if block > take:
        fail("obj_game/Step_0.gml calls ring_block_shots() after "
             "enemy_take_shots() -- a shot absorbed by a ring has to be gone "
             "before the boss behind it is offered the pool, or the ring "
             "blocks nothing while looking exactly as though it does")


def check_hall_frame_textures():
    """A hall buffer may not be submitted with a multi-frame sprite's page.

    `vertex_submit` takes **one** texture and `bg_sanctum`'s `hall_uv` writes
    coordinates in *page* space, so a buffer holding geometry from two frames
    of a sprite is drawn against whichever page `sprite_get_texture(spr, 0)`
    names. That is correct exactly while the packer has put both frames on the
    same page, and the packer is under no obligation to: adding two tiles to
    the hall's folder repacked the atlas, `spr_hall_banner`'s two frames came
    apart, and one tabard in every other bay came back drawn out of a piece of
    masonry.

    Nothing else can see it. The build is clean, the sprite is present and
    inked, every coordinate is in range, and what lands on screen is a
    perfectly valid picture of the wrong thing -- the same failure this file
    already records about the ceiling drawing the floor's winged discs. It was
    reported by a person looking at the screen.

    **And it cannot be asserted at run time either.** `sprite_get_texture`
    answers a pointer to the frame's own entry rather than to the page it sits
    on -- measured: three single-frame sprites certainly packed together give
    three different pointers -- so no suite can ask whether two frames share a
    page. What can be refused is the construction that needs the question
    asking, which is this. The answer is `hall_submit_frames`: one buffer per
    frame, each drawn with its own frame's texture, right whatever the packer
    does.
    """
    path = os.path.join(ROOT, "scripts", "bg_sanctum", "bg_sanctum.gml")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8-sig") as fh:
        src = _strip_noise(fh.read())

    pattern = re.compile(
        r"hall_submit\s*\([^;]*?sprite_get_texture\s*\(\s*(\w+)\s*,")
    seen = set()
    for match in pattern.finditer(src):
        spr = match.group(1)
        if spr in seen:
            continue
        seen.add(spr)
        yy = os.path.join(ROOT, "sprites", spr, spr + ".yy")
        if not os.path.exists(yy):
            continue
        with open(yy, encoding="utf-8-sig") as fh:
            frames = fh.read().count('"$GMSpriteFrame"')
        if frames > 1:
            fail("bg_sanctum submits a buffer with %s's page, and %s has %d "
                 "frames -- a buffer mixing frames is drawn against one page "
                 "and is right only while the packer happens to keep them "
                 "together. Use hall_submit_frames()." % (spr, spr, frames))


# The geometry writers in `bg_sanctum`, and which argument of each carries the
# sprite its texture coordinates are read from.
_HALL_WRITERS = {
    "hall_tiles": 5, "hall_quad": 5, "hall_face": 1, "hall_face_u": 1,
    "hall_face_z": 1, "hall_cross": 1, "hall_taper": 9, "hall_sphere": 7,
    "hall_ring": 9, "hall_lathe": 6,
}


def _hall_args(src, start):
    """The argument list of the call whose name ends at `start`, split at the
    commas that are not inside brackets."""
    i = src.find("(", start)
    if i < 0:
        return []
    depth = 0
    args = [""]
    for j in range(i, len(src)):
        ch = src[j]
        if ch in "([{":
            depth += 1
            if depth == 1:
                continue
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return [a.strip() for a in args]
        if depth == 1 and ch == ",":
            args.append("")
            continue
        args[-1] += ch
    return [a.strip() for a in args]


def check_hall_buffer_textures():
    """A hall buffer may not be written from one sprite and drawn with another.

    `vertex_submit` takes **one** texture and `bg_sanctum`'s `hall_uv` writes
    coordinates in *page* space, so a buffer's geometry is drawn against
    whichever page the submit binds. Write it from a second sprite and what
    those coordinates index is whatever the packer happened to leave at that
    spot on the bound page -- which is correct exactly while the two sprites
    land together, and the packer is under no obligation to keep them there.

    That is the rule `hall_build_case` states in a comment, and the pedestals
    broke it twice: the shaft was textured `spr_hall_deskface` and rode in the
    buffer submitted with `spr_hall_plinth`, and the cap was textured
    `spr_hall_pale` and rode in the one submitted with `spr_hall_stone`. It was
    reported as the pedestals *sometimes* coming back as white paper, and
    "sometimes" is the whole diagnosis -- a repack that separated the two
    sprites put the shaft's coordinates over a blank corner of another page.

    Nothing else could see it. The build is clean, both sprites exist and are
    inked, every coordinate is in range, and what lands on screen is a
    perfectly valid picture of the wrong thing. This is
    `check_hall_frame_textures`' rule between two *sprites* rather than
    between two frames of one, and it was tested against a deliberate
    violation before being believed.

    A slot whose submit names no sprite statically -- the orrery's rings carry
    theirs on the struct -- is skipped rather than guessed at.
    """
    path = os.path.join(ROOT, "scripts", "bg_sanctum", "bg_sanctum.gml")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8-sig") as fh:
        src = _strip_noise(fh.read())

    # locals standing in for a sprite, either directly or through its texture
    alias = {}
    for m in re.finditer(r"\bvar\s+(_\w+)\s*=\s*(spr_\w+)\s*;", src):
        alias[m.group(1)] = m.group(2)
    for m in re.finditer(
            r"\bvar\s+(_\w+)\s*=\s*sprite_get_texture\s*\(\s*(spr_\w+)",
            src):
        alias[m.group(1)] = m.group(2)

    def sprite_of(expr):
        expr = expr.strip()
        if expr.startswith("spr_"):
            return expr
        return alias.get(expr)

    # every geometry write, as (buffer expression, sprite)
    writes = []
    for name, idx in _HALL_WRITERS.items():
        for m in re.finditer(r"\b%s\s*\(" % name, src):
            args = _hall_args(src, m.start())
            if len(args) <= idx:
                continue
            writes.append((m.start(), args[0], sprite_of(args[idx])))

    # ...and the functions they sit in, so a fill handed to hall_prop_buffer
    # can be resolved back to what it writes
    funcs = [(m.start(), m.group(1))
             for m in re.finditer(r"\bfunction\s+(\w+)\s*\(", src)]
    func_sprites = {}
    for pos, buf, spr in writes:
        if not buf.startswith("_vb") or spr is None:
            continue
        owner = None
        for fpos, fname in funcs:
            if fpos < pos:
                owner = fname
            else:
                break
        if owner:
            func_sprites.setdefault(owner, set()).add(spr)

    slot_writes = {}

    def note(slot, sprites):
        if slot and sprites:
            slot_writes.setdefault(slot, set()).update(sprites)

    member = re.compile(r"^[\w.\[\]]*\.(\w+)(?:\[[^\]]*\])?$")
    for _pos, buf, spr in writes:
        m = member.match(buf)
        if m and spr:
            note(m.group(1), {spr})

    # a slot filled through hall_prop_buffer, by named function or inline
    for m in re.finditer(r"(\w+)\s*:\s*hall_prop_buffer\s*\(", src):
        args = _hall_args(src, m.end(1))
        if len(args) < 2:
            continue
        fill = args[1].strip()
        if re.fullmatch(r"\w+", fill):
            note(m.group(1), func_sprites.get(fill, set()))
        else:
            note(m.group(1), set(re.findall(r"\bspr_\w+", fill)))

    # what each slot is actually drawn with
    slot_subs = {}
    unresolved = set()
    for m in re.finditer(r"\bhall_submit\s*\(", src):
        args = _hall_args(src, m.start())
        if len(args) < 2:
            continue
        sm = member.match(args[0])
        if not sm:
            continue
        slot = sm.group(1)
        tex = re.match(r"sprite_get_texture\s*\(\s*([^,\s]+)", args[1])
        spr = sprite_of(tex.group(1)) if tex else sprite_of(args[1])
        if spr is None:
            unresolved.add(slot)
            continue
        slot_subs.setdefault(slot, set()).add(spr)

    for slot in sorted(slot_writes):
        if slot in unresolved or slot not in slot_subs:
            continue
        stray = slot_writes[slot] - slot_subs[slot]
        if stray:
            fail("bg_sanctum writes .%s from %s but submits it with %s -- a "
                 "buffer is drawn against one page, so geometry from another "
                 "sprite indexes whatever the packer left at those "
                 "coordinates. One buffer per texture."
                 % (slot, ", ".join(sorted(stray)),
                    ", ".join(sorted(slot_subs[slot]))))


def check_texture_groups_exist(yyp):
    """A sprite may not name a texture group the project does not have.

    GameMaker does not complain: an unknown `textureGroupId` falls back to
    Default and the sprite packs there, so the group is *silently* not applied
    and nothing anywhere says so. What that hides is a mitigation that was
    never wired up -- five of the hall's multi-frame sprites named a
    `HallFrames` group, presumably to force each sprite's frames onto one page,
    and the group had never been added to the `.yyp`. It is the `GAME_ERROR`
    shape again: the thing that makes it hard to notice is that the sprites
    look exactly as though the group is doing its job.

    (The hall no longer needs one. `hall_submit_frames` is right whatever the
    packer does, which is the whole argument for building it that way.)
    """
    if yyp is None:
        return
    known = {g.get("name") for g in yyp.get("TextureGroups", [])}
    if not known:
        return
    for yy in glob.glob(os.path.join(ROOT, "sprites", "*", "*.yy")):
        if yy.endswith(".old.yy"):
            continue
        data = load_yy(yy)
        if not isinstance(data, dict):
            continue
        group = (data.get("textureGroupId") or {}).get("name")
        if group and group not in known:
            fail("%s names texture group %r, which %s.yyp does not have -- "
                 "GameMaker falls back to Default silently, so the grouping "
                 "is not being applied."
                 % (rel(yy), group, PROJECT))


def main():
    yyp_path = os.path.join(ROOT, PROJECT + ".yyp")
    yyp = load_yy(yyp_path)
    load_yy(os.path.join(ROOT, PROJECT + ".resource_order"))

    if yyp is not None:
        check_yyp_resources(yyp)
        check_texture_groups_exist(yyp)
        check_resource_folders(yyp)
        check_gml_asset_references(yyp)
    check_record_shapes()
    check_object_events()
    check_room_creation_code()
    check_room_instances()
    check_script_function_names(yyp or {})
    check_scripts_registered()
    check_unknown_functions()
    check_call_arity()
    check_duplicate_function_definitions()
    check_shadowed_builtins()
    check_legacy_globals()
    check_macro_references()
    check_sprite_texture_pages()
    check_font_ink_ratio()
    check_font_digit_mid()
    check_bg_seams()
    check_bg_keepout()
    check_scrub_covers_horizon()
    check_rotunda_scale_agrees()
    check_bands_are_rooted()
    check_font_accessors_called()
    check_sprite_draws_are_explicit()
    check_run_clears_the_field()
    check_rings_block_before_enemies()
    check_hall_frame_textures()
    check_hall_buffer_textures()
    check_sprites_not_blank()
    check_enum_references()
    check_brace_balance()
    check_delta_time_in_rules()

    if problems:
        print("%d problem(s) found:\n" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("project checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
