/// @desc Sylvia's drafts on the drafting table, from the browser sketch
///       `sylvia.js`: "Iris bloom" in two versions and two spells from
///       it, and "Iris blooms" (at the end of this file). His N1 and N2,
///       from the same sketches, are in his slots (`sylvia_spirals`).
///       Placeholders: Sylvia has no stage or sprite yet.

// Each of Sylvia's drafts' health: three times `DRAFT_SLOT_HP`. Full focused fire,
// every shot landing, deals 30 a second (`rank_full_fire`), so this is about
// 36 seconds of it against a 40-second clock.
#macro SYLVIA_DRAFT_HP 1080

// ---------------------------------------------------------------------------
// Iris bloom
//
// Every `EVERY` frames `N` curved lasers (magenta and indigo by turns) wait
// `DELAY` frames as marks on a ring `R0` round the caster, then fire `OFF` degrees
// off straight out and curl back the other way along arcs, at `SPD` px a
// frame: a pinwheel of blades sweeping out over
// the field. Alternate volleys curl the other way, and each is turned `STEP`
// degrees on from the last. Soon after the blades fire, twice as many cyan
// orbs leave the same ring along the same arcs, two to each gap, at `ORB`,
// and run straight once they have come as far round as the blades.
//
// The sketch's blades run 50 frames on arcs of radius 290 and die well short
// of the player; the non-spell's run on wider arcs (`ARC`) until they near
// the walls (`LIFE`). The spell, **Iris Rosette** (a placeholder name), keeps
// the sketch's arcs and runs each blade a little over a whole loop
// (`ROSETTE_*`), so the blades fold into a turning flower round the caster. The
// second non-spell (`LOOP_*`) keeps the sketch's arcs too, but each blade
// turns `LOOP_TURN` degrees and then runs straight for `LOOP_RUN` frames, so
// the flower forms and then fires its blades out past the player; its orbs
// turn as far and run straight too. The second spell, **Slow Rosette** (a
// placeholder name), is Iris Rosette from the middle of the field with the
// whole pattern slowed to `SLOW` of its pace: every speed, and the volleys'
// rhythm and marks with it, so the flower keeps its shape. Its blades keep a
// trail node every `1 / SLOW` frames, so they are as long as at full pace,
// and leave at `LAUNCH` times their speed, easing to `SETTLE` times it (by
// 1/e in `SETTLE_T` frames at full pace) along the same arcs; each runs as
// far as at a steady speed. It is also `SLOW_SCALE` times the size (every
// distance and speed, not its timing), cast from the middle of the field, so
// the loops just reach the corners the player can get to.
//
// The orbs are persistent while they follow their arcs, which carry them out
// past the field's edge and back; they are culled as usual once they run
// straight.
// ---------------------------------------------------------------------------

#macro SYLVIA_IRIS_EVERY 90
#macro SYLVIA_IRIS_N 12
#macro SYLVIA_IRIS_R0 50
#macro SYLVIA_IRIS_OFF 40
#macro SYLVIA_IRIS_ARC 480
#macro SYLVIA_IRIS_SPD 8
#macro SYLVIA_IRIS_LIFE 170
#macro SYLVIA_IRIS_WID 14
#macro SYLVIA_IRIS_DELAY 20
#macro SYLVIA_IRIS_STEP 15
#macro SYLVIA_IRIS_ROSETTE_ARC 290
#macro SYLVIA_IRIS_ROSETTE_LIFE 240
#macro SYLVIA_IRIS_LOOP_TURN 360
#macro SYLVIA_IRIS_LOOP_RUN 160
#macro SYLVIA_IRIS_SLOW 0.5
#macro SYLVIA_IRIS_SLOW_SCALE 1.3
#macro SYLVIA_IRIS_LAUNCH 2.0
#macro SYLVIA_IRIS_SETTLE 0.8
#macro SYLVIA_IRIS_SETTLE_T 25
#macro SYLVIA_IRIS_ORB 3.5
// Frames after the blades fire that the orbs go live.
#macro SYLVIA_IRIS_ORB_AT 12

/// @desc **Iris bloom** (Sylvia's, a draft).
function draft_sylvia_iris(_e, _g, _t) {
    sylvia_iris(_e, _t, SYLVIA_IRIS_ARC, SYLVIA_IRIS_LIFE);
}

/// @desc **Iris bloom**, the blades looping and then running straight
///       (Sylvia's, a draft).
function draft_sylvia_iris_loop(_e, _g, _t) {
    var _turn = radtodeg(SYLVIA_IRIS_SPD / SYLVIA_IRIS_ROSETTE_ARC);
    sylvia_iris(_e, _t, SYLVIA_IRIS_ROSETTE_ARC,
                ceil(SYLVIA_IRIS_LOOP_TURN / _turn) + SYLVIA_IRIS_LOOP_RUN,
                SYLVIA_IRIS_LOOP_TURN);
}

