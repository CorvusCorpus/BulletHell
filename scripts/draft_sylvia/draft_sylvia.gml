/// @desc Sylvia's non-spells as drafts on the drafting table, from the
///       browser sketch `sylvia.js`: N1 and N2 from "Two spirals: peel" and
///       "Two spirals: spin and fling", and "Iris bloom" in two versions and
///       two spells from it (at the end of this file). Placeholders: he has no stage or sprite
///       yet.
///
/// At the top of each hold he sends out pens (balls) to two points beside and
/// below him. From each point the pens wind outward along the arms of a
/// spiral, laying still darts: in N1 the left spiral cyan and the right its
/// mirror image in magenta, in N2 the other way round. A short pause after
/// the last dart the spirals come alive.
/// In `peel` each dart sets off along its arm where it lies, from the loose
/// outer ends inward; in `spin and fling` each spiral spins up as a whole the
/// way that unwinds it and every dart is let go along its circle, so the
/// outer turns fly fastest. A dart bounces once off a side wall.
///
/// Unlike the sketch (orbs, one arm a spiral), these lay darts on two arms.
///
/// The pens and the spinning darts are moved by tasks (`bullet_task`), each
/// bound to a struct for its arm. A pen's life is its pair's clock; a dart
/// knows the clock from the frame it was laid.

// Each of his drafts' health: three times `DRAFT_SLOT_HP`. Full focused fire,
// every shot landing, deals 30 a second (`rank_full_fire`), so this is about
// 36 seconds of it against a 40-second clock.
#macro SYLVIA_DRAFT_HP 1080

// The spirals: centres `DX` either side of him and `DY` below, each of `ARMS`
// arms evenly round. An arm winds `TURNS` times counterclockwise from radius
// `R0` at bearing `A0` (plus its share of the turn) out to `R1` (the right
// spiral mirrored). A pen reaches its centre in `REACH` frames, easing in,
// then winds out at `PEN` px a frame, laying a dart every `GAP` px; the
// spirals come alive `PAUSE` frames after the pens reach the ends. A pair is
// laid at the top of every hold of `HOLD` frames.
#macro SYLVIA_SPI_ARMS 2
#macro SYLVIA_SPI_SHOT BSHAPE_DART
#macro SYLVIA_SPI_DX 300
#macro SYLVIA_SPI_DY 170
#macro SYLVIA_SPI_R0 18
#macro SYLVIA_SPI_R1 190
#macro SYLVIA_SPI_TURNS 2.5
#macro SYLVIA_SPI_A0 270
#macro SYLVIA_SPI_GAP 30
#macro SYLVIA_SPI_REACH 20
#macro SYLVIA_SPI_PEN 16
#macro SYLVIA_SPI_PAUSE 22
#macro SYLVIA_SPI_HOLD 210

// Peel: over `SPAN` frames, outer ends first, each dart sets off along its
// arm's heading where it lies, speeding up by `ACC` a frame to `VTO`.
#macro SYLVIA_PEEL_SPAN 72
#macro SYLVIA_PEEL_ACC 0.06
#macro SYLVIA_PEEL_VTO 3.4

// Spin and fling: each spiral spins up over `RAMP` frames to `SPIN` degrees a
// frame, and `AT` frames after it came alive every dart is let go along its
// circle at the speed it had there, plus `KICK`.
#macro SYLVIA_FLING_RAMP 40
#macro SYLVIA_FLING_SPIN 2.0
#macro SYLVIA_FLING_AT 64
#macro SYLVIA_FLING_KICK 1.0

// ---------------------------------------------------------------------------
// The attacks
// ---------------------------------------------------------------------------

/// @desc Sylvia's N1, **Two spirals: peel** (a draft).
function draft_sylvia_peel(_e, _g, _t) {
    var _cyc = SYLVIA_SPI_HOLD + BOSS_STEP_MOVE;
    if ((_t mod _cyc) == 0) sylvia_spirals(_e, false);
}

