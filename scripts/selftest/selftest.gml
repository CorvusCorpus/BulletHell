/// @desc The suites `tools/test.py` runs with `-selftest` and grades from
///       stdout.
///
/// Everything runs headless at the fixed 60 Hz step, so a suite can drive
/// hundreds of frames and then read the pools. The suites cover things that
/// break silently: engine mechanics, pool limits, collision, hitboxes that
/// must match their sprites, data integrity, save safety and specific past
/// bugs. Attack tuning and the look of things are not pinned here.
///
/// No suite touches the real save file.

// How long `test_attacks_run` runs each attack.
#macro ST_ATTACK_FRAMES 300

function selftest_run() {
    global.st_pass = 0;
    global.st_fail = 0;

    test_bullet_table();
    test_bullet_pool();
    test_fire_patterns();
    test_bullet_motion();
    test_bullet_cartesian();
    test_bullet_mods();
    test_bullet_dress();
    test_bullet_queue();
    test_bullet_expiry();
    test_collision();
    test_graze();
    test_laser();
    test_laser_graze();
    test_rings();
    test_mika_slots();
    test_mika_sand();
    test_storm_cage();
    test_boss_step();
    test_hall_sky();
    test_hall_orb();
    test_hall_floor();
    test_hall_preview();
    test_old_sanctum();
    test_spell_resist();
    test_player();
    test_bomb_seals();
    test_grace_dial();
    test_items();
    test_untouchable();
    test_phase_tables();
    test_boss_phases();
    test_boss_move();
    test_stage_table();
    test_stage_run();
    test_corridor();
    test_band_strip();
    test_grove_turn();
    test_marks();
    test_wave_marks();
    test_stage_encounters();
    test_rank_card();
    test_practice();
    test_drafts();
    test_hex_seal();
    test_hud_layout();
    test_boss_rig();
    test_counter();
    test_run_starts_clean();
    test_boss_is_never_invisible();
    test_save_atomicity();
    test_audio_budget();
    test_audio_playback();
    test_attacks_run();
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

/// @desc Empty every pool, so no suite inherits another's field.
function st_reset() {
    danmaku_init();
    laser_init();
    ring_init();
    item_init();
    enemy_init();
    fx_clear();
}

/// @desc A stand-in for `obj_game`, carrying only what the rules read.
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
        // The only place a spell broken and a spell survived differ.
        ended_n: 0,
        ended_beaten: false,
        on_phase_end: function(_e, _beaten) {
            ended_n++;
            ended_beaten = _beaten;
        },
        practice: undefined,
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
// Bullets
// ---------------------------------------------------------------------------

function test_bullet_table() {
    ok("bullet table has every shape",
       array_length(global.bshape_sprite) == BSHAPE_COUNT);

    var _bad_radius = 0;
    var _bad_frames = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        if (global.bshape_radius[_s] <= 0) _bad_radius++;
        var _want = BCOL_COUNT * global.bshape_frames[_s];
        if (sprite_get_number(global.bshape_sprite[_s]) != _want) _bad_frames++;
    }
    ok("every shape has a positive hit radius", _bad_radius == 0);
    ok("every sprite holds colours x animation frames", _bad_frames == 0);

    // An oriented shape's angle is its heading, so a default spin on one
    // would be overwritten every frame.
    var _spun = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        if (global.bshape_oriented[_s] && global.bshape_spin[_s] != 0) _spun++;
    }
    ok("no oriented shape carries a default spin", _spun == 0);
    ok("the star shapes turn on their own",
       global.bshape_spin[BSHAPE_STAR] > 0
       && global.bshape_spin[BSHAPE_STAR6] > 0
       && global.bshape_spin[BSHAPE_MOTE] > 0);

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

    var _tail_x = bullet_get(99).x;
    bullet_kill_at(50);
    ok("killing one drops the count", bullet_count() == 99);
    ok("the swapped-in bullet survives at the hole",
       bullet_get(50).x == _tail_x);

    for (var _i = bullet_count() - 1; _i >= 0; _i--) bullet_kill_at(_i);
    ok("the pool empties exactly", bullet_count() == 0);

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
    var _seen = [];
    for (var _i = 0; _i < 12; _i++) array_push(_seen, bullet_get(_i).dir);
    ok_near("the ring starts on its own angle", _seen[0], 0, 0.001);
    ok_near("the ring steps by 360/n", _seen[3] - _seen[2], 30, 0.001);

    st_reset();
    fire_fan(500, 500, 5, 3, 90, 40, BSHAPE_RICE, BCOL_GOLD, 0);
    ok("a fan of five is five bullets", bullet_count() == 5);
    ok_near("the fan's ends are +/- arc/2", bullet_get(0).dir, 70, 0.001);
    ok_near("the fan's far end", bullet_get(4).dir, 110, 0.001);
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
    ok_near("its rows rise by the step", bullet_get(10).spd, 3, 0.001);
    ok_near("and every row keeps a bullet on the aim line",
            bullet_get(12).dir, 90, 0.001);

    st_reset();
    fire_fan_stack(500, 500, 3, 2, 2, 0.5, 90, 40, BSHAPE_RICE, BCOL_BONE, 0,
                   6);
    ok_near("a skewed row is turned off the one in front",
            bullet_get(4).dir - bullet_get(1).dir, 6, 0.001);

    ok_near("aim_at points right", aim_at(0, 0, 100, 0), 0, 0.001);
    ok_near("aim_at points up", aim_at(0, 0, 0, -100), 90, 0.001);
    st_reset();
}

