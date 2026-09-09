#!/usr/bin/env python3
"""Create GameMaker resources and register them everywhere they must appear.

A resource is never in one place. A script is a `.gml`, a `.yy`, a line in
`Wordsearch.yyp` and a line in `Wordsearch.resource_order`; a sprite adds a PNG
per frame plus a second copy under `layers/`; an object's events are stored
both as `.gml` files and as entries in its own `eventList`. Miss one and the
failure is silent in a different way each time -- the project won't open, or
the asset won't resolve, or GameMaker draws nothing and mentions it to nobody.

This module is the single place that knows those pairings. Everything that
generates art or code for this project goes through it.

**Every GUID is derived from the resource's name**, not generated fresh, so
re-running a generator writes byte-identical files and produces no diff. That
is what makes the art scripts safe to re-run.

Import it; there is no command line:

    import gm_new
    gm_new.folder("Scripts/engine")
    gm_new.script("grid_functions", body, folder="Scripts/engine")
    gm_new.sprite("spr_rune", [img], origin="center", folder="Sprites/board")
    gm_new.obj("obj_grid", {"Create_0": code}, folder="Objects")
"""
import json
import os
import re
import shutil
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

NAMESPACE = uuid.UUID("6f9d1e2a-7c34-4b58-9a01-2d5e8f3b6c47")


def _project():
    for fn in os.listdir(ROOT):
        if fn.endswith(".yyp"):
            return fn[:-4]
    raise SystemExit("no .yyp found in %s" % ROOT)


PROJECT = _project()
YYP = os.path.join(ROOT, PROJECT + ".yyp")
ORDER = os.path.join(ROOT, PROJECT + ".resource_order")

# Event file stem -> (eventType, eventNum).
EVENTS = {
    "Create_0": (0, 0),
    "Destroy_0": (1, 0),
    "Alarm_0": (2, 0),
    "Alarm_1": (2, 1),
    "Step_0": (3, 0),
    "Step_1": (3, 1),    # Begin Step
    "Step_2": (3, 2),    # End Step
    "Other_4": (7, 4),   # Room Start
    "Other_5": (7, 5),   # Room End
    "Other_10": (7, 10), # User Event 0
    "Draw_0": (8, 0),
    "Draw_64": (8, 64),  # Draw GUI
    "Draw_72": (8, 72),  # Draw Begin
    "Draw_73": (8, 73),  # Draw End
    "Draw_74": (8, 74),  # Draw GUI Begin
    "Draw_75": (8, 75),  # Draw GUI End
    "CleanUp_0": (12, 0),
}


def guid(*parts):
    """A stable GUID for a named thing, so regeneration is a no-op."""
    return str(uuid.uuid5(NAMESPACE, "/".join(parts)))


def read(path):
    with open(path, encoding="utf-8-sig") as fh:
        return fh.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def validate(path):
    """Parse GameMaker's JSON-with-trailing-commas to prove an edit is sound."""
    text = read(path)
    try:
        json.loads(re.sub(r",(\s*[}\]])", r"\1", text))
    except json.JSONDecodeError as exc:
        raise SystemExit("%s is now malformed: %s" % (path, exc))


# ---------------------------------------------------------------------------
# .yyp / .resource_order registration
# ---------------------------------------------------------------------------

def _add_to_list(path, key, entry):
    """Add `entry` as the first element of the JSON list named `key`.

    Insertion is **after the opening bracket**, never before the closing one:
    the closing `],` of one list is textually identical to every other, so
    anchoring on it puts the entry in whichever list happens to match first.
    Handles both the empty form (`"key":[],`) and a list with contents.
    """
    text = read(path)
    if entry in text:
        return

    empty = '"%s":[],' % key
    if empty in text:
        write(path, text.replace(empty, '"%s":[\n%s\n  ],' % (key, entry)))
    else:
        opening = '"%s":[' % key
        if opening not in text:
            raise SystemExit("no %r list in %s" % (key, path))
        write(path, text.replace(opening, opening + "\n" + entry, 1))
    validate(path)


def register(name, rel_path, order=0):
    """Add a resource to the .yyp resource list and the resource order."""
    _add_to_list(YYP, "resources",
                 '    {"id":{"name":"%s","path":"%s",},},' % (name, rel_path))
    _add_to_list(ORDER, "ResourceOrderSettings",
                 '    {"name":"%s","order":%d,"path":"%s",},'
                 % (name, order, rel_path))


