t++;
sfx_step();
bg_step(bg);
fx_step();

if (enter_t > 0) {
    enter_t--;
    if (enter_t == 0) {
        global.stage_def = stages[pick];
        global.stage_pick = pick;
        // **The screen that begins a run says which kind it is.** Attack
        // practice leaves its request standing so the attack list can put the
        // cursor back where it was, which means an ordinary run inherits it
        // unless this line clears it -- and the symptom would be picking a
        // stage off the rack and landing in the middle of somebody's fourth
        // spell. Exactly the shape of the bug `run_clear_field`'s note is
        // about: one entry path correct and every other one inheriting.
        global.practice = undefined;
        room_goto(room_game);
    }
    exit;
}

var _n = array_length(stages);
var _moved = false;
if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_down)) {
    pick = (pick + 1) mod _n;
    _moved = true;
}
if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_up)) {
    pick = (pick + _n - 1) mod _n;
    _moved = true;
}
if (_moved) sfx(Sfx.UiMove);
cursor += (pick - cursor) * 0.24;

if (keyboard_check_pressed(ord("Z"))) {
    var _def = stages[pick];
    // **On the drafting table both keys do the one useful thing.** It has no
    // waves and no run to begin, so a Z that refused would be teaching the
    // player a rule about a card that exists to be opened -- and there is
    // nothing else it could mean. See `stage_drafts`.
    if (stage_is_draft(_def)) {
        sfx(Sfx.UiSelect);
        global.stage_def = _def;
        global.stage_pick = pick;
        room_goto(room_practice);
        exit;
    }
    // **A locked or unbuilt stage refuses rather than being skipped over.**
    // Skipping it would mean the cursor never lands on the seven that are
    // planned, and a rack that silently has no cells in it is a rack that
    // stops advertising there is more game coming.
    if (!stage_is_built(_def)) {
        // **A refusal is not a rebuke.** The rack refuses in order to
        // advertise that there is more game coming, so the cue for it is a
        // door that did not open rather than a buzzer -- see `cue_ui_deny`.
        sfx(Sfx.UiDeny);
        fx_text(GAME_CX, GAME_H - 300, "NOT YET BUILT", COL_SILVER, 60, 1.6);
        fx_shake(4);
    } else if (!stage_is_unlocked(_def)) {
        sfx(Sfx.UiDeny);
        fx_text(GAME_CX, GAME_H - 300,
                "CLEAR " + string(_def.needs) + " STAGE"
                + (_def.needs == 1 ? "" : "S") + " FIRST",
                COL_LIFE, 60, 1.6);
        fx_shake(6);
    } else {
        enter_t = 34;
        sfx(Sfx.UiSelect);
        fx_flash_screen(COL_SZUIX_LIT, 0.5);
        fx_ring(GAME_CX, GAME_CY, 40, 900, 34, COL_SZUIX_LIT, 1);
    }
}

// **X opens the attack list for the highlighted stage.** It hangs off the rack
// rather than being a menu of its own, so it never has to ask which stage --
// the rack has already answered that, with its locks, its unbuilt cards and a
// layout that grows by itself when a stage is added.
//
// It refuses on the same terms the rack does and one term fewer: a stage with
// no bosses in it has nothing to practise, and that is the only refusal. Being
// *locked* is not one, deliberately -- the locks pace a first playthrough, and
// this is where an attack is drilled or tuned. See `practice_available`.
if (keyboard_check_pressed(ord("X"))) {
    var _def = stages[pick];
    if (!practice_available(_def)) {
        sfx(Sfx.UiDeny);
        fx_text(GAME_CX, GAME_H - 300, "NO ATTACKS TO PRACTISE", COL_SILVER,
                60, 1.6);
        fx_shake(4);
    } else {
        sfx(Sfx.UiSelect);
        global.stage_def = _def;
        global.stage_pick = pick;
        room_goto(room_practice);
    }
}

if (keyboard_check_pressed(vk_escape)) game_end();
