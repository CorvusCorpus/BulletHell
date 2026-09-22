/// @desc The bullet pool and the firing API.
///
/// Bullets are structs in one flat array, not instances. A dead bullet is
/// swapped with the last live one (O(1) removal), and structs past the live
/// count are kept for reuse, so steady firing allocates nothing. Loops that
/// remove bullets run backwards.
///
/// The API follows Danmakufu ph3. `fire` (ph3's `CreateShotA1`) is the polar
/// model: direction, speed, acceleration, turn. `fire_xy` and `bullet_force`
/// are the Cartesian model (ph3's B-series), needed for forces along one axis
/// (falling, arcing). `dir` and `spd` are kept correct on both models. Events
/// at particular frames go in a per-bullet queue (`BQ`, ph3's `AddPattern`).

// ---------------------------------------------------------------------------
// The pool
// ---------------------------------------------------------------------------

/// @desc Create the pool. Called once, from obj_boot.
function danmaku_init() {
    global.bullets = [];
    global.bullet_n = 0;
    global.bullet_peak = 0;
    global.bullet_refused = 0;

    global.pshots = [];
    global.pshot_n = 0;
    global.pshot_seq = 0;       // see `pshot_fire`; only ever read by a draw
}

/// @desc A blank bullet struct. Only ever called when the pool has to grow.
function bullet_blank() {
    return {
        x: 0, y: 0, px: 0, py: 0,

        // The polar motion model.
        dir: 0, spd: 0, acc: 0, spd_min: -9999, spd_max: 9999,
        turn: 0,

        // The Cartesian model; `cart` says which one moves this bullet.
        cart: false,
        vx: 0, vy: 0, ax: 0, ay: 0,
        vx_min: -9999, vx_max: 9999, vy_min: -9999, vy_max: 9999,

        shape: BSHAPE_ORB, col: BCOL_BONE, r: 5, scale: 1,
        angle: 0, spin: 0,
        delay: 0, delay0: 0,

        // Fading out after a timed deletion (harmless while fading).
        fade_t: 0, fade_n: 1,

        life: 0,

        // Continuous behaviour, and the event queue. `q_n` entries are in use;
        // slots beyond it are kept for reuse.
        bmod: BMod.Plain, mod_a: 0, mod_b: 0,
        q: [], q_n: 0, q_i: 0,

        // Survives `bullet_clear_circle` (bombs), not `bullet_clear_all`.
        resist: false,

        grazed: false,
    };
}

/// @desc How many bullets are live.
function bullet_count() {
    return global.bullet_n;
}

/// @desc The live bullet at `_i`. Only valid for `_i < bullet_count()`.
function bullet_get(_i) {
    return global.bullets[_i];
}

/// @desc Take a slot from the pool, growing the array if needed. Returns
///       `undefined` at `BULLET_MAX`: the pool refuses rather than growing.
function bullet_alloc() {
    if (global.bullet_n >= BULLET_MAX) {
        global.bullet_refused++;
        return undefined;
    }
    var _i = global.bullet_n;
    if (_i >= array_length(global.bullets)) {
        array_push(global.bullets, bullet_blank());
    }
    global.bullet_n = _i + 1;
    if (global.bullet_n > global.bullet_peak) {
        global.bullet_peak = global.bullet_n;
    }
    return global.bullets[_i];
}

/// @desc Retire the bullet at index `_i`, in O(1).
function bullet_kill_at(_i) {
    var _last = global.bullet_n - 1;
    if (_i != _last) {
        var _tmp = global.bullets[_i];
        global.bullets[_i] = global.bullets[_last];
        global.bullets[_last] = _tmp;
    }
    global.bullet_n = _last;
}

// ---------------------------------------------------------------------------
// Firing
// ---------------------------------------------------------------------------

