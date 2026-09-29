/// @desc The stage's title card: the stage's name in gilt over a dark band
///       across the field, played by its timeline (`wave_title_card`).
///
/// The lettering, the rules and the stage label are rendered by
/// `tools/make_titles.py`, one frame per stage (`def.card`); a card with no
/// frame shows nothing. Here they are only revealed and faded: the band opens,
/// the rules draw outward from a star at their centre, the label settles, the
/// name is uncovered from its middle outward behind a bright edge, the
/// subtitle rises into place, a sheen crosses the name, and it all fades
/// while the name lifts. Everything stays inside the field.

// Frames, from the start.
#macro CARD_TIME 290
#macro CARD_OUT 236                // when it starts to leave
#macro CARD_BAND_IN 28             // the band opening
#macro CARD_RULE_AT 10             // the rules begin to draw, from a star
#macro CARD_RULE_LEN 40
#macro CARD_LABEL_AT 20
#macro CARD_NAME_AT 30             // the name is uncovered over...
#macro CARD_NAME_LEN 46            // ...this many frames
#macro CARD_SUB_AT 66
#macro CARD_SHEEN_AT 112
#macro CARD_SHEEN_LEN 58

// Where it sits: the name's middle, a third of the way down the field.
#macro CARD_Y (FIELD_Y0 + FIELD_H * 0.34)
#macro CARD_BAND_H 370             // the band's full height
#macro CARD_LABEL_DY -118          // the label, above the rule above the name
#macro CARD_RULE_DY -76
#macro CARD_RULE2_DY 66            // the rule below it
#macro CARD_SUB_DY 108             // the subtitle, below that

// How soft the uncovering edge is: slices, and each slice's width.
#macro CARD_EDGE_SLICES 10
#macro CARD_EDGE_W 7

/// @desc An idle card. One per run.
function title_card_new() {
    return { t: -1, frame: 0 };
}

/// @desc Play the card for a stage def (nothing, for a def without one).
function title_card_start(_c, _def) {
    var _f = _def[$ "card"];
    if (_f == undefined || _f < 0
        || _f >= sprite_get_number(spr_card_title)) {
        return;
    }
    _c.frame = _f;
    _c.t = 0;
}

/// @desc A timeline event: play the stage's title card now.
function wave_title_card() {
    return function(_g) {
        var _c = _g[$ "title"];
        if (_c != undefined) title_card_start(_c, _g.def);
    };
}

function title_card_live(_c) {
    return _c.t >= 0;
}

function title_card_step(_c) {
    if (_c.t < 0) return;
    _c.t++;
    if (_c.t >= CARD_TIME) _c.t = -1;
}

/// @desc 0 to 1 over `_len` frames from `_at`, eased out.
function card_ramp(_t, _at, _len) {
    var _f = clamp((_t - _at) / max(1, _len), 0, 1);
    return 1 - (1 - _f) * (1 - _f) * (1 - _f);
}

