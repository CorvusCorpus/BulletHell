/// @desc Lasers: the travelling ray, the telegraphed beam, and the curved
///       trail, in one pool.
///
/// A beam always has a warning phase first (its `_warn` is an ordinary
/// argument; never pass 0). A curved laser is the trail of a moving head: the
/// last `CURVE_NODES` positions it occupied, collided against segment by
/// segment. A laser only kills while firing. A beam kills across about a
/// third of its drawn width; a ray or a curve across its white core, and not
/// in its points (`BRAY_HIT`, `BRAY_INSET`).
///
/// Rays and curves are drawn in the same light (`spr_bul_ray`), laid along
/// them as a textured strip, so their points keep their shape at any length
/// and round any bend. Their `wid` is the width of that light's body, edge
/// to edge of the hue; a faint glow reaches a little past it.

/// @desc A beam's warning line and the glow at its root are sized from its
///       `wid` times `LASER_BEAM_FLARE`, so a thin beam's light is thin beside
///       them, but never from more than `LASER_BEAM_FLARE_ADD` px wider than
///       its light (`laser_flare_wid`), so a wide beam's glow doesn't swamp
///       its caster.
#macro LASER_BEAM_FLARE 3.3
#macro LASER_BEAM_FLARE_ADD 30
/// @desc The radius of the orb at a beam's root (`laser_draw_orb`), as a
///       multiple of the beam's width: wider than the beam, so it caps it.
#macro LASER_BEAM_ORB 1.0

function laser_init() {
    global.lasers = [];
    global.laser_n = 0;
    laser_uv_init();
}

/// @desc Where each frame of `spr_bul_ray` sits on its page. The `Default`
///       group crops transparent borders, so a frame's UVs cover only the
///       part kept (see `draw_sprite_poly`); this is that part, in the
///       sprite's own pixels, with the half texel the strip insets its UVs by.
function laser_uv_init() {
    global.laser_uv = [];
    var _w = sprite_get_width(spr_bul_ray);
    var _h = sprite_get_height(spr_bul_ray);
    for (var _f = 0; _f < sprite_get_number(spr_bul_ray); _f++) {
        var _q = sprite_get_uvs(spr_bul_ray, _f);
        var _kw = max(1, _w * _q[6]);
        var _kh = max(1, _h * _q[7]);
        array_push(global.laser_uv, {
            x0: _q[4], x1: _q[4] + _kw, kw: _kw,
            y0: _q[5], y1: _q[5] + _kh,
            hu: 0.5 / _kw, hv: 0.5 / _kh,
        });
    }
}