def folder(path, order=0):
    """Ensure an asset-tree folder exists. `path` is like "Objects/board"."""
    parts = path.split("/")
    for depth in range(len(parts)):
        sub = "/".join(parts[:depth + 1])
        name = parts[depth]
        folder_path = "folders/%s.yy" % sub

        if '"%s"' % folder_path not in read(YYP):
            _add_to_list(YYP, "Folders",
                         '    {"$GMFolder":"","%%Name":"%s","folderPath":"%s",'
                         '"name":"%s","resourceType":"GMFolder",'
                         '"resourceVersion":"2.0",},' % (name, folder_path, name))
        if '"%s"' % folder_path not in read(ORDER):
            _add_to_list(ORDER, "FolderOrderSettings",
                         '    {"name":"%s","order":%d,"path":"%s",},'
                         % (name, order, folder_path))

    return "folders/%s.yy" % path


def _parent(folder_path):
    if not folder_path:
        return '"name":"%s",\n    "path":"%s.yyp",' % (PROJECT, PROJECT)
    name = folder_path.split("/")[-1]
    return '"name":"%s",\n    "path":"folders/%s.yy",' % (name, folder_path)


# ---------------------------------------------------------------------------
# Scripts
# ---------------------------------------------------------------------------

SCRIPT_YY = """{
  "$GMScript":"v1",
  "%%Name":"%(name)s",
  "isCompatibility":false,
  "isDnD":false,
  "name":"%(name)s",
  "parent":{
    %(parent)s
  },
  "resourceType":"GMScript",
  "resourceVersion":"2.0",
}"""


def script(name, body=None, folder=None, order=0):
    """Create a script asset, or register one whose .gml is authored elsewhere.

    `body=None` means "leave whatever .gml is on disk alone" -- most of this
    project's GML is written as files rather than as Python strings, and this
    is what lets the same call register it without clobbering it.
    """
    d = os.path.join(ROOT, "scripts", name)
    gml = os.path.join(d, name + ".gml")
    if body is not None:
        write(gml, body)
    elif not os.path.exists(gml):
        raise SystemExit("scripts/%s/%s.gml does not exist and no body given"
                         % (name, name))
    write(os.path.join(d, name + ".yy"),
          SCRIPT_YY % {"name": name, "parent": _parent(folder)})
    register(name, "scripts/%s/%s.yy" % (name, name), order)


# ---------------------------------------------------------------------------
# Objects
# ---------------------------------------------------------------------------

OBJECT_YY = """{
  "$GMObject":"",
  "%%Name":"%(name)s",
  "eventList":[
%(events)s
  ],
  "managed":true,
  "name":"%(name)s",
  "overriddenProperties":[],
  "parent":{
    %(parent)s
  },
  "parentObjectId":%(parent_object)s,
  "persistent":%(persistent)s,
  "physicsAngularDamping":0.1,
  "physicsDensity":0.5,
  "physicsFriction":0.2,
  "physicsGroup":1,
  "physicsKinematic":false,
  "physicsLinearDamping":0.1,
  "physicsObject":false,
  "physicsRestitution":0.1,
  "physicsSensor":false,
  "physicsShape":1,
  "physicsShapePoints":[],
  "physicsStartAwake":true,
  "properties":[],
  "resourceType":"GMObject",
  "resourceVersion":"2.0",
  "solid":false,
  "spriteId":%(sprite)s,
  "spriteMaskId":null,
  "visible":true,
}"""

EVENT_LINE = ('    {"$GMEvent":"v1","%%Name":"","collisionObjectId":null,'
              '"eventNum":%d,"eventType":%d,"isDnD":false,"name":"",'
              '"resourceType":"GMEvent","resourceVersion":"2.0",},')


def _ref(name, kind):
    if not name:
        return "null"
    return '{\n    "name":"%s",\n    "path":"%s/%s/%s.yy",\n  }' % (
        name, kind, name, name)