/// @desc Sylvia's N2, **Two spirals: spin and fling** (a draft).
function draft_sylvia_fling(_e, _g, _t) {
    var _cyc = SYLVIA_SPI_HOLD + BOSS_STEP_MOVE;
    if ((_t mod _cyc) == 0) sylvia_spirals(_e, true);
}

// ---------------------------------------------------------------------------
// The spiral
// ---------------------------------------------------------------------------

/// @desc The spiral's radius after winding `_a` degrees.
function sylvia_spiral_r(_a) {
    return SYLVIA_SPI_R0
           + (SYLVIA_SPI_R1 - SYLVIA_SPI_R0) * _a / (SYLVIA_SPI_TURNS * 360);
}

/// @desc The left spiral's heading after winding `_a` degrees: square to its
///       radius, leaning outward by how fast the radius grows.
function sylvia_spiral_dir(_a) {
    var _grow = (SYLVIA_SPI_R1 - SYLVIA_SPI_R0)
                / degtorad(SYLVIA_SPI_TURNS * 360);
    return SYLVIA_SPI_A0 + _a + 90 - darctan2(_grow, sylvia_spiral_r(_a));
}

/// @desc The degrees wound `_s` px along the spiral (`_sp`, from
///       `sylvia_spiral`).
function sylvia_spiral_wound(_sp, _s) {
    var _lo = 0;
    var _hi = array_length(_sp.len) - 1;
    if (_s >= _sp.len[_hi]) return _sp.th[_hi];
    while (_hi - _lo > 1) {
        var _mid = (_lo + _hi) div 2;
        if (_sp.len[_mid] <= _s) _lo = _mid; else _hi = _mid;
    }
    var _f = (_s - _sp.len[_lo]) / max(0.0001, _sp.len[_hi] - _sp.len[_lo]);
    return lerp(_sp.th[_lo], _sp.th[_hi], _f);
}

/// @desc The spiral, worked out once: the degrees wound (`th`) and the length
///       come (`len`) every half degree; its whole length in px (`total`); the
///       darts on one arm (`n`); the frames from a pen going live to its
///       spiral coming alive (`live`); and for each dart of the left spiral's
///       first arm its bearing from the centre (`ang`), radius (`r`) and the
///       arm's heading there (`dir`).
function sylvia_spiral() {
    static _sp = undefined;
    if (_sp != undefined) return _sp;

    var _wound = SYLVIA_SPI_TURNS * 360;
    var _steps = ceil(_wound / 0.5);
    var _th = array_create(_steps + 1, 0);
    var _len = array_create(_steps + 1, 0);
    var _l = 0;
    var _px = 0;
    var _py = 0;
    for (var _i = 0; _i <= _steps; _i++) {
        var _a = min(_wound, _i * 0.5);
        var _r = sylvia_spiral_r(_a);
        var _x = lengthdir_x(_r, SYLVIA_SPI_A0 + _a);
        var _y = lengthdir_y(_r, SYLVIA_SPI_A0 + _a);
        if (_i > 0) _l += point_distance(_px, _py, _x, _y);
        _th[_i] = _a;
        _len[_i] = _l;
        _px = _x;
        _py = _y;
    }

    var _total = floor(_l);
    var _n = floor(_total / SYLVIA_SPI_GAP) + 1;
    var _s = {
        th: _th, len: _len, total: _total, n: _n,
        live: SYLVIA_SPI_REACH + ceil(_total / SYLVIA_SPI_PEN)
              + SYLVIA_SPI_PAUSE,
        ang: array_create(_n, 0), r: array_create(_n, 0),
        dir: array_create(_n, 0),
    };
    for (var _k = 0; _k < _n; _k++) {
        var _w = sylvia_spiral_wound(_s, _k * SYLVIA_SPI_GAP);
        _s.ang[_k] = SYLVIA_SPI_A0 + _w;
        _s.r[_k] = sylvia_spiral_r(_w);
        _s.dir[_k] = sylvia_spiral_dir(_w);
    }
    _sp = _s;
    return _sp;
}

// ---------------------------------------------------------------------------
// The pens and the darts
// ---------------------------------------------------------------------------

