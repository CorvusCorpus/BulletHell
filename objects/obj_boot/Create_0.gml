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
grove_table_init();
sanctum_table_init();

danmaku_init();
laser_init();
ring_init();
item_init();
enemy_init();
fx_init();
ui_init();
// `audio_init` is NOT here -- it is below the command line, because whether
// the game makes any sound at all depends on which flag was passed. See the
// call site.

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

// **Which frames a shot run photographs, relative to the scene's own.** Empty
// is the ordinary one-picture run. A burst exists because half of what this
// project now draws is a *sequence* -- a bomb is four seconds of sigil, theft
// and seals -- and a still of frame 26 says nothing about whether the other
// hundred read. One launch, several shutters, so a sequence costs one build
// and seven seconds rather than six of each.
global.shot_burst = [];

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
    } else if (_a == "-burst") {
        // A comma-separated list of frame offsets, taken as a separate
        // argument for the same reason the scene name is: one this file does
        // not understand should be visible rather than silently ignored.
        if (_i < _argc) {
            global.shot_burst = shot_parse_burst(parameter_string(_i + 1));
            _i++;
        }
    }
}

// **Neither harness takes the display, and the *option* is what makes that
// true rather than a line of GML.** The game is played full screen -- a
// 1920x1080 window does not fit on a 1920x1080 desktop, so a windowed run
// draws every pixel at 0.97 of its design size -- and for a long time that
// was `option_windows_start_fullscreen`, with the harnesses dropping back out
// of it here.
//
// **Dropping back out is too late.** The option is read by the runner before
// a line of GML executes, so a harness run had already changed the display
// mode, raised a topmost borderless window over everything else and taken the
// foreground by the time this file got a say. Switching back a frame later
// gives the pixels back and does not give the focus back -- and both tools are
// run every few minutes while somebody is working on something else. Reported,
// in those words, as forcing the game window to the front and blocking
// whatever they were doing. The Wordsearch project has the same two tools and
// has never done it, and the whole of the difference was that one option.
//
// So the option is off and the *player* asks for the display, which is the
// only path that wants it. A harness never mentions it, and there is no frame
// in which it held it.
//
// The price is unchanged: a harness screenshot comes back at 1864x1048, which
// is 97% of design size with everything in the picture scaling together, and
// nothing in the tooling measures a screenshot -- `check_bg_keepout` and its
// neighbours measure the PNGs the generators write, not these. Pass
// `-fullscreen` when a photographed pixel really does have to be a design
// pixel; `tools/shot.py --fullscreen` is the way to ask for it.
//
// **`_mode == ""` is load-bearing** and points the other way from the test it
// replaced: full screen is the game's, not the harnesses'.
//
// **Borderless, not exclusive.** A plain `window_set_fullscreen` on Windows is
// exclusive fullscreen, and Windows drops an exclusive app out of that mode the
// moment anything else takes focus -- which the screenshot overlay does, and
// so does alt-tab -- and the runner does not go back in afterwards. Reported
// as the game leaving full screen every time a screenshot was taken, which is
// exactly when somebody is trying to show what it looks like. A borderless
// window the size of the display has no mode to lose. It is set before the
// switch because it decides what the switch does, and it covers F4 as well.
window_enable_borderless_fullscreen(true);
if (_mode == "" || _want_full) window_set_fullscreen(true);

// **Neither harness makes a sound, on the same reasoning as neither taking
// the display.** `tools/test.py` runs the game once and `tools/shot.py --all`
// runs it thirty-two times, minimised, while somebody is working on something
// else -- and a build that played a boss dying through their speakers thirty
// two times is the same complaint as the window coming to the front, one
// notch louder.
//
// It is read from `_mode` for the same reason the full-screen line above is:
// silence is the *harness's*, not the game's, and expressing it as "the game
// asks for sound" rather than "a tool switches it off" leaves no frame in
// which it was on. Everything in `audio_functions` still runs either way --
// only the statement that starts a voice is skipped -- so `test_audio_budget`
// grades the real decision.
audio_init(_mode == "");

if (_mode == "selftest") {
    // **A hidden window is not the answer, and it was tried.** The suites draw
    // nothing anybody looks at, so `window_set_visible(false)` here looks free
    // -- and it hangs. GameMaker stops stepping a window it is not showing, so
    // `room_test` never runs, nothing reaches stdout, and what `tools/test.py`
    // reports is its 180-second timeout: the exact failure mode the note about
    // modal boxes is about, caused this time by the fix rather than by a bug.
    // Where the window *is* is the Python side's business; see `tools/run.py`.
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
