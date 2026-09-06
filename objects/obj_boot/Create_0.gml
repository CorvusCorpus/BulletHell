/// @desc Initialise every global the game reads, then dispatch.
///
/// **Every global is assigned here, without exception.** `??` does not save a
/// read of a global that does not exist -- it handles an undefined *value*,
/// and a missing variable raises. In the Wordsearch project that cost an
/// entire game mode: a screen read `global.vs_difficulty` in its Create event
/// to restore a dial, nothing had ever assigned it, and the whole route from
/// the menu into a match died before the first frame -- as a modal error box,
/// which under the headless tooling is not a failure but a *hang*.
///
/// So a default that lives at its only call site is a default that is not
/// there the first time. It goes here.

randomize();

// The GUI layer is the design resolution, so a HUD coordinate is a design
// pixel whatever window the player has. Without this the GUI layer is the
// *window* size and every readout moves when the window is resized.
display_set_gui_size(GAME_W, GAME_H);

// The generated tables first: everything else indexes into them.
palette_init();
bullet_table_init();

danmaku_init();
laser_init();
item_init();
enemy_init();
fx_init();
ui_init();

global.progress_readonly = false;
progress_load();

// Which stage the title screen has the cursor on, and which one the game room
// is about to play. Both are read by rooms that do not create them.
global.stage_pick = 0;
global.stage_def = undefined;

// Which attack the practice screen chose, or `undefined` for an ordinary run
// of a whole stage. `obj_game` reads it in its Create and nothing else tests
// for it -- see `practice_functions`. It is assigned here for the same reason
// everything else in this file is: a default that lives at its only call site
// is a default that is not there the first time.
global.practice = undefined;

// The best score on each attack, this session only -- never saved, because a
// practice attempt is not a stage result and must not be able to file one.
// See the note above `practice_key`.
global.practice_best = {};

// The posing harness. `obj_shot` reads this; every other path leaves it alone.
// The empty string is the whole of "we are playing the game normally", and
// nothing else has to test for it.
global.shot_scene = "";

// ---------------------------------------------------------------------------
// The command line
// ---------------------------------------------------------------------------
//
// `-shot <scene>` takes the scene as a **separate argument** rather than fused
// into the flag, so an unknown one can be refused loudly. Wordsearch fused
// them, and a scene whose switch nothing read did not fail: the game opened
// its menu and sat there until the harness's timeout, with nothing in the
// output to say the scene simply did not exist.

var _argc = parameter_count();
var _mode = "";
var _scene = "";
var _want_full = false;
for (var _i = 1; _i <= _argc; _i++) {
    var _a = parameter_string(_i);
    if (_a == "-selftest") {
        _mode = "selftest";
    } else if (_a == "-fullscreen") {
        _want_full = true;
    } else if (_a == "-shot") {
        _mode = "shot";
        if (_i < _argc) {
            _scene = parameter_string(_i + 1);
            _i++;
        }
    }
}

// **Neither harness takes the display, and that reverses a decision.** The
// game starts full screen, which is right for playing it. It was right for
// `tools/shot.py` too on the reasoning that there the display *is* the output:
// at full screen a screenshot is 1920x1080 exactly, so a design pixel and a
// photographed pixel are the same pixel and a HUD box can be measured off the
// PNG.
//
// What that reasoning left out is who is at the machine. Both tools are run
// every few minutes while somebody is working on something else, and a
// harness that seizes the display -- changing the display mode, rearranging
// every other window, stealing focus for a few seconds, eighteen times over
// for `--all` -- is a far worse cost than the one it was buying. Reported, in
// those words, as a nightmare to work alongside.
//
// The price is that a screenshot comes back at 1864x1048: a 1920x1080 window
// does not fit on a 1920x1080 desktop, so GameMaker clamps it. That is 97% of
// design size, everything in the picture scales together, and nothing in the
// tooling measures a screenshot -- `check_bg_keepout` and its neighbours
// measure the PNGs the generators write, not these. Pass `-fullscreen` when a
// photographed pixel really does have to be a design pixel; `tools/shot.py
// --fullscreen` is the way to ask for it.
// **`_mode != ""` is load-bearing.** This is the harnesses' rule and not the
// game's: a player gets the full screen the options file asks for, and only a
// run that was started by a tool drops out of it.
if (_mode != "" && !_want_full) window_set_fullscreen(false);

if (_mode == "selftest") {
    room_goto(room_test);
    exit;
}

if (_mode == "shot") {
    if (!shot_scene_known(_scene)) {
        show_debug_message("SHOT UNKNOWN SCENE " + _scene);
        game_end(1);
        exit;
    }
    global.shot_scene = _scene;
    show_debug_message("SHOT SCENE " + _scene);
    instance_create_depth(0, 0, -9000, obj_shot);
    // Anything the scene's room reads in its *own* Create has to be written
    // before the room change. `shot_pose` runs a frame later, which is too
    // late for a global that decides what kind of run is being started.
    shot_scene_prepare(_scene);
    room_goto(shot_scene_room(_scene));
    exit;
}

room_goto(room_title);