/// @desc Send a pair of spirals' pens out from `_e`, one for each arm of a
///       spiral each side; `_fling` picks how they come alive.
function sylvia_spirals(_e, _fling) {
    for (var _m = 1; _m >= -1; _m -= 2) {
        for (var _j = 0; _j < SYLVIA_SPI_ARMS; _j++) {
            // `m` is 1 for the left spiral and -1 for its mirror image; `off`
            // turns the arm round the centre from the first.
            var _sv = {
                m: _m,
                off: _j * 360 / SYLVIA_SPI_ARMS,
                ox: _e.x - _m * SYLVIA_SPI_DX, oy: _e.y + SYLVIA_SPI_DY,
                sx: _e.x, sy: _e.y,
                // N1's left spiral is cyan; N2 swaps the colours.
                col: ((_m > 0) != _fling) ? BCOL_CYAN : BCOL_MAGENTA,
                fling: _fling,
                laid: 0,            // darts the pen has laid
                spin_task: undefined,
            };
            if (_fling) _sv.spin_task = method(_sv, sylvia_spin_task);
            bullet_task(fire(_e.x, _e.y, 0, 270, BSHAPE_BALL, _sv.col),
                        method(_sv, sylvia_pen_task));
        }
    }
}

/// @desc An arm's bearing `_a` from its centre, turned by the arm's share
///       (`off`) and mirrored for the right spiral.
function sylvia_arm_ang(_sv, _a) {
    return (_sv.m > 0) ? _a + _sv.off : 180 - (_a + _sv.off);
}

/// @desc A pen's task, bound to its arm: it eases from him to the spiral's
///       centre, winds out along the arm laying darts, and fades where it
///       ends.
function sylvia_pen_task(_u) {
    var _sp = sylvia_spiral();
    var _t = _u.life;
    if (_t <= SYLVIA_SPI_REACH) {
        var _e = 1 - sqr(1 - _t / SYLVIA_SPI_REACH);
        _u.x = lerp(sx, ox, _e);
        _u.y = lerp(sy, oy, _e);
        return false;
    }

    var _s = min(_sp.total, (_t - SYLVIA_SPI_REACH) * SYLVIA_SPI_PEN);
    var _a = sylvia_spiral_wound(_sp, _s);
    var _r = sylvia_spiral_r(_a);
    var _ang = sylvia_arm_ang(self, SYLVIA_SPI_A0 + _a);
    _u.x = ox + lengthdir_x(_r, _ang);
    _u.y = oy + lengthdir_y(_r, _ang);
    while (laid < _sp.n && laid * SYLVIA_SPI_GAP <= _s) {
        sylvia_lay(self, laid, _t);
        laid++;
    }

    if (_s >= _sp.total) {
        _u.bmod = BMod.Plain;
        _u.mod_s = undefined;
        _u.spd = 0;
        bullet_fade(_u);
    }
    return false;
}

/// @desc Pen `_sv` lays dart `_k` of its arm on pair frame `_t`: still, with
///       the short mark a shed bullet gets, and one bounce. It points the way
///       it will leave: along the arm for a peel, round the centre the way
///       the spiral spins for a fling.
function sylvia_lay(_sv, _k, _t) {
    var _sp = sylvia_spiral();
    var _ang = sylvia_arm_ang(_sv, _sp.ang[_k]);
    var _dir = _sv.fling ? _ang - _sv.m * 90
                         : sylvia_arm_ang(_sv, _sp.dir[_k]);
    var _u = fire(_sv.ox + lengthdir_x(_sp.r[_k], _ang),
                  _sv.oy + lengthdir_y(_sp.r[_k], _ang),
                  0, _dir, SYLVIA_SPI_SHOT, _sv.col, BULLET_SPLIT_DELAY);
    if (_u == undefined) return;
    bullet_bounce(_u, 1);

    // The pair's clock on the dart's first live frame (its life 0).
    var _at = _t + BULLET_SPLIT_DELAY + 1;
    if (_sv.fling) {
        _u.mod_a = _k;
        _u.mod_b = _at;
        bullet_task(_u, _sv.spin_task);
    } else {
        // Outer end first, the innermost `SYLVIA_PEEL_SPAN` frames later.
        var _go = ceil(_sp.live
                       + SYLVIA_PEEL_SPAN * (_sp.n - 1 - _k) / _sp.n);
        bullet_accel_at(_u, _go - _at, SYLVIA_PEEL_ACC, SYLVIA_PEEL_VTO);
    }
}