/// @desc Fire one bullet (ph3's `CreateShotA1`). Returns the bullet so the
///       caller can adjust it, or `undefined` if the pool is full -- every
///       caller must cope with that.
/// @param {real} _x
/// @param {real} _y
/// @param {real} _spd
/// @param {real} _dir     degrees, GameMaker's sense: 0 is right, 90 is up
/// @param {real} _shape   BSHAPE_*
/// @param {real} _col     BCOL_*
/// @param {real} _delay   frames spent as a harmless warning mark
function fire(_x, _y, _spd, _dir, _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    var _b = bullet_alloc();
    if (_b == undefined) return undefined;

    _b.x = _x;  _b.y = _y;
    _b.px = _x; _b.py = _y;
    _b.dir = _dir;
    _b.spd = _spd;
    _b.acc = 0;
    _b.spd_min = -9999;
    _b.spd_max = 9999;
    _b.turn = 0;
    // Reset every field: a reused struct still holds the previous bullet's
    // state.
    _b.cart = false;
    _b.vx = 0; _b.vy = 0; _b.ax = 0; _b.ay = 0;
    _b.vx_min = -9999; _b.vx_max = 9999;
    _b.vy_min = -9999; _b.vy_max = 9999;
    _b.shape = _shape;
    _b.col = _col;
    _b.r = global.bshape_radius[_shape];
    _b.scale = 1;
    _b.angle = _dir;
    // The shape's default spin (zero for oriented shapes, whose angle is their
    // heading). Starting at the firing angle scatters a ring's phases.
    _b.spin = global.bshape_spin[_shape];
    _b.delay = _delay;
    _b.delay0 = max(1, _delay);
    _b.fade_t = 0;
    _b.fade_n = 1;
    _b.life = 0;
    _b.bmod = BMod.Plain;
    _b.mod_a = 0;
    _b.mod_b = 0;
    _b.q_n = 0;
    _b.q_i = 0;
    _b.resist = false;
    _b.grazed = false;

    // A vote for this shape's shot cue; `sfx_step` turns a frame's votes into
    // one voice. Cast on fire rather than when the delay ends, because the
    // warning mark is what the player reacts to.
    sfx(sfx_for_shape(_shape));
    return _b;
}

/// @desc Fire one bullet from Cartesian velocity components (ph3's
///       `CreateShotB1`). `dir` and `spd` are derived, so oriented shapes
///       point the right way on their first frame.
function fire_xy(_x, _y, _vx, _vy, _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    var _b = fire(_x, _y, point_distance(0, 0, _vx, _vy),
                  point_direction(0, 0, _vx, _vy), _shape, _col, _delay);
    if (_b == undefined) return undefined;
    _b.cart = true;
    _b.vx = _vx;
    _b.vy = _vy;
    return _b;
}

/// @desc Give a bullet a per-axis force (with `fire_xy`, ph3's
///       `CreateShotB2`), converting a polar bullet to the Cartesian model.
///       Caps are terminal velocities read relative to the current velocity;
///       `BQ_KEEP` means no cap.
function bullet_force(_u, _ax, _ay, _vx_cap = BQ_KEEP, _vy_cap = BQ_KEEP) {
    if (_u == undefined) return undefined;
    if (!_u.cart) {
        _u.cart = true;
        _u.vx = lengthdir_x(_u.spd, _u.dir);
        _u.vy = lengthdir_y(_u.spd, _u.dir);
    }
    _u.ax = _ax;
    _u.ay = _ay;
    if (_vx_cap != BQ_KEEP) {
        _u.vx_min = min(_u.vx, _vx_cap);
        _u.vx_max = max(_u.vx, _vx_cap);
    }
    if (_vy_cap != BQ_KEEP) {
        _u.vy_min = min(_u.vy, _vy_cap);
        _u.vy_max = max(_u.vy, _vy_cap);
    }
    return _u;
}

/// @desc Put a bullet back on the polar model, keeping its velocity. Any
///       polar instruction (aim, move, accel, turn, a `BMod`) does this, so an
///       old force can't override it.
function bullet_repolar(_u) {
    _u.cart = false;
    _u.ax = 0;
    _u.ay = 0;
}

/// @desc Start a bullet fading out. It is harmless from this frame on.
function bullet_fade(_u, _frames = BULLET_FADE_DEFAULT) {
    if (_u == undefined) return undefined;
    if (_u.fade_t > 0) return _u;          // already on its way out
    _u.fade_n = max(1, _frames);
    _u.fade_t = _u.fade_n;
    return _u;
}

/// @desc The angle from one point to another. Takes the target explicitly, so
///       tests can aim at a coordinate.
function aim_at(_x, _y, _tx, _ty) {
    return point_direction(_x, _y, _tx, _ty);
}

/// @desc `_n` bullets evenly around a full circle, starting at `_dir0`.
function fire_ring(_x, _y, _n, _spd, _dir0, _shape, _col,
                   _delay = BULLET_DELAY_DEFAULT) {
    if (_n <= 0) return;
    var _step = 360 / _n;
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd, _dir0 + _i * _step, _shape, _col, _delay);
    }
}

