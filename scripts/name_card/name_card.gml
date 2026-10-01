/// @desc A boss's name card: who it is, said once, before its first attack.
///
/// It is the spell cut-in's band (`spell_cutin`) put to a name. A bright cut
/// runs across the field and opens into a narrow tilted band of dark glass.
/// The boss's title comes in along it, then its name slams in over that in
/// gilt, with the declaration's gong (`boss_namecard_step` times the cue and
/// starts the boss's theme), a flash and a jolt. The card holds until it is
/// let go (`boss_namecard_release`); then the band closes to a line, and the
/// name leaves it and flies up to its plate on the boss's rail, where the
/// rail takes it over (`hud_step`).
///
/// A conversation plays the card as one of its beats (`talk_card`), with the
/// speakers' portraits standing round it; a final boss with nothing to say
/// gets it on its own during its declaration, with the boss itself drawn in
/// front of the band.
///
/// Everything is a function of the boss's `card_t` (frames since the card
/// began, -1 when idle) and `card_out` (frames since it was let go, -1 while
/// it holds): nothing is simulated. Everything stays inside the field.

// Frames, from the card's start.
#macro NAMECARD_TITLE_AT 10        // the title comes in
#macro NAMECARD_SLAM_AT 30         // the name lands
#macro NAMECARD_HOLD_MIN 62        // the soonest it may be let go

// Frames, from its being let go.
#macro NAMECARD_FLY_AT 6           // the name leaves the band...
#macro NAMECARD_LAND_AT 30         // ...and arrives on the rail
#macro NAMECARD_OUT_TIME 44        // all of the leaving

// The band: where its centre line crosses the field's middle column, and its
// height. It is turned as the cut-in's is (`CUTIN_TILT`).
#macro NAMECARD_Y (FIELD_Y0 + FIELD_H * 0.52)
#macro NAMECARD_H 240

// What is written on it, measured down from its centre line: the name's
// capitals, the rule under them, and the title. Each is shrunk past its
// width.
#macro NAMECARD_NAME_V -34
#macro NAMECARD_RULE_V 38
#macro NAMECARD_TITLE_V 76
#macro NAMECARD_NAME_MAX 640
#macro NAMECARD_TITLE_MAX 760

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// @desc The card's band this frame, in the cut-in's own terms (`cutin_geom`)
///       so the cut-in's parts can draw it. Its `t` is where the cut-in would
///       be: opening as the card opens, held while it holds, and closing from
///       the frame it is let go.
function namecard_geom(_b) {
    var _t = _b.card_t;
    var _o = _b.card_out;
    var _open = cutin_back(_t, 4, 12);
    if (_o >= 0) _open *= 1 - cutin_in(_o, 0, 14);

    // The jolt it takes as the name lands.
    var _jx = 0;
    var _jy = 0;
    var _u = _t - NAMECARD_SLAM_AT;
    if (_u >= 0 && _u < 9) {
        var _k = 1 - _u / 9;
        _jx = dsin(_u * 131) * 9 * _k;
        _jy = dcos(_u * 97) * 6 * _k;
    }
    return {
        t: (_o < 0) ? min(_t, CUTIN_CLOSE_AT - 12) : (CUTIN_CLOSE_AT + _o),
        h: NAMECARD_H * _open,
        open: clamp(_open, 0, 1),
        cx: FIELD_CX + _jx,
        cy: NAMECARD_Y + _jy,
        k: -dtan(CUTIN_TILT),
    };
}

/// @desc Is the card on screen?
function namecard_live(_boss) {
    return _boss != undefined && _boss.boss.card_t >= 0;
}

// How much of the middle of `spr_card_rule`'s two frames is ornament rather
// than line: the crescent, and the lozenge. A band or a plate with a rule of
// its own sets one into a break in it, and leaves the sprite's lines out.
#macro RULE_ORN_CRESCENT 44
#macro RULE_ORN_LOZENGE 22