def obj(name, events=None, sprite=None, parent_object=None, persistent=False,
        folder=None, order=0):
    """Create or overwrite an object. `events` maps event stem -> GML source.

    The event `.gml` files and the `eventList` are written from the same dict,
    which is the whole point: they cannot drift apart.
    """
    events = events or {}
    d = os.path.join(ROOT, "objects", name)

    for stem in events:
        if stem not in EVENTS:
            raise SystemExit("unknown event %r (add it to gm_new.EVENTS)" % stem)

    # Drop event files that are no longer declared, so an object can shrink.
    if os.path.isdir(d):
        for fn in os.listdir(d):
            if fn.endswith(".gml") and fn[:-4] not in events:
                os.remove(os.path.join(d, fn))

    for stem, body in events.items():
        if body is not None:
            write(os.path.join(d, stem + ".gml"), body)
        elif not os.path.exists(os.path.join(d, stem + ".gml")):
            raise SystemExit("objects/%s/%s.gml does not exist and no body given"
                             % (name, stem))

    lines = []
    for stem in events:
        etype, enum = EVENTS[stem]
        lines.append(EVENT_LINE % (enum, etype))

    write(os.path.join(d, name + ".yy"), OBJECT_YY % {
        "name": name,
        "events": "\n".join(lines),
        "parent": _parent(folder),
        "parent_object": _ref(parent_object, "objects"),
        "persistent": "true" if persistent else "false",
        "sprite": _ref(sprite, "sprites"),
    })
    register(name, "objects/%s/%s.yy" % (name, name), order)


# ---------------------------------------------------------------------------
# Sprites
# ---------------------------------------------------------------------------

SPRITE_YY = """{
  "$GMSprite":"v2",
  "%%Name":"%(name)s",
  "bboxMode":%(bbox_mode)d,
  "bbox_bottom":%(bbox_bottom)d,
  "bbox_left":%(bbox_left)d,
  "bbox_right":%(bbox_right)d,
  "bbox_top":%(bbox_top)d,
  "collisionKind":1,
  "collisionTolerance":0,
  "DynamicTexturePage":false,
  "edgeFiltering":false,
  "For3D":false,
  "frames":[
%(frames)s
  ],
  "gridX":0,
  "gridY":0,
  "height":%(height)d,
  "HTile":false,
  "layers":[
    {"$GMImageLayer":"","%%Name":"%(layer)s","blendMode":0,"displayName":"default","isLocked":false,"name":"%(layer)s","opacity":100.0,"resourceType":"GMImageLayer","resourceVersion":"2.0","visible":true,},
  ],
  "name":"%(name)s",
  "nineSlice":null,
  "origin":%(origin_kind)d,
  "parent":{
    %(parent)s
  },
  "preMultiplyAlpha":false,
  "resourceType":"GMSprite",
  "resourceVersion":"2.0",
  "sequence":{
    "$GMSequence":"v1",
    "%%Name":"%(name)s",
    "autoRecord":true,
    "backdropHeight":768,
    "backdropImageOpacity":0.5,
    "backdropImagePath":"",
    "backdropWidth":1366,
    "backdropXOffset":0.0,
    "backdropYOffset":0.0,
    "events":{
      "$KeyframeStore<MessageEventKeyframe>":"",
      "Keyframes":[],
      "resourceType":"KeyframeStore<MessageEventKeyframe>",
      "resourceVersion":"2.0",
    },
    "eventStubScript":null,
    "eventToFunction":{},
    "length":%(count)d.0,
    "lockOrigin":false,
    "moments":{
      "$KeyframeStore<MomentsEventKeyframe>":"",
      "Keyframes":[],
      "resourceType":"KeyframeStore<MomentsEventKeyframe>",
      "resourceVersion":"2.0",
    },
    "name":"%(name)s",
    "playback":1,
    "playbackSpeed":%(fps).1f,
    "playbackSpeedType":0,
    "resourceType":"GMSequence",
    "resourceVersion":"2.0",
    "seqHeight":%(height)d.0,
    "seqWidth":%(width)d.0,
    "showBackdrop":true,
    "showBackdropImage":false,
    "timeUnits":1,
    "tracks":[
      {"$GMSpriteFramesTrack":"","builtinName":0,"events":[],"inheritsTrackColour":true,"interpolation":1,"isCreationTrack":false,"keyframes":{"$KeyframeStore<SpriteFrameKeyframe>":"","Keyframes":[
%(keyframes)s
          ],"resourceType":"KeyframeStore<SpriteFrameKeyframe>","resourceVersion":"2.0",},"modifiers":[],"name":"frames","resourceType":"GMSpriteFramesTrack","resourceVersion":"2.0","spriteId":null,"trackColour":0,"tracks":[],"traits":0,},
    ],
    "visibleRange":null,
    "volume":1.0,
    "xorigin":%(xorigin)d,
    "yorigin":%(yorigin)d,
  },
  "swatchColours":null,
  "swfPrecision":0.5,
  "textureGroupId":{
    "name":"%(texgroup)s",
    "path":"texturegroups/%(texgroup)s",
  },
  "type":0,
  "VTile":false,
  "width":%(width)d,
}"""

