/// @desc Flight routes: fodder that flies a list of legs (sweep in on a curve,
///       hold, circle a point, dive at the player, leave) and fires whatever
///       its wave gives it on the way.
///
/// A route is an array of legs, each a small immutable struct, so one route
/// is shared by every foe of a formation; a foe's progress along it lives in
/// its own `mem`. Coordinates are field coordinates (`FIELD_X0/Y0` are added
/// here). A foe spawned `mirror`ed flies its route reflected left to right:
/// x becomes `FIELD_W - x`, orbits turn the other way and exits lean the
/// other way, so a wave's two sides are one route.
///
/// A foe only fires while it is inside the field, so nothing shoots from off
/// screen. A route should end in `leg_exit`; one that runs out leaves
/// upward.

enum Leg {
    Curve,      // a quadratic Bezier from where it is to a point
    Hold,       // stay put
    Orbit,      // swing round a centre
    Aim,        // travel toward where the player was when the leg began
    Exit,       // leave in a direction, speeding up, and retire off the field
    Appear,     // materialise where it is: unshootable, harmless, fading in
    Path,       // placed each frame by a function (a formation's shape)
}

enum Ease {
    Linear,
    Out,        // fast, then settling
    In,         // slow, then away
    InOut,
}

/// @desc `_t` (0 to 1) eased.
function ease_apply(_kind, _t) {
    _t = clamp(_t, 0, 1);
    switch (_kind) {
        case Ease.Out:   return 1 - (1 - _t) * (1 - _t) * (1 - _t);
        case Ease.In:    return _t * _t * _t;
        case Ease.InOut: return _t * _t * (3 - 2 * _t);
    }
    return _t;
}

// ---------------------------------------------------------------------------
// Legs
// ---------------------------------------------------------------------------

/// @desc Curve from wherever the foe is to (`_x`, `_y`), pulled toward the
///       control point (`_cx`, `_cy`), over `_dur` frames.
function leg_curve(_x, _y, _cx, _cy, _dur, _ease = Ease.InOut) {
    return { kind: Leg.Curve, x: _x, y: _y, cx: _cx, cy: _cy,
             dur: max(1, _dur), ease: _ease };
}

/// @desc A straight line to (`_x`, `_y`).
function leg_to(_x, _y, _dur, _ease = Ease.InOut) {
    return { kind: Leg.Curve, x: _x, y: _y, cx: undefined, cy: undefined,
             dur: max(1, _dur), ease: _ease };
}

function leg_hold(_dur) {
    return { kind: Leg.Hold, dur: max(1, _dur) };
}

/// @desc Swing `_deg` degrees round (`_cx`, `_cy`) (positive is
///       anticlockwise on screen), from wherever the foe is, ending at radius
///       `_r1` (or keeping its radius, for -1).
function leg_orbit(_cx, _cy, _deg, _dur, _r1 = -1, _ease = Ease.Linear) {
    return { kind: Leg.Orbit, cx: _cx, cy: _cy, deg: _deg, r1: _r1,
             dur: max(1, _dur), ease: _ease };
}

/// @desc Travel `_dist` pixels toward where the player is when the leg
///       begins, stopping at least `_short` pixels short of them.
function leg_aim(_dist, _dur, _ease = Ease.InOut, _short = 150) {
    return { kind: Leg.Aim, dist: _dist, dur: max(1, _dur), ease: _ease,
             short: _short };
}

/// @desc Leave along `_dir` (degrees; mirrored with the route), accelerating
///       by `_acc` a frame up to `_spd`. The foe retires once it is clear of
///       the field.
function leg_exit(_dir, _spd, _acc = 0.2) {
    return { kind: Leg.Exit, dir: _dir, spd: _spd, acc: _acc, dur: 1,
             radial: false };
}

/// @desc Leave straight away from the centre of the last orbit or path it
///       flew round (a formation breaking outward).
function leg_exit_radial(_spd, _acc = 0.2) {
    return { kind: Leg.Exit, dir: 0, spd: _spd, acc: _acc, dur: 1,
             radial: true };
}

/// @desc Placed each frame for `_dur` frames by `_fn(foe, k, frame)`, which
///       sets the foe's `x` and `y` (field coordinates plus `FIELD_X0/Y0`,
///       as everywhere else) with `k` running 0 to 1. It may set `mem.ox` and
///       `mem.oy` to the centre it is turning round, for `leg_exit_radial`.
function leg_path(_fn, _dur) {
    return { kind: Leg.Path, fn: _fn, dur: max(1, _dur) };
}

/// @desc Materialise where it stands over `_dur` frames: drawn fading in over
///       a summoning glyph, and neither shootable nor harmful until it is
///       whole.
function leg_appear(_dur) {
    return { kind: Leg.Appear, dur: max(1, _dur) };
}