// ---------------------------------------------------------------------------
// Parts shared with a conversation (`talk_draw_blade`, `talk_draw_plate`)
// ---------------------------------------------------------------------------

/// @desc A line along the band `_g`, from `_a` to `_b` off its centre line
///       and `_x0` to `_x1` across the field.
function band_draw_line(_g, _a, _b, _x0, _x1, _col, _alpha) {
    draw_poly(cutin_strip(_g, _a, _b, _x0, _x1), _col, _alpha);
}

/// @desc One of `spr_card_rule`'s ornaments (frame 0's crescent, frame 1's
///       lozenge: `_w` is its width in the sprite), turned with the band and
///       centred `_off` down from the point (`_x`, `_y`).
function band_draw_ornament(_fr, _w, _x, _y, _off, _a) {
    cutin_draw_rule(_fr, { cx: _x, cy: _y }, _off,
                    _w / sprite_get_width(spr_card_rule), _a);
}

/// @desc Rays of `_col` out from (`_x`, `_y`), cut to the convex polygon
///       `_clip`: each rises from nothing `_r0` out, and is gone by `_r1`.
///       They turn slowly with `_t`; `_burst` (0 to 1) flares them. Additive.
function band_draw_rays(_x, _y, _clip, _col, _a0, _burst, _t, _r0, _r1) {
    if (_a0 <= 0.004) return;
    gpu_set_blendmode(bm_add);
    var _mid = lerp(_r0, _r1, 0.4);
    for (var _i = 0; _i < 28; _i++) {
        var _ang = _i * 12.857 + 6 * dsin(_i * 97) + _t * 0.06;
        var _in = _r0 + 70 * frac(_i * 0.371);
        var _hw = (3 + 13 * frac(_i * 0.618)) * (1 + 0.8 * _burst);
        var _dx = dcos(_ang);
        var _dy = -dsin(_ang);
        var _a = _a0 * (0.5 + 0.5 * frac(_i * 0.293));
        // A wedge widening outward, in two lengths: brightening, then
        // fading.
        var _f = (_mid - _in) / max(1, _r1 - _in);
        var _x0 = _x + _dx * _in;
        var _y0 = _y + _dy * _in;
        var _x1 = _x + _dx * _mid;
        var _y1 = _y + _dy * _mid;
        var _x2 = _x + _dx * _r1;
        var _y2 = _y + _dy * _r1;
        var _w1 = _hw * _f;
        draw_poly_ramp(poly_clip([_x0, _y0, _x1 - _dy * _w1, _y1 + _dx * _w1,
                                  _x1 + _dy * _w1, _y1 - _dx * _w1], _clip),
                       _col, 0, _a, _x0, _y0, _dx, _dy, _mid - _in);
        draw_poly_ramp(poly_clip([_x1 - _dy * _w1, _y1 + _dx * _w1,
                                  _x2 - _dy * _hw, _y2 + _dx * _hw,
                                  _x2 + _dy * _hw, _y2 - _dx * _hw,
                                  _x1 + _dy * _w1, _y1 - _dx * _w1], _clip),
                       _col, _a, 0, _x1, _y1, _dx, _dy, _r1 - _mid);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Motes of gold and of `_col` rising through the band `_g` between
///       `_x0` and `_x1`, some catching the light. Each is a function of the
///       clock `_t`. Additive.
function band_draw_motes(_g, _col, _a0, _t, _x0 = FIELD_X0, _x1 = FIELD_X1,
                         _n = 26) {
    if (_a0 <= 0.01) return;
    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    var _lit = merge_colour(_col, c_white, 0.35);
    for (var _i = 0; _i < _n; _i++) {
        var _u = cutin_wrap(_i * 0.6180339 + 0.21
                            - _t * (0.0010 + 0.0012 * frac(_i * 0.377)));
        var _p = cutin_wrap(_t * (0.006 + 0.006 * frac(_i * 0.531))
                            + _i * 0.291);
        var _x = lerp(_x0 + 20, _x1 - 20, _u);
        var _y = cutin_y(_g, _x) + _g.h * (0.42 - 0.84 * _p);
        // Fainter toward both ends of the stretch, and of the rise.
        var _a = _a0 * sin(_p * pi) * sin(_u * pi)
                 * (0.35 + 0.4 * frac(_i * 0.71));
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

/// @desc A line of tracked capitals in the current font, centred on
///       (`_cx`, `_cy`) by its length and by its capitals' ink, scaled `_s`
///       and turned `_ang`, with the rail's dark outline (`_thick`; none at
///       0). At scale 1 and no turn this is exactly what the rail's
///       nameplate draws.
function band_draw_tracked(_cx, _cy, _str, _track, _s, _ang, _col, _a,
                           _thick = 3) {
    if (_a <= 0.01) return;
    var _ax = dcos(_ang);
    var _ay = -dsin(_ang);
    var _half = text_tracked_width(_str, _track) * _s * 0.5;
    var _drop = text_cap_middle_y(0, _s);
    var _x = _cx - _half * _ax - _drop * _ay;
    var _y = _cy - _half * _ay + _drop * _ax;
    draw_set_halign(fa_left);
    draw_set_valign(fa_bottom);
    var _run = 0;
    for (var _i = 1; _i <= string_length(_str); _i++) {
        var _ch = string_char_at(_str, _i);
        var _gx = _x + _run * _ax;
        var _gy = _y + _run * _ay;
        if (_thick > 0) {
            draw_set_colour(c_black);
            draw_set_alpha(_a * 0.85);
            for (var _k = 0; _k < 8; _k++) {
                draw_text_transformed(_gx + lengthdir_x(_thick, _k * 45),
                                      _gy + lengthdir_y(_thick, _k * 45),
                                      _ch, _s, _s, _ang);
            }
        }
        draw_set_colour(_col);
        draw_set_alpha(_a);
        draw_text_transformed(_gx, _gy, _ch, _s, _s, _ang);
        _run += (string_width(_ch) + _track) * _s;
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw a boss's name card (GUI layer, after the field's frame). `_h`
///       is the HUD, for where the rail puts the name. It is played with
///       no conversation round it, so it darkens the field itself and draws
///       the boss again in front of its band. (A conversation draws the
///       card's parts among its own: `talk_draw`.)
function namecard_draw(_h, _boss) {
    if (!namecard_live(_boss)) return;
    var _b = _boss.boss;
    var _col = global.bullet_colour[_b.def.col];
    var _g = namecard_geom(_b);

    cutin_draw_veil(_g);
    namecard_draw_band(_g, _boss, FIELD_CX, _col, NAMECARD_TITLE_MAX);
    cutin_draw_caster(_g, _boss, _col);
    namecard_draw_flight(_h, _g, _boss, FIELD_CX, _col, NAMECARD_TITLE_MAX);

    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The band and what is written on it, while the name is still there.
///       `_tx` is the column the writing is centred on, and `_room` the
///       width it is kept to.
function namecard_draw_band(_g, _boss, _tx, _col, _room) {
    var _b = _boss.boss;
    var _t = _b.card_t;
    var _o = _b.card_out;
    var _u = _t - NAMECARD_SLAM_AT;

    namecard_draw_strips(_g, _col);
    if (_g.h > 1) {
        var _band = cutin_strip(_g, -_g.h * 0.5, _g.h * 0.5);
        var _ny = cutin_y(_g, _tx) + NAMECARD_NAME_V * 0.3;
        var _burst = (_u >= 0) ? exp(-_u / 7) : 0;

        // Dark glass, lightest behind the name.
        var _n = 12;
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i <= _n; _i++) {
            var _x = lerp(FIELD_X0, FIELD_X1, _i / _n);
            var _w = clamp(1 - abs(_x - _tx) / (FIELD_W * 0.6), 0, 1);
            _w = _w * _w * (3 - 2 * _w);
            var _y = cutin_y(_g, _x);
            draw_vertex_colour(_x, _y - _g.h * 0.5,
                               merge_colour(COL_VOID, COL_ARCANE,
                                            0.30 + 0.60 * _w), 0.96);
            draw_vertex_colour(_x, _y + _g.h * 0.5,
                               merge_colour(COL_VOID, COL_ARCANE, 0.20 * _w),
                               0.96);
        }
        draw_primitive_end();

        // The boss's colour gathered behind the name, and its circle.
        gpu_set_blendmode(bm_add);
        var _bw = sprite_get_width(spr_fx_bloom);
        draw_sprite_poly(spr_fx_bloom, 0, _tx, _ny, 1250 / _bw, 520 / _bw,
                         _band, _col, 0.30 + 0.25 * _burst);
        draw_sprite_poly(spr_fx_bloom, 0, _tx, _ny, 620 / _bw, 250 / _bw,
                         _band, merge_colour(_col, c_white, 0.5),
                         0.16 + 0.3 * _burst);
        if (_u >= 0) {
            var _ra = min(1, _u / 14) * _g.open;
            var _rs = 500 / sprite_get_width(spr_boss_sigil);
            draw_sprite_ext(spr_boss_sigil, 0, _tx, _ny, _rs, _rs * 0.40,
                            _t * 0.30, _col, 0.34 * _ra);
            draw_sprite_ext(spr_boss_sigil, 0, _tx, _ny, _rs * 0.7,
                            _rs * 0.28, -_t * 0.52, c_white, 0.13 * _ra);
        }
        gpu_set_blendmode(bm_normal);
        band_draw_rays(_tx, _ny, _band, merge_colour(_col, c_white, 0.5),
                       0.09 * _g.open + 0.45 * _burst, _burst, _t, 150, 1100);

        if (_t < 26 || _o >= 0) cutin_draw_streaks(_g, _band);
        band_draw_motes(_g, _col, _g.open, _t);
        namecard_draw_edges(_g, _tx);

        namecard_draw_text(_g, _b, _tx, _col, _room);

        // The flash as the name lands.
        if (_u >= 0 && _u < 12) {
            var _k = 1 - _u / 12;
            gpu_set_blendmode(bm_add);
            draw_poly(_band, c_white, 0.5 * _k * _k);
            gpu_set_blendmode(bm_normal);
        }
    }
    cutin_draw_cut(_g, _col);
}

/// @desc The layers round the band, as the cut-in has them but fewer: a
///       broad, steeper band of the boss's colour behind it sliding in from
///       the left, and a bar of it above the band from the right. They slide
///       back out as the band closes.
function namecard_draw_strips(_g, _col) {
    var _t = _g.t;
    var _hh = _g.h * 0.5;
    var _gone = cutin_in(_t, CUTIN_CLOSE_AT - 2, 14);

    var _sl = FIELD_W * (1 - cutin_quint(_t, 2, 16)) + FIELD_W * _gone;
    var _ghost = cutin_quad(_g.cx - _sl, _g.cy, _g.k + 0.075,
                            FIELD_X0 - _sl, FIELD_X1 - _sl,
                            -_hh * 1.35, _hh * 1.35);
    draw_poly(poly_clip(_ghost, cutin_field_poly()), _col, 0.11 * _g.open);

    var _sa = FIELD_W * (1 - cutin_quint(_t, 5, 14)) + FIELD_W * _gone;
    var _x0 = FIELD_X0 + FIELD_W * 0.36 + _sa;
    if (_x0 < FIELD_X1) {
        band_draw_line(_g, -_hh - 28, -_hh - 14, _x0, FIELD_X1, _col, 0.85);
    }
}

/// @desc The band's edges: one gilt line on each with a dark one outside
///       it, the field's width. The title card's lozenge is set into a break
///       in the upper line and its crescent into one in the lower, at the
///       column `_tx` the writing is centred on.
function namecard_draw_edges(_g, _tx) {
    var _hh = _g.h * 0.5;
    var _a = min(1, _g.h / 40);
    var _gaps = [RULE_ORN_LOZENGE * 0.5 + 6, RULE_ORN_CRESCENT * 0.5 + 12];
    for (var _i = 0; _i < 2; _i++) {
        var _s = (_i == 0) ? -1 : 1;
        var _e = _s * _hh;
        band_draw_line(_g, _e + _s * 1.2, _e + _s * 4.2, FIELD_X0, FIELD_X1,
                       COL_VOID, 0.8 * _a);
        band_draw_line(_g, _e - 1.2, _e + 1.2, FIELD_X0, _tx - _gaps[_i],
                       COL_GILT_LIT, 0.9 * _a);
        band_draw_line(_g, _e - 1.2, _e + 1.2, _tx + _gaps[_i], FIELD_X1,
                       COL_GILT_LIT, 0.9 * _a);
    }
    var _w = card_ramp(_g.t, 6, 14) * _a;
    band_draw_ornament(1, RULE_ORN_LOZENGE, _tx, cutin_y(_g, _tx), -_hh, _w);
    band_draw_ornament(0, RULE_ORN_CRESCENT, _tx, cutin_y(_g, _tx), _hh, _w);
}

/// @desc The title, the rule and the name on the band. The name is drawn
///       here until it leaves for the rail (`namecard_draw_flight`).
function namecard_draw_text(_g, _b, _tx, _col, _room) {
    var _t = _b.card_t;
    var _o = _b.card_out;
    var _ax = dcos(CUTIN_TILT);
    var _ay = -dsin(CUTIN_TILT);
    // The band's centre line where the name stands, and how much of the
    // writing is left as the band closes.
    var _cy = cutin_y(_g, _tx);
    var _keep = (_o < 0) ? 1 : (1 - cutin_in(_o, 0, 10));

    // The title: in along the band from the right, under the name's place.
    var _title = _b.def[$ "title"] ?? "";
    var _ta = card_ramp(_t, NAMECARD_TITLE_AT, 16) * _keep;
    if (_title != "" && _ta > 0.01) {
        draw_set_font(fnt_ui());
        var _w = max(1, string_width(_title));
        var _s = min(1, min(NAMECARD_TITLE_MAX, _room) / _w);
        var _sl = 90 * (1 - cutin_quint(_t, NAMECARD_TITLE_AT, 18));
        var _u0 = _sl - _w * _s * 0.5;
        cutin_draw_line_turned(_tx + _u0 * _ax - NAMECARD_TITLE_V * _ay,
                               _cy + _u0 * _ay + NAMECARD_TITLE_V * _ax,
                               _title, _s, CUTIN_TILT,
                               merge_colour(COL_PARCHMENT, _col, 0.22), _ta);
    }

    // The rule between them, drawn out from its middle.
    var _rw = card_ramp(_t, NAMECARD_TITLE_AT + 4, 22) * 0.62;
    cutin_draw_rule(1, { cx: _tx - NAMECARD_RULE_V * _ay, cy: _cy },
                    NAMECARD_RULE_V * _ax, _rw, _keep * _g.open);

    // The name: slammed in oversized, flashing white, a sheen crossing it
    // after.
    var _u = _t - NAMECARD_SLAM_AT;
    if (_u < 0 || (_o >= NAMECARD_FLY_AT)) return;
    var _name = string_upper(_b.def.name);
    draw_set_font(fnt_title());
    var _nw = max(1, string_width(_name));
    var _ns = min(1, min(NAMECARD_NAME_MAX, _room) / _nw);
    var _pop = cutin_back(_u, 0, 9);
    var _sc = _ns * (2.3 - 1.3 * _pop);
    var _half = _nw * _sc * 0.5;
    var _flash = 0.9 * exp(-_u / 5);
    var _sheen = (_u >= 6 && _u < 46) ? (_u - 6) / 40 : -1;
    cutin_draw_gilt_line(_tx - _half * _ax - NAMECARD_NAME_V * _ay,
                         _cy - _half * _ay + NAMECARD_NAME_V * _ax, _name,
                         _sc, CUTIN_TILT, clamp(_u / 3, 0, 1), _flash, _sheen);

    // A star thrown across it as it lands.
    if (_u < 30) {
        var _f = 1 - _u / 30;
        card_draw_star(_tx - NAMECARD_NAME_V * _ay, _cy + NAMECARD_NAME_V * _ax,
                       60 + 620 * _f * _f, _f * _f);
    }
}

/// @desc The name's flight from the band to its plate on the rail, and its
///       landing there: it shrinks and levels, the band's gilt lettering
///       giving way to the rail's.
function namecard_draw_flight(_h, _g, _boss, _tx, _col, _room) {
    var _b = _boss.boss;
    var _o = _b.card_out;
    if (_o < NAMECARD_FLY_AT) return;

    var _name = string_upper(_b.def.name);
    var _ax = dcos(CUTIN_TILT);
    var _ay = -dsin(CUTIN_TILT);
    var _dy = hud_rig_y(_h) - BOSS_BAR_Y;
    var _ra = clamp((_h.rig - 0.42) * 2.4, 0, 1);

    draw_set_font(fnt_title());
    var _nw = max(1, string_width(_name));
    var _ns = min(1, min(NAMECARD_NAME_MAX, _room) / _nw);
    draw_set_font(fnt_ui());
    var _tw = max(1, text_tracked_width(_name, BOSS_NAME_TRACK));

    var _fx = _tx - NAMECARD_NAME_V * _ay;
    var _fy = cutin_y(_g, _tx) + NAMECARD_NAME_V * _ax;
    var _to_x = FIELD_CX;
    var _to_y = BOSS_NAME_Y + _dy;

    var _f = cutin_smooth(_o, NAMECARD_FLY_AT,
                          NAMECARD_LAND_AT - NAMECARD_FLY_AT);
    if (_f < 1) {
        for (var _k = 3; _k >= 0; _k--) {
            // Three fading copies trail it.
            var _q = max(0, _f - _k * 0.035);
            if (_k > 0 && _q <= 0) continue;
            var _x = lerp(_fx, _to_x, _q);
            var _y = lerp(_fy, _to_y, _q) + dsin(_q * 180) * 46;
            var _ang = lerp(CUTIN_TILT, 0, _q);
            var _mix = clamp((_q - 0.1) / 0.6, 0, 1);
            _mix = _mix * _mix * (3 - 2 * _mix);
            var _ghost = (_k == 0) ? 1 : 0.16 / _k;

            if (_k == 0 && _mix < 1) {
                draw_set_font(fnt_title());
                var _cs = lerp(_ns, _tw / _nw, _q);
                var _hx = _nw * _cs * 0.5;
                cutin_draw_gilt_line(_x - _hx * dcos(_ang),
                                     _y + _hx * dsin(_ang), _name, _cs, _ang,
                                     1 - _mix, 0, -1);
            }
            draw_set_font(fnt_ui());
            band_draw_tracked(_x, _y, _name, BOSS_NAME_TRACK,
                              lerp(_nw * _ns / _tw, 1, _q), _ang,
                              COL_GILT_LIT,
                              max(_mix, (_k > 0) ? 1 : 0) * _ghost
                              * lerp(1, _ra, _q), (_k == 0) ? 3 : 0);
        }
    }

    // It lands with a glint.
    var _l = _o - NAMECARD_LAND_AT;
    if (_l >= 0) {
        var _fade = 1 - _l / (NAMECARD_OUT_TIME - NAMECARD_LAND_AT);
        draw_bloom(_to_x, _to_y, 260, _col, 0.6 * _fade * _ra);
        gpu_set_blendmode(bm_add);
        card_draw_glint(_to_x, _to_y, 120 * _fade, c_white, _fade * _ra);
        gpu_set_blendmode(bm_normal);
    }
}
