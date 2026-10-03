/// @desc Szuix's cut-in as he spends a sigil (`player_bomb`): a spell's
///       declaration (`spell_cutin`) turned round, as though he were
///       declaring a spell of his own back at the boss.
///
/// It does what a boss's cut-in does, mirrored and quicker, since he casts it
/// in the middle of a fight. A cut splits out both ways along the band's line
/// from above where he cast, and opens into a band tilted the other way from
/// a spell's. His portrait slides in from the left with its eyes shut, over
/// his sigil turning behind him, while the band's layers slide in round it.
/// Then the eyes snap open (as `cue_bomb`'s rise peaks): the band flashes and
/// jolts, the face punches in, light streaks from the eyes, the sigil flares,
/// and two marks slam in beside him. The band closes to a line, well before
/// his grace runs out. Unlike a spell's, it has no name plate.
///
/// He is drawn again in front of it all, with his hitbox while he is
/// focused, so the band never hides him.
///
/// Everything is a function of the player's `cutin_t` (frames since the
/// cast, -1 when idle). The portrait (`spr_cutin_szuix`, from
/// `make_portraits.py`) keeps the spell cut-in's contract: eyes shut, then
/// open, its origin midway between the eyes, which `talk_art` gives.

// Frames, from the cast.
#macro SIGIL_CUTIN_OPEN_AT 20      // the eyes open
#macro SIGIL_CUTIN_CLOSE_AT 64     // the band starts to close
#macro SIGIL_CUTIN_TIME 80         // all of it: the band is gone

// The band: its centre line crosses the field's middle column
// `SIGIL_CUTIN_Y` down, turned `SIGIL_CUTIN_TILT` degrees (a spell's is
// turned the other way). His eyes sit `SIGIL_CUTIN_FACE_V` below the line.
#macro SIGIL_CUTIN_Y (FIELD_Y0 + FIELD_H * 0.5)
#macro SIGIL_CUTIN_TILT 7
#macro SIGIL_CUTIN_H 340
#macro SIGIL_CUTIN_FACE_V -14

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// @desc The band this frame (as `cutin_geom` has it), and `x0`, where its
///       cut starts: above where he cast.
function sigil_cutin_geom(_p) {
    var _t = _p.cutin_t;
    var _open = cutin_back(_t, 3, 11)
              * (1 - cutin_in(_t, SIGIL_CUTIN_CLOSE_AT, 12));
    var _jx = 0;
    var _jy = 0;
    var _u = _t - SIGIL_CUTIN_OPEN_AT;
    if (_u >= 0 && _u < 9) {
        var _k = 1 - _u / 9;
        _jx = dsin(_u * 131) * 9 * _k;
        _jy = dcos(_u * 97) * 6 * _k;
    }
    return {
        t: _t,
        h: SIGIL_CUTIN_H * _open,
        open: clamp(_open, 0, 1),
        cx: FIELD_CX + _jx,
        cy: SIGIL_CUTIN_Y + _jy,
        k: -dtan(SIGIL_CUTIN_TILT),
        x0: clamp(_p.bomb_x, FIELD_X0 + 40, FIELD_X1 - 40),
    };
}