/// @desc `_n` bullets spread across `_arc` degrees, centred on `_dir`. With
///       an odd `_n` one bullet goes down the aim line; with an even `_n` the
///       aim line is a gap.
function fire_fan(_x, _y, _n, _spd, _dir, _arc, _shape, _col,
                  _delay = BULLET_DELAY_DEFAULT) {
    if (_n <= 0) return;
    if (_n == 1) {
        fire(_x, _y, _spd, _dir, _shape, _col, _delay);
        return;
    }
    var _step = _arc / (_n - 1);
    var _start = _dir - _arc * 0.5;
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd, _start + _i * _step, _shape, _col, _delay);
    }
}

/// @desc `_n` bullets down one line at rising speeds (a "stack").
function fire_stack(_x, _y, _n, _spd0, _spd_step, _dir, _shape, _col,
                    _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd0 + _i * _spd_step, _dir, _shape, _col, _delay);
    }
}

/// @desc A ring of stacks: `_rings` speeds, `_n` around each.
function fire_ring_stack(_x, _y, _n, _rings, _spd0, _spd_step, _dir0,
                         _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    for (var _s = 0; _s < _rings; _s++) {
        fire_ring(_x, _y, _n, _spd0 + _s * _spd_step, _dir0, _shape, _col,
                  _delay);
    }
}

/// @desc A fan of stacks: `_rows` speeds, `_n` across `_arc` in each. Each
///       row is turned `_skew` degrees from the one in front (half a step
///       keeps the rows' gaps from lining up).
function fire_fan_stack(_x, _y, _n, _rows, _spd0, _spd_step, _dir, _arc,
                        _shape, _col, _delay = BULLET_DELAY_DEFAULT,
                        _skew = 0) {
    for (var _r = 0; _r < _rows; _r++) {
        fire_fan(_x, _y, _n, _spd0 + _r * _spd_step, _dir + _r * _skew, _arc,
                 _shape, _col, _delay);
    }
}

/// @desc `_n` bullets at random angles inside `_arc` of `_dir`, at random
///       speeds between `_spd0` and `_spd1`.
function fire_spray(_x, _y, _n, _spd0, _spd1, _dir, _arc, _shape, _col,
                    _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, random_range(_spd0, _spd1),
             _dir + random_range(-_arc * 0.5, _arc * 0.5), _shape, _col,
             _delay);
    }
}

// ---------------------------------------------------------------------------
// Scheduled events
//
// A bullet's queue is sorted on insert and walked off the front, so a bullet
// with no events costs one integer compare. Use the named helpers rather than
// `bullet_schedule` directly.
// ---------------------------------------------------------------------------

/// @desc Schedule one event at frame `_at` of a bullet's life. Sorted on
///       insert; refused past `BULLET_QUEUE_MAX`. Returns the bullet, and
///       passes `undefined` through (from a refused `fire`).
function bullet_schedule(_u, _at, _kind, _a = 0, _b = 0, _c = 0, _d = 0,
                         _e5 = 0) {
    if (_u == undefined) return undefined;
    if (_u.q_n >= BULLET_QUEUE_MAX) return _u;

    if (_u.q_n >= array_length(_u.q)) {
        array_push(_u.q,
                   { at: 0, kind: BQ.Aim, a: 0, b: 0, c: 0, d: 0, e: 0 });
    }
    var _e = _u.q[_u.q_n];
    _e.at = _at;
    _e.kind = _kind;
    _e.a = _a;
    _e.b = _b;
    _e.c = _c;
    _e.d = _d;
    _e.e = _e5;
    _u.q_n++;

    // Insertion sort by swapping references; usually already in order.
    var _i = _u.q_n - 1;
    while (_i > _u.q_i && _u.q[_i - 1].at > _u.q[_i].at) {
        var _tmp = _u.q[_i - 1];
        _u.q[_i - 1] = _u.q[_i];
        _u.q[_i] = _tmp;
        _i--;
    }
    return _u;
}

/// @desc Turn to face the target at `_at`, plus `_off` degrees (ph3's
///       `AddPatternA4`).
function bullet_aim_at(_u, _at, _off = 0) {
    return bullet_schedule(_u, _at, BQ.Aim, _off);
}

