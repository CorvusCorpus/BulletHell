/// @desc Rings: furniture a boss puts down, used by Mika's fight
///       (`stage_sanctum`).
///
/// A ring can't be destroyed. What it does is a field on the struct:
/// - Block: player shots crossing its band are absorbed (enemy bullets and the
///   bomb's seals are not). The hole in the middle does not block.
/// - Kill: the band hurts to touch once the ring has formed. Charging it
///   (after a visible warning) widens the lethal band to the whole cuff.
/// - Arc: two rings can be linked by a lethal line of current.
/// - Fire: `act(ring, run, frame)` runs every frame like a boss attack.
///
/// Every ring is `RING_R`; there is no per-ring radius (owner's rule). The pool
/// works like the bullet pool: flat array, swap-remove, reused structs, and a
/// refusal past `RING_MAX`.

// ---------------------------------------------------------------------------
// The pool
// ---------------------------------------------------------------------------

function ring_init() {
    global.rings = [];
    global.ring_n = 0;
    // Each ring gets a serial (`gen`), because pooled structs are reused: a
    // remembered ring is checked with `ring_valid`.
    global.ring_seq = 0;
}

function ring_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0,
        // Last frame's position. A ring carried by its `src` moves without
        // `vx`/`vy` changing, so this is its true travel (`ring_vel_x`).
        px: 0, py: 0,
        // No radius field: every ring is `RING_R`.
        ang: 0, spin: 0,
        col: BCOL_GOLD,
        gen: 0,
        t: 0,
        ttl: 0,                  // 0 is "until something says otherwise"
        form: RING_FORM,         // arriving: visible, harmless, and no block
        fade: -1,                // leaving; -1 is "not"
        warn: 0, hot: 0,         // charging, then charged
        src: undefined,          // a struct with x/y this ring rides
        ox: 0, oy: 0,
        act: undefined,          // function(_ring, _g, _t), every frame
        arc: undefined,          // another ring this one is strung to
        arc_gen: -1, arc_t: 0,
        graze_t: 0,
        alive: true,
    };
}

function ring_count() {
    return global.ring_n;
}

function ring_get(_i) {
    return global.rings[_i];
}

function ring_alloc() {
    if (global.ring_n >= RING_MAX) return undefined;
    var _i = global.ring_n;
    if (_i >= array_length(global.rings)) {
        array_push(global.rings, ring_blank());
    }
    global.ring_n = _i + 1;
    var _g = global.rings[_i];
    _g.vx = 0; _g.vy = 0;
    _g.ang = 0; _g.spin = 0;
    _g.t = 0;
    _g.ttl = 0;
    _g.form = RING_FORM;
    _g.fade = -1;
    _g.warn = 0; _g.hot = 0;
    _g.src = undefined; _g.ox = 0; _g.oy = 0;
    _g.act = undefined;
    _g.arc = undefined; _g.arc_gen = -1; _g.arc_t = 0;
    _g.graze_t = 0;
    _g.alive = true;
    global.ring_seq++;
    _g.gen = global.ring_seq;
    return _g;
}

function ring_kill_at(_i) {
    var _last = global.ring_n - 1;
    global.rings[_i].alive = false;
    if (_i != _last) {
        var _tmp = global.rings[_i];
        global.rings[_i] = global.rings[_last];
        global.rings[_last] = _tmp;
    }
    global.ring_n = _last;
}

/// @desc Remove every ring. Called at the end of an attack (rings never
///       leave on their own) and by `run_clear_field`.
function ring_clear_all() {
    var _n = global.ring_n;
    for (var _i = 0; _i < _n; _i++) global.rings[_i].alive = false;
    global.ring_n = 0;
    return _n;
}

/// @desc Is this still the ring the reference was taken from? `alive` catches
///       a swept ring; `gen` catches its slot being reused by a new ring.
function ring_valid(_ring, _gen) {
    return _ring != undefined && _ring.alive && _ring.gen == _gen;
}

// ---------------------------------------------------------------------------
// Putting one down
// ---------------------------------------------------------------------------