// ---------------------------------------------------------------------------
// Spawning
// ---------------------------------------------------------------------------

/// @desc Put a foe on a route. (`_x`, `_y`) is in field coordinates, before
///       mirroring. `_fire(foe, run, t)` is called every frame the foe is
///       inside the field, `t` counting frames since it spawned. `_opt` may
///       carry `mirror` (fly the route reflected), `scale` (drawn size and hit
///       radius), `drops` (`[red, blue, gold]`) and `data` (anything the fire
///       function wants).
function foe_spawn(_kind, _x, _y, _hp, _route, _fire, _opt = undefined) {
    var _mirror = (_opt != undefined) && (_opt[$ "mirror"] ?? false);
    var _drops = (_opt == undefined) ? undefined : _opt[$ "drops"];
    var _fx = _mirror ? (FIELD_W - _x) : _x;
    var _e = enemy_spawn(_kind, FIELD_X0 + _fx, FIELD_Y0 + _y, _hp, foe_act,
                         BCOL_GOLD,
                         (_drops == undefined) ? 0 : _drops[0],
                         (_drops == undefined) ? 1 : _drops[1],
                         (_drops == undefined) ? 2 : _drops[2]);
    if (_e == undefined) return undefined;
    var _scale = (_opt == undefined) ? 1 : (_opt[$ "scale"] ?? 1);
    _e.scale = _scale;
    _e.r = enemy_radius(_kind) * _scale;
    _e.mem = {
        route: _route,
        fire: _fire,
        side: _mirror ? -1 : 1,
        data: (_opt == undefined) ? undefined : _opt[$ "data"],
        leg: -1,
        lt: 0,          // frames into the current leg
        ft: 0,          // frames since it spawned
        // Where the current leg began, and what it worked out then.
        x0: _e.x, y0: _e.y,
        ox: 0, oy: 0, a0: 0, rad0: 0,
        tx: 0, ty: 0,
        spd: 0,
        edir: 0,
        // 0 to 1 while materialising (`leg_appear`), -1 otherwise.
        appear: -1,
    };
    foe_next_leg(_e, undefined);
    return _e;
}

/// @desc A timeline event that spawns one foe (`foe_spawn`'s arguments).
function ev_foe(_at, _kind, _x, _y, _hp, _route, _fire, _opt = undefined) {
    // The fields avoid the names of functions (`fire`) and built-in
    // variables (`x`, `y`): inside a bound method those win over a struct
    // member, and `fire` here would hand the foe the firing function itself.
    return ev(_at, method({ kind_: _kind, fx: _x, fy: _y, life: _hp,
                            legs: _route, pattern: _fire, opt: _opt },
                          function(_g) {
        foe_spawn(kind_, fx, fy, life, legs, pattern, opt);
    }));
}

// ---------------------------------------------------------------------------
// Reading a foe's progress (for fire functions)
// ---------------------------------------------------------------------------

/// @desc Which leg of its route the foe is on.
function foe_leg(_e) {
    return _e.mem.leg;
}

/// @desc Frames into the current leg.
function foe_leg_t(_e) {
    return _e.mem.lt;
}

/// @desc +1, or -1 for a foe flying its route mirrored.
function foe_side(_e) {
    return _e.mem.side;
}

/// @desc Is the foe on leg `_leg`, `_t` frames in?
function foe_at(_e, _leg, _t) {
    return _e.mem.leg == _leg && _e.mem.lt == _t;
}

/// @desc Is the foe inside the field, at least `_in` pixels from its edge?
function foe_inside(_e, _in = 0) {
    return _e.x > FIELD_X0 + _in && _e.x < FIELD_X1 - _in
           && _e.y > FIELD_Y0 + _in && _e.y < FIELD_Y1 - _in;
}

// ---------------------------------------------------------------------------
// The driver
// ---------------------------------------------------------------------------

