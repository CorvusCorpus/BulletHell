/// @desc A spell's cut-in: its declaration, played over the field while the
///       spell holds its fire (`BOSS_SPELL_LEAD`).
///
/// A bright cut runs across the field (`Sfx.SpellCut`, sounded by
/// `boss_enter_phase`) and opens into a tilted band. In the band is the
/// caster's face with its eyes shut (the portrait's frame 0), pushed in over
/// a ground of the spell's colour, and the spell's name slides in on a plate
/// under the band's left end. Then the eyes snap open (frame 1):
/// the band flashes and jolts, the face punches in, light streaks from the
/// eyes, two marks slam in beside it, and the declaration's gong sounds
/// (`boss_cutin_step` times the cue to the frame). The band closes to a line,
/// and the name leaves its plate and flies up to its place under the boss's
/// rail, where the rail takes it over (`hud_step`).
///
/// The caster itself is drawn again in front of the band, with its sigil and
/// a rim of light, so the band never hides it.
///
/// Everything is a function of the boss's `cutin_t` (frames since the spell
/// was declared, -1 when idle): nothing is simulated. Everything stays inside
/// the field. A portrait (`def.cutin`) is two frames, eyes shut then open,
/// transparent round the head, with its origin on the band's centre line;
/// `cutin_art` says where its eyes are.

// Frames, from the declaration.
#macro CUTIN_BAND_TIME 96          // the band, from the cut to gone: the lead
#macro CUTIN_TIME 120              // all of it, the name's flight included
#macro CUTIN_OPEN_AT 34            // the eyes open
#macro CUTIN_CLOSE_AT 78           // the band starts to close
#macro CUTIN_FLY_AT 84             // the name leaves its plate...
#macro CUTIN_LAND_AT 106           // ...and arrives under the rail

// The declaration cue's gong comes this far into it (`cue_spell_declare`'s
// `hit_at`, 0.2s), so the cue starts this long before the eyes open.
#macro CUTIN_CUE_LEAD 12

// The band: its centre line crosses the field's middle column `CUTIN_Y` down,
// turned `CUTIN_TILT` degrees (anticlockwise, as GameMaker turns sprites; the
// face in Mika's sheet leans the same way).
#macro CUTIN_Y (FIELD_Y0 + FIELD_H * 0.40)
#macro CUTIN_TILT -7
#macro CUTIN_H 400

// The plate the name comes in on: its left end, how far under the band, its
// height, and how the name is set on it.
#macro CUTIN_PLATE_X (FIELD_X0 + 64)
#macro CUTIN_PLATE_GAP 34
#macro CUTIN_PLATE_H 118
#macro CUTIN_PLATE_LEAN 0.29       // its ends lean this much x per y
#macro CUTIN_NAME_S 0.86           // `fnt_spell` at this scale...
#macro CUTIN_NAME_MAX 640          // ...shrunk further past this width
#macro CUTIN_CAPTION_V 30          // where the caption's capitals are centred
#macro CUTIN_NAME_V 80             // ...and the name's

// ---------------------------------------------------------------------------
// Timing curves
// ---------------------------------------------------------------------------

/// @desc 0 to 1 over `_len` frames from `_at`, eased in (cubic).
function cutin_in(_t, _at, _len) {
    var _f = clamp((_t - _at) / max(1, _len), 0, 1);
    return _f * _f * _f;
}

/// @desc 0 to 1 over `_len` frames from `_at`, eased out hard (quintic).
function cutin_quint(_t, _at, _len) {
    var _f = 1 - clamp((_t - _at) / max(1, _len), 0, 1);
    return 1 - _f * _f * _f * _f * _f;
}

/// @desc 0 to 1 over `_len` frames from `_at`, overshooting and settling.
function cutin_back(_t, _at, _len) {
    var _f = clamp((_t - _at) / max(1, _len), 0, 1) - 1;
    return 1 + 2.7 * _f * _f * _f + 1.7 * _f * _f;
}

/// @desc 0 to 1 over `_len` frames from `_at`, eased in and out.
function cutin_smooth(_t, _at, _len) {
    var _f = clamp((_t - _at) / max(1, _len), 0, 1);
    return _f * _f * (3 - 2 * _f);
}