/// @desc A ring at a point, in a colour; `undefined` past the cap. It forms
///       over `RING_FORM` frames, during which it neither blocks nor kills.
function ring_new(_x, _y, _col = BCOL_GOLD, _ttl = 0) {
    var _g = ring_alloc();
    if (_g == undefined) return undefined;
    _g.x = _x; _g.y = _y;
    _g.px = _x; _g.py = _y;
    _g.col = _col;
    _g.ttl = _ttl;
    sfx(Sfx.WardClose);
    return _g;
}

/// @desc Ride something with an `x` and a `y` (usually the caster) at a
///       fixed offset.
function ring_attach(_ring, _src, _ox = 0, _oy = 0) {
    if (_ring == undefined) return;
    _ring.src = _src;
    _ring.ox = _ox;
    _ring.oy = _oy;
}

/// @desc Charge the band: `_warn` frames of visible build-up, then `_hot`
///       frames at full lethal width. Always give a non-zero warning.
function ring_charge(_ring, _warn, _hot) {
    if (_ring == undefined) return;
    _ring.warn = _warn;
    _ring.hot = _hot;
    sfx(Sfx.LaserCharge);
}

/// @desc String current between two rings for `_frames`. The far ring's `gen`
///       is kept, so the arc dies with it.
function ring_link(_a, _b, _frames) {
    if (_a == undefined || _b == undefined) return;
    _a.arc = _b;
    _a.arc_gen = _b.gen;
    _a.arc_t = _frames;
}