function test_bullet_motion() {
    st_reset();
    var _b = fire(500, 500, 4, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok_near("a bullet moves by its speed", _b.x, 504, 0.001);
    ok_near("and not in the other axis", _b.y, 500, 0.001);

    st_reset();
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

    st_reset();
    fire(GAME_W + CULL_MARGIN - 5, 500, 20, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok("a bullet that leaves the field is culled", bullet_count() == 0);
    st_reset();
}

function test_bullet_cartesian() {
    st_reset();
    var _b = fire_xy(500, 500, 3, -4, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_step(0, 0);
    ok_near("a Cartesian bullet moves by its x component", _b.x, 503, 0.001);
    ok_near("and by its y component", _b.y, 496, 0.001);
    ok_near("its speed is the magnitude of the two", _b.spd, 5, 0.001);
    ok_near("and its heading is honest",
            _b.dir, point_direction(0, 0, 3, -4), 0.001);

    // A force in one axis bends a polar bullet, capped at a terminal speed.
    st_reset();
    var _f = fire(500, 200, 6, 0, BSHAPE_PELLET, BCOL_GOLD, 0);
    bullet_force(_f, 0, 0.5, BQ_KEEP, 4);
    for (var _i = 0; _i < 30; _i++) bullet_step(0, 0);
    ok("a force pulls a bullet off its heading", _f.y > 200);
    ok_near("and leaves the other axis alone", _f.vx, 6, 0.001);
    ok_near("the cap is a terminal velocity", _f.vy, 4, 0.001);
    ok("and the heading follows the path down",
       _f.dir > 270 && _f.dir < 360);

    st_reset();
    fire_xy(400, 500, 24, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    bullet_step(0, 0);
    ok("a Cartesian bullet is swept for collision like any other",
       bullet_hit_index(412, 500, PLAYER_R) == 0);

    // A later polar instruction must take the bullet off the force model.
    st_reset();
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
    // An event scheduled for frame N fires on step N + 1: `life` increments at
    // the end of a step.
    st_reset();
    var _b = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_aim_at(_b, 3);
    for (var _i = 0; _i < 3; _i++) bullet_step(500, 0);
    ok("an aimed bullet has not turned early", abs(_b.dir - 0) < 0.001);
    bullet_step(500, 0);
    ok_near("an aimed bullet turns to its target", _b.dir, 90, 2.0);
    ok("and its event is spent", _b.q_i == _b.q_n);

    st_reset();
    var _o = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_aim_at(_o, 0, 30);
    bullet_step(500, 0);
    ok_near("an aim offset leads its target", _o.dir, 120, 2.0);

    st_reset();
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
    var _w = fire(500, 500, 2, 0, BSHAPE_RICE, BCOL_JADE, 0);
    bullet_shed_every(_w, 1, 2, 3, 1, 4, 180);
    for (var _i = 0; _i < 8; _i++) bullet_step(0, 0);
    ok("a wake leaves one child per burst", bullet_count() == 4);
    ok_near("and the parent flies on through all of them", _w.x, 516, 0.001);

    st_reset();
    var _h = fire(500, 500, 2, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    _h.bmod = BMod.Home;
    _h.mod_a = 2;
    bullet_step(500, 0);
    ok_near("homing turns by at most its cap", _h.dir, 2, 0.001);
    st_reset();
}

/// @desc A split or a shed can hand each child to a callback as it is made.
function test_bullet_dress() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _seen = { n: 0, idx: [] };
    var _u = fire(FIELD_CX, FIELD_CY, 3, 0, BSHAPE_SPHERE, BCOL_GOLD, 0);
    bullet_split_at(_u, 2, 6, 2.5, 0,
                    method(_seen, function(_c, _k) {
        n++;
        array_push(idx, _k);
        if (_c != undefined) _c.col = BCOL_JADE;
    }));
    for (var _f = 0; _f < 4 + BULLET_SPLIT_DELAY; _f++) {
        bullet_step(_g.player.x, _g.player.y);
    }
    ok("a split calls its dress method once per child", _seen.n == 6);
    var _ordered = (array_length(_seen.idx) == 6);
    for (var _i = 0; _i < array_length(_seen.idx); _i++) {
        if (_seen.idx[_i] != _i) _ordered = false;
    }
    ok("...and told its index round the burst", _ordered);
    var _dressed = (bullet_count() == 6);
    for (var _i = 0; _i < bullet_count(); _i++) {
        if (bullet_get(_i).col != BCOL_JADE) _dressed = false;
    }
    ok("...and what it did to the child reaches the field", _dressed);

    st_reset();
    _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _shed = { n: 0 };
    _u = fire(FIELD_CX, FIELD_CY, 3, 0, BSHAPE_SPHERE, BCOL_GOLD, 0);
    bullet_shed_at(_u, 2, 4, 2.5, 0, 0,
                   method(_shed, function(_c, _k) { n++; }));
    for (var _f = 0; _f < 4 + BULLET_SPLIT_DELAY; _f++) {
        bullet_step(_g.player.x, _g.player.y);
    }
    ok("a shed dresses its children as well", _shed.n == 4);
    ok("...and keeps its parent, which is what makes it a shed",
       bullet_count() == 5);
    st_reset();
}

function test_bullet_queue() {
    st_reset();
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
    var _k = fire(500, 500, 3, 45, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_move_at(_k, 0, BQ_KEEP, 180);
    bullet_step(0, 0);
    ok("a kept field is left alone", _k.spd == 3);
    ok("while the one beside it is set", _k.dir == 180);

    st_reset();
    var _f = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    for (var _i = 0; _i < BULLET_QUEUE_MAX + 4; _i++) bullet_turn_at(_f, _i, 1);
    ok("a bullet's queue refuses past its cap", _f.q_n == BULLET_QUEUE_MAX);

    st_reset();
    var _g = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_graphic_at(_g, 1, BSHAPE_SPHERE, BCOL_ROSE);
    bullet_step(0, 0);
    bullet_step(0, 0);
    ok("a scheduled graphic change swaps the picture",
       _g.shape == BSHAPE_SPHERE && _g.col == BCOL_ROSE);
    ok("and the hitbox goes with it",
       _g.r == global.bshape_radius[BSHAPE_SPHERE]);

    ok("scheduling on a refused bullet is not an error",
       bullet_turn_at(undefined, 4, 2) == undefined);
    st_reset();
}

function test_bullet_expiry() {
    st_reset();
    var _b = fire(500, 500, 1, 0, BSHAPE_ORB, BCOL_CYAN, 0);
    bullet_expire_at(_b, 10, 6);
    for (var _i = 0; _i < 10; _i++) bullet_step(0, 0);
    ok("a bullet with a lifetime is solid until its frame",
       bullet_hit_index(_b.x, _b.y, PLAYER_R) == 0);
    bullet_step(0, 0);
    ok("it starts fading on that frame", _b.fade_t > 0);
    ok("a fading bullet cannot hit",
       bullet_hit_index(_b.x, _b.y, PLAYER_R) == -1);
    ok("and cannot be grazed either",
       bullet_graze(_b.x, _b.y, GRAZE_R) == 0);
    for (var _i = 0; _i < 6; _i++) bullet_step(0, 0);
    ok("and it is gone when the fade is", bullet_count() == 0);
    st_reset();
}

function test_collision() {
    // Swept: a fast bullet is tested along the segment it moved this frame.
    st_reset();
    var _b = fire(400, 500, 24, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    bullet_step(0, 0);
    ok("a fast bullet cannot tunnel through the player",
       bullet_hit_index(412, 500, PLAYER_R) == 0);

    st_reset();
    fire(400, 500, 1, 0, BSHAPE_PELLET, BCOL_CRIMSON, 0);
    ok("a bullet a long way off does not hit",
       bullet_hit_index(900, 500, PLAYER_R) == -1);

    st_reset();
    fire(500, 500, 0, 0, BSHAPE_BALL, BCOL_CRIMSON, 30);
    ok("a bullet still fading in cannot hit",
       bullet_hit_index(500, 500, PLAYER_R) == -1);

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
    ok("and never grazes twice", _again == 0);

    st_reset();
    fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CYAN, 30);
    ok("a bullet still fading in cannot be grazed",
       bullet_graze(500, 500, GRAZE_R) == 0);
    st_reset();
}

// ---------------------------------------------------------------------------
// Lasers and rings
// ---------------------------------------------------------------------------

function test_laser() {
    st_reset();
    var _l = laser_beam(500, 500, 0, 800, 40, BCOL_GOLD, 20, 30, 10);
    ok("a beam starts in its warning", _l.phase == LaserPhase.Warn);
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

    // A ray's body runs backwards from its head.
    st_reset();
    var _r = laser_ray(500, 500, 0, 6, 200, 24, BCOL_CRIMSON, 60);
    laser_step();
    ok("a ray covers the ground behind its head",
       laser_hits(_r, 420, 500, 4));
    ok("and nothing in front of it", !laser_hits(_r, 700, 500, 4));

    st_reset();
    var _c = laser_curve(500, 500, 0, 8, 3, 30, BCOL_ROSE, 400);
    for (var _i = 0; _i < 20; _i++) laser_step();
    ok("a curve lays down one node a frame", _c.node_n == 20);
    ok("its trail is dangerous", laser_hits(_c, _c.nx[4], _c.ny[4], 4));
    for (var _i = 0; _i < 100; _i++) laser_step();
    ok("and the trail is capped", _c.node_n <= CURVE_NODES);

    // The light at a beam's root must never outlive the beam.
    st_reset();
    var _b2 = laser_beam(400, 300, 0, 900, 40, BCOL_CYAN, 30, 24, 12);
    var _lit = true;
    for (var _i = 0; _i < 30 + 24 + 12; _i++) {
        var _m = laser_muzzle(_b2);
        if (_m.alpha <= 0.01 || _m.r <= 0) _lit = false;
        laser_step();
    }
    ok("a beam's muzzle is lit for every frame the beam is", _lit);
    _b2.phase = LaserPhase.Done;
    var _done = laser_muzzle(_b2);
    ok("...and goes out with it", _done.alpha <= 0.01 && _done.r <= 0);

    // `src` carries a beam's root along; `look` keeps it aimed at a point.
    st_reset();
    var _src = { x: 300, y: 300 };
    var _spot = { x: 900, y: 700 };
    var _lb = laser_beam(_src.x, _src.y, 0, 1200, 30, BCOL_CYAN, 10, 60, 10);
    _lb.src = _src;
    _lb.look = _spot;
    var _rides = true;
    var _trained = true;
    for (var _i = 0; _i < 40; _i++) {
        _src.x += 6;
        laser_step();
        if (_lb.x != _src.x || _lb.y != _src.y) _rides = false;
        if (laser_spine_dist(_lb, _spot.x, _spot.y) > 0.5) _trained = false;
    }
    ok("a beam with a src rides it", _rides);
    ok("...and one with a look stays trained on that point", _trained);
    st_reset();
}

function test_laser_graze() {
    st_reset();
    var _l = laser_beam(500, 500, 0, 800, 40, BCOL_GOLD, 10, 200, 10);
    ok("a warning line cannot be grazed",
       laser_graze(700, 520, PLAYER_R) == 0);
    for (var _i = 0; _i < 10; _i++) laser_step();
    ok("a player well clear of a live beam pays nothing",
       laser_graze(700, 580, PLAYER_R) == 0);
    ok("riding one pays", laser_graze(700, 520, PLAYER_R) == 1);
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

function test_rings() {
    st_reset();
    var _r = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("a ring reaches the field", _r != undefined && ring_count() == 1);
    ok("the band fits inside its own sprite",
       RING_SPR_LINE * (1 + RING_BAND_FRAC) < 1.0);

    // Pooled rings are reused, so a remembered ring is checked by its gen.
    var _gen = _r.gen;
    ok("a live ring validates", ring_valid(_r, _gen));
    ring_clear_all();
    ok("clearing empties the pool", ring_count() == 0);
    ok("and a reference to a swept ring is refused", !ring_valid(_r, _gen));
    var _r2 = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("the slot is handed straight back out", _r2 == _r);
    ok("...and the old reference is still refused", !ring_valid(_r, _gen));

    st_reset();
    var _made = 0;
    for (var _i = 0; _i < RING_MAX + 8; _i++) {
        if (ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0) != undefined) {
            _made++;
        }
    }
    ok("the pool refuses rather than growing",
       _made == RING_MAX && ring_count() == RING_MAX);

    // Blocking is swept, like bullet collision, and only on the band.
    st_reset();
    var _ring = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("a ring that is still arriving does not block", !ring_solid(_ring));
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    ok("...and does once it has arrived", ring_solid(_ring));
    var _half = ring_band_half();
    var _inner = FIELD_CY + RING_R - _half - 2;
    var _outer = FIELD_CY + RING_R + _half + 2;
    ok("a shot that jumps the whole band is still caught",
       ring_seg_crosses(_ring, FIELD_CX, _outer, FIELD_CX, _inner));
    ok("...which a point test at either end would have missed",
       ring_band_dist(_ring, FIELD_CX, _outer) > _half
       && ring_band_dist(_ring, FIELD_CX, _inner) > _half);
    ok("a shot inside the hole passes",
       !ring_seg_crosses(_ring, FIELD_CX - 20, FIELD_CY + 30,
                         FIELD_CX + 20, FIELD_CY - 30));
    ok("a shot right past the outside passes",
       !ring_seg_crosses(_ring, FIELD_CX + 300, FIELD_CY - 100,
                         FIELD_CX + 300, FIELD_CY + 100));

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

    // The metal kills from the frame it is solid; a charge widens the lethal
    // band only after its warning, and never past the drawn metal.
    st_reset();
    _ring = ring_new(FIELD_CX, FIELD_CY, BCOL_GOLD, 0);
    ok("a ring that is still forming cannot hurt anybody",
       !ring_any_hit(FIELD_CX, FIELD_CY + RING_R, PLAYER_R));
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(undefined);
    ok("...and the moment it is solid, the metal does",
       ring_any_hit(FIELD_CX, FIELD_CY + RING_R, PLAYER_R));
    var _bevel = FIELD_CY + RING_R
                 + (RING_BAND_HALF * RING_KILL_FRAC + RING_BAND_HALF) * 0.5
                 + PLAYER_R;
    ok("cold, the bevel either side of the core is still margin",
       !ring_any_hit(FIELD_CX, _bevel, PLAYER_R));
    ok("riding a cold band pays a graze",
       ring_graze(FIELD_CX,
                  FIELD_CY + RING_R + ring_kill_half(_ring) + PLAYER_R + 2,
                  PLAYER_R) == 1);
    ring_charge(_ring, 20, 30);
    var _bit_during_warning = false;
    for (var _i = 0; _i < 20; _i++) {
        if (_ring.warn > 0 && ring_any_hit(FIELD_CX, _bevel, PLAYER_R)) {
            _bit_during_warning = true;
        }
        ring_step(undefined);
    }
    ok("a charging ring does not widen before its warning is out",
       !_bit_during_warning);
    ok("and then the whole cuff bites",
       ring_any_hit(FIELD_CX, _bevel, PLAYER_R));
    ok("a cold band kills narrower than it is drawn",
       RING_BAND_HALF * RING_KILL_FRAC < ring_band_half());
    ok("...and a charged one no wider",
       ring_kill_half(_ring) <= ring_band_half());
    var _just_outside = FIELD_CY + RING_R + ring_kill_half(_ring)
                        + PLAYER_R + 2;
    ok("...so the black of the cuff is the hitbox",
       !ring_any_hit(FIELD_CX, _just_outside, PLAYER_R));
    _ring.graze_t = 0;
    ok("riding a charged band pays",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 1);
    ok("...and not again on the next frame",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 0);
    for (var _i = 0; _i < RING_GRAZE_CD + 1; _i++) ring_step(undefined);
    ok("...but again once the cooldown is up",
       ring_graze(FIELD_CX, _just_outside, PLAYER_R) == 1);

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
    ring_dismiss(_b, 1);
    ring_step(undefined);
    ring_step(undefined);
    ok("and it goes out with the ring at its far end", !ring_arc_live(_a));
    ok("...so nothing is left lethal in the middle of the field",
       !ring_any_hit(FIELD_CX, FIELD_CY, PLAYER_R));

    // A bullet fired from a moving ring with `ring_rim_at_x/_y` goes live on
    // the metal rather than inside the hole.
    st_reset();
    var _gm = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _mover = ring_new(FIELD_X0 + 300, FIELD_CY, BCOL_GOLD, 0);
    _mover.vx = 4;
    for (var _i = 0; _i < RING_FORM + 1; _i++) ring_step(_gm);
    var _delay = 10;
    var _worst = 0;
    for (var _ang = 0; _ang < 360; _ang += 45) {
        var _u = fire(ring_rim_at_x(_mover, _ang, _delay),
                      ring_rim_at_y(_mover, _ang, _delay), 0, _ang,
                      BSHAPE_PELLET, BCOL_GOLD, _delay);
        for (var _i = 0; _i < _delay; _i++) {
            ring_step(_gm);
            bullet_step(_gm.player.x, _gm.player.y);
        }
        _worst = max(_worst, abs(point_distance(_mover.x, _mover.y,
                                                _u.x, _u.y) - RING_R));
    }
    ok("a bullet fired ahead of a moving ring goes live on its metal",
       _worst < 1);
    st_reset();
}

// ---------------------------------------------------------------------------
// Mika
// ---------------------------------------------------------------------------

function test_mika_slots() {
    var _slots = mika_slots();
    var _ph = mika_phases();
    var _n = array_length(_ph);
    ok("Mika has fifteen attacks", _n == 15
       && _n == MIKA_NONSPELLS + MIKA_SPELLS
       && array_length(_slots) == _n);

    var _order = true;
    for (var _i = 0; _i < _n; _i++) {
        var _want = (_i >= 2 * MIKA_NONSPELLS) || ((_i mod 2) == 1);
        if ((_ph[_i].kind == AttackKind.Spell) != _want) _order = false;
    }
    ok("in the order non-spell, spell, ..., spell, spell", _order);

    ok("the first slot is N1", mika_slot_name(0) == "N1");
    ok("the second is S1", mika_slot_name(1) == "S1");
    ok("the seventh pair is N7 and S7",
       mika_slot_name(12) == "N7" && mika_slot_name(13) == "S7");
    ok("and the last is S8", mika_slot_name(14) == "S8");

    var _scenes = true;
    for (var _i = 0; _i < _n; _i++) {
        var _sc = shot_mika_scene(_i);
        if (shot_mika_slot(_sc) != _i || !shot_scene_known(_sc)) {
            _scenes = false;
        }
    }
    ok("each slot has a screenshot scene, and the scene finds its slot",
       _scenes);
    ok("and a name that is not a slot finds none",
       shot_mika_slot("mika_s9") < 0 && shot_mika_slot("sanctum") < 0);

    // Thresholds are summed from the per-slot `hp` column.
    var _total = mika_hp();
    var _left = _total;
    var _worth = true;
    var _derived = true;
    for (var _i = 0; _i < _n; _i++) {
        if (_slots[_i].hp <= 0) _worth = false;
        _left -= _slots[_i].hp;
        if (abs(_ph[_i].hp_end * _total - _left) > 0.01) _derived = false;
    }
    ok("every slot is worth some of him", _worth);
    ok("each threshold is what is left after its slot", _derived);

    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _e = mika_spawn(_g);
    ok("he spawns with the slots' health summed",
       _e != undefined && _e.hp_max == _total);
    st_reset();
}

/// @desc Mika's sand is bullets drawn small, so each grain's hitbox has to
///       shrink with its drawing.
function test_mika_sand() {
    st_reset();
    var _all = mika_sand_cycles();
    var _honest = true;
    for (var _c = 0; _c < array_length(_all); _c++) {
        for (var _i = 0; _i < array_length(_all[_c]); _i++) {
            var _k = mika_sand_grade(_c, _i);
            var _u = fire(FIELD_CX, FIELD_CY, MIKA_SAND_SPD, 90, BSHAPE_ORB,
                          BCOL_GOLD, 0);
            mika_sand_dress(_u, _k, MIKA_SAND_HOLD, MIKA_SAND_BRAKE,
                            MIKA_SAND_FLOOR, MIKA_SAND_CURL, MIKA_SAND_BEND,
                            MIKA_SAND_LIFE);
            if (_u == undefined || _u.shape != _k.shape
                || abs(_u.r - global.bshape_radius[_k.shape] * _k.scale)
                   > 0.001) {
                _honest = false;
            }
        }
    }
    ok("every grain Mika's rings throw kills at the size it is drawn",
       _honest);
    st_reset();
}

/// @desc Storm Cage's rings and bolts are the only thing between the player
///       and the storm, and a grain that got through would look no different
///       from one that didn't. The player runs a route through the corners
///       and along the walls, alternately flat out and focused, in the order
///       `obj_game` steps things; no grain may ever be inside the triangle
///       between the rings, and the rings, carried past the field's edge,
///       must not be culled. Also reports what the catch costs a frame.
function test_storm_cage() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _p = _g.player;
    var _x0 = FIELD_X0 + FIELD_MARGIN;
    var _x1 = FIELD_X1 - FIELD_MARGIN;
    var _y0 = FIELD_Y0 + FIELD_MARGIN;
    var _y1 = FIELD_Y1 - FIELD_MARGIN;
    var _route = [[_x0, _y1], [_x1, _y1], [FIELD_CX, FIELD_CY], [_x0, _y0],
                  [_x1, _y0], [_x1, _y1], [FIELD_CX, _y1]];
    var _leg = 0;
    var _leaks = 0;
    var _rings_lost = false;
    var _cost = 0;
    var _cost_n = 0;

    for (var _t = 0; _t < 1500; _t++) {
        var _to = _route[_leg mod array_length(_route)];
        var _spd = ((_leg mod 2) == 0) ? PLAYER_SPD : PLAYER_SPD_FOCUS;
        var _d = point_distance(_p.x, _p.y, _to[0], _to[1]);
        if (_d <= _spd) {
            _p.x = _to[0];
            _p.y = _to[1];
            _leg++;
        } else {
            _p.x += (_to[0] - _p.x) / _d * _spd;
            _p.y += (_to[1] - _p.y) / _d * _spd;
        }

        bullet_step(_p.x, _p.y);
        var _t0 = get_timer();
        mika_storm_cage(undefined, _g, _t);
        if (_t >= STORM_START + STORM_RISE) {
            _cost += get_timer() - _t0;
            _cost_n++;
        }
        ring_step(_g);

        if (ring_count() != 3) {
            _rings_lost = true;
            break;
        }
        var _a = ring_get(0);
        var _b = ring_get(1);
        var _c = ring_get(2);
        for (var _i = 0; _i < bullet_count(); _i++) {
            var _u = bullet_get(_i);
            if (_u.shape == STORM_GLASS_SHAPE) continue;
            var _s0 = (_b.x - _a.x) * (_u.y - _a.y)
                      - (_b.y - _a.y) * (_u.x - _a.x);
            var _s1 = (_c.x - _b.x) * (_u.y - _b.y)
                      - (_c.y - _b.y) * (_u.x - _b.x);
            var _s2 = (_a.x - _c.x) * (_u.y - _c.y)
                      - (_a.y - _c.y) * (_u.x - _c.x);
            if ((_s0 > 0 && _s1 > 0 && _s2 > 0)
                || (_s0 < 0 && _s1 < 0 && _s2 < 0)) {
                _leaks++;
            }
        }
    }
    ok("Storm Cage's rings survive being carried past the field's edge",
       !_rings_lost);
    ok("and no grain of its storm gets inside the cage (" + string(_leaks)
       + " did)", !_rings_lost && _leaks == 0);
    show_debug_message("SELFTEST INFO storm cage catch "
                       + string(_cost / max(1, _cost_n) / 1000)
                       + "ms a frame at full strength");
    st_reset();
}

/// @desc `BossMove.Step`: the boss holds still, then hops somewhere else.
function test_boss_step() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _e = { x: FIELD_CX, y: BOSS_HOME_Y,
               boss: { phase: 0, drift_t: 0, track_x: FIELD_CX,
                       home_x: FIELD_CX, home_y: BOSS_HOME_Y,
                       phases: [ { move: BossMove.Step } ] } };
    var _moved_holding = 0;
    var _moved_hopping = 0;
    var _held_true = 0;
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    for (var _f = 0; _f < _cyc * 3; _f++) {
        var _was_x = _e.x;
        var _was_y = _e.y;
        var _holding = boss_holding(_e);
        boss_move(_e, _g, 0);
        var _d = point_distance(_was_x, _was_y, _e.x, _e.y);
        if (_holding) { _held_true++; _moved_holding = max(_moved_holding, _d); }
        else          { _moved_hopping = max(_moved_hopping, _d); }
    }
    ok("a stepping boss holds for the hold and hops for the hop",
       _held_true == BOSS_STEP_HOLD * 3);
    ok("...travels during a hop", _moved_hopping > 1);
    ok("...and is still while it holds", _moved_holding < 1.0);

    var _b = _e.boss;
    var _inside = true;
    for (var _i = 0; _i < 40; _i++) {
        if (boss_step_x(_b, _i) - 130 < FIELD_X0) _inside = false;
        if (boss_step_x(_b, _i) + 130 > FIELD_X1) _inside = false;
    }
    ok("...and never lands off the side of the field", _inside);
    st_reset();
}

// ---------------------------------------------------------------------------
// Stage three's hall
// ---------------------------------------------------------------------------

/// @desc What the sky and the far chamber need from the masonry, the fog and
///       the far plane.
function test_hall_sky() {
    st_reset();
    var _f = (FIELD_H * 0.5) / dtan(HALL_FOV * 0.5);
    var _cam = HALL_CAM_FLY;

    // The parapet's top edge is the steepest line over the nave, so it is what
    // the visible wedge of sky is measured from.
    var _par_y = HALL_CEIL_H + HALL_COPING_H + HALL_PARAPET_H;
    var _slope = (_par_y - _cam) / HALL_PARAPET_X;
    var _cop_y = HALL_CEIL_H + HALL_COPING_H;
    var _cop_x = HALL_HALF_W - HALL_CORN_D - 14;
    ok("the parapet is what the sky is measured from",
       _slope >= (_cop_y - _cam) / _cop_x);

    var _cy = _f * (HALL_ORRERY_Y - _cam) / HALL_ORRERY_Z;
    var _cr = _f * HALL_ORRERY_R / HALL_ORRERY_Z;
    var _half = darctan(1 / _slope);
    ok("the orrery clears the masonry it hangs behind",
       _cy >= _cr / dsin(_half));
    var _vp = _f * dtan(abs(HALL_PITCH_B));
    ok("...and its top is inside the field",
       _cy + _cr + _vp < FIELD_H * 0.5);
    ok("the orrery is further off than the last bay drawn",
       HALL_ORRERY_Z > HALL_BAYS * HALL_BAY_Z);

    // A bay enters the draw loop (HALL_BAYS - 1) bays out, so by then it must
    // be fully fogged and faded, or it pops in.
    ok("the last bay drawn arrives fully fogged",
       (HALL_BAYS - 1) * HALL_BAY_Z >= HALL_FOG_END);
    ok("...and fully faded",
       HALL_FADE_END <= (HALL_BAYS - 1) * HALL_BAY_Z);
    ok("...over a band rather than at a plane",
       HALL_FADE_START < HALL_FADE_END - HALL_BAY_Z);

    ok("the orrery is nearer than the far plane", HALL_ORRERY_Z < HALL_ZFAR);
    ok("the sky dome is inside the frustum",
       HALL_SKY_R > HALL_ZNEAR && HALL_SKY_R < HALL_ZFAR);
    ok("the sky at the horizon is exactly the fog colour",
       hall_sky_col(0) == HALL_FOG);

    // Stars must be out by the wall tops, or the fog's join shows.
    var _sky_el = darctan((HALL_ORRERY_Y - _cam) / HALL_ORRERY_Z);
    ok("a star at the wall-top line is out", hall_star_extinction(0) <= 0.001);
    ok("...and one where the orrery hangs is fully lit",
       hall_star_extinction(_sky_el) > 0.9);

    var _rot_top = _f * (HALL_ROT_Y0 + 2 * HALL_ROT_HH - _cam) / HALL_ROT_Z;
    var _rot_bot = _f * (HALL_ROT_Y0 - _cam) / HALL_ROT_Z;
    ok("the far chamber tops out under the orrery",
       _rot_top < _cy + _cr);
    ok("...and its foot is below the vanishing point", _rot_bot < 0);
    ok("...and it stands behind the orrery",
       HALL_ROT_Z > HALL_ORRERY_Z);
    ok("...past the last bay the hall draws",
       HALL_ROT_Z > HALL_BAYS * HALL_BAY_Z);
    ok("...and inside the far plane", HALL_ROT_Z < HALL_ZFAR);

    var _bw = HALL_BANNER_H * sprite_get_width(spr_hall_banner)
              / sprite_get_height(spr_hall_banner);
    ok("a banner hangs clear of the cornice it hangs under",
       HALL_BANNER_X + _bw * 0.5 < HALL_HALF_W - HALL_CORN_D);
    st_reset();
}

/// @desc The orb in an alcove and the light it casts are at the same place.
function test_hall_orb() {
    st_reset();
    for (var _s = -1; _s <= 1; _s += 2) {
        var _x = hall_orb_x(_s);
        var _mouth = _s * (HALL_HALF_W + HALL_PIL_D);
        var _back = _s * (HALL_HALF_W + HALL_PIL_D + HALL_ALCOVE_D);
        ok("the orb stands inside its own alcove",
           abs(_x) > abs(_mouth) && abs(_x) < abs(_back));
        ok("...clear of the mouth and of the back wall",
           abs(_x) - HALL_ORB_R > abs(_mouth)
           && abs(_x) + HALL_ORB_R < abs(_back));

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

        var _cup = HALL_ORB_Y - HALL_ORB_R;
        ok("the orb sits in its cup rather than over it",
           _cup - HALL_ORB_CRADLE > HALL_PLINTH_H);
        ok("...and the stand stands on the alcove's own sill",
           HALL_ORB_Y - HALL_ORB_R - HALL_ORB_CRADLE - HALL_PLINTH_H > 0);
    }
}

function test_hall_floor() {
    st_reset();
    ok("the runner and its border fit inside the nave",
       HALL_RUNNER_HW + HALL_BORDER_W < HALL_HALF_W);

    // The floor is lit per world point, not per tile, so a course joint is not
    // a light of its own.
    var _z = HALL_BAY_Z * 0.5;
    var _mid = hall_floor_light(0, 0, _z, 1, 0);
    var _wall = hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 0);
    var _seam = hall_floor_light(HALL_RUNNER_HW, 0, _z, 1, 0);
    ok("the joint between two courses is not a light of its own",
       _seam < _wall && _seam > _mid);
    ok("an alcove throws a pool onto the stone in front of it",
       hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 2)
       > hall_floor_light(HALL_HALF_W - 40, 0, _z, 1, 0));
}

/// @desc The review card, which flies the hall with no enemies.
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

/// @desc The frozen pre-rebuild stage three. Delete this with its script.
function test_old_sanctum() {
    var _def = old_stage_sanctum_def();
    ok("the old stage three has no stage to file a clear against",
       _def.id == "");
    ok("it says what it is", stage_is_old_draft(_def));
    ok("...and nothing else claims to be it",
       !stage_is_old_draft(stage_sanctum_def())
       && !stage_is_old_draft(draft_stage_def())
       && !stage_is_old_draft(preview_stage_def())
       && !stage_is_old_draft(undefined));

    var _on_rack = false;
    var _rack = rack_list();
    for (var _i = 0; _i < array_length(_rack); _i++) {
        if (stage_is_old_draft(_rack[_i])) _on_rack = true;
    }
    var _on_roster = false;
    var _roster = stage_list();
    for (var _i = 0; _i < array_length(_roster); _i++) {
        if (stage_is_old_draft(_roster[_i])) _on_roster = true;
    }
    ok("it is on the rack", _on_rack);
    ok("...and not on the roster, which counts stages", !_on_roster);
}

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

/// @desc A bomb sweep spares `resist` bullets and lasers; a phase change
///       clears everything.
function test_spell_resist() {
    st_reset();
    var _r = fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    _r.resist = true;
    fire(500, 500, 0, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    ok("a bomb takes the ordinary bullets",
       bullet_clear_circle(500, 500, 200, false) == 1);
    ok("and leaves the bomb-proof one", bullet_count() == 1);
    ok("which is the one that resisted", bullet_get(0).resist);
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

function test_player() {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_CY);
    var _p = _g.player;
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
    _p.x = GAME_CX; _p.y = GAME_CY;
    player_step(_p, { left: false, right: true, up: false, down: false,
                      shoot: false, bomb: false, focus: true }, _g);
    ok("focus is slower than unfocused",
       point_distance(GAME_CX, GAME_CY, _p.x, _p.y) < _straight);
    _p.x = 5; _p.y = 5;
    player_step(_p, { left: true, right: false, up: true, down: false,
                      shoot: false, bomb: false, focus: false }, _g);
    ok("the player is held inside the field",
       _p.x >= FIELD_MARGIN - 0.01 && _p.y >= FIELD_MARGIN - 0.01);

    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    ok("a hit costs HP_PER_HIT",
       player_hit(_p) && _p.hp == HP_MAX - HP_PER_HIT);
    ok("and grants invulnerability", player_invulnerable(_p));
    ok("a second hit inside the grace does nothing", !player_hit(_p));
    ok_near("the grace lasts IFRAME_TIME", _p.iframe, IFRAME_TIME, 1);
    var _hits = 1;
    while (_p.alive && _hits < 100) {
        _p.iframe = 0;
        player_hit(_p);
        _hits++;
    }
    ok("enough hits end the run", !_p.alive && _p.hp <= 0);

    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    _p.mp = MP_MAX;
    fire_ring(_p.x, _p.y, 60, 0.1, 0, BSHAPE_ORB, BCOL_CRIMSON, 0);
    var _before = bullet_count();
    player_bomb(_p, _g);
    for (var _i = 0; _i < BOMB_GROW + 2; _i++) player_bomb_sweep(_p);
    ok("a special costs MP_PER_BOMB", _p.mp == MP_MAX - MP_PER_BOMB);
    ok("and sweeps the bullets around him", bullet_count() < _before);
    ok("and grants grace", player_invulnerable(_p));

    // A special pressed on the same frame a bullet arrives wins.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_CY);
    _p = _g.player;
    _p.mp = MP_MAX;
    fire(_p.x, _p.y, 0, 0, BSHAPE_BALL, BCOL_CRIMSON, 0);
    player_step(_p, { left: false, right: false, up: false, down: false,
                      shoot: false, bomb: true, focus: false }, _g);
    player_collide(_p, _g);
    ok("a special on the frame of a hit beats the hit", _p.hp == HP_MAX);
    ok("a special is counted once", _p.bomb_n == 1);
    for (var _i = 0; _i < BOMB_INVULN - 2; _i++) {
        player_step(_p, { left: false, right: false, up: false, down: false,
                          shoot: false, bomb: true, focus: false }, _g);
    }
    ok("...and holding the key through its grace does not count it again",
       _p.bomb_n == 1);
    st_reset();
}

function test_bomb_seals() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY + 200);
    var _p = _g.player;
    _p.mp = MP_MAX;
    player_bomb(_p, _g);
    ok("no seal is in the air on the frame of the cast",
       player_seals_live(_p) == 0);
    ok("and the close-up is", _p.card_t == PLAYER_CARD_TIME);
    var _launched = -1;
    for (var _f = 0; _f < BOMB_INVULN; _f++) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
        player_seals_step(_p);
        if (_launched < 0 && player_seals_live(_p) > 0) _launched = _f;
    }
    ok("the seals leave at BOMB_SEAL_AT", _launched == BOMB_SEAL_AT - 1);

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

