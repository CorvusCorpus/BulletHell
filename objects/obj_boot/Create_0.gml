/// @desc Initialise every global the game reads, parse the command line, then
///       go to the right room.
///
/// Every global is assigned here: `??` only handles an undefined value, and
/// reading a global that was never assigned raises (a modal error box, which
/// hangs the harnesses).

randomize();

// GUI coordinates are design pixels whatever the window size.
display_set_gui_size(GAME_W, GAME_H);

// The generated tables first: everything else indexes into them.
palette_init();
bullet_table_init();
grove_table_init();
sanctum_table_init();

danmaku_init();
laser_init();
ring_init();
item_init();
enemy_init();
fx_init();
ui_init();
// `audio_init` is called after the command line is parsed (harnesses are
// silent).

global.progress_readonly = false;
progress_load();

// Which stage the title screen has the cursor on, and which one the game room
// is about to play. Both are read by rooms that do not create them.
global.stage_pick = 0;
global.stage_def = undefined;

// The attack chosen on the practice screen, or `undefined` for a normal stage
// run (read by `obj_game`'s Create).
global.practice = undefined;

// Best score per practised attack, this session only (never saved).
global.practice_best = {};

// The screenshot scene being posed (`obj_shot`); "" in normal play.
global.shot_scene = "";

// Frame offsets a `-burst` shot run photographs; empty for a single shot.
global.shot_burst = [];

// ---------------------------------------------------------------------------
// The command line
// ---------------------------------------------------------------------------
//
// `-shot <scene>` takes the scene as a separate argument so an unknown scene
// can be refused with an error instead of silently opening the title screen.

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
    } else if (_a == "-burst") {
        // A comma-separated list of frame offsets.
        if (_i < _argc) {
            global.shot_burst = shot_parse_burst(parameter_string(_i + 1));
            _i++;
        }
    }
}

// Full screen only in normal play (or with `-fullscreen`), so the harnesses
// never take over the display. This must be done here rather than with
// `option_windows_start_fullscreen`, which the runner applies before any GML
// runs. Harness screenshots are therefore windowed (1864x1048 on a 1080p
// desktop).
//
// Borderless rather than exclusive: Windows drops an exclusive-fullscreen app
// out of fullscreen when anything else takes focus (alt-tab, the screenshot
// overlay). Set before the switch, since it decides what the switch does
// (and what F4 does).
window_enable_borderless_fullscreen(true);
if (_mode == "" || _want_full) window_set_fullscreen(true);

// Sound only in normal play; the harnesses are silent.
audio_init(_mode == "");

if (_mode == "selftest") {
    // Don't hide the window here: GameMaker stops stepping an invisible
    // window, so the tests would never run. `build.run_game` starts the game
    // minimised instead.
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
    // Set any globals the scene's room reads in its own Create (`shot_pose`
    // runs a frame later, too late for those).
    shot_scene_prepare(_scene);
    room_goto(shot_scene_room(_scene));
    exit;
}

room_goto(room_title);