/// @desc Start a ring leaving. It stops blocking and killing at once; the
///       fade is only visual.
function ring_dismiss(_ring, _frames = RING_FADE) {
    if (_ring == undefined || _ring.fade >= 0) return;
    _ring.fade = _frames;
    _ring.hot = 0;
    _ring.warn = 0;
    _ring.arc_t = 0;
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// @desc Half the thickness of the metal, in pixels (the same for every
///       ring).
function ring_band_half() {
    return RING_BAND_HALF;
}

/// @desc Is the metal there this frame? False while forming and while leaving.
function ring_solid(_ring) {
    return _ring.alive && _ring.form <= 0 && _ring.fade < 0;
}

/// @desc Is the band charged (lit, and lethal at full width)? `warn` must be
///       tested: `ring_charge` sets `warn` and `hot` together, so `hot > 0`
///       alone would be true during the warning.
function ring_is_hot(_ring) {
    return _ring.warn <= 0 && _ring.hot > 0 && ring_solid(_ring);
}

/// @desc Is this ring's arc live, and is the far end still the ring it was?
function ring_arc_live(_ring) {
    return _ring.arc_t > 0 && ring_solid(_ring)
           && ring_valid(_ring.arc, _ring.arc_gen)
           && ring_solid(_ring.arc);
}

/// @desc A point on the band, at `_dir` degrees round it.
function ring_rim_x(_ring, _dir) {
    return _ring.x + lengthdir_x(RING_R, _dir);
}

function ring_rim_y(_ring, _dir) {
    return _ring.y + lengthdir_y(RING_R, _dir);
}

/// @desc How far the ring moved this frame, however it is being moved.
function ring_vel_x(_ring) {
    return _ring.x - _ring.px;
}

function ring_vel_y(_ring) {
    return _ring.y - _ring.py;
}

/// @desc Where the point at `_dir` on the band will be in `_frames` frames if
///       the ring keeps moving as it is. Fire from here with a delay of
///       `_frames`: a bullet's warning mark holds still, so firing at the
///       current rim of a moving ring puts the bullet inside the hole.
function ring_rim_at_x(_ring, _dir, _frames) {
    return _ring.x + ring_vel_x(_ring) * _frames + lengthdir_x(RING_R, _dir);
}

function ring_rim_at_y(_ring, _dir, _frames) {
    return _ring.y + ring_vel_y(_ring) * _frames + lengthdir_y(RING_R, _dir);
}

/// @desc How far a point is from the band (zero on the metal). Hits and
///       grazes use the same measurement at different widths.
function ring_band_dist(_ring, _x, _y) {
    return abs(point_distance(_ring.x, _ring.y, _x, _y) - RING_R);
}

/// @desc Does the segment from (`_x0`,`_y0`) to (`_x1`,`_y1`) cross the band?
///       Swept, because player shots move further per frame than the band is
///       thick. The distance from the centre along a segment covers every value
///       between its closest approach and its furthest end, so the segment
///       meets the annulus exactly when that interval overlaps the band.
function ring_seg_crosses(_ring, _x0, _y0, _x1, _y1) {
    var _half = RING_BAND_HALF;
    var _lo = point_seg_dist(_ring.x, _ring.y, _x0, _y0, _x1, _y1);
    if (_lo > RING_R + _half) return false;
    var _hi = max(point_distance(_ring.x, _ring.y, _x0, _y0),
                  point_distance(_ring.x, _ring.y, _x1, _y1));
    return _hi >= RING_R - _half;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function ring_step(_g) {
    for (var _i = global.ring_n - 1; _i >= 0; _i--) {
        var _r = global.rings[_i];

        // Recorded before moving, so `ring_vel_x` is this frame's travel when
        // the ring's `act` runs.
        _r.px = _r.x;
        _r.py = _r.y;

        if (_r.src != undefined) {
            _r.x = _r.src.x + _r.ox;
            _r.y = _r.src.y + _r.oy;
        } else {
            _r.x += _r.vx;
            _r.y += _r.vy;
        }

        _r.ang += _r.spin;

        if (_r.form > 0) _r.form--;
        if (_r.graze_t > 0) _r.graze_t--;
        if (_r.arc_t > 0) _r.arc_t--;

        // The charge: the warning counts down, then the band is hot.
        if (_r.warn > 0) {
            _r.warn--;
            if (_r.warn == 0 && _r.hot > 0) {
                sfx(Sfx.LaserFire);
                fx_flash_at(_r.x, _r.y, global.bullet_colour[_r.col], 0.30);
            }
        } else if (_r.hot > 0) {
            _r.hot--;
        }

        // The behaviour runs while the ring is still forming, too.
        if (_r.act != undefined && _r.fade < 0) _r.act(_r, _g, _r.t);

        _r.t++;

        if (_r.ttl > 0 && _r.t >= _r.ttl && _r.fade < 0) {
            ring_dismiss(_r);
        }

        if (_r.fade >= 0) {
            _r.fade--;
            if (_r.fade < 0) {
                ring_kill_at(_i);
                continue;
            }
        }

        // Culled once it is entirely off the field.
        var _out = RING_R + CULL_MARGIN;
        if (_r.x < FIELD_X0 - _out || _r.x > FIELD_X1 + _out
            || _r.y < FIELD_Y0 - _out || _r.y > FIELD_Y1 + _out) {
            ring_kill_at(_i);
        }
    }
}

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------

/// @desc Absorb every player shot that crosses a ring's metal; returns how
///       many. Must run before `enemy_take_shots`, so an absorbed shot never
///       reaches the boss (`check_rings_block_before_enemies`). The spark is
///       placed on the band, not at the shot's end position.
function ring_block_shots() {
    var _stopped = 0;
    for (var _s = global.pshot_n - 1; _s >= 0; _s--) {
        var _sh = global.pshots[_s];
        for (var _i = global.ring_n - 1; _i >= 0; _i--) {
            var _r = global.rings[_i];
            if (!ring_solid(_r)) continue;
            if (!ring_seg_crosses(_r, _sh.px, _sh.py, _sh.x, _sh.y)) {
                continue;
            }

            var _dir = point_direction(_r.x, _r.y, _sh.x, _sh.y);
            var _hx = ring_rim_x(_r, _dir);
            var _hy = ring_rim_y(_r, _dir);
            fx_spark(_hx, _hy, _dir + 180 + random_range(-50, 50),
                     random_range(1, 3), global.bullet_colour[_r.col], 10, 10);
            pshot_kill_at(_s);
            _stopped++;
            break;      // one shot is stopped by one ring
        }
    }
    return _stopped;
}

// ---------------------------------------------------------------------------
// Hurting
// ---------------------------------------------------------------------------

/// @desc How far either side of the band's centre line it kills: less than
///       the drawn metal when cold, the whole drawn cuff when charged, never
///       wider.
function ring_kill_half(_ring) {
    return RING_BAND_HALF
           * (ring_is_hot(_ring) ? RING_HOT_KILL_FRAC : RING_KILL_FRAC);
}

/// @desc Half the width an arc kills at. The drawn bolt's jitter stays
///       inside it (`ring_draw_arcs`).
function ring_arc_half() {
    return RING_ARC_WID * 0.34;
}

/// @desc The ends of a ring's live arc, or `undefined`.
function ring_arc_ends(_ring) {
    if (!ring_arc_live(_ring)) return undefined;
    return { x0: _ring.x, y0: _ring.y, x1: _ring.arc.x, y1: _ring.arc.y };
}

/// @desc Is this ring touching a circle, by its metal (whenever solid) or by
///       its arc?
function ring_hits(_ring, _x, _y, _rad) {
    if (ring_solid(_ring)
        && ring_band_dist(_ring, _x, _y) < _rad + ring_kill_half(_ring)) {
        return true;
    }
    var _a = ring_arc_ends(_ring);
    if (_a != undefined
        && point_seg_dist(_x, _y, _a.x0, _a.y0, _a.x1, _a.y1)
           < _rad + ring_arc_half()) {
        return true;
    }
    return false;
}

/// @desc Is any ring touching this circle?
function ring_any_hit(_x, _y, _rad) {
    for (var _i = 0; _i < global.ring_n; _i++) {
        if (ring_hits(global.rings[_i], _x, _y, _rad)) return true;
    }
    return false;
}

/// @desc Pay a graze for every ring (band or arc) the player is riding, on a
///       `RING_GRAZE_CD` cooldown per ring; returns how many paid. The band is
///       the kill width plus `GRAZE_R`.
function ring_graze(_x, _y, _rad) {
    var _n = 0;
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        if (_r.graze_t > 0) continue;
        var _near = false;
        if (ring_solid(_r)) {
            _near = ring_band_dist(_r, _x, _y)
                    < _rad + ring_kill_half(_r) + GRAZE_R;
        }
        if (!_near) {
            var _a = ring_arc_ends(_r);
            if (_a != undefined) {
                _near = point_seg_dist(_x, _y, _a.x0, _a.y0, _a.x1, _a.y1)
                        < _rad + ring_arc_half() + GRAZE_R;
            }
        }
        if (!_near) continue;
        _r.graze_t = RING_GRAZE_CD;
        _n++;
    }
    return _n;
}

// ---------------------------------------------------------------------------
// Firing from a ring
// ---------------------------------------------------------------------------

/// @desc `_n` bullets evenly round the band, each travelling straight out.
///       Fired from the metal (led for movement over the delay), not the
///       centre, so the warning marks don't appear in the hole.
function ring_fire_rim(_ring, _n, _spd, _dir0, _shape, _col,
                       _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        var _a = _dir0 + _i * (360 / _n);
        fire(ring_rim_at_x(_ring, _a, _delay),
             ring_rim_at_y(_ring, _a, _delay), _spd, _a,
             _shape, _col, _delay);
    }
}

