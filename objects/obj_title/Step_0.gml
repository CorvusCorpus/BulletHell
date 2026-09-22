t++;
sfx_step();
bg_step(bg);
fx_step();

if (enter_t > 0) {
    enter_t--;
    if (enter_t == 0) {
        global.stage_def = stages[pick];
        global.stage_pick = pick;
        // The attack list leaves `global.practice` set (to restore its
        // cursor), so a normal run must clear it.
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
    // The drafting table can only be practised, so Z opens its attack list.
    if (stage_is_draft(_def)) {
        sfx(Sfx.UiSelect);
        global.stage_def = _def;
        global.stage_pick = pick;
        room_goto(room_practice);
        exit;
    }
    // Unbuilt and locked stages can be selected but refuse to start.
    if (!stage_is_built(_def)) {
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

// X opens the attack list (practice) for the highlighted stage. Only a stage
// with no bosses refuses; locked stages can still be practised.
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
