t++;
sfx_step();
bg_step(bg);
fx_step();

if (enter_t > 0) {
    enter_t--;
    if (enter_t == 0) {
        var _r = rows[picks[pick]];
        // **The request is written to the global and the room is entered.**
        // Same seam the rack uses for `global.stage_def`, and for the same
        // reason: a room transition carries nothing with it.
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

    // Left and right jump a boss rather than moving one line, which is the
    // only shortcut the list needs: nine attacks is a short walk and the one
    // long walk in it is from the midboss's first to the boss's first.
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

if (_n > 0 && keyboard_check_pressed(ord("Z"))) {
    enter_t = 26;
    sfx(Sfx.UiSelect);
    fx_flash_screen(COL_SZUIX_LIT, 0.4);
    fx_ring(GAME_CX, GAME_CY, 40, 780, 30, COL_SZUIX_LIT, 1);
}

// **X as well as escape.** Escape is what leaves a screen and X is what the
// hand is already on -- it is the special in play, and there is nothing here
// to spend one on.
if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(ord("X"))) {
    sfx(Sfx.UiBack);
    // **`global.practice` is deliberately left set.** It is what Create reads
    // to put the cursor back on the attack that was practised last, and
    // clearing it here would be clearing it in the wrong place: what a stale
    // request could break is an *ordinary* run, and the screen that starts one
    // of those is the rack. See `obj_title`'s Step -- the screen that begins a
    // run is the screen that says which kind it is.
    room_goto(room_title);
}