function test_grace_dial() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _p = _g.player;
    ok("no grace to begin with", player_grace_left(_p) == 0);
    player_hit(_p);
    ok("a hit gives the dial its full sweep",
       _p.grace_max == IFRAME_TIME
       && player_grace_left(_p) == IFRAME_TIME);

    // A hit's grace and a bomb's overlap rather than add.
    _p.mp = MP_MAX;
    player_bomb(_p, _g);
    ok("a bomb inside a grace keeps the longer of the two",
       player_grace_left(_p) == max(IFRAME_TIME - 0, BOMB_INVULN));
    ok("and the dial never reads over full",
       player_grace_left(_p) <= _p.grace_max);

    ok_near("the low-life heartbeat joins up across its wrap",
            player_heartbeat(LOW_HP_BEAT), player_heartbeat(0), 0.02);
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

/// @desc The harness-only flag a posed screenshot uses, so a hit cannot clear
///       part of the pattern being photographed.
function test_untouchable() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _p = _g.player;
    fire_ring(_p.x, _p.y, 24, 0.01, 0, BSHAPE_ORB, BCOL_AZURE, 0);
    var _wall = bullet_count();
    ok("there is something to be hit by", _wall >= 20);

    _p.untouchable = true;
    ok("an untouchable player cannot be touched", player_invulnerable(_p));
    ok("and a hit on one does nothing", !player_hit(_p));
    ok("so it keeps its health", _p.hp == HP_MAX);
    ok("and nothing is swept off the field", bullet_count() == _wall);

    _p.untouchable = false;
    _p.iframe = 0;
    ok("an ordinary player is touchable", !player_invulnerable(_p));
    ok("and a hit on one lands", player_hit(_p));
    ok("and costs health", _p.hp < HP_MAX);
    ok("and clears what was on top of them", bullet_count() < _wall);
    ok("a fresh player is not untouchable", !player_new().untouchable);
    st_reset();
}

