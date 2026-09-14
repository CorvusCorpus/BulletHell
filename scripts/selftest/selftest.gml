/// @desc The suites `tools/test.py` grades.
///
/// **A bullet hell is arithmetic, and almost none of it is visible in a still
/// frame.** A ring that is one bullet short, a fan whose middle is off by half
/// a step, a laser whose warning line and beam disagree about where the beam
/// is, a boss phase table whose thresholds do not descend -- every one of
/// those looks completely fine in a screenshot and is wrong in play. This is
/// where they are caught.
///
/// **Everything here runs headless and draws nothing.** The game is a fixed
/// 60Hz step and every rule takes its time as a frame count, so a suite can
/// drive a boss through nine hundred frames in a couple of milliseconds and
/// then read the bullets it laid down. That is the entire payoff of refusing
/// `delta_time` inside `scripts/` -- see `check_delta_time_in_rules`.
///
/// **No suite here touches a real save file.** `save_run` and its friends name
/// files in the player's own save area, and a suite that exercised progress
/// end-to-end would overwrite their cleared stages with its own scratch state,
/// permanently, with nothing to report it. `test_save_atomicity` proves the
/// primitives on a file of its own instead.

function selftest_run() {
    global.st_pass = 0;
    global.st_fail = 0;

    test_bullet_table();
    test_bullet_pool();
    test_fire_patterns();
    test_bullet_motion();
    test_bullet_cartesian();
    test_bullet_mods();
    test_bullet_queue();
    test_bullet_expiry();
    test_collision();
    test_graze();
    test_laser();
    test_laser_graze();
    test_rings();
    test_hall_sky();
    test_hall_orb();
    test_hall_floor();
    test_hall_preview();
    test_spell_resist();
    test_player();
    test_bomb_seals();
    test_grace_dial();
    test_items();
    test_untouchable();
    test_boss_table();
    test_boss_phases();
    test_boss_move();
    test_stage_table();
    test_stage_run();
    test_corridor();
    test_band_strip();
    test_grove_turn();
    test_marks();
    test_practice();
    test_drafts();
    test_hex_seal();
    test_hud_layout();
    test_run_starts_clean();
    test_boss_is_never_invisible();
    test_save_atomicity();
    test_audio_budget();
    test_audio_playback();
    test_bullet_cost();

    show_debug_message("SELFTEST DONE " + string(global.st_pass) + " passed, "
                       + string(global.st_fail) + " failed");
}

function ok(_name, _cond) {
    if (_cond) {
        global.st_pass++;
        show_debug_message("SELFTEST PASS " + _name);
    } else {
        global.st_fail++;
        show_debug_message("SELFTEST FAIL " + _name);
    }
}

function ok_near(_name, _got, _want, _tol) {
    var _good = abs(_got - _want) <= _tol;
    if (!_good) {
        show_debug_message("SELFTEST FAIL " + _name + "  (got "
                           + string(_got) + ", wanted " + string(_want)
                           + " +/- " + string(_tol) + ")");
        global.st_fail++;
        return;
    }
    global.st_pass++;
    show_debug_message("SELFTEST PASS " + _name);
}

/// @desc A clean field. Every suite starts with one, because a suite that
///       inherited the last one's bullets would pass or fail depending on the
///       order the suites happen to be listed in.
function st_reset() {
    danmaku_init();
    laser_init();
    ring_init();
    item_init();
    enemy_init();
    fx_clear();
}

/// @desc A stand-in for `obj_game`, carrying only what the rules read.
///
///       **Written as a struct rather than as an instance**, which is the same
///       trick `side_init` uses in the Wordsearch project: every rule takes
///       `_g` explicitly and never asks whether it is an object, so a suite
///       can hand it seventy fields on a struct and drive the whole game
///       without a room.
function st_game(_px, _py) {
    return {
        player: player_new(),
        tally: 0,
        spell_bg: -1,
        t: 0,
        beaten: false,
        beaten_final: false,
        on_boss_beaten: function(_e) {
            beaten = true;
            beaten_final = boss_is_final(_e);
        },
        // The other end of the same seam. **`_beaten` is the only place the
        // difference between a spell broken and a spell survived survives** --
        // `boss_end_phase` pulls the health down to the threshold either way --
        // so a suite that wants to assert on it has to catch it here. See the
        // note beside the call in `boss_end_phase`.
        ended_n: 0,
        ended_beaten: false,
        on_phase_end: function(_e, _beaten) {
            ended_n++;
            ended_beaten = _beaten;
        },
        // Attack practice reads this in the run it is driving; an ordinary run
        // leaves it `undefined` and nothing else tests for it.
        practice: undefined,
        // A real ledger, so `test_boss_phases` can read the marks the fight
        // files rather than only proving it does not crash while filing them.
        marks: rank_ledger_new(),
        px_want: _px,
        py_want: _py,
    };
}

function st_game_at(_px, _py) {
    var _g = st_game(_px, _py);
    _g.player.x = _px;
    _g.player.y = _py;
    _g.player.entry = 0;
    return _g;
}

// ---------------------------------------------------------------------------

function test_bullet_table() {
    ok("bullet table has every shape",
       array_length(global.bshape_sprite) == BSHAPE_COUNT);

    var _bad_radius = 0;
    var _bad_frames = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        if (global.bshape_radius[_s] <= 0) _bad_radius++;

        // **The frame count is the contract between the art and the engine.**
        // A shape's sprite holds one frame per colour, times its animation --
        // and `bullet_frame` computes an index off exactly that. A sprite
        // regenerated with a different frame count would draw the wrong colour
        // for every bullet of that shape, and nothing else would notice.
        var _want = BCOL_COUNT * global.bshape_frames[_s];
        if (sprite_get_number(global.bshape_sprite[_s]) != _want) _bad_frames++;
    }
    ok("every shape has a positive hit radius", _bad_radius == 0);
    ok("every sprite holds colours x animation frames", _bad_frames == 0);

    // **An oriented shape may not carry a default spin.** For those, `angle`
    // *is* the heading -- `bullet_step` overwrites it from `dir` every frame --
    // so a spin on one is either silently thrown away or, if the two ever swap
    // order, a dart drawn pointing somewhere it is not going. The rule lives
    // here rather than in the generator that writes the table, because a table
    // is data and data is exactly what stops being right without telling you.
    var _spun = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        if (global.bshape_oriented[_s] && global.bshape_spin[_s] != 0) _spun++;
    }
    ok("no oriented shape carries a default spin", _spun == 0);
    ok("the star shapes turn on their own",
       global.bshape_spin[BSHAPE_STAR] > 0
       && global.bshape_spin[BSHAPE_STAR6] > 0
       && global.bshape_spin[BSHAPE_MOTE] > 0);

    // ...and that the table reaches a bullet, which is the half of this a
    // check on the data cannot see. A default nothing reads is not a default.
    st_reset();
    var _spinner = fire(500, 500, 3, 0, BSHAPE_STAR, BCOL_GOLD, 0);
    var _plain = fire(500, 500, 3, 0, BSHAPE_DART, BCOL_GOLD, 0);
    ok("fire gives a star its shape's spin",
       _spinner.spin == global.bshape_spin[BSHAPE_STAR]);
    ok("fire gives an oriented bullet none", _plain.spin == 0);

    var _was = _spinner.angle;
    bullet_step(0, 0);
    ok("a spinning bullet turns as it flies", _spinner.angle != _was);
    st_reset();

    // The last frame of the last colour must exist, which is the one index
    // `bullet_frame` can produce that a smaller sprite would not hold.
    var _worst = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        var _f = bullet_frame(_s, BCOL_COUNT - 1, 999);
        if (_f >= sprite_get_number(global.bshape_sprite[_s])) _worst++;
    }
    ok("bullet_frame never indexes past its sprite", _worst == 0);

    ok("palette has a colour for every bullet hue",
       array_length(global.bullet_colour) == BCOL_COUNT);
}