/// @desc As `ring_fire_rim`, but each bullet travels along the band's tangent
///       (`_sign` picks the direction round).
function ring_fire_tangent(_ring, _n, _spd, _dir0, _shape, _col, _sign = 1,
                           _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        var _a = _dir0 + _i * (360 / _n);
        fire(ring_rim_at_x(_ring, _a, _delay),
             ring_rim_at_y(_ring, _a, _delay), _spd,
             _a + 90 * _sign, _shape, _col, _delay);
    }
}

/// @desc A beam from the ring's centre that follows the ring (`src`).
function ring_beam(_ring, _dir, _len, _wid, _col, _warn, _hot, _fade = 18) {
    var _l = laser_beam(_ring.x, _ring.y, _dir, _len, _wid, _col, _warn, _hot,
                        _fade);
    if (_l != undefined) _l.src = _ring;
    return _l;
}

// ---------------------------------------------------------------------------
// Drawing
//
// Rings are drawn under the bullets, so they can be opaque without hiding
// one.
// ---------------------------------------------------------------------------

/// @desc Scale, alpha and charge glow for a ring this frame. The charge
///       pulses during the warning and is full while hot.
function ring_visual(_ring) {
    if (_ring.fade >= 0) {
        var _f = _ring.fade / max(1, RING_FADE);
        return { scale: 1 + (1 - _f) * 0.14, alpha: _f, charge: 0 };
    }
    var _c = 0;
    if (_ring.warn > 0 && _ring.hot > 0) {
        var _p = 1 - _ring.warn / max(1, RING_WARN);
        _c = _p * (0.45 + 0.55 * abs(dsin(_ring.warn * 9)));
    } else if (_ring.hot > 0) {
        _c = 1;
    }
    if (_ring.form > 0) {
        var _in = 1 - _ring.form / max(1, RING_FORM);
        return { scale: 0.72 + 0.28 * _in, alpha: _in * 0.85, charge: _c };
    }
    return { scale: 1, alpha: 1, charge: _c };
}

