/// @desc One frame of a run.
///
/// **Every clock in this game is a frame count and every frame is the same
/// size.** Nothing here reads `delta_time`; a danmaku pattern is a sequence of
/// exact angles on exact ticks, and a pattern that advanced by wall time would
/// be a different pattern on every machine and impossible to assert on.
/// `check_delta_time_in_rules` refuses it inside `scripts/` for the same
/// reason.

// **Input comes through one seam.** `input_override` is `undefined` in play
// and a struct when something else is driving -- which today is only
// `obj_shot`, posing a scene with the shot button held, and tomorrow is a
// replay or a demo attract mode. A harness that drove the player by writing
// positions would be photographing a state the game cannot reach.
// **The frame's sound is resolved here, at the top, before anything that
// might `exit`.** There are five early returns below this line and three of
// them are states where a cue most needs to sound -- the pause menu, the
// result panel and the menu on it. Resolving last frame's requests rather
// than this frame's costs sixteen milliseconds, which is well under the
// ear's ability to bind a sound to a picture, and buys that no path
// through this event can skip it. See `audio_functions`.
sfx_step();

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
        // **The resume row says `Pause` and the other two say `UiSelect`.**
        // Leaving the menu the way it was entered is the same event twice,
        // and a confirm chime on it would say a choice was made where what
        // actually happened is a choice being declined.
        sfx(pause_row == 0 ? Sfx.Pause : Sfx.UiSelect);
        switch (pause_row) {
            case 0: phase = phase_before_pause; break;
            case 1: game_reset_stage(); break;
            // Out of a practice attempt is back to the attack list, not to the
            // rack: what somebody abandoning one attack wants is almost always
            // a different attack, and a rack two screens away from the thing
            // they are working on is two screens of travel per idea.
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
    // **The field keeps running under the result panel.** Bullets that were in
    // flight finish their arcs and the particles from the kill burn out, which
    // is what makes the panel feel like it arrived over the fight rather than
    // instead of it.
    bullet_step(player.x, player.y);
    laser_step();
    ring_step(self);
    // **The console keeps settling under the panel.** It was left out of this
    // branch, so the moment a run ended the score stopped rolling wherever it
    // had got to -- and the frame a run ends on is the frame the biggest
    // single award in the game lands, so what froze was always a number
    // part-way to the truth. The stage panel showed it plainly: 4,826,150
    // across the field beside a console reading 1,310. The field goes on
    // running under a result for exactly this reason, and the console is
    // reading the same run.
    hud_step(hud, self);

    // **Practice ends in a menu and a stage ends in a key.** A stage is over
    // when it is over -- there is one thing to do next and it is to go back to
    // the rack -- where the whole point of practising an attack is doing it
    // again, so the panel that says how it went is also the fastest way back
    // in. `room_restart` is the retry, for the same reason
    // `game_reset_stage` is: `obj_game`'s Create is the one place that knows
    // what a fresh run is, and `global.practice` outlives the room, so
    // restarting it replays the same attack and cannot drift from what
    // starting one does.
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

// The boss's ceremony holds the *stage*, not the field. Bullets already in
// flight keep moving through a declaration, which is what stops the screen
// freezing at the exact moment it is trying to be dramatic.
if (phase == Phase.BossDeclare && boss_ref != undefined
    && boss_ref.boss.started) {
    phase = Phase.Playing;
}

fx_step();
// **The camera looks where the player is**, and this is the only place in the
// game that knows both. See `GROVE_LEAN`; stage one never reads it.
bg_step(bg, player_field_aim(player));

var _hp_before = player.hp;
var _bombs_before = player.bomb_n;
player_step(player, _in, self);
if (player.hp < _hp_before) on_player_hit();
// **Off the count, not off `bomb_t`.** This used to ask whether `bomb_t` was
// still `BOMB_INVULN`, which it never is by here -- `player_step` casts and
// then ticks the grace down on the same frame -- so no boss ever heard about
// a sigil: every one spent in an attack still graded amethyst and still paid
// the capture bonus. `stage_encounter_close` diffs `bomb_n` for the same
// reason.
if (player.bomb_n > _bombs_before) boss_note_bomb(boss_ref);

pshot_step();
bullet_step(player.x, player.y);
laser_step();
enemy_step(self);
// **After the enemies, because an attack is what puts a ring down** -- so one
// spawned this frame starts arriving on the frame it was asked for rather than
// on the next. See `ring_step`.
ring_step(self);

// **The rings eat what crosses their metal, and this line has to come first.**
// A shot absorbed here never reaches the boss behind it, which is the whole
// mechanic; run the other way round and a ring would be scenery with a spark
// effect on it. See `ring_block_shots`.
ring_block_shots();
tally += enemy_take_shots(self);
// The bomb's seals, on the same terms and straight after: they are the
// player's other way of doing damage and they respect the same ceremony.
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
    // Dying is the third way a practice attempt can end, and the only one the
    // boss never hears about -- `boss_end_phase` is not reached, so there is
    // no mark and `tier` comes back as none. That is the honest reading: an
    // attempt that ended before the attack did was never graded, and for the
    // same reason it files no best either. A score for an attack that was
    // never finished is not a score on that attack.
    if (practice != undefined) {
        practice_result = practice_outcome(boss_ref, PracticeEnd.Died, marks);
    }
    bullet_clear_all(false);
    laser_clear_all();
    ring_clear_all();
}

// The stage only advances while the field belongs to it. During a boss the
// timeline is held exactly where it was, so a midboss that takes two minutes
// does not eat the waves written after it.
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
        // **Recorded here rather than inside the boss.** Writing progress
        // touches a real file in the player's save area, so a suite that drove
        // a boss to zero would overwrite their cleared stages with its own
        // scratch state -- permanently, and with nothing to report it. The
        // boss decides; the run records. Same split `vs_time_winner` and
        // `vs_call_time` are built on in the Wordsearch project.
        //
        // **And a practice attempt records nothing.** It cannot reach this
        // line -- an attack ending in practice goes to `Phase.Won` through
        // `on_phase_end`, a frame before `boss_finish` could run -- and the
        // guard is here anyway, because the cost of being wrong about that is
        // a stage marked cleared in a real player's save by somebody drilling
        // its first non-spell, permanently, with nothing to report it.
        if (practice == undefined) {
            progress_record(def.id, tally, player.hit_n == 0, _caught);
        }
    }
}

hud_step(hud, self);

// The spell wash. Eased in and out rather than switched, because the moment a
// spell is declared is the moment the player most needs the field to stay
// legible -- a background that snapped would take the pattern with it.
if (spell_bg >= 0) {
    spell_col = spell_bg;
    spell_fade = min(1, spell_fade + 0.035);
} else {
    spell_fade = max(0, spell_fade - 0.045);
}