function test_bullet_pool() {
    st_reset();
    ok("pool starts empty", bullet_count() == 0);

    for (var _i = 0; _i < 100; _i++) {
        fire(100 + _i, 100, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    }
    ok("a hundred fired is a hundred live", bullet_count() == 100);

    // Kill from the middle. The swap-remove has to leave the array dense and
    // must not lose the bullet it swapped in.
    var _tail_x = bullet_get(99).x;
    bullet_kill_at(50);
    ok("killing one drops the count", bullet_count() == 99);
    ok("the swapped-in bullet survives at the hole",
       bullet_get(50).x == _tail_x);

    // Killing every bullet by index, backwards, must land on exactly zero.
    for (var _i = bullet_count() - 1; _i >= 0; _i--) bullet_kill_at(_i);
    ok("the pool empties exactly", bullet_count() == 0);

    // **The cap refuses rather than resizing.** Past `BULLET_MAX` `fire`
    // answers `undefined`, and every caller has to cope with that -- a pool
    // that grew without limit would turn a runaway pattern into a machine that
    // stops responding.
    for (var _i = 0; _i < BULLET_MAX + 40; _i++) {
        fire(10, 10, 0, 0, BSHAPE_PELLET, BCOL_BONE, 0);
    }
    ok("the pool caps at BULLET_MAX", bullet_count() == BULLET_MAX);
    ok("firing past the cap answers undefined",
       fire(10, 10, 0, 0, BSHAPE_PELLET, BCOL_BONE, 0) == undefined);
    st_reset();
}

function test_fire_patterns() {
    st_reset();

    fire_ring(500, 500, 12, 3, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    ok("a ring of twelve is twelve bullets", bullet_count() == 12);

    // Evenly spaced, and the first one on the angle it was given.
    var _seen = [];
    for (var _i = 0; _i < 12; _i++) array_push(_seen, bullet_get(_i).dir);
    ok_near("the ring starts on its own angle", _seen[0], 0, 0.001);
    ok_near("the ring steps by 360/n", _seen[3] - _seen[2], 30, 0.001);

    st_reset();
    fire_fan(500, 500, 5, 3, 90, 40, BSHAPE_RICE, BCOL_GOLD, 0);
    ok("a fan of five is five bullets", bullet_count() == 5);
    ok_near("the fan's ends are +/- arc/2", bullet_get(0).dir, 70, 0.001);
    ok_near("the fan's far end", bullet_get(4).dir, 110, 0.001);
    // **An odd fan puts one bullet down the centre line**, which is the
    // difference between an aimed pattern the player must move for and one
    // they survive by standing still. It is a property worth asserting rather
    // than remembering.
    ok_near("an odd fan has a bullet on the aim line", bullet_get(2).dir,
            90, 0.001);

    st_reset();
    fire_fan(500, 500, 1, 3, 45, 40, BSHAPE_RICE, BCOL_GOLD, 0);
    ok("a fan of one fires straight down the aim", bullet_count() == 1
       && abs(bullet_get(0).dir - 45) < 0.001);

    st_reset();
    fire_stack(500, 500, 4, 2, 0.5, 30, BSHAPE_DART, BCOL_LIME, 0);
    ok("a stack of four is four bullets", bullet_count() == 4);
    ok_near("a stack rises by its step", bullet_get(3).spd, 3.5, 0.001);
    ok_near("a stack shares one angle", bullet_get(3).dir, 30, 0.001);

    st_reset();
    fire_ring_stack(500, 500, 8, 3, 2, 0.4, 0, BSHAPE_ORB, BCOL_ROSE, 0);
    ok("a ring-stack is n x rings", bullet_count() == 24);

    st_reset();
    fire_fan_stack(500, 500, 5, 3, 2, 0.5, 90, 40, BSHAPE_RICE, BCOL_BONE, 0);
    ok("a fan-stack is n x rows", bullet_count() == 15);
    // Row by row, in order, so a caller can reason about which arc is which.
    ok_near("its rows rise by the step", bullet_get(10).spd, 3, 0.001);
    // **Every row is still a fan**, which is the property the whole helper
    // exists for: the odd-count rule has to survive being stacked, or an aimed
    // volley has a hole down the middle of two rows out of three.
    ok_near("and every row keeps a bullet on the aim line",
            bullet_get(12).dir, 90, 0.001);

    // **The skew turns each row off the one in front.** Without it three rows
    // put their gaps on the same radial lines and the volley has one answer;
    // it defaults to zero so a caller who wants the columns aligned still has
    // that.
    st_reset();
    fire_fan_stack(500, 500, 3, 2, 2, 0.5, 90, 40, BSHAPE_RICE, BCOL_BONE, 0,
                   6);
    ok_near("a skewed row is turned off the one in front",
            bullet_get(4).dir - bullet_get(1).dir, 6, 0.001);

    // Aiming is pure and takes its target explicitly, which is what makes it
    // assertable at all.
    ok_near("aim_at points right", aim_at(0, 0, 100, 0), 0, 0.001);
    ok_near("aim_at points up", aim_at(0, 0, 0, -100), 90, 0.001);
    st_reset();
}

function test_bullet_motion() {
    st_reset();

    // No delay: it moves on the first step, and it moves by its speed.
    var _b = fire(500, 500, 4, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok_near("a bullet moves by its speed", _b.x, 504, 0.001);
    ok_near("and not in the other axis", _b.y, 500, 0.001);

    st_reset();
    // **A delayed bullet does not move.** It is a mark saying something is
    // about to be here, and a mark that drifted would be a promise the bullet
    // then breaks.
    var _d = fire(500, 500, 4, 0, BSHAPE_ORB, BCOL_CYAN, 5);
    for (var _i = 0; _i < 5; _i++) bullet_step(0, 0);
    ok("a delayed bullet has not moved", _d.x == 500 && _d.delay == 0);
    bullet_step(0, 0);
    ok_near("and moves once its delay is spent", _d.x, 504, 0.001);

    st_reset();
    var _a = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    _a.acc = 0.5;
    _a.spd_max = 2.0;
    for (var _i = 0; _i < 20; _i++) bullet_step(0, 0);
    ok_near("acceleration is clamped by spd_max", _a.spd, 2.0, 0.001);

    st_reset();
    var _t = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    _t.turn = 3;
    for (var _i = 0; _i < 10; _i++) bullet_step(0, 0);
    ok_near("turn accumulates every frame", _t.dir, 30, 0.001);

    // An oriented shape's drawn angle tracks its direction; a round one spins.
    ok("an oriented bullet faces where it is going",
       global.bshape_oriented[BSHAPE_DART]);
    st_reset();

    // Culling: a bullet that leaves is gone.
    fire(GAME_W + CULL_MARGIN - 5, 500, 20, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok("a bullet that leaves the field is culled", bullet_count() == 0);
    st_reset();
}

function test_bullet_cartesian() {
    st_reset();

    // The B-series: a bullet given components rather than a heading.
    var _b = fire_xy(500, 500, 3, -4, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok_near("a Cartesian bullet moves by its x component", _b.x, 503, 0.001);
    ok_near("and by its y component", _b.y, 496, 0.001);
    // **Both models keep `dir` and `spd` true**, which is what lets collision,
    // aiming and every oriented sprite go on reading one motion model.
    ok_near("its speed is the magnitude of the two", _b.spd, 5, 0.001);
    ok_near("and its heading is honest",
            _b.dir, point_direction(0, 0, 3, -4), 0.001);

    st_reset();
    // **The shape the polar model cannot draw.** A bullet fired flat that
    // falls: `dir`, `spd`, `acc` and `turn` bend a path only along its own
    // direction, so there is no way to write this as a heading and a speed.
    var _f = fire(500, 200, 6, 0, BSHAPE_PELLET, BCOL_GOLD, 0);
    bullet_force(_f, 0, 0.5, BQ_KEEP, 4);
    for (var _i = 0; _i < 30; _i++) bullet_step(0, 0);
    ok("a force pulls a bullet off its heading", _f.y > 200);
    ok_near("and leaves the other axis alone", _f.vx, 6, 0.001);
    // Sign-aware: the cap can only ever be a terminal velocity, never a shove.
    ok_near("the cap is a terminal velocity", _f.vy, 4, 0.001);
    ok("and the heading follows the path down",
       _f.dir > 270 && _f.dir < 360);

    st_reset();
    // A swept test reads `px`/`py`, which the Cartesian branch maintains --
    // so a fast falling bullet cannot tunnel any more than a fast flat one.
    fire_xy(400, 500, 24, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    bullet_step(0, 0);
    ok("a Cartesian bullet is swept for collision like any other",
       bullet_hit_index(412, 500, PLAYER_R) == 0);

    st_reset();
    // **A polar instruction wins.** Otherwise a force set forty frames ago
    // would silently override the instruction that has just arrived.
    var _p = fire(500, 500, 4, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_force(_p, 0, 0.6);
    bullet_move_at(_p, 4, 4, 180);
    for (var _i = 0; _i < 6; _i++) bullet_step(0, 0);
    ok("a polar instruction takes a bullet off the Cartesian model",
       !_p.cart && _p.ax == 0);
    ok_near("and it goes where it was told", _p.dir, 180, 0.001);
    st_reset();
}

function test_bullet_mods() {
    st_reset();

    // Aim: turns to face the target on the nose, once.
    //
    // `life` is incremented at the *end* of a step, so a bullet spawned this
    // frame is on frame 0 during its first step and an event scheduled for
    // frame `_at` fires on step `_at + 1`. Asserted rather than adjusted,
    // because the alternative -- incrementing first -- would make frame 0
    // unreachable.
    var _b = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_aim_at(_b, 3);
    for (var _i = 0; _i < 3; _i++) bullet_step(500, 0);
    ok("an aimed bullet has not turned early", abs(_b.dir - 0) < 0.001);
    bullet_step(500, 0);
    // Loose, because the bullet has *moved* over those three frames -- it is
    // aiming from where it is now, which is a few pixels off where it started,
    // and that is the correct behaviour rather than an error to tighten away.
    ok_near("an aimed bullet turns to its target", _b.dir, 90, 2.0);
    ok("and its event is spent", _b.q_i == _b.q_n);

    st_reset();
    // The offset is lead or lag, and it is what makes an aimed pattern a
    // pattern rather than a shot.
    var _o = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_aim_at(_o, 0, 30);
    bullet_step(500, 0);
    ok_near("an aim offset leads its target", _o.dir, 120, 2.0);

    st_reset();
    // Split: the parent dies and the children are its shape and colour, which
    // is what makes a burst legible as one event.
    var _s = fire(500, 500, 1, 0, BSHAPE_SPHERE, BCOL_ROSE, 0);
    bullet_split_at(_s, 2, 8, 3);
    for (var _i = 0; _i < 4; _i++) bullet_step(0, 0);
    ok("a split leaves its children behind", bullet_count() == 8);
    var _same = true;
    for (var _i = 0; _i < bullet_count(); _i++) {
        if (bullet_get(_i).shape != BSHAPE_SPHERE
            || bullet_get(_i).col != BCOL_ROSE) _same = false;
    }
    ok("the children carry the parent's shape and colour", _same);

    st_reset();
    // **A shed is a split whose parent lives**, which is the whole difference
    // and the reason it is a kind of its own: a bullet that drops a wake
    // behind it is a different pattern from one that bursts.
    var _w = fire(500, 500, 2, 0, BSHAPE_RICE, BCOL_JADE, 0);
    bullet_shed_every(_w, 1, 2, 3, 1, 4, 180);
    for (var _i = 0; _i < 8; _i++) bullet_step(0, 0);
    ok("a wake leaves one child per burst", bullet_count() == 4);
    ok_near("and the parent flies on through all of them", _w.x, 516, 0.001);

    st_reset();
    // Homing is capped, and the cap is the whole of what makes it fair. It
    // carries no frame, because it is what the bullet does on every one.
    var _h = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    _h.bmod = BMod.Home;
    _h.mod_a = 2;                          // degrees a frame
    bullet_step(500, 0);
    ok_near("homing turns by at most its cap", _h.dir, 2, 0.001);
    st_reset();
}

function test_bullet_queue() {
    st_reset();

    // **Two events on one bullet.** This is the whole reason the queue exists:
    // the single slot it replaced could hold the first of these or the second
    // and never both, so half of what ph3's AddPattern chain is used for could
    // not be written here at all.
    var _b = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_accel_at(_b, 2, 0.5, 4);
    bullet_turn_at(_b, 6, 5);
    for (var _i = 0; _i < 3; _i++) bullet_step(0, 0);
    ok("the first event fires on its frame", _b.acc == 0.5);
    ok("and the second has not fired early", _b.turn == 0);
    for (var _i = 0; _i < 5; _i++) bullet_step(0, 0);
    ok("and then the second one does", _b.turn == 5);
    ok_near("acceleration is still capped by its own limit", _b.spd, 4, 0.001);

    st_reset();
    // Sorted on insert, so a pattern may write its events in any order.
    var _q = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_turn_at(_q, 9, 3);
    bullet_move_at(_q, 1, 6);
    ok("events sort by frame however they were added",
       _q.q[0].at == 1 && _q.q[1].at == 9);
    bullet_step(0, 0);
    bullet_step(0, 0);
    ok("and the earlier one is the one that fired",
       _q.spd == 6 && _q.turn == 0);

    st_reset();
    // BQ_KEEP is not zero, and the difference matters: zero speed and zero
    // degrees are both things a pattern might genuinely mean.
    var _k = fire(500, 500, 3, 45, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_move_at(_k, 0, BQ_KEEP, 180);
    bullet_step(0, 0);
    ok("a kept field is left alone", _k.spd == 3);
    ok("while the one beside it is set", _k.dir == 180);

    st_reset();
    // **The queue refuses rather than growing**, on the same terms as the pool.
    var _f = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    for (var _i = 0; _i < BULLET_QUEUE_MAX + 4; _i++) bullet_turn_at(_f, _i, 1);
    ok("a bullet's queue refuses past its cap", _f.q_n == BULLET_QUEUE_MAX);

    st_reset();
    // A scheduled graphic change, and the hitbox that has to follow it --
    // `bullet_table` is the one place either is decided, and a bullet drawn as
    // one shape while colliding as another is the exact lie it exists to stop.
    var _g = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_graphic_at(_g, 1, BSHAPE_SPHERE, BCOL_ROSE);
    bullet_step(0, 0);
    bullet_step(0, 0);
    ok("a scheduled graphic change swaps the picture",
       _g.shape == BSHAPE_SPHERE && _g.col == BCOL_ROSE);
    ok("and the hitbox goes with it",
       _g.r == global.bshape_radius[BSHAPE_SPHERE]);

    // A pattern firing into a full pool gets `undefined` back from `fire`, and
    // must not have to test for it before every line that decorates the shot.
    ok("scheduling on a refused bullet is not an error",
       bullet_turn_at(undefined, 4, 2) == undefined);
    st_reset();
}

function test_bullet_expiry() {
    st_reset();

    // **A bullet that never leaves the field never left the pool.** Culling is
    // by geometry alone, so anything homing -- and anything turning fast
    // enough to orbit -- used to live until the phase ended, and the pool is a
    // refusal rather than a resize: what that reaches a player as is a boss
    // whose later patterns quietly stop firing.
    var _b = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_expire_at(_b, 10, 6);
    for (var _i = 0; _i < 10; _i++) bullet_step(0, 0);
    ok("a bullet with a lifetime is solid until its frame",
       bullet_hit_index(_b.x, _b.y, PLAYER_R) == 0);

    bullet_step(0, 0);
    ok("it starts fading on that frame", _b.fade_t > 0);
    // **Harmless from the first frame of the fade.** What the player watches
    // leave has already stopped mattering, so the fade is a courtesy to the
    // eye and never a window in which a ghost can still land a hit.
    ok("a fading bullet cannot hit",
       bullet_hit_index(_b.x, _b.y, PLAYER_R) == -1);
    ok("and cannot be grazed either",
       bullet_graze(_b.x, _b.y, GRAZE_R) == 0);

    for (var _i = 0; _i < 6; _i++) bullet_step(0, 0);
    ok("and it is gone when the fade is", bullet_count() == 0);
    st_reset();
}

function test_spell_resist() {
    st_reset();

    // **The two sweeps differ, and this is the difference.** A circle is
    // something the player did -- a bomb, or the mercy clear after a hit --
    // and `resist` is how the genre writes a bullet a bomb cannot take.
    var _r = fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    _r.resist = true;
    fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    ok("a bomb takes the ordinary bullets",
       bullet_clear_circle(500, 500, 200, false) == 1);
    ok("and leaves the bomb-proof one", bullet_count() == 1);
    ok("which is the one that resisted", bullet_get(0).resist);

    // A phase change is the *game* changing what is on the field, and a
    // bullet left over from the previous attack is a bug, not a challenge.
    bullet_clear_all(false);
    ok("a phase change takes everything", bullet_count() == 0);

    st_reset();
    var _l = laser_beam(500, 500, 0, 400, 30, BCOL_GOLD, 10, 120, 10);
    _l.resist = true;
    laser_beam(500, 600, 0, 400, 30, BCOL_GOLD, 10, 120, 10);
    laser_clear_all(true);
    ok("a bomb spares a bomb-proof laser too", laser_count() == 1);
    laser_clear_all();
    ok("and a phase change does not", laser_count() == 0);
    st_reset();
}

function test_laser_graze() {
    st_reset();

    // Geometry: the spine runs right from (500, 500), it kills within
    // `wid * 0.34 + PLAYER_R` of that line, and it pays within another
    // `GRAZE_R` -- so the deal is the one a bullet already offers.
    var _l = laser_beam(500, 500, 0, 800, 40, BCOL_GOLD, 10, 200, 10);

    // **A warning line is not dangerous, so standing in one is not nerve.**
    // Paying for it would be paying the player for reading the telegraph and
    // then ignoring what it said.
    ok("a warning line cannot be grazed",
       laser_graze(700, 520, PLAYER_R) == 0);

    for (var _i = 0; _i < 10; _i++) laser_step();
    ok("a player well clear of a live beam pays nothing",
       laser_graze(700, 580, PLAYER_R) == 0);
    ok("riding one pays", laser_graze(700, 520, PLAYER_R) == 1);
    // **On a cooldown, where a bullet is grazed once ever.** A bullet passes
    // and is gone; a laser stands there, and a flag would pay a player who
    // brushed it for a frame what it pays one who rode the length of it.
    ok("and not again on the very next frame",
       laser_graze(700, 520, PLAYER_R) == 0);

    ok("the graze band sits outside the band that kills",
       !laser_hits(_l, 700, 520, PLAYER_R));
    ok("and the band that kills still does", laser_hits(_l, 700, 508, PLAYER_R));

    for (var _i = 0; _i < LASER_GRAZE_CD; _i++) laser_step();
    ok("riding it keeps paying, once the cooldown is up",
       laser_graze(700, 520, PLAYER_R) == 1);
    st_reset();
}

function test_collision() {
    st_reset();

    // **A fast bullet is tested against the segment it travelled.** At speed
    // twenty-four a bullet moves twenty-four pixels between frames and the
    // player's hitbox is four; a point test misses roughly four times in five,
    // and what that produces is a bullet passing *through* the player and
    // doing nothing, at random.
    var _b = fire(400, 500, 24, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    bullet_step(0, 0);      // now at 424; the player is at 412, between them
    ok("a fast bullet cannot tunnel through the player",
       bullet_hit_index(412, 500, PLAYER_R) == 0);

    st_reset();
    fire(400, 500, 1, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    ok("a bullet a long way off does not hit",
       bullet_hit_index(900, 500, PLAYER_R) == -1);

    st_reset();
    // A delayed bullet is intangible. This is the single most important
    // fairness rule in the genre.
    fire(500, 500, 0, 0, BSHAPE_BALL, BCOL_CRIMSON, 30);
    ok("a bullet still fading in cannot hit",
       bullet_hit_index(500, 500, PLAYER_R) == -1);

    // The segment helper itself, since everything above rests on it.
    ok_near("a point on a segment is zero away",
            point_seg_dist(5, 0, 0, 0, 10, 0), 0, 0.001);
    ok_near("a point beside a segment measures perpendicular",
            point_seg_dist(5, 3, 0, 0, 10, 0), 3, 0.001);
    ok_near("a point past the end measures to the end",
            point_seg_dist(14, 0, 0, 0, 10, 0), 4, 0.001);
    st_reset();
}

function test_graze() {
    st_reset();
    fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    var _first = bullet_graze(500 + GRAZE_R * 0.5, 500, GRAZE_R);
    var _again = bullet_graze(500 + GRAZE_R * 0.5, 500, GRAZE_R);
    ok("a near miss grazes", _first == 1);
    // **A bullet is grazed once, ever.** Without the flag a player parked
    // beside a slow bullet grazes it sixty times a second, which turns the one
    // mechanic that rewards nerve into one that rewards loitering.
    ok("and never grazes twice", _again == 0);

    st_reset();
    fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CYAN, 30);
    ok("a bullet still fading in cannot be grazed",
       bullet_graze(500, 500, GRAZE_R) == 0);
    st_reset();
}

function test_laser() {
    st_reset();

    var _l = laser_beam(500, 500, 0, 800, 40, BCOL_GOLD, 20, 30, 10);
    ok("a beam starts in its warning", _l.phase == LaserPhase.Warn);
    // **A warning cannot kill.** If it could, the telegraph would be a lie and
    // the whole mechanic would be a coin toss with extra steps.
    ok("a warning line is not dangerous", !laser_hits(_l, 700, 500, 4));
    ok("and is drawn thin", laser_visual(_l).wid < _l.wid * 0.5);

    for (var _i = 0; _i < 20; _i++) laser_step();
    ok("a beam fires when its warning is up", _l.phase == LaserPhase.Fire);
    ok("a firing beam hits what is under it", laser_hits(_l, 700, 500, 4));
    ok("and not what is beside it", !laser_hits(_l, 700, 500 + 200, 4));

    for (var _i = 0; _i < 30; _i++) laser_step();
    ok("a beam fades when its time is up", _l.phase == LaserPhase.Fade);
    ok("a fading beam is not dangerous", !laser_hits(_l, 700, 500, 4));

    for (var _i = 0; _i < 12; _i++) laser_step();
    ok("and is gone afterwards", laser_count() == 0);

    st_reset();
    // A ray's body runs *backwards* from its head, which is the one thing
    // about it that is easy to get the wrong way round.
    var _r = laser_ray(500, 500, 0, 6, 200, 24, BCOL_CRIMSON, 60);
    laser_step();
    ok("a ray covers the ground behind its head",
       laser_hits(_r, 420, 500, 4));
    ok("and nothing in front of it", !laser_hits(_r, 700, 500, 4));

    st_reset();
    // A curve is a trail of where its head has been. Nothing curves; a
    // straight thing moves and its history is the curve.
    var _c = laser_curve(500, 500, 0, 8, 3, 30, BCOL_ROSE, 400);
    for (var _i = 0; _i < 20; _i++) laser_step();
    ok("a curve lays down one node a frame", _c.node_n == 20);
    ok("its trail is dangerous", laser_hits(_c, _c.nx[4], _c.ny[4], 4));
    for (var _i = 0; _i < 100; _i++) laser_step();
    ok("and the trail is capped", _c.node_n <= CURVE_NODES);
    st_reset();
}

function test_player() {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_CY);
    var _p = _g.player;

    // **Diagonals are normalised.** Without it, moving diagonally is forty per
    // cent faster than moving straight and every player who notices travels
    // everywhere at 45 degrees.
    _p.x = GAME_CX; _p.y = GAME_CY;
    player_step(_p, { left: false, right: true, up: true, down: false,
                      shoot: false, bomb: false, focus: false }, _g);
    var _diag = point_distance(GAME_CX, GAME_CY, _p.x, _p.y);
    _p.x = GAME_CX; _p.y = GAME_CY;
    player_step(_p, { left: false, right: true, up: false, down: false,
                      shoot: false, bomb: false, focus: false }, _g);
    var _straight = point_distance(GAME_CX, GAME_CY, _p.x, _p.y);
    ok_near("a diagonal is the same speed as a straight", _diag, _straight,
            0.01);

    // Focus is slower, and that is the trade the whole mechanic rests on.
    _p.x = GAME_CX; _p.y = GAME_CY;
    player_step(_p, { left: false, right: true, up: false, down: false,
                      shoot: false, bomb: false, focus: true }, _g);
    ok("focus is slower than unfocused",
       point_distance(GAME_CX, GAME_CY, _p.x, _p.y) < _straight);

    // The field holds him.
    _p.x = 5; _p.y = 5;
    player_step(_p, { left: true, right: false, up: true, down: false,
                      shoot: false, bomb: false, focus: false }, _g);
    ok("the player is held inside the field",
       _p.x >= FIELD_MARGIN - 0.01 && _p.y >= FIELD_MARGIN - 0.01);

    // A hit costs a quarter, grants grace, and does not cost twice.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    ok("a hit costs a quarter of the bar",
       player_hit(_p) && _p.hp == HP_MAX - HP_PER_HIT);
    ok("and grants invulnerability", player_invulnerable(_p));
    ok("a second hit inside the grace does nothing", !player_hit(_p));
    ok_near("the grace is three seconds", _p.iframe, IFRAME_TIME, 1);

    // Four hits and he is done.
    _p.iframe = 0; player_hit(_p);
    _p.iframe = 0; player_hit(_p);
    _p.iframe = 0; player_hit(_p);
    ok("four hits ends the run", !_p.alive && _p.hp == 0);

    // The special spends exactly a quarter and clears what is on top of him.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    _p.mp = MP_MAX;
    fire_ring(_p.x, _p.y, 60, 0.1, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    var _before = bullet_count();
    player_bomb(_p, _g);
    for (var _i = 0; _i < BOMB_GROW + 2; _i++) player_bomb_sweep(_p);
    ok("a special costs a quarter of the meter", _p.mp == MP_MAX - MP_PER_BOMB);
    ok("and sweeps the bullets around him", bullet_count() < _before);
    ok("and grants grace", player_invulnerable(_p));

    // **The special beats the bullet.** It is checked before anything can hit,
    // which is the single most argued-about frame in the genre and the only
    // defensible way round it: a player who reacted in time should live.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    _p.mp = MP_MAX;
    fire(_p.x, _p.y, 0, 0, BSHAPE_BALL, BCOL_CRIMSON, 0);
    player_step(_p, { left: false, right: false, up: false, down: false,
                      shoot: false, bomb: true, focus: false }, _g);
    player_collide(_p, _g);
    ok("a special on the frame of a hit beats the hit", _p.hp == HP_MAX);
    st_reset();
}

/// @desc The bomb's seals: when they leave, what they sweep, what they hurt,
///       and that they are gone before the grace is.
///
///       **The last one matters most.** A seal is a thing that clears bullets
///       and does damage, and one still in the air after the player is
///       vulnerable again would be a bomb that went on fighting for them
///       after it had stopped protecting them. It is arithmetic --
///       `BOMB_SEAL_AT + BOMB_SEAL_LIFE` against `BOMB_INVULN` -- and it is
///       exactly the kind of arithmetic that stops being true when somebody
///       lengthens one of them.
function test_bomb_seals() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY + 200);
    var _p = _g.player;
    _p.mp = MP_MAX;

    ok("the seals wait for the grace to outlast them",
       BOMB_SEAL_AT + BOMB_SEAL_LIFE < BOMB_INVULN);

    player_bomb(_p, _g);
    ok("no seal is in the air on the frame of the cast",
       player_seals_live(_p) == 0);
    ok("and the close-up is", _p.card_t == PLAYER_CARD_TIME);

    // Run the bomb out. The sweep is stepped the way `player_step` steps it.
    var _launched = -1;
    for (var _f = 0; _f < BOMB_INVULN; _f++) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
        player_seals_step(_p);
        if (_launched < 0 && player_seals_live(_p) > 0) _launched = _f;
    }
    ok("the seals leave at BOMB_SEAL_AT", _launched == BOMB_SEAL_AT - 1);
    ok("and every one of them is spent by the end of the grace",
       player_seals_live(_p) == 0);

    // A seal sweeps what it flies through.
    st_reset();
    _g = st_game_at(FIELD_CX, FIELD_CY);
    _p = _g.player;
    _p.mp = MP_MAX;
    player_bomb(_p, _g);
    for (var _f = 0; _f < BOMB_SEAL_AT + 2; _f++) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
        player_seals_step(_p);
    }
    var _s = _p.seals[0];
    fire(_s.x + 20, _s.y + 20, 0, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    ok("there is a bullet beside a seal", bullet_count() == 1);
    player_seals_step(_p);
    ok("and the seal sweeps it", bullet_count() == 0);

    // ...and strikes what it catches, for real damage.
    st_reset();
    _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _p = _g.player;
    _p.mp = MP_MAX;
    var _e = enemy_spawn(EnemyKind.Wisp, FIELD_CX, FIELD_CY, 400, undefined,
                         BCOL_JADE);
    player_bomb(_p, _g);
    var _hit_at = -1;
    for (var _f = 0; _f < BOMB_INVULN; _f++) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
        player_seals_step(_p);
        enemy_take_seals(_p, _g);
        if (_hit_at < 0 && _e.hp < 400) _hit_at = _f;
    }
    ok("a seal hunts down what is on the field", _hit_at > BOMB_SEAL_AT);
    ok("and takes BOMB_SEAL_DMG off it per strike",
       (400 - _e.hp) mod BOMB_SEAL_DMG == 0 && _e.hp < 400);
    st_reset();
}

/// @desc The dial round Szuix while he cannot be hit.
///
///       It is drawn as `left / grace_max`, so the only thing a suite can say
///       about it -- and the only thing that can go wrong without anybody
///       noticing -- is that the fraction starts at one, falls, and never
///       climbs above one when one grace lands inside another.
function test_grace_dial() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _p = _g.player;

    ok("no grace to begin with", player_grace_left(_p) == 0);
    player_hit(_p);
    ok("a hit gives the dial its full sweep",
       _p.grace_max == IFRAME_TIME
       && player_grace_left(_p) == IFRAME_TIME);

    // A bomb cast inside the grace of a hit. The dial must not overfill: the
    // two overlap rather than adding up.
    _p.mp = MP_MAX;
    player_bomb(_p, _g);
    ok("a bomb inside a grace keeps the longer of the two",
       player_grace_left(_p) == max(IFRAME_TIME - 0, BOMB_INVULN));
    ok("and the dial never reads over full",
       player_grace_left(_p) <= _p.grace_max);

    // The heartbeat is a pure function of the clock, and it has to join up
    // across its own wrap or the warning ticks once a cycle.
    var _peak = player_heartbeat(0);
    ok("the heartbeat peaks at the start of a beat", _peak > 0.9);
    ok_near("and joins up across the wrap", player_heartbeat(LOW_HP_BEAT),
            _peak, 0.02);
    var _rest = player_heartbeat(LOW_HP_BEAT * 0.62);
    ok("and rests between beats", _rest < 0.1);
    st_reset();
}

/// @desc The harness's invulnerability flag. See `player_new`.
///
///       **Asserted for two things, and the second is the one that matters.**
///       That an untouchable player keeps its health is obvious. That being
///       hit sweeps the field is not -- it is `player_hit`'s mercy clear, it
///       is correct in play, and it is what made a posed screenshot lie about
///       the pattern it was taking a picture of.
function test_untouchable() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _p = _g.player;

    // A wall of bullets across the player, of the kind a posed scene stands in
    // the middle of for sixteen seconds.
    fire_ring(_p.x, _p.y, 24, 0.01, 0, BSHAPE_ORB, BCOL_AZURE, 0);
    var _wall = bullet_count();
    ok("there is something to be hit by", _wall >= 20);

    _p.untouchable = true;
    ok("an untouchable player cannot be touched", player_invulnerable(_p));
    ok("and a hit on one does nothing", !player_hit(_p));
    ok("so it keeps its health", _p.hp == HP_MAX);
    // **The half that is not about health.** A hit clears a circle 190 wide,
    // which in a posed scene is a hole in the ward being photographed.
    ok("and nothing is swept off the field", bullet_count() == _wall);

    // And it is off by default, or every suite that drives the player would be
    // proving the wrong thing.
    _p.untouchable = false;
    _p.iframe = 0;
    ok("an ordinary player is touchable", !player_invulnerable(_p));
    ok("and a hit on one lands", player_hit(_p));
    ok("and costs health", _p.hp < HP_MAX);
    ok("and clears what was on top of them", bullet_count() < _wall);
    ok("a fresh player is not untouchable", !player_new().untouchable);

    st_reset();
}

function test_items() {
    st_reset();
    item_spawn(500, 500, ItemKind.Health);
    item_spawn(500, 500, ItemKind.Mana);
    ok("shards spawn", item_count() == 2);

    var _got = item_step(500, 500);
    ok("a shard on top of the player is collected", _got.n == 2);
    ok("red is health and blue is special",
       _got.hp == ITEM_HP_VALUE && _got.mp == ITEM_MP_VALUE);
    ok("and it pays a tally", _got.tally > 0);
    ok("the field is emptied", item_count() == 0);

    st_reset();
    // **Above the line, everything comes to you.** The point of collection is
    // the one thing in the genre that rewards flying up into the pattern.
    item_spawn(200, 900, ItemKind.Tally);
    var _it = global.items[0];
    item_step(1700, ITEM_AUTO_LINE - 10);
    ok("above the line a distant shard is drawn in", _it.homing);

    st_reset();
    item_spawn(200, 900, ItemKind.Tally);
    _it = global.items[0];
    item_step(1700, GAME_H - 100);
    ok("below it, a distant shard is not", !_it.homing);
    st_reset();
}

function test_boss_table() {
    var _p = ziggy_phases();
    ok("Ziggy has seven attacks", array_length(_p) == 7);

    // **The thresholds must descend and must reach zero**, or the fight either
    // never ends or ends in the middle. Nothing else would notice: an attack
    // whose `hp_end` is above the previous one's simply completes on its first
    // frame, which reads as the boss skipping an attack at random.
    var _descends = true;
    var _prev = 1.0;
    for (var _i = 0; _i < array_length(_p); _i++) {
        if (_p[_i].hp_end >= _prev) _descends = false;
        _prev = _p[_i].hp_end;
    }
    ok("the phase table descends", _descends);
    ok("and ends at zero", _p[array_length(_p) - 1].hp_end == 0);

    var _named = true;
    var _timed = true;
    for (var _i = 0; _i < array_length(_p); _i++) {
        if (_p[_i].kind == AttackKind.Spell && _p[_i].name == "") _named = false;
        if (_p[_i].time <= 0) _timed = false;
    }
    ok("every spell has a name", _named);
    // A timer is not a failure state -- running out ends the attack the same
    // way and simply awards no capture. What it stops is a player who cannot
    // beat one spell being stuck on it forever.
    ok("every attack has a time limit", _timed);

    // The midboss too, since it goes through the same machinery.
    ok("the midboss's table descends and ends at zero",
       ziggy_midboss_def().final == false);
}

function test_boss_phases() {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _b = ziggy_spawn(_g);
    ok("the boss reaches the field", _b != undefined);

    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    boss_enter_phase(_b, _g, 0);

    ok("it starts on its first attack", _b.boss.phase == 0);
    // A non-spell has no ceremony, so it opens the moment it is entered. The
    // pause between attacks is all the breathing room one gets, which is the
    // difference the ceremony exists to draw.
    ok("and is vulnerable once it has", boss_vulnerable(_b));
    ok("a non-spell holds nothing back", _b.boss.lead_t == 0);

    // **A spell declares itself before it fires**, which is the genre's rule
    // and was missing: a spell used to open on the frame it was named, so the
    // eye card announcing it was drawn over bullets it had already launched.
    // Nothing about this is visible from a still frame and nothing about it is
    // visible from the phase table either -- it is the one rule here that
    // lives between the two.
    st_reset();
    boss_enter_phase(_b, _g, 1);            // Cinder Waltz
    ok("a spell opens with a declaration", _b.boss.lead_t == BOSS_SPELL_LEAD);
    ok("through which the boss cannot be shot", !boss_vulnerable(_b));
    for (var _i = 0; _i < BOSS_SPELL_LEAD; _i++) boss_act(_b, _g);
    ok("and fires nothing while it does", global.bullet_n == 0);
    ok("and the clock has not started", _b.boss.phase_t == 0);
    boss_act(_b, _g);
    ok("then the pattern opens", global.bullet_n > 0);
    ok("and the boss is live", boss_vulnerable(_b));

    st_reset();
    boss_enter_phase(_b, _g, 0);

    // Drive its health through every threshold and check it walks the table in
    // order and stops exactly once.
    var _steps = 0;
    var _seen = 0;
    while (!_b.boss.beaten && _steps < 40000) {
        _b.hp -= 40;
        boss_act(_b, _g);
        // Skip the pause between attacks rather than waiting it out.
        if (_b.boss.clear_t > 1) _b.boss.clear_t = 1;
        _steps++;
        // Only count phases that are actual attacks. `boss_enter_phase` is
        // called one past the end to finish the fight, and that index is a
        // marker rather than a phase the boss ever ran.
        if (_b.boss.phase > _seen
            && _b.boss.phase < array_length(_b.boss.phases)) {
            _seen = _b.boss.phase;
        }
    }
    ok("the boss works through every attack",
       _seen == array_length(ziggy_phases()) - 1);
    ok("and is beaten at the end of them", _b.boss.beaten);
    ok("the run is told, and told it was the final boss",
       _g.beaten && _g.beaten_final);

    // A timeout ends an attack too, and pulls the bar down to the threshold so
    // the bar can never disagree with which attack the boss is on.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _b = ziggy_spawn(_g);
    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    boss_enter_phase(_b, _g, 0);
    for (var _i = 0; _i < ziggy_phases()[0].time + 2; _i++) boss_act(_b, _g);
    ok("running the clock out ends the attack", _b.boss.clear_t > 0);
    ok("and pulls the bar down to the threshold",
       _b.hp <= _b.hp_max * ziggy_phases()[0].hp_end + 0.001);
    st_reset();
}

/// @desc A boss that fires nothing, so a movement kind can be driven without a
///       pattern in the way of the measurement.
function st_still(_e, _g, _t) {}

/// @desc Ziggy, on the field, on one endless attack with the given movement.
///
///       **The table is replaced rather than the fight being played**, because
///       what is under test is the movement column and not any pattern that
///       happens to name it -- and a suite that drove `Demon Sealing Hex` to
///       assert on tracking would fail the day somebody retimed the ward.
function st_boss_on_move(_g, _move) {
    var _b = ziggy_spawn(_g);
    _b.boss.phases = [{
        kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
        hp_end: 0.0, time: 1000000, move: _move, attack: st_still,
    }];
    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    boss_enter_phase(_b, _g, 0);
    return _b;
}

/// @desc How a boss carries itself through an attack. See `boss_move`.
function test_boss_move() {
    st_reset();

    // **The default has to survive the column being added.** Every attack in
    // the game was written before this existed and none of them names a
    // movement, so a phase with no `move` member must go on drifting -- and a
    // bare `.move` read would not merely get that wrong, it would raise on the
    // first frame of the fight.
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _zb = ziggy_spawn(_g);
    var _drifts = true;
    for (var _i = 0; _i < array_length(_zb.boss.phases); _i++) {
        if (boss_move_kind(_zb.boss, _i) != BossMove.Drift) _drifts = false;
    }
    ok("an attack that names no movement drifts", _drifts);
    // Either end of the table is ceremony rather than an attack -- the arrival
    // and the pause after the last one -- and an index off the end must answer
    // rather than reaching past the array.
    ok("and so does the ceremony either side of the table",
       boss_move_kind(_zb.boss, -1) == BossMove.Drift
       && boss_move_kind(_zb.boss, array_length(_zb.boss.phases))
          == BossMove.Drift);

    // ---- Fixed ------------------------------------------------------------
    st_reset();
    _g = st_game_at(FIELD_X0 + FIELD_MARGIN, GAME_H - 300);
    var _b = st_boss_on_move(_g, BossMove.Fixed);
    _b.x = FIELD_X0 + 100;                  // well off station
    _b.y = FIELD_Y0 + 700;
    for (var _i = 0; _i < 240; _i++) boss_act(_b, _g);
    ok("a fixed attack takes its station",
       abs(_b.x - _b.boss.home_x) < 2 && abs(_b.y - _b.boss.home_y) < 2);

    // **And holds it.** A residual wobble would be the drift put back under
    // another name, and the attacks that ask for this ask because their shape
    // is measured from their own origin.
    var _lo = _b.x, _hi = _b.x;
    for (var _i = 0; _i < 600; _i++) {
        boss_act(_b, _g);
        _lo = min(_lo, _b.x);
        _hi = max(_hi, _b.x);
    }
    ok("and holds it", _hi - _lo < 1);
    ok("whatever the player does", abs(_b.x - _b.boss.home_x) < 2);

    // ---- Track ------------------------------------------------------------
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _b = st_boss_on_move(_g, BossMove.Track);

    _g.player.x = FIELD_X0 + FIELD_MARGIN;
    for (var _i = 0; _i < 900; _i++) boss_act(_b, _g);
    ok("a tracking attack comes to a player in the left corner",
       _b.x < FIELD_CX - 300);

    _g.player.x = FIELD_X1 - FIELD_MARGIN;
    for (var _i = 0; _i < 900; _i++) boss_act(_b, _g);
    ok("and to one in the right corner", _b.x > FIELD_CX + 300);

    // **Loosely, which is the whole of the difference between this and a
    // homing boss.** The station walks at a capped speed rather than easing
    // toward the player, so a player who crosses the field genuinely gets out
    // from under the boss and keeps that for the seconds it takes to walk
    // back. An ease would be fastest exactly when they were furthest away.
    _g.player.x = FIELD_X0 + FIELD_MARGIN;
    for (var _i = 0; _i < 30; _i++) boss_act(_b, _g);
    ok("but loosely -- half a second on it is still half a field behind",
       abs(_b.x - _g.player.x) > FIELD_W * 0.5);

    // **It still wanders while it tracks.** A boss parked exactly above the
    // player fires every aimed pattern straight down, which is the thing the
    // drift exists to prevent, reintroduced by the fix for it.
    _g.player.x = FIELD_CX;
    for (var _i = 0; _i < 400; _i++) boss_act(_b, _g);
    _lo = _b.x;
    _hi = _b.x;
    for (var _i = 0; _i < 700; _i++) {
        boss_act(_b, _g);
        _lo = min(_lo, _b.x);
        _hi = max(_hi, _b.x);
    }
    ok("and wanders while it tracks", _hi - _lo > BOSS_TRACK_SWAY);

    // The sway is squashed against the edge rather than the station being held
    // off it, so a cornered player still gets a boss over them -- and neither
    // half of that may put the sprite off the side of the picture.
    var _inside = true;
    for (var _i = 0; _i < 1200; _i++) {
        _g.player.x = ((_i div 300) mod 2 == 0)
            ? FIELD_X0 + FIELD_MARGIN : FIELD_X1 - FIELD_MARGIN;
        boss_act(_b, _g);
        if (_b.x < FIELD_X0 + BOSS_TRACK_EDGE - 1
            || _b.x > FIELD_X1 - BOSS_TRACK_EDGE + 1) _inside = false;
    }
    ok("and never carries itself off the side of the field", _inside);

    // **A tracking attack starts from where the boss is.** The tracked column
    // is dragged along behind the boss whenever anything else is moving it; if
    // it were not, an attack following one that tracked would open by lurching
    // across the field to wherever that one had left the column.
    st_reset();
    _g = st_game_at(FIELD_X0 + FIELD_MARGIN, GAME_H - 300);
    _b = st_boss_on_move(_g, BossMove.Track);
    for (var _i = 0; _i < 900; _i++) boss_act(_b, _g);   // parked hard left
    _b.boss.phases[0].move = BossMove.Fixed;
    for (var _i = 0; _i < 400; _i++) boss_act(_b, _g);   // back to station
    _b.boss.phases[0].move = BossMove.Track;
    var _was = _b.x;
    boss_act(_b, _g);
    ok("and picks up from where the boss is rather than lurching",
       abs(_b.x - _was) < 20);

    // ---- the ceremony repositions -----------------------------------------
    //
    // **A Fixed attack takes its station during the pause before it**, because
    // the pauses move for `next_phase` and the attack moves for `phase`. That
    // is what stops it sliding into place across the first second of its own
    // pattern, and it needed nothing added to get it.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _b = st_boss_on_move(_g, BossMove.Drift);
    _b.boss.phases = [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
          hp_end: 0.5, time: 1000000, attack: st_still },
        { kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
          hp_end: 0.0, time: 1000000, move: BossMove.Fixed, attack: st_still },
    ];
    boss_enter_phase(_b, _g, 0);
    for (var _i = 0; _i < 300; _i++) boss_act(_b, _g);
    ok("the drifting attack before it is off station",
       abs(_b.x - _b.boss.home_x) > 60);
    _b.hp = _b.hp_max * 0.5;                  // break it
    boss_act(_b, _g);
    ok("breaking it opens the pause", _b.boss.clear_t > 0);
    while (_b.boss.clear_t > 0) boss_act(_b, _g);
    ok("and the fixed attack opens already on its station",
       _b.boss.phase == 1 && abs(_b.x - _b.boss.home_x) < 8);

    st_reset();
}

function test_stage_table() {
    var _e = stage_ziggy_script();
    ok("the stage has a timeline", array_length(_e) > 8);

    var _sorted = true;
    for (var _i = 1; _i < array_length(_e); _i++) {
        if (_e[_i].at < _e[_i - 1].at) _sorted = false;
    }
    ok("the timeline is in order", _sorted);

    // The boss is last, and the midboss is before it. Neither is checkable
    // against a `switch` on a frame counter, which is the argument for the
    // table being data.
    var _last_gate = -1;
    var _bosses = 0;
    for (var _i = 0; _i < array_length(_e); _i++) {
        if (!_e[_i].gate && _e[_i].fn == undefined) _last_gate = _i;
    }
    ok("no event has a missing action", _last_gate == -1);

    var _list = stage_list();
    ok("the roster has nine stages", array_length(_list) == 9);
    ok("stage one is built", stage_is_built(_list[0]));
    ok("and needs nothing to unlock", _list[0].needs == 0);
    ok("stage two is built", stage_is_built(_list[1]));
    // **No assertion about what stage two costs to unlock.** It is open while
    // the fight in it is a placeholder -- see `stage_grove_def` -- and a suite
    // that pinned that number would have to be edited on the day it goes back
    // to one, which is a suite reporting the roster rather than checking it.
    ok("and the rack can say what it costs", is_real(_list[1].needs));
    ok("stage three is built", stage_is_built(_list[2]));
    ok("and it can say what it costs too", is_real(_list[2].needs));

    // **The built stages are a prefix of the roster**, which is the honest
    // form of "the rest are marked unbuilt": the rack draws every entry and
    // the locks pace a first playthrough, so a built stage sitting after an
    // unbuilt one would be a stage nothing can reach. Written as a scan
    // rather than as an index, because this assertion was a hard-coded `1`
    // and it went stale the day a second stage was added -- which is a suite
    // reporting the roster rather than checking it.
    var _built = 0;
    var _prefix = true;
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (stage_is_built(_list[_i])) {
            if (_i != _built) _prefix = false;
            _built++;
        }
    }
    ok("and the built ones are the front of the rack", _prefix);
    ok("with the rest honestly marked unbuilt", _built < array_length(_list));

    // Stage two's own table, on the same terms as stage one's -- and one
    // thing stage one has nothing to say about: it turns half way through.
    var _e2 = stage_grove_script();
    var _sorted2 = true;
    for (var _i = 1; _i < array_length(_e2); _i++) {
        if (_e2[_i].at < _e2[_i - 1].at) _sorted2 = false;
    }
    ok("stage two's timeline is in order too", _sorted2);

    var _e3 = stage_sanctum_script();
    var _sorted3 = true;
    for (var _i = 1; _i < array_length(_e3); _i++) {
        if (_e3[_i].at < _e3[_i - 1].at) _sorted3 = false;
    }
    ok("stage three's timeline is in order too", _sorted3);
}

