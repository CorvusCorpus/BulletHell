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
    test_spell_resist();
    test_player();
    test_items();
    test_boss_table();
    test_boss_phases();
    test_stage_table();
    test_stage_run();
    test_marks();
    test_practice();
    test_hud_layout();
    test_run_starts_clean();
    test_boss_is_never_invisible();
    test_save_atomicity();
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
    ok("the roster has eight stages", array_length(_list) == 8);
    ok("stage one is built", stage_is_built(_list[0]));
    ok("and needs nothing to unlock", _list[0].needs == 0);
    var _rest_locked = true;
    for (var _i = 1; _i < array_length(_list); _i++) {
        if (stage_is_built(_list[_i])) _rest_locked = false;
    }
    ok("and the rest are honestly marked unbuilt", _rest_locked);
}

function test_stage_run() {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.boss_ref = undefined;
    _g.phase = Phase.Playing;

    var _s = stage_new(stage_ziggy_def());

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
    ok("the stage reaches its end", _s.done);
    ok("and puts a boss on the field on the way", _boss_seen);
    ok("without leaking enemies past its own cap",
       enemy_count() <= ENEMY_MAX);
    st_reset();
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
    var _list = stage_list();
    ok("an unbuilt stage offers nothing to practise",
       !practice_available(_list[1]));
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
    ok("the spell name sits under the boss's bar",
       BOSS_SPELL_Y > BOSS_BAR_Y + BOSS_BAR_H
       && BOSS_SPELL_Y < FIELD_Y0 + FIELD_H * 0.14);
    ok("and the boss still flies clear of both",
       BOSS_HOME_Y - BOSS_DRIFT_Y - 125 > BOSS_SPELL_Y);

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
    ok("and the boss flies below its own line, not through it",
       BOSS_HOME_Y - BOSS_DRIFT_Y - 125 > BOSS_BAR_Y + BOSS_BAR_H);

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
    item_spawn(FIELD_CX, FIELD_CY, ItemKind.Tally);
    enemy_spawn(EnemyKind.Wisp, FIELD_CX, FIELD_CY, 5, undefined, BCOL_CYAN,
                0, 0, 0);
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 100, 1000, ziggy_phases(),
                        ziggy_def());

    ok("the field can be dirtied at all",
       bullet_count() > 0 && laser_count() > 0 && item_count() > 0
       && enemy_count() > 1 && _b != undefined);

    // This is what entering `room_game` does, and it is the whole assertion:
    // however a run was reached, it starts here.
    run_clear_field();

    ok("a run starts with no bullets", bullet_count() == 0);
    ok("...no lasers", laser_count() == 0);
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