// ---------------------------------------------------------------------------
// Bosses and stages
// ---------------------------------------------------------------------------

/// @desc Every boss table on the rack is well formed: thresholds strictly
///       descend to exactly zero, every spell has a name, every attack has a
///       clock and a function, and each call builds a fresh table (phase
///       structs are mutable).
function test_phase_tables() {
    var _rack = rack_list();
    var _bad = "";
    var _tables = 0;
    for (var _s = 0; _s < array_length(_rack); _s++) {
        var _bosses = _rack[_s][$ "bosses"];
        if (_bosses == undefined) continue;
        for (var _b = 0; _b < array_length(_bosses); _b++) {
            var _name = _bosses[_b].name;
            var _ph = _bosses[_b].phases();
            var _n = array_length(_ph);
            _tables++;
            if (_n == 0) {
                _bad += _name + " (empty) ";
                continue;
            }
            if (_ph == _bosses[_b].phases()) _bad += _name + " (shared) ";
            var _prev = 1.0;
            for (var _i = 0; _i < _n; _i++) {
                var _p = _ph[_i];
                var _at = _name + " #" + string(_i + 1);
                if (_p.hp_end >= _prev) _bad += _at + " (does not descend) ";
                if (_p.kind == AttackKind.Spell && _p.name == "") {
                    _bad += _at + " (unnamed spell) ";
                }
                if (_p.time <= 0) _bad += _at + " (no clock) ";
                if (!is_callable(_p.attack)) _bad += _at + " (no attack) ";
                _prev = _p.hp_end;
            }
            if (_ph[_n - 1].hp_end != 0) {
                _bad += _name + " (does not end at zero) ";
            }
        }
    }
    ok("every boss table on the rack is well formed (" + string(_tables)
       + " tables) " + _bad, _tables > 0 && _bad == "");
}