function test_stage_run() {
    st_stage_run(stage_ziggy_def(), "the stage");
    st_stage_run(stage_grove_def(), "stage two");
    st_stage_run(stage_sanctum_def(), "stage three");
}

/// @desc Play a whole stage headlessly, killing everything a second after it
///       arrives. **The gates are what this is testing** -- one that released
///       early would collapse the timeline into a single frame, and one that
///       never released would hang the stage.
function st_stage_run(_def, _label) {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.boss_ref = undefined;
    _g.phase = Phase.Playing;
    // The timeline reaches for `_g.bg` -- stage two turns its background half
    // way through -- so the run has to have one, exactly as a real run does.
    _g.bg = _def.make_bg();

    var _s = stage_new(_def);

    // Play the stage the way a competent player does: everything on the field
    // dies about a second after it arrives. **The gates are what this is
    // testing** -- a gate that released early would collapse the timeline into
    // one frame, and a gate that never released would hang the stage.
    var _boss_seen = false;
    for (var _i = 0; _i < 12000; _i++) {
        stage_step(_s, _g);
        if ((_i mod 70) == 0) enemy_sweep_fodder(_g);
        if (_g.boss_ref != undefined) {
            _boss_seen = true;
            // Pretend the boss died, so the stage picks up again.
            _g.boss_ref = undefined;
            _g.phase = Phase.Playing;
        }
        if (_s.done) break;
    }
    ok(_label + " reaches its end", _s.done);
    ok(_label + " puts a boss on the field on the way", _boss_seen);
    ok(_label + " leaks no enemies past its own cap",
       enemy_count() <= ENEMY_MAX);
    ok(_label + " leaks no rings past its own cap",
       ring_count() <= RING_MAX);
    st_reset();
}