FRAME_LINE = ('    {"$GMSpriteFrame":"v1","%%Name":"%(id)s","name":"%(id)s",'
              '"resourceType":"GMSpriteFrame","resourceVersion":"2.0",},')

KEYFRAME_LINE = """            {"$Keyframe<SpriteFrameKeyframe>":"","Channels":{
                "0":{"$SpriteFrameKeyframe":"","Id":{"name":"%(id)s","path":"sprites/%(sprite)s/%(sprite)s.yy",},"resourceType":"SpriteFrameKeyframe","resourceVersion":"2.0",},
              },"Disabled":false,"id":"%(key)s","IsCreationKey":false,"Key":%(index)d.0,"Length":1.0,"resourceType":"Keyframe<SpriteFrameKeyframe>","resourceVersion":"2.0","Stretch":false,},"""


def sprite(name, images, origin="topleft", folder=None, fps=30.0, order=0,
           texgroup="Default", bbox=None):
    """Create or overwrite a sprite from a list of PIL images (one per frame).

    `origin` is "topleft", "center", or an (x, y) tuple.
    `bbox` is (left, top, right, bottom); it defaults to the full frame.
    """
    if not images:
        raise SystemExit("sprite %s has no frames" % name)

    width, height = images[0].size
    for img in images:
        if img.size != (width, height):
            raise SystemExit("sprite %s has frames of differing size" % name)

    if origin == "topleft":
        xo, yo, kind = 0, 0, 0
    elif origin == "center":
        xo, yo, kind = width // 2, height // 2, 4
    else:
        xo, yo, kind = int(origin[0]), int(origin[1]), 9

    if bbox is None:
        bbox = (0, 0, width - 1, height - 1)

    d = os.path.join(ROOT, "sprites", name)
    layers_dir = os.path.join(d, "layers")
    if os.path.isdir(layers_dir):
        shutil.rmtree(layers_dir)
    for fn in (os.listdir(d) if os.path.isdir(d) else []):
        if fn.endswith(".png"):
            os.remove(os.path.join(d, fn))

    layer_id = guid(name, "layer")
    frame_ids = []
    os.makedirs(d, exist_ok=True)
    for i, img in enumerate(images):
        fid = guid(name, "frame", str(i))
        frame_ids.append(fid)
        img.save(os.path.join(d, fid + ".png"))
        sub = os.path.join(layers_dir, fid)
        os.makedirs(sub, exist_ok=True)
        img.save(os.path.join(sub, layer_id + ".png"))

    frames = "\n".join(FRAME_LINE % {"id": f} for f in frame_ids)
    keyframes = "\n".join(
        KEYFRAME_LINE % {"id": f, "sprite": name, "index": i,
                         "key": guid(name, "key", str(i))}
        for i, f in enumerate(frame_ids))

    write(os.path.join(d, name + ".yy"), SPRITE_YY % {
        "name": name, "width": width, "height": height,
        "frames": frames, "keyframes": keyframes, "count": len(images),
        "layer": layer_id, "parent": _parent(folder), "fps": fps,
        "origin_kind": kind, "xorigin": xo, "yorigin": yo,
        "bbox_mode": 2 if bbox else 0,
        "bbox_left": bbox[0], "bbox_top": bbox[1],
        "bbox_right": bbox[2], "bbox_bottom": bbox[3],
        "texgroup": texgroup,
    })
    register(name, "sprites/%s/%s.yy" % (name, name), order)


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

