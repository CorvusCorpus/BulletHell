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
/// - Lane: it can flash the path it is about to be thrown down
///   (`ring_lane_flash`). Drawn only.
/// - Track: it can show the circle it orbits on round its `src` (`track`),
///   as a line under everything. Drawn only.
/// - Depth: in a 2.5D effect it can be nearer or further (`depth`, a factor on
///   its size that its collision follows), dimmed (`shade`), or behind its
///   caster (`behind`), where it is drawn before the enemies and neither
///   hurts, grazes nor blocks.
///
/// Every ring is `RING_R`, times its `depth` (owner's rule). The pool
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
        // No radius field: every ring is `RING_R`, times `depth` below.
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
        arc_col: -1,             // the arc's colour; -1 is the ring's `col`
        graze_t: 0,
        // False for a ring that may be carried off the field and back (one
        // riding the player), which would otherwise be culled.
        cull: true,
        // 2.5D depth: `depth` scales its size, drawn and collided alike
        // (`ring_radius`); `shade` dims it (0 to 1, drawn only); a ring
        // `behind` is drawn before the enemies, so its caster hides it, and
        // neither hurts, grazes nor blocks (`ring_touchable`).
        depth: 1, shade: 0,
        behind: false,
        // A steady light in the band (0 to 1), drawn like a charge's heat but
        // harmless: the band's lethal width doesn't change.
        glow: 0,
        // The radius of the orbit it rides round its `src`, shown as a line
        // in `track_col` (a colour) at `track_a` (0 is none); drawn only.
        track: 0, track_a: 0, track_col: c_white,
        // The path it is about to be thrown down (`ring_lane_flash`), and
        // frames since the flash (-1 is "none"); drawn only.
        lane_t: -1, lane_life: 1,
        lane_x0: 0, lane_y0: 0, lane_dir: 0, lane_len: 0,
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
    _g.arc_col = -1;
    _g.graze_t = 0;
    _g.cull = true;
    _g.depth = 1;
    _g.shade = 0;
    _g.behind = false;
    _g.glow = 0;
    _g.track = 0;
    _g.track_a = 0;
    _g.track_col = c_white;
    _g.lane_t = -1;
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