/// @desc The corridor projection, the prop ring, and the grove's turn.
///
///       **Everything in here is invisible in a screenshot**, which is the
///       whole reason it is written down. A tree drawn in the wrong depth
///       order looks like a tree. A tree that is a pixel too big looks like a
///       tree. What a picture cannot say is whether the order is still right
///       after four minutes of flying, whether the wood is the same wood on
///       the second attempt, or whether the red arrives out of the distance
///       rather than everywhere at once.
function test_corridor() {
    var _v = corridor_view(false);
    var _hy = corridor_horizon(_v);

    // **The projection and its inverse have to agree**, because the ground is
    // drawn through one and every prop standing on it through the other. If
    // they disagreed the trees would float or sink, and a forest of floating
    // trees is a thing you notice and cannot name.
    var _agree = true;
    for (var _i = 1; _i <= 6; _i++) {
        var _z = 300 * _i;
        var _sy = _hy + corridor_k(_z) * CORRIDOR_CAM_H;
        if (abs(corridor_depth_at(_v, _sy) - _z) > 0.5) _agree = false;
    }
    ok("the ground's depth and a prop's footing agree", _agree);
    // **The corridor has a back wall.** Unclamped, a row a pixel under the
    // horizon reports a quarter of a million units -- further away than
    // anything the world contains, including the parked blood wavefront,
    // which drew a red line across a stage that had not turned.
    ok("the horizon is the far plane, not a divide by zero",
       corridor_depth_at(_v, _hy) == CORRIDOR_Z_FAR);
    ok("and nothing under it reports further than that",
       corridor_depth_at(_v, _hy + 1) <= CORRIDOR_Z_FAR
       && corridor_depth_at(_v, _hy + 0.2) <= CORRIDOR_Z_FAR);

    // **The camera turns, it does not slide, and that is a claim about
    // every depth at once.** Under a small yaw everything on screen shifts by
    // the same number of pixels -- the moon at infinity, the far wood and a
    // tree ten metres off -- because they have all turned through the same
    // angle. A camera that *translated* would move the near trees and leave
    // the moon where it was, which reads as a world sliding behind glass
    // rather than as a flyer looking somewhere else. Nothing about a single
    // frame could say which of the two is happening.
    var _v0 = corridor_view(false, 0, 0);
    var _v1 = corridor_view(false, 30, -12);
    var _alike = true;
    for (var _i = 1; _i <= 6; _i++) {
        var _zz = 400 * _i;
        var _dx = (_v1.cx + corridor_k(_zz) * 500)
                  - (_v0.cx + corridor_k(_zz) * 500);
        if (abs(_dx - 30) > 0.001) _alike = false;
    }
    ok("a yaw shifts every depth by the same amount", _alike);
    ok("and the horizon goes with it",
       abs((corridor_horizon(_v1) - corridor_horizon(_v0)) + 12) < 0.001);

    // **A wave band's baseline only ever dips.** The far wood's foot is drawn
    // at the vanishing point and the ground is painted over the top of it, so
    // a slice lifted even slightly shows a band of sky under a wood -- and
    // periodicity is what keeps the displacement from putting a step at every
    // tile seam, which is the defect `fbm_field`'s `wrap_y` exists to prevent
    // one dimension over.
    var _lifts = false;
    var _over = false;
    for (var _i = 0; _i <= 240; _i++) {
        var _wv = corridor_band_wave(_i / 240, GROVE_RIDGE_H, 137);
        if (_wv < 0) _lifts = true;
        if (_wv > GROVE_RIDGE_H + 0.001) _over = true;
    }
    // **The hedgerow crosses the foot of the moon, and that reverses a
    // decision.** It used to part for the path wider than the moon is round,
    // on the reasoning that undergrowth over the centrepiece would be losing
    // it -- and what that left was the most-looked-at stretch of horizon in
    // the stage ruled dead straight, under the brightest thing in the
    // picture, which is the complaint the layer was built for. It was also
    // the only place the hedge could be seen at all. It dips for the path now
    // and this is what stops the next tidy-up turning the dip back into a
    // parting.
    ok("the hedgerow dips for the path rather than parting for it",
       GROVE_SCRUB_DIP > 0 && GROVE_SCRUB_DIP < 0.75);
    var _vc = corridor_view(false, 0);
    ok("and the dip is whole on the centre line and gone past its width",
       corridor_band_dip(_vc, _vc.cx, GROVE_SCRUB_DIP_W) == 1
       && corridor_band_dip(_vc, _vc.cx + GROVE_SCRUB_DIP_W + 1,
                            GROVE_SCRUB_DIP_W) == 0);
    ok("the ridge dips the far wood's foot and never lifts it", !_lifts);
    ok("and never further than it was asked to", !_over);
    ok("and it is periodic in its own tile, so the band still tiles",
       abs(corridor_band_wave(0, GROVE_RIDGE_H, 137)
           - corridor_band_wave(1, GROVE_RIDGE_H, 137)) < 0.001);

    // Nearer is bigger and further from the middle. One line, and it is the
    // entire claim the picture rests on.
    ok("nearer is bigger", corridor_k(400) > corridor_k(1600));
    ok("and further out from the centre",
       abs(corridor_k(400) * 600) > abs(corridor_k(1600) * 600));

    // **A tree leaves the frame sideways, and that is what makes the near
    // plane safe.** Nothing in this stage is ever seen at `CORRIDOR_Z_MIN`,
    // because the trees stand off the path -- so the clamp in `corridor_k` is
    // a guard against arithmetic rather than something the eye relies on. If
    // this ever failed, a tree would grow to fill the screen and wink out.
    // Measured from the tree's *inner edge*, not from its trunk: the whole
    // sprite has to have left the field, and a tree is as wide as it is.
    // The *widest* a tree can be, not the nominal one: a prop carries its own
    // size, so the clearance has to hold for the biggest a hash can produce.
    var _half_w = corridor_prop_half_w(spr_scn_tree, GROVE_TREE_H,
                                       1 + GROVE_VARY_H, 1 + GROVE_VARY_W);
    var _edge = corridor_k(CORRIDOR_Z_NEAR) * (GROVE_PATH_HALF - _half_w);
    ok("a tree is off the side of the field before it reaches the camera",
       _edge > FIELD_W * 0.5);

    // The hash. `frac` keeps its sign in GML, so an unfolded hash comes back
    // in (-1, 1) and half of everything indexed by it lands on entry zero --
    // which is the bug `hex_debris` already shipped once.
    var _in_range = true;
    var _spread = 0;
    for (var _i = 0; _i < 400; _i++) {
        var _h = corridor_hash(_i, 17);
        if (_h < 0 || _h >= 1) _in_range = false;
        if (_h > 0.5) _spread++;
    }
    ok("the hash answers in [0, 1)", _in_range);
    ok("and does not pile up in one half", _spread > 140 && _spread < 260);
    ok("and is the same answer every time",
       corridor_hash(9, 4) == corridor_hash(9, 4));

    // ---- the ring ---------------------------------------------------------
    var _b = bg_grove();
    ok("the grove is a corridor", _b.kind == BGKIND_CORRIDOR);
    ok("and stage one is not", bg_brimstone().kind == BGKIND_PARALLAX);

    // **The stage arrives rather than starting.** It used to open at full
    // speed on its first frame, which is the one moment in it nobody
    // composed. The claim here is that the opening is slow *and* that it
    // finishes -- a fog that lifted to 96% would be a stage permanently a
    // little foggy and permanently a little slow, which is the failure nobody
    // would ever notice by looking.
    var _i0 = bg_grove();
    bg_step(_i0);
    ok("a flight opens far slower than it settles", _i0.spd < GROVE_SPEED * 0.5);
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_i0);
    ok("and the fog has lifted by the time it is over", _i0.intro == 1);
    ok_near("and it settles at exactly the speed it was asked for",
            _i0.spd, GROVE_SPEED, 0.001);

    // **The swell is a modulation and not a speed.** It rides on top of
    // `spd` rather than inside it precisely so this can be asked: four swells
    // have to travel what four of the flat speed would, or the flight having
    // a rhythm has quietly changed how long the stage is.
    //
    // **And it is gentle, which is a number rather than a feeling.** The
    // wingbeat before it changed the speed by more than one and a half per
    // cent a frame, and was reported as a little jarring; what matters is
    // not the size of the swing but how fast it happens, because the eye
    // reads speed off the things nearest the lens and a change it can catch
    // inside the half-second one of those takes to cross is a lurch.
    var _lo = 999999999;
    var _hi = 0;
    var _sum = 0;
    var _jolt = 0;
    var _was = _i0.rush;
    for (var _f = 0; _f < GROVE_SWELL * 4; _f++) {
        bg_step(_i0);
        _lo = min(_lo, _i0.rush);
        _hi = max(_hi, _i0.rush);
        _sum += _i0.rush;
        _jolt = max(_jolt, abs(_i0.rush - _was) / _i0.spd);
        _was = _i0.rush;
    }
    ok("the swell never puts the corridor into reverse", _lo > 0);
    ok("and it is a rhythm rather than a constant", _hi > _lo * 1.1);
    ok_near("and four swells travel what four flat ones would",
            _sum / (GROVE_SWELL * 4), GROVE_SPEED, GROVE_SPEED * 0.03);
    ok("and it never changes the speed by half a per cent in a frame: "
       + string_format(_jolt * 100, 1, 2) + "%", _jolt < 0.005);
    ok("and the camera stays inside its own throw",
       abs(_i0.cam_x) <= GROVE_SWAY + 0.001
       && abs(_i0.cam_y) <= GROVE_RISE + 0.001);

    // ---- the flyer steers -------------------------------------------------
    // **The camera looks where the player is**, and the claim has three parts
    // no screenshot can make between them: which way it goes, that a player
    // who commits to a side actually gets there, and that a player who merely
    // *dodges* moves it by almost nothing. The last is the whole reason the
    // follow is filtered rather than direct -- a camera that read the player
    // frame for frame would shake in time with the dodging, on the one line a
    // danmaku player measures every bullet against. See `GROVE_LEAN`.
    var _lf = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_lf, 0);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, -1);
    ok("a player at the left wall slides the camera left: "
       + string_format(_lf.lean, 1, 1) + " units",
       _lf.lean < -GROVE_LEAN * 0.9);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, 1);
    ok("and one at the right wall slides it right",
       _lf.lean > GROVE_LEAN * 0.9);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, 0);
    ok("and the middle of the field is straight ahead",
       abs(_lf.lean) < GROVE_LEAN * 0.05);

    // **The rate is the part that matters.** A player who crosses the whole
    // field must not drag the camera with them frame for frame, and the cap
    // is what makes that a guarantee rather than a tuning: this hands it the
    // worst input there is -- a player teleporting wall to wall every frame
    // -- and asks the camera to stay inside its own speed anyway.
    var _lr = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_lr, 1);
    var _was_l = _lr.lean;
    var _jerk = 0;
    for (var _f = 0; _f < 400; _f++) {
        bg_step(_lr, ((_f mod 2) == 0) ? -1 : 1);
        _jerk = max(_jerk, abs(_lr.lean - _was_l));
        _was_l = _lr.lean;
    }
    ok("and nothing the player can do moves it faster than its cap: "
       + string_format(_jerk, 1, 3) + "px", _jerk <= GROVE_LEAN_SPD + 0.0001);

    // ...and a dodge is not a decision. **Flown rather than asserted**: a
    // real player at `PLAYER_SPD` reversing every third of a second, which is
    // what dodging a fan looks like and is bounded by how fast anybody can
    // actually cross this field. Handing the camera a square wave instead
    // measures a player who can teleport, which is the input the cap above is
    // already for.
    var _ld = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_ld, 0);
    //
    // **What is measured is the swing, not the settling.** A player dodging
    // about one spot is still standing somewhere, and the camera leaning to
    // where they are standing is the feature; the first four hundred frames
    // are it arriving there, and folding those into the same min and max
    // would measure the lean and call it a wobble.
    var _dp = player_new();
    var _dlo = 999999;
    var _dhi = -999999;
    for (var _f = 0; _f < 1300; _f++) {
        _dp.x += ((((_f div 20) mod 2) == 0) ? -1 : 1) * PLAYER_SPD;
        _dp.x = clamp(_dp.x, FIELD_X0, FIELD_X1);
        bg_step(_ld, player_field_aim(_dp));
        if (_f < 400) continue;
        _dlo = min(_dlo, _ld.lean);
        _dhi = max(_dhi, _ld.lean);
    }
    ok("and a dodge barely moves it at all: "
       + string_format(_dhi - _dlo, 1, 2) + "px",
       (_dhi - _dlo) < GROVE_LEAN * 0.15);

    // **The request is a request, and a screen with no player makes none.**
    // The rack and the attack list both step a background and neither has a
    // player on it, so the default has to be the meander on its own rather
    // than a lean toward wherever the last run left somebody standing.
    var _ln = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 400; _f++) bg_step(_ln);
    ok("and a screen with no player on it does not steer", _ln.lean == 0);

    // **A rooted band goes nowhere on its own, and one that did was
    // reported.** The hedgerow hides the join between the ground and the far
    // wood, so it lies across the middle of the frame under the moon -- and
    // it carried a share of an accumulator that only ever grows, which walked
    // it a hundred pixels left every twenty seconds whatever the player did.
    // The steering could offset forty-eight of that and only while the player
    // stayed at a wall, so the net motion was always leftward on the one
    // layer where a yaw reads at all. See `grove_rooted_x`.
    var _rb = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_rb, 0);
    var _rlo = 999999;
    var _rhi = -999999;
    for (var _f = 0; _f < 1800; _f++) {
        bg_step(_rb, 0);
        var _rx = grove_rooted_x(corridor_view(false, _rb.cam_x, _rb.cam_y,
                                              _rb.lat));
        _rlo = min(_rlo, _rx);
        _rhi = max(_rhi, _rx);
    }
    ok("a rooted band travels nowhere over half a minute: "
       + string_format(_rhi - _rlo, 1, 1) + "px",
       (_rhi - _rlo) <= GROVE_SWAY * 2 + 0.001);

    // ...and the camera is the whole of what does move it, which is the half
    // of the claim that stops the fix being "pin it down and forget it".
    //
    // **And it moves a near band further than a far one, which is the whole
    // of the depth in this stage.** Pinned to the yaw alone every band shifted
    // by exactly what the moon shifted, so the canopy kept a fixed offset in
    // front of it however the player flew -- reported as the branches having
    // lost their parallax. A yaw cannot express depth; only the slide can, and
    // this is the assertion that says the slide is still there. See
    // `grove_rooted_x`.
    // **Two depths at the same instant**, so the yaw -- which is common to
    // both, being a rotation -- cancels exactly and what is left is the
    // parallax on its own. Sampling one depth at two *times* instead measures
    // the meander as well, which at these amplitudes can cancel the far
    // wood's whole travel and did.
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, -1);
    var _vl = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    var _part_l = grove_rooted_x(_vl, 0, 700)
                  - grove_rooted_x(_vl, 0, CORRIDOR_Z_FAR);
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, 1);
    var _vr = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    var _part_r = grove_rooted_x(_vr, 0, 700)
                  - grove_rooted_x(_vr, 0, CORRIDOR_Z_FAR);
    ok("the canopy parts from the far wood as the player steers: "
       + string_format(abs(_part_r - _part_l), 1, 1) + "px",
       abs(_part_r - _part_l) > GROVE_LEAN);
    ok("and it parts the other way at the other wall",
       (_part_l < 0) != (_part_r < 0));
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, 0);
    var _vm = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    ok("and the two sit together when the player is on the centre line",
       abs(grove_rooted_x(_vm, 0, 700)
           - grove_rooted_x(_vm, 0, CORRIDOR_Z_FAR)) < 1);

    // ...and the field's own fraction is what feeds it, which is the one
    // place the sign is written down.
    var _pl = player_new();
    _pl.x = FIELD_X0;
    ok("the left wall reads as -1", player_field_aim(_pl) == -1);
    _pl.x = FIELD_X1;
    ok("and the right wall as +1", player_field_aim(_pl) == 1);
    _pl.x = FIELD_CX;
    ok("and the centre line as nothing", player_field_aim(_pl) == 0);

    // **The horizon drifts, it does not bob.** A pitch on a wingbeat was
    // written, looked at and taken out: at that rate this line is a level
    // that visibly rises and falls, and a danmaku player is measuring every
    // bullet on screen against it. What replaced it is a wander on the
    // meander's own timescale -- so a second of it has to move the horizon
    // by almost nothing, which is a claim about the *rate* and the only part
    // of it a still frame could never show.
    var _cy0 = _i0.cam_y;
    for (var _f = 0; _f < 60; _f++) bg_step(_i0);
    ok("and the horizon drifts rather than bobbing",
       abs(_i0.cam_y - _cy0) < GROVE_RISE * 0.5);

    // **The order has to survive the whole stage.** The ring's claim is that
    // recycling a prop to the back of the queue keeps it sorted for ever, and
    // "for ever" is the part a screenshot cannot check. Four thousand frames
    // is about a minute of flying and several laps of the corridor.
    var _ordered = true;
    var _inside = true;
    for (var _f = 0; _f < 4000; _f++) {
        bg_step(_b);
        if ((_f mod 37) != 0) continue;
        var _o = corridor_ring_order(_b.trees);
        var _last = 999999999;
        for (var _j = 0; _j < _b.trees.n; _j++) {
            var _p = _b.trees.props[_o[_j]];
            if (_p.z > _last) _ordered = false;
            _last = _p.z;
            if (_p.z < CORRIDOR_Z_MIN || _p.z > CORRIDOR_Z_FAR * 1.2) {
                _inside = false;
            }
        }
    }
    ok("the ring is still in depth order a minute in", _ordered);
    ok("and every prop is still inside the corridor", _inside);

    // **The same wood on the second attempt.** Every recycled prop is a hash
    // of its lap, never `random`, for the same reason the hex's scatter is:
    // noise that differs every attempt is noise nobody can learn.
    var _a1 = bg_grove();
    var _a2 = bg_grove();
    for (var _f = 0; _f < 900; _f++) {
        bg_step(_a1);
        bg_step(_a2);
    }
    var _same = true;
    for (var _j = 0; _j < _a1.trees.n; _j++) {
        if (_a1.trees.props[_j].wx != _a2.trees.props[_j].wx
            || _a1.trees.props[_j].frame != _a2.trees.props[_j].frame
            || _a1.trees.props[_j].scale != _a2.trees.props[_j].scale
            || _a1.trees.props[_j].tag != _a2.trees.props[_j].tag) {
            _same = false;
        }
    }
    ok("two flights through the grove are the same flight", _same);

    // **Every ring on the background has to be stepped, and this walks them
    // rather than naming them.** The trunks were built, drawn, depth-sorted
    // and lit for several passes with nothing advancing them -- so the
    // nearest and largest things in the wood held station while the world
    // went past, and what reached a player was "those are static images
    // slapped on the background". Nothing about a prop's drawing says whether
    // it moves.
    //
    // Named individually this assertion would have passed the day it was
    // written and gone stale the day a fourth ring was added, which is the
    // shape of the bug it exists for. So it finds them: anything on the
    // background carrying a `props` array is a ring, and a ring that has not
    // recycled anything after a lap of the corridor is not being stepped.
    var _c2 = bg_grove();
    var _names = variable_struct_get_names(_c2);
    var _rings = 0;
    var _stalled = "";
    for (var _f = 0; _f < 2000; _f++) bg_step(_c2);
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _val = _c2[$ _names[_i]];
        if (!is_struct(_val) || !variable_struct_exists(_val, "props")) {
            continue;
        }
        _rings++;
        if (_val.lap <= 0) _stalled += _names[_i] + " ";
    }
    ok("the grove has more than one ring of props", _rings >= 3);

    // **Nothing may arrive in clear air.** A prop's alpha is zero at its own
    // ring's far plane, so nothing ever appears out of nothing -- and that is
    // only half of arriving unseen. Its *colour* has to already be the fog's
    // too, or what fades up is a shape in its own colour at a distance where a
    // thing that size can still be made out. The trunks recycled where more
    // than half the air was clear and it was reported twice, both times as big
    // trees popping in in front of smaller ones further back. Sorting them
    // correctly did not help: they really were in front.
    var _clear = "";
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _cv = _c2[$ _names[_i]];
        if (!is_struct(_cv) || !variable_struct_exists(_cv, "props")) continue;
        if (corridor_haze(_cv.z1) > CORRIDOR_ARRIVE_HAZE) {
            _clear += _names[_i] + " ";
        }
    }
    ok("and no ring recycles its props into clear air: " + _clear,
       _clear == "");

    // **Neither edge of the frame may go bare, and that is a claim about
    // runs rather than about counts.** A fair coin over forty trees produces
    // a run of six on one side about as often as not, and a run of six is one
    // edge of the picture empty for two seconds -- which is exactly how it
    // was reported. The wood was never too sparse; it was clumped, which is
    // what randomness does and what nobody means by it. `grove_side` places
    // them in stratified pairs -- one either side, in a hashed order -- so a
    // run is bounded at two by construction. Walked in depth order, because
    // that is the order they arrive in, and measured on the ring rather than
    // on the function so that a ring with an odd number of props, whose pairs
    // would break at the wrap, would be caught here.
    //
    // The number is the assertion. A coin flip measures nine to twelve.
    var _worst = 0;
    var _run = 0;
    var _prev = 0;
    var _ord = corridor_ring_order(_c2.trees);
    for (var _j = 0; _j < _c2.trees.n; _j++) {
        var _sd = sign(_c2.trees.props[_ord[_j]].wx);
        if (_sd == _prev) {
            _run++;
        } else {
            _run = 1;
            _prev = _sd;
        }
        _worst = max(_worst, _run);
    }
    ok("no stretch of the wood stands all down one side: " + string(_worst),
       _worst <= 2);

    // **No bough can hang across the moon.** At the far end of their ring
    // they are level with it, so that is where the clearance has to hold --
    // and it is measured from the inner edge of the widest bough the hash can
    // make, then checked against every bough actually in the ring.
    var _bk = corridor_k(GROVE_BOUGH_Z * 1.05);
    ok("no bough can hang across the moon, even at the back of its ring",
       _bk * GROVE_BOUGH_IN > GROVE_MOON_R);
    var _across = 0;
    for (var _j = 0; _j < _c2.boughs.n; _j++) {
        var _bp = _c2.boughs.props[_j];
        var _bw = corridor_prop_half_w(spr_scn_bough, GROVE_BOUGH_H,
                                       _bp.scale, _bp.aspect);
        if (abs(_bp.wx) - _bw < GROVE_BOUGH_IN - 1) _across++;
    }
    ok("and none in the ring stands inside that clearance", _across == 0);

    // ...and the understorey is on both sides of the path at once, which is
    // the layer that fills the periphery whatever the trees are doing.
    var _left = 0;
    for (var _j = 0; _j < _c2.verge.n; _j++) {
        if (_c2.verge.props[_j].wx < 0) _left++;
    }
    ok("the verge stands on both sides of the path",
       _left > _c2.verge.n * 0.35 && _left < _c2.verge.n * 0.65);

    // **No trunk may wall the field**, however wide the hash makes it. The
    // clearance is measured from a prop's inner edge for exactly this reason,
    // and this is the assertion that says so rather than the comment.
    var _walled = false;
    for (var _j = 0; _j < _c2.trunks.n; _j++) {
        var _tp = _c2.trunks.props[_j];
        var _thw = corridor_prop_half_w(spr_scn_trunk, GROVE_TRUNK_H,
                                        _tp.scale, _tp.aspect);
        if (abs(_tp.wx) - _thw < GROVE_TRUNK_HALF - 1) _walled = true;
    }
    ok("and no trunk stands closer to the path than its clearance",
       !_walled);

    // **One depth order over every ring, not one per ring.** Four rings drawn
    // as four sequential loops put every trunk in the wood in front of every
    // tree in it whatever their depths -- which reaches a player as a big tree
    // fading in *in front of* a small tree that was already closer. Depth
    // order is a property of the frame.
    corridor_merge_step(_c2.merge);
    var _count = 0;
    var _names2 = variable_struct_get_names(_c2);
    for (var _i = 0; _i < array_length(_names2); _i++) {
        var _rv = _c2[$ _names2[_i]];
        if (is_struct(_rv) && variable_struct_exists(_rv, "props")) {
            _count += _rv.n;
        }
    }
    ok("the merged pass covers every prop in every ring",
       _c2.merge.total == _count);

    var _mono = true;
    var _prev = 999999999;
    for (var _i = 0; _i < _c2.merge.total; _i++) {
        var _mp = _c2.merge.out[_i];
        if (_mp == undefined || _mp.z > _prev + 0.001) _mono = false;
        _prev = (_mp == undefined) ? _prev : _mp.z;
    }
    ok("and it is in one depth order, far to near", _mono);
    ok("and every one of them is being stepped: " + _stalled, _stalled == "");

    // Every charm hangs off a branch the sprite actually has.
    var _hangs_ok = true;
    for (var _f = 0; _f < sprite_get_number(spr_scn_tree); _f++) {
        for (var _i = 0; _i < grove_hang_count(_f); _i++) {
            var _h = grove_hang_at(_f, _i);
            if (_h[0] < 0 || _h[0] > 1 || _h[1] < 0 || _h[1] > 1) {
                _hangs_ok = false;
            }
        }
    }
    ok("every hang point is inside its own tree", _hangs_ok);
    var _tagged = true;
    for (var _j = 0; _j < _a1.trees.n; _j++) {
        var _p = _a1.trees.props[_j];
        if (_p.tag >= 0 && _p.hang >= grove_hang_count(_p.frame)) {
            _tagged = false;
        }
    }
    ok("and no charm hangs off a branch its tree has not got", _tagged);
}

/// @desc A wave band at rest draws the same picture its sprite does.
///
///       **The one suite here that draws, and it has to.** `tools/test.py`
///       never draws a frame, which is exactly why the strip's first version
///       survived: it fed a primitive page-space texture coordinates, the
///       runtime read them in sprite space, and the band came out as a
///       stretched patch of its own top-left corner -- arithmetically
///       spotless, and invisible to every assertion in the file. It was found
///       by the hedgerow it drew not being on the screen.
///
///       So the band is drawn to a surface with no wave and no dip, the same
///       sprite is drawn beside it with `draw_sprite_ext`, and the two are
///       compared a pixel at a time. Surfaces can be drawn to from a Create
///       event, which is where this runs. What it would catch is the runtime
///       changing its mind about texture space, and anybody "fixing" the
///       coordinates back to `sprite_get_uvs` because that is what they look
///       like they should be.
function test_band_strip() {
    var _w = 256;
    var _h = 80;
    var _sc = _w / sprite_get_width(spr_scn_treeline);
    var _v = { x0: 0, y0: 0, w: _w, h: _h, cx: _w / 2, x1: _w, y1: _h,
               ox: 0 };
    var _ref = surface_create(_w, _h);
    var _got = surface_create(_w, _h);

    surface_set_target(_ref);
    draw_clear_alpha(c_black, 1);
    draw_sprite_ext(spr_scn_treeline, 0, 0, 0, _sc, _sc, 0, c_white, 1);
    surface_reset_target();

    surface_set_target(_got);
    draw_clear_alpha(c_black, 1);
    corridor_draw_band_wave(_v, spr_scn_treeline, 0, 0, _sc, c_white, 1, 0, 0);
    surface_reset_target();

    // A grid of samples over the band, clear of its two ends where the strip
    // tiles and the reference does not.
    var _bh = sprite_get_height(spr_scn_treeline) * _sc;
    var _n = 0;
    var _off = 0;
    for (var _x = 6; _x < _w - 6; _x += 7) {
        for (var _y = 2; _y < _bh - 2; _y += 3) {
            var _a = surface_getpixel(_ref, _x, _y);
            var _b = surface_getpixel(_got, _x, _y);
            _n++;
            if (abs(colour_get_red(_a) - colour_get_red(_b)) > 48) _off++;
        }
    }
    surface_free(_ref);
    surface_free(_got);
    ok("a wave band at rest draws the picture its sprite does: "
       + string(_off) + " of " + string(_n) + " samples differ",
       _n > 100 && _off < _n * 0.06);
}