function test_boss_phases() {
    var _zp = ziggy_phases();
    var _plain = 0;
    while (_plain < array_length(_zp)
           && _zp[_plain].kind != AttackKind.NonSpell) _plain++;
    var _spell = 0;
    while (_spell < array_length(_zp)
           && _zp[_spell].kind != AttackKind.Spell) _spell++;

    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _b = ziggy_spawn(_g);
    ok("the boss reaches the field", _b != undefined);
    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    boss_enter_phase(_b, _g, _plain);
    ok("it enters the attack it is given", _b.boss.phase == _plain);
    ok("and is vulnerable once it has", boss_vulnerable(_b));
    ok("a non-spell holds nothing back", _b.boss.lead_t == 0);

    // A spell is declared before it fires, and the boss can't be hurt then.
    st_reset();
    boss_enter_phase(_b, _g, _spell);
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
    var _steps = 0;
    var _seen = 0;
    while (!_b.boss.beaten && _steps < 40000) {
        _b.hp -= 40;
        boss_act(_b, _g);
        if (_b.boss.clear_t > 1) _b.boss.clear_t = 1;
        _steps++;
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

    // A timeout ends the attack and pulls the bar down to its threshold.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _b = ziggy_spawn(_g);
    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    boss_enter_phase(_b, _g, _plain);
    for (var _i = 0; _i < _zp[_plain].time + 2; _i++) boss_act(_b, _g);
    ok("running the clock out ends the attack", _b.boss.clear_t > 0);
    ok("and pulls the bar down to the threshold",
       _b.hp <= _b.hp_max * _zp[_plain].hp_end + 0.001);
    st_reset();
}

function st_still(_e, _g, _t) {}

/// @desc A Ziggy whose table is one idle attack moving by `_move`.
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

function test_boss_move() {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _zb = st_boss_on_move(_g, BossMove.Drift);
    _zb.boss.phases = [{
        kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
        hp_end: 0.0, time: 1000000, attack: st_still,
    }];
    ok("an attack that names no movement drifts",
       boss_move_kind(_zb.boss, 0) == BossMove.Drift);
    ok("and so does the ceremony either side of the table",
       boss_move_kind(_zb.boss, -1) == BossMove.Drift
       && boss_move_kind(_zb.boss, 1) == BossMove.Drift);

    st_reset();
    _g = st_game_at(FIELD_X0 + FIELD_MARGIN, GAME_H - 300);
    var _b = st_boss_on_move(_g, BossMove.Fixed);
    _b.x = FIELD_X0 + 100;
    _b.y = FIELD_Y0 + 700;
    for (var _i = 0; _i < 240; _i++) boss_act(_b, _g);
    ok("a fixed attack takes its station",
       abs(_b.x - _b.boss.home_x) < 2 && abs(_b.y - _b.boss.home_y) < 2);
    var _lo = _b.x, _hi = _b.x;
    for (var _i = 0; _i < 600; _i++) {
        boss_act(_b, _g);
        _lo = min(_lo, _b.x);
        _hi = max(_hi, _b.x);
    }
    ok("and holds it", _hi - _lo < 1);
    ok("whatever the player does", abs(_b.x - _b.boss.home_x) < 2);

    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _b = st_boss_on_move(_g, BossMove.Close);
    var _far = 0;
    for (var _i = 0; _i < 900; _i++) {
        boss_act(_b, _g);
        _far = max(_far, abs(_b.x - _b.boss.home_x));
    }
    ok("a close attack keeps to its station", _far <= BOSS_CLOSE_X + 2);

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
    var _inside = true;
    for (var _i = 0; _i < 1200; _i++) {
        _g.player.x = ((_i div 300) mod 2 == 0)
            ? FIELD_X0 + FIELD_MARGIN : FIELD_X1 - FIELD_MARGIN;
        boss_act(_b, _g);
        if (_b.x < FIELD_X0 + BOSS_TRACK_EDGE - 1
            || _b.x > FIELD_X1 - BOSS_TRACK_EDGE + 1) _inside = false;
    }
    ok("and never carries itself off the side of the field", _inside);

    // An attack that starts tracking picks up from where the boss is.
    st_reset();
    _g = st_game_at(FIELD_X0 + FIELD_MARGIN, GAME_H - 300);
    _b = st_boss_on_move(_g, BossMove.Track);
    for (var _i = 0; _i < 900; _i++) boss_act(_b, _g);
    _b.boss.phases[0].move = BossMove.Fixed;
    for (var _i = 0; _i < 400; _i++) boss_act(_b, _g);
    _b.boss.phases[0].move = BossMove.Track;
    var _was = _b.x;
    boss_act(_b, _g);
    ok("and picks up from where the boss is rather than lurching",
       abs(_b.x - _was) < 20);

    // The pause between attacks is where a boss moves to its next station.
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
    _b.hp = _b.hp_max * 0.5;
    boss_act(_b, _g);
    ok("breaking it opens the pause", _b.boss.clear_t > 0);
    while (_b.boss.clear_t > 0) boss_act(_b, _g);
    ok("and the fixed attack opens already on its station",
       _b.boss.phase == 1 && abs(_b.x - _b.boss.home_x) < 8);
    st_reset();
}

/// @desc Every card on the rack with a timeline has it in order, with an
///       action on every event.
function test_stage_table() {
    var _list = stage_list();
    ok("stage one is built and needs nothing to unlock",
       stage_is_built(_list[0]) && _list[0].needs == 0);

    var _rack = rack_list();
    var _bad = "";
    var _checked = 0;
    for (var _s = 0; _s < array_length(_rack); _s++) {
        var _def = _rack[_s];
        if (!stage_is_built(_def)) continue;
        var _e = _def.build();
        _checked++;
        for (var _i = 0; _i < array_length(_e); _i++) {
            if (_i > 0 && _e[_i].at < _e[_i - 1].at) {
                _bad += _def.name + " (out of order) ";
                break;
            }
            if (!_e[_i].gate && _e[_i].fn == undefined) {
                _bad += _def.name + " (an event with no action) ";
                break;
            }
        }
    }
    ok("every timeline on the rack is in order, with an action on every "
       + "event " + _bad, _checked > 0 && _bad == "");
}

/// @desc Each stage played headless, killing each wave a second after it
///       arrives, reaches its end and puts a boss on the field on the way.
function test_stage_run() {
    st_stage_run(stage_ziggy_def(), "the stage");
    st_stage_run(stage_grove_def(), "stage two");
    st_stage_run(stage_sanctum_def(), "stage three");
    st_stage_run(old_stage_sanctum_def(), "the old stage three");
}

function st_stage_run(_def, _label) {
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.boss_ref = undefined;
    _g.phase = Phase.Playing;
    _g.bg = _def.make_bg();
    var _s = stage_new(_def);
    var _boss_seen = false;
    for (var _i = 0; _i < 12000; _i++) {
        stage_step(_s, _g);
        if ((_i mod 70) == 0) enemy_sweep_fodder(_g);
        if (_g.boss_ref != undefined) {
            _boss_seen = true;
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
    ok(_label + " grades the groups of waves it contains",
       rank_count(_g.marks) > 0);
    st_reset();
}

// ---------------------------------------------------------------------------
// Stage two's corridor
// ---------------------------------------------------------------------------

function test_corridor() {
    // The projection: a ground row and a prop's footing agree on depth, and
    // the horizon reports the far plane rather than dividing by zero.
    var _v = corridor_view(false);
    var _hy = corridor_horizon(_v);
    var _agree = true;
    for (var _i = 1; _i <= 6; _i++) {
        var _z = 300 * _i;
        var _sy = _hy + corridor_k(_z) * CORRIDOR_CAM_H;
        if (abs(corridor_depth_at(_v, _sy) - _z) > 0.5) _agree = false;
    }
    ok("the ground's depth and a prop's footing agree", _agree);
    ok("the horizon is the far plane, not a divide by zero",
       corridor_depth_at(_v, _hy) == CORRIDOR_Z_FAR);
    ok("and nothing under it reports further than that",
       corridor_depth_at(_v, _hy + 1) <= CORRIDOR_Z_FAR
       && corridor_depth_at(_v, _hy + 0.2) <= CORRIDOR_Z_FAR);

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

    // A band's wave only pushes it down (lifting it would show sky under the
    // wood), and stays periodic in its tile so the band still tiles.
    var _lifts = false;
    var _over = false;
    for (var _i = 0; _i <= 240; _i++) {
        var _wv = corridor_band_wave(_i / 240, GROVE_RIDGE_H, 137);
        if (_wv < 0) _lifts = true;
        if (_wv > GROVE_RIDGE_H + 0.001) _over = true;
    }
    var _vc = corridor_view(false, 0);
    ok("a band's dip is whole on the centre line and gone past its width",
       corridor_band_dip(_vc, _vc.cx, GROVE_SCRUB_DIP_W) == 1
       && corridor_band_dip(_vc, _vc.cx + GROVE_SCRUB_DIP_W + 1,
                            GROVE_SCRUB_DIP_W) == 0);
    ok("the ridge dips the far wood's foot and never lifts it", !_lifts);
    ok("and never further than it was asked to", !_over);
    ok("and it is periodic in its own tile, so the band still tiles",
       abs(corridor_band_wave(0, GROVE_RIDGE_H, 137)
           - corridor_band_wave(1, GROVE_RIDGE_H, 137)) < 0.001);

    var _half_w = corridor_prop_half_w(spr_scn_tree, GROVE_TREE_H,
                                       1 + GROVE_VARY_H, 1 + GROVE_VARY_W);
    var _edge = corridor_k(CORRIDOR_Z_NEAR) * (GROVE_PATH_HALF - _half_w);
    ok("a tree is off the side of the field before it reaches the camera",
       _edge > FIELD_W * 0.5);

    // `frac` keeps its sign, so the hash has to be folded into [0, 1).
    var _in_range = true;
    var _spread = 0;
    for (var _i = 0; _i < 400; _i++) {
        var _h = corridor_hash(_i, 17);
        if (_h < 0 || _h >= 1) _in_range = false;
        if (_h > 0.5) _spread++;
    }
    ok("the hash answers in [0, 1)", _in_range);
    ok("and does not pile up in one half", _spread > 140 && _spread < 260);

    // The arrival, and the swell on the flight's speed.
    var _i0 = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 5; _f++) bg_step(_i0);
    ok("the fog has lifted by the end of the arrival", _i0.intro == 1);
    ok_near("and the flight settles at exactly the speed it was asked for",
            _i0.spd, GROVE_SPEED, 0.001);
    var _lo = 999999999;
    var _sum = 0;
    for (var _f = 0; _f < GROVE_SWELL * 4; _f++) {
        bg_step(_i0);
        _lo = min(_lo, _i0.rush);
        _sum += _i0.rush;
    }
    ok("the swell never puts the corridor into reverse", _lo > 0);
    ok_near("and four swells travel what four flat ones would",
            _sum / (GROVE_SWELL * 4), GROVE_SPEED, GROVE_SPEED * 0.03);
    ok("and the camera stays inside its own throw",
       abs(_i0.cam_x) <= GROVE_SWAY + 0.001
       && abs(_i0.cam_y) <= GROVE_RISE + 0.001);

    // Steering: the camera leans toward the player's side of the field,
    // capped per frame.
    var _lf = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_lf, 0);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, -1);
    ok("a player at the left wall slides the camera left",
       _lf.lean < -GROVE_LEAN * 0.9);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, 1);
    ok("and one at the right wall slides it right",
       _lf.lean > GROVE_LEAN * 0.9);
    for (var _f = 0; _f < 900; _f++) bg_step(_lf, 0);
    ok("and the middle of the field is straight ahead",
       abs(_lf.lean) < GROVE_LEAN * 0.05);
    var _lr = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 4; _f++) bg_step(_lr, 1);
    var _was_l = _lr.lean;
    var _jerk = 0;
    for (var _f = 0; _f < 400; _f++) {
        bg_step(_lr, ((_f mod 2) == 0) ? -1 : 1);
        _jerk = max(_jerk, abs(_lr.lean - _was_l));
        _was_l = _lr.lean;
    }
    ok("and nothing the player does moves it faster than its cap",
       _jerk <= GROVE_LEAN_SPD + 0.0001);
    var _ln = bg_grove();
    for (var _f = 0; _f < GROVE_INTRO_TIME + 400; _f++) bg_step(_ln);
    ok("and a screen with no player on it does not steer", _ln.lean == 0);

    // Horizon bands follow the camera and nothing else. The canopy and the far
    // wood are at different depths, so steering parts them.
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
    ok("a rooted band travels nowhere over half a minute",
       (_rhi - _rlo) <= GROVE_SWAY * 2 + 0.001);
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, -1);
    var _vl = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    var _part_l = grove_rooted_x(_vl, 0, 700)
                  - grove_rooted_x(_vl, 0, CORRIDOR_Z_FAR);
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, 1);
    var _vr = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    var _part_r = grove_rooted_x(_vr, 0, 700)
                  - grove_rooted_x(_vr, 0, CORRIDOR_Z_FAR);
    ok("the canopy parts from the far wood one way at each wall",
       (_part_l < 0) != (_part_r < 0));
    for (var _f = 0; _f < 900; _f++) bg_step(_rb, 0);
    var _vm = corridor_view(false, _rb.cam_x, _rb.cam_y, _rb.lat);
    ok("and the two sit together when the player is on the centre line",
       abs(grove_rooted_x(_vm, 0, 700)
           - grove_rooted_x(_vm, 0, CORRIDOR_Z_FAR)) < 1);

    var _pl = player_new();
    _pl.x = FIELD_X0;
    ok("the left wall reads as -1", player_field_aim(_pl) == -1);
    _pl.x = FIELD_X1;
    ok("and the right wall as +1", player_field_aim(_pl) == 1);
    _pl.x = FIELD_CX;
    ok("and the centre line as nothing", player_field_aim(_pl) == 0);

    // The ring buffers: props stay in depth order however long the flight.
    var _b = bg_grove();
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

    // Every ring is found by walking the struct, so a ring added later is
    // checked without being named here.
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
    ok("the grove has rings of props to check", _rings > 0);
    var _clear = "";
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _cv = _c2[$ _names[_i]];
        if (!is_struct(_cv) || !variable_struct_exists(_cv, "props")) continue;
        if (corridor_haze(_cv.z1) > CORRIDOR_ARRIVE_HAZE) {
            _clear += _names[_i] + " ";
        }
    }
    ok("no ring recycles its props into clear air " + _clear, _clear == "");

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
    var _walled = false;
    for (var _j = 0; _j < _c2.trunks.n; _j++) {
        var _tp = _c2.trunks.props[_j];
        var _thw = corridor_prop_half_w(spr_scn_trunk, GROVE_TRUNK_H,
                                        _tp.scale, _tp.aspect);
        if (abs(_tp.wx) - _thw < GROVE_TRUNK_HALF - 1) _walled = true;
    }
    ok("and no trunk stands closer to the path than its clearance",
       !_walled);

    // All rings are drawn in one merged far-to-near pass.
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
    var _prev_z = 999999999;
    for (var _i = 0; _i < _c2.merge.total; _i++) {
        var _mp = _c2.merge.out[_i];
        if (_mp == undefined || _mp.z > _prev_z + 0.001) _mono = false;
        _prev_z = (_mp == undefined) ? _prev_z : _mp.z;
    }
    ok("and it is in one depth order, far to near", _mono);
    ok("and every ring is being stepped " + _stalled, _stalled == "");

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

/// @desc A primitive textured with `sprite_get_texture` reads UVs in the
///       sprite's own 0-1 space. Draws a band both ways and compares pixels.
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

/// @desc Stage two's turn: it runs once, and the red travels down the
///       corridor by depth.
function test_grove_turn() {
    var _b = bg_grove();
    ok("a stage opens with nothing having happened", _b.omen == 0);
    ok("and the wave is past the far end of the corridor",
       grove_blood_at(_b, CORRIDOR_Z_FAR) == 0);
    bg_set_omen(_b);
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) bg_step(_b);
    ok("the turn reaches exactly one and stops", _b.omen == 1);
    for (var _f = 0; _f < 60; _f++) bg_step(_b);
    ok("and stays there", _b.omen == 1);
    ok("and the corridor runs at the speed the turn asks for",
       abs(_b.spd - GROVE_SPEED_FAST) < 0.01);

    var _c = bg_grove();
    bg_set_omen(_c);
    var _far_leads = true;
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) {
        bg_step(_c);
        if (grove_blood_at(_c, 4200) < grove_blood_at(_c, 400)) {
            _far_leads = false;
        }
    }
    ok("the far wood turns before the near wood does", _far_leads);
    ok("by the end the whole corridor has turned",
       grove_blood_at(_c, CORRIDOR_Z_FAR) == 1
       && grove_blood_at(_c, CORRIDOR_Z_NEAR) == 1);

    var _d = bg_grove();
    bg_set_omen(_d);
    var _high = 0;
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) {
        bg_step(_d);
        _high = max(_high, grove_eclipse(_d));
    }
    ok("the umbra crosses the moon completely", _high >= 0.999);

    var _brim = bg_brimstone();
    ok("a parallax stage starts unturned", _brim.omen == 0);
    bg_set_omen(_brim);
    for (var _f = 0; _f < BG_OMEN_TIME; _f++) bg_step(_brim);
    ok("and turns harmlessly when asked", _brim.omen == 1 && _brim.t > 0);
}

// ---------------------------------------------------------------------------
// Grading
// ---------------------------------------------------------------------------