/// @desc **Iris Rosette** (Sylvia's, a draft spell; placeholder name).
function draft_sylvia_rosette(_e, _g, _t) {
    sylvia_iris(_e, _t, SYLVIA_IRIS_ROSETTE_ARC, SYLVIA_IRIS_ROSETTE_LIFE);
}

/// @desc **Slow Rosette** (Sylvia's, a draft spell; placeholder name): Iris
///       Rosette at `SLOW` of its pace and `SLOW_SCALE` of its size, its
///       blades launched and settling. Its row puts the caster in the middle.
function draft_sylvia_slow_rosette(_e, _g, _t) {
    sylvia_iris(_e, _t, SYLVIA_IRIS_ROSETTE_ARC,
                ceil(SYLVIA_IRIS_ROSETTE_LIFE / SYLVIA_IRIS_SLOW), -1,
                SYLVIA_IRIS_SLOW, true, SYLVIA_IRIS_SLOW_SCALE);
}

/// @desc An iris bloom whose blades run `_life` frames on arcs of radius
///       `_arc`; given `_turn_deg`, blades and orbs turn that many degrees
///       round their arcs and then run straight. `_pace` scales its speeds,
///       and stretches its rhythm and marks to match. With `_settle`, the
///       blades launch and settle (`LAUNCH`, `SETTLE`), each running as far
///       as `_life` frames would take it at a steady speed. `_scale` sizes
///       the whole of it: every distance and speed, not its timing.
function sylvia_iris(_e, _t, _arc, _life, _turn_deg = -1, _pace = 1,
                     _settle = false, _scale = 1) {
    var _every = floor(SYLVIA_IRIS_EVERY / _pace + 0.5);
    var _delay = floor(SYLVIA_IRIS_DELAY / _pace + 0.5);
    var _spd = SYLVIA_IRIS_SPD * _pace * _scale;
    var _orb = SYLVIA_IRIS_ORB * _pace * _scale;
    var _r0 = SYLVIA_IRIS_R0 * _scale;
    _arc *= _scale;
    // Frames between a blade's trail nodes, so a slow blade is as long.
    var _gap = max(1, floor(1 / _pace + 0.5));
    var _u = _t mod _every;
    var _k = _t div _every;
    var _way = ((_k mod 2) == 0) ? 1 : -1;
    var _base = _k * SYLVIA_IRIS_STEP;

    // How far a blade's head runs: `_life` frames at a steady speed.
    var _dist = _spd * _life;

    if (_u == 0) {
        var _go = _spd;
        var _head = _life;
        var _share = 0;
        if (_settle) {
            // Out at `LAUNCH` times the speed; the frames it then takes, easing
            // toward `SETTLE` times it, to run as far (as `laser_step_curve`
            // eases: before each move).
            _go = _spd * SYLVIA_IRIS_LAUNCH;
            _share = 1 - exp(-_pace / SYLVIA_IRIS_SETTLE_T);
            var _v = _go;
            var _run = 0;
            _head = 0;
            while (_run < _dist) {
                _v += (_spd * SYLVIA_IRIS_SETTLE - _v) * _share;
                _run += _v;
                _head++;
            }
        }
        // Degrees a frame that keep a head at `_go` on a circle of `_arc`.
        var _turn = radtodeg(_go / _arc);
        var _for = (_turn_deg < 0) ? -1 : floor(_turn_deg / _turn + 0.5);
        for (var _i = 0; _i < SYLVIA_IRIS_N; _i++) {
            var _th = _base + _i * 360 / SYLVIA_IRIS_N;
            var _l = laser_curve(_e.x + lengthdir_x(_r0, _th),
                                 _e.y + lengthdir_y(_r0, _th),
                                 _th + _way * SYLVIA_IRIS_OFF, _go,
                                 -_way * _turn, SYLVIA_IRIS_WID,
                                 ((_i mod 2) == 0) ? BCOL_MAGENTA
                                                   : BCOL_INDIGO,
                                 _head, _delay, _for);
            if (_l == undefined) break;
            _l.node_gap = _gap;
            if (_settle) {
                laser_curve_ease(_l, _spd * SYLVIA_IRIS_SETTLE, _share);
            }
        }
    }

    // Fired with a mark, so they go live `ORB_AT` frames after the blades.
    if (_u == _delay + floor(SYLVIA_IRIS_ORB_AT / _pace + 0.5)
              - BULLET_DELAY_DEFAULT) {
        var _bend = radtodeg(_orb / _arc);
        // The frames an orb takes to come as far round as a blade's head.
        var _round = (_turn_deg < 0)
            ? floor(_dist / _orb + 0.5)
            : floor(_turn_deg / _bend + 0.5);
        for (var _j = 0; _j < 2 * SYLVIA_IRIS_N; _j++) {
            var _at = _base + (_j + 0.5) * 180 / SYLVIA_IRIS_N;
            var _o = fire(_e.x + lengthdir_x(_r0, _at),
                          _e.y + lengthdir_y(_r0, _at),
                          _orb, _at + _way * SYLVIA_IRIS_OFF,
                          BSHAPE_ORB, BCOL_CYAN);
            if (_o == undefined) break;
            _o.turn = -_way * _bend;
            bullet_turn_at(_o, _round, 0);
            // Its arc carries it out past the edge and back.
            bullet_persist(_o);
            bullet_cull_at(_o, _round);
        }
    }
}

