/// @desc Lasers: the travelling ray, the telegraphed beam, and the curved
///       trail, in one pool.
///
/// A beam always has a warning phase first (its `_warn` is an ordinary
/// argument; never pass 0). A curved laser is the trail of a moving head: the
/// last `CURVE_NODES` positions it occupied, collided against segment by
/// segment. A laser only kills while firing, at about a third of its drawn
/// width.

function laser_init() {
    global.lasers = [];
    global.laser_n = 0;
}

function laser_blank() {
    return {
        kind: LaserKind.Beam,
        phase: LaserPhase.Warn,
        t: 0,
        x: 0, y: 0, dir: 0,
        len: 100, wid: 20, spd: 0, turn: 0,
        col: BCOL_BONE,
        warn: 60, hot: 120, fade: 20,
        src: undefined,          // a struct with x/y the origin follows
        // A world point the beam re-aims at every frame, or `undefined` to
        // keep its heading. With `src` too, the beam's root rides its caster
        // while its line pivots about this point.
        look: undefined,
        nx: [], ny: [], node_n: 0,
        // Grazed on a cooldown (a laser stands there; a bullet passes once).
        graze_t: 0, graze_cd: LASER_GRAZE_CD,
        resist: false,           // bomb-proof, as a bullet may be
        alive: true,
    };
}

function laser_alloc() {
    if (global.laser_n >= LASER_MAX) return undefined;
    var _i = global.laser_n;
    if (_i >= array_length(global.lasers)) {
        array_push(global.lasers, laser_blank());
    }
    global.laser_n = _i + 1;
    var _l = global.lasers[_i];
    _l.phase = LaserPhase.Warn;
    _l.t = 0;
    _l.spd = 0;
    _l.turn = 0;
    _l.src = undefined;
    _l.look = undefined;
    _l.node_n = 0;
    _l.graze_t = 0;
    _l.graze_cd = LASER_GRAZE_CD;
    _l.resist = false;
    _l.alive = true;
    return _l;
}

function laser_kill_at(_i) {
    var _last = global.laser_n - 1;
    if (_i != _last) {
        var _tmp = global.lasers[_i];
        global.lasers[_i] = global.lasers[_last];
        global.lasers[_last] = _tmp;
    }
    global.laser_n = _last;
}

function laser_count() {
    return global.laser_n;
}

// ---------------------------------------------------------------------------
// The three kinds
// ---------------------------------------------------------------------------

/// @desc An anchored beam that warns, fires, then fades.
/// @param {real} _warn  frames of warning line. **Never pass 0.**
function laser_beam(_x, _y, _dir, _len, _wid, _col, _warn, _hot, _fade = 18) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Beam;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.len = _len; _l.wid = _wid;
    _l.col = _col;
    _l.warn = _warn; _l.hot = _hot; _l.fade = _fade;
    // The charge cue sounds with the warning, not the beam.
    sfx(Sfx.LaserCharge);
    return _l;
}

/// @desc A bar of light that travels; no warning phase.
function laser_ray(_x, _y, _dir, _spd, _len, _wid, _col, _life) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Ray;
    _l.phase = LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.len = _len; _l.wid = _wid;
    _l.col = _col;
    _l.warn = 0; _l.hot = _life; _l.fade = 14;
    sfx(Sfx.LaserFire);
    return _l;
}

/// @desc A trail laid down by a head moving at `_spd` and turning `_turn`
///       degrees a frame. `_life` is how long the head lives; the trail then
///       drains away behind it.
function laser_curve(_x, _y, _dir, _spd, _turn, _wid, _col, _life) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Curve;
    _l.phase = LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.turn = _turn; _l.wid = _wid;
    _l.col = _col;
    _l.warn = 0; _l.hot = _life; _l.fade = CURVE_NODES;
    _l.node_n = 0;
    sfx(Sfx.LaserFire);
    return _l;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function laser_step() {
    for (var _i = global.laser_n - 1; _i >= 0; _i--) {
        var _l = global.lasers[_i];

        // A beam or ray with a `src` follows it.
        if (_l.src != undefined && _l.kind != LaserKind.Curve) {
            _l.x = _l.src.x;
            _l.y = _l.src.y;
        }

        _l.t++;
        if (_l.graze_t > 0) _l.graze_t--;
        switch (_l.kind) {
            case LaserKind.Beam: laser_step_beam(_l); break;
            case LaserKind.Ray:  laser_step_ray(_l);  break;
            case LaserKind.Curve: laser_step_curve(_l); break;
        }

        if (_l.phase == LaserPhase.Done) {
            laser_kill_at(_i);
        }
    }
}

