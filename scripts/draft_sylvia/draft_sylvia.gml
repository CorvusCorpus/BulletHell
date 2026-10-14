/// @desc Two of Sylvia's non-spell sketches, "Two spirals: peel" and "Two
///       spirals: spin and fling" (the browser sketch `sylvia.js`), as drafts
///       on the drafting table. Placeholders: he has no stage or sprite yet.
///
/// At the top of each hold he sends out pens (balls) to two points beside and
/// below him. From each point the pens wind outward along the arms of a
/// spiral, laying still darts: the left spiral cyan, the right its mirror
/// image in magenta. A short pause after the last dart the spirals come alive.
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

/// @desc **Two spirals: peel** (Sylvia's, a draft).
function draft_sylvia_peel(_e, _g, _t) {
    var _cyc = SYLVIA_SPI_HOLD + BOSS_STEP_MOVE;
    if ((_t mod _cyc) == 0) sylvia_spirals(_e, false);
}

/// @desc **Two spirals: spin and fling** (Sylvia's, a draft).
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
                col: (_m > 0) ? BCOL_CYAN : BCOL_MAGENTA,
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