/// @desc Start the leg after the current one, from where the foe is.
function foe_next_leg(_e, _g) {
    var _m = _e.mem;
    _m.leg++;
    _m.lt = 0;
    _m.x0 = _e.x;
    _m.y0 = _e.y;
    _m.appear = -1;
    _e.alpha = 1;

    if (_m.leg >= array_length(_m.route)) return;
    var _l = _m.route[_m.leg];
    var _s = _m.side;
    switch (_l.kind) {
        case Leg.Curve:
            _m.tx = FIELD_X0 + ((_s > 0) ? _l.x : FIELD_W - _l.x);
            _m.ty = FIELD_Y0 + _l.y;
            if (_l.cx == undefined) {
                _m.ox = (_m.x0 + _m.tx) * 0.5;
                _m.oy = (_m.y0 + _m.ty) * 0.5;
            } else {
                _m.ox = FIELD_X0 + ((_s > 0) ? _l.cx : FIELD_W - _l.cx);
                _m.oy = FIELD_Y0 + _l.cy;
            }
            break;

        case Leg.Orbit:
            _m.ox = FIELD_X0 + ((_s > 0) ? _l.cx : FIELD_W - _l.cx);
            _m.oy = FIELD_Y0 + _l.cy;
            _m.a0 = point_direction(_m.ox, _m.oy, _e.x, _e.y);
            _m.rad0 = point_distance(_m.ox, _m.oy, _e.x, _e.y);
            break;

        case Leg.Aim:
            // Without a run (a test), aim straight down.
            var _px = (_g == undefined) ? _e.x : _g.player.x;
            var _py = (_g == undefined) ? FIELD_Y1 : _g.player.y;
            var _d = point_direction(_e.x, _e.y, _px, _py);
            var _far = min(_l.dist,
                           max(0, point_distance(_e.x, _e.y, _px, _py) - _l.short));
            _m.tx = _e.x + lengthdir_x(_far, _d);
            _m.ty = _e.y + lengthdir_y(_far, _d);
            break;

        case Leg.Exit:
            // Starts off at a third of its speed, whatever it was doing.
            _m.spd = _l.spd * 0.33;
            _m.edir = _l.radial ? point_direction(_m.ox, _m.oy, _e.x, _e.y)
                                : ((_s > 0) ? _l.dir : 180 - _l.dir);
            break;

        case Leg.Appear:
            _m.appear = 0;
            _e.alpha = 0;
            _e.shootable = false;
            _e.touch = false;
            break;
    }
}

/// @desc One frame of a foe on a route (its `act`).
function foe_act(_e, _g) {
    var _m = _e.mem;
    var _n = array_length(_m.route);

    if (_m.leg >= _n) {
        // The route ran out without an exit: leave upward.
        _e.y -= 6;
        if (_e.y < FIELD_Y0 - 120) _e.retire = true;
        return;
    }

    var _l = _m.route[_m.leg];
    var _done = false;
    var _f = (_m.lt + 1) / _l.dur;

    switch (_l.kind) {
        case Leg.Curve:
        case Leg.Aim:
            var _k = ease_apply(_l.ease, _f);
            if (_l.kind == Leg.Aim) {
                _e.x = lerp(_m.x0, _m.tx, _k);
                _e.y = lerp(_m.y0, _m.ty, _k);
            } else {
                var _u = 1 - _k;
                _e.x = _u * _u * _m.x0 + 2 * _u * _k * _m.ox + _k * _k * _m.tx;
                _e.y = _u * _u * _m.y0 + 2 * _u * _k * _m.oy + _k * _k * _m.ty;
            }
            _done = (_f >= 1);
            break;

        case Leg.Hold:
            _done = (_f >= 1);
            break;

        case Leg.Orbit:
            var _k = ease_apply(_l.ease, _f);
            var _a = _m.a0 + _l.deg * _m.side * _k;
            var _rr = (_l.r1 < 0) ? _m.rad0 : lerp(_m.rad0, _l.r1, _k);
            _e.x = _m.ox + lengthdir_x(_rr, _a);
            _e.y = _m.oy + lengthdir_y(_rr, _a);
            _done = (_f >= 1);
            break;

        case Leg.Exit:
            _m.spd = min(_l.spd, _m.spd + _l.acc);
            _e.x += lengthdir_x(_m.spd, _m.edir);
            _e.y += lengthdir_y(_m.spd, _m.edir);
            // Clear of the field by more than its own size.
            var _clear = 60 + _e.r;
            if (_e.x < FIELD_X0 - _clear || _e.x > FIELD_X1 + _clear
                || _e.y < FIELD_Y0 - _clear || _e.y > FIELD_Y1 + _clear) {
                _e.retire = true;
            }
            break;

        case Leg.Path:
            // Through a local: a bare call to a struct member reads to
            // `check_unknown_functions` as an unknown function.
            var _fn = _l.fn;
            _fn(_e, min(1, _f), _m.lt);
            _done = (_f >= 1);
            break;

        case Leg.Appear:
            _m.appear = min(1, _f);
            _e.alpha = _m.appear;
            if (_f >= 1) {
                _e.shootable = true;
                _e.touch = true;
                _done = true;
            }
            break;
    }

    // Only while inside the field, so nothing fires from off screen.
    if (_m.fire != undefined && foe_inside(_e, 8)) {
        _m.fire(_e, _g, _m.ft);
    }

    _m.lt++;
    _m.ft++;
    if (_done) foe_next_leg(_e, _g);
}
