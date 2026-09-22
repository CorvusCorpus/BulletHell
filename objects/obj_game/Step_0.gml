/// @desc One frame of a run. Every clock is a frame count; nothing reads
///       `delta_time` (`check_delta_time_in_rules` enforces this in
///       `scripts/`).

// Resolve sound requests first, before any `exit` below can skip it.
sfx_step();

// `input_override` replaces the keyboard when set (the screenshot harness).
var _in = (input_override != undefined) ? input_override : input_gather();

// ---------------------------------------------------------------------------
// Pausing, and the states that are not play
// ---------------------------------------------------------------------------

if (keyboard_check_pressed(vk_escape)) {
    if (phase == Phase.Paused) {
        phase = phase_before_pause;
        sfx(Sfx.Pause);
    } else if (phase == Phase.Playing || phase == Phase.BossDeclare
               || phase == Phase.PhaseClear) {
        phase_before_pause = phase;
        phase = Phase.Paused;
        pause_row = 0;
        sfx(Sfx.Pause);
    }
}

if (phase == Phase.Paused) {
    if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_down)) {
        sfx(Sfx.UiMove);
    }
    if (keyboard_check_pressed(vk_up))   pause_row = (pause_row + 2) mod 3;
    if (keyboard_check_pressed(vk_down)) pause_row = (pause_row + 1) mod 3;
    if (keyboard_check_pressed(ord("Z"))) {
        // Resuming plays the pause cue; the other rows the select cue.
        sfx(pause_row == 0 ? Sfx.Pause : Sfx.UiSelect);
        switch (pause_row) {
            case 0: phase = phase_before_pause; break;
            case 1: game_reset_stage(); break;
            // Quitting practice returns to the attack list, not the rack.
            case 2:
                room_goto((practice != undefined) ? room_practice
                                                  : room_title);
                break;
        }
    }
    exit;
}

if (phase == Phase.Won || phase == Phase.Lost) {
    result_t++;
    fx_step();
    bg_step(bg, player_field_aim(player));
    // The field and the HUD keep running under the result panel (bullets
    // finish their paths; the score counter finishes rolling up).
    bullet_step(player.x, player.y);
    laser_step();
    ring_step(self);
    hud_step(hud, self);

    // Practice: a menu (retry / attack list / title). Retry is a room restart;
    // `global.practice` survives it, so the same attack starts again. A stage
    // result just waits for Z.
    if (practice != undefined) {
        if (result_t > 24) {
            if (keyboard_check_pressed(vk_up) || keyboard_check_pressed(vk_down)) {
                sfx(Sfx.UiMove);
            }
            if (keyboard_check_pressed(vk_up)) {
                result_row = (result_row + 2) mod 3;
            }
            if (keyboard_check_pressed(vk_down)) {
                result_row = (result_row + 1) mod 3;
            }
            if (keyboard_check_pressed(ord("Z"))) {
                sfx(Sfx.UiSelect);
                switch (result_row) {
                    case 0: room_restart(); break;
                    case 1: room_goto(room_practice); break;
                    case 2: room_goto(room_title); break;
                }
            }
        }
        exit;
    }

    if (result_t > 30 && keyboard_check_pressed(ord("Z"))) {
        sfx(Sfx.UiSelect);
        room_goto(room_title);
    }
    exit;
}

// ---------------------------------------------------------------------------
// Play
// ---------------------------------------------------------------------------

t++;
if (fade < 1) fade = min(1, fade + 0.03);

if (phase == Phase.Intro) {
    intro_t--;
    _in = input_idle();
    if (intro_t <= 0) phase = Phase.Playing;
}

// A declaration holds the stage timeline, not the field: bullets keep moving.
if (phase == Phase.BossDeclare && boss_ref != undefined
    && boss_ref.boss.started) {
    phase = Phase.Playing;
}

fx_step();
// The background camera leans toward the player (stage two uses this).
bg_step(bg, player_field_aim(player));

var _hp_before = player.hp;
var _bombs_before = player.bomb_n;
player_step(player, _in, self);
if (player.hp < _hp_before) on_player_hit();
// Detect a bomb from the count (`bomb_t` has already ticked down by here).
if (player.bomb_n > _bombs_before) boss_note_bomb(boss_ref);

pshot_step();
bullet_step(player.x, player.y);
laser_step();
enemy_step(self);
// After the enemies, so a ring an attack spawns this frame steps this frame.
ring_step(self);

// Rings must absorb shots before enemies are offered them, or they wouldn't
// block anything (`check_rings_block_before_enemies` enforces the order).
ring_block_shots();
tally += enemy_take_shots(self);
tally += enemy_take_seals(player, self);

var _got = item_step(player.x, player.y);
if (_got.n > 0) {
    player.hp = min(HP_MAX, player.hp + _got.hp);
    player.mp = min(MP_MAX, player.mp + _got.mp);
    tally += _got.tally;
}

var _was_hit = player_collide(player, self);
if (_was_hit) on_player_hit();

if (!player.alive && phase != Phase.Lost) {
    phase = Phase.Lost;
    result_t = 0;
    result_row = 0;
    // Dying in practice: no mark is filed and no best is recorded.
    if (practice != undefined) {
        practice_result = practice_outcome(boss_ref, PracticeEnd.Died, marks);
    }
    bullet_clear_all(false);
    laser_clear_all();
    ring_clear_all();
}

// The stage timeline is held while a boss is on the field.
if (phase == Phase.Playing && boss_ref == undefined) {
    stage_step(stage, self);
}

// ---------------------------------------------------------------------------
// Handing over
// ---------------------------------------------------------------------------

if (midboss_pending > 0) {
    midboss_pending--;
    if (midboss_pending == 0) {
        boss_ref = undefined;
        phase = Phase.Playing;
    }
}

if (win_pending > 0) {
    win_pending--;
    if (win_pending == 0) {
        phase = Phase.Won;
        result_t = 0;
        var _caught = (boss_ref == undefined) ? 0 : boss_ref.boss.captured;
        // Progress is recorded here, not in the boss code, so suites that
        // defeat bosses never write the real save file. Practice never
        // records (it can't reach here anyway; guarded to be safe).
        if (practice == undefined) {
            progress_record(def.id, tally, player.hit_n == 0, _caught);
        }
    }
}

hud_step(hud, self);

// The spell background eases in and out.
if (spell_bg >= 0) {
    spell_col = spell_bg;
    spell_fade = min(1, spell_fade + 0.035);
} else {
    spell_fade = max(0, spell_fade - 0.045);
}