function laser_step_beam(_l) {
    // A beam with `look` re-aims and ignores `turn`.
    if (_l.look != undefined) {
        _l.dir = point_direction(_l.x, _l.y, _l.look.x, _l.look.y);
    } else {
        _l.dir += _l.turn;
    }
    if (_l.phase == LaserPhase.Warn && _l.t >= _l.warn) {
        _l.phase = LaserPhase.Fire;
        _l.t = 0;
        fx_flash_at(_l.x, _l.y, global.bullet_colour[_l.col], 0.35);
        sfx(Sfx.LaserFire);
    } else if (_l.phase == LaserPhase.Fire && _l.t >= _l.hot) {
        _l.phase = LaserPhase.Fade;
        _l.t = 0;
    } else if (_l.phase == LaserPhase.Fade && _l.t >= _l.fade) {
        _l.phase = LaserPhase.Done;
    }
}

function laser_step_ray(_l) {
    _l.dir += _l.turn;
    _l.x += lengthdir_x(_l.spd, _l.dir);
    _l.y += lengthdir_y(_l.spd, _l.dir);

    if (_l.phase == LaserPhase.Fire && _l.t >= _l.hot) {
        _l.phase = LaserPhase.Fade;
        _l.t = 0;
    } else if (_l.phase == LaserPhase.Fade && _l.t >= _l.fade) {
        _l.phase = LaserPhase.Done;
    }

    // Culled when the whole ray, tail included, has left the field.
    var _tx = _l.x - lengthdir_x(_l.len, _l.dir);
    var _ty = _l.y - lengthdir_y(_l.len, _l.dir);
    if (min(_l.x, _tx) > FIELD_X1 + CULL_MARGIN
        || max(_l.x, _tx) < FIELD_X0 - CULL_MARGIN
        || min(_l.y, _ty) > FIELD_Y1 + CULL_MARGIN
        || max(_l.y, _ty) < FIELD_Y0 - CULL_MARGIN) {
        _l.phase = LaserPhase.Done;
    }
}

function laser_step_curve(_l) {
    if (_l.phase == LaserPhase.Fire) {
        _l.dir += _l.turn;
        _l.x += lengthdir_x(_l.spd, _l.dir);
        _l.y += lengthdir_y(_l.spd, _l.dir);
        curve_push(_l, _l.x, _l.y);
        if (_l.t >= _l.hot) {
            _l.phase = LaserPhase.Fade;
            _l.t = 0;
        }
    } else {
        // The head stops and the tail drains a node a frame; collision reads
        // the same nodes, so the drained part is no longer dangerous.
        curve_drop_oldest(_l);
        if (_l.node_n <= 1) {
            _l.phase = LaserPhase.Done;
        }
    }
}

/// @desc Push a node onto the trail, dropping the oldest once it is full.
///       Nodes are two parallel arrays of reals, not structs, for speed.
function curve_push(_l, _x, _y) {
    if (_l.node_n < CURVE_NODES) {
        _l.nx[_l.node_n] = _x;
        _l.ny[_l.node_n] = _y;
        _l.node_n++;
        return;
    }
    for (var _i = 0; _i < CURVE_NODES - 1; _i++) {
        _l.nx[_i] = _l.nx[_i + 1];
        _l.ny[_i] = _l.ny[_i + 1];
    }
    _l.nx[CURVE_NODES - 1] = _x;
    _l.ny[CURVE_NODES - 1] = _y;
}

function curve_drop_oldest(_l) {
    if (_l.node_n <= 0) return;
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        _l.nx[_i] = _l.nx[_i + 1];
        _l.ny[_i] = _l.ny[_i + 1];
    }
    _l.node_n--;
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

/// @desc Is a laser dangerous this frame? Only while firing (not during its
///       warning or its fade).
function laser_is_hot(_l) {
    return _l.phase == LaserPhase.Fire;
}