function laser_blank() {
    return {
        kind: LaserKind.Beam,
        phase: LaserPhase.Warn,
        t: 0,
        x: 0, y: 0, dir: 0,
        len: 100, wid: 20, spd: 0, turn: 0,
        // Frames a curve's head has left to turn before it runs straight, or
        // -1 to turn for as long as it lives.
        turn_for: -1,
        // Frames between a curve's nodes (`laser_step_curve`), and frames
        // since its last.
        node_gap: 1, node_t: 0,
        // A curve easing its speed (`laser_curve_ease`): the speed it eases
        // toward (-1: none), the share of the gap it closes a frame, and its
        // turn per pixel, which keeps its path whatever its speed.
        spd_to: -1, spd_ease: 0, bend: 0,
        col: BCOL_BONE,
        warn: 60, hot: 120, fade: 20,
        src: undefined,          // a struct with x/y the origin follows
        // A world point the beam re-aims at every frame, or `undefined` to
        // keep its heading. With `src` too, the beam's root rides its caster
        // while its line pivots about this point.
        look: undefined,
        nx: [], ny: [], node_n: 0,
        // A ray's distance travelled, and a ray's or a curve's length from
        // point to point this frame (a ray grows out of where it was fired).
        run: 0, span: 0,
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
    _l.turn_for = -1;
    _l.node_gap = 1;
    _l.node_t = 0;
    _l.spd_to = -1;
    _l.spd_ease = 0;
    _l.bend = 0;
    _l.src = undefined;
    _l.look = undefined;
    _l.node_n = 0;
    _l.run = 0;
    _l.span = 0;
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

/// @desc An anchored beam that warns, fires, then fades. It fires in a ray's
///       light, `_wid` wide, full width from its root (under its muzzle) to a
///       point `_len` out (`laser_draw_needle`), opening to that width over
///       its first frames (`laser_open`).
/// @param {real} _warn  frames of warning line. **Never pass 0.**
function laser_beam(_x, _y, _dir, _len, _wid, _col, _warn, _hot, _fade = 18) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Beam;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.len = _len; _l.wid = _wid;
    _l.span = _len;
    _l.col = _col;
    _l.warn = _warn; _l.hot = _hot; _l.fade = _fade;
    // The charge cue sounds with the warning, not the beam.
    sfx(Sfx.LaserCharge);
    return _l;
}

/// @desc A loose laser: a needle of light `_wid` wide and up to `_len` from
///       point to point (`laser_draw_needle`), whose head travels at `_spd`.
///       It grows out of the point it was fired from until it is `_len`
///       long, its tail held there. For `_delay` frames first it is a
///       harmless mark on that point, as a bullet's delay is. `_life` counts
///       from when it fires; then it fades, harmless.
function laser_ray(_x, _y, _dir, _spd, _len, _wid, _col, _life, _delay = 0) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Ray;
    _l.phase = (_delay > 0) ? LaserPhase.Warn : LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.len = _len; _l.wid = _wid;
    _l.col = _col;
    _l.warn = _delay; _l.hot = _life; _l.fade = 14;
    if (_delay <= 0) sfx(Sfx.LaserFire);
    return _l;
}

/// @desc A trail laid down by a head moving at `_spd` and turning `_turn`
///       degrees a frame, drawn in a ray's light (`laser_draw_curve`).
///       `_life` is how long the head lives, from when it fires; the trail
///       then drains away behind it. `_delay` is as `laser_ray`'s. With
///       `_turn_for` (frames), the head stops turning after that long and
///       runs straight. Its trail keeps `CURVE_NODES` nodes, one a frame; a
///       slow curve can keep one every `node_gap` frames instead (set on the
///       laser it returns), so it is as long as a faster one.
function laser_curve(_x, _y, _dir, _spd, _turn, _wid, _col, _life,
                     _delay = 0, _turn_for = -1) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Curve;
    _l.phase = (_delay > 0) ? LaserPhase.Warn : LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.turn = _turn; _l.wid = _wid;
    _l.turn_for = _turn_for;
    _l.col = _col;
    _l.warn = _delay; _l.hot = _life; _l.fade = CURVE_NODES;
    _l.node_n = 0;
    if (_delay <= 0) sfx(Sfx.LaserFire);
    return _l;
}