/// @desc The face this frame (as `cutin_face` has it). It slides in from the
///       left as it pushes in, drifts right, punches in as the eyes open,
///       and slides away right as the band closes.
function sigil_cutin_face(_g) {
    var _t = _g.t;
    var _in = card_ramp(_t, 2, 16);
    var _out = cutin_in(_t, SIGIL_CUTIN_CLOSE_AT, 16);
    var _x = _g.cx - 40 - 140 * (1 - _in) + 0.5 * _t + 200 * _out;
    var _s = 1 + 0.16 * (1 - _in) + 0.0008 * _t + 0.05 * _out;
    var _u = _t - SIGIL_CUTIN_OPEN_AT;
    if (_u >= 0) _s += 0.07 * exp(-_u / 6) * cos(_u * 0.55);
    var _y = cutin_y(_g, _x) + SIGIL_CUTIN_FACE_V;

    var _art = talk_art(spr_cutin_szuix);
    var _ex = _x;
    var _ey = _y;
    var _n = array_length(_art.eyes);
    if (_n > 0) {
        _ex = 0;
        _ey = 0;
        for (var _i = 0; _i < _n; _i++) {
            _ex += _x + _art.eyes[_i][0] * _s;
            _ey += _y + _art.eyes[_i][1] * _s;
        }
        _ex /= _n;
        _ey /= _n;
    }
    return { x: _x, y: _y, s: _s, fr: (_t >= SIGIL_CUTIN_OPEN_AT) ? 1 : 0,
             art: _art, ex: _ex, ey: _ey };
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw it (GUI layer, after the boss's cut-in, so it is on top).
function sigil_cutin_draw(_p) {
    var _t = _p.cutin_t;
    if (_t < 0) return;
    var _spr = spr_cutin_szuix;
    var _g = sigil_cutin_geom(_p);
    var _f = sigil_cutin_face(_g);

    sigil_cutin_draw_veil(_g);
    sigil_cutin_draw_strips(_g, COL_SIGIL);
    if (_g.h > 1) {
        var _band = cutin_strip(_g, -_g.h * 0.5, _g.h * 0.5);
        cutin_draw_reflection(_g, _f, _spr);
        cutin_draw_ground(_g, _f, _band, COL_SIGIL, SIGIL_CUTIN_OPEN_AT);
        sigil_cutin_draw_sigil(_g, _f, _band);
        cutin_draw_face(_g, _f, _band, _spr, COL_RUNE, SIGIL_CUTIN_OPEN_AT,
                        SIGIL_CUTIN_TILT);
        sigil_cutin_draw_flare(_g, _f, _band);
        sigil_cutin_draw_streaks(_g, _band);
        cutin_draw_motes(_g, COL_RUNE, SIGIL_CUTIN_CLOSE_AT);
        cutin_draw_edges(_g, SIGIL_CUTIN_TILT);
    }
    sigil_cutin_draw_cut(_g, COL_SIGIL);
    sigil_cutin_draw_marks(_g);
    sigil_cutin_draw_caster(_g, _p);

    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc How far the veil is down (0 to 1).
function sigil_cutin_veil(_t) {
    return card_ramp(_t, 0, 6)
         * (1 - cutin_smooth(_t, SIGIL_CUTIN_CLOSE_AT + 2, 14));
}

/// @desc The field darkened under the band, more at its top and bottom than
///       through the middle, and lighter than a spell's veil.
function sigil_cutin_draw_veil(_g) {
    var _a = sigil_cutin_veil(_g.t) * 0.5;
    if (_a <= 0.004) return;
    var _c = merge_colour(COL_VOID, COL_ARCANE, 0.25);
    var _ys = [FIELD_Y0, SIGIL_CUTIN_Y - SIGIL_CUTIN_H * 0.6,
               SIGIL_CUTIN_Y + SIGIL_CUTIN_H * 0.6, FIELD_Y1];
    var _as = [1.25, 0.85, 0.85, 1.3];
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i < 4; _i++) {
        var _aa = min(1, _a * _as[_i]);
        draw_vertex_colour(FIELD_X0, _ys[_i], _c, _aa);
        draw_vertex_colour(FIELD_X1, _ys[_i], _c, _aa);
    }
    draw_primitive_end();
}

/// @desc The layers round the band, as a spell's but from the other sides: a
///       broad, steeper band of his colour behind it sliding in from the
///       right, a bar of it above the band from the left, and a gilt bar
///       under its right end. They slide back out as the band closes.
function sigil_cutin_draw_strips(_g, _col) {
    var _t = _g.t;
    var _hh = _g.h * 0.5;
    var _field = cutin_field_poly();
    var _gone = cutin_in(_t, SIGIL_CUTIN_CLOSE_AT - 2, 12);

    var _sl = FIELD_W * (1 - cutin_quint(_t, 1, 14)) + FIELD_W * _gone;
    var _ghost = cutin_quad(_g.cx + _sl, _g.cy, _g.k - 0.075,
                            FIELD_X0 + _sl, FIELD_X1 + _sl,
                            -_hh * 1.35, _hh * 1.35);
    draw_poly(poly_clip(_ghost, _field), _col, 0.11 * _g.open);

    var _sa = FIELD_W * (1 - cutin_quint(_t, 3, 12)) + FIELD_W * _gone;
    draw_poly(poly_clip(cutin_strip(_g, -_hh - 30, -_hh - 14,
                                    FIELD_X0 - _sa,
                                    FIELD_X1 - FIELD_W * 0.36 - _sa), _field),
              _col, 0.85);
    draw_poly(poly_clip(cutin_strip(_g, -_hh - 41, -_hh - 38,
                                    FIELD_X0 - _sa * 1.2,
                                    FIELD_X1 - FIELD_W * 0.56 - _sa * 1.2),
                        _field),
              COL_GILT_LIT, 0.6);

    var _sb = FIELD_W * (1 - cutin_quint(_t, 5, 12)) + FIELD_W * _gone;
    draw_poly(poly_clip(cutin_strip(_g, _hh + 12, _hh + 19,
                                    FIELD_X1 - FIELD_W * 0.42 + _sb,
                                    FIELD_X1 + _sb), _field),
              COL_GILT_LIT, 0.75);
}

/// @desc His sigil (`spr_fx_sigil`, the bomb's own circle) behind him, cut to
///       the band: it grows in spinning, settles to a slow turn, and flares
///       and kicks round as the eyes open.
function sigil_cutin_draw_sigil(_g, _f, _band) {
    var _t = _g.t;
    var _u = _t - SIGIL_CUTIN_OPEN_AT;
    var _kick = (_u >= 0) ? exp(-_u / 8) : 0;
    var _grow = cutin_back(_t, 0, 16);
    // The sprite's outer ring sits 494 of its 512 half-pixels out.
    var _sc = 430 / 494 * (sprite_get_width(spr_fx_sigil) / 1024.0)
            * (0.55 + 0.45 * _grow) * (1 + 0.06 * _kick);
    var _spin = _t * 0.5 + 70 * (1 - card_ramp(_t, 0, 22))
              + 24 * ((_u >= 0) ? 1 - exp(-_u / 6) : 0);
    var _a = _g.open * (0.55 + 0.45 * _kick);
    var _x = _f.ex;
    var _y = _f.ey + 30;
    gpu_set_blendmode(bm_add);
    draw_sprite_poly(spr_fx_sigil, 0, _x, _y, _sc, _sc, _band, COL_SIGIL,
                     0.8 * _a, undefined, _spin);
    draw_sprite_poly(spr_fx_sigil, 1, _x, _y, _sc, _sc, _band, COL_RUNE,
                     0.65 * _a, undefined, -_spin * 1.6);
    draw_sprite_poly(spr_fx_sigil, 2, _x, _y, _sc * 0.9, _sc * 0.9, _band,
                     merge_colour(COL_SIGIL, c_white, 0.4), 0.5 * _a,
                     undefined, _spin * 0.4);
    gpu_set_blendmode(bm_normal);
}

/// @desc As the eyes open, the sigil thrown forward over him: its rings and
///       script, cut to the band, swelling out and fading.
function sigil_cutin_draw_flare(_g, _f, _band) {
    var _u = _g.t - SIGIL_CUTIN_OPEN_AT;
    if (_u < 0 || _u >= 24) return;
    var _k = 1 - _u / 24;
    var _sc = 430 / 494 * (sprite_get_width(spr_fx_sigil) / 1024.0)
            * (1 + 0.5 * (1 - _k * _k));
    var _x = _f.ex;
    var _y = _f.ey + 30;
    gpu_set_blendmode(bm_add);
    draw_sprite_poly(spr_fx_sigil, 0, _x, _y, _sc, _sc, _band,
                     merge_colour(COL_SIGIL, c_white, 0.3), 0.7 * _k * _k,
                     undefined, _g.t * 0.5);
    draw_sprite_poly(spr_fx_sigil, 1, _x, _y, _sc * 0.92, _sc * 0.92, _band,
                     COL_RUNE, 0.5 * _k * _k, undefined, -_g.t * 0.8);
    gpu_set_blendmode(bm_normal);
}

/// @desc Speed lines along the band, rushing right as the face slides in and
///       out, faint while it holds.
function sigil_cutin_draw_streaks(_g, _band) {
    var _t = _g.t;
    var _a = 0.04 + 0.4 * (1 - card_ramp(_t, 2, 16))
             + 0.35 * cutin_in(_t, SIGIL_CUTIN_CLOSE_AT - 4, 12);
    var _len0 = sqrt(1 + _g.k * _g.k);
    var _dx = 1 / _len0;
    var _dy = _g.k / _len0;
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 18; _i++) {
        var _v = (frac(_i * 0.7548) * 2 - 1) * 0.46 * _g.h;
        var _len = 160 + 380 * frac(_i * 0.5698);
        var _span = FIELD_W + _len + 200;
        var _run = _t * (38 + 30 * frac(_i * 0.339)) + frac(_i * 0.1234) * _span;
        // The head, leading to the right; the tail fades behind it.
        var _x = FIELD_X0 - 100 + (_run mod _span);
        var _y = cutin_y(_g, _x) + _v;
        var _w = 1.5 + 2.5 * frac(_i * 0.83);
        var _seg = [_x, _y - _w, _x - _len * _dx, _y - _len * _dy - _w,
                    _x - _len * _dx, _y - _len * _dy + _w, _x, _y + _w];
        draw_poly_ramp(poly_clip(_seg, _band), c_white,
                       _a * (0.4 + 0.6 * frac(_i * 0.47)), 0, _x, _y, -_dx,
                       -_dy, _len);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The cut the band opens from, splitting out both ways from above
///       where he cast; and the line the band closes to, flaring before it
///       goes.
function sigil_cutin_draw_cut(_g, _col) {
    var _t = _g.t;
    var _a = 0;
    var _xa = FIELD_X0;
    var _xb = FIELD_X1;
    if (_t < 12) {
        var _r = card_ramp(_t, 0, 6);
        _xa = lerp(_g.x0, FIELD_X0, _r);
        _xb = lerp(_g.x0, FIELD_X1, _r);
        _a = 1 - cutin_in(_t, 5, 7);
    } else if (_t >= SIGIL_CUTIN_CLOSE_AT + 9) {
        _a = card_ramp(_t, SIGIL_CUTIN_CLOSE_AT + 9, 3)
             * (1 - cutin_smooth(_t, SIGIL_CUTIN_TIME - 6, 5));
    }
    if (_a <= 0.01) return;

    var _len = sqrt(1 + _g.k * _g.k);
    var _nx = -_g.k / _len;
    var _ny = 1 / _len;
    var _y0 = cutin_y(_g, _xa);
    gpu_set_blendmode(bm_add);
    for (var _s = -1; _s <= 1; _s += 2) {
        draw_poly_ramp(cutin_strip(_g, 0, _s * 16, _xa, _xb), _col,
                       0.6 * _a, 0, _xa, _y0, _nx * _s, _ny * _s, 16);
    }
    draw_poly(cutin_strip(_g, -1.6, 1.6, _xa, _xb), c_white, _a);
    // A light at each running end while it opens.
    if (_t < 8) {
        for (var _s = 0; _s < 2; _s++) {
            var _hx = (_s == 0) ? _xa : _xb;
            var _hy = cutin_y(_g, _hx);
            draw_bloom(_hx, _hy, 120, _col, _a * 0.8);
            gpu_set_blendmode(bm_add);
            card_draw_glint(_hx, _hy, 70, c_white, _a);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The two marks a spell's cut-in slams in as the eyes open
///       (`cutin_draw_mark`), over the band's upper edge toward its left end.
function sigil_cutin_draw_marks(_g) {
    var _t = _g.t;
    var _x = FIELD_X0 + 170;
    var _y = cutin_y(_g, _x) - SIGIL_CUTIN_H * 0.5 + 70;
    var _leave = cutin_in(_t, SIGIL_CUTIN_CLOSE_AT, 10);
    for (var _m = 0; _m < 2; _m++) {
        var _u = _t - SIGIL_CUTIN_OPEN_AT - _m * 3;
        if (_u < 0) continue;
        var _pop = cutin_back(_u, 0, 8);
        var _s = ((_m == 0) ? 1.45 : 1.1) * (1.9 - 0.9 * _pop)
                 * (1 - 0.4 * _leave);
        var _a = clamp(_u / 3, 0, 1) * (1 - _leave);
        cutin_draw_mark(_x + _m * 104 + dsin(_t * 41 + _m * 90) * 1.2,
                        _y + _m * 22 - 40 * _leave, _s, _a);
    }
}

/// @desc Szuix drawn again in front of the band, as a spell's caster is
///       (`cutin_draw_caster`): a glow behind him and a rim of his eyes'
///       colour round him, his focus circle, and his hitbox while he is
///       focused. It goes as the veil lifts off him as `player_draw` draws
///       him.
function sigil_cutin_draw_caster(_g, _p) {
    var _a = min(1, 3 * sigil_cutin_veil(_g.t));
    if (_a <= 0.01 || !_p.alive) return;
    // The world shakes and the GUI doesn't, so the shake is added here.
    var _x = _p.x + global.shake_x;
    var _y = _p.y + global.shake_y;
    var _fr = (_p.anim div 5) mod sprite_get_number(spr_szuix);
    var _ang = -_p.lean * 7;
    var _flicker = (_p.iframe > 0) ? 0.45 + 0.35 * dsin(_p.iframe * 34) : 1;

    gpu_set_blendmode(bm_add);
    var _gs = 220 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _gs, _gs, 0, COL_SZUIX, 0.5 * _a);
    draw_sprite_ext(spr_szuix_aura, _fr, _x, _y, 1, 1, _ang, COL_RUNE,
                    0.6 * _a * _a * _a);
    gpu_set_blendmode(bm_normal);
    player_draw_focus_ring(_p, _x, _y, _a);
    draw_sprite_ext(spr_szuix, _fr, _x, _y, 1, 1, _ang, c_white, _a * _flicker);
    player_draw_focus_heart(_p, _x, _y, _a);

    if (_p.focus && _p.entry <= 0) player_draw_hitbox_at(_x, _y, _a);
}