/// @desc How far a point is from a laser's spine. Hits and grazes use this
///       same measurement at different widths.
function laser_spine_dist(_l, _x, _y) {
    if (_l.kind == LaserKind.Curve) {
        var _best = 99999;
        for (var _i = 0; _i < _l.node_n - 1; _i++) {
            _best = min(_best, point_seg_dist(_x, _y, _l.nx[_i], _l.ny[_i],
                                              _l.nx[_i + 1], _l.ny[_i + 1]));
        }
        return _best;
    }

    // A ray's segment runs backwards from its head; a beam's runs forwards
    // from its anchor.
    var _x1, _y1;
    if (_l.kind == LaserKind.Ray) {
        _x1 = _l.x - lengthdir_x(_l.len, _l.dir);
        _y1 = _l.y - lengthdir_y(_l.len, _l.dir);
    } else {
        _x1 = _l.x + lengthdir_x(_l.len, _l.dir);
        _y1 = _l.y + lengthdir_y(_l.len, _l.dir);
    }
    return point_seg_dist(_x, _y, _l.x, _l.y, _x1, _y1);
}

/// @desc Half the width a laser kills at: about a third of its drawn width
///       (the glow either side is harmless).
function laser_hit_half(_l) {
    return _l.wid * 0.34;
}

/// @desc Does this laser touch a circle at (`_x`, `_y`)?
function laser_hits(_l, _x, _y, _rad) {
    if (!laser_is_hot(_l)) return false;
    return laser_spine_dist(_l, _x, _y) < _rad + laser_hit_half(_l);
}

/// @desc Is any laser touching this circle?
function laser_any_hit(_x, _y, _rad) {
    for (var _i = 0; _i < global.laser_n; _i++) {
        if (laser_hits(global.lasers[_i], _x, _y, _rad)) return true;
    }
    return false;
}

/// @desc Pay a graze for every firing laser the player is riding, on a
///       cooldown per laser; returns how many paid. The band is the kill
///       width plus `GRAZE_R`.
function laser_graze(_x, _y, _rad) {
    var _count = 0;
    for (var _i = 0; _i < global.laser_n; _i++) {
        var _l = global.lasers[_i];
        if (!laser_is_hot(_l) || _l.graze_t > 0) continue;
        if (laser_spine_dist(_l, _x, _y) < _rad + laser_hit_half(_l) + GRAZE_R) {
            _l.graze_t = _l.graze_cd;
            _count++;
        }
    }
    return _count;
}