/// @desc Set speed and/or direction at `_at` (ph3's `AddPatternA1`).
///       `BQ_KEEP` leaves one alone.
function bullet_move_at(_u, _at, _spd = BQ_KEEP, _dir = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Move, _spd, _dir);
}

/// @desc Start accelerating at `_at`, toward `_cap`. The cap becomes the
///       speed floor or ceiling as `min`/`max` of the current speed and
///       `_cap`, so a floor above the current speed has no effect.
function bullet_accel_at(_u, _at, _acc, _cap = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Accel, _acc, _cap);
}

/// @desc Start turning at `_at`, `_turn` degrees a frame.
function bullet_turn_at(_u, _at, _turn) {
    return bullet_schedule(_u, _at, BQ.Turn, _turn);
}

/// @desc Apply a per-axis force at `_at` (see `bullet_force`).
function bullet_force_at(_u, _at, _ax, _ay, _vx_cap = BQ_KEEP,
                         _vy_cap = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Force, _ax, _ay, _vx_cap, _vy_cap);
}

/// @desc Burst into `_n` children at `_at` and die. `_dress(child, index)`, if
///       given, is called on each child as it is made.
function bullet_split_at(_u, _at, _n, _spd, _off = 0, _dress = undefined) {
    return bullet_schedule(_u, _at, BQ.Split, _spd, _off, _n, _dress);
}

/// @desc Shed `_n` children at `_at`, `_dist` pixels out, and keep going
///       (ph3's `ObjShot_AddShotA1`/`A2`). `_dress` as for a split.
function bullet_shed_at(_u, _at, _n, _spd, _off = 0, _dist = 0,
                        _dress = undefined) {
    return bullet_schedule(_u, _at, BQ.Shed, _spd, _off, _n, _dist, _dress);
}

/// @desc A wake: shed `_times` times, every `_period` frames from `_from`.
///       Each shed is its own queue entry, so `BULLET_QUEUE_MAX` limits how
///       long a wake can be.
function bullet_shed_every(_u, _from, _period, _times, _n, _spd, _off = 0,
                           _dist = 0, _dress = undefined) {
    for (var _k = 0; _k < _times; _k++) {
        bullet_shed_at(_u, _from + _k * _period, _n, _spd, _off, _dist,
                       _dress);
    }
    return _u;
}

/// @desc Change a bullet's shape and colour at `_at` (ph3's `AddPatternA3`).
///       The hitbox changes with it.
function bullet_graphic_at(_u, _at, _shape, _col) {
    return bullet_schedule(_u, _at, BQ.Graphic, _shape, _col);
}

/// @desc Give a bullet a lifetime (ph3's `ObjShot_SetDeleteFrame`); it fades
///       out rather than vanishing. Needed for anything that might never leave
///       the field (homing, orbiting), which would otherwise hold pool slots.
function bullet_expire_at(_u, _at, _frames = BULLET_FADE_DEFAULT) {
    return bullet_schedule(_u, _at, BQ.Fade, _frames);
}

/// @desc The burst behind `BQ.Split` and `BQ.Shed`. Children take the
///       parent's shape and colour and a short warning delay. `_dress(child,
///       k)` is called on each (with `undefined` if the pool refused it).
function bullet_spawn_children(_u, _n, _spd, _off, _dist, _dress = undefined) {
    var _count = max(1, _n);
    var _step = 360 / _count;
    var _has = is_method(_dress);
    for (var _k = 0; _k < _count; _k++) {
        var _dir = _u.dir + _off + _k * _step;
        var _c = fire(_u.x + lengthdir_x(_dist, _dir),
                      _u.y + lengthdir_y(_dist, _dir),
                      _spd, _dir, _u.shape, _u.col, BULLET_SPLIT_DELAY);
        if (_has) _dress(_c, _k);
    }
}