/// @desc Draw it (GUI layer, after the field's frame).
function title_card_draw(_c) {
    if (_c.t < 0) return;
    var _t = _c.t;
    var _fr = _c.frame;

    // Leaving: everything fades together.
    var _out = clamp((_t - CARD_OUT) / (CARD_TIME - CARD_OUT), 0, 1);
    var _keep = 1 - _out * _out * (3 - 2 * _out);
    var _cy = CARD_Y;

    // ---- the band ------------------------------------------------------
    var _open = card_ramp(_t, 0, CARD_BAND_IN) * (1 - _out * 0.55);
    card_draw_band(_cy, CARD_BAND_H * (0.35 + 0.65 * _open), 0.66 * _open * _keep);

    // Motes drifting up through it.
    card_draw_motes(_cy, _t, _open * _keep);

    // ---- the rules, drawn outward from a star ---------------------------
    var _rw = card_ramp(_t, CARD_RULE_AT, CARD_RULE_LEN);
    card_draw_reveal(spr_card_rule, 0, FIELD_CX, _cy + CARD_RULE_DY, _rw,
                     _keep, 1, false);
    card_draw_reveal(spr_card_rule, 1, FIELD_CX, _cy + CARD_RULE2_DY, _rw,
                     _keep * 0.85, 1, false);
    // The star where they start, flaring and settling.
    if (_t >= CARD_RULE_AT) {
        var _sf = clamp((_t - CARD_RULE_AT) / 30, 0, 1);
        var _flare = (1 - _sf) * (1 - _sf);
        card_draw_star(FIELD_CX, _cy + CARD_RULE_DY,
                       34 + 150 * _flare, (0.35 + 0.65 * _flare) * _keep);
    }

    // ---- the stage label -----------------------------------------------
    var _la = card_ramp(_t, CARD_LABEL_AT, 26);
    if (_la > 0) {
        var _lx = 1 + 0.22 * (1 - _la);
        var _lw = sprite_get_width(spr_card_label) * _lx;
        draw_sprite_ext(spr_card_label, _fr, FIELD_CX - _lw * 0.5,
                        _cy + CARD_LABEL_DY
                        - sprite_get_height(spr_card_label) * 0.5,
                        _lx, 1, 0, c_white, _la * _keep);
    }

    // ---- the name ------------------------------------------------------
    var _nw = card_ramp(_t, CARD_NAME_AT, CARD_NAME_LEN);
    var _lift = 10 * _out;
    var _ns = 1 + 0.015 * _out + 0.03 * (1 - card_ramp(_t, CARD_NAME_AT, 70));
    card_draw_reveal(spr_card_title, _fr, FIELD_CX, _cy - _lift, _nw, _keep,
                     _ns, true);

    // A sheen across it once it is whole.
    if (_t >= CARD_SHEEN_AT && _t < CARD_SHEEN_AT + CARD_SHEEN_LEN) {
        var _sp = (_t - CARD_SHEEN_AT) / CARD_SHEEN_LEN;
        card_draw_sheen(_fr, FIELD_CX, _cy - _lift, _ns, _sp, _keep);
    }

    // ---- the subtitle --------------------------------------------------
    var _sa = card_ramp(_t, CARD_SUB_AT, 34);
    if (_sa > 0) {
        var _sw = sprite_get_width(spr_card_sub);
        var _sh = sprite_get_height(spr_card_sub);
        draw_sprite_ext(spr_card_sub, _fr, FIELD_CX - _sw * 0.5,
                        _cy + CARD_SUB_DY - _sh * 0.5 + 14 * (1 - _sa),
                        1, 1, 0, c_white, _sa * _keep);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The band the card sits on: indigo darkening the field, softest at
///       its top and bottom and at the field's sides. Inside the field only.
function card_draw_band(_cy, _h, _alpha) {
    if (_alpha <= 0.004) return;
    var _deep = merge_colour(COL_VOID, COL_ARCANE, 0.55);
    // Rows top to bottom, each strip fading at both ends of the field.
    var _rows = 12;
    var _cols = [0, 0.14, 0.5, 0.86, 1];
    var _ca = [0, 1, 1, 1, 0];
    for (var _r = 0; _r < _rows; _r++) {
        var _v0 = _r / _rows;
        var _v1 = (_r + 1) / _rows;
        var _a0 = card_band_profile(_v0) * _alpha;
        var _a1 = card_band_profile(_v1) * _alpha;
        var _y0 = _cy - _h * 0.5 + _h * _v0;
        var _y1 = _cy - _h * 0.5 + _h * _v1;
        draw_primitive_begin(pr_trianglestrip);
        for (var _k = 0; _k < array_length(_cols); _k++) {
            var _x = FIELD_X0 + FIELD_W * _cols[_k];
            draw_vertex_colour(_x, _y0, _deep, _a0 * _ca[_k]);
            draw_vertex_colour(_x, _y1, _deep, _a1 * _ca[_k]);
        }
        draw_primitive_end();
    }

    // Two hairlines of gilt, just inside its edges, fading toward the sides.
    gpu_set_blendmode(bm_add);
    for (var _s = -1; _s <= 1; _s += 2) {
        var _y = _cy + _s * _h * 0.44;
        draw_primitive_begin(pr_trianglestrip);
        for (var _k = 0; _k < array_length(_cols); _k++) {
            var _x = FIELD_X0 + FIELD_W * _cols[_k];
            var _a = _alpha * 0.30 * _ca[_k] * (0.4 + 0.6 * (1 - abs(_cols[_k] - 0.5) * 2));
            draw_vertex_colour(_x, _y - 0.8, COL_GILT, _a);
            draw_vertex_colour(_x, _y + 0.8, COL_GILT, _a);
        }
        draw_primitive_end();
    }
    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
}

/// @desc How dark the band is `_v` of the way down it: solid through the
///       middle, eased to nothing at both edges.
function card_band_profile(_v) {
    var _e = min(_v, 1 - _v) / 0.30;
    _e = clamp(_e, 0, 1);
    return _e * _e * (3 - 2 * _e);
}

/// @desc Motes of gold and cyan drifting up through the band. Each is a
///       function of the card's clock, not simulated.
function card_draw_motes(_cy, _t, _alpha) {
    if (_alpha <= 0.01) return;
    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 34; _i++) {
        var _sx = frac(_i * 0.6180339 + 0.13);
        var _rate = 0.0022 + 0.0020 * frac(_i * 0.377);
        var _p = frac(_t * _rate + _i * 0.291);
        var _x = FIELD_X0 + 60 + (FIELD_W - 120) * _sx
                 + dsin(_t * 0.9 + _i * 47) * 12;
        var _y = _cy + CARD_BAND_H * 0.36 - _p * CARD_BAND_H * 0.72;
        // Fainter toward the field's sides, and at both ends of the rise.
        var _edge = 1 - abs(_sx - 0.5) * 1.6;
        var _a = _alpha * max(0, _edge) * sin(_p * pi)
                 * (0.20 + 0.25 * frac(_i * 0.71));
        if (_a <= 0.01) continue;
        var _col = ((_i mod 4) == 0) ? COL_RUNE : COL_GILT_LIT;
        var _k = (6 + 7 * frac(_i * 0.53)) / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _k, _k, 0, _col, _a);
        // A few catch the light as four-pointed glints.
        if ((_i mod 5) == 2) {
            var _tw = max(0, dsin(_t * 5 + _i * 71));
            card_draw_glint(_x, _y, 16 * _tw, _col, _a * _tw * 1.4);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc A four-pointed glint (two crossed streaks). Additive; the caller
///       sets the blend mode.
function card_draw_glint(_x, _y, _arm, _col, _a) {
    if (_a <= 0.01 || _arm <= 0.5) return;
    var _sw = sprite_get_width(spr_fx_spark);
    var _sh = sprite_get_height(spr_fx_spark);
    for (var _k = 0; _k < 2; _k++) {
        draw_sprite_ext(spr_fx_spark, 0, _x, _y, _arm * 2 / _sw, 3 / _sh,
                        _k * 90, _col, _a);
    }
}

/// @desc The star the rules are drawn from: a bloom and a four-pointed
///       flare `_arm` long.
function card_draw_star(_x, _y, _arm, _a) {
    if (_a <= 0.01) return;
    // `draw_bloom` sets and restores its own blend.
    draw_bloom(_x, _y, 40 + _arm * 0.9, COL_GILT_LIT, _a * 0.45);
    gpu_set_blendmode(bm_add);
    var _sw = sprite_get_width(spr_fx_spark);
    var _sh = sprite_get_height(spr_fx_spark);
    for (var _k = 0; _k < 4; _k++) {
        var _len = (_k mod 2 == 0) ? _arm : _arm * 0.45;
        draw_sprite_ext(spr_fx_spark, 0, _x, _y, _len / _sw, 5 / _sh,
                        _k * 90, merge_colour(COL_GILT_LIT, c_white, 0.5), _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Draw frame `_fr` of a card sprite (top-left origin) centred on
///       (`_cx`, `_cy`) at scale `_s`, uncovered from its middle outward:
///       `_f` of its width shows, with a soft edge `CARD_EDGE_SLICES` slices
///       wide. `_lit` adds a bright rim along the uncovering edge (the name's
///       `spr_card_title_lit`).
function card_draw_reveal(_spr, _fr, _cx, _cy, _f, _a, _s, _lit) {
    if (_f <= 0 || _a <= 0.004) return;
    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);
    var _x0 = _cx - _w * _s * 0.5;
    var _y0 = _cy - _h * _s * 0.5;
    var _half = _w * 0.5;
    var _edge = CARD_EDGE_SLICES * CARD_EDGE_W;
    // How far out from the middle the solid part reaches, in sprite pixels;
    // the soft edge runs beyond it, and is gone once it is off the ends.
    var _reach = (_half + _edge) * _f - _edge;

    var _solid = clamp(_reach, 0, _half);
    if (_solid > 0) {
        draw_sprite_part_ext(_spr, _fr, _half - _solid, 0, _solid * 2, _h,
                             _x0 + (_half - _solid) * _s, _y0, _s, _s,
                             c_white, _a);
    }
    // The edge, a slice at a time, fading outward, on both sides.
    for (var _k = 0; _k < CARD_EDGE_SLICES; _k++) {
        var _in = _reach + _k * CARD_EDGE_W;
        if (_in >= _half) break;
        if (_in + CARD_EDGE_W <= 0) continue;
        var _u0 = max(0, _in);
        var _u1 = min(_half, _in + CARD_EDGE_W);
        var _sa = _a * (1 - (_k + 0.5) / CARD_EDGE_SLICES);
        var _sw = _u1 - _u0;
        if (_sw <= 0) continue;
        draw_sprite_part_ext(_spr, _fr, _half + _u0, 0, _sw, _h,
                             _x0 + (_half + _u0) * _s, _y0, _s, _s,
                             c_white, _sa);
        draw_sprite_part_ext(_spr, _fr, _half - _u1, 0, _sw, _h,
                             _x0 + (_half - _u1) * _s, _y0, _s, _s,
                             c_white, _sa);
    }

    // The bright rim riding the edge while it is still moving.
    if (_lit && _f < 1) {
        gpu_set_blendmode(bm_add);
        var _lw = 26;
        for (var _k = 0; _k < 6; _k++) {
            var _in = _reach - _lw * 0.5 + _k * (_lw / 6);
            if (_in < 0 || _in >= _half) continue;
            var _sw = min(_lw / 6, _half - _in);
            var _ga = _a * sin((_k + 0.5) / 6 * pi) * 0.9;
            draw_sprite_part_ext(spr_card_title_lit, _fr, _half + _in, 0, _sw,
                                 _h, _x0 + (_half + _in) * _s, _y0, _s, _s,
                                 c_white, _ga);
            draw_sprite_part_ext(spr_card_title_lit, _fr, _half - _in - _sw, 0,
                                 _sw, _h, _x0 + (_half - _in - _sw) * _s, _y0,
                                 _s, _s, c_white, _ga);
        }
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The sheen crossing the name, `_p` of the way across: the lit
///       lettering added in a soft band leaning like a reflection.
function card_draw_sheen(_fr, _cx, _cy, _s, _p, _a) {
    var _w = sprite_get_width(spr_card_title_lit);
    var _h = sprite_get_height(spr_card_title_lit);
    var _x0 = _cx - _w * _s * 0.5;
    var _y0 = _cy - _h * _s * 0.5;
    var _band = 150;
    var _pos = lerp(-_band, _w + _band, _p);
    var _n = 12;
    // The band is cut in horizontal strips, each shifted, so it leans.
    var _rows = 6;
    gpu_set_blendmode(bm_add);
    for (var _r = 0; _r < _rows; _r++) {
        var _v0 = _h * _r / _rows;
        var _vh = _h / _rows;
        var _shift = (_r - _rows * 0.5) * -14;
        for (var _k = 0; _k < _n; _k++) {
            var _u0 = _pos + _shift - _band * 0.5 + _k * (_band / _n);
            var _u1 = _u0 + _band / _n;
            var _c0 = clamp(_u0, 0, _w);
            var _c1 = clamp(_u1, 0, _w);
            if (_c1 <= _c0) continue;
            var _ga = _a * 0.75 * sqr(sin((_k + 0.5) / _n * pi));
            draw_sprite_part_ext(spr_card_title_lit, _fr, _c0, _v0, _c1 - _c0,
                                 _vh, _x0 + _c0 * _s, _y0 + _v0 * _s, _s, _s,
                                 c_white, _ga);
        }
    }
    gpu_set_blendmode(bm_normal);
}