/// @desc Flash the path this ring is about to be thrown down, for `_life`
///       frames: the ground its metal will sweep from (`_x0`, `_y0`) along
///       `_dir` to the point `_len` pixels on where it stops, drawn from
///       wherever the ring is along it (`ring_draw_lanes`). Decoration only:
///       the lane neither blocks nor kills.
function ring_lane_flash(_ring, _x0, _y0, _dir, _len, _life) {
    if (_ring == undefined) return;
    _ring.lane_x0 = _x0;
    _ring.lane_y0 = _y0;
    _ring.lane_dir = _dir;
    _ring.lane_len = _len;
    _ring.lane_t = 0;
    _ring.lane_life = max(1, _life);
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

/// @desc Can the metal hurt, graze or block this frame: solid, and not
///       behind its caster?
function ring_touchable(_ring) {
    return ring_solid(_ring) && !_ring.behind;
}

/// @desc The ring's radius this frame: `RING_R`, nearer or further by its
///       `depth`.
function ring_radius(_ring) {
    return RING_R * _ring.depth;
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
    return _ring.x + lengthdir_x(ring_radius(_ring), _dir);
}

function ring_rim_y(_ring, _dir) {
    return _ring.y + lengthdir_y(ring_radius(_ring), _dir);
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
    return _ring.x + ring_vel_x(_ring) * _frames
           + lengthdir_x(ring_radius(_ring), _dir);
}

function ring_rim_at_y(_ring, _dir, _frames) {
    return _ring.y + ring_vel_y(_ring) * _frames
           + lengthdir_y(ring_radius(_ring), _dir);
}

/// @desc How far a point is from the band (zero on the metal). Hits and
///       grazes use the same measurement at different widths.
function ring_band_dist(_ring, _x, _y) {
    return abs(point_distance(_ring.x, _ring.y, _x, _y) - ring_radius(_ring));
}

/// @desc Does the segment from (`_x0`,`_y0`) to (`_x1`,`_y1`) cross the band?
///       Swept, because player shots move further per frame than the band is
///       thick. The distance from the centre along a segment covers every value
///       between its closest approach and its furthest end, so the segment
///       meets the annulus exactly when that interval overlaps the band.
function ring_seg_crosses(_ring, _x0, _y0, _x1, _y1) {
    var _rad = ring_radius(_ring);
    var _half = RING_BAND_HALF * _ring.depth;
    var _lo = point_seg_dist(_ring.x, _ring.y, _x0, _y0, _x1, _y1);
    if (_lo > _rad + _half) return false;
    var _hi = max(point_distance(_ring.x, _ring.y, _x0, _y0),
                  point_distance(_ring.x, _ring.y, _x1, _y1));
    return _hi >= _rad - _half;
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
        if (_r.lane_t >= 0) {
            _r.lane_t++;
            if (_r.lane_t > _r.lane_life) _r.lane_t = -1;
        }
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

        // Culled once it is entirely off the field, unless `cull` is off.
        var _out = RING_R + CULL_MARGIN;
        if (_r.cull
            && (_r.x < FIELD_X0 - _out || _r.x > FIELD_X1 + _out
                || _r.y < FIELD_Y0 - _out || _r.y > FIELD_Y1 + _out)) {
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
            if (!ring_touchable(_r)) continue;
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
    return RING_BAND_HALF * _ring.depth
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
///       its arc? The circle was at (`_px`, `_py`) when the frame began.
///
///       The metal is tested swept, since a thrown ring can move further in a
///       frame than the band is wide. Seen from the ring, the circle moved
///       from where it was against where the ring was to where it is against
///       where the ring is; the distance from the centre along that path
///       covers every value between its closest approach and its further end,
///       so the metal was touched if that range meets the band. When neither
///       moved, this is the band distance.
function ring_hits(_ring, _x, _y, _rad, _px = _x, _py = _y) {
    if (ring_touchable(_ring)) {
        var _k = _rad + ring_kill_half(_ring);
        var _ax = _px - _ring.px;
        var _ay = _py - _ring.py;
        var _bx = _x - _ring.x;
        var _by = _y - _ring.y;
        var _lo = point_seg_dist(0, 0, _ax, _ay, _bx, _by);
        var _hi = max(point_distance(0, 0, _ax, _ay),
                      point_distance(0, 0, _bx, _by));
        var _r = ring_radius(_ring);
        if (_lo < _r + _k && _hi > _r - _k) return true;
    }
    var _a = ring_arc_ends(_ring);
    if (_a != undefined
        && point_seg_dist(_x, _y, _a.x0, _a.y0, _a.x1, _a.y1)
           < _rad + ring_arc_half()) {
        return true;
    }
    return false;
}

/// @desc Is any ring touching this circle (swept from (`_px`, `_py`), as
///       `ring_hits`)?
function ring_any_hit(_x, _y, _rad, _px = _x, _py = _y) {
    for (var _i = 0; _i < global.ring_n; _i++) {
        if (ring_hits(global.rings[_i], _x, _y, _rad, _px, _py)) return true;
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
        if (ring_touchable(_r)) {
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
///       pulses during the warning and is full while hot; a ring's `glow`
///       lights it as far without a charge.
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
    _c = max(_c, _ring.glow);
    if (_ring.form > 0) {
        var _in = 1 - _ring.form / max(1, RING_FORM);
        return { scale: 0.72 + 0.28 * _in, alpha: _in * 0.85, charge: _c };
    }
    return { scale: 1, alpha: 1, charge: _c };
}

/// @desc The rings passing behind their caster (`behind`), and their lanes,
///       drawn before the enemies so the boss hides them.
function ring_draw_behind() {
    ring_draw_tracks();
    ring_draw_lanes(true);
    ring_draw_bodies(true);
}

/// @desc Every ring's orbit track (`track`): a solid line round the circle it
///       rides on about its `src`, in `track_col`, full at the circle and
///       fading to nothing `RING_TRACK_HALF` either side, so its edge is soft
///       at any slant. Drawn before the enemies and every ring.
function ring_draw_tracks() {
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        if (_r.track <= 0 || _r.src == undefined) continue;
        var _a = _r.track_a * ring_visual(_r).alpha;
        if (_a <= 0.01) continue;
        var _cx = _r.src.x;
        var _cy = _r.src.y;
        var _col = _r.track_col;
        var _rad = _r.track;
        // Too small to draw as a circle (a track can grow from nothing).
        if (_rad < 2 * RING_TRACK_HALF) continue;
        var _n = max(24, ceil(180 / darccos(clamp(1 - RING_TRACK_SAG / _rad,
                                                  -1, 1))));
        var _step = 360 / _n;
        // The outer half, then the inner: each a strip from the full line to
        // nothing.
        for (var _s = -1; _s <= 1; _s += 2) {
            var _edge = _rad + _s * RING_TRACK_HALF;
            draw_primitive_begin(pr_trianglestrip);
            for (var _k = 0; _k <= _n; _k++) {
                var _ux = dcos(_k * _step);
                var _uy = -dsin(_k * _step);
                draw_vertex_colour(_cx + _ux * _rad, _cy + _uy * _rad, _col,
                                   _a);
                draw_vertex_colour(_cx + _ux * _edge, _cy + _uy * _edge,
                                   _col, 0);
            }
            draw_primitive_end();
        }
    }
}

/// @desc Every other ring, with the lanes under them and the arcs over.
function ring_draw() {
    ring_draw_lanes(false);
    ring_draw_bodies(false);
    ring_draw_arcs();
}

/// @desc The rings whose `behind` is `_behind`.
function ring_draw_bodies(_behind) {
    var _half = sprite_get_width(spr_ring) * 0.5 * RING_SPR_LINE;

    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        if (_r.behind != _behind) continue;
        var _v = ring_visual(_r);
        if (_v.alpha <= 0.01) continue;
        var _col = global.bullet_colour[_r.col];
        var _k = (ring_radius(_r) * _v.scale) / _half;
        // Dimmed by its shade: the metal toward black, the light with it.
        var _lit = 1 - _r.shade;

        draw_sprite_ext(spr_ring, 0, _r.x, _r.y, _k, _k, _r.ang,
                        merge_colour(c_black, c_white, _lit), _v.alpha);

        // The light stays put while the pattern turns under it, so these two
        // are drawn unrotated (`tools/make_rings.py`). The sheen is the
        // reflections, added. The glint scales what is already there
        // (dst * (1 + src)), which lifts the chain's gold and leaves the black
        // alone; that blend ignores alpha, so it fades through its colour.
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_ring_sheen, 0, _r.x, _r.y, _k, _k, 0, c_white,
                        _v.alpha * _lit);
        gpu_set_blendmode_ext(bm_dest_colour, bm_one);
        draw_sprite_ext(spr_ring_glint, 0, _r.x, _r.y, _k, _k, 0,
                        merge_colour(c_black, c_white, _v.alpha * _lit), 1);

        // The charge: the band heats up in the ring's hue.
        if (_v.charge > 0.01) {
            gpu_set_blendmode(bm_add);
            draw_sprite_ext(spr_ring_heat, 0, _r.x, _r.y, _k, _k, _r.ang,
                            _col, _v.alpha * _v.charge * 0.9);
            var _gs = (ring_radius(_r) * 2.8) / sprite_get_width(spr_fx_bloom);
            draw_sprite_ext(spr_fx_bloom, 0, _r.x, _r.y, _gs, _gs, 0, _col,
                            _v.alpha * _v.charge * 0.10);
        }
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The lane flash (`ring_lane_flash`) of every ring whose `behind` is
///       `_behind`, under the rings drawn with it. The lane is the capsule the
///       metal sweeps, one outline round both ends, so it wraps the ring
///       behind and rounds off where the ring stops. It is soft-edged strips
///       offset from that outline: a hot hairline in a warm bloom, a fainter
///       second rule just inside it, and light falling off inward from the
///       edge. It pops in, a pulse of light
///       runs down it to the stop, a four-pointed star flares there as the
///       pulse arrives, and it fades. Additive.
function ring_draw_lanes(_behind) {
    static _lp = { n: 0, px: [], py: [], nx: [], ny: [], sw: [] };
    // Rows of each band: offsets from the outline (negative is inward) and
    // their share of the band's alpha. The rows approximate curves that
    // meet zero gently, since a linear ramp shows an edge where it ends.
    static _rim_d = [0, -6, -13.5, -30, -(RING_R + RING_BAND_HALF)];
    static _rim_a = [1, 0.585, 0.238, 0, 0];
    static _bloom_d = [11, 6.6, 3.3, 0, -3.3, -6.6, -11];
    static _bloom_a = [0, 0.352, 0.784, 1, 0.784, 0.352, 0];
    static _core_d = [1.8, 0, -1.8];
    static _core_a = [0, 1, 0];
    static _rule_d = [-5.8, -7, -8.2];
    static _rule_a = [0, 1, 0];

    var _w = RING_R + RING_BAND_HALF;
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        if (_r.lane_t < 1 || _r.fade >= 0 || _r.behind != _behind) continue;

        // `ring_step` has already counted this frame, so the flash's first
        // frame is 0 here. Up over three frames, held, then eased out.
        var _f = _r.lane_t - 1;
        var _in = 1;
        if (_f < 2) {
            _in = (_f + 1) / 3;
        } else if (_f >= 5) {
            _in = sqr(max(0, 1 - (_f - 5) / max(1, _r.lane_life - 5)));
        }
        if (_in <= 0.005) continue;

        var _col = global.bullet_colour[_r.col];
        // The hairline is whitest at the pop and cools as it fades.
        var _core = merge_colour(_col, c_white,
                                 0.65 + 0.35 * max(0, 1 - _f / 8));

        // From level with the ring's centre to the stop.
        var _ux = lengthdir_x(1, _r.lane_dir);
        var _uy = lengthdir_y(1, _r.lane_dir);
        var _k0 = clamp((_r.x - _r.lane_x0) * _ux + (_r.y - _r.lane_y0) * _uy,
                        0, _r.lane_len);
        var _sx = _r.lane_x0 + _ux * _k0;
        var _sy = _r.lane_y0 + _uy * _k0;
        var _len = _r.lane_len - _k0;

        // The pulse runs from behind the ring to past the stop in ten frames,
        // easing out, then dies away over four.
        var _run = 1 - power(1 - min(1, _f / 10), 3);
        var _pos = -_w + (_len + 2 * _w) * _run;
        var _pg = max(0, 1 - max(0, _f - 10) / 4);
        ring_lane_loop(_lp, _sx, _sy, _ux, _uy, _len, _w, _pos, _pg);

        var _fill = power(_in, 1.5);
        ring_lane_rows(_lp, _rim_d, _rim_a, 0.42 * _fill, _col, 1.5,
                       0.19 * sqrt(_in));
        ring_lane_rows(_lp, _bloom_d, _bloom_a, 0.30 * _in, _col, 0.8, 0);
        ring_lane_rows(_lp, _rule_d, _rule_a, 0.45 * _in, _col, 0.6, 0);
        ring_lane_rows(_lp, _core_d, _core_a, _in, _core, 0.6, 0);

        // The star at the stop, as the pulse gets there.
        var _arr = _f - 5.5;
        if (_arr > -1) {
            var _sa = max(0, 1 - _arr / 12) * clamp((_arr + 1) / 2, 0, 1);
            if (_sa > 0.01) {
                ring_lane_star(_sx + _ux * _len, _sy + _uy * _len,
                               _r.lane_dir, _sa, _core, _col);
            }
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Fill `_lp` with a lane's outline once round, closing where it
///       began: one side from (`_sx`, `_sy`) to the stop `_len` pixels along
///       (`_ux`, `_uy`), the round end, the other side back, and the round
///       end behind. Each point has its outward normal and the pulse's
///       strength there: a bell `_pos` pixels along the lane, times `_pg`.
function ring_lane_loop(_lp, _sx, _sy, _ux, _uy, _len, _w, _pos, _pg) {
    var _nx = -_uy;
    var _ny = _ux;
    var _ex = _sx + _ux * _len;
    var _ey = _sy + _uy * _len;
    // Sides in steps short enough to carry the pulse; ends in 24.
    var _steps = max(1, ceil(_len / 24));
    var _cap = 24;
    _lp.n = 0;
    for (var _k = 0; _k <= _steps; _k++) {
        var _s = _len * _k / _steps;
        ring_lane_point(_lp, _sx + _ux * _s, _sy + _uy * _s, _nx, _ny, _w, _s,
                        _pos, _pg);
    }
    for (var _k = 1; _k < _cap; _k++) {
        var _a = 90 - 180 * _k / _cap;
        ring_lane_point(_lp, _ex, _ey, dcos(_a) * _ux + dsin(_a) * _nx,
                        dcos(_a) * _uy + dsin(_a) * _ny, _w,
                        _len + dcos(_a) * _w, _pos, _pg);
    }
    for (var _k = _steps; _k >= 0; _k--) {
        var _s = _len * _k / _steps;
        ring_lane_point(_lp, _sx + _ux * _s, _sy + _uy * _s, -_nx, -_ny, _w,
                        _s, _pos, _pg);
    }
    for (var _k = 1; _k <= _cap; _k++) {
        var _a = -90 - 180 * _k / _cap;
        ring_lane_point(_lp, _sx, _sy, dcos(_a) * _ux + dsin(_a) * _nx,
                        dcos(_a) * _uy + dsin(_a) * _ny, _w, dcos(_a) * _w,
                        _pos, _pg);
    }
}

/// @desc Add one point of a lane's outline to `_lp`: `_w` out from
///       (`_cx`, `_cy`) along the unit normal (`_nx`, `_ny`), `_s` pixels
///       along the lane.
function ring_lane_point(_lp, _cx, _cy, _nx, _ny, _w, _s, _pos, _pg) {
    var _i = _lp.n;
    _lp.px[_i] = _cx + _nx * _w;
    _lp.py[_i] = _cy + _ny * _w;
    _lp.nx[_i] = _nx;
    _lp.ny[_i] = _ny;
    _lp.sw[_i] = _pg * exp(-sqr((_s - _pos) / 60));
    _lp.n = _i + 1;
}

/// @desc One band of a lane, as a triangle strip right round the outline in
///       `_lp` between each pair of neighbouring rows (offsets `_ds`, alphas
///       `_as` times `_scale`). Where the pulse is, each alpha is raised by
///       `_gain` times it, and `_add` times it is added.
function ring_lane_rows(_lp, _ds, _as, _scale, _col, _gain, _add) {
    for (var _j = 0; _j < array_length(_ds) - 1; _j++) {
        var _da = _ds[_j];
        var _db = _ds[_j + 1];
        var _aa = _as[_j] * _scale;
        var _ab = _as[_j + 1] * _scale;
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _lp.n; _i++) {
            var _p = _lp.sw[_i];
            var _x = _lp.px[_i];
            var _y = _lp.py[_i];
            var _nx = _lp.nx[_i];
            var _ny = _lp.ny[_i];
            draw_vertex_colour(_x + _nx * _da, _y + _ny * _da, _col,
                               min(1, _aa * (1 + _gain * _p) + _add * _p));
            draw_vertex_colour(_x + _nx * _db, _y + _ny * _db, _col,
                               min(1, _ab * (1 + _gain * _p) + _add * _p));
        }
        draw_primitive_end();
    }
}

/// @desc The four-pointed star that flares where a lane ends: a small glow
///       and two crossed streaks, one along the lane (`_dir`).
function ring_lane_star(_x, _y, _dir, _a, _core, _glow) {
    var _bw = sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _x, _y, 44 / _bw, 44 / _bw, 0, _glow,
                    _a * 0.5);
    var _sw = sprite_get_width(spr_fx_spark);
    var _sh = sprite_get_height(spr_fx_spark);
    var _arm = 92 * (0.7 + 0.3 * _a);
    for (var _k = 0; _k < 4; _k++) {
        draw_sprite_ext(spr_fx_spark, 0, _x, _y, _arm / _sw, 5 / _sh,
                        _dir + _k * 90, _core, _a);
    }
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

        var _col = global.bullet_colour[(_r.arc_col >= 0) ? _r.arc_col
                                                          : _r.col];
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