function test_marks() {
    var _named = true;
    for (var _i = 0; _i < Mark.Count; _i++) {
        if (mark_name(_i) == "--") _named = false;
    }
    ok("every tier on the ladder is named", _named);

    // The standing is the mean mark rounded half up. GML's `round` rounds
    // halves to even, so a tie is tested at two rungs.
    var _led = rank_ledger_new();
    ok("an unmarked attempt has no standing at all", rank_overall(_led) == -1);
    ok("and an unmarked attempt is not a perfect one", !rank_is_perfect(_led));
    for (var _i = 0; _i < 5; _i++) rank_note(_led, "x", Mark.Gold);
    ok("five golds is a gold standing", rank_overall(_led) == Mark.Gold);
    rank_note(_led, "x", Mark.Stone);
    ok("and one stone among five golds lands on a tie, which goes up",
       rank_overall(_led) == Mark.Gold);
    rank_note(_led, "x", Mark.Stone);
    ok("but a second one pulls the standing down",
       rank_overall(_led) < Mark.Gold);
    ok("the ledger counts what it was given", rank_count(_led) == 7);
    var _half_lo = rank_ledger_new();
    rank_note(_half_lo, "x", Mark.Silver);
    rank_note(_half_lo, "x", Mark.Gold);
    var _half_hi = rank_ledger_new();
    rank_note(_half_hi, "x", Mark.Gold);
    rank_note(_half_hi, "x", Mark.Amethyst);
    ok("a standing exactly between two rungs takes the higher one",
       rank_overall(_half_lo) == Mark.Gold
       && rank_overall(_half_hi) == Mark.Amethyst);

    // ABSOLUTE AMETHYST is a standing, not a sixth tier.
    var _pf = rank_ledger_new();
    for (var _i = 0; _i < 4; _i++) rank_note(_pf, "x", Mark.Amethyst);
    ok("every encounter at the top is a perfect standing",
       rank_is_perfect(_pf) && rank_overall_name(_pf) == "ABSOLUTE AMETHYST");
    rank_note(_pf, "x", Mark.Gold);
    ok("and one gold among them is not",
       !rank_is_perfect(_pf) && rank_overall(_pf) == Mark.Amethyst);
    ok("...which the standing can still reach on its own",
       rank_overall_name(_pf) == "AMETHYST");

    // Clean is GOLD; a hit costs two rungs, a sigil one; the threshold adds
    // one.
    ok("clean but under the threshold is the base rung",
       rank_for_encounter(0, 0, false) == RANK_BASE);
    ok("clean and over it is the top",
       rank_for_encounter(0, 0, true) == Mark.Amethyst);
    ok("a hit costs more than a sigil",
       rank_for_encounter(1, 0, false) < rank_for_encounter(0, 1, false));
    ok("and the threshold is worth exactly one sigil",
       rank_for_encounter(0, 1, true) == rank_for_encounter(0, 0, false));
    ok("two hits bottoms out and cannot go below it",
       rank_for_encounter(2, 0, false) == Mark.Stone
       && rank_for_encounter(9, 9, false) == Mark.Stone);

    var _surv = { kind: AttackKind.Spell, time: 30 * FPS, name: "S" };
    ok("a survival spell has a target it can reach",
       rank_attack_target(_surv, 0) > 0
       && rank_attack_target(_surv, 0) < 1000000);
    var _short = { kind: AttackKind.Spell, time: 10 * FPS, name: "S" };
    var _long = { kind: AttackKind.Spell, time: 40 * FPS, name: "L" };
    ok("a longer attack asks for more grazing",
       rank_attack_target(_long, 0) > rank_attack_target(_short, 0));
    ok("and a row may name its own target",
       rank_attack_target({ kind: AttackKind.Spell, time: 40 * FPS,
                            name: "X", score: 1234 }, 0) == 1234);

    // Par: an attack broken by its par meets its target on speed alone, and
    // each second past par asks the graze rate. `_short_by` is what is left
    // to earn by grazing when the attack is broken at frame `_at`.
    var _row = { kind: AttackKind.Spell, name: "M", time: 60 * FPS };
    var _span = 300;
    var _par = rank_attack_par(_row, _span);
    var _left = [_par, _par * 0.5, _par + 10 * FPS];
    var _short_by = [];
    for (var _k = 0; _k < 3; _k++) {
        _short_by[_k] = rank_attack_target(_row, _span) - TALLY_SPELL_CLEAR
                        - rank_speed_award(_row, 1 - _left[_k] / _row.time);
    }
    ok("an attack broken at its par needs no grazing",
       _par > 0 && _par < _row.time && abs(_short_by[0]) < 0.01);
    ok("nor does one broken sooner", _short_by[1] < 0);
    ok("each second past par asks the graze rate",
       abs(_short_by[2] / 10 / TALLY_GRAZE - RANK_GRAZE_RATE) < 0.001);
    ok("more health gives a later par",
       rank_attack_par(_row, 2 * _span) > _par);
    ok("par never runs past the clock",
       rank_attack_par(_row, 1000000) == _row.time);
    ok("and a row may set its own par",
       rank_attack_par({ kind: AttackKind.Spell, name: "P", time: 60 * FPS,
                         par: 600 }, _span) == 600);
    ok("a timeout can't meet its target",
       rank_attack_expired(_row, false) && !rank_attack_expired(_row, true));
    ok("unless the attack is a survival attack",
       !rank_attack_expired({ kind: AttackKind.Spell, name: "V",
                              time: 60 * FPS, survival: true }, false));

    // Par is priced on a volley's damage, so the volley has to be what
    // `rank_full_fire` thinks it is.
    st_reset();
    player_fire(player_new());
    ok("a volley is PSHOT_BARRELS shots", pshot_count() == PSHOT_BARRELS);

    ok("a wave is passed by killing most of it, without grazing",
       rank_wave_target(5000) > 0 && rank_wave_target(5000) < 5000);

    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _e = boss_spawn(FIELD_CX, FIELD_Y0 + 300, 1000, ziggy_phases(),
                        ziggy_def());
    _e.boss.entry_t = 0;
    _e.boss.declare_t = 0;
    _e.boss.started = true;
    boss_enter_phase(_e, _g, 0);
    var _before = rank_count(_g.marks);
    boss_end_phase(_e, _g, true);
    ok("beating an attack files a mark",
       rank_count(_g.marks) == _before + 1);
    ok("and the run now has a standing", rank_overall(_g.marks) >= 0);

    // Through the real end of an attack, clean and with no graze: broken fast
    // is the top mark; broken at the last moment is not; a timeout is not,
    // even on an attack whose par reaches its clock (so its target is only
    // the clear award, which the timeout still pays); and a survival attack
    // that is outlasted can be.
    var _tiers = [];
    var _hp = [400, 400, 100000, 100000];
    var _at = [1, 40 * FPS - 1, 40 * FPS, 40 * FPS];
    var _broken = [true, true, false, false];
    var _surv = [false, false, false, true];
    for (var _k = 0; _k < 4; _k++) {
        st_reset();
        var _gk = st_game_at(FIELD_CX, FIELD_Y1 - 200);
        var _ek = boss_spawn(FIELD_CX, FIELD_Y0 + 300, _hp[_k],
                             [{ kind: AttackKind.Spell, name: "RACE",
                                col: BCOL_GOLD, bg: -1, hp_end: 0,
                                time: 40 * FPS, move: BossMove.Fixed,
                                attack: st_attack_idle,
                                survival: _surv[_k] }],
                             ziggy_def());
        _ek.boss.entry_t = 0;
        _ek.boss.declare_t = 0;
        _ek.boss.started = true;
        boss_enter_phase(_ek, _gk, 0);
        _ek.boss.phase_t = _at[_k];
        if (_broken[_k]) _ek.hp = 0;
        boss_end_phase(_ek, _gk, _broken[_k]);
        _tiers[_k] = _gk.marks.marks[0].tier;
    }
    ok("a spell broken clean and fast is the top mark without a graze",
       _tiers[0] == Mark.Amethyst);
    ok("and one broken clean at the last moment is the base rung",
       _tiers[1] == RANK_BASE);
    ok("and so is a timeout, even one whose par reaches the clock",
       rank_attack_par({ time: 40 * FPS }, 100000) == 40 * FPS
       && _tiers[2] == RANK_BASE);
    ok("but an outlasted survival attack over its target is the top mark",
       _tiers[3] == Mark.Amethyst);

    // The capture bonus is paid after the mark is filed, so it cannot lift
    // the mark over its own threshold.
    st_reset();
    var _g2 = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _e2 = boss_spawn(FIELD_CX, FIELD_Y0 + 300, 1000,
                         [{ kind: AttackKind.Spell, name: "CAPTURE ME",
                            col: BCOL_GOLD, bg: -1, hp_end: 0,
                            time: 40 * FPS, move: BossMove.Fixed,
                            attack: st_attack_idle,
                            score: TALLY_SPELL_CLEAR
                                   + rank_graze_worth(40 * FPS) + 1 }],
                         ziggy_def());
    _e2.boss.entry_t = 0;
    _e2.boss.declare_t = 0;
    _e2.boss.started = true;
    boss_enter_phase(_e2, _g2, 0);
    boss_end_phase(_e2, _g2, true);
    ok("a captured spell is still marked against its own threshold",
       _e2.boss.captured == 1 && _g2.marks.marks[0].tier == RANK_BASE);
    st_reset();
}

function st_attack_idle(_e, _g, _t) {
}

/// @desc A group of waves is graded as the window during which fodder is on
///       the field.
function test_wave_marks() {
    var _def = {
        id: "",
        name: "T",
        subtitle: "t",
        needs: 0,
        make_bg: bg_brimstone,
        build: st_wave_script,
    };

    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _g.boss_ref = undefined;
    _g.phase = Phase.Playing;
    var _s = stage_new(_def);
    ok("a stage counts its own encounters before it runs", _s.encounters == 1);
    for (var _i = 0; _i < 20; _i++) stage_step(_s, _g);
    ok("fodder arriving opens one", _s.enc != undefined);
    ok("and nothing is filed while it is open", rank_count(_g.marks) == 0);
    enemy_sweep_fodder(_g);
    stage_step(_s, _g);
    ok("and the field clearing closes it", _s.enc == undefined);
    ok("filing exactly one mark", rank_count(_g.marks) == 1);
    ok("clean but unscored is the base rung",
       _g.marks.marks[0].tier == RANK_BASE);
    ok("labelled as the wave it was", _g.marks.marks[0].label == "WAVE 1");
    ok("and a wave is never a spell", !_g.marks.marks[0].spell);

    st_reset();
    var _g2 = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _g2.boss_ref = undefined;
    _g2.phase = Phase.Playing;
    _g2.player.hit_n = 7;
    var _s2 = stage_new(_def);
    for (var _i = 0; _i < 20; _i++) stage_step(_s2, _g2);
    _g2.player.hit_n++;
    enemy_sweep_fodder(_g2);
    stage_step(_s2, _g2);
    ok("only the hits taken inside the window count",
       rank_count(_g2.marks) == 1
       && _g2.marks.marks[0].tier == RANK_BASE - RANK_HIT_COST);

    st_reset();
    var _g3 = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _g3.boss_ref = { x: 0, y: 0 };
    _g3.phase = Phase.Playing;
    var _s3 = stage_new(_def);
    for (var _i = 0; _i < 20; _i++) stage_step(_s3, _g3);
    ok("no encounter opens while a boss holds the field", _s3.enc == undefined);
    st_reset();
}

function st_wave_script() {
    var _e = [];
    array_push(_e, ev(2, wave_cross(EnemyKind.Wisp, 4, -1, 200, 40,
                                    5.0, 3, BCOL_EMBER, undefined)));
    array_push(_e, ev_gate(10));
    return _e;
}

/// @desc The console's socket count: a stage counts its groups of waves as
///       well as its attacks.
function test_stage_encounters() {
    var _list = stage_list();
    var _bad = "";
    for (var _d = 0; _d < array_length(_list); _d++) {
        var _def = _list[_d];
        if (!stage_is_built(_def)) continue;
        var _s = stage_new(_def);
        var _attacks = 0;
        var _bosses = _def[$ "bosses"] ?? [];
        for (var _i = 0; _i < array_length(_bosses); _i++) {
            _attacks += array_length(_bosses[_i].phases());
        }
        if (!(_attacks > 0 && _s.encounters > _attacks)) {
            _bad += _def.name + " ";
        }
    }
    ok("every stage counts its waves as well as its attacks " + _bad,
       _bad == "");
    ok("a card that names its own count keeps it",
       stage_new(preview_stage_def()).encounters == 1);
}

function test_rank_card() {
    var _c = rank_card_new();
    ok("a fresh card is not on screen", !rank_card_live(_c));

    var _led = rank_ledger_new();
    rank_note(_led, "WAVE 2", Mark.Gold, false, 18400, 15000, 0, 1);
    rank_card_show(_c, _led.marks[0], 3, 13);
    ok("shown, it carries what the mark carried",
       _c.tier == Mark.Gold && _c.label == "WAVE 2"
       && _c.earned == 18400 && _c.target == 15000 && _c.bombs == 1);

    var _live = 0;
    while (rank_card_live(_c)) {
        _live++;
        if (_live > RANK_CARD_TIME * 4) break;
        var _last = rank_card_where(_c);
        rank_card_step(_c);
        if (!rank_card_live(_c)) {
            var _home = hud_mark_xy(3, 13);
            ok("it lands on the socket it is filling",
               abs(_last[0] - _home[0]) < 2 && abs(_last[1] - _home[1]) < 2);
            ok("...and shrinks to the size of one",
               abs(_last[2] - RANK_CARD_HOME_S) < 0.02);
        }
    }
    ok("and it runs for exactly its own length", _live == RANK_CARD_TIME);
    ok("then it is idle again", !rank_card_live(_c));

    // The console throws the card by watching the ledger grow.
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _g.marks = rank_ledger_new();
    var _h = hud_new();
    hud_step(_h, _g);
    ok("an empty ledger throws no card", !rank_card_live(_h.card));
    rank_note(_g.marks, "WAVE 1", Mark.Silver, false, 10, 20, 1, 0);
    hud_step(_h, _g);
    ok("a mark landing throws one", rank_card_live(_h.card)
       && _h.card.tier == Mark.Silver);
    var _t_after = _h.card.t;
    hud_step(_h, _g);
    ok("and the next frame advances it rather than throwing it again",
       _h.card.t == _t_after + 1);
    st_reset();
}

// ---------------------------------------------------------------------------
// Practice and the drafting table
// ---------------------------------------------------------------------------