/// @desc Apply every scheduled event whose frame has come. Returns true if the
///       bullet is spent (a split), so the caller kills it.
function bullet_run_queue(_u, _tx, _ty) {
    while (_u.q_i < _u.q_n) {
        var _e = _u.q[_u.q_i];
        if (_u.life < _e.at) break;
        _u.q_i++;

        switch (_e.kind) {
            case BQ.Aim:
                _u.dir = aim_at(_u.x, _u.y, _tx, _ty) + _e.a;
                bullet_repolar(_u);
                break;

            case BQ.Move:
                if (_e.a != BQ_KEEP) _u.spd = _e.a;
                if (_e.b != BQ_KEEP) _u.dir = _e.b;
                bullet_repolar(_u);
                break;

            case BQ.Accel:
                _u.acc = _e.a;
                if (_e.b != BQ_KEEP) {
                    _u.spd_min = min(_u.spd, _e.b);
                    _u.spd_max = max(_u.spd, _e.b);
                }
                bullet_repolar(_u);
                break;

            case BQ.Turn:
                _u.turn = _e.a;
                bullet_repolar(_u);
                break;

            case BQ.Force:
                bullet_force(_u, _e.a, _e.b, _e.c, _e.d);
                break;

            case BQ.Split:
                bullet_spawn_children(_u, _e.c, _e.a, _e.b, 0, _e.d);
                return true;

            case BQ.Shed:
                bullet_spawn_children(_u, _e.c, _e.a, _e.b, _e.d, _e.e);
                break;

            case BQ.Graphic:
                _u.shape = _e.a;
                _u.col = _e.b;
                // Scaled by the bullet's own scale, so a small bullet keeps a
                // small hitbox.
                _u.r = global.bshape_radius[_e.a] * _u.scale;
                // The new shape's default spin.
                _u.spin = global.bshape_spin[_e.a];
                break;

            case BQ.Fade:
                bullet_fade(_u, _e.a);
                break;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

/// @desc Advance every bullet one frame and cull what has left the field.
///       `_tx`/`_ty` is what aiming and homing bullets aim at. Note the order:
///       acceleration is applied before moving, and `life` increments at the
///       end, so an event at frame N fires on step N + 1.
function bullet_step(_tx, _ty) {
    var _l = FIELD_X0 - CULL_MARGIN;
    var _t = FIELD_Y0 - CULL_MARGIN;
    var _r = FIELD_X1 + CULL_MARGIN;
    var _b = FIELD_Y1 + CULL_MARGIN;

    // Locals rather than `global.` lookups inside the hot loop.
    var _pool = global.bullets;
    var _oriented = global.bshape_oriented;

    // Backwards, because a swap-remove moves an unvisited bullet into `_i`.
    for (var _i = global.bullet_n - 1; _i >= 0; _i--) {
        var _u = _pool[_i];

        if (_u.delay > 0) {
            _u.delay--;
            // A delayed bullet (a warning mark) does not move.
            continue;
        }

        if (_u.fade_t > 0) {
            _u.fade_t--;
            if (_u.fade_t <= 0) {
                bullet_kill_at(_i);
                continue;
            }
        }

        if (_u.q_i < _u.q_n && bullet_run_queue(_u, _tx, _ty)) {
            bullet_kill_at(_i);
            continue;
        }

        if (_u.bmod != BMod.Plain) {
            bullet_apply_mod(_u, _tx, _ty);
        }

        if (_u.cart) {
            // Cartesian: each axis has its own force and cap.
            _u.vx = clamp(_u.vx + _u.ax, _u.vx_min, _u.vx_max);
            _u.vy = clamp(_u.vy + _u.ay, _u.vy_min, _u.vy_max);

            _u.px = _u.x;
            _u.py = _u.y;
            _u.x += _u.vx;
            _u.y += _u.vy;

            // Keep `dir` and `spd` correct. A stationary bullet keeps its
            // heading (`point_direction` of nothing would answer 0).
            _u.spd = point_distance(0, 0, _u.vx, _u.vy);
            if (_u.spd > 0) _u.dir = point_direction(0, 0, _u.vx, _u.vy);
        } else {
            _u.spd = clamp(_u.spd + _u.acc, _u.spd_min, _u.spd_max);
            _u.dir += _u.turn;

            _u.px = _u.x;
            _u.py = _u.y;
            _u.x += lengthdir_x(_u.spd, _u.dir);
            _u.y += lengthdir_y(_u.spd, _u.dir);
        }

        if (_oriented[_u.shape]) {
            _u.angle = _u.dir;
        } else {
            _u.angle += _u.spin;
        }

        _u.life++;

        if (_u.x < _l || _u.x > _r || _u.y < _t || _u.y > _b) {
            bullet_kill_at(_i);
        }
    }
}

/// @desc The per-frame behaviours (`BMod`). Both steer `dir`, so a bullet on
///       the Cartesian model is put back on the polar one first.
function bullet_apply_mod(_u, _tx, _ty) {
    if (_u.cart) bullet_repolar(_u);

    switch (_u.bmod) {
        case BMod.Home:
            // Turns toward the target by at most `mod_a` degrees a frame.
            var _want = aim_at(_u.x, _u.y, _tx, _ty);
            _u.dir += clamp(angle_difference(_want, _u.dir), -_u.mod_a, _u.mod_a);
            break;

        case BMod.Wander:
            _u.dir += dsin(_u.life * _u.mod_b) * _u.mod_a;
            break;
    }
}

// ---------------------------------------------------------------------------
// Clearing
// ---------------------------------------------------------------------------

/// @desc Sweep every bullet within `_rad` of a point; returns how many went.
///       `_to_items` drops a shard for every `CLEAR_ITEM_EVERY`th swept (in
///       sweep order). `resist` bullets survive this -- it is what bombs and
///       the clear after a hit use. `_each(x, y, col, n)`, if given, is called
///       for each swept bullet.
function bullet_clear_circle(_x, _y, _rad, _to_items, _each = undefined) {
    var _n = 0;
    var _r2 = _rad * _rad;
    for (var _i = global.bullet_n - 1; _i >= 0; _i--) {
        var _u = global.bullets[_i];
        if (_u.resist) continue;
        var _dx = _u.x - _x;
        var _dy = _u.y - _y;
        if (_dx * _dx + _dy * _dy > _r2) continue;
        if (_to_items && (_n mod CLEAR_ITEM_EVERY) == 0) {
            item_spawn(_u.x, _u.y, ItemKind.Tally);
        }
        if (_each != undefined) _each(_u.x, _u.y, _u.col, _n);
        fx_bullet_pop(_u.x, _u.y, _u.col);
        bullet_kill_at(_i);
        _n++;
    }
    return _n;
}

/// @desc Sweep the whole field, `resist` bullets included. What a phase
///       change does.
function bullet_clear_all(_to_items) {
    var _n = global.bullet_n;
    for (var _i = _n - 1; _i >= 0; _i--) {
        var _u = global.bullets[_i];
        if (_to_items && (_i mod CLEAR_ITEM_EVERY) == 0) {
            item_spawn(_u.x, _u.y, ItemKind.Tally);
        }
        fx_bullet_pop(_u.x, _u.y, _u.col);
    }
    global.bullet_n = 0;
    return _n;
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

/// @desc The distance from a point to a line segment. Bullets are tested
///       against the segment they moved this frame, so fast ones can't pass
///       through the player between frames.
function point_seg_dist(_px, _py, _x0, _y0, _x1, _y1) {
    var _dx = _x1 - _x0;
    var _dy = _y1 - _y0;
    var _len2 = _dx * _dx + _dy * _dy;
    if (_len2 <= 0.0001) {
        return point_distance(_px, _py, _x0, _y0);
    }
    var _t = clamp(((_px - _x0) * _dx + (_py - _y0) * _dy) / _len2, 0, 1);
    return point_distance(_px, _py, _x0 + _dx * _t, _y0 + _dy * _t);
}

/// @desc The index of the first bullet that hits a circle at (`_x`, `_y`),
///       or -1. A cheap bounding-box reject runs before the segment test.
function bullet_hit_index(_x, _y, _rad) {
    var _n = global.bullet_n;
    var _pool = global.bullets;
    for (var _i = 0; _i < _n; _i++) {
        var _u = _pool[_i];
        // Harmless while still a warning mark or while fading out.
        if (_u.delay > 0 || _u.fade_t > 0) continue;

        var _reach = _rad + _u.r;
        // The box covers the whole segment moved, not just the end point, or
        // a fast bullet would be rejected before the swept test.
        var _lo_x = min(_u.px, _u.x) - _reach;
        if (_x < _lo_x) continue;
        if (_x > max(_u.px, _u.x) + _reach) continue;
        var _lo_y = min(_u.py, _u.y) - _reach;
        if (_y < _lo_y) continue;
        if (_y > max(_u.py, _u.y) + _reach) continue;

        if (point_seg_dist(_x, _y, _u.px, _u.py, _u.x, _u.y) < _reach) {
            return _i;
        }
    }
    return -1;
}

/// @desc Mark every ungrazed bullet within `_rad` as grazed, and count them.
///       A bullet pays a graze once, ever.
function bullet_graze(_x, _y, _rad) {
    var _n = global.bullet_n;
    var _pool = global.bullets;
    var _count = 0;
    for (var _i = 0; _i < _n; _i++) {
        var _u = _pool[_i];
        if (_u.grazed || _u.delay > 0 || _u.fade_t > 0) continue;
        var _dx = _u.x - _x;
        var _dy = _u.y - _y;
        var _reach = _rad + _u.r;
        if (_dx * _dx + _dy * _dy < _reach * _reach) {
            _u.grazed = true;
            _count++;
        }
    }
    return _count;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc The sprite frame for a bullet. A shape's frames are its colours;
///       an animated shape's are colour-major with the animation inside (see
///       `tools/make_bullets.py`). The only place that index is computed.
function bullet_frame(_shape, _col, _life) {
    var _f = global.bshape_frames[_shape];
    if (_f <= 1) return _col;
    return _col * _f + ((_life div 3) mod _f);
}

/// @desc Draw every bullet: live bullets first, then the warning marks
///       additively on top, so a warning is never hidden under a live bullet.
function bullet_draw() {
    var _n = global.bullet_n;

    for (var _i = 0; _i < _n; _i++) {
        var _u = global.bullets[_i];
        if (_u.delay > 0) continue;
        draw_sprite_ext(global.bshape_sprite[_u.shape],
                        bullet_frame(_u.shape, _u.col, _u.life),
                        _u.x, _u.y, _u.scale, _u.scale, _u.angle,
                        c_white,
                        (_u.fade_t > 0) ? _u.fade_t / _u.fade_n : 1);
    }

    // The marks: additive, oversized, shrinking onto where the bullet will
    // be.
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < _n; _i++) {
        var _u = global.bullets[_i];
        if (_u.delay <= 0) continue;
        var _t = _u.delay / _u.delay0;                 // 1 at birth, 0 at live
        var _s = _u.scale * (1 + (BULLET_DELAY_SCALE - 1) * _t);
        draw_sprite_ext(global.bshape_sprite[_u.shape],
                        bullet_frame(_u.shape, _u.col, 0),
                        _u.x, _u.y, _s, _s, _u.angle,
                        c_white, 0.30 * (1 - _t) + 0.14);
    }
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The player's shots: a separate, smaller pool (tested against enemies, carry
// damage, never graze).
// ---------------------------------------------------------------------------

function pshot_fire(_x, _y, _spd, _dir, _dmg) {
    if (global.pshot_n >= PSHOT_MAX) return undefined;
    var _i = global.pshot_n;
    if (_i >= array_length(global.pshots)) {
        array_push(global.pshots, {
            x: 0, y: 0, px: 0, py: 0, dir: 0, spd: 0, dmg: 0, life: 0,
            flick: 0,
        });
    }
    global.pshot_n = _i + 1;
    var _s = global.pshots[_i];
    _s.x = _x;  _s.y = _y;
    _s.px = _x; _s.py = _y;
    _s.dir = _dir;
    _s.spd = _spd;
    _s.dmg = _dmg;
    _s.life = 0;
    // Each shot starts at a different phase of the flame animation, so two
    // barrels fired on one frame don't flicker in lockstep.
    global.pshot_seq = (global.pshot_seq + 3) mod 8;
    _s.flick = global.pshot_seq;
    return _s;
}

function pshot_kill_at(_i) {
    var _last = global.pshot_n - 1;
    if (_i != _last) {
        var _tmp = global.pshots[_i];
        global.pshots[_i] = global.pshots[_last];
        global.pshots[_last] = _tmp;
    }
    global.pshot_n = _last;
}

function pshot_step() {
    for (var _i = global.pshot_n - 1; _i >= 0; _i--) {
        var _s = global.pshots[_i];
        _s.px = _s.x;
        _s.py = _s.y;
        _s.x += lengthdir_x(_s.spd, _s.dir);
        _s.y += lengthdir_y(_s.spd, _s.dir);
        _s.life++;
        if (_s.x < FIELD_X0 - 60 || _s.x > FIELD_X1 + 60
            || _s.y < FIELD_Y0 - 60 || _s.y > FIELD_Y1 + 60) {
            pshot_kill_at(_i);
        }
    }
}

function pshot_count() {
    return global.pshot_n;
}