function ring_draw() {
    var _half = sprite_get_width(spr_ring) * 0.5 * RING_SPR_LINE;

    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        var _v = ring_visual(_r);
        if (_v.alpha <= 0.01) continue;
        var _col = global.bullet_colour[_r.col];
        var _k = (RING_R * _v.scale) / _half;

        draw_sprite_ext(spr_ring, 0, _r.x, _r.y, _k, _k, _r.ang, c_white,
                        _v.alpha);

        // The light stays put while the pattern turns under it, so these two
        // are drawn unrotated (`tools/make_rings.py`). The sheen is the
        // reflections, added. The glint scales what is already there
        // (dst * (1 + src)), which lifts the chain's gold and leaves the black
        // alone; that blend ignores alpha, so it fades through its colour.
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_ring_sheen, 0, _r.x, _r.y, _k, _k, 0, c_white,
                        _v.alpha);
        gpu_set_blendmode_ext(bm_dest_colour, bm_one);
        draw_sprite_ext(spr_ring_glint, 0, _r.x, _r.y, _k, _k, 0,
                        merge_colour(c_black, c_white, _v.alpha), 1);

        // The charge: the band heats up in the ring's hue.
        if (_v.charge > 0.01) {
            gpu_set_blendmode(bm_add);
            draw_sprite_ext(spr_ring_heat, 0, _r.x, _r.y, _k, _k, _r.ang,
                            _col, _v.alpha * _v.charge * 0.9);
            var _gs = (RING_R * 2.8) / sprite_get_width(spr_fx_bloom);
            draw_sprite_ext(spr_fx_bloom, 0, _r.x, _r.y, _gs, _gs, 0, _col,
                            _v.alpha * _v.charge * 0.10);
        }
        gpu_set_blendmode(bm_normal);
    }

    ring_draw_arcs();
}

/// @desc The current strung between two rings: a jagged run of bars along
///       the same segment the collision uses. The jitter is capped inside the
///       lethal width and comes from a hash of the node, frame and ring
///       serial, not `random`.
function ring_draw_arcs() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        var _a = ring_arc_ends(_r);
        if (_a == undefined) continue;

        var _col = global.bullet_colour[_r.col];
        var _len = point_distance(_a.x0, _a.y0, _a.x1, _a.y1);
        if (_len < 1) continue;
        var _dir = point_direction(_a.x0, _a.y0, _a.x1, _a.y1);
        var _nx = lengthdir_x(1, _dir + 90);
        var _ny = lengthdir_y(1, _dir + 90);
        // Inside the band that kills.
        var _amp = min(ring_arc_half() * 0.9, _len * 0.03);

        var _px = _a.x0;
        var _py = _a.y0;
        for (var _k = 1; _k <= RING_ARC_NODES; _k++) {
            var _t = _k / RING_ARC_NODES;
            // Zero at both ends, so the bolt is pinned to the two rings.
            var _w = dsin(_t * 180) * _amp
                     * dsin(_k * 137 + _r.t * 43 + _r.gen * 61);
            var _qx = _a.x0 + (_a.x1 - _a.x0) * _t + _nx * _w;
            var _qy = _a.y0 + (_a.y1 - _a.y0) * _t + _ny * _w;
            var _sl = point_distance(_px, _py, _qx, _qy);
            if (_sl > 0.01) {
                laser_draw_bar(_px, _py, point_direction(_px, _py, _qx, _qy),
                               _sl + 1.5, RING_ARC_WID, _col, 0.9);
            }
            _px = _qx;
            _py = _qy;
        }
    }
    gpu_set_blendmode(bm_normal);
}