// ---------------------------------------------------------------------------
// Iris blooms
//
// From the sketch "Iris blooms". Sets of `SEEDS` seeds (rose balls) come in
// pairs, a one-two: the second set `EVERY` frames after the first, then
// `REST` frames before the next pair. A set's seeds leave the caster evenly round,
// the set at a random turn, so no two sets lay the same paths. Each leaves at
// `SPD` and brakes by `BRAKE` a frame, curving along an arc of radius `ARC`
// (the way the set's blooms spin) until it stops, and there spins out a small
// iris: `VOLLEYS` volleys of `ARMS` rice, cyan and magenta by turns, one
// every `GAP` frames at `SHOT` px a frame, the bloom turning `SPIN` degrees a
// frame, so its arms wind into a spiral. The seed is spent with its last
// volley. A pair's second set spins the other way.
//
// A seed is moved by a task (`sylvia_seed_task`), which fires its bloom: a
// bullet's queue holds too few events for this many volleys.
// ---------------------------------------------------------------------------

#macro SYLVIA_BLOOMS_EVERY 90
#macro SYLVIA_BLOOMS_REST 150
#macro SYLVIA_BLOOMS_SEEDS 5
#macro SYLVIA_BLOOMS_SPD 10
#macro SYLVIA_BLOOMS_BRAKE 0.22
#macro SYLVIA_BLOOMS_ARC 200
#macro SYLVIA_BLOOMS_ARMS 6
#macro SYLVIA_BLOOMS_VOLLEYS 12
#macro SYLVIA_BLOOMS_GAP 2
#macro SYLVIA_BLOOMS_SPIN 7
#macro SYLVIA_BLOOMS_SHOT 3.6

/// @desc **Iris blooms** (Sylvia's, a draft).
function draft_sylvia_blooms(_e, _g, _t) {
    var _cyc = SYLVIA_BLOOMS_EVERY + SYLVIA_BLOOMS_REST;
    var _c = _t mod _cyc;
    if (_c != 0 && _c != SYLVIA_BLOOMS_EVERY) return;

    var _way = (_c == 0) ? 1 : -1;
    var _base = random(360);
    for (var _i = 0; _i < SYLVIA_BLOOMS_SEEDS; _i++) {
        var _dir = _base + _i * 360 / SYLVIA_BLOOMS_SEEDS;
        var _u = fire(_e.x, _e.y, SYLVIA_BLOOMS_SPD, _dir, BSHAPE_BALL,
                      BCOL_ROSE);
        if (_u == undefined) break;
        // `rest` is the seed's life on the frame it stopped.
        bullet_task(_u, method({ way: _way, spd: SYLVIA_BLOOMS_SPD,
                                 dir: _dir, rest: -1 }, sylvia_seed_task));
    }
}

/// @desc A seed's task, bound to its own struct: brake and curve out (as the
///       sketch moves a shot: change speed, turn, then move), and once
///       stopped fire the bloom's volleys. Spent with the last.
function sylvia_seed_task(_u) {
    if (rest < 0) {
        spd = max(0, spd - SYLVIA_BLOOMS_BRAKE);
        dir += way * radtodeg(spd / SYLVIA_BLOOMS_ARC);
        _u.x += lengthdir_x(spd, dir);
        _u.y += lengthdir_y(spd, dir);
        if (spd > 0) return false;
        rest = _u.life;
    }

    var _b = _u.life - rest;
    if ((_b mod SYLVIA_BLOOMS_GAP) != 0) return false;
    for (var _j = 0; _j < SYLVIA_BLOOMS_ARMS; _j++) {
        fire(_u.x, _u.y, SYLVIA_BLOOMS_SHOT,
             way * _b * SYLVIA_BLOOMS_SPIN + _j * 360 / SYLVIA_BLOOMS_ARMS,
             BSHAPE_RICE, ((_j mod 2) == 0) ? BCOL_CYAN : BCOL_MAGENTA,
             BULLET_SPLIT_DELAY);
    }
    return _b >= (SYLVIA_BLOOMS_VOLLEYS - 1) * SYLVIA_BLOOMS_GAP;
}