/// @desc A spinning spiral's dart, bound to its arm (`mod_a` is its index,
///       `mod_b` the pair's clock on its first live frame): still until the
///       spiral comes alive, carried round the centre as it spins up, then let
///       go along its circle.
function sylvia_spin_task(_u) {
    var _sp = sylvia_spiral();
    var _v = _u.mod_b + _u.life - _sp.live;
    if (_v < 0) return false;

    // Degrees turned so far: each frame's spin since it came alive, summed.
    var _turned = (_v <= SYLVIA_FLING_RAMP)
        ? SYLVIA_FLING_SPIN * _v * (_v + 1) / (2 * SYLVIA_FLING_RAMP)
        : SYLVIA_FLING_SPIN * ((SYLVIA_FLING_RAMP + 1) / 2
                               + _v - SYLVIA_FLING_RAMP);
    var _k = _u.mod_a;
    var _r = _sp.r[_k];
    var _ang = sylvia_arm_ang(self, _sp.ang[_k]) - m * _turned;
    _u.x = ox + lengthdir_x(_r, _ang);
    _u.y = oy + lengthdir_y(_r, _ang);
    if (_v < SYLVIA_FLING_AT) return false;

    var _w = SYLVIA_FLING_SPIN * min(1, _v / SYLVIA_FLING_RAMP);
    _u.bmod = BMod.Plain;
    _u.mod_s = undefined;
    _u.dir = _ang - m * 90;
    _u.spd = degtorad(_w) * _r + SYLVIA_FLING_KICK;
    return false;
}

// ---------------------------------------------------------------------------
// Iris bloom
//
// Every `EVERY` frames `N` curved lasers (magenta and indigo by turns) wait
// `DELAY` frames as marks on a ring `R0` round him, then fire `OFF` degrees
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
// (`ROSETTE_*`), so the blades fold into a turning flower round him. The
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
// far as at a steady speed.
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
///       Rosette at `SLOW` of its pace, its blades launched and settling.
///       Its row puts him where Mika stands for his centred spells.
function draft_sylvia_slow_rosette(_e, _g, _t) {
    sylvia_iris(_e, _t, SYLVIA_IRIS_ROSETTE_ARC,
                ceil(SYLVIA_IRIS_ROSETTE_LIFE / SYLVIA_IRIS_SLOW), -1,
                SYLVIA_IRIS_SLOW, true);
}

/// @desc An iris bloom whose blades run `_life` frames on arcs of radius
///       `_arc`; given `_turn_deg`, blades and orbs turn that many degrees
///       round their arcs and then run straight. `_pace` scales its speeds,
///       and stretches its rhythm and marks to match. With `_settle`, the
///       blades launch and settle (`LAUNCH`, `SETTLE`), each running as far
///       as `_life` frames would take it at a steady speed.
function sylvia_iris(_e, _t, _arc, _life, _turn_deg = -1, _pace = 1,
                     _settle = false) {
    var _every = floor(SYLVIA_IRIS_EVERY / _pace + 0.5);
    var _delay = floor(SYLVIA_IRIS_DELAY / _pace + 0.5);
    var _spd = SYLVIA_IRIS_SPD * _pace;
    var _orb = SYLVIA_IRIS_ORB * _pace;
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
            var _l = laser_curve(_e.x + lengthdir_x(SYLVIA_IRIS_R0, _th),
                                 _e.y + lengthdir_y(SYLVIA_IRIS_R0, _th),
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
            var _o = fire(_e.x + lengthdir_x(SYLVIA_IRIS_R0, _at),
                          _e.y + lengthdir_y(SYLVIA_IRIS_R0, _at),
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
