#!/usr/bin/env python3
"""Static checks GameMaker doesn't do: resource registration and `.yy` shape,
object events, undefined macros and functions, call arity, legacy globals,
blank sprite frames, metrics shared with the generators, and guards for
specific past bugs.

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

    GameMaker's folders are virtual (only the Folders list in the .yyp), so a
    resource pointing at an undeclared folder, or one declared at different
    case, looks fine until GameMaker refuses to load the project with "Cannot
    find folder path". Folder paths are case sensitive.
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

    `score`, `health` and `lives` are built-in globals kept from GM8. An
    instance variable with one of those names splits in two: `inst.score = 5`
    writes an instance variable, while a bare `score` in that object's own
    events reads the global. Nothing reports it; the value just never arrives.
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
    """Every SHOUTING_SNAKE identifier in the GML must be a macro that exists.

    GameMaker compiles an undefined identifier as a variable read, so the build
    is clean and the game throws at run time, which under `tools/test.py` and
    `tools/shot.py` is a modal dialog and so a hang until the timeout.
    GameMaker's own built-ins are almost all lower-case, so an upper-case
    identifier here is a project macro or a mistake; the few upper-case
    built-ins are listed below.
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

    # Enum members are written `Enum.Member`, which this pattern never
    # matches; they are collected above so a bare one isn't reported either.
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

    GameMaker doesn't refuse an oversized sprite: it halves it, logs one
    warning ("rescaled from 2100,1080 to 1050,540"), and the game runs with the
    sprite at half resolution. The page also carries a border per sprite, so
    the usable width is a little under the nominal size.
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

    # Only the platforms this project builds; the mobile pages stay at 2048.
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

    Every pool is a global that outlives a room, so a run that doesn't clear
    them starts with the previous run's bullets, lasers, items and enemies,
    including a boss still firing. `test_run_starts_clean` proves
    `run_clear_field` empties everything; this checks that it is called.
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


# Sprites whose frames are a catalogue rather than an animation, where an
# empty frame is intentional. Each entry gives its reason.
BLANK_FRAMES_OK = {
    "spr_scn_charm_lit": "two charms have no glowing part; see make_grove.py",
}