ROOM_YY = """{
  "$GMRoom":"v1",
  "%%Name":"%(name)s",
  "creationCodeFile":"%(creation)s",
  "inheritCode":false,
  "inheritCreationOrder":false,
  "inheritLayers":false,
  "instanceCreationOrder":[
%(order_list)s
  ],
  "isDnd":false,
  "layers":[
    {"$GMRInstanceLayer":"","%%Name":"Instances","depth":0,"effectEnabled":true,"effectType":null,"gridX":32,"gridY":32,"hierarchyFrozen":false,"inheritLayerDepth":false,"inheritLayerSettings":false,"inheritSubLayers":true,"inheritVisibility":true,"instances":[
%(instances)s
    ],"layers":[],"name":"Instances","properties":[],"resourceType":"GMRInstanceLayer","resourceVersion":"2.0","userdefinedDepth":false,"visible":true,},
    {"$GMRBackgroundLayer":"","%%Name":"Background","animationFPS":15.0,"animationSpeedType":0,"colour":%(colour)d,"depth":100,"effectEnabled":true,"effectType":null,"gridX":32,"gridY":32,"hierarchyFrozen":false,"hspeed":0.0,"htiled":false,"inheritLayerDepth":false,"inheritLayerSettings":false,"inheritSubLayers":true,"inheritVisibility":true,"layers":[],"name":"Background","properties":[],"resourceType":"GMRBackgroundLayer","resourceVersion":"2.0","spriteId":null,"stretch":false,"userdefinedAnimFPS":false,"userdefinedDepth":false,"visible":true,"vspeed":0.0,"vtiled":false,"x":0,"y":0,},
  ],
  "name":"%(name)s",
  "parent":{
    %(parent)s
  },
  "parentRoom":null,
  "physicsSettings":{
    "inheritPhysicsSettings":false,
    "PhysicsWorld":false,
    "PhysicsWorldGravityX":0.0,
    "PhysicsWorldGravityY":10.0,
    "PhysicsWorldPixToMetres":0.1,
  },
  "resourceType":"GMRoom",
  "resourceVersion":"2.0",
  "roomSettings":{
    "Height":%(height)d,
    "inheritRoomSettings":false,
    "persistent":false,
    "Width":%(width)d,
  },
  "sequenceId":null,
  "views":[
%(views)s
  ],
  "viewSettings":{
    "clearDisplayBuffer":true,
    "clearViewBackground":false,
    "enableViews":false,
    "inheritViewSettings":false,
  },
  "volume":1.0,
}"""

INSTANCE_LINE = ('      {"$GMRInstance":"v1","%%Name":"%(name)s","colour":4294967295,'
                 '"frozen":false,"hasCreationCode":false,"ignore":false,'
                 '"imageIndex":0,"imageSpeed":1.0,"inheritCode":false,'
                 '"inheritedItemId":null,"inheritItemSettings":false,'
                 '"isDnd":false,"name":"%(name)s","objectId":{"name":"%(obj)s",'
                 '"path":"objects/%(obj)s/%(obj)s.yy",},"properties":[],'
                 '"resourceType":"GMRInstance","resourceVersion":"2.0",'
                 '"rotation":0.0,"scaleX":1.0,"scaleY":1.0,"x":%(x)d.0,'
                 '"y":%(y)d.0,},')


def room(name, width, height, instances=None, folder=None, order=0,
         colour=0xFF000000):
    """Create or overwrite a room.

    `instances` is a list of (object_name, x, y). Each is written into **both**
    the layer's instance list and `instanceCreationOrder` -- GameMaker creates
    what the second list names, so an instance in only the layer silently does
    not exist at run time.
    """
    instances = instances or []
    placed = []
    order_lines = []
    for i, (obj_name, x, y) in enumerate(instances):
        inst = "inst_%s_%d" % (name, i)
        placed.append(INSTANCE_LINE % {"name": inst, "obj": obj_name,
                                       "x": int(x), "y": int(y)})
        order_lines.append(
            '    {"name":"%s","path":"rooms/%s/%s.yy",},' % (inst, name, name))

    view = ('    {"hborder":32,"hport":%d,"hspeed":-1,"hview":%d,"inherit":false,'
            '"objectId":null,"vborder":32,"visible":false,"vspeed":-1,'
            '"wport":%d,"wview":%d,"xport":0,"xview":0,"yport":0,"yview":0,},'
            % (height, height, width, width))

    d = os.path.join(ROOT, "rooms", name)
    write(os.path.join(d, name + ".yy"), ROOM_YY % {
        "name": name, "width": width, "height": height,
        "instances": "\n".join(placed),
        "order_list": "\n".join(order_lines),
        "views": "\n".join([view] * 8),
        "parent": _parent(folder), "creation": "", "colour": colour,
    })
    register(name, "rooms/%s/%s.yy" % (name, name), order)