/// @desc `_v` folded into [0, 1). (`frac` keeps its sign.)
function cutin_wrap(_v) {
    var _f = frac(_v);
    return (_f < 0) ? _f + 1 : _f;
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// @desc The band this frame: how far open, where, and the jolt it takes when
///       the eyes open.
function cutin_geom(_t) {
    var _open = cutin_back(_t, 4, 12) * (1 - cutin_in(_t, CUTIN_CLOSE_AT, 14));
    var _jx = 0;
    var _jy = 0;
    var _u = _t - CUTIN_OPEN_AT;
    if (_u >= 0 && _u < 9) {
        var _k = 1 - _u / 9;
        _jx = dsin(_u * 131) * 9 * _k;
        _jy = dcos(_u * 97) * 6 * _k;
    }
    return {
        t: _t,
        h: CUTIN_H * _open,
        open: clamp(_open, 0, 1),
        cx: FIELD_CX + _jx,
        cy: CUTIN_Y + _jy,
        k: -dtan(CUTIN_TILT),       // the centre line's slope, y per x
    };
}

/// @desc The band's centre line at `_x`.
function cutin_y(_g, _x) {
    return _g.cy + _g.k * (_x - _g.cx);
}

/// @desc A quadrilateral between two lines of slope `_k` through
///       (`_cx`, `_cy` + `_a`) and (`_cx`, `_cy` + `_b`), from `_x0` to `_x1`,
///       as a flat `[x, y, ...]` array.
function cutin_quad(_cx, _cy, _k, _x0, _x1, _a, _b) {
    var _y0 = _cy + _k * (_x0 - _cx);
    var _y1 = _cy + _k * (_x1 - _cx);
    return [_x0, _y0 + _a, _x1, _y1 + _a, _x1, _y1 + _b, _x0, _y0 + _b];
}

/// @desc A strip along the band, `_a` to `_b` from its centre line.
function cutin_strip(_g, _a, _b, _x0 = FIELD_X0, _x1 = FIELD_X1) {
    return cutin_quad(_g.cx, _g.cy, _g.k, _x0, _x1, _a, _b);
}

function cutin_field_poly() {
    return [FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y0,
            FIELD_X1, FIELD_Y1, FIELD_X0, FIELD_Y1];
}

/// @desc The face this frame: where the portrait's origin is, its scale, the
///       frame shown, and the midpoint of its eyes. It slides in from the
///       right as it pushes in, drifts left, punches in as the eyes open, and
///       slides away as the band closes.
function cutin_face(_g, _spr) {
    var _t = _g.t;
    var _in = card_ramp(_t, 3, 18);
    var _out = cutin_in(_t, CUTIN_CLOSE_AT, 18);
    var _x = _g.cx + 120 * (1 - _in) - 0.4 * _t - 180 * _out;
    var _s = 1 + 0.16 * (1 - _in) + 0.0005 * _t + 0.05 * _out;
    var _u = _t - CUTIN_OPEN_AT;
    if (_u >= 0) _s += 0.07 * exp(-_u / 6) * cos(_u * 0.55);
    var _y = cutin_y(_g, _x);

    var _art = (_spr == undefined) ? { eyes: [], glow: c_white }
                                   : cutin_art(_spr);
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
    return { x: _x, y: _y, s: _s, fr: (_t >= CUTIN_OPEN_AT) ? 1 : 0,
             art: _art, ex: _ex, ey: _ey };
}

// ---------------------------------------------------------------------------
// Polygons
// ---------------------------------------------------------------------------

/// @desc Clip polygon `_subj` to the convex polygon `_clip` (both flat
///       `[x, y, ...]` arrays, either winding). Returns the part inside.
function poly_clip(_subj, _clip) {
    var _out = _subj;
    var _n = array_length(_clip) div 2;
    // The clip polygon's winding, so "inside" is the same side of every edge.
    var _area = 0;
    for (var _i = 0; _i < _n; _i++) {
        var _j = (_i + 1) mod _n;
        _area += _clip[_i * 2] * _clip[_j * 2 + 1]
               - _clip[_j * 2] * _clip[_i * 2 + 1];
    }
    var _sgn = (_area >= 0) ? 1 : -1;

    for (var _i = 0; _i < _n; _i++) {
        var _m = array_length(_out) div 2;
        if (_m == 0) break;
        var _ax = _clip[_i * 2];
        var _ay = _clip[_i * 2 + 1];
        var _j = (_i + 1) mod _n;
        var _ex = _clip[_j * 2] - _ax;
        var _ey = _clip[_j * 2 + 1] - _ay;

        var _src = _out;
        _out = [];
        var _px = _src[(_m - 1) * 2];
        var _py = _src[(_m - 1) * 2 + 1];
        var _pd = (_ex * (_py - _ay) - _ey * (_px - _ax)) * _sgn;
        for (var _k = 0; _k < _m; _k++) {
            var _qx = _src[_k * 2];
            var _qy = _src[_k * 2 + 1];
            var _qd = (_ex * (_qy - _ay) - _ey * (_qx - _ax)) * _sgn;
            if ((_qd >= 0) != (_pd >= 0)) {
                var _f = _pd / (_pd - _qd);
                array_push(_out, lerp(_px, _qx, _f), lerp(_py, _qy, _f));
            }
            if (_qd >= 0) array_push(_out, _qx, _qy);
            _px = _qx;
            _py = _qy;
            _pd = _qd;
        }
    }
    return _out;
}

/// @desc Fill a convex polygon in one colour.
function draw_poly(_poly, _col, _alpha) {
    var _n = array_length(_poly) div 2;
    if (_n < 3 || _alpha <= 0.004) return;
    draw_primitive_begin(pr_trianglelist);
    for (var _i = 1; _i < _n - 1; _i++) {
        draw_vertex_colour(_poly[0], _poly[1], _col, _alpha);
        draw_vertex_colour(_poly[_i * 2], _poly[_i * 2 + 1], _col, _alpha);
        draw_vertex_colour(_poly[_i * 2 + 2], _poly[_i * 2 + 3], _col, _alpha);
    }
    draw_primitive_end();
}

/// @desc Fill a convex polygon whose alpha runs from `_a0` to `_a1` along the
///       unit direction (`_dx`, `_dy`), over `_len` pixels from (`_x`, `_y`).
function draw_poly_ramp(_poly, _col, _a0, _a1, _x, _y, _dx, _dy, _len) {
    var _n = array_length(_poly) div 2;
    if (_n < 3 || max(_a0, _a1) <= 0.004) return;
    draw_primitive_begin(pr_trianglelist);
    for (var _i = 1; _i < _n - 1; _i++) {
        for (var _v = 0; _v < 3; _v++) {
            var _k = (_v == 0) ? 0 : (_i + _v - 1);
            var _px = _poly[_k * 2];
            var _py = _poly[_k * 2 + 1];
            var _f = clamp(((_px - _x) * _dx + (_py - _y) * _dy) / _len, 0, 1);
            draw_vertex_colour(_px, _py, _col, lerp(_a0, _a1, _f));
        }
    }
    draw_primitive_end();
}

/// @desc Draw the part of a sprite frame (placed at `_x`, `_y` by its origin
///       and scaled `_xs`, `_ys`) inside the convex polygon `_poly`, as a
///       textured primitive: the polygon is the mask, so the band can cut the
///       portrait off along slanted edges.
///
///       With `_mirror` (`{x, y, nx, ny, fade}`: a point on a line, its unit
///       normal, and a distance) the sprite is drawn reflected in that line
///       instead, fading to nothing `fade` pixels from it.
///
///       UVs run 0..1 across the part of the sprite kept on its page (a
///       primitive textured with `sprite_get_texture` reads the sprite's own
///       UV space; see `corridor_draw_band_wave`), inset half a texel, and the
///       polygon is first cut to that part, so a cropped sprite maps exactly.
function draw_sprite_poly(_spr, _fr, _x, _y, _xs, _ys, _poly, _col, _alpha,
                          _mirror = undefined) {
    if (_alpha <= 0.004) return;
    var _q4 = sprite_get_uvs(_spr, _fr);
    var _kx = _q4[4];
    var _ky = _q4[5];
    var _kw = max(1, sprite_get_width(_spr) * _q4[6]);
    var _kh = max(1, sprite_get_height(_spr) * _q4[7]);
    var _hu = 0.5 / _kw;
    var _hv = 0.5 / _kh;
    var _ox = sprite_get_xoffset(_spr);
    var _oy = sprite_get_yoffset(_spr);

    // The kept part of the sprite, on screen.
    var _l = _x + (_kx - _ox) * _xs;
    var _tp = _y + (_ky - _oy) * _ys;
    var _r = _l + _kw * _xs;
    var _bt = _tp + _kh * _ys;

    var _src = _poly;
    if (_mirror != undefined) _src = poly_reflect(_poly, _mirror);
    var _q = poly_clip(_src, [_l, _tp, _r, _tp, _r, _bt, _l, _bt]);
    var _n = array_length(_q) div 2;
    if (_n < 3) return;

    draw_primitive_begin_texture(pr_trianglelist, sprite_get_texture(_spr, _fr));
    for (var _i = 1; _i < _n - 1; _i++) {
        for (var _v = 0; _v < 3; _v++) {
            var _k = (_v == 0) ? 0 : (_i + _v - 1);
            var _sx = _q[_k * 2];
            var _sy = _q[_k * 2 + 1];
            var _u = lerp(_hu, 1 - _hu, (_sx - _l) / (_r - _l));
            var _w = lerp(_hv, 1 - _hv, (_sy - _tp) / (_bt - _tp));
            var _a = _alpha;
            if (_mirror != undefined) {
                var _d = (_sx - _mirror.x) * _mirror.nx
                       + (_sy - _mirror.y) * _mirror.ny;
                _sx -= 2 * _d * _mirror.nx;
                _sy -= 2 * _d * _mirror.ny;
                _a *= clamp(1 - abs(_d) / _mirror.fade, 0, 1);
            }
            draw_vertex_texture_colour(_sx, _sy, _u, _w, _col, _a);
        }
    }
    draw_primitive_end();
}

/// @desc A polygon reflected in the line `_mirror` (see `draw_sprite_poly`).
function poly_reflect(_poly, _mirror) {
    var _n = array_length(_poly);
    var _out = array_create(_n, 0);
    for (var _i = 0; _i < _n; _i += 2) {
        var _d = (_poly[_i] - _mirror.x) * _mirror.nx
               + (_poly[_i + 1] - _mirror.y) * _mirror.ny;
        _out[_i] = _poly[_i] - 2 * _d * _mirror.nx;
        _out[_i + 1] = _poly[_i + 1] - 2 * _d * _mirror.ny;
    }
    return _out;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw the cut-in (GUI layer, after the field's frame). `_h` is the
///       HUD, for where the rail puts the spell's name.
function cutin_draw(_h, _boss) {
    var _b = _boss.boss;
    var _t = _b.cutin_t;
    if (_t < 0) return;
    var _p = boss_phase(_boss);
    if (_p == undefined || _p.kind != AttackKind.Spell) return;

    var _col = global.bullet_colour[_p.col];
    var _spr = _b.def[$ "cutin"];
    var _g = cutin_geom(_t);
    var _f = cutin_face(_g, _spr);

    if (_t < CUTIN_BAND_TIME) {
        cutin_draw_veil(_g);
        cutin_draw_strips(_g, _col);
        if (_g.h > 1) {
            var _band = cutin_strip(_g, -_g.h * 0.5, _g.h * 0.5);
            if (_spr != undefined) cutin_draw_reflection(_g, _f, _spr);
            cutin_draw_ground(_g, _f, _band, _col);
            if (_spr != undefined) cutin_draw_face(_g, _f, _band, _spr, _col);
            cutin_draw_streaks(_g, _band);
            cutin_draw_motes(_g, _col);
            cutin_draw_edges(_g);
        }
        cutin_draw_cut(_g, _col);
        cutin_draw_caster(_g, _boss, _col);
        cutin_draw_marks(_g);
    }
    cutin_draw_name(_h, _g, _boss, _p, _col);

    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc How far the veil is down (0 to 1).
function cutin_veil(_t) {
    return card_ramp(_t, 0, 8) * (1 - cutin_smooth(_t, CUTIN_CLOSE_AT + 2, 16));
}

/// @desc The field darkened under the band, a little more at its top and
///       bottom than through the middle.
function cutin_draw_veil(_g) {
    var _a = cutin_veil(_g.t) * 0.62;
    if (_a <= 0.004) return;
    var _c = merge_colour(COL_VOID, COL_ARCANE, 0.25);
    var _ys = [FIELD_Y0, CUTIN_Y - CUTIN_H * 0.6, CUTIN_Y + CUTIN_H * 0.6,
               FIELD_Y1];
    var _as = [1.25, 0.85, 0.85, 1.3];
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i < 4; _i++) {
        var _aa = min(1, _a * _as[_i]);
        draw_vertex_colour(FIELD_X0, _ys[_i], _c, _aa);
        draw_vertex_colour(FIELD_X1, _ys[_i], _c, _aa);
    }
    draw_primitive_end();
}

/// @desc The layers round the band: a broad, steeper band of the spell's
///       colour behind it sliding in from the left, a bar of it above the
///       band from the right, and a gilt bar under its left end. They slide
///       back out as the band closes.
function cutin_draw_strips(_g, _col) {
    var _t = _g.t;
    var _hh = _g.h * 0.5;
    var _field = cutin_field_poly();
    var _gone = cutin_in(_t, CUTIN_CLOSE_AT - 2, 14);

    var _sl = FIELD_W * (1 - cutin_quint(_t, 2, 16)) + FIELD_W * _gone;
    var _ghost = cutin_quad(_g.cx - _sl, _g.cy, _g.k + 0.075,
                            FIELD_X0 - _sl, FIELD_X1 - _sl,
                            -_hh * 1.35, _hh * 1.35);
    draw_poly(poly_clip(_ghost, _field), _col, 0.11 * _g.open);

    var _sa = FIELD_W * (1 - cutin_quint(_t, 5, 14)) + FIELD_W * _gone;
    draw_poly(poly_clip(cutin_strip(_g, -_hh - 30, -_hh - 14,
                                    FIELD_X0 + FIELD_W * 0.36 + _sa,
                                    FIELD_X1 + _sa), _field),
              _col, 0.85);
    draw_poly(poly_clip(cutin_strip(_g, -_hh - 41, -_hh - 38,
                                    FIELD_X0 + FIELD_W * 0.56 + _sa * 1.2,
                                    FIELD_X1 + _sa * 1.2), _field),
              COL_GILT_LIT, 0.6);

    var _sb = FIELD_W * (1 - cutin_quint(_t, 7, 14)) + FIELD_W * _gone;
    draw_poly(poly_clip(cutin_strip(_g, _hh + 12, _hh + 19,
                                    FIELD_X0 - _sb,
                                    FIELD_X0 + FIELD_W * 0.42 - _sb), _field),
              COL_GILT_LIT, 0.75);
}

/// @desc The face reflected in the band's lower edge, as in a polished floor,
///       fading away from it.
function cutin_draw_reflection(_g, _f, _spr) {
    var _hh = _g.h * 0.5;
    var _deep = 150;
    var _area = poly_clip(cutin_strip(_g, _hh, _hh + _deep),
                          cutin_field_poly());
    // The edge's unit normal, pointing down.
    var _len = sqrt(1 + _g.k * _g.k);
    var _mirror = { x: _g.cx, y: _g.cy + _hh, nx: -_g.k / _len, ny: 1 / _len,
                    fade: _deep };
    draw_sprite_poly(_spr, _f.fr, _f.x, _f.y, _f.s, _f.s, _area, c_white,
                     0.22 * _g.open, _mirror);
}

/// @desc The band's ground: the spell's colour, darkest at the field's sides
///       and lit behind the face, with rays drawn out from the eyes.
function cutin_draw_ground(_g, _f, _band, _col) {
    var _dark = merge_colour(_col, COL_VOID, 0.84);
    var _mid = merge_colour(_col, COL_VOID, 0.52);
    var _n = 12;
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _n; _i++) {
        var _x = lerp(FIELD_X0, FIELD_X1, _i / _n);
        var _w = clamp(1 - abs(_x - _f.x) / (FIELD_W * 0.55), 0, 1);
        var _c = merge_colour(_dark, _mid, _w * _w * (3 - 2 * _w));
        var _y = cutin_y(_g, _x);
        draw_vertex_colour(_x, _y - _g.h * 0.5, _c, 0.97);
        draw_vertex_colour(_x, _y + _g.h * 0.5, _c, 0.97);
    }
    draw_primitive_end();

    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    draw_sprite_poly(spr_fx_bloom, 0, _f.ex, _f.ey, 1300 / _bw, 560 / _bw,
                     _band, _col, 0.55);
    draw_sprite_poly(spr_fx_bloom, 0, _f.ex, _f.ey - 30, 700 / _bw,
                     320 / _bw, _band, merge_colour(_col, c_white, 0.45), 0.3);

    // Rays from the eyes, flaring as they open.
    var _t = _g.t;
    var _u = _t - CUTIN_OPEN_AT;
    var _burst = (_u >= 0) ? exp(-_u / 7) : 0;
    var _a0 = 0.11 * _g.open + 0.5 * _burst;
    var _c = merge_colour(_col, c_white, 0.5);
    for (var _i = 0; _i < 32; _i++) {
        var _ang = _i * 11.25 + 6 * dsin(_i * 97) + _t * 0.06;
        var _r0 = 230 + 90 * frac(_i * 0.371);
        var _r1 = 1400;
        var _hw = (4 + 16 * frac(_i * 0.618)) * (1 + 0.8 * _burst);
        var _dx = dcos(_ang);
        var _dy = -dsin(_ang);
        var _tri = [_f.ex + _dx * _r0, _f.ey + _dy * _r0,
                    _f.ex + _dx * _r1 - _dy * _hw, _f.ey + _dy * _r1 + _dx * _hw,
                    _f.ex + _dx * _r1 + _dy * _hw, _f.ey + _dy * _r1 - _dx * _hw];
        draw_poly_ramp(poly_clip(_tri, _band), _c, 0,
                       _a0 * (0.5 + 0.5 * frac(_i * 0.293)),
                       _f.ex + _dx * _r0, _f.ey + _dy * _r0, _dx, _dy, 420);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The face, cut to the band, with a rim of the spell's colour round
///       it (the portrait is dark, and would sink into the band); the glow
///       gathering behind its shut eyes; and, as they open, the band's flash,
///       an echo of the face thrown forward, and a streak of light through
///       each eye.
function cutin_draw_face(_g, _f, _band, _spr, _col) {
    var _t = _g.t;
    var _u = _t - CUTIN_OPEN_AT;

    gpu_set_blendmode(bm_add);
    gpu_set_fog(true, merge_colour(_col, c_white, 0.25), 0, 0);
    for (var _i = 0; _i < 8; _i++) {
        draw_sprite_poly(_spr, _f.fr, _f.x + lengthdir_x(6, _i * 45),
                         _f.y + lengthdir_y(6, _i * 45), _f.s, _f.s, _band,
                         c_white, 0.26);
    }
    gpu_set_fog(false, c_black, 0, 0);
    gpu_set_blendmode(bm_normal);

    draw_sprite_poly(_spr, _f.fr, _f.x, _f.y, _f.s, _f.s, _band, c_white, 1);

    gpu_set_blendmode(bm_add);
    if (_u >= 0 && _u < 14) {
        var _k = 1 - _u / 14;
        var _es = _f.s * (1.05 + 0.04 * (1 - _k));
        draw_sprite_poly(_spr, 1, _f.x, _f.y, _es, _es, _band, c_white,
                         0.45 * _k * _k);
    }
    if (_u >= 0 && _u < 12) {
        var _k = 1 - _u / 12;
        draw_poly(_band, c_white, 0.55 * _k * _k);
    }

    var _eyes = _f.art.eyes;
    var _glow = _f.art.glow;
    var _bw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < array_length(_eyes); _i++) {
        var _e = _eyes[_i];
        var _x = _f.x + _e[0] * _f.s;
        var _y = _f.y + _e[1] * _f.s;
        var _a = (_u < 0)
            ? 0.04 + 0.14 * card_ramp(_t, 8, CUTIN_OPEN_AT - 8)
            : 0.34 + 0.08 * dsin(_t * 9) + 0.9 * exp(-_u / 5);
        var _sz = _e[2] * 3.4 * _f.s / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _sz, _sz * 0.8, 0, _glow,
                        min(1, _a));
        if (_u >= 0 && _u < 30) {
            var _len = 420 * ((_u < 4) ? (_u + 1) / 5 : exp(-(_u - 4) / 9));
            cutin_draw_streak(_x, _y - _e[3] * 0.15, _len, 7, CUTIN_TILT,
                              _glow, 0.9);
            cutin_draw_streak(_x, _y - _e[3] * 0.15, _len * 0.6, 3,
                              CUTIN_TILT, c_white, 1);
            cutin_draw_streak(_x, _y - _e[3] * 0.15, _len * 0.3, 3,
                              CUTIN_TILT + 90, c_white, 0.8);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc A streak of light `_len` either side of (`_x`, `_y`), `_wid` thick,
///       turned `_ang`. Additive; the caller sets the blend mode.
function cutin_draw_streak(_x, _y, _len, _wid, _ang, _col, _a) {
    if (_len <= 0.5 || _a <= 0.01) return;
    draw_sprite_ext(spr_fx_spark, 0, _x, _y,
                    _len * 2 / sprite_get_width(spr_fx_spark),
                    _wid / sprite_get_height(spr_fx_spark), _ang, _col, _a);
}

/// @desc Speed lines along the band, rushing left as the face slides in and
///       out, faint while it holds.
function cutin_draw_streaks(_g, _band) {
    var _t = _g.t;
    var _a = 0.04 + 0.4 * (1 - card_ramp(_t, 2, 20))
             + 0.35 * cutin_in(_t, CUTIN_CLOSE_AT - 4, 14);
    var _len0 = sqrt(1 + _g.k * _g.k);
    var _dx = 1 / _len0;
    var _dy = _g.k / _len0;
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 18; _i++) {
        var _v = (frac(_i * 0.7548) * 2 - 1) * 0.46 * _g.h;
        var _len = 160 + 380 * frac(_i * 0.5698);
        var _span = FIELD_W + _len + 200;
        var _run = _t * (38 + 30 * frac(_i * 0.339)) + frac(_i * 0.1234) * _span;
        var _x = FIELD_X1 + 100 - (_run mod _span);
        var _y = cutin_y(_g, _x) + _v;
        var _w = 1.5 + 2.5 * frac(_i * 0.83);
        var _seg = [_x, _y - _w, _x + _len * _dx, _y + _len * _dy - _w,
                    _x + _len * _dx, _y + _len * _dy + _w, _x, _y + _w];
        draw_poly_ramp(poly_clip(_seg, _band), c_white,
                       _a * (0.4 + 0.6 * frac(_i * 0.47)), 0, _x, _y, _dx,
                       _dy, _len);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Motes of gold and of the spell's colour rising through the band,
///       some catching the light.
function cutin_draw_motes(_g, _col) {
    var _t = _g.t;
    var _a0 = _g.open * (1 - cutin_in(_t, CUTIN_CLOSE_AT, 12));
    if (_a0 <= 0.01) return;
    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    var _lit = merge_colour(_col, c_white, 0.35);
    for (var _i = 0; _i < 30; _i++) {
        var _u = cutin_wrap(_i * 0.6180339 + 0.21
                            - _t * (0.0010 + 0.0012 * frac(_i * 0.377)));
        var _p = cutin_wrap(_t * (0.006 + 0.006 * frac(_i * 0.531))
                            + _i * 0.291);
        var _x = FIELD_X0 + 20 + (FIELD_W - 40) * _u;
        var _y = cutin_y(_g, _x) + _g.h * (0.42 - 0.84 * _p);
        var _a = _a0 * sin(_p * pi) * (0.35 + 0.4 * frac(_i * 0.71));
        var _c = ((_i mod 3) == 0) ? COL_GILT_LIT : _lit;
        var _k = (5 + 8 * frac(_i * 0.53)) / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _k, _k, 0, _c, _a);
        if ((_i mod 4) == 1) {
            var _tw = max(0, dsin(_t * 6 + _i * 71));
            card_draw_glint(_x, _y, 14 * _tw, _c, _a * _tw * 1.3);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The band's edges: a gilt line on each with a dark one outside it,
///       the field's width, and over them the title card's rules drawn out
///       from the middle (the plain one along the top, the one with the
///       crescent hanging under the band).
function cutin_draw_edges(_g) {
    var _hh = _g.h * 0.5;
    var _a = min(1, _g.h / 40);
    for (var _s = -1; _s <= 1; _s += 2) {
        var _e = _s * _hh;
        draw_poly(cutin_strip(_g, _e + _s * 1.2, _e + _s * 4.2), COL_VOID,
                  0.8 * _a);
        draw_poly(cutin_strip(_g, _e - 1.2, _e + 1.2), COL_GILT_LIT, 0.9 * _a);
    }
    var _w = card_ramp(_g.t, 6, 18);
    cutin_draw_rule(1, _g, -_hh, _w, _a);
    cutin_draw_rule(0, _g, _hh, _w, _a);
}

/// @desc Frame `_fr` of `spr_card_rule`, `_f` of it showing from its middle,
///       centred on the band's edge `_off` from its centre line and turned
///       with it.
function cutin_draw_rule(_fr, _g, _off, _f, _a) {
    if (_f <= 0 || _a <= 0.01) return;
    var _w = sprite_get_width(spr_card_rule);
    var _hgt = sprite_get_height(spr_card_rule);
    var _half = _w * 0.5 * _f;
    var _ang = CUTIN_TILT;
    // The part's top-left corner, turned about the rule's middle.
    var _x = _g.cx - _half * dcos(_ang) - _hgt * 0.5 * dsin(_ang);
    var _y = _g.cy + _off + _half * dsin(_ang) - _hgt * 0.5 * dcos(_ang);
    draw_sprite_general(spr_card_rule, _fr, _w * 0.5 - _half, 0, _half * 2,
                        _hgt, _x, _y, 1, 1, _ang, c_white, c_white, c_white,
                        c_white, _a);
}

/// @desc The cut the band opens from, running across the field left to right;
///       and the line the band closes to, flaring before it goes.
function cutin_draw_cut(_g, _col) {
    var _t = _g.t;
    var _a = 0;
    var _x1 = FIELD_X1;
    if (_t < 16) {
        _x1 = lerp(FIELD_X0, FIELD_X1, card_ramp(_t, 0, 7));
        _a = 1 - cutin_in(_t, 7, 9);
    } else if (_t >= CUTIN_CLOSE_AT + 11) {
        _a = card_ramp(_t, CUTIN_CLOSE_AT + 11, 3)
             * (1 - cutin_smooth(_t, CUTIN_BAND_TIME - 7, 5));
    }
    if (_a <= 0.01) return;

    var _len = sqrt(1 + _g.k * _g.k);
    var _nx = -_g.k / _len;
    var _ny = 1 / _len;
    var _y0 = cutin_y(_g, FIELD_X0);
    gpu_set_blendmode(bm_add);
    for (var _s = -1; _s <= 1; _s += 2) {
        draw_poly_ramp(cutin_strip(_g, 0, _s * 16, FIELD_X0, _x1), _col,
                       0.6 * _a, 0, FIELD_X0, _y0, _nx * _s, _ny * _s, 16);
    }
    draw_poly(cutin_strip(_g, -1.6, 1.6, FIELD_X0, _x1), c_white, _a);
    if (_t < 10) {
        var _hy = cutin_y(_g, _x1);
        draw_bloom(_x1, _hy, 120, _col, _a * 0.8);
        gpu_set_blendmode(bm_add);
        card_draw_glint(_x1, _hy, 70, c_white, _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The caster drawn again in front of the band: its sigil under it and a
///       glow behind it, brighter than `boss_draw` has them, and a rim of the
///       spell's colour round it. It goes as the veil lifts off the boss drawn
///       under it; the rim goes first, or the fading boss is washed out in
///       it. (A boss drawn in parts casts no spells,
///       and isn't drawn here.)
function cutin_draw_caster(_g, _e, _col) {
    var _t = _g.t;
    // Solid until the veil has nearly lifted, so the boss under it isn't
    // seen through.
    var _a = min(1, 3 * cutin_veil(_t));
    var _b = _e.boss;
    if (_a <= 0.01 || _b.def[$ "draw"] != undefined) return;

    var _spr = _b.def.sprite;
    var _pose = boss_pose(_e);
    // The world shakes and the GUI doesn't, so the shake is added here.
    var _bx = _e.x + global.shake_x;
    var _by = _e.y + global.shake_y;
    var _y = _by + _pose[1];

    gpu_set_blendmode(bm_add);
    var _rs = 300 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, _bx, _by, _rs, _rs * 0.42,
                    _e.t * 0.30, _col, 0.75 * _a);
    var _gs = 380 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _bx, _by, _gs, _gs, 0, _col, 0.5 * _a);
    gpu_set_fog(true, merge_colour(_col, c_white, 0.4), 0, 0);
    for (var _i = 0; _i < 8; _i++) {
        draw_sprite_ext(_spr, _pose[0], _bx + lengthdir_x(3, _i * 45),
                        _y + lengthdir_y(3, _i * 45), 1, 1, 0, c_white,
                        0.4 * _a * _a * _a);
    }
    gpu_set_fog(false, c_black, 0, 0);
    gpu_set_blendmode(bm_normal);
    draw_sprite_ext(_spr, _pose[0], _bx, _y, 1, 1, 0, c_white, _a);
}

/// @desc Two marks slammed in beside the face as its eyes open, like a pair
///       of exclamation marks: glass in gilt, leaning, over the band's
///       upper edge toward its right end.
function cutin_draw_marks(_g) {
    var _t = _g.t;
    var _x = FIELD_X1 - 300;
    var _y = cutin_y(_g, _x) - CUTIN_H * 0.5 + 70;
    var _leave = cutin_in(_t, CUTIN_CLOSE_AT, 12);
    for (var _m = 0; _m < 2; _m++) {
        var _u = _t - CUTIN_OPEN_AT - _m * 3;
        if (_u < 0) continue;
        var _pop = cutin_back(_u, 0, 8);
        var _s = ((_m == 0) ? 1.45 : 1.1) * (1.9 - 0.9 * _pop)
                 * (1 - 0.4 * _leave);
        var _a = clamp(_u / 3, 0, 1) * (1 - _leave);
        cutin_draw_mark(_x + _m * 104 + dsin(_t * 41 + _m * 90) * 1.2,
                        _y + _m * 36 - 40 * _leave, _s, _a);
    }
}

/// @desc One mark, its foot at (`_x`, `_y`), scaled `_s`: a tapering stroke
///       and a point under it, each with a dark shadow, a glass fill, a gilt
///       rim and a pale edge catching the light.
function cutin_draw_mark(_x, _y, _s, _a) {
    if (_a <= 0.01) return;
    var _shapes = [[-18, -156, 18, -156, 8, -46, -8, -46],
                   [0, -36, 15, -19, 0, -2, -15, -19]];
    var _lean = 0.30;
    for (var _k = 0; _k < 2; _k++) {
        var _src = _shapes[_k];
        var _n = array_length(_src) div 2;
        var _pts = array_create(_n * 2, 0);
        var _top = infinity;
        var _bot = -infinity;
        for (var _i = 0; _i < _n; _i++) {
            var _px = _src[_i * 2];
            var _py = _src[_i * 2 + 1];
            _pts[_i * 2] = _x + (_px - _py * _lean) * _s;
            _pts[_i * 2 + 1] = _y + _py * _s;
            _top = min(_top, _pts[_i * 2 + 1]);
            _bot = max(_bot, _pts[_i * 2 + 1]);
        }
        var _shadow = array_create(_n * 2, 0);
        for (var _i = 0; _i < _n; _i++) {
            _shadow[_i * 2] = _pts[_i * 2] + 9 * _s;
            _shadow[_i * 2 + 1] = _pts[_i * 2 + 1] + 9 * _s;
        }
        draw_poly(_shadow, COL_VOID, 0.6 * _a);

        // Glass: pale violet at the top to the dark at the foot.
        draw_primitive_begin(pr_trianglelist);
        for (var _i = 1; _i < _n - 1; _i++) {
            for (var _v = 0; _v < 3; _v++) {
                var _j = (_v == 0) ? 0 : (_i + _v - 1);
                var _f = (_pts[_j * 2 + 1] - _top) / max(1, _bot - _top);
                draw_vertex_colour(_pts[_j * 2], _pts[_j * 2 + 1],
                                   merge_colour(COL_ARCANE_LIT, COL_VOID, _f),
                                   (0.5 + 0.25 * _f) * _a);
            }
        }
        draw_primitive_end();

        // The rim, and a pale line along its upper-left edges.
        for (var _i = 0; _i < _n; _i++) {
            var _j = (_i + 1) mod _n;
            var _ax = _pts[_i * 2];
            var _ay = _pts[_i * 2 + 1];
            var _bx = _pts[_j * 2];
            var _by = _pts[_j * 2 + 1];
            var _len = max(0.001, point_distance(_ax, _ay, _bx, _by));
            var _nx = -(_by - _ay) / _len;
            var _ny = (_bx - _ax) / _len;
            var _w = 1.7 * _s;
            draw_poly([_ax + _nx * _w, _ay + _ny * _w, _bx + _nx * _w,
                       _by + _ny * _w, _bx - _nx * _w, _by - _ny * _w,
                       _ax - _nx * _w, _ay - _ny * _w], COL_GILT_LIT, _a);
            if (_nx + _ny > 0.3) {
                var _in = 4 * _s;
                draw_poly([_ax + _nx * _in, _ay + _ny * _in, _bx + _nx * _in,
                           _by + _ny * _in, _bx + _nx * (_in + 1.2),
                           _by + _ny * (_in + 1.2), _ax + _nx * (_in + 1.2),
                           _ay + _ny * (_in + 1.2)], COL_RUNE, 0.55 * _a);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// The name
// ---------------------------------------------------------------------------

/// @desc A point on the plate: `_u` along it and `_v` down it from its top-left
///       corner, with the plate slid `_slide` along its length.
function cutin_plate_at(_g, _u, _v, _slide) {
    var _px = CUTIN_PLATE_X;
    var _py = cutin_y(_g, _px) + CUTIN_H * 0.5 + CUTIN_PLATE_GAP;
    var _ax = dcos(CUTIN_TILT);
    var _ay = -dsin(CUTIN_TILT);
    var _uu = _u + _slide;
    return [_px + _uu * _ax + _v * _ay * -1, _py + _uu * _ay + _v * _ax];
}

/// @desc The plate, the name on it, the name's flight to the rail, and its
///       landing there.
function cutin_draw_name(_h, _g, _e, _p, _col) {
    var _t = _g.t;
    if (_t < 12) return;

    var _name = _p.name;
    var _cap = string_upper(_e.boss.def.name);
    draw_set_font(fnt_spell());
    var _nw = max(1, string_width(_name));
    var _ns = min(CUTIN_NAME_S, CUTIN_NAME_MAX / _nw);
    draw_set_font(fnt_small());
    var _cw = text_tracked_width(_cap, 8);
    var _len = max(_nw * _ns, _cw) + 110;

    var _slide = -(_len + 260) * (1 - cutin_quint(_t, 12, 16));
    var _in = clamp((_t - 12) / 4, 0, 1);

    // The plate, sliding back out the way it came as the name leaves it.
    if (_t < CUTIN_FLY_AT + 12) {
        var _back = cutin_smooth(_t, CUTIN_FLY_AT, 12);
        cutin_draw_plate(_g, _len, _slide - (_len + 260) * _back,
                         _in * (1 - _back), _cap, _col);
    }

    // The name on it: gilt, flashing white as the eyes open, a sheen crossing
    // it after.
    var _lean = CUTIN_PLATE_LEAN;
    var _from = cutin_plate_at(_g, 36 - CUTIN_NAME_V * _lean, CUTIN_NAME_V,
                               _slide);
    if (_t < CUTIN_FLY_AT) {
        var _u = _t - CUTIN_OPEN_AT;
        var _flash = (_u >= 0) ? 0.85 * exp(-_u / 5) : 0;
        var _sheen = (_u >= 4 && _u < 40) ? (_u - 4) / 36 : -1;
        draw_set_font(fnt_spell());
        cutin_draw_gilt_line(_from[0], _from[1], _name, _ns, CUTIN_TILT,
                             _in, _flash, _sheen);
        return;
    }

    // The flight: from the plate to the rail, shrinking and levelling, the
    // plate's lettering giving way to the rail's.
    var _dy = hud_rig_y(_h) - BOSS_BAR_Y;
    var _ra = clamp((_h.rig - 0.42) * 2.4, 0, 1);
    var _at = hud_spell_name_at(_name, _dy);   // sets `fnt_ui()`
    var _ui_w = max(1, string_width(_name));
    var _to_x = _at[0];
    var _to_y = BOSS_SPELL_Y + _dy;
    var _rs = _at[2];

    var _f = cutin_smooth(_t, CUTIN_FLY_AT, CUTIN_LAND_AT - CUTIN_FLY_AT);
    for (var _k = 3; _k >= 0; _k--) {
        // Three fading copies trail it while it flies.
        var _q = max(0, _f - _k * 0.03);
        if (_k > 0 && (_f >= 1 || _q <= 0)) continue;
        var _x = lerp(_from[0], _to_x, _q);
        var _y = lerp(_from[1], _to_y, _q) - dsin(_q * 180) * 60;
        var _ang = lerp(CUTIN_TILT, 0, _q);
        var _mix = clamp((_q - 0.1) / 0.6, 0, 1);
        _mix = _mix * _mix * (3 - 2 * _mix);
        var _ghost = (_k == 0) ? 1 : 0.14 / _k;

        draw_set_font(fnt_spell());
        var _cs = lerp(_ns, _rs * _ui_w / _nw, _q);
        if (_k == 0 && _mix < 1) {
            cutin_draw_gilt_line(_x, _y, _name, _cs, _ang, 1 - _mix, 0, -1);
        }
        draw_set_font(fnt_ui());
        var _us = lerp(_ns * _nw / _ui_w, _rs, _q);
        var _a = _mix * _ghost * lerp(1, _ra, _q);
        if (_k == 0) {
            cutin_draw_line_turned(_x, _y, _name, _us, _ang, _col, _a);
        } else {
            var _drop = text_cap_middle_y(0, _us);
            gpu_set_blendmode(bm_add);
            draw_set_halign(fa_left);
            draw_set_valign(fa_bottom);
            draw_set_colour(_col);
            draw_set_alpha(_a);
            draw_text_transformed(_x + _drop * dsin(_ang),
                                  _y + _drop * dcos(_ang), _name, _us, _us,
                                  _ang);
            gpu_set_blendmode(bm_normal);
            draw_set_alpha(1);
            draw_set_colour(c_white);
        }
    }

    // It lands with a glint at its head.
    var _l = _t - CUTIN_LAND_AT;
    if (_l >= 0) {
        var _k = 1 - _l / (CUTIN_TIME - CUTIN_LAND_AT);
        draw_bloom(_to_x + 6, _to_y, 110, _col, 0.6 * _k * _ra);
        gpu_set_blendmode(bm_add);
        card_draw_glint(_to_x + 6, _to_y, 46 * _k, c_white, _k * _ra);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The plate: indigo glass with gilt rules along its top and bottom, a
///       tab of the spell's colour at its left end, a star at its right, and
///       the caster's name over the spell's.
function cutin_draw_plate(_g, _len, _slide, _a, _cap, _col) {
    if (_a <= 0.01) return;
    var _hgt = CUTIN_PLATE_H;

    // A point on it, `_u` along and `_v` down, its ends leaning.
    var _pt = method({ g: _g, slide: _slide }, function(_u, _v) {
        return cutin_plate_at(g, _u - _v * CUTIN_PLATE_LEAN, _v, slide);
    });

    var _c0 = _pt(0, 0);
    var _c1 = _pt(_len, 0);
    var _c2 = _pt(_len, _hgt);
    var _c3 = _pt(0, _hgt);
    var _body = [_c0[0], _c0[1], _c1[0], _c1[1], _c2[0], _c2[1], _c3[0], _c3[1]];

    var _shadow = array_create(8, 0);
    for (var _i = 0; _i < 8; _i += 2) {
        _shadow[_i] = _body[_i] + 7;
        _shadow[_i + 1] = _body[_i + 1] + 9;
    }
    draw_poly(_shadow, COL_VOID, 0.45 * _a);

    var _top = merge_colour(COL_ARCANE, COL_VOID, 0.15);
    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(_c0[0], _c0[1], _top, 0.92 * _a);
    draw_vertex_colour(_c1[0], _c1[1], _top, 0.92 * _a);
    draw_vertex_colour(_c3[0], _c3[1], COL_VOID, 0.94 * _a);
    draw_vertex_colour(_c2[0], _c2[1], COL_VOID, 0.94 * _a);
    draw_primitive_end();

    // Its rules, and a thread of cyan under the top one.
    var _rules = [[0, 2.4, COL_GILT_LIT, 0.95], [2.4, 4.2, COL_VOID, 0.8],
                  [_hgt - 2.4, _hgt, COL_GILT, 0.9], [7, 8.2, COL_RUNE, 0.45]];
    for (var _i = 0; _i < array_length(_rules); _i++) {
        var _r = _rules[_i];
        var _u1 = (_i == 3) ? _len * 0.62 : _len;
        var _p0 = _pt(0, _r[0]);
        var _p1 = _pt(_u1, _r[0]);
        var _p2 = _pt(_u1, _r[1]);
        var _p3 = _pt(0, _r[1]);
        draw_poly([_p0[0], _p0[1], _p1[0], _p1[1], _p2[0], _p2[1], _p3[0],
                   _p3[1]], _r[2], _r[3] * _a);
    }

    var _t0 = _pt(0, 0);
    var _t1 = _pt(14, 0);
    var _t2 = _pt(14, _hgt);
    var _t3 = _pt(0, _hgt);
    draw_poly([_t0[0], _t0[1], _t1[0], _t1[1], _t2[0], _t2[1], _t3[0], _t3[1]],
              _col, 0.95 * _a);

    var _st = _pt(_len - 30, _hgt * 0.5);
    card_draw_star(_st[0], _st[1], 16 + 10 * dsin(_g.t * 7), 0.7 * _a);

    // The caster's name, small and spaced, over the spell's.
    var _cp = _pt(36, CUTIN_CAPTION_V);
    draw_set_font(fnt_small());
    cutin_draw_tracked_turned(_cp[0], _cp[1], _cap, 8, CUTIN_TILT, COL_RUNE,
                              0.9 * _a);
}

/// @desc A line of capitals, each glyph turned `_ang` about the line's start
///       (`draw_text_tracked` can't turn). Its capitals are centred on
///       (`_x`, `_y`) vertically; `_x` is its left end.
function cutin_draw_tracked_turned(_x, _y, _str, _track, _ang, _col, _a) {
    if (_a <= 0.01) return;
    var _ax = dcos(_ang);
    var _ay = -dsin(_ang);
    var _drop = text_cap_middle_y(0);
    draw_set_halign(fa_left);
    draw_set_valign(fa_bottom);
    draw_set_colour(_col);
    draw_set_alpha(_a);
    var _run = 0;
    for (var _i = 1; _i <= string_length(_str); _i++) {
        var _ch = string_char_at(_str, _i);
        draw_text_transformed(_x + _run * _ax - _drop * _ay,
                              _y + _run * _ay + _drop * _ax, _ch, 1, 1, _ang);
        _run += string_width(_ch) + _track;
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A line in the current font, its capitals centred vertically on
///       (`_x`, `_y`) with `_x` its left end, turned `_ang`, with the rail's
///       dark outline. At `_ang` 0 this is exactly what `draw_text_fit` draws
///       under the rail.
function cutin_draw_line_turned(_x, _y, _str, _s, _ang, _col, _a) {
    if (_a <= 0.01) return;
    var _drop = text_cap_middle_y(0, _s);
    var _ax = dcos(_ang);
    var _ay = -dsin(_ang);
    var _ox = _x - _drop * _ay;
    var _oy = _y + _drop * _ax;
    draw_set_halign(fa_left);
    draw_set_valign(fa_bottom);
    draw_set_colour(c_black);
    draw_set_alpha(_a * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text_transformed(_ox + lengthdir_x(3, _i * 45),
                              _oy + lengthdir_y(3, _i * 45), _str, _s, _s,
                              _ang);
    }
    draw_set_colour(_col);
    draw_set_alpha(_a);
    draw_text_transformed(_ox, _oy, _str, _s, _s, _ang);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A line in gilt (`sh_gilt_text`) in the current font: its capitals
///       centred vertically on (`_x`, `_y`) with `_x` its left end, turned
///       `_ang`, with a soft shadow and a dark line round it. `_flash` turns it
///       white-gold; `_sheen` (0 to 1, or -1 for none) is a band of light
///       crossing it.
function cutin_draw_gilt_line(_x, _y, _str, _s, _ang, _a, _flash, _sheen) {
    if (_a <= 0.01) return;
    static _u = undefined;
    if (_u == undefined && shader_is_compiled(sh_gilt_text)) {
        _u = {
            origin: shader_get_uniform(sh_gilt_text, "u_origin"),
            down: shader_get_uniform(sh_gilt_text, "u_down"),
            cap: shader_get_uniform(sh_gilt_text, "u_cap"),
            bevel: shader_get_uniform(sh_gilt_text, "u_bevel"),
            sheen: shader_get_uniform(sh_gilt_text, "u_sheen"),
            flash: shader_get_uniform(sh_gilt_text, "u_flash"),
        };
    }

    var _cell = string_height("H") * _s;
    var _drop = text_cap_middle_y(0, _s);
    var _ax = dcos(_ang);
    var _ay = -dsin(_ang);
    // The anchor (`fa_left`, `fa_bottom`) and the unit vector down the letters.
    var _ox = _x - _drop * _ay;
    var _oy = _y + _drop * _ax;
    var _dx = -_ay;
    var _dy = _ax;

    draw_set_halign(fa_left);
    draw_set_valign(fa_bottom);
    draw_set_colour(make_colour_rgb(6, 2, 10));
    for (var _k = 1; _k <= 3; _k++) {
        draw_set_alpha(0.16 * _a);
        draw_text_transformed(_ox + 2.5 * _k, _oy + 3.5 * _k, _str, _s, _s,
                              _ang);
    }
    draw_set_colour(make_colour_rgb(34, 14, 28));
    draw_set_alpha(0.95 * _a);
    for (var _i = 0; _i < 8; _i++) {
        draw_text_transformed(_ox + lengthdir_x(2.6, _i * 45),
                              _oy + lengthdir_y(2.6, _i * 45), _str, _s, _s,
                              _ang);
    }

    draw_set_alpha(_a);
    if (_u == undefined) {
        // No shader: plain gold.
        draw_set_colour(merge_colour(COL_GILT_LIT, c_white, _flash));
        draw_text_transformed(_ox, _oy, _str, _s, _s, _ang);
    } else {
        var _w = string_width(_str) * _s;
        var _tex = font_get_texture(draw_get_font());
        shader_set(sh_gilt_text);
        shader_set_uniform_f(_u.origin, _ox, _oy);
        shader_set_uniform_f(_u.down, _dx, _dy);
        shader_set_uniform_f(_u.cap,
                             -_cell * (FONT_BASELINE_DROP + FONT_INK_RATIO),
                             _cell * FONT_INK_RATIO);
        shader_set_uniform_f(_u.bevel, texture_get_texel_width(_tex) * 1.4,
                             texture_get_texel_height(_tex) * 1.8);
        shader_set_uniform_f(_u.sheen, lerp(-160, _w + 160, max(0, _sheen)),
                             90, (_sheen >= 0) ? 0.9 : 0);
        shader_set_uniform_f(_u.flash, _flash);
        draw_set_colour(c_white);
        draw_text_transformed(_ox, _oy, _str, _s, _s, _ang);
        shader_reset();
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}