/// @desc Have curve `_l` ease its speed toward `_to`, closing `_share` of the
///       gap every frame, and turn in step with its speed so it keeps the
///       path it was fired on. Passes `undefined` through.
function laser_curve_ease(_l, _to, _share) {
    if (_l == undefined) return undefined;
    _l.spd_to = _to;
    _l.spd_ease = _share;
    _l.bend = (_l.spd != 0) ? _l.turn / _l.spd : 0;
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
    _l.span = _l.len;
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

/// @desc A ray or curve's delay: it waits where it was fired, then fires.
///       Returns whether it is still waiting.
function laser_step_delay(_l) {
    if (_l.phase != LaserPhase.Warn) return false;
    if (_l.t < _l.warn) return true;
    _l.phase = LaserPhase.Fire;
    _l.t = 0;
    sfx(Sfx.LaserFire);
    return false;
}

function laser_step_ray(_l) {
    if (laser_step_delay(_l)) return;
    _l.dir += _l.turn;
    _l.x += lengthdir_x(_l.spd, _l.dir);
    _l.y += lengthdir_y(_l.spd, _l.dir);
    _l.run += abs(_l.spd);
    _l.span = min(_l.len, _l.run);

    if (_l.phase == LaserPhase.Fire && _l.t >= _l.hot) {
        _l.phase = LaserPhase.Fade;
        _l.t = 0;
    } else if (_l.phase == LaserPhase.Fade && _l.t >= _l.fade) {
        _l.phase = LaserPhase.Done;
    }

    // Culled when the whole ray, tail included, has left the field.
    var _tx = _l.x - lengthdir_x(_l.span, _l.dir);
    var _ty = _l.y - lengthdir_y(_l.span, _l.dir);
    if (min(_l.x, _tx) > FIELD_X1 + CULL_MARGIN
        || max(_l.x, _tx) < FIELD_X0 - CULL_MARGIN
        || min(_l.y, _ty) > FIELD_Y1 + CULL_MARGIN
        || max(_l.y, _ty) < FIELD_Y0 - CULL_MARGIN) {
        _l.phase = LaserPhase.Done;
    }
}

function laser_step_curve(_l) {
    if (laser_step_delay(_l)) return;
    if (_l.phase == LaserPhase.Fire) {
        if (_l.spd_to >= 0) {
            // Turned by the mean of the last step's speed and this one's, so
            // the steps stay chords of one circle as the speed changes.
            var _was = _l.spd;
            _l.spd += (_l.spd_to - _l.spd) * _l.spd_ease;
            _l.turn = _l.bend * (_was + _l.spd) * 0.5;
        }
        if (_l.turn_for != 0) {
            _l.dir += _l.turn;
            if (_l.turn_for > 0) _l.turn_for--;
        }
        _l.x += lengthdir_x(_l.spd, _l.dir);
        _l.y += lengthdir_y(_l.spd, _l.dir);
        // A node every `node_gap` frames; between them the newest follows
        // the head.
        _l.node_t++;
        if (_l.node_n < 2 || _l.node_t >= _l.node_gap) {
            _l.node_t = 0;
            curve_push(_l, _l.x, _l.y);
        } else {
            _l.nx[_l.node_n - 1] = _l.x;
            _l.ny[_l.node_n - 1] = _l.y;
        }
        if (_l.t >= _l.hot) {
            _l.phase = LaserPhase.Fade;
            _l.t = 0;
        }
    } else {
        // The head stops and the tail drains a node every `node_gap` frames;
        // collision reads the same nodes, so the drained part is no longer
        // dangerous.
        _l.node_t++;
        if (_l.node_t >= _l.node_gap) {
            _l.node_t = 0;
            curve_drop_oldest(_l);
        }
        if (_l.node_n <= 1) {
            _l.phase = LaserPhase.Done;
        }
    }
    _l.span = curve_span(_l);
}

/// @desc A curve's length along its trail, tail to head.
function curve_span(_l) {
    var _s = 0;
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        _s += point_distance(_l.nx[_i], _l.ny[_i], _l.nx[_i + 1], _l.ny[_i + 1]);
    }
    return _s;
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

/// @desc The share of its width a laser is drawn and collided at while it
///       fires: a beam opens to full width over its first three frames of
///       fire; a ray or a curve fires at full width.
function laser_open(_l) {
    if (_l.kind != LaserKind.Beam || _l.phase != LaserPhase.Fire) return 1;
    return min(1, (_l.t + 1) / 3);
}

/// @desc The scale a needle `_wid` wide and `_span` long is drawn and
///       collided at: 1, or less while it is shorter than its points (`_ends`
///       of them: two on a ray or a curve, one on a beam) together, when the
///       whole needle is smaller so its points keep their shape. That is a
///       ray just fired, or a curve's first and last moments.
function laser_grow_at(_wid, _span, _ends) {
    var _tip = BRAY_TIP * _wid / (2 * BRAY_BODY);
    if (_tip <= 0) return 1;
    return min(1, _span / (_ends * _tip));
}

/// @desc `laser_grow_at` for a laser this frame.
function laser_grow(_l) {
    return laser_grow_at(_l.wid * laser_open(_l), _l.span,
                         (_l.kind == LaserKind.Beam) ? 1 : 2);
}

/// @desc How far a point is from a laser's spine. Hits and grazes use this
///       same measurement at different widths.
function laser_spine_dist(_l, _x, _y) {
    // It stops short of each point by `BRAY_INSET`, so a point never kills
    // where its light is narrower than the kill width.
    var _span = _l.span;
    if (_span <= 0) return 99999;
    var _in = BRAY_INSET * _l.wid * laser_open(_l) / (2 * BRAY_BODY)
              * laser_grow(_l);

    // A beam's runs forwards from its anchor, where it is full width.
    if (_l.kind == LaserKind.Beam) {
        return point_seg_dist(_x, _y, _l.x, _l.y,
                              _l.x + lengthdir_x(_span - _in, _l.dir),
                              _l.y + lengthdir_y(_span - _in, _l.dir));
    }

    // A ray's runs backwards from its head.
    if (_l.kind == LaserKind.Ray) {
        return point_seg_dist(_x, _y,
                              _l.x - lengthdir_x(_in, _l.dir),
                              _l.y - lengthdir_y(_in, _l.dir),
                              _l.x - lengthdir_x(_span - _in, _l.dir),
                              _l.y - lengthdir_y(_span - _in, _l.dir));
    }

    // A curve's is its trail from `_in` past the tail to `_in` short of the
    // head.
    var _a = _in;
    var _b = _span - _in;
    var _best = 99999;
    var _s = 0;
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        var _x0 = _l.nx[_i];
        var _y0 = _l.ny[_i];
        var _x1 = _l.nx[_i + 1];
        var _y1 = _l.ny[_i + 1];
        var _len = point_distance(_x0, _y0, _x1, _y1);
        if (_len > 0 && _s + _len > _a) {
            var _f0 = max(0, (_a - _s) / _len);
            var _f1 = min(1, (_b - _s) / _len);
            _best = min(_best, point_seg_dist(_x, _y,
                lerp(_x0, _x1, _f0), lerp(_y0, _y1, _f0),
                lerp(_x0, _x1, _f1), lerp(_y0, _y1, _f1)));
        }
        _s += _len;
        if (_s >= _b) break;
    }
    return _best;
}