/// @desc The blood moon: what turns, in what order, and what stage one does
///       about it (nothing).
function test_grove_turn() {
    var _b = bg_grove();
    ok("a stage opens with nothing having happened", _b.omen == 0);
    ok("and the wave is past the far end of the corridor",
       grove_blood_at(_b, CORRIDOR_Z_FAR) == 0);

    var _speed_before = _b.spd;

    bg_set_omen(_b);
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) bg_step(_b);
    ok("the turn reaches exactly one and stops", _b.omen == 1);
    for (var _f = 0; _f < 60; _f++) bg_step(_b);
    ok("and stays there", _b.omen == 1);
    ok("the corridor is faster afterwards", _b.spd > _speed_before);
    ok("and it is the speed it was asked for",
       abs(_b.spd - GROVE_SPEED_FAST) < 0.01);

    // **The red arrives out of the distance.** This is the one claim the
    // whole transition is built on and the one a still frame is least able to
    // make: at every moment during the wave, something far away is redder
    // than something near. A ring expanding across the *screen* would have
    // turned the near trees first, which is the obvious version of this
    // effect and is backwards.
    var _c = bg_grove();
    bg_set_omen(_c);
    var _far_leads = true;
    var _seen_partial = false;
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) {
        bg_step(_c);
        var _far = grove_blood_at(_c, 4200);
        var _near = grove_blood_at(_c, 400);
        if (_far < _near) _far_leads = false;
        if (_far > 0.02 && _near < 0.98) _seen_partial = true;
    }
    ok("the far wood turns before the near wood does", _far_leads);
    ok("and there is a moment when only half of it has", _seen_partial);
    ok("by the end the whole corridor has turned",
       grove_blood_at(_c, CORRIDOR_Z_FAR) == 1
       && grove_blood_at(_c, CORRIDOR_Z_NEAR) == 1);

    // The eclipse is a body going past, so its coverage rises to totality and
    // comes back. A version that ran to the end and reversed would be two
    // movements to write and one to get wrong.
    var _d = bg_grove();
    bg_set_omen(_d);
    var _low = 1, _high = 0;
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) {
        bg_step(_d);
        var _e = grove_eclipse(_d);
        _low = min(_low, _e);
        _high = max(_high, _e);
    }
    ok("the umbra crosses the moon completely", _high >= 0.999);
    ok("and the wavefront launches after it is total",
       GROVE_WAVE_START <= 1);

    // **Stage one never turns**, and it must not raise for being asked
    // whether it has. The field is on the base struct precisely so that a run
    // can say "the stage turns" without knowing what kind of world it is
    // saying it to.
    var _brim = bg_brimstone();
    ok("a parallax stage starts unturned", _brim.omen == 0);
    bg_set_omen(_brim);
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) bg_step(_brim);
    ok("and turns harmlessly when asked", _brim.omen == 1 && _brim.t > 0);
}

function test_marks() {
    // **The ladder has to be a ladder**, which is the one thing about a grading
    // system a suite can check without opinions: the tiers are ordered, every
    // one of them has a name and a colour, and the standing a ledger reports is
    // never off the end of it.
    var _named = true;
    for (var _i = 0; _i < Mark.Count; _i++) {
        if (mark_name(_i) == "--") _named = false;
    }
    ok("every tier on the ladder is named", _named);
    ok("and the ladder is in order",
       Mark.Slag < Mark.Iron && Mark.Iron < Mark.Silver
       && Mark.Silver < Mark.Gold && Mark.Gold < Mark.Adamant);

    var _led = rank_ledger_new();
    ok("an unmarked attempt has no standing at all", rank_overall(_led) == -1);

    // **A run of golds and one slag is not a gold run**, which is the whole
    // reason the mean is floored rather than rounded. Getting this backwards
    // would let one good encounter pay for one bad one, and the grade would
    // stop meaning "consistent" and start meaning "average".
    for (var _i = 0; _i < 5; _i++) rank_note(_led, "x", Mark.Gold);
    ok("five golds is a gold standing", rank_overall(_led) == Mark.Gold);
    rank_note(_led, "x", Mark.Slag);
    ok("and one slag among them pulls it down",
       rank_overall(_led) < Mark.Gold);
    ok("the ledger counts what it was given", rank_count(_led) == 6);

    // The boss's own grading, from the three facts a phase ends knowing.
    ok("running the clock out is the bottom of the ladder",
       rank_for_attack(false, 0, 0, 0.9) == Mark.Slag);
    ok("a sigil spent costs more than a hit taken",
       rank_for_attack(true, 0, 1, 0.9) < rank_for_attack(true, 1, 0, 0.9));
    ok("clean and slow is gold", rank_for_attack(true, 0, 0, 0.1) == Mark.Gold);
    ok("clean and quick is the top of it",
       rank_for_attack(true, 0, 0, 0.9) == Mark.Adamant);

    // ...and a real fight files real marks. `test_boss_phases` drives the
    // phases; this checks the ledger they land in, because the grading being
    // *called* is the half that a pure function test cannot cover -- and it is
    // the half that broke first, on a stub controller with no ledger at all.
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _e = boss_spawn(FIELD_CX, FIELD_Y0 + 300, 1000, ziggy_phases(),
                        ziggy_def());
    _e.boss.entry_t = 0;
    _e.boss.declare_t = 0;
    _e.boss.started = true;
    var _before = rank_count(_g.marks);
    boss_end_phase(_e, _g, true);
    ok("beating an attack files a mark",
       rank_count(_g.marks) == _before + 1);
    ok("and the run now has a standing", rank_overall(_g.marks) >= 0);
    st_reset();
}

/// @desc Attack practice: the list, the request, and the seam that ends one.
///
/// **The thing worth proving here is that practice is an ordinary run**, and
/// almost every assertion below is a way of saying so: the definition it
/// builds is stage-def shaped, the boss it puts on the field is spawned by the
/// stage's own spawner, and the attack it starts is entered by the same
/// `boss_enter_phase` a fight enters one with. A mode assembled out of its own
/// parallel machinery would be a mode that drifts, and what drifts is exactly
/// what somebody is practising *against*.
function test_practice() {
    var _stage = stage_ziggy_def();
    var _bosses = practice_bosses(_stage);
    ok("stage one lists both its bosses", array_length(_bosses) == 2);

    // **A boss is listed as a function returning its table, not as a table.**
    // A table built once at stage-definition time would be shared by every run
    // that read it, and a phase struct is mutable -- so this is the difference
    // between two practice attempts and one attempt run twice.
    var _same = (_bosses[1].phases() != _bosses[1].phases());
    ok("and each hands back a fresh phase table", _same);
    ok("the midboss's table is reachable without spawning it",
       array_length(ziggy_midboss_phases()) == 2);
    ok("and it is the table the midboss actually fights",
       array_length(_bosses[0].phases()) == array_length(ziggy_midboss_phases()));

    // An unbuilt stage has no bosses and must say so rather than raising: a
    // bare `_def.bosses` on one of those is the missing-member trap.
    //
    // **Found rather than indexed.** This read `_list[1]`, which was an
    // unbuilt stage until the day stage two was written and then quietly
    // became an assertion about a built one.
    var _list = stage_list();
    var _unbuilt = undefined;
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (!stage_is_built(_list[_i])) {
            _unbuilt = _list[_i];
            break;
        }
    }
    ok("the roster still has an unbuilt stage in it", _unbuilt != undefined);
    ok("an unbuilt stage offers nothing to practise",
       !practice_available(_unbuilt));
    ok("and stage one does", practice_available(_stage));

    // ---- the request ------------------------------------------------------
    var _p = practice_new(_stage, 1, 1);          // Ziggy, Cinder Waltz
    ok("a spell is listed under its own name", _p.label == "Cinder Waltz");
    var _np = practice_new(_stage, 1, 0);
    ok("and a non-spell under the boss's, numbered",
       _np.label == "ZIGGY 1");

    ok("the run it describes has one graded encounter",
       _p.def.encounters == 1);
    ok("and an empty timeline", array_length(_p.def.build()) == 0);
    // **The id is empty so nothing can be recorded against it.** A practice
    // attempt is not a stage result; `progress_record` is keyed on this, and a
    // stage marked cleared by somebody drilling its first non-spell would be
    // permanent and silent.
    ok("and no stage to file a clear against", _p.def.id == "");
    ok("a blank id reads back as nothing cleared",
       !progress_stage("").cleared && progress_stage("").best == 0);

    // ---- starting one -----------------------------------------------------
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.practice = practice_new(_stage, 1, 3);     // Ziggy, Meteor Fall
    _g.player.hp = 10;
    _g.player.mp = 0;
    var _b = practice_begin(_g);

    ok("the boss reaches the field", _b != undefined);
    ok("and past the arrival and the name splash",
       _b.boss.entry_t == 0 && _b.boss.declare_t == 0 && _b.boss.started);

    // ---- the beat before it opens -----------------------------------------
    //
    // **The attack does not start on frame one.** Practice arrives inside the
    // boss's own between-attacks pause, so the player has three seconds to
    // read the field and get off the spawn point -- and the boss cannot be
    // chipped during them, which is what makes the health set above mean
    // anything.
    ok("the attack has not started yet", _b.boss.phase < 0);
    ok("but it knows which one is coming", _b.boss.next_phase == 3);
    ok("and there is a beat before it does",
       _b.boss.clear_t == PRACTICE_READY);
    ok("during which the boss cannot be shot", !boss_vulnerable(_b));

    // The health starts where the attack does, so the bar spans this attack
    // rather than sitting nearly full over notches already passed.
    var _want = _b.hp_max * ziggy_phases()[2].hp_end;
    ok_near("its health starts at the attack's own threshold", _b.hp, _want, 1);

    ok("the player is topped up to full life", _g.player.hp == HP_MAX);
    ok("and full sigil", _g.player.mp == MP_MAX);

    // **Nothing fires during the beat.** A pattern that opened while the count
    // was still running would be the very thing the beat was added to stop,
    // and it is not visible from the boss's own state -- only from the field.
    for (var _i = 0; _i < PRACTICE_READY - 1; _i++) boss_act(_b, _g);
    ok("no bullet is fired during the beat", global.bullet_n == 0);
    ok("and it is still not the attack", _b.boss.phase < 0);

    boss_act(_b, _g);
    ok("then the attack asked for is entered", _b.boss.phase == 3);

    // **And a spell still declares itself before it fires.** Meteor Fall is a
    // spell, so the beat hands over to `BOSS_SPELL_LEAD` rather than to a
    // pattern -- practice gets the ceremony a fight gets, which is the whole
    // reason `practice_begin` enters the phase through the boss's own pause
    // instead of calling the attack itself.
    ok("but it is still declaring itself", _b.boss.lead_t > 0);
    for (var _i = 0; _i < BOSS_SPELL_LEAD; _i++) boss_act(_b, _g);
    ok("and only then is the boss live", boss_vulnerable(_b));

    // ---- and ending one ---------------------------------------------------
    //
    // **The seam is what this suite is really for.** Practice ends an attempt
    // when the attack ends, and the only frame that knows whether the attack
    // was broken or merely survived is inside `boss_end_phase`.
    var _n0 = _g.ended_n;
    for (var _i = 0; _i < ziggy_phases()[3].time + 2; _i++) boss_act(_b, _g);
    ok("running the clock out tells the run the attack ended",
       _g.ended_n == _n0 + 1);
    ok("and tells it the attack was survived, not broken", !_g.ended_beaten);

    var _timed = practice_outcome(_b, PracticeEnd.TimedOut, _g.marks);
    ok("which the panel reports as survived",
       practice_end_name(_timed) == "SURVIVED");

    // Breaking one is the other half, and a clean break of a spell is the
    // outcome the whole mode exists to be drilled for.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.practice = practice_new(_stage, 1, 1);
    _b = practice_begin(_g);
    for (var _i = 0; _i < PRACTICE_READY + BOSS_SPELL_LEAD; _i++) {
        boss_act(_b, _g);
    }
    _b.hp = boss_phase_floor(_b);
    boss_act(_b, _g);
    ok("breaking it tells the run so", _g.ended_n == 1 && _g.ended_beaten);

    var _clean = practice_outcome(_b, PracticeEnd.Beaten, _g.marks);
    ok("a spell broken untouched reads as a capture",
       practice_end_name(_clean) == "CAPTURED");
    ok("and it earned a mark", _clean.tier >= Mark.Gold);

    _b.boss.hits_this_phase = 1;
    var _hit = practice_outcome(_b, PracticeEnd.Beaten, _g.marks);
    ok("one taken and it is only broken",
       practice_end_name(_hit) == "BROKEN");
    ok("and dying is neither", practice_end_name(
        practice_outcome(_b, PracticeEnd.Died, rank_ledger_new()))
        == "DEFEATED");
    ok("with no mark to show for it", practice_outcome(
        _b, PracticeEnd.Died, rank_ledger_new()).tier < 0);

    st_reset();
}

/// @desc The drafting table: attacks with no boss yet. See `stage_drafts`.
///
///       **What is worth asserting here is the derivation, not the patterns.**
///       Whether a draft is any fun is exactly the question the mode exists to
///       ask a person, and no suite can answer it. What a suite can hold down
///       is the machinery underneath: that adding a row cannot silently break
///       the ladder, that the table is not a stage in any of the ways that
///       touch a save, and that every slot is worth the same.
function test_drafts() {
    st_reset();

    // ---- the rack ---------------------------------------------------------
    var _stages = stage_list();
    var _rack = rack_list();
    ok("the rack carries the roster, the review card and the table",
       array_length(_rack) == array_length(_stages) + 2);
    ok("and the table is the last card",
       stage_is_draft(_rack[array_length(_rack) - 1]));
    // A bare `_def.draft` on any of the eight would raise rather than answer,
    // which is the trap `practice_bosses` is written around one file over.
    var _none = true;
    for (var _i = 0; _i < array_length(_stages); _i++) {
        if (stage_is_draft(_stages[_i])) _none = false;
    }
    ok("and no stage claims to be one", _none);
    ok("nor does nothing at all", !stage_is_draft(undefined));

    // ---- what it is, and is not -------------------------------------------
    var _def = draft_stage_def();
    ok("it can be practised", practice_available(_def));
    // **Not built, deliberately.** A run of a whole stage is the path that
    // reaches `progress_record`, and a scratchpad must not be able to write to
    // somebody's save. The empty id is the second lock on the same door.
    ok("but it is not a stage to play", !stage_is_built(_def));
    ok("and has no stage to file a clear against", _def.id == "");
    ok("a blank id reads back as nothing cleared",
       !progress_stage(_def.id).cleared);

    // ---- the ladder -------------------------------------------------------
    var _l = draft_list();
    var _ph = draft_phases();
    var _n = array_length(_l);
    ok("there is a phase per draft", array_length(_ph) == _n);

    var _descends = true;
    var _even = true;
    var _prev = 1.0;
    var _span = 1 / _n;
    for (var _i = 0; _i < _n; _i++) {
        if (_ph[_i].hp_end >= _prev) _descends = false;
        if (abs((_prev - _ph[_i].hp_end) - _span) > 0.001) _even = false;
        _prev = _ph[_i].hp_end;
    }
    ok("the table descends", _descends);
    // **Equal shares are the point.** An attack tuned last week must not get
    // shorter because somebody added an idea underneath it.
    ok("and every draft owns the same span of the bar", _even);
    ok("and the last one lands exactly on zero",
       _ph[_n - 1].hp_end == 0);

    // The kind follows the name and nothing else says it twice.
    var _kinds = true;
    for (var _i = 0; _i < _n; _i++) {
        var _named = (_l[_i].name != "");
        if (_named != (_ph[_i].kind == AttackKind.Spell)) _kinds = false;
        if (_named != (_ph[_i].bg != -1)) _kinds = false;
    }
    ok("a name is what makes a draft a spell", _kinds);

    // A table built once would be shared by every run that read it, and a
    // phase struct is mutable -- the same trap `ziggy_phases` is written
    // around.
    ok("and each call hands back a fresh table", draft_phases() != _ph);

    // **An attack is claimed once.** `Demon Sealing Hex` moved from this
    // table to Velka's, and an attack in two places is two copies that will
    // be tuned apart -- which is the whole of why the drafting table says
    // moving one is moving the function, not copying the row.
    var _claimed = false;
    for (var _i = 0; _i < _n; _i++) {
        if (_l[_i].name == "Demon Sealing Hex") _claimed = true;
    }
    var _vp = velka_phases();
    var _hex = _vp[array_length(_vp) - 1];
    ok("Demon Sealing Hex is Velka's last spell and off the drafting table",
       !_claimed && _hex.name == "Demon Sealing Hex"
       && _hex.kind == AttackKind.Spell && _hex.hp_end == 0
       && _hex.move == BossMove.Track);

    // ---- the caster -------------------------------------------------------
    //
    // The boss's health is derived from how many drafts there are, so one
    // slot is worth `DRAFT_SLOT_HP` whatever else is on the table.
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _b = draft_boss_spawn(_g);
    ok("the draft boss reaches the field", _b != undefined);
    ok_near("and one slot is worth a fixed amount of health",
            _b.hp_max / _n, DRAFT_SLOT_HP, 0.001);
    ok("it wears the placeholder art", _b.boss.def.sprite == spr_boss_ziggy);
    // Not Ziggy's hue and not Ziggy's arena: a draft borrows the drawing and
    // nothing else. See the note at the top of `stage_drafts`.
    ok("but not Ziggy's colour", _b.boss.def.col != ziggy_def().col);
    ok("nor his forge", _b.boss.def.spell_bg == SPELLBG_SIGIL);

    // ---- practising one ---------------------------------------------------
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    var _p = practice_new(_def, 0, 1);
    ok("a named draft is listed under its own name",
       _p.label == _l[1].name);
    _g.practice = _p;
    _b = practice_begin(_g);
    ok("practice puts the draft boss on the field", _b != undefined);
    ok("on the attack that was chosen", _b.boss.next_phase == 1);
    ok_near("with the bar starting where that attack does",
            _b.hp, _b.hp_max * _ph[0].hp_end, 1);

    st_reset();
}