function test_practice() {
    var _stage = stage_ziggy_def();
    var _bosses = practice_bosses(_stage);
    ok("each boss hands back a fresh phase table",
       _bosses[1].phases() != _bosses[1].phases());
    ok("and it is the table the midboss actually fights",
       array_length(_bosses[0].phases()) == array_length(ziggy_midboss_phases()));

    var _list = stage_list();
    var _unbuilt = undefined;
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (!stage_is_built(_list[_i])) {
            _unbuilt = _list[_i];
            break;
        }
    }
    if (_unbuilt != undefined) {
        ok("an unbuilt stage offers nothing to practise",
           !practice_available(_unbuilt));
    }
    ok("and stage one does", practice_available(_stage));

    // Pick attacks out of Ziggy's table by kind, so this survives the table
    // being rewritten: the first non-spell, and a spell that is not the last
    // attack.
    var _zp = ziggy_phases();
    var _plain = -1;
    var _spell = -1;
    for (var _i = 0; _i < array_length(_zp); _i++) {
        if (_plain < 0 && _zp[_i].kind == AttackKind.NonSpell) _plain = _i;
        if (_spell < 0 && _i > 0 && _zp[_i].kind == AttackKind.Spell
            && _zp[_i].hp_end > 0) _spell = _i;
    }

    var _p = practice_new(_stage, 1, _spell);
    ok("a spell is listed under its own name", _p.label == _zp[_spell].name);
    var _np = practice_new(_stage, 1, _plain);
    ok("and a non-spell under the boss's, numbered",
       _np.label == "ZIGGY " + string(_plain + 1));
    ok("the run it describes has one graded encounter",
       _p.def.encounters == 1);
    ok("and an empty timeline", array_length(_p.def.build()) == 0);
    ok("and no stage to file a clear against", _p.def.id == "");
    ok("a blank id reads back as nothing cleared",
       !progress_stage("").cleared && progress_stage("").best == 0);

    // Practice arrives inside the boss's between-attack pause.
    st_reset();
    var _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.practice = practice_new(_stage, 1, _spell);
    _g.player.hp = 10;
    _g.player.mp = 0;
    var _b = practice_begin(_g);
    ok("the boss reaches the field", _b != undefined);
    ok("and past the arrival and the name splash",
       _b.boss.entry_t == 0 && _b.boss.declare_t == 0 && _b.boss.started);
    ok("the attack has not started yet", _b.boss.phase < 0);
    ok("but it knows which one is coming", _b.boss.next_phase == _spell);
    ok("and there is a beat before it does",
       _b.boss.clear_t == PRACTICE_READY);
    ok("during which the boss cannot be shot", !boss_vulnerable(_b));
    var _want = _b.hp_max * _zp[_spell - 1].hp_end;
    ok_near("its health starts at the attack's own threshold", _b.hp, _want, 1);
    ok("the player is topped up to full life", _g.player.hp == HP_MAX);
    ok("and full sigil", _g.player.mp == MP_MAX);
    for (var _i = 0; _i < PRACTICE_READY - 1; _i++) boss_act(_b, _g);
    ok("no bullet is fired during the beat", global.bullet_n == 0);
    ok("and it is still not the attack", _b.boss.phase < 0);
    boss_act(_b, _g);
    ok("then the attack asked for is entered", _b.boss.phase == _spell);
    ok("but it is still declaring itself", _b.boss.lead_t > 0);
    for (var _i = 0; _i < BOSS_SPELL_LEAD; _i++) boss_act(_b, _g);
    ok("and only then is the boss live", boss_vulnerable(_b));
    var _n0 = _g.ended_n;
    for (var _i = 0; _i < _zp[_spell].time + 2; _i++) boss_act(_b, _g);
    ok("running the clock out tells the run the attack ended",
       _g.ended_n == _n0 + 1);
    ok("and tells it the attack was survived, not broken", !_g.ended_beaten);
    var _timed = practice_outcome(_b, PracticeEnd.TimedOut, _g.marks);
    ok("which the panel reports as survived",
       practice_end_name(_timed) == "SURVIVED");

    // Broken, survived, captured and defeated are four different outcomes.
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.practice = practice_new(_stage, 1, _spell);
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

    // A boss marked `turned` is practised in its stage's second-half
    // background.
    var _hall = stage_sanctum_def();
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.bg = bg_sanctum();
    _g.practice = practice_new(_hall, 1, 0);
    practice_begin(_g);
    ok("Mika is practised in the open hall", _g.bg.omen_on && _g.bg.omen == 1);
    ok("...with the lights already up", _g.bg.intro == 1);
    st_reset();
    _g = st_game_at(GAME_CX, GAME_H - 300);
    _g.bg = bg_sanctum();
    _g.practice = practice_new(_hall, 0, 0);
    practice_begin(_g);
    ok("and the Proctor on the approach, where he is fought",
       !_g.bg.omen_on && _g.bg.omen == 0);
    ok("...lights up there too, since the arrival is the stage's",
       _g.bg.intro == 1);

    ok("a list that fits never scrolls",
       practice_list_scroll(0, 300, 400, 400, 100) == 0);
    ok("the page does not move while the cursor is inside it",
       practice_list_scroll(200, 500, 1000, 600, 100) == 200);
    ok("it turns when the cursor nears the foot",
       practice_list_scroll(0, 560, 1000, 600, 100) == 60);
    ok("and when it nears the head",
       practice_list_scroll(400, 450, 1000, 600, 100) == 350);
    ok("and it never runs past either end",
       practice_list_scroll(0, 1000, 1000, 600, 100) == 400
       && practice_list_scroll(400, 0, 1000, 600, 100) == 0);

    ok("two cards with no id keep separate bests",
       practice_key(draft_stage_def(), 0, 0)
       != practice_key(old_stage_sanctum_def(), 0, 0));
    st_reset();
}

function test_drafts() {
    st_reset();
    var _stages = stage_list();
    var _none = true;
    for (var _i = 0; _i < array_length(_stages); _i++) {
        if (stage_is_draft(_stages[_i])) _none = false;
    }
    ok("no stage claims to be the drafting table", _none);
    ok("nor does nothing at all", !stage_is_draft(undefined));

    var _def = draft_stage_def();
    ok("the drafting table can be practised", practice_available(_def));
    ok("but it is not a stage to play", !stage_is_built(_def));
    ok("and has no stage to file a clear against", _def.id == "");
    ok("a blank id reads back as nothing cleared",
       !progress_stage(_def.id).cleared);

    // Each draft owns an equal share of the bar, and a name makes it a spell.
    var _l = draft_list();
    var _ph = draft_phases();
    var _n = array_length(_l);
    ok("there is a phase per draft", array_length(_ph) == _n);
    var _even = true;
    var _prev = 1.0;
    var _span = 1 / _n;
    for (var _i = 0; _i < _n; _i++) {
        if (abs((_prev - _ph[_i].hp_end) - _span) > 0.001) _even = false;
        _prev = _ph[_i].hp_end;
    }
    ok("every draft owns the same span of the bar", _even);
    var _kinds = true;
    for (var _i = 0; _i < _n; _i++) {
        var _named = (_l[_i].name != "");
        if (_named != (_ph[_i].kind == AttackKind.Spell)) _kinds = false;
        if (_named != (_ph[_i].bg != -1)) _kinds = false;
    }
    ok("a name is what makes a draft a spell", _kinds);

    var _g = st_game_at(GAME_CX, GAME_H - 300);
    var _b = draft_boss_spawn(_g);
    ok("the draft boss reaches the field", _b != undefined);
    ok_near("and one slot is worth a fixed amount of health",
            _b.hp_max / _n, DRAFT_SLOT_HP, 0.001);

    var _named_i = -1;
    for (var _i = 0; _i < _n; _i++) {
        if (_l[_i].name != "") {
            _named_i = _i;
            break;
        }
    }
    if (_named_i >= 0) {
        st_reset();
        _g = st_game_at(GAME_CX, GAME_H - 300);
        var _p = practice_new(_def, 0, _named_i);
        ok("a named draft is listed under its own name",
           _p.label == _l[_named_i].name);
        _g.practice = _p;
        _b = practice_begin(_g);
        ok("practice puts the draft boss on the field", _b != undefined);
        ok("on the attack that was chosen", _b.boss.next_phase == _named_i);
        var _top = (_named_i > 0) ? _ph[_named_i - 1].hp_end : 1;
        ok_near("with the bar starting where that attack does",
                _b.hp, _b.hp_max * _top, 1);
    }
    st_reset();
}

// ---------------------------------------------------------------------------
// Demon Sealing Hex
// ---------------------------------------------------------------------------

/// @desc The Hex's geometry rests on arithmetic that would break silently: the
///       ward closes into an even ring, turns as a rigid body, and its
///       collapse lands every bead on one point on one frame (which relies on
///       `bullet_step` accelerating before it moves).
function test_hex_seal() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_CY);
    var _e = { x: FIELD_CX, y: BOSS_HOME_Y };

    var _lit = HEX_DRAW + HEX_SEAL_DELAY + 12;
    for (var _f = 0; _f < _lit; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }
    var _ang = [];
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
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
    ok("the ward's outer ring closes into a whole ring",
       array_length(_ang) > 8);
    ok("and its beads are evenly apart the whole way round",
       _wide < _tight * 1.25);

    for (var _f = _lit; _f < HEX_SCATTER_AT; _f++) {
        bullet_step(_g.player.x, _g.player.y);
        velka_demon_sealing_hex(_e, _g, _f);
    }
    var _far = 0;
    for (var _i = 0; _i < bullet_count(); _i++) {
        var _u = bullet_get(_i);
        if (_u.shape != HEX_BEAD || _u.col != BCOL_CRIMSON) continue;
        _far = max(_far, point_distance(FIELD_CX, FIELD_CY, _u.x, _u.y));
    }
    ok_near("the ward turns without opening", _far, HEX_R_OUT, 1);

    for (var _f = HEX_SCATTER_AT; _f <= HEX_BURST_AT + 1; _f++) {
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
    ok("the collapse lands every bead on the same point on the same frame",
       _landed > 0 && _adrift == 0);

    var _bounded = true;
    for (var _i = 0; _i < 200; _i++) {
        var _h = hex_hash(_i, 27.611);
        if (_h < 0 || _h >= 1) _bounded = false;
    }
    ok("the hash behind its scatter is bounded to [0, 1)", _bounded);
    st_reset();
}

// ---------------------------------------------------------------------------
// The HUD
// ---------------------------------------------------------------------------

/// @desc Nothing on the console overlaps the field, nothing is cut off by the
///       field's frame, and no two readouts overlap.
function test_hud_layout() {
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

    var _inside = true;
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _b = hud_box(_names[_i]);
        if (_b[0] < HUD_PANEL_X0 || _b[2] > HUD_PANEL_X1
            || _b[1] < HUD_PANEL_Y0 || _b[3] > HUD_PANEL_Y1) {
            _inside = false;
        }
    }
    ok("every console readout is on the console's plate", _inside);
    ok("the plate fits on the screen",
       HUD_PANEL_Y0 > 0 && HUD_PANEL_Y1 < GAME_H);
    ok("and clears the field",
       rect_clear_of_field(HUD_PANEL_X0, HUD_PANEL_Y0,
                           HUD_PANEL_X1, HUD_PANEL_Y1));

    // The boss's rail lives in the top of the field; the frame's mask must
    // hide it between bosses and must not clip it during a fight.
    ok("the whole rig stows behind the frame between bosses",
       BOSS_RIG_STOW + BOSS_BAR_H * 0.5
       + max(BOSS_DIAL_D, BOSS_PCT_H) * 0.5 <= FIELD_Y0);
    ok("the cartouche and the dial stay inside the field",
       BOSS_BAR_Y + BOSS_BAR_H * 0.5 - max(BOSS_PCT_H, BOSS_DIAL_D) * 0.5
       > FIELD_Y0);
    ok("the nameplate stands inside the field, above its rail",
       BOSS_PLATE_Y > FIELD_Y0 && BOSS_NAME_Y < BOSS_BAR_Y);
    ok("the spell's name clears the cartouche above it",
       BOSS_SPELL_Y - 16 >= BOSS_BAR_Y + BOSS_BAR_H * 0.5 + BOSS_PCT_H * 0.5);
    ok("and the line's box covers everything drawn on it",
       hud_box("boss")[1] <= BOSS_BAR_Y
       && hud_box("boss")[3] >= BOSS_SPELL_Y);

    // `BOSS_INK_ABOVE` is measured off the boss sprites.
    ok("the boss flies below its own rail, not through it",
       BOSS_HOME_Y - BOSS_DRIFT_Y - BOSS_INK_ABOVE > BOSS_BAR_Y + BOSS_BAR_H);
    ok("and the ink allowance fits inside the sprite it came from",
       BOSS_INK_ABOVE <= sprite_get_yoffset(spr_boss_ziggy));

    ok("the lower meter has room to stand on its plate",
       HUD_ROW_SIGIL + HUD_METER_H < HUD_PANEL_Y1);
    var _life = hud_box("life");
    var _mana = hud_box("mana");
    ok("the two meters stack without overlapping", _mana[1] >= _life[3] + 1);
    draw_set_font(fnt_small());
    var _tag = string_width("SIGIL  READY");
    draw_set_font(fnt_ui());
    var _val = string_width(string(HP_MAX));
    ok("a meter's name and value fit on one line without meeting",
       _tag + _val < HUD_METER_W - 60);

    ok("the field is inside the screen",
       FIELD_X0 > 0 && FIELD_Y0 > 0
       && FIELD_X1 < GAME_W && FIELD_Y1 <= GAME_H);
    ok("and there is a margin to put the console in",
       GAME_W - FIELD_X1 > HUD_METER_W);
    ok("the boss stations inside the field",
       BOSS_HOME_Y > FIELD_Y0 && BOSS_HOME_Y < FIELD_Y1);
    ok("the frame's corner ornaments stay in the margin",
       FIELD_ORN_OUT >= UI_CORNER_DEPTH * FIELD_ORN_SCALE);
    ok("and the rule they stand on is in the margin too",
       FIELD_RULE_OUT > 0 && FIELD_ORN_OUT < FIELD_X0
       && FIELD_ORN_OUT < FIELD_Y0);

    // Stage one's near layer draws over bullets.
    ok("the foreground layer is never opaque", BG_NEAR_ALPHA <= 0.55);
    ok("and it leaves most of the field alone", BG_NEAR_EDGE * 2 < 0.34);

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