/// @desc Clear every laser. A bomb passes `true` to spare `resist` lasers; a
///       phase change clears everything.
function laser_clear_all(_spare_resist = false) {
    if (!_spare_resist) {
        var _n = global.laser_n;
        global.laser_n = 0;
        return _n;
    }
    var _gone = 0;
    for (var _i = global.laser_n - 1; _i >= 0; _i--) {
        if (global.lasers[_i].resist) continue;
        laser_kill_at(_i);
        _gone++;
    }
    return _gone;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc How wide and how bright a laser is drawn this frame.
function laser_visual(_l) {
    switch (_l.phase) {
        case LaserPhase.Warn:
            // A thin line that brightens in its last stretch, so it is never
            // mistaken for the beam.
            var _p = _l.t / max(1, _l.warn);
            var _imminent = max(0, (_p - 0.82) / 0.18);
            return {
                wid: _l.wid * (0.10 + 0.30 * _imminent),
                alpha: 0.34 + 0.30 * _imminent + 0.10 * dsin(_l.t * 14),
            };

        case LaserPhase.Fire:
            // Reaches full width over three frames.
            var _in = min(1, _l.t / 3);
            return { wid: _l.wid * _in, alpha: 0.95 };

        case LaserPhase.Fade:
            var _f = 1 - _l.t / max(1, _l.fade);
            return { wid: _l.wid * (1 + (1 - _f) * 0.8), alpha: _f * 0.8 };
    }
    return { wid: 0, alpha: 0 };
}

function laser_draw() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.laser_n; _i++) {
        var _l = global.lasers[_i];
        var _v = laser_visual(_l);
        if (_v.alpha <= 0.01) continue;
        var _col = global.bullet_colour[_l.col];

        if (_l.kind == LaserKind.Curve) {
            laser_draw_curve(_l, _v, _col);
        } else {
            var _len = _l.len;
            var _x0 = _l.x;
            var _y0 = _l.y;
            if (_l.kind == LaserKind.Ray) {
                // Drawn from the tail forward, so the sprite's bright end is
                // at the head.
                _x0 = _l.x - lengthdir_x(_len, _l.dir);
                _y0 = _l.y - lengthdir_y(_len, _l.dir);
            }
            laser_draw_bar(_x0, _y0, _l.dir, _len, _v.wid, _col, _v.alpha);

            // A light at a beam's root (rays and curves have a lit head).
            if (_l.kind == LaserKind.Beam) laser_draw_muzzle(_l, _col);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Radius and alpha of the light at a beam's root this frame: it gathers
///       through the warning, flickers while firing and blooms out with the
///       fade. Sizes are multiples of the beam's width.
function laser_muzzle(_l) {
    switch (_l.phase) {
        case LaserPhase.Warn:
            var _p = _l.t / max(1, _l.warn);
            return { r: _l.wid * (0.85 + 1.70 * _p * _p),
                     alpha: 0.28 + 0.46 * _p * _p };

        case LaserPhase.Fire:
            return { r: _l.wid * (2.55 + 0.22 * dsin(_l.t * 23)),
                     alpha: 0.95 };

        case LaserPhase.Fade:
            var _f = 1 - _l.t / max(1, _l.fade);
            return { r: _l.wid * (2.55 + (1 - _f) * 2.0), alpha: _f * 0.7 };
    }
    return { r: 0, alpha: 0 };
}

/// @desc The light at a beam's root: a coloured bloom, a smaller white one
///       inside it, and a four-pointed spark with two points along the beam.
///       Additive.
function laser_draw_muzzle(_l, _col) {
    var _m = laser_muzzle(_l);
    if (_m.alpha <= 0.01 || _m.r <= 0.5) return;

    var _bw = sprite_get_width(spr_fx_bloom);
    var _bh = sprite_get_height(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _l.x, _l.y, _m.r / _bw, _m.r / _bh, 0,
                    _col, _m.alpha * 0.70);
    var _hot = _m.r * 0.40;
    draw_sprite_ext(spr_fx_bloom, 0, _l.x, _l.y, _hot / _bw, _hot / _bh, 0,
                    c_white, _m.alpha * 0.85);

    var _sw = sprite_get_width(spr_fx_spark);
    var _sh = sprite_get_height(spr_fx_spark);
    var _arm = _m.r * 1.35;
    var _thk = max(1, _m.r * 0.11);
    for (var _k = 0; _k < 4; _k++) {
        draw_sprite_ext(spr_fx_spark, 0, _l.x, _l.y, _arm / _sw, _thk / _sh,
                        _l.dir + _k * 90, _col, _m.alpha * 0.5);
    }
}

/// @desc One straight bar of light from (`_x`, `_y`) along `_dir`: a wide body
///       in the hue with a narrow white core over it.
function laser_draw_bar(_x, _y, _dir, _len, _wid, _col, _alpha) {
    var _sw = sprite_get_width(spr_laser_body);
    var _sh = sprite_get_height(spr_laser_body);
    draw_sprite_ext(spr_laser_body, 0, _x, _y,
                    _len / _sw, _wid / _sh, _dir, _col, _alpha * 0.85);
    draw_sprite_ext(spr_laser_body, 0, _x, _y,
                    _len / _sw, max(1, _wid * 0.34) / _sh, _dir,
                    c_white, _alpha * 0.8);
}

/// @desc A curve, drawn as a bar between each pair of nodes (the same
///       segments collision tests), so it stays continuous at any head speed.
///       The head end is brightest and widest, and gets a cap.
function laser_draw_curve(_l, _v, _col) {
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        var _t = (_l.node_n <= 2) ? 1 : (_i / (_l.node_n - 2));
        var _x0 = _l.nx[_i];
        var _y0 = _l.ny[_i];
        var _len = point_distance(_x0, _y0, _l.nx[_i + 1], _l.ny[_i + 1]);
        if (_len < 0.01) continue;
        var _dir = point_direction(_x0, _y0, _l.nx[_i + 1], _l.ny[_i + 1]);
        // 1.5px of overlap so consecutive bars meet.
        laser_draw_bar(_x0, _y0, _dir, _len + 1.5,
                       _v.wid * (0.45 + 0.55 * _t), _col,
                       _v.alpha * (0.35 + 0.65 * _t));
    }

    if (_l.node_n > 0) {
        var _n = _l.node_n - 1;
        var _cs = _v.wid * 1.15 / sprite_get_width(spr_laser_node);
        draw_sprite_ext(spr_laser_node, 0, _l.nx[_n], _l.ny[_n], _cs, _cs, 0,
                        _col, _v.alpha);
        draw_sprite_ext(spr_laser_node, 0, _l.nx[_n], _l.ny[_n],
                        _cs * 0.5, _cs * 0.5, 0, c_white, _v.alpha);
    }
}