/// @desc Half the width a laser kills at: its white core (`BRAY_HIT` of its
///       half width as drawn this frame), not the band of hue round it.
function laser_hit_half(_l) {
    return BRAY_HIT * _l.wid * laser_open(_l) * 0.5 * laser_grow(_l);
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

/// @desc How wide and how bright a laser is drawn this frame. A beam's
///       warning is a thin line that brightens in its last stretch, so it is
///       never mistaken for the beam. A ray's or a curve's delay mark is its
///       needle (`laser_draw_mark`), faint and oversized, shrinking and
///       brightening onto where it will be fired from, as a bullet's mark
///       does. Every kind fires at full strength (a beam opening,
///       `laser_open`) and fades out narrowing.
function laser_visual(_l) {
    switch (_l.phase) {
        case LaserPhase.Warn:
            if (_l.kind == LaserKind.Beam) {
                var _p = _l.t / max(1, _l.warn);
                var _imminent = max(0, (_p - 0.82) / 0.18);
                return {
                    wid: laser_flare_wid(_l) * (0.10 + 0.30 * _imminent),
                    alpha: 0.34 + 0.30 * _imminent + 0.10 * dsin(_l.t * 14),
                };
            }
            var _t = 1 - _l.t / max(1, _l.warn);     // 1 at birth, 0 at fire
            return { wid: _l.wid * (0.6 + 0.9 * _t),
                     alpha: 0.16 + 0.34 * (1 - _t) };

        case LaserPhase.Fire:
            return { wid: _l.wid * laser_open(_l), alpha: 1 };

        case LaserPhase.Fade:
            var _f = 1 - _l.t / max(1, _l.fade);
            return { wid: _l.wid * (0.35 + 0.65 * _f), alpha: _f };
    }
    return { wid: 0, alpha: 0 };
}

function laser_draw() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.laser_n; _i++) {
        var _l = global.lasers[_i];
        var _v = laser_visual(_l);
        if (_v.alpha <= 0.01) continue;

        if (_l.kind == LaserKind.Beam) {
            var _col = global.bullet_colour[_l.col];
            if (_l.phase == LaserPhase.Warn) {
                laser_draw_bar(_l.x, _l.y, _l.dir, _l.len, _v.wid, _col,
                               _v.alpha);
            } else {
                laser_draw_needle(_l.x + lengthdir_x(_l.len, _l.dir),
                                  _l.y + lengthdir_y(_l.len, _l.dir),
                                  _l.dir, _l.len, _v.wid, _l.col, _v.alpha,
                                  true);
            }
            // A light at a beam's root.
            laser_draw_muzzle(_l, _col);
        } else if (_l.phase == LaserPhase.Warn) {
            laser_draw_mark(_l, _v.wid, _v.alpha);
        } else if (_l.kind == LaserKind.Ray) {
            laser_draw_needle(_l.x, _l.y, _l.dir, _l.span, _v.wid, _l.col,
                              _v.alpha);
        } else {
            laser_draw_curve(_l, _v.wid, _v.alpha);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The width a beam's warning line and root glow are sized from.
function laser_flare_wid(_l) {
    return min(_l.wid * LASER_BEAM_FLARE, _l.wid + LASER_BEAM_FLARE_ADD);
}

/// @desc The light at a beam's root this frame: the glow's size (`r`) and
///       alpha, and the orb's radius (`orb`) and alpha (`orb_a`). The glow
///       gathers through the warning, flickers while firing and blooms out
///       with the fade; the orb grows through the warning to its full size
///       as the beam fires and shrinks away with the fade.
function laser_muzzle(_l) {
    var _w = laser_flare_wid(_l);
    var _o = _l.wid * LASER_BEAM_ORB;
    switch (_l.phase) {
        case LaserPhase.Warn:
            var _p = _l.t / max(1, _l.warn);
            return { r: _w * (0.85 + 1.70 * _p * _p),
                     alpha: 0.28 + 0.46 * _p * _p,
                     orb: _o * (0.30 + 0.70 * _p * _p),
                     orb_a: 0.45 + 0.55 * _p };

        case LaserPhase.Fire:
            return { r: _w * (2.55 + 0.22 * dsin(_l.t * 23)),
                     alpha: 0.95,
                     orb: _o * (1 + 0.05 * dsin(_l.t * 23)), orb_a: 1 };

        case LaserPhase.Fade:
            var _f = 1 - _l.t / max(1, _l.fade);
            return { r: _w * (2.55 + (1 - _f) * 2.0), alpha: _f * 0.7,
                     orb: _o * _f, orb_a: _f };
    }
    return { r: 0, alpha: 0, orb: 0, orb_a: 0 };
}

/// @desc The light at a beam's root: a coloured bloom, a smaller white one
///       inside it, a four-pointed spark with two points along the beam, and
///       over them the orb, in the beam's own light. Additive.
function laser_draw_muzzle(_l, _col) {
    var _m = laser_muzzle(_l);
    laser_draw_orb(_l.x, _l.y, _m.orb, _l.col, _m.orb_a);
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

// ---------------------------------------------------------------------------
// The light of rays and curves
//
// `spr_bul_ray` laid along the laser as one textured triangle strip, a column
// of two vertices at a time across it. The sprite is [glow | point | body |
// point | glow] end to end and its body is the same in every column, so the
// points are mapped at their own shape and only the body is stretched. Its
// size scales with `wid` (`BRAY_BODY` is half the body's width in sprite
// pixels), and while the laser is shorter than its two points together the
// whole needle is drawn smaller (`laser_grow`).
// ---------------------------------------------------------------------------

/// @desc One column of the strip: the two vertices across the spine point
///       (`_x`, `_y`), at `_a` and `_b` along the unit normal (`_nx`, `_ny`),
///       showing the sprite's column `_sx` (its own pixels). `_m` is the
///       frame's entry in `global.laser_uv`.
function laser_strip_pair(_x, _y, _nx, _ny, _a, _b, _sx, _m, _alpha) {
    var _u = lerp(_m.hu, 1 - _m.hu, (_sx - _m.x0) / _m.kw);
    draw_vertex_texture_colour(_x + _nx * _a, _y + _ny * _a, _u, _m.hv,
                               c_white, _alpha);
    draw_vertex_texture_colour(_x + _nx * _b, _y + _ny * _b, _u, 1 - _m.hv,
                               c_white, _alpha);
}

/// @desc The sprite column shown `_s` along a laser `_span` long from its
///       tail's point, for a needle drawn at `_k` screen pixels to a sprite
///       pixel: measured from the tail's point on the tail's half, from the
///       head's on the head's (`_head`). Past a point's length it is in the
///       body, which is the same everywhere, so it stops at the middle.
function laser_strip_sx(_s, _span, _k, _head) {
    if (_head) {
        return max(BRAY_W - BRAY_GLOW - (_span - _s) / _k, BRAY_W * 0.5);
    }
    return min(BRAY_GLOW + _s / _k, BRAY_W * 0.5);
}

/// @desc A straight needle of light, `_span` from its tail's point to its
///       head's at (`_hx`, `_hy`), heading `_dir`, `_wid` wide, in frame
///       `_fr` (its colour). A ray is one; so is a delay mark. With `_flat`
///       its tail is cut square at full width instead (a beam's root, under
///       its muzzle).
function laser_draw_needle(_hx, _hy, _dir, _span, _wid, _fr, _alpha,
                           _flat = false) {
    if (_span <= 0.5 || _wid <= 0.5 || _alpha <= 0.004) return;
    var _k = _wid / (2 * BRAY_BODY);
    _k *= laser_grow_at(_wid, _span, _flat ? 1 : 2);
    var _m = global.laser_uv[_fr];
    var _a = (_m.y0 - BRAY_THICK * 0.5) * _k;
    var _b = (_m.y1 - BRAY_THICK * 0.5) * _k;
    var _tip = BRAY_TIP * _k;
    var _dx = lengthdir_x(1, _dir);
    var _dy = lengthdir_y(1, _dir);
    var _tx = _hx - _dx * _span;
    var _ty = _hy - _dy * _span;

    // The glow past the tail's point, the ends of both points, and the glow
    // past the head's.
    var _s0 = (_m.x0 - BRAY_GLOW) * _k;
    var _s3 = _span + (_m.x1 - (BRAY_W - BRAY_GLOW)) * _k;
    draw_primitive_begin_texture(pr_trianglestrip,
                                 sprite_get_texture(spr_bul_ray, _fr));
    if (_flat) {
        laser_strip_pair(_tx, _ty, -_dy, _dx, _a, _b, BRAY_W * 0.5, _m,
                         _alpha);
    } else {
        laser_strip_pair(_tx + _dx * _s0, _ty + _dy * _s0, -_dy, _dx, _a, _b,
                         _m.x0, _m, _alpha);
        laser_strip_pair(_tx + _dx * _tip, _ty + _dy * _tip, -_dy, _dx, _a,
                         _b, BRAY_GLOW + BRAY_TIP, _m, _alpha);
    }
    laser_strip_pair(_hx - _dx * _tip, _hy - _dy * _tip, -_dy, _dx, _a, _b,
                     BRAY_W - BRAY_GLOW - BRAY_TIP, _m, _alpha);
    laser_strip_pair(_tx + _dx * _s3, _ty + _dy * _s3, -_dy, _dx, _a, _b,
                     _m.x1, _m, _alpha);
    draw_primitive_end();
}

/// @desc A ray's or a curve's delay mark: its needle at its shortest (the two
///       points together), centred where it will be fired from and pointing
///       the way it will go.
function laser_draw_mark(_l, _wid, _alpha) {
    var _span = 2 * BRAY_TIP * _wid / (2 * BRAY_BODY);
    laser_draw_needle(_l.x + lengthdir_x(_span * 0.5, _l.dir),
                      _l.y + lengthdir_y(_span * 0.5, _l.dir),
                      _l.dir, _span, _wid, _l.col, _alpha);
}

/// @desc A curve: the needle laid along its trail, a column at every node
///       (turned to the trail through its neighbours) and more where the
///       mapping bends: the end of each point, and the middle, where the
///       tail's half and the head's half meet. Between columns the mapping is
///       then straight, so the points keep their shape at any head speed.
function laser_draw_curve(_l, _wid, _alpha) {
    var _n = _l.node_n;
    var _span = _l.span;
    if (_n < 2 || _span <= 0.5 || _wid <= 0.5 || _alpha <= 0.004) return;
    var _k = _wid / (2 * BRAY_BODY) * laser_grow_at(_wid, _span, 2);
    var _fr = _l.col;
    var _m = global.laser_uv[_fr];
    var _a = (_m.y0 - BRAY_THICK * 0.5) * _k;
    var _b = (_m.y1 - BRAY_THICK * 0.5) * _k;
    var _tip = BRAY_TIP * _k;
    var _mid = _span * 0.5;
    // Whether the points end before the middle (not while the needle is
    // drawn smaller, when they meet there).
    var _ends = (_tip < _mid - 0.01);
    var _px = _l.nx;
    var _py = _l.ny;

    draw_primitive_begin_texture(pr_trianglestrip,
                                 sprite_get_texture(spr_bul_ray, _fr));

    // The glow past the tail's point, along the first segment.
    var _dx = _px[1] - _px[0];
    var _dy = _py[1] - _py[0];
    var _d = sqrt(_dx * _dx + _dy * _dy);
    if (_d > 0.0001) {
        _dx /= _d;
        _dy /= _d;
    } else {
        _dx = lengthdir_x(1, _l.dir);
        _dy = lengthdir_y(1, _l.dir);
    }
    var _nx = -_dy;
    var _ny = _dx;
    var _e = (_m.x0 - BRAY_GLOW) * _k;
    laser_strip_pair(_px[0] + _dx * _e, _py[0] + _dy * _e, _nx, _ny, _a, _b,
                     _m.x0, _m, _alpha);

    var _s = 0;
    for (var _i = 0; _i < _n; _i++) {
        var _i0 = max(0, _i - 1);
        var _i1 = min(_n - 1, _i + 1);
        var _ex = _px[_i1] - _px[_i0];
        var _ey = _py[_i1] - _py[_i0];
        var _el = sqrt(_ex * _ex + _ey * _ey);
        if (_el > 0.0001) {
            _nx = -_ey / _el;
            _ny = _ex / _el;
        }
        var _x0 = _px[_i];
        var _y0 = _py[_i];
        if (_s <= _mid) {
            laser_strip_pair(_x0, _y0, _nx, _ny, _a, _b,
                             laser_strip_sx(_s, _span, _k, false), _m, _alpha);
        }
        if (_s >= _mid) {
            laser_strip_pair(_x0, _y0, _nx, _ny, _a, _b,
                             laser_strip_sx(_s, _span, _k, true), _m, _alpha);
        }
        if (_i == _n - 1) break;

        var _x1 = _px[_i + 1];
        var _y1 = _py[_i + 1];
        var _len = point_distance(_x0, _y0, _x1, _y1);
        if (_len > 0.0001) {
            var _snx = -(_y1 - _y0) / _len;
            var _sny = (_x1 - _x0) / _len;
            var _f;
            if (_ends && _tip > _s && _tip < _s + _len) {
                _f = (_tip - _s) / _len;
                laser_strip_pair(lerp(_x0, _x1, _f), lerp(_y0, _y1, _f),
                                 _snx, _sny, _a, _b, BRAY_GLOW + BRAY_TIP,
                                 _m, _alpha);
            }
            if (_mid > _s && _mid < _s + _len) {
                _f = (_mid - _s) / _len;
                var _mx = lerp(_x0, _x1, _f);
                var _my = lerp(_y0, _y1, _f);
                laser_strip_pair(_mx, _my, _snx, _sny, _a, _b,
                                 laser_strip_sx(_mid, _span, _k, false),
                                 _m, _alpha);
                laser_strip_pair(_mx, _my, _snx, _sny, _a, _b,
                                 laser_strip_sx(_mid, _span, _k, true),
                                 _m, _alpha);
            }
            if (_ends && _span - _tip > _s && _span - _tip < _s + _len) {
                _f = (_span - _tip - _s) / _len;
                laser_strip_pair(lerp(_x0, _x1, _f), lerp(_y0, _y1, _f),
                                 _snx, _sny, _a, _b,
                                 BRAY_W - BRAY_GLOW - BRAY_TIP, _m, _alpha);
            }
        }
        _s += _len;
    }

    // The glow past the head's point, along the last segment.
    var _h = _n - 1;
    _dx = _px[_h] - _px[_h - 1];
    _dy = _py[_h] - _py[_h - 1];
    _d = sqrt(_dx * _dx + _dy * _dy);
    if (_d > 0.0001) {
        _dx /= _d;
        _dy /= _d;
    } else {
        _dx = lengthdir_x(1, _l.dir);
        _dy = lengthdir_y(1, _l.dir);
    }
    _e = (_m.x1 - (BRAY_W - BRAY_GLOW)) * _k;
    laser_strip_pair(_px[_h] + _dx * _e, _py[_h] + _dy * _e, -_dy, _dx, _a, _b,
                     _m.x1, _m, _alpha);
    draw_primitive_end();
}

/// @desc A round body of a ray's light at (`_x`, `_y`), `_rb` in radius to the
///       edge of its hue, in frame `_fr` (its colour): the sprite's
///       cross-section turned round its middle, as a fan of triangles from
///       the centre row out to the edge row, so it has the same core, band,
///       edge and glow as the lasers.
function laser_draw_orb(_x, _y, _rb, _fr, _alpha) {
    if (_rb <= 0.5 || _alpha <= 0.004) return;
    var _m = global.laser_uv[_fr];
    var _k = _rb / BRAY_BODY;
    var _u = lerp(_m.hu, 1 - _m.hu, (BRAY_W * 0.5 - _m.x0) / _m.kw);
    var _vc = lerp(_m.hv, 1 - _m.hv,
                   (BRAY_THICK * 0.5 - _m.y0) / (_m.y1 - _m.y0));
    var _r = (BRAY_THICK * 0.5 - _m.y0) * _k;
    var _n = 32;
    draw_primitive_begin_texture(pr_trianglelist,
                                 sprite_get_texture(spr_bul_ray, _fr));
    for (var _i = 0; _i < _n; _i++) {
        var _a0 = _i * (360 / _n);
        var _a1 = _a0 + 360 / _n;
        draw_vertex_texture_colour(_x, _y, _u, _vc, c_white, _alpha);
        draw_vertex_texture_colour(_x + lengthdir_x(_r, _a0),
                                   _y + lengthdir_y(_r, _a0), _u, _m.hv,
                                   c_white, _alpha);
        draw_vertex_texture_colour(_x + lengthdir_x(_r, _a1),
                                   _y + lengthdir_y(_r, _a1), _u, _m.hv,
                                   c_white, _alpha);
    }
    draw_primitive_end();
}