/// @desc The boss's rail lowers when a boss is on the field, lands once, and
///       stows behind the frame again when it leaves.
function test_boss_rig() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _h = hud_new();
    ok("a console opens with its rail stowed", _h.rig == 0);
    ok("and stowed is entirely behind the frame",
       hud_rig_y(_h) + BOSS_BAR_H <= FIELD_Y0);
    for (var _i = 0; _i < 200; _i++) hud_step(_h, _g);
    ok("and an empty field never lowers it", _h.rig == 0);
    ok("...nor lights its landing", _h.rig_flare == 0);

    var _b = ziggy_spawn(_g);
    ok("a boss reaches the field", _b != undefined);
    var _lands = 0;
    for (var _i = 0; _i < BOSS_ENTRY_TIME; _i++) {
        hud_step(_h, _g);
        if (_h.rig_flare >= 1) _lands++;
    }
    ok("the rail comes down while the boss arrives", _h.rig > 0.9);
    ok("and its landing fires once as it does", _lands == 1);
    for (var _i = 0; _i < 240; _i++) hud_step(_h, _g);
    ok("then it settles", abs(_h.rig - 1) < 0.01);
    ok("and the landing is spent", _h.rig_flare == 0);

    _b.boss.beaten = true;
    for (var _i = 0; _i < 300; _i++) hud_step(_h, _g);
    ok("a beaten boss draws it back up", _h.rig < 0.02);
    ok("and back up is behind the frame again",
       hud_rig_y(_h) + BOSS_BAR_H <= FIELD_Y0);
    st_reset();
}

/// @desc The boss's percentage counter: odometer wheels, rolling to rest on a
///       floor rather than a round.
function test_counter() {
    ok("the lowest wheel is the counter itself",
       abs(counter_wheel_pos(753.4, 0) - 753.4) < 0.0001);
    ok("a higher wheel stands still while the one below it turns",
       counter_wheel_pos(753.4, 1) == 75 && counter_wheel_pos(753.4, 2) == 7);
    ok("and turns while the one below passes through nine",
       abs(counter_wheel_pos(759.5, 1) - 75.5) < 0.0001
       && counter_wheel_pos(759.5, 2) == 7);
    ok("so 100.0 to 99.9 turns every wheel at once",
       abs(counter_wheel_pos(999.5, 1) - 99.5) < 0.0001
       && abs(counter_wheel_pos(999.5, 2) - 9.5) < 0.0001
       && abs(counter_wheel_pos(999.5, 3) - 0.5) < 0.0001);
    ok("and a full counter reads one, zero, zero, zero",
       counter_wheel_pos(1000, 3) == 1 && counter_wheel_pos(1000, 2) == 10
       && counter_wheel_pos(1000, 1) == 100);

    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _h = hud_new();
    var _b = ziggy_spawn(_g);
    ok("a counter starts full", _h.pct_roll == 1000);
    _b.hp = _b.hp_max * 0.7463;
    var _last = _h.pct_roll;
    var _up = false;
    for (var _i = 0; _i < 90; _i++) {
        hud_step(_h, _g);
        if (_h.pct_roll > _last) _up = true;
        _last = _h.pct_roll;
    }
    ok("damage turns it down", _h.pct_roll < 1000 && !_up);
    ok("and it comes to rest on the tenth below the truth",
       _h.pct_roll == 746);
    _b.hp = _b.hp_max * 0.7453;
    var _n = 0;
    while (_h.pct_roll != 745 && _n < 60) {
        hud_step(_h, _g);
        _n++;
    }
    ok("a single tenth turns over", _h.pct_roll == 745);
    _b.hp = _b.hp_max * 0.9996;
    for (var _i = 0; _i < 120; _i++) hud_step(_h, _g);
    ok("a scratched boss does not read full", _h.pct_roll == 999);

    // In practice the rail reads the practised attack's own span.
    st_reset();
    _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    _h = hud_new();
    _b = ziggy_spawn(_g);
    var _ph = _b.boss.phases;
    var _top = _ph[1].hp_end;
    var _bot = _ph[2].hp_end;
    _g.practice = { phase_i: 2 };
    _b.hp = _b.hp_max * _top;
    for (var _i = 0; _i < 150; _i++) hud_step(_h, _g);
    ok("a practised attack opens at 100.0", _h.pct_roll == 1000
       && abs(_h.boss_shown - 1) < 0.01);
    _b.hp = _b.hp_max * lerp(_bot, _top, 0.5);
    for (var _i = 0; _i < 150; _i++) hud_step(_h, _g);
    ok("half way through it the rail is half full", _h.pct_roll == 500
       && abs(_h.boss_shown - 0.5) < 0.01);
    _b.hp = _b.hp_max * _bot;
    for (var _i = 0; _i < 150; _i++) hud_step(_h, _g);
    ok("and it breaks at 0.0", _h.pct_roll == 0 && _h.boss_shown < 0.01);
    _g.practice = undefined;
    _b.hp = _b.hp_max * lerp(_bot, _top, 0.5);
    for (var _i = 0; _i < 150; _i++) hud_step(_h, _g);
    ok("a stage reads the same health against the whole fight",
       _h.pct_roll == floor(lerp(_bot, _top, 0.5) * 1000 + 0.0001));
    st_reset();
}

// ---------------------------------------------------------------------------
// Runs, saves, audio
// ---------------------------------------------------------------------------

/// @desc The pools are globals that outlive a room, so every run has to start
///       by emptying them.
function test_run_starts_clean() {
    st_reset();
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
    run_clear_field();
    ok("a run starts with no bullets", bullet_count() == 0);
    ok("...no lasers", laser_count() == 0);
    ok("...no rings", ring_count() == 0);
    ok("...no items", item_count() == 0);
    ok("...and no enemies, boss included", enemy_count() == 0);
    ok("so nothing is left to find a boss in", enemy_find_boss() == undefined);
}

/// @desc Bosses are drawn from the enemy pool, so one the run has let go of
///       is still on the field.
function test_boss_is_never_invisible() {
    st_reset();
    var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 + 200, 400, ziggy_phases(),
                        ziggy_def());
    _g.boss_ref = _b;
    _g.boss_ref = undefined;
    ok("a boss outlives the run's reference to it",
       enemy_count() == 1 && enemy_find_boss() != undefined);
    var _still = enemy_find_boss();
    ok("and is still a real enemy on the field",
       _still.hp > 0 && _still.r > 0);
}

/// @desc The save primitives, on a scratch file. Nothing here touches the real
///       save.
function test_save_atomicity() {
    var _name = "selftest_scratch.json";
    save_delete(_name);
    save_write_json(_name, { a: 1, b: "two" });
    var _back = save_read_json(_name);
    ok("a saved struct reads back", _back != undefined && _back.a == 1
       && _back.b == "two");
    ok("and leaves no temp file behind", !file_exists(_name + ".tmp"));

    file_rename(_name, _name + ".tmp");
    var _recovered = save_read_json(_name);
    ok("a save interrupted mid-rename is recovered",
       _recovered != undefined && _recovered.a == 1);
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

/// @desc `sfx` only votes; `sfx_step` turns a frame's votes into at most one
///       voice per cue and `SFX_VOICES` a frame.
function test_audio_budget() {
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

    var _table = global.sfx_table;
    for (var _i = 0; _i < 400; _i++) sfx(Sfx.ShotSoft);
    sfx_step();
    ok("a cue on cooldown drops its requests rather than queueing them",
       global.sfx_voices == 1 && global.sfx_want[Sfx.ShotSoft] == 0);
    var _gap = _table[Sfx.ShotSoft].gap;
    for (var _f = 0; _f < _gap; _f++) {
        sfx(Sfx.ShotSoft);
        sfx_step();
    }
    ok("and sounds again once its gap has run", global.sfx_voices == 2);

    sfx_reset();
    for (var _f = 0; _f < 60; _f++) {
        for (var _i = 0; _i < 120; _i++) sfx(Sfx.ShotSoft);
        sfx_step();
    }
    var _want = 60 div _table[Sfx.ShotSoft].gap;
    ok("a second of flat-out firing is " + string(global.sfx_voices)
       + " voices, not " + string(global.sfx_requests),
       global.sfx_voices <= _want + 1 && global.sfx_voices >= _want - 1);

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

    ok("one request carries no swell", sfx_swell(1) == 0);
    ok("more is bigger", sfx_swell(8) > sfx_swell(2));
    ok("...and it stops growing", sfx_swell(SFX_SWELL_FULL * 8) <= 1);

    // Votes cast before a room change are dropped, not played in the new
    // room.
    sfx_reset();
    sfx(Sfx.PlayerDown);
    global.sfx_room = -999;
    sfx_step();
    ok("a request does not survive a room change",
       global.sfx_voices == 0 && !sfx_sounded(Sfx.PlayerDown));

    var _holes = 0;
    var _bad_gap = 0;
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        if (_table[_c] == undefined) { _holes++; continue; }
        if (!audio_exists(_table[_c].snd)) _holes++;
        if (_table[_c].gap < 1) _bad_gap++;
    }
    ok("every cue has a row and a real sound", _holes == 0);
    ok("and no cue may sound every frame", _bad_gap == 0);

    var _bad_voice = 0;
    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        var _v = sfx_for_shape(_s);
        if (_v != Sfx.ShotSoft && _v != Sfx.ShotSharp && _v != Sfx.ShotHeavy) {
            _bad_voice++;
        }
    }
    ok("every bullet shape maps to a shot cue", _bad_voice == 0);

    st_reset();
    sfx_reset();
    fire_ring(FIELD_CX, FIELD_CY, 30, 3, 0, BSHAPE_NEEDLE, BCOL_CRIMSON, 0);
    ok("a ring of needles asks for the sharp cue",
       global.sfx_want[Sfx.ShotSharp] == 30);
    sfx_step();
    ok("...and gets one voice for the ring", global.sfx_voices == 1);
    ok("and the suite ran silent", global.audio_on == false);
}

/// @desc The real `audio_play_sound` path runs under the suite with the
///       master gain at zero.
function test_audio_playback() {
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
    sfx_play_now(Sfx.ShotSoft, 240);
    ok("...including a coalesced volley's gain and pitch",
       audio_is_playing(snd_shot_soft));
    audio_stop_all();
    global.audio_on = _was;
    sfx_reset();
    ok("and the suite is silent again", global.audio_on == false);
}

/// @desc Every attack on the rack runs for a few seconds without throwing and
///       without filling the bullet pool. A throw is caught and named here;
///       left uncaught it would be a modal box, which hangs the harness.
function test_attacks_run() {
    var _rack = rack_list();
    var _threw = "";
    var _flooded = "";
    var _ran = 0;
    for (var _s = 0; _s < array_length(_rack); _s++) {
        var _bosses = _rack[_s][$ "bosses"];
        if (_bosses == undefined) continue;
        for (var _b = 0; _b < array_length(_bosses); _b++) {
            var _n = array_length(_bosses[_b].phases());
            for (var _p = 0; _p < _n; _p++) {
                var _label = _bosses[_b].name + " #" + string(_p + 1);
                st_reset();
                var _g = st_game_at(FIELD_CX, FIELD_Y1 - 200);
                try {
                    var _e = _bosses[_b].spawn(_g);
                    _e.boss.entry_t = 0;
                    _e.boss.declare_t = 0;
                    _e.boss.started = true;
                    _e.x = _e.boss.home_x;
                    _e.y = _e.boss.home_y;
                    boss_enter_phase(_e, _g, _p);
                    _e.boss.lead_t = 0;
                    for (var _f = 0; _f < ST_ATTACK_FRAMES; _f++) {
                        boss_act(_e, _g);
                        ring_step(_g);
                        laser_step();
                        bullet_step(_g.player.x, _g.player.y);
                        if (bullet_count() >= BULLET_MAX) {
                            _flooded += _label + " ";
                            break;
                        }
                    }
                    _ran++;
                } catch (_err) {
                    _threw += _label + " ("
                              + (is_struct(_err) ? _err.message : string(_err))
                              + ") ";
                }
            }
        }
    }
    ok("every attack on the rack runs without throwing (" + string(_ran)
       + " run) " + _threw, _ran > 0 && _threw == "");
    ok("and none fills the bullet pool " + _flooded, _flooded == "");
    st_reset();
}

/// @desc A rough performance guard for the bullet loops.
function test_bullet_cost() {
    st_reset();
    var _n = 2000;
    for (var _i = 0; _i < _n; _i++) {
        var _b = fire(random(GAME_W), random(GAME_H), 0.2, random(360),
                      BSHAPE_ORB, BCOL_CYAN, 0);
        if (_b == undefined) break;
    }
    var _live = bullet_count();

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

    ok("stepping a full screen of bullets stays under budget", _per < 4.0);
    ok("and a second of a full screen is well under a second",
       _best < 600000);
    st_reset();
}