def room_order(names):
    """Rewrite RoomOrderNodes so rooms start in the order given."""
    lines = ['    {"roomId":{"name":"%s","path":"rooms/%s/%s.yy",},},' % (n, n, n)
             for n in names]
    text = read(YYP)
    text = re.sub(r'"RoomOrderNodes":\[.*?\n  \],',
                  '"RoomOrderNodes":[\n%s\n  ],' % "\n".join(lines),
                  text, flags=re.S)
    write(YYP, text)
    validate(YYP)


# ---------------------------------------------------------------------------
# Included files
# ---------------------------------------------------------------------------

INCLUDED_LINE = ('    {"$GMIncludedFile":"","%%Name":"%(file)s","CopyToMask":-1,'
                 '"filePath":"%(dir)s","name":"%(file)s",'
                 '"resourceType":"GMIncludedFile","resourceVersion":"2.0",},')


def included_file(filename, directory="datafiles"):
    """Register a file in datafiles/ so it ships with the build."""
    _add_to_list(YYP, "IncludedFiles",
                 INCLUDED_LINE % {"file": filename, "dir": directory})


def delete(name, kind):
    """Remove a resource and every registration of it. `kind` is the folder."""
    shutil.rmtree(os.path.join(ROOT, kind, name), ignore_errors=True)
    path = "%s/%s/%s.yy" % (kind, name, name)
    for f in (YYP, ORDER):
        lines = [ln for ln in read(f).split("\n") if '"%s"' % path not in ln]
        write(f, "\n".join(lines))
        validate(f)


# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------

SOUND_YY = """{
  "$GMSound":"",
  "%%Name":"%(name)s",
  "audioGroupId":{
    "name":"audiogroup_default",
    "path":"audiogroups/audiogroup_default",
  },
  "bitDepth":1,
  "bitRate":128,
  "compression":%(compression)d,
  "conversionMode":0,
  "duration":%(duration).8f,
  "name":"%(name)s",
  "parent":{
    %(parent)s
  },
  "preload":%(preload)s,
  "resourceType":"GMSound",
  "resourceVersion":"2.0",
  "sampleRate":%(rate)d,
  "soundFile":"%(name)s.wav",
  "type":0,
  "volume":1.0,
}"""


def sound(name, samples, rate=44100, folder=None, order=0, preload=True):
    """Create or overwrite a sound from mono float samples in [-1, 1].

    Written as **16-bit PCM WAV, uncompressed and preloaded**, which is the
    right answer for every sound in this project and the wrong one for exactly
    none of them: these are all short cues, a decode on first play is a stutter
    at the worst possible moment, and `compression` 0 with `preload` true is
    what says "this lives in memory". Music, if it ever arrives, wants the
    opposite and should not come through here without saying so.

    The `.yy` carries the duration, and GameMaker believes it rather than
    measuring the file -- so it is computed from the samples that were actually
    written rather than passed in.
    """
    import struct
    import wave

    clipped = bytearray()
    for s in samples:
        v = int(round(max(-1.0, min(1.0, s)) * 32767))
        clipped += struct.pack("<h", v)

    d = os.path.join(ROOT, "sounds", name)
    os.makedirs(d, exist_ok=True)
    wav = os.path.join(d, name + ".wav")
    with wave.open(wav, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(rate)
        fh.writeframes(bytes(clipped))

    write(os.path.join(d, name + ".yy"), SOUND_YY % {
        "name": name,
        "parent": _parent(folder),
        "duration": len(samples) / float(rate),
        "rate": rate,
        "compression": 0,
        "preload": "true" if preload else "false",
    })
    register(name, "sounds/%s/%s.yy" % (name, name), order)