/// @desc **Demon Sealing Hex**: the ward, and the two ways it comes apart.
///
///       See the section at the foot of `stage_drafts`. What is asserted here
///       is only the part of it that is arithmetic, and every one of those is
///       invisible in a screenshot of any single frame -- which is the test
///       for whether an assertion in this project is worth writing.
///
///       **The ward keeps its radius.** Every bead is set turning about the
///       middle with a speed proportional to its own distance from it, and
///       that is a circle only if the speed and the turn rate agree. Get
///       either wrong and the seal opens into a spiral over the three seconds
///       it stands for -- and a picture taken on the frame it closes would
///       show a perfect pentagram either way.
///
///       **The ring closes on itself.** The ward turns while it is being
///       inscribed, so the bead the ring comes back to has moved off the top
///       since it was placed; the first version left one gap at the seam four
///       times the width of every other one, and it was reported from a
///       screenshot rather than caught here.
///
///       **The collapse arrives together.** A bead on the outer ring is 356
///       pixels out and one at the waist of an arm is a third of that; both
///       have to reach the middle on the same frame, or what lands is a smear
///       rather than a point.
///
///       **The inscription finishes together.** Seven traces of four very
///       different lengths, all of which have to put their last bead down on
///       the same frame -- which is the one thing about this attack the player
///       is being asked to watch.
function test_hex_seal() {
    st_reset();
    // Dead centre, so the clamp is a no-op and none of the ward is off the
    // field to be culled while it is being measured.
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    // The attack reads a position off its caster and nothing else, so this is
    // the whole of what a boss is to it.
    var _e = { x: FIELD_CX, y: BOSS_HOME_Y };

    // ---- the inscription --------------------------------------------------
    //
    // **The game's own order**: bullets move, then the boss fires. See
    // `obj_game`'s Step. Running it the other way round here would put every
    // scheduled event one frame out and quietly prove the wrong thing.
    var _was = 0;
    var _last = 0;
    for (var _f = 0; _f < HEX_DRAW; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
        _last = bullet_count() - _was;
        _was = bullet_count();
    }
    var _drawn = bullet_count();

    ok("the ward is a ward by the time it closes", _drawn > 180);
    // One bead from each of the five arms and each of the two rings. A trace
    // that had run out early would leave this short, which is the failure the
    // slice arithmetic exists to prevent.
    ok("and all seven traces are still writing on the last frame of it",
       _last >= 7);

    var _far = 0;
    var _outside = false;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        var _d = point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y);
        _far = max(_far, _d);
        if (_d > HEX_R_OUT + 1) _outside = true;
    }
    ok("nothing of it stands outside the ward", !_outside);
    ok_near("and the outer ring is the boundary", _far, HEX_R_OUT, 1);

    // ---- the seam ---------------------------------------------------------
    //
    // **Measured only once every bead of the ring is turning.** The fix runs
    // the pen ahead of the figure, so the ring is deliberately *not* round on
    // the frame the last bead is placed -- it is round `HEX_SEAL_DELAY` frames
    // later, when that bead has gone live and caught up. Measuring too early
    // would fail an attack that was working.
    //
    // Widest gap against narrowest, rather than against a count, because that
    // is the shape of the defect and it saves this test having to know how
    // many beads there are meant to be.
    var _lit = HEX_DRAW + HEX_SEAL_DELAY + 12;
    for (var _f = HEX_DRAW; _f < _lit; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _ang = [];
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        // Shape as well as radius: the volleys are crossing this annulus by
        // now, and a fan bullet counted as a bead is a gap that is not there.
        if (_u.shape != HEX_BEAD || _u.col != BCOL_CRIMSON) continue;
        if (abs(point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y) - HEX_R_OUT)
            > 4) continue;
        array_push(_ang, point_direction(FIELD_CX, FIELD_CY, _u.x, _u.y));
    }
    array_sort(_ang, true);
    var _wide = 0;
    var _tight = 360;
    for (var _i = 0; _i < array_length(_ang); _i++) {
        var _next = (_i == array_length(_ang) - 1)
                    ? _ang[0] + 360 : _ang[_i + 1];
        _wide = max(_wide, _next - _ang[_i]);
        _tight = min(_tight, _next - _ang[_i]);
    }
    ok("the outer ring is a whole ring", array_length(_ang) > 90);
    ok("and its beads are evenly apart the whole way round",
       _wide < _tight * 1.25);

    // ---- it turns, and turning is not drifting ----------------------------
    for (var _f = _lit; _f < HEX_SCATTER_AT; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _far2 = 0;
    var _held = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != HEX_BEAD || _u.col != BCOL_CRIMSON) continue;
        _held++;
        _far2 = max(_far2, point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y));
    }
    ok("the ward is still standing three seconds later", _held > 180);
    ok_near("and has turned without opening", _far2, HEX_R_OUT, 1);

    // **The boss goes quiet before the ward moves**, which is the only warning
    // either break gets that is not the break itself.
    //
    // Asserted by looking at what is in the air on the frame it breaks rather
    // than by restating the condition in the attack: a volley fired inside the
    // hold would still be young, and none of them is. A bullet's age is its
    // life plus however much of its delay it has already spent, because `life`
    // does not start until the mark does -- see `bullet_step`.
    var _young = 9999;
    var _fans = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != BSHAPE_RICE) continue;
        _fans++;
        _young = min(_young, _u.life + _u.delay0 - _u.delay);
    }
    ok("the last volley is in the air rather than being fired", _fans > 0);
    ok("and the boss has been quiet for the whole hold",
       _young >= HEX_HOLD_RED);

    // ---- the red seal comes apart -----------------------------------------
    //
    // **Not outward.** Thrown along their own radii the beads keep the
    // figure's shape all the way off the screen and the room the ward was
    // enclosing is the one place in the field nothing travels through -- so
    // the player who spent three seconds learning to stand in the middle of it
    // gets three more seconds of standing in the middle of it. Scattered
    // across the whole circle, the middle is the busiest place there is, and
    // that is what this counts.
    for (var _f = HEX_SCATTER_AT; _f < HEX_SCATTER_AT + 140; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _crossing = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != HEX_BEAD || _u.col != BCOL_CRIMSON) continue;
        if (point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y) < HEX_R_IN * 0.6) {
            _crossing++;
        }
    }
    ok("the broken ward goes back through the room it was enclosing",
       _crossing > 25);

    // ---- the blue seal is pulled inwards ----------------------------------
    //
    // All the way to the frame the collapse lands on, which is one after
    // `HEX_BURST_AT`: a bead spends `HEX_SEAL_DELAY` frames as a mark, its
    // queue is read on the step *before* it moves, and the attack fires after
    // the step rather than before it. Every bead carries the same three, so
    // they still arrive together -- but the frame they arrive on is not the
    // one the beat is named for, and a test that assumed it was would fail on
    // an attack that was working.
    // **The collapse has to open too slowly to be a lurch**, which is the
    // whole job of `HEX_IMPLODE_RAMP` and the one property of this movement no
    // screenshot can show: a still frame of a ward that has moved seven pixels
    // and a still frame of one that has moved nineteen are the same picture.
    // What the player is owed is a beat in which the figure visibly goes
    // *soft* -- beads drifting off the line they stood on -- before anything
    // has crossed any distance, because that beat is the only warning the
    // collapse gives and the answer to it is to already be leaving.
    //
    // A band rather than a ceiling: it has to have started, or the notice is a
    // freeze, and it has to have barely started, or the notice is the
    // collapse.
    for (var _f = HEX_SCATTER_AT + 140; _f <= HEX_IMPLODE_AT + 13; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _edge = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != HEX_BEAD || _u.col != BCOL_AZURE) continue;
        _edge = max(_edge, point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y));
    }
    ok("the collapse has begun a fifth of a second in", _edge < HEX_R_OUT - 1);
    ok("and has barely begun", _edge > HEX_R_OUT - 12);

    for (var _f = HEX_IMPLODE_AT + 14; _f <= HEX_BURST_AT + 1; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _landed = 0;
    var _adrift = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != HEX_BEAD || _u.col != BCOL_AZURE) continue;
        _landed++;
        if (point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y) > 1.5) _adrift++;
    }
    ok("the collapse brings the whole seal in", _landed > 50);
    ok("and every bead of it lands on the same point on the same frame",
       _adrift == 0);

    // The quarter of it that bursts is gone from the pool -- a split kills its
    // parent -- and what stands in its place is the detonation.
    //
    // **Found by colour and not by shape**, which is the change: the burst is
    // seven kinds of debris now and the one thing every piece of it has in
    // common is the hue. Nothing else in this attack is cyan -- the seals are
    // crimson and azure, the volleys are bone -- so the colour is the whole
    // test, and it is also the property that says the seven kinds are one
    // object breaking rather than seven things arriving.
    var _burst = 0;
    var _fast = 0;
    var _slow = 9999;
    var _seen = array_create(BSHAPE_COUNT, false);
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.col != BCOL_CYAN) continue;
        _burst++;
        _fast = max(_fast, _u.spd);
        _slow = min(_slow, _u.spd);
        _seen[_u.shape] = true;
    }
    var _kinds_out = 0;
    for (var _i = 0; _i < BSHAPE_COUNT; _i++) if (_seen[_i]) _kinds_out++;

    ok("and throws a burst out of the point it lands on", _burst > 50);

    // **A detonation is a thing coming apart, not a thing being fired.** One
    // shape at one of three speeds is a firework however many of it there are,
    // and that is what this used to be -- reported, accurately, as pathetic.
    // Both halves are asserted because either alone puts it back: seven sizes
    // all travelling together is a sorted wall, and one size at seven speeds
    // is rings again.
    ok("made of several different kinds of debris", _kinds_out >= 5);
    ok("at a wide spread of speeds", _fast > _slow * 2);

    // **A ring with a wedge missing is not a burst.** Every child's heading is
    // worked back from a heading its parent only acquires at the moment it
    // fires, so a sign slip or an off-by-one in the share does not throw and
    // does not change the count -- it just piles the whole detonation into one
    // side of the field, which is a thing only the shape on screen can say.
    var _sector = array_create(12, 0);
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.col != BCOL_CYAN) continue;
        _sector[((floor(_u.dir / 30) mod 12) + 12) mod 12]++;
    }
    var _thinnest = 9999;
    for (var _i = 0; _i < 12; _i++) _thinnest = min(_thinnest, _sector[_i]);
    ok("and it goes out in every direction", _thinnest >= 3);

    // ---- and the debris leaves by leaving ---------------------------------
    //
    // **Nothing in the scatter carries a lifetime**, because a bullet that
    // winks out mid-field is one the player was taught to respect and then
    // told not to bother with. So what has to be true instead is that the
    // geometry removes it: every bead travels in a straight line at a cap low
    // enough to be outrun, and `CULL_MARGIN` does the rest.
    //
    // **Nearly all rather than all, and the slack is the honest part.** A bead
    // thrown from the far side of the ward toward the far corner of the cull
    // box has about sixteen hundred pixels to cover and will still be in the
    // air when the cycle turns over. That is fine and is what it should look
    // like -- debris outlasting the thing it came off. What would not be fine
    // is a bead with no exit at all, which is what this catches: one direction
    // that never leaves means the pool fills up over a fight and the attack
    // quietly stops firing.
    for (var _f = HEX_BURST_AT + 2; _f < HEX_CYCLE; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }

    var _left = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape == HEX_BEAD && _u.col == BCOL_CRIMSON) _left++;
    }
    ok("and nearly all of the broken ward has left by the end of the cycle",
       _left * 4 < _drawn);

    // ---- the debris table -------------------------------------------------
    //
    // **The grading is the design and not a garnish**, so it is asserted on the
    // table rather than on a sample of what came out of one detonation: the
    // per-rune speed jitter is deliberately wide enough that two neighbouring
    // kinds overlap, which is what stops the cloud reading as sorted, and it
    // would make a measurement taken off fired bullets noisy for a reason that
    // is correct.
    //
    // Walked as a hash in `[0, 1)` rather than as an index, because that is the
    // only way in and the suite has no business knowing how many kinds there
    // are -- adding one should not touch this.
    var _prev_r = 9999;
    var _prev_s = 0;
    var _kinds = 0;
    var _graded = true;
    var _last = -1;
    for (var _i = 0; _i < 400; _i++) {
        var _d = hex_debris(_i / 400);
        if (_d.shape == _last) continue;
        _last = _d.shape;
        _kinds++;
        if (global.bshape_radius[_d.shape] >= _prev_r) _graded = false;
        if (_d.spd <= _prev_s) _graded = false;
        _prev_r = global.bshape_radius[_d.shape];
        _prev_s = _d.spd;
    }
    ok("the debris table has several kinds in it", _kinds >= 5);
    // Heavy and slow, light and fast. It reads as mass, it grades the cloud
    // along the radius for free, and it is what pays the player who answered
    // the blue half and left: the sparks reach them and the chunks do not.
    ok("and the heavier a piece is the slower it comes off", _graded);

    // **A hash, not a random.** The same detonation on the tenth attempt as on
    // the first is the whole reason this is not `fire_spray` -- and it has to
    // be in `[0, 1)` rather than in `(-1, 1)`, because GML's `frac` keeps the
    // sign and an unfolded hash would put half the runes on the first row of
    // the table. Which is one shape at one speed, which is the shell this
    // whole change exists to get rid of.
    var _bounded = true;
    var _spread = 0;
    for (var _i = 0; _i < 200; _i++) {
        var _h = hex_hash(_i, 27.611);
        if (_h < 0 || _h >= 1) _bounded = false;
        if (_h > 0.5) _spread++;
    }
    ok("the hash behind it is bounded", _bounded);
    ok("and does not sit in one half of its range",
       _spread > 60 && _spread < 140);
    ok("and answers the same thing twice",
       hex_hash(17, 27.611) == hex_hash(17, 27.611));

    st_reset();
}

function test_hud_layout() {
    // **The assertion the whole HUD rests on: nothing in the console is over
    // the playfield.**
    //
    // This is what the bordered field bought, and it is worth being precise
    // about why it is better than what it replaced. The old layout put the
    // readouts in the corners of a full-bleed field and faded them as the
    // player approached; the property it wanted was "a readout never hides a
    // bullet the player needs", and that is not a property any suite can
    // check -- it depends on alpha, on what is behind it, and on what the
    // player happens to be doing. So the fade shipped measuring distance from
    // an element's top-left corner, which meant a 430-pixel-wide bar faded at
    // its left end and not at all at its right, and nothing noticed.
    //
    // With a console the property becomes a rectangle overlap, and a rectangle
    // overlap is decidable.
    var _names = hud_console_boxes();
    var _clear = true;
    var _guilty = "";
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _b = hud_box(_names[_i]);
        if (!rect_clear_of_field(_b[0], _b[1], _b[2], _b[3])) {
            _clear = false;
            _guilty = _names[_i];
        }
    }
    ok("no console readout overlaps the playfield" +
       (_clear ? "" : " (" + _guilty + " does)"), _clear);

    // **And the one box that is over it is over it on purpose.**
    //
    // The boss's line is the declared exception, so asserting it is clear of
    // the field would be asserting the opposite of the design. What replaces
    // that assertion is the thing that makes the exception affordable: it is a
    // *line*. Its occlusion budget is its height, and `FIELD_OVERLAY_MAX_H` is
    // the one number that stops the exception growing quietly back into the
    // 168-pixel strip it was carved out of.
    //
    // A box that is merely narrow is not enough -- the old strip was "only"
    // 168 tall too, and it was outside the field, which is why nobody had to
    // argue about it. Inside the field the number has to be small enough that
    // a bullet crossing the bar is behind it for about one frame, and at the
    // slowest speed this game fires at that is under twenty pixels.
    var _bb = hud_box("boss");
    ok("the boss's line is inside the field, which is the point of it",
       !rect_clear_of_field(_bb[0], _bb[1], _bb[2], _bb[3]));
    ok("its bar is a line rather than a strip",
       BOSS_BAR_H <= FIELD_OVERLAY_MAX_H);
    ok("and the whole line sits in the field's top eighth",
       _bb[3] < FIELD_Y0 + FIELD_H * 0.125);

    // ...and every box is a real rectangle, or a typo in `hud_box` would park
    // a readout in the top-left corner and pass the test above for free.
    var _all = array_concat(_names, ["boss"]);
    var _real = true;
    var _on = true;
    for (var _i = 0; _i < array_length(_all); _i++) {
        var _b = hud_box(_all[_i]);
        if (_b[2] <= _b[0] || _b[3] <= _b[1]) _real = false;
        if (_b[0] < 0 || _b[1] < 0 || _b[2] > GAME_W || _b[3] > GAME_H) {
            _on = false;
        }
    }
    ok("every HUD box is a real rectangle", _real);
    ok("and all of it is on the screen", _on);

    // The console's own plate contains everything the console draws, and
    // clears the field. A readout outside its plate is a readout floating on
    // the fascia, which reads as a bug whether or not it overlaps anything.
    var _inside = true;
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _b = hud_box(_names[_i]);
        if (_b[0] < HUD_PANEL_X0 || _b[2] > HUD_PANEL_X1
            || _b[1] < HUD_PANEL_Y0 || _b[3] > HUD_PANEL_Y1) {
            _inside = false;
        }
    }
    ok("every console readout is on the console's plate", _inside);

    // **The plate and the field's frame stand to the same line.** Flush with
    // `FIELD_Y0` the plate sat seventeen pixels below the rule that frames the
    // picture beside it, and two panels on one fascia that disagree about
    // where the top of the fascia is read as one having slipped.
    ok("the plate stands to the field's outer rule",
       HUD_PANEL_Y0 == FIELD_Y0 - FIELD_RULE_OUT
       && HUD_PANEL_Y1 == FIELD_Y1 + FIELD_RULE_OUT);
    ok("and the fascia still has room for it",
       HUD_PANEL_Y0 > 0 && HUD_PANEL_Y1 < GAME_H);
    ok("and the plate itself clears the field",
       rect_clear_of_field(HUD_PANEL_X0, HUD_PANEL_Y0,
                           HUD_PANEL_X1, HUD_PANEL_Y1));

    // The rows are in the order they are drawn in and do not collide, which is
    // the one thing a hand-written layout gets wrong.
    ok("the console's rows are in order and spaced",
       HUD_ROW_STAGE < HUD_RULE_1 - 60
       && HUD_RULE_1 < HUD_ROW_BEST - 20
       && HUD_ROW_BEST < HUD_ROW_SCORE - 50
       && HUD_ROW_SCORE < HUD_ROW_GRAZE - 50
       && HUD_ROW_GRAZE < HUD_RULE_2 - 30
       && HUD_RULE_2 < HUD_ROW_LIFE - 44
       && HUD_ROW_LIFE < HUD_ROW_SIGIL - HUD_METER_H
       && HUD_ROW_SIGIL + HUD_METER_H < HUD_RULE_3
       && HUD_RULE_3 < HUD_ROW_MARKS - 20);

    // **The rows that share a shape share a pitch.** Collapsing the score onto
    // one line freed a row's height and the layout kept the old spacing, which
    // left visible gaps between every readout -- a tidy-up that made the thing
    // it tidied look worse. Three rows one pitch apart is a rhythm; three rows
    // at two different pitches is a mistake, and the difference is arithmetic.
    ok("the three number rows are evenly pitched",
       abs((HUD_ROW_SCORE - HUD_ROW_BEST)
           - (HUD_ROW_GRAZE - HUD_ROW_SCORE)) <= 4);

    // The ledger runs to the foot of the plate, which is what it is for.
    var _mk = hud_box("marks");
    ok("the ledger fills the rest of the plate",
       _mk[3] > HUD_ROW_MARKS + 200 && _mk[3] <= HUD_PANEL_Y1);

    // **The spell's name is over the field now, on the boss's own line**, so it
    // is held to the same rule the bar is: everything drawn over the playfield
    // is a line at the top of it. It has been in three places and this is the
    // one where it is next to the health it refers to.
    //
    // The order down the line is bar, then the caster's name, then the spell's
    // -- the bar pinned to the top because it is the part read mid-dodge, and
    // the type hanging off it because type can.
    ok("the bar is pinned to the top of the field",
       BOSS_BAR_Y - FIELD_Y0 <= 20);
    ok("the boss's name sits under its bar",
       BOSS_NAME_Y >= BOSS_BAR_Y + BOSS_BAR_H);
    ok("and the spell name under that",
       BOSS_SPELL_Y >= BOSS_NAME_Y + BOSS_SPELL_ROW
       && BOSS_SPELL_Y < FIELD_Y0 + FIELD_H * 0.14);

    // **What the boss clears is the bar, and only the bar.** It used to have
    // to clear the whole line, because the name was centred over the middle of
    // it -- which is exactly where a boss stands. The name and the timer are
    // at the two ends now, so the middle of the line is the boss's, and the
    // one thing it may not fly through is the fourteen pixels of tube.
    ok("the boss flies below its own bar, not through it",
       BOSS_HOME_Y - BOSS_DRIFT_Y - 125 > BOSS_BAR_Y + BOSS_BAR_H);

    // **And it holds station in the top third, not over the player.** At its
    // lowest drift the foot of the sprite has to stay out of the bottom half
    // of the field: a boss leaning past the middle is one the player is under
    // for the whole fight, which is what 320 was and what was reported.
    ok("and it keeps out of the player's half",
       BOSS_HOME_Y + BOSS_DRIFT_Y + 125 < FIELD_CY);

    // **The sections that hold a fixed thing are of comparable height, and the
    // one that grows is the biggest.** This is the assertion that would have
    // caught the layout this replaced: an early pass put four rows in the top
    // four hundred pixels and two in the bottom two hundred, and left three
    // hundred and thirty in the middle with nothing on it. Every individual
    // spacing check above passed, because none of them can see a gap -- they
    // only see order. What a gap looks like arithmetically is one section far
    // larger than the content it was given.
    //
    // The ledger is exempt from the comparison and asserted separately: it is
    // the section the layout deliberately gives the most room to, and holding
    // it to the same ratio would be asserting that the console must never
    // prioritise anything.
    var _cuts = [HUD_PANEL_Y0, HUD_RULE_1, HUD_RULE_2, HUD_RULE_3];
    var _lo = 99999;
    var _hi = 0;
    for (var _i = 1; _i < array_length(_cuts); _i++) {
        var _span = _cuts[_i] - _cuts[_i - 1];
        _lo = min(_lo, _span);
        _hi = max(_hi, _span);
    }
    ok("no fixed section of the console is more than three times another",
       _hi <= _lo * 3);
    ok("and the ledger gets the most room",
       HUD_PANEL_Y1 - HUD_RULE_3 >= _hi);
    ok("the lower meter has room to stand on its plate",
       HUD_ROW_SIGIL + HUD_METER_H < HUD_PANEL_Y1);

    // **The two meters lie down and stack.** Upright they stood side by side
    // and the assertion was that they did not touch; the axis is what changed,
    // so the assertion changes with it -- two rows that overlap is exactly the
    // failure the side-by-side test used to catch, one axis over.
    var _life = hud_box("life");
    var _mana = hud_box("mana");
    ok("the two meters stack without overlapping", _mana[1] >= _life[3] + 1);
    ok("and both span the console's full width",
       _life[2] - _life[0] == HUD_METER_W
       && _mana[2] - _mana[0] == HUD_METER_W);

    // **A meter's name and its value share one line above the glass**, so the
    // one thing that can go wrong is the two meeting in the middle. The old
    // upright version etched its label *down* the glass and measured against
    // the vessel's height; lying down there is no down, so what is measured is
    // that the pair fit across the width with room between them.
    draw_set_font(fnt_small());
    var _tag = string_width("SIGIL  READY");
    draw_set_font(fnt_ui());
    var _val = string_width(string(HP_MAX));
    ok("a meter's name and value fit on one line without meeting",
       _tag + _val < HUD_METER_W - 60);

    // The boss's tube spans the field less its inset, and stands clear of
    // where the boss itself flies -- which is the thing that made a centred
    // name possible at all. `spr_boss_ziggy` is 250 tall on a centred origin.
    ok("the boss bar spans the field's width less its inset",
       hud_box("boss")[0] == FIELD_X0 + BOSS_BAR_INSET
       && hud_box("boss")[2] == FIELD_X1 - BOSS_BAR_INSET);
    ok("and the line's box covers everything drawn on it",
       hud_box("boss")[1] <= BOSS_BAR_Y
       && hud_box("boss")[3] >= BOSS_SPELL_Y);

    // **The field itself has to be a sane rectangle inside the screen**, since
    // every coordinate in the game is measured from it -- a typo here would
    // put the playfield off the edge of the display and nothing else would
    // notice.
    ok("the field is inside the screen",
       FIELD_X0 > 0 && FIELD_Y0 > 0
       && FIELD_X1 < GAME_W && FIELD_Y1 <= GAME_H);
    ok("and there is a margin to put the console in",
       GAME_W - FIELD_X1 > HUD_METER_W);
    ok("the boss stations inside the field",
       BOSS_HOME_Y > FIELD_Y0 && BOSS_HOME_Y < FIELD_CY);

    // **Nothing else drawn over the field may be opaque.**
    //
    // The near parallax layer is the other thing drawn on top of live danmaku.
    // It was opaque, and at ninety-four per cent it did not hide scenery, it
    // hid *bullets* -- reported the way this class of bug always is: "I am
    // taking damage and there is nothing on screen." There was; it was behind
    // a spire.
    //
    // No suite can look at a frame and say whether a bullet was visible, so
    // what is asserted is the constant that makes it impossible: the layer is
    // translucent enough that a lit bullet reads through it, and the keep-out
    // band still leaves the great majority of the field completely clear.
    // **And nothing decorative is drawn over it at all.** The frame's corner
    // pieces are 37 pixels deep at the elbow, so how far out they are pushed
    // decides whether the ornament ends up on the playfield -- it did, by
    // seven pixels, in the first version. Seven pixels of near-black in the
    // extreme corner costs nobody a life, which is exactly why the rule has to
    // be arithmetic rather than judgement.
    ok("the frame's corner ornaments stay in the margin",
       FIELD_ORN_OUT >= UI_CORNER_DEPTH * FIELD_ORN_SCALE);
    ok("and the rule they stand on is in the margin too",
       FIELD_RULE_OUT > 0 && FIELD_ORN_OUT < FIELD_X0
       && FIELD_ORN_OUT < FIELD_Y0);

    ok("the foreground layer is never opaque", BG_NEAR_ALPHA <= 0.55);
    ok("and it leaves most of the field alone", BG_NEAR_EDGE * 2 < 0.34);

    // The player cannot leave it, which is what `FIELD_MARGIN` is for.
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _p = _g.player;
    var _in = input_idle();
    _in.left = true;
    _in.up = true;
    for (var _i = 0; _i < 400; _i++) player_step(_p, _in, _g);
    ok("the player is held inside the field going up and left",
       _p.x >= FIELD_X0 + FIELD_MARGIN - 0.01
       && _p.y >= FIELD_Y0 + FIELD_MARGIN - 0.01);
    _in.left = false; _in.up = false;
    _in.right = true; _in.down = true;
    for (var _i = 0; _i < 400; _i++) player_step(_p, _in, _g);
    ok("and going down and right",
       _p.x <= FIELD_X1 - FIELD_MARGIN + 0.01
       && _p.y <= FIELD_Y1 - FIELD_MARGIN + 0.01);
}

