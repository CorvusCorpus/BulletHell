t++;
sfx_step();
bg_step(bg);
fx_step();

if (enter_t > 0) {
    enter_t--;
    if (enter_t == 0) {
        var _r = rows[picks[pick]];
        // The request is passed to `obj_game` through a global.
        global.practice = practice_new(stage, _r.boss_i, _r.phase_i);
        room_goto(room_game);
    }
    exit;
}

var _n = array_length(picks);
if (_n > 0) {
    if (keyboard_check_pressed(vk_down) || keyboard_check_pressed(vk_up)) {
        sfx(Sfx.UiMove);
    }
    if (keyboard_check_pressed(vk_down)) pick = (pick + 1) mod _n;
    if (keyboard_check_pressed(vk_up))   pick = (pick + _n - 1) mod _n;

    // Left/right jump to the next/previous boss's first attack.
    if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_left)) {
        sfx(Sfx.UiMove);
        var _dir = keyboard_check_pressed(vk_right) ? 1 : -1;
        var _here = rows[picks[pick]].boss_i;
        var _want = (_here + _dir + array_length(bosses))
                    mod array_length(bosses);
        for (var _i = 0; _i < _n; _i++) {
            if (rows[picks[_i]].boss_i == _want) {
                pick = _i;
                break;
            }
        }
    }
}
cursor += (pick - cursor) * 0.3;

// Scroll to keep the cursor in view, eased at the cursor's rate.
if (_n > 0) {
    scroll_want = practice_list_scroll(scroll_want, row_y[picks[pick]],
                                       list_span, list_window, row_head + 26);
}
scroll += (scroll_want - scroll) * 0.3;

if (_n > 0 && keyboard_check_pressed(ord("Z"))) {
    enter_t = 26;
    sfx(Sfx.UiSelect);
    fx_flash_screen(COL_SZUIX_LIT, 0.4);
    fx_ring(GAME_CX, GAME_CY, 40, 780, 30, COL_SZUIX_LIT, 1);
}

// Escape or X goes back to the rack.
if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(ord("X"))) {
    sfx(Sfx.UiBack);
    // `global.practice` is left set so the cursor returns to the last attack
    // next time; the rack clears it before starting a normal run.
    room_goto(room_title);
}