def check_sprites_not_blank():
    """No sprite frame may be entirely transparent.

    With the project open in the GameMaker IDE, its cached copy of a sprite can
    be written back over one a `make_*` script just produced, reverting the
    `.yy` and leaving some or all frames blank, with a clean build. Every frame
    is checked. The fix is to re-run the generator that owns the sprite with
    the IDE closed. `BLANK_FRAMES_OK` lists the sprites whose empty frames are
    intentional.
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

    GameMaker reports this only at compile time. Only identifiers declared as
    enums are checked, so a struct field reached through a dot is never
    mistaken for one.
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
    """One #macro's value from constants.gml, integer or decimal (`read_macros`
    reads integers only).
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
    `.gml` is invisible to it, and calls into it compile into calls to nothing.
    """
    for gml in sorted(glob.glob(os.path.join(ROOT, "scripts", "*", "*.gml"))):
        yy = gml[:-4] + ".yy"
        if not os.path.exists(yy):
            fail("%s has no .yy -- the script is not registered, and every "
                 "call to it compiles into a call to nothing (run "
                 "tools/scaffold.py)" % rel(gml))


def check_brace_balance():
    """Every .gml file must have as many { as }.

    A missing brace is a compile error nothing else here notices, and scripted
    edits (a regex that eats one line too many) are how it happens. Strings and
    comments are stripped first, so a brace inside either doesn't count.
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

    A misspelled field is valid JSON, but GameMaker refuses to open the project
    (`Field "isDnd": expected`). The casing differs between record kinds (a
    room instance has "isDnd", an object event "isDnD"), so copying one to the
    other is the easy mistake. Records are compared against their siblings in
    the same file rather than against a schema.
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

    GameMaker only creates the instances instanceCreationOrder names; one that
    is only in a layer shows in the room editor and never exists in game.
    `gm_new.room` writes both lists. Creation code is checked too:
    hasCreationCode wants an InstanceCreationCode_<name>.gml beside the room,
    and a file with no instance to attach to is ignored silently.
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
    would report every one of them.
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

    # A project function whose name starts with an asset prefix isn't a
    # missing asset: `fnt_ui()` is an accessor for a font's handle.
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

    GameMaker compiles a call to a function that doesn't exist, and the game
    throws when the line is reached, which under the harnesses is a hang. Calls
    through a dot are struct methods and are skipped. String literals are
    stripped along with comments, because test names read like English and
    would otherwise scan as calls.
    """
    builtins = _runtime_function_names()
    if builtins is None:
        # No runtime to read. A hand-kept list of built-ins would go stale, so
        # the check stands down.
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

    # Instance methods, and functions handed in as arguments. Every local and
    # argument starts with an underscore by convention, so a leading
    # underscore means a value, not a global function.
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

    Comments become spaces and strings become `"xxx"` (a placeholder rather
    than blank, so an argument list stays countable). Length is preserved so a
    match offset still names the right line in the original.
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
    """Every call to a project function must pass a number of arguments it
    takes.

    GML binds missing arguments to `undefined` rather than refusing the call,
    so the failure surfaces wherever the value is finally used, possibly in a
    Draw event no suite reaches. Only project functions are checked; the
    runtime's arities aren't available in a usable form.
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
    """No script may read `delta_time`: the game is fixed-step and measures
    time in frames, which is what lets the tests drive it headlessly. Object
    events are not scanned.
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

    A sprite font's `string_height` returns the atlas cell, not the ink, and
    the HUD lays itself out in ink by multiplying by `FONT_INK_RATIO`. The
    constant would go stale silently when `make_fonts.py` changes a size or
    padding, so it is checked against the PNGs.
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

    `text_digit_middle_y` centres a digit's ink with these ratios (for the
    boss's percentage and the dial's clock), so a regenerated font that moved
    its digits would put every counter off-centre. Measured as the mean, over
    the ten digits, of where the ink's middle sits above the bottom of the
    cell, as a fraction of the cell.
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

    Each layer is drawn twice, at `y` and at `y - GAME_H`, so a mismatch
    between its first and last rows is a line sweeping up the screen. The join
    is measured against the layer's own texture: it fails if it differs by more
    than three times the layer's typical adjacent-row difference.
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
        # The floor keeps a perfectly flat layer (adjacent delta 0) from
        # failing automatically.
        budget = max(1.0, adjacent * 3.0)
        if join > budget:
            fail("%s does not tile top to bottom: its join differs by %.2f "
                 "against %.2f between ordinary adjacent rows -- a seam will "
                 "sweep up the screen once a cycle" % (name, join, adjacent))


def check_bg_keepout():
    """The near parallax layer must leave the middle of the screen alone: it is
    drawn over the field, so anything in the centre could hide a bullet. The
    generator's window (`make_near`) keeps it clear; this checks the window is
    still there.
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

    `rotunda` in `tools/make_sanctum.py` paints its own perspective for the
    design-pixel width it will be drawn at (`HALL_ROT_HW_SCREEN` there), which
    is derivable here from the world half-width, the distance and the lens. If
    the two drift apart, the rings curve by the wrong amount and nothing else
    notices.
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
    """The grove's hedgerow must never fall below the horizon it hides.

    The ground plane meets the far wood at one horizontal row, and the scrub
    band is drawn over the join. Whether it covers it depends on the hedge's
    thinnest stretch and on four numbers in three files: the band's drawn
    height, how much of it stands above the horizon, how far the wave and dip
    push it down, and where the art's crown bottoms out. The near row is
    measured, because it is drawn over the far one and is the taller.
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
    """A grove scenery band's sideways position must follow the camera.

    The tiled bands (far wood, hedgerow, canopy) stand on the ground, so only
    the camera may move them sideways. The x of a band draw has to be
    `grove_rooted_x(...)`, or a parameter passed straight through from a
    checked caller; `_b.drift` is allowed only in `grove_draw_mist`, since the
    mist is the one thing that drifts.
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
    """A font accessor must be called, never passed by name.

    `fnt_ui` without parentheses is a valid reference to the function, which
    `draw_set_font` accepts and then throws on ("argument 1 incorrect type
    (script) expecting a font"), in a Draw event no suite reaches. Nothing else
    catches it, because `check_gml_asset_references` treats `fnt_*` names as
    project functions. Passing functions by name is ordinary elsewhere in this
    codebase; the font accessors exist only to be called.
    """
    # The word boundary matters: without it `\w*` backtracks until the
    # lookahead succeeds, so `fnt_ui(` would match as `fnt_u` followed by
    # `i(`.
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

    A bare `draw_sprite` uses whatever colour and alpha were last set, possibly
    by a different event on the previous frame (a fading splash once faded the
    ground layer with it). Use `draw_sprite_ext(..., c_white, 1)`.
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
    """`obj_game`'s Step must block shots on rings before the enemies take
    them.

    `ring_block_shots` removes a blocked shot from the pool, so it has to run
    first; the other way round, a boss behind a ring takes every hit and the
    picture looks identical. `test_rings` proves the blocking works but can't
    prove the order.
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

    `vertex_submit` takes one texture and `hall_uv` writes coordinates in page
    space, so a buffer holding geometry from two frames of a sprite is right
    only while the packer keeps both frames on one page; a repack that splits
    them draws one frame out of whatever else is on the page. It can't be
    asserted at run time (`sprite_get_texture` returns a per-frame pointer, not
    the page), so this refuses the construction. `hall_submit_frames` gives
    each frame its own buffer.
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

    The same rule as `check_hall_frame_textures`, between two sprites rather
    than two frames of one: a buffer's page-space coordinates index whatever is
    at that spot on the page it is submitted with, which is right only while
    the packer keeps both sprites together. A slot whose submit names no sprite
    statically (the orrery's rings carry theirs on the struct) is skipped.
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
    """A sprite may not name a texture group the project doesn't have. An
    unknown `textureGroupId` silently falls back to Default, so the group is
    never applied and nothing says so.
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