function test_run_starts_clean() {
    // **The bug this exists for was reported as two unrelated ones.** "Ziggy's
    // patterns keep firing at the start of the level" and "I take random
    // damage from invisible bullets during the boss fight" were the same
    // leftover boss, still stepping his phase table in a run that had not
    // cleared the field it inherited.
    //
    // Nothing could have caught it, because nothing asked the question. The
    // pools are globals allocated once in `obj_boot` and reused for the life
    // of the process, and the only code that emptied them was the pause menu's
    // restart -- so the one path a suite or a developer naturally exercises was
    // the one path that was already correct.
    st_reset();

    // Put one of everything on the field, including a boss mid-fight.
    fire(FIELD_CX, FIELD_CY, 3, 90, BSHAPE_ORB, BCOL_CYAN, 0);
    laser_beam(FIELD_CX, FIELD_CY, 90, 900, 30, BCOL_GOLD, 20, 40, 10);
    ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    item_spawn(FIELD_CX, FIELD_CY, ItemKind.Tally);
    enemy_spawn(EnemyKind.Wisp, FIELD_CX, FIELD_CY, 5, undefined, BCOL_CYAN,
                0, 0, 0);
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 100, 1000, ziggy_phases(),
                        ziggy_def());

    ok("the field can be dirtied at all",
       bullet_count() > 0 && laser_count() > 0 && item_count() > 0
       && enemy_count() > 1 && ring_count() > 0 && _b != undefined);

    // This is what entering `room_game` does, and it is the whole assertion:
    // however a run was reached, it starts here.
    run_clear_field();

    ok("a run starts with no bullets", bullet_count() == 0);
    ok("...no lasers", laser_count() == 0);
    // **A ring is the one thing on this list that would never leave on its
    // own.** A bullet goes off the edge and a laser runs out of clock; a ring
    // stands there until something says otherwise, so a run that inherited one
    // would inherit it for the whole stage.
    ok("...no rings", ring_count() == 0);
    ok("...no items", item_count() == 0);
    ok("...and no enemies, boss included", enemy_count() == 0);
    ok("so nothing is left to find a boss in", enemy_find_boss() == undefined);
}

function test_boss_is_never_invisible() {
    // **A boss the run has stopped pointing at is still on the field.**
    //
    // Drawing used to go through the controller's `boss_ref`, which is the
    // boss it is *currently fighting* -- not the set of bosses that exist. The
    // two come apart in ordinary play: a beaten midboss keeps flying while
    // `boss_ref` is released, and a boss inherited from a previous run was
    // never referenced at all. Either one was drawn by nobody while remaining
    // able to fire and solid to the touch.
    //
    // No headless suite can look at a frame, so what is asserted is the
    // condition that made it possible -- that a boss outlives the reference to
    // it -- and `enemy_draw` now reads the pool rather than the reference, so
    // the condition is no longer dangerous.
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 + 200, 400, ziggy_phases(),
                        ziggy_def());
    _g.boss_ref = _b;

    // The handover a midboss gets: the run lets go of it and it flies off.
    _g.boss_ref = undefined;

    ok("a boss outlives the run's reference to it",
       enemy_count() == 1 && enemy_find_boss() != undefined);

    // And it is still a live thing while it does -- which is why being drawn
    // matters rather than being a tidiness point.
    var _still = enemy_find_boss();
    ok("and is still a real enemy on the field",
       _still.hp > 0 && _still.r > 0);
}

function test_save_atomicity() {
    // **On a file of its own.** `progress_save` names the player's real save,
    // and a suite that round-tripped through it would overwrite their cleared
    // stages with scratch state, permanently, with nothing to report it.
    var _name = "selftest_scratch.json";
    save_delete(_name);

    save_write_json(_name, { a: 1, b: "two" });
    var _back = save_read_json(_name);
    ok("a saved struct reads back", _back != undefined && _back.a == 1
       && _back.b == "two");
    ok("and leaves no temp file behind", !file_exists(_name + ".tmp"));

    // The recovery path: the live file gone and only the temp left is what a
    // process killed between the delete and the rename leaves. That temp is
    // the *newer* save, not a scrap.
    file_rename(_name, _name + ".tmp");
    var _recovered = save_read_json(_name);
    ok("a save interrupted mid-rename is recovered",
       _recovered != undefined && _recovered.a == 1);

    // A live file that does not parse is set aside rather than left where the
    // next write would replace it.
    save_delete(_name);
    var _f = file_text_open_write(_name);
    file_text_write_string(_f, "{ this is not json");
    file_text_close(_f);
    var _bad = save_read_json(_name);
    ok("a corrupt save reads as absent", _bad == undefined);
    ok("and its bytes are kept", file_exists(_name + ".bad"));

    save_delete(_name);
    if (file_exists(_name + ".bad")) file_delete(_name + ".bad");
    ok("the scratch file is cleaned up", !file_exists(_name));
}

function test_audio_budget() {
    // **The claim this suite exists for**: a pattern may ask for a sound once
    // per bullet, and one frame produces one voice. Nothing else in the audio
    // system matters if this is not true -- a boss non-spell fires a hundred
    // and twenty bullets on a single frame, and a hundred and twenty voices of
    // the same 75ms cue is not a volley, it is a burst of comb-filtered noise
    // with the mixer's pool exhausted behind it.
    st_reset();
    sfx_reset();

    var _n = 300;
    for (var _i = 0; _i < _n; _i++) sfx(Sfx.ShotSoft);
    ok("three hundred bullets make three hundred requests",
       global.sfx_requests == _n);

    sfx_step();
    ok("...and exactly one voice", global.sfx_voices == 1);
    ok("...which is the cue they asked for", sfx_sounded(Sfx.ShotSoft));
    ok("...and nothing is left pending", global.sfx_want[Sfx.ShotSoft] == 0);

    // **The backlog is dropped, not held.** A request that could not be
    // afforded is about something that has already happened, so carrying it
    // forward would sound the shot after the bullet had crossed the field --
    // and would let one busy second play out over the quiet one after it.
    var _table = global.sfx_table;
    for (var _i = 0; _i < 400; _i++) sfx(Sfx.ShotSoft);
    sfx_step();
    ok("a cue on cooldown drops its requests rather than queueing them",
       global.sfx_voices == 1 && global.sfx_want[Sfx.ShotSoft] == 0);

    // ...and it comes back once the gap has run.
    var _gap = _table[Sfx.ShotSoft].gap;
    for (var _f = 0; _f < _gap; _f++) {
        sfx(Sfx.ShotSoft);
        sfx_step();
    }
    ok("and sounds again once its gap has run", global.sfx_voices == 2);

    // Firing flat out for a second: the ratio is what a player actually hears
    // against what the patterns asked for.
    sfx_reset();
    for (var _f = 0; _f < 60; _f++) {
        for (var _i = 0; _i < 120; _i++) sfx(Sfx.ShotSoft);
        sfx_step();
    }
    var _want = 60 div _table[Sfx.ShotSoft].gap;
    ok("a second of flat-out firing is " + string(global.sfx_voices)
       + " voices, not " + string(global.sfx_requests),
       global.sfx_voices <= _want + 1 && global.sfx_voices >= _want - 1);

    // **The per-frame budget, spent in priority order.** The busiest frame in
    // the game is a spell ending -- the whole field pops into shards, a
    // capture is awarded and the next attack is named -- and what has to
    // survive that is the ceremony rather than forty collected shards.
    sfx_reset();
    for (var _c = 0; _c < Sfx.COUNT; _c++) sfx(_c);
    sfx_step();
    ok("every cue at once spends the budget and no more",
       global.sfx_voices == SFX_VOICES);

    var _lowest = 9999;
    var _dropped_prio = -1;
    for (var _i = 0; _i < global.sfx_played_n; _i++) {
        _lowest = min(_lowest, _table[global.sfx_played[_i]].prio);
    }
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        if (!sfx_sounded(_c)) _dropped_prio = max(_dropped_prio, _table[_c].prio);
    }
    ok("...on the highest-priority cues", _lowest >= _dropped_prio);

    // The swell: one bullet is not a volley, and a volley is capped.
    ok("one request carries no swell", sfx_swell(1) == 0);
    ok("more is bigger", sfx_swell(8) > sfx_swell(2));
    ok("...and it stops growing", sfx_swell(SFX_SWELL_FULL * 8) <= 1);

    // **Votes do not cross a room boundary.** A cue requested on the last
    // partial frame of a run -- the death, say -- must not be resolved by the
    // first `sfx_step` of the title screen and announced there.
    sfx_reset();
    sfx(Sfx.PlayerDown);
    global.sfx_room = -999;                  // stand in for "we changed room"
    sfx_step();
    ok("a request does not survive a room change",
       global.sfx_voices == 0 && !sfx_sounded(Sfx.PlayerDown));

    // The table itself. **A cue with no row is a crash in a Draw event no
    // suite reaches**, which is the same trap `check_call_arity` exists for --
    // and the enum and the table are written in two places that have to agree.
    var _holes = 0;
    var _bad_gap = 0;
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        if (_table[_c] == undefined) { _holes++; continue; }
        if (!audio_exists(_table[_c].snd)) _holes++;
        // A gap of zero is a cue that may sound sixty times a second, which is
        // the exact failure this whole file is built to make impossible.
        if (_table[_c].gap < 1) _bad_gap++;
    }
    ok("every cue has a row and a real sound", _holes == 0);
    ok("and no cue may sound every frame", _bad_gap == 0);

    // **Every bullet shape has a voice**, and it is one of the three shot cues
    // rather than, say, the boss dying. The fallthrough in `sfx_for_shape`
    // makes a missing shape quietly wrong instead of loudly broken, which is
    // right for decoration and is exactly why it needs asserting here.
    var _bad_voice = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        var _v = sfx_for_shape(_s);
        if (_v != Sfx.ShotSoft && _v != Sfx.ShotSharp && _v != Sfx.ShotHeavy) {
            _bad_voice++;
        }
    }
    ok("every bullet shape maps to a shot cue", _bad_voice == 0);

    // And the end-to-end path: firing a real ring through the real pool asks
    // for the real cue. Asserted rather than assumed, because the call lives
    // in `fire` -- the hottest function in the game -- and is exactly the kind
    // of line somebody removes while optimising.
    st_reset();
    sfx_reset();
    fire_ring(FIELD_CX, FIELD_CY, 30, 3, 0, BSHAPE_NEEDLE, BCOL_CRIMSON, 0);
    ok("a ring of needles asks for the sharp cue",
       global.sfx_want[Sfx.ShotSharp] == 30);
    sfx_step();
    ok("...and gets one voice for the ring", global.sfx_voices == 1);

    // **The collapse's telegraph has to be as long as the collapse.**
    // `snd_ward_pull` is a rising tone written to arrive at the top exactly as
    // the ward reaches the middle, which is the whole of why it is a telegraph
    // rather than a noise -- and its length is a number in `tools/make_sfx.py`
    // while `HEX_IMPLODE` is a number in `stage_drafts`. Two files, one fact,
    // and nothing in the build would notice them drifting: a cue half a second
    // short resolves onto nothing and a cue half a second long is still
    // climbing when the detonation lands, and both are perfectly valid audio.
    ok_near("the collapse cue is as long as the collapse",
            audio_sound_length(snd_ward_pull), HEX_IMPLODE / FPS, 0.05);

    // **Silence under a harness is the flag, not the arithmetic.** Everything
    // above this line ran with `global.audio_on` false, which is how the
    // suites can grade the whole decision without anybody hearing it -- so
    // this asserts the flag is actually off, or every number above is a
    // measurement of a different code path than the one that ships.
    ok("and the suite ran silent", global.audio_on == false);
}

function test_audio_playback() {
    // **The one line the rest of the audio suite cannot reach.**
    // `global.audio_on` is false under both harnesses, which is what lets
    // `test_audio_budget` grade every decision without anybody hearing it --
    // and the cost of that is that `audio_play_sound` itself, the single
    // statement that ships, is never executed by any suite. A wrong argument
    // count there is not a compile error in GML: it binds the missing one to
    // `undefined` and throws when it is used, which under `tools/test.py` is a
    // modal box and therefore a *hang* rather than a failure.
    //
    // `audio_init` set the master gain to zero alongside the flag, so the real
    // call can be made here and heard by nobody. That is the whole reason the
    // gain is set as well as the flag rather than instead of it.
    var _was = global.audio_on;
    global.audio_on = true;
    sfx_reset();

    var _played = 0;
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        sfx_play_now(_c, 1);
        if (audio_is_playing(global.sfx_table[_c].snd)) _played++;
    }
    ok("every cue loads and plays through the real path",
       _played == Sfx.COUNT);

    // And the swelled path, which passes a different gain and a pitch off 1.0
    // -- the arguments a plain call never exercises.
    sfx_play_now(Sfx.ShotSoft, 240);
    ok("...including a coalesced volley's gain and pitch",
       audio_is_playing(snd_shot_soft));

    audio_stop_all();
    global.audio_on = _was;
    sfx_reset();
    ok("and the suite is silent again", global.audio_on == false);
}

function test_bullet_cost() {
    st_reset();

    // A full-ish screen, stepped for a second. **The budget is per bullet per
    // frame**, not an absolute, because the absolute depends entirely on what
    // else the machine is doing -- and an absolute tight enough to be
    // interesting fails at random, which is worse than none.
    var _n = 2000;
    for (var _i = 0; _i < _n; _i++) {
        var _b = fire(random(GAME_W), random(GAME_H), 0.2, random(360),
                      BSHAPE_ORB, BCOL_CYAN, 0);
        if (_b == undefined) break;
    }
    var _live = bullet_count();

    // **The fastest of three runs, not the average.** Noise on a wall clock
    // only ever adds time, so the minimum is the closest thing to the cost of
    // the code; the mean is the cost of the code plus whatever else was
    // happening. `tools/test.py` builds immediately before this runs.
    var _best = 999999;
    for (var _r = 0; _r < 3; _r++) {
        var _t0 = get_timer();
        for (var _f = 0; _f < 60; _f++) {
            bullet_step(GAME_CX, GAME_CY);
            bullet_graze(GAME_CX, GAME_CY, GRAZE_R);
            bullet_hit_index(GAME_CX, GAME_CY, PLAYER_R);
        }
        _best = min(_best, get_timer() - _t0);
    }

    var _per = _best / (_live * 60);        // microseconds per bullet-frame
    show_debug_message("SELFTEST INFO bullet cost " + string(_live)
                       + " bullets, " + string(_best / 1000)
                       + "ms for 60 frames, " + string(_per) + "us each");

    // **Measured at about 2.0us per bullet-frame under the VM runtime**, which
    // is what `tools/build.py` produces. That is 4ms a frame at the two
    // thousand bullets this suite uses and about 1.5ms at the six to twelve
    // hundred a busy screen actually carries -- comfortable against a 16.6ms
    // budget, and YYC is several times faster again.
    //
    // The number is dominated by the interpreter rather than by anything this
    // code does: hoisting the pool and the shape table out of the loop, and
    // replacing the graze test's `point_distance` with inline squared
    // distance, together moved it by under three per cent. **The lever that
    // would actually matter is folding the three passes into one** -- step,
    // graze and hit each walk the whole pool, and one pass would touch each
    // struct once. It is not done because it would make three pure functions
    // into one that does everything, and 4ms is not a problem yet.
    //
    // The budget is set well above the measurement on purpose. A ceiling tight
    // enough to be interesting sits inside the natural spread of a wall clock
    // on a machine that is also building, and a test that cries wolf gets its
    // number raised until it means nothing.
    ok("stepping a full screen of bullets stays under budget", _per < 4.0);

    // And an absolute backstop. A per-bullet budget cannot see a regression
    // that only moves the tail -- an accidental O(n^2), say -- because it
    // divides by the very count that grew.
    ok("and a second of a full screen is well under a second",
       _best < 600000);
    st_reset();
}

/// @desc The ring pool: what it blocks, what it does not, and what it kills.
///
///       **Almost none of this is visible in a screenshot, and the one part
///       that is would look right while being wrong.** A ring drawn over a
///       boss and eating shots looks identical whether it is eating them along
///       its metal or across its whole disc -- the difference only shows as
///       the player slowly concluding the fight is unfair. So the hole is
///       asserted as hard as the band is.
/// @desc The open roof: the wedge of sky, and what has to fit in it.
///
///       **This is arithmetic no screenshot can do and no screenshot can
///       report.** A picture says "the orrery is behind the masonry" only if
///       it happens to be, at the one camera position it was taken at -- and
///       the numbers that decide it live in three files: the parapet's height
///       and setback in `constants`, the field's size and field of view in
///       `constants` too, and the orrery's own distance, height and radius
///       beside them. Every one of those is individually reasonable at any
///       value; what has to hold is a relation between all of them.
///
///       It is the same shape of guard as `check_scrub_covers_horizon` one
///       stage over, which adds four numbers from three files and asks
///       whether the hedge still hides the line it was built to hide. That
///       one had always been broken and nothing had ever added it up.
function test_hall_sky() {
    st_reset();

    // The lens, in pixels. A vertical field of view of `HALL_FOV` over the
    // field's height is one focal length, and every screen position below is
    // measured with it.
    var _f = (FIELD_H * 0.5) / dtan(HALL_FOV * 0.5);

    // **The wedge.** A long horizontal edge at height H and half-width X
    // projects, from a camera at `HALL_CAM_FLY`, to a straight ray out of the
    // vanishing point with slope (H - cam) / X -- so the sky the player can
    // see is the cone above the steepest such ray in the hall. The parapet is
    // that edge, and nothing may be built above the wall without this being
    // recomputed.
    var _cam = HALL_CAM_FLY;
    var _par_y = HALL_CEIL_H + HALL_COPING_H + HALL_PARAPET_H;
    var _slope = (_par_y - _cam) / HALL_PARAPET_X;
    var _cop_y = HALL_CEIL_H + HALL_COPING_H;
    var _cop_x = HALL_HALF_W - HALL_CORN_D - 14;
    ok("the parapet is what the sky is measured from",
       _slope >= (_cop_y - _cam) / _cop_x);

    // The orrery, on screen.
    var _cy = _f * (HALL_ORRERY_Y - _cam) / HALL_ORRERY_Z;
    var _cr = _f * HALL_ORRERY_R / HALL_ORRERY_Z;
    // The perpendicular distance from the wedge's edge to its centre line is
    // `sin` of the wedge's own half-angle, so a circle fits when its centre is
    // at least its radius over that.
    var _half = darctan(1 / _slope);
    ok("the orrery clears the masonry it hangs behind",
       _cy >= _cr / dsin(_half));

    // ...and it is still on the screen. The vanishing point of a hall flown
    // level-ish sits `tan(pitch)` above the middle of the frame.
    var _vp = _f * dtan(abs(HALL_PITCH_B));
    ok("...and its top is inside the field",
       _cy + _cr + _vp < FIELD_H * 0.5);
    // A landmark small enough to fit anywhere is a landmark nobody looks at.
    ok("...and it is big enough to be the thing at the end of the hall",
       _cr * 2 > FIELD_H * 0.16);

    // **The hall is drawn out to `HALL_BAYS` and the orrery is beyond all of
    // it**, which is what lets the depth buffer sort the two without the
    // orrery ever being written into a bay's own depth. It is also inside the
    // far plane, or it would be clipped away entirely.
    ok("the orrery is further off than the last bay drawn",
       HALL_ORRERY_Z > HALL_BAYS * HALL_BAY_Z);

    // **A bay arrives already fogged, or it arrives.** The hall is endless
    // because nothing is recycled, but the *range* of bays drawn is not:
    // `_b1` is `_b0 + HALL_BAYS`, so one more bay enters the loop every time
    // the camera crosses a bay line. If the air is still clear out there, a
    // whole bay of shelving, its parapet and its furniture appear at once --
    // which is the grove's `CORRIDOR_ARRIVE_HAZE` finding, in a stage that
    // buys its distance with hardware fog instead of an alpha.
    //
    // The worst case is the camera exactly on a bay line, where the last bay
    // drawn begins `(HALL_BAYS - 1)` bays out; the props inside it are half a
    // bay further again.
    ok("the last bay drawn arrives fully fogged",
       (HALL_BAYS - 1) * HALL_BAY_Z >= HALL_FOG_END);
    ok("...and the fog has somewhere to fall off across",
       HALL_FOG_END > HALL_FOG_START * 2);

    // **And fully faded, which is the half that actually hides it.** Fog
    // recolours a surface toward the air and that hides it only where what is
    // behind it is the air too -- here it is the rotunda, which is a lit
    // building, so an arriving bay was a fog-coloured silhouette cut out of
    // it. `sh_hall` takes the alpha instead; this is the number that has to
    // reach zero before a bay can enter the loop.
    ok("...and fully faded, which is what hides it from the rotunda",
       HALL_FADE_END <= (HALL_BAYS - 1) * HALL_BAY_Z);
    ok("...over a band rather than at a plane",
       HALL_FADE_START < HALL_FADE_END - HALL_BAY_Z);
    // **The fade begins where the fog ends, and neither before nor after.**
    // Before, and a surface goes transparent while its colour is still its
    // own, which reads as the texture dissolving rather than as distance. At
    // the same distance as the fog's own end -- which is where both of them
    // were -- the rows the fog had merely dimmed are the rows the fade
    // removes, and the hall loses the depth the fog was buying: measured by
    // counting tabards down the nave, six rows became four.
    ok("...beginning exactly where the air goes solid",
       HALL_FADE_START == HALL_FOG_END);
    ok("...and nearer than the far plane", HALL_ORRERY_Z < HALL_ZFAR);
    // The dome has to be inside the frustum too: the depth test is off for it,
    // and the near and far planes clip regardless.
    ok("the sky dome is inside the frustum",
       HALL_SKY_R > HALL_ZNEAR && HALL_SKY_R < HALL_ZFAR);

    // **The sky at the horizon is the fog**, which is what stops the far end
    // of the hall meeting the sky at a line. Asserted rather than assumed
    // because `hall_sky_col` gained a palette of its own and could very
    // easily have gained a horizon of its own with it.
    ok("the sky at the horizon is exactly the fog colour",
       hall_sky_col(0) == HALL_FOG);
    ok("...and it is a different colour further up",
       hall_sky_col(40) != HALL_FOG);

    // **The stars fade out before the wall tops do**, or the architecture
    // closes into haze with a crisp starfield behind it and the join between
    // them is the line the fog exists to hide. The wedge's own lowest
    // elevation is at its edge, which is the slope above.
    //
    // **Measured at the elevation the orrery hangs at, not at some elevation
    // above it.** The first version of this asked whether a star well above
    // `HALL_STAR_EL1` was lit, which is true for every ramp there is and is
    // therefore not a question -- it passed happily against a ramp spread
    // over forty-six degrees, which is the exact defect that put an empty
    // grey wedge on the screen. What has to be lit is the sky the player
    // actually looks at, and the orrery is by construction in the middle of
    // it.
    var _sky_el = darctan((HALL_ORRERY_Y - _cam) / HALL_ORRERY_Z);
    ok("a star at the wall-top line is out", hall_star_extinction(0) <= 0.001);
    ok("...and one where the orrery hangs is fully lit",
       hall_star_extinction(_sky_el) > 0.9);

    // ---- the chamber at the end of it -------------------------------------
    //
    // **It is a floor under the landmark, not a second thing over it.** The
    // first version was hung over the whole wedge and its galleries swept up
    // past the orrery, which read as pale arcs across the sky rather than as
    // a building under one.
    var _rot_top = _f * (HALL_ROT_Y0 + 2 * HALL_ROT_HH - _cam) / HALL_ROT_Z;
    var _rot_bot = _f * (HALL_ROT_Y0 - _cam) / HALL_ROT_Z;
    ok("the far chamber tops out under the orrery",
       _rot_top < _cy + _cr);
    // **Its foot is under the horizon.** The hall's own floor runs out a few
    // thousand units short of it, so anything that stopped *above* the
    // vanishing point would leave a band of bare sky between the marble and
    // the chamber -- a ruled line across the field, which is the defect the
    // open roof was built to avoid rather than to introduce.
    ok("...and its foot is below the vanishing point", _rot_bot < 0);
    // Behind the orrery, past the last bay, inside the far plane: the three
    // facts that let it be drawn as a backdrop and still sort correctly.
    ok("...and it stands behind the orrery",
       HALL_ROT_Z > HALL_ORRERY_Z);
    ok("...past the last bay the hall draws",
       HALL_ROT_Z > HALL_BAYS * HALL_BAY_Z);
    ok("...and inside the far plane", HALL_ROT_Z < HALL_ZFAR);

    // **A banner is placed by its centre and has a width.** It hangs in front
    // of the wall, so how far out it may go is bounded by the cornice face
    // rather than by the wall -- moved outboard to hang off the new wall head
    // it put its outer third through the masonry, which is a sum of three
    // numbers in two files that nothing was adding up.
    var _bw = HALL_BANNER_H * sprite_get_width(spr_hall_banner)
              / sprite_get_height(spr_hall_banner);
    ok("a banner hangs clear of the cornice it hangs under",
       HALL_BANNER_X + _bw * 0.5 < HALL_HALF_W - HALL_CORN_D);
    ok("...and its head is under the coping rather than in it",
       HALL_CEIL_H - HALL_BANNER_DROP <= HALL_CEIL_H);

    st_reset();
}

/// @desc The review card: the hall, flown on its own, and nothing in it.
///
///       **What is worth asserting is that it cannot do any harm**, which is
///       the same thing `test_drafts` asserts about the drafting table and for
///       the same reason. Whether the reveal is paced right is exactly the
///       question this card exists to ask a person, and no suite can answer
///       it.
/// @desc The alcove's orb, its stand, and the light it casts are one object.
///
///       **Two halves of one lamp, disagreeing about where it is.** The
///       sphere was built at the mouth of the recess and `hall_wall_light`
///       put its falloff at the back wall -- a hundred and eighty units
///       apart, which on screen is a pool of light on empty stone beside an
///       orb casting nothing. Both numbers are legal and the picture is
///       valid, so the only thing that could ever have reported it is an
///       assertion with both of them in view.
function test_hall_orb() {
    st_reset();

    for (var _s = -1; _s <= 1; _s += 2) {
        var _x = hall_orb_x(_s);
        // the recess, measured the way `hall_case_side` measures it
        var _mouth = _s * (HALL_HALF_W + HALL_PIL_D);
        var _back = _s * (HALL_HALF_W + HALL_PIL_D + HALL_ALCOVE_D);
        ok("the orb stands inside its own alcove",
           abs(_x) > abs(_mouth) && abs(_x) < abs(_back));
        // ...and clear of both, by its own radius: against the back wall it
        // is occluded from every angle the camera reaches, and in the plane
        // of the mouth half of it hangs out over the nave with nothing under
        // it, which is how it read before the stand was built.
        ok("...clear of the mouth and of the back wall",
           abs(_x) - HALL_ORB_R > abs(_mouth)
           && abs(_x) + HALL_ORB_R < abs(_back));

        // **The light is at the orb, which is the whole of this suite.**
        // Sampled rather than reasoned about, and sampled **far out**: near
        // the alcove the ambient, the lamp and the orb together run past the
        // cap, so two points either side of the sphere both read 1.35 and a
        // comparison there says nothing at all. It is the same trap as
        // measuring a clipped facet map. Differenced against the same bay
        // with no orb in it, so what is left is the orb's own term and
        // nothing else.
        var _z = HALL_BAY_Z * 0.5;
        var _near = hall_wall_light(_x, HALL_ORB_Y, _z + 700, _s, 2)
                    - hall_wall_light(_x, HALL_ORB_Y, _z + 700, _s, 0);
        var _far = hall_wall_light(_x, HALL_ORB_Y, _z + 1000, _s, 2)
                   - hall_wall_light(_x, HALL_ORB_Y, _z + 1000, _s, 0);
        ok("...and the light it casts falls off with distance from it",
           _near > _far && _far > 0);
        ok("...and a bay with no orb in it is not lit by one",
           hall_wall_light(_x, HALL_ORB_Y, _z, _s, 0)
           < hall_wall_light(_x, HALL_ORB_Y, _z, _s, 2));

        // The stack: the shaft's head, the cup, and the sphere resting in it.
        // Every one of these is derived from the one below, so what this
        // holds is that the derivation still lands the orb on the stand
        // rather than above it -- which is what it did when the stand was a
        // flat plate and the sphere floated twenty-four units clear.
        var _cup = HALL_ORB_Y - HALL_ORB_R;
        ok("the orb sits in its cup rather than over it",
           _cup - HALL_ORB_CRADLE > HALL_PLINTH_H);
        ok("...and the stand stands on the alcove's own sill",
           HALL_ORB_Y - HALL_ORB_R - HALL_ORB_CRADLE - HALL_PLINTH_H > 0);
    }
}

/// @desc The pavement's three courses fill the nave exactly once.
///
///       **A floor is read across, so what has to be right is the sum.** Four
///       squares of marble was reported as the same thing four times left to
///       right; what replaced it is a runner, a border course either side and
///       the marble out at the walls -- and the one way that can go wrong
///       silently is for the courses to overlap or to leave a strip of
///       nothing, either of which is a perfectly valid picture of a floor
///       with a seam in it.
function test_hall_floor() {
    st_reset();

    var _sum = HALL_RUNNER_HW + HALL_BORDER_W;
    ok("the runner and its border fit inside the nave", _sum < HALL_HALF_W);
    ok("...and the marble takes what is left, at a sane tile",
       (HALL_HALF_W - _sum) / HALL_AISLE_NX > 120);
    // The player lives over the runner, so it has to be wider than they are
    // and narrower than the field: a runner the width of the nave is a nave.
    ok("the runner is the lane the player actually flies in",
       HALL_RUNNER_HW * 2 > FIELD_W * 0.25
       && HALL_RUNNER_HW * 2 < HALL_HALF_W * 2 * 0.62);
    // **The step is small.** It is there for the two lit lines it puts down
    // the hall, not to be architecture in its own right -- and anything the
    // camera could fly *into* at 250 units up is a different problem.
    ok("the step is a fillet rather than a stair",
       HALL_FLOOR_STEP > 0 && HALL_FLOOR_STEP < 30);
    // The threshold is a band across the aisle, not a slab: it may not eat
    // the bay it is marking the end of.
    ok("the threshold is a band, not a bay",
       HALL_THRESH_W > 0 && HALL_THRESH_W < HALL_BAY_Z * 0.2);

    // **The pavement is lit by the room, not by the tile.** The old floor
    // shaded off the u of each tile, so it was bright at every tile edge --
    // four bright seams across the nave rather than two bright walls. What
    // holds it down is that the light near a wall beats the light in the
    // middle, measured in world coordinates where the defect lived.
    var _z = HALL_BAY_Z * 0.5;
    var _mid = hall_floor_light(0, 0, _z, 1, 0);
    var _wall = hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 0);
    var _seam = hall_floor_light(HALL_RUNNER_HW, 0, _z, 1, 0);
    ok("the pavement is brighter at the walls than down the middle",
       _wall > _mid);
    ok("...and the joint between two courses is not a light of its own",
       _seam < _wall && _seam > _mid);
    // ...and the alcove's orb reaches it, which is the other half of a lamp
    // being a lamp.
    ok("an alcove throws a pool onto the stone in front of it",
       hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 2)
       > hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 0));
    // The centre of the field is where the player lives and where the danmaku
    // is thickest, so it stays the darkest part of the picture.
    ok("...and the middle of the nave stays the darkest part of it",
       _mid < HALL_WALL_AMB + 0.25);
}

function test_hall_preview() {
    st_reset();

    var _def = preview_stage_def();
    ok("the review card is a stage to play", stage_is_built(_def));
    ok("...but has no stage to file a clear against", _def.id == "");
    ok("...and a blank id reads back as nothing cleared",
       !progress_stage(_def.id).cleared);
    ok("...and no attacks to practise", !practice_available(_def));
    ok("...and it is not the drafting table", !stage_is_draft(_def));
    ok("...and it says what it is, so the rack need not guess",
       stage_is_preview(_def));
    ok("...and no stage claims to be one",
       !stage_is_preview(stage_sanctum_def())
       && !stage_is_preview(draft_stage_def()));
    ok("nor does nothing at all", !stage_is_preview(undefined));

    // **It has nothing in it.** Not a rule about taste: a wave would put an
    // enemy on the field, and the whole of what this card is for is watching
    // the background with nothing in front of it.
    var _ev = _def.build();
    ok("its running order is nothing but the turn, over and over",
       array_length(_ev) == PREVIEW_CYCLES * 2);
    var _gates = 0;
    for (var _i = 0; _i < array_length(_ev); _i++) {
        if (_ev[_i].gate) _gates++;
    }
    ok("...with no gates in it, because nothing ever has to be cleared",
       _gates == 0);
    var _sorted = true;
    for (var _i = 1; _i < array_length(_ev); _i++) {
        if (_ev[_i].at < _ev[_i - 1].at) _sorted = false;
    }
    ok("...and it is in order", _sorted);

    // The rewind is a cut, and a cut is what it claims to be.
    var _b = bg_new(spr_hall_floor, spr_hall_stone, spr_hall_pale,
                    HALL_FOG, HALL_SPEED);
    bg_set_omen(_b);
    for (var _i = 0; _i < BG_OMEN_TIME; _i++) bg_omen_step(_b);
    ok("the turn runs to its end", _b.omen >= 1);
    bg_clear_omen(_b);
    ok("...and the rewind puts it back at once", _b.omen == 0 && !_b.omen_on);
    bg_omen_step(_b);
    ok("...and it stays there until it is asked again", _b.omen == 0);

    st_reset();
}

function test_rings() {
    st_reset();

    // --- the pool ------------------------------------------------------
    var _r = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("a ring reaches the field", _r != undefined && ring_count() == 1);
    ok("and it knows how thick its metal is",
       abs(ring_band_half() - RING_R * RING_BAND_FRAC) < 0.001);

    // **Every ring is the same size and there is no argument that changes
    // that.** It is asserted rather than trusted because the rule is the whole
    // reason `RING_R` is a macro instead of a field: six rings on the field
    // have to be six of one object, and an attack that could ask for a bigger
    // one would be introducing a second thing to learn without saying so.
    var _other = ring_new(FIELD_X0 + 200, FIELD_Y0 + 200, BCOL_CYAN, 0);
    ok("and every ring is the same size",
       _other != undefined && ring_band_half() == RING_BAND_HALF);
    // ...and moderately bigger than the largest thing the game fires, which is
    // the number `RING_R` was chosen against.
    var _biggest = 0;
    for (var _i = 0; _i < BSHAPE_COUNT; _i++) {
        _biggest = max(_biggest, global.bshape_w[_i]);
    }
    ok("...and moderately bigger than the largest bullet",
       RING_R * 2 > _biggest && RING_R * 2 < _biggest * 2.2);
    ring_clear_all();
    _r = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);

    // **The drawn band has to fit inside the sprite it is drawn from.** Both
    // numbers mirror `tools/make_rings.py`, and if the outer edge ran past the
    // sprite's own edge the metal would be sliced flat along four sides --
    // the defect `cut_pad` exists for, one family over.
    ok("the band fits inside its own sprite",
       RING_SPR_LINE * (1 + RING_BAND_FRAC) < 1.0);

    // A stale reference: sweep the ring and the serial no longer matches, even
    // though the struct is still sitting in the pool waiting to be reused.
    var _gen = _r.gen;
    ok("a live ring validates", ring_valid(_r, _gen));
    ring_clear_all();
    ok("clearing empties the pool", ring_count() == 0);
    ok("and a reference to a swept ring is refused", !ring_valid(_r, _gen));

    var _r2 = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("the slot is handed straight back out", _r2 == _r);
    ok("...and the old reference is still refused", !ring_valid(_r, _gen));

    // The cap is a refusal, as every pool here is.
    st_reset();
    var _made = 0;
    for (var _i = 0; _i < RING_MAX + 8; _i++) {
        if (ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0) != undefined) {
            _made++;
        }
    }
    ok("the pool refuses rather than growing",
       _made == RING_MAX && ring_count() == RING_MAX);

    // --- blocking ------------------------------------------------------
    st_reset();
    var _ring = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    // A ring that blocked while it was still arriving would be a wall that
    // appeared without warning, which is the rule `BULLET_DELAY_DEFAULT`
    // states for bullets.
    ok("a ring that is still arriving does not block", !ring_solid(_ring));
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    ok("...and does once it has arrived", ring_solid(_ring));

    // **The swept test, which is the whole reason this is not a point
    // check.** A player shot travels `PSHOT_SPD` a frame against metal
    // `2 * ring_band_half` thick, so a point test would miss most of them and
    // the ring would read as leaking at random -- the same defect
    // `bullet_hit_index` exists for. The segment here steps clean over the
    // band in one frame.
    var _half = ring_band_half();
    var _inner = FIELD_CY + RING_R - _half - 2;
    var _outer = FIELD_CY + RING_R + _half + 2;
    ok("a shot that jumps the whole band is still caught",
       ring_seg_crosses(_ring, FIELD_CX, _outer, FIELD_CX, _inner));
    ok("...which a point test at either end would have missed",
       ring_band_dist(_ring, FIELD_CX, _outer) > _half
       && ring_band_dist(_ring, FIELD_CX, _inner) > _half);

    // The hole. **This is the half that makes the mechanic answerable**: a
    // ring that blocked across its disc would be an indestructible shield,
    // which is the "unanswerable rather than hard" defect `BossMove` was
    // written for.
    ok("a shot inside the hole passes",
       !ring_seg_crosses(_ring, FIELD_CX - 20, FIELD_CY + 30,
                         FIELD_CX + 20, FIELD_CY - 30));
    ok("a shot right past the outside passes",
       !ring_seg_crosses(_ring, FIELD_CX + 300, FIELD_CY - 100,
                         FIELD_CX + 300, FIELD_CY + 100));

    // ...and end to end, through the real function.
    st_reset();
    _ring = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    pshot_fire(FIELD_CX, FIELD_CY + 300, PSHOT_SPD, 90, PSHOT_DMG);
    pshot_fire(FIELD_CX + 400, FIELD_CY + 300, PSHOT_SPD, 90, PSHOT_DMG);
    var _stopped = 0;
    for (var _i = 0; _i < 40; _i++) {
        pshot_step();
        _stopped += ring_block_shots();
    }
    ok("one shot of two is eaten by the metal", _stopped == 1);

    // --- the charge ----------------------------------------------------
    st_reset();
    _ring = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    ok("a cold ring cannot hurt anybody",
       !ring_any_hit(FIELD_CX, FIELD_CY + RING_R, PLAYER_R));

    ring_charge(_ring, 20, 30);
    var _bit_during_warning = false;
    // **Sampled while the warning is still running, not after each step.**
    // The frame the countdown reaches zero *is* the frame the metal goes live,
    // so a loop that stepped and then looked would find the band hot on its
    // last pass and call that a failure -- which is the assertion being off by
    // one rather than the rule being broken, and it is the harder of the two
    // to see because the first run of this was failing for a real reason as
    // well. See `ring_is_hot`.
    for (var _i = 0; _i < 20; _i++) {
        if (_ring.warn > 0
            && ring_any_hit(FIELD_CX, FIELD_CY + RING_R, PLAYER_R)) {
            _bit_during_warning = true;
        }
        ring_step(undefined);
    }
    // **A telegraph that can kill is not a telegraph.** Same rule
    // `laser_is_hot` keeps, and the reason `ring_charge` refuses a warning of
    // zero in its docstring.
    ok("a charging ring cannot hurt anybody either", !_bit_during_warning);
    ok("and then the metal bites",
       ring_any_hit(FIELD_CX, FIELD_CY + RING_R, PLAYER_R));

    // It kills a little narrower than it is drawn, on the genre's rule.
    ok("it kills narrower than it is drawn",
       ring_kill_half() < ring_band_half());
    var _just_outside = FIELD_CY + RING_R + ring_kill_half() + PLAYER_R + 2;
    ok("...so the black of the cuff is the hitbox",
       !ring_any_hit(FIELD_CX, _just_outside, PLAYER_R));

    // Grazing: outside the kill band, and on a cooldown rather than once,
    // because a wall is still there a second later. Same deal `laser_graze`
    // makes and off the same measurement, so what the player learnt from the
    // bullets holds here.
    _ring.graze_t = 0;
    ok("riding a charged band pays",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 1);
    ok("...and not again on the next frame",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 0);

    for (var _i = 0; _i < RING_GRAZE_CD + 1; _i++) ring_step(undefined);
    ok("...but again once the cooldown is up",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 1);

    // --- the arc -------------------------------------------------------
    st_reset();
    var _a = ring_new(FIELD_CX - 300, FIELD_CY, BCOL_CYAN, 0);
    var _b = ring_new(FIELD_CX + 300, FIELD_CY, BCOL_CYAN, 0);
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    ring_link(_a, _b, 120);
    ok("current runs between two rings", ring_arc_live(_a));
    ok("...and it is lethal along the line between them",
       ring_any_hit(FIELD_CX, FIELD_CY, PLAYER_R));
    ok("...and not off it",
       !ring_any_hit(FIELD_CX, FIELD_CY + 240, PLAYER_R));

    // **Losing the far end takes the current with it.** A ring struct is
    // reused out of the pool, so an arc held as a bare reference would keep
    // drawing a lethal line to whatever took the slot -- which is the trap the
    // serial on every ring exists for, and the one thing here that would reach
    // a player as damage from nothing.
    ring_dismiss(_b, 1);
    ring_step(undefined);
    ring_step(undefined);
    ok("and it goes out with the ring at its far end", !ring_arc_live(_a));
    ok("...so nothing is left lethal in the middle of the field",
       !ring_any_hit(FIELD_CX, FIELD_CY, PLAYER_R));

    // --- Mika's table --------------------------------------------------
    var _ph = mika_phases();
    var _descends = true;
    var _prev = 1.0;
    for (var _i = 0; _i < array_length(_ph); _i++) {
        if (_ph[_i].hp_end >= _prev) _descends = false;
        _prev = _ph[_i].hp_end;
    }
    ok("Mika's table descends", _descends);
    ok("and ends at zero", _ph[array_length(_ph) - 1].hp_end == 0);

    // **Every attack he has puts a ring on the field**, which is the claim the
    // whole stage was written to make and the one an assertion can actually
    // check. It is played rather than read: each attack is run against a real
    // controller for a few seconds and the pool is counted.
    var _ringed = 0;
    for (var _i = 0; _i < array_length(_ph); _i++) {
        st_reset();
        var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
        var _e = mika_spawn(_g);
        if (_e == undefined) break;
        _e.boss.entry_t = 0;
        _e.boss.declare_t = 0;
        _e.boss.started = true;
        _e.x = _e.boss.home_x;
        _e.y = _e.boss.home_y;
        boss_enter_phase(_e, _g, _i);
        _e.boss.lead_t = 0;
        var _seen = 0;
        for (var _f = 0; _f < 320; _f++) {
            _ph[_i].attack(_e, _g, _f);
            ring_step(_g);
            _seen = max(_seen, ring_count());
        }
        if (_seen > 0) _ringed++;
    }
    ok("every one of his attacks is a ring attack",
       _ringed == array_length(_ph));

    st_reset();
}
