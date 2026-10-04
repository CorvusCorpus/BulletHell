/// @desc Drawing helpers: fonts and text, panels and the fascia (the margin
///       around the field), the field's frame, the capsule "vessel" gauges,
///       the boss rail's parts, and counter wheels.

/// @desc Build the sprite fonts. Called once, from `obj_boot`. The glyph
///       string is generated (ASCII 32..126) to match `tools/make_fonts.py`'s
///       frame order.
function ui_init() {
    var _glyphs = "";
    for (var _i = 32; _i <= 126; _i++) {
        _glyphs += chr(_i);
    }

    // `prop = true` spaces glyphs by their ink. (The space glyph carries an
    // invisible bar so it isn't measured as zero width.)
    global.fnt_small = font_add_sprite_ext(spr_fnt_small, _glyphs, true, 1);
    global.fnt_ui    = font_add_sprite_ext(spr_fnt_ui, _glyphs, true, 1);
    global.fnt_talk  = font_add_sprite_ext(spr_fnt_talk, _glyphs, true, 1);
    global.fnt_num   = font_add_sprite_ext(spr_fnt_num, _glyphs, true, 2);
    global.fnt_head  = font_add_sprite_ext(spr_fnt_head, _glyphs, true, 2);
    global.fnt_spell = font_add_sprite_ext(spr_fnt_spell, _glyphs, true, 3);
    global.fnt_title = font_add_sprite_ext(spr_fnt_title, _glyphs, true, 4);

    // True while a clear layer is being drawn (`ui_blend`).
    global.ui_premul = false;
}

// ---------------------------------------------------------------------------
// Cached layers
//
// What the HUD shows that changes only now and then is drawn once into a
// surface, copied to the screen each frame, and drawn again only when what it
// shows changes (its key) or the surface is lost. A layer is drawn in window
// pixels, as the GUI layer itself is (`display_set_gui_size` scales it to the
// window), so a copy lands pixel for pixel and looks as drawing directly
// would at any window size. Two kinds:
//
// - An opaque layer is what is drawn over an opaque ground (the frame's
//   margins, the console's plate). It is drawn over black with alpha writes
//   off, and only the ground's own rectangles are copied (`ui_layer_put_rect`).
// - A clear layer has nothing under it. It is drawn premultiplied, with every
//   blend set through `ui_blend`, so its translucent and additive drawing
//   lands on the screen as it would have directly (`ui_layer_put`).
// ---------------------------------------------------------------------------

/// @desc A layer covering `_w` x `_h` GUI units at (`_x`, `_y`).
function ui_layer_new(_x, _y, _w, _h, _opaque = false) {
    return {
        x: _x, y: _y, w: _w, h: _h, opaque: _opaque,
        surf: -1,
        key: undefined, src: undefined,
        // Window pixels per GUI unit, and the window pixel its surface's
        // corner lands on; worked out when it is drawn.
        kx: 1, ky: 1, ox: 0, oy: 0,
        // What `ui_layer_end` puts back.
        was_premul: false, was_world: undefined,
    };
}

/// @desc Free a layer's surface (from its owner's Clean Up).
function ui_layer_free(_l) {
    if (surface_exists(_l.surf)) surface_free(_l.surf);
    _l.surf = -1;
    _l.key = undefined;
}

/// @desc Window pixels per GUI unit, across and down, read from the view the
///       GUI event draws with (the window's own size can be a pixel off the
///       buffer drawn into, and is 0 while minimised). 1 outside it.
function ui_gui_scale_x() {
    var _k = matrix_get(matrix_view)[0];
    return (_k > 0) ? _k : 1;
}

function ui_gui_scale_y() {
    var _k = matrix_get(matrix_view)[5];
    return (_k > 0) ? _k : 1;
}

/// @desc Start drawing into `_l` if it needs it, and answer whether it does:
///       its surface was lost, the window changed size, or `_key` (compared
///       with `==`) or `_src` (compared by reference) differ from what it
///       holds. When it answers true, draw in GUI coordinates and close with
///       `ui_layer_end`.
function ui_layer_begin(_l, _key = 0, _src = undefined) {
    if (surface_exists(_l.surf) && _l.key == _key && _l.src == _src
        && _l.kx == ui_gui_scale_x() && _l.ky == ui_gui_scale_y()) {
        return false;
    }
    _l.key = _key;
    _l.src = _src;
    ui_layer_open(_l);
    return true;
}

/// @desc Start drawing into `_l` whatever it holds (for a layer redrawn every
///       frame, such as the boss's rail). Close with `ui_layer_end`.
function ui_layer_open(_l) {
    var _kx = ui_gui_scale_x();
    var _ky = ui_gui_scale_y();
    _l.kx = _kx;
    _l.ky = _ky;
    _l.ox = floor(_l.x * _kx);
    _l.oy = floor(_l.y * _ky);
    var _sw = max(1, ceil((_l.x + _l.w) * _kx) - _l.ox);
    var _sh = max(1, ceil((_l.y + _l.h) * _ky) - _l.oy);
    if (surface_exists(_l.surf)
        && (surface_get_width(_l.surf) != _sw
            || surface_get_height(_l.surf) != _sh)) {
        surface_free(_l.surf);
    }
    if (!surface_exists(_l.surf)) _l.surf = surface_create(_sw, _sh);

    _l.was_world = matrix_get(matrix_world);
    surface_set_target(_l.surf);
    // GUI units to this surface's pixels, as the GUI layer maps them to the
    // window's.
    matrix_set(matrix_world,
               matrix_build(-_l.ox, -_l.oy, 0, 0, 0, 0, _kx, _ky, 1));
    _l.was_premul = global.ui_premul;
    if (_l.opaque) {
        draw_clear_alpha(c_black, 1);
        gpu_set_colorwriteenable(true, true, true, false);
        global.ui_premul = false;
    } else {
        draw_clear_alpha(c_black, 0);
        global.ui_premul = true;
    }
    ui_blend(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc Finish drawing into `_l`, and put the draw state back as it was.
function ui_layer_end(_l) {
    gpu_set_colorwriteenable(true, true, true, true);
    global.ui_premul = _l.was_premul;
    ui_blend(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
    matrix_set(matrix_world, _l.was_world);
    surface_reset_target();
}

/// @desc Copy a clear layer where it belongs, `_dy` GUI units lower (a whole
///       number of window pixels; see `ui_snap_dy`), at `_alpha`. Onto the
///       screen or into another clear layer alike.
function ui_layer_put(_l, _alpha = 1, _dy = 0) {
    if (!surface_exists(_l.surf) || _alpha <= 0.004) return;
    // Premultiplied: the colour carries the alpha too.
    var _v = clamp(floor(255 * _alpha + 0.5), 0, 255);
    gpu_set_blendmode_ext(bm_one, bm_inv_src_alpha);
    draw_surface_ext(_l.surf, _l.ox / _l.kx, _l.oy / _l.ky + _dy,
                     1 / _l.kx, 1 / _l.ky, 0, make_colour_rgb(_v, _v, _v),
                     _alpha);
    ui_blend(bm_normal);
}

/// @desc Copy the part of an opaque layer under the GUI rectangle (`_x1`,
///       `_y1`)-(`_x2`, `_y2`): exactly the window pixels a fill of that
///       rectangle would cover.
function ui_layer_put_rect(_l, _x1, _y1, _x2, _y2) {
    if (!surface_exists(_l.surf)) return;
    var _px1 = ceil(_x1 * _l.kx - 0.5);
    var _py1 = ceil(_y1 * _l.ky - 0.5);
    var _px2 = ceil(_x2 * _l.kx - 0.5);
    var _py2 = ceil(_y2 * _l.ky - 0.5);
    if (_px2 <= _px1 || _py2 <= _py1) return;
    draw_surface_part_ext(_l.surf, _px1 - _l.ox, _py1 - _l.oy, _px2 - _px1,
                          _py2 - _py1, _px1 / _l.kx, _py1 / _l.ky,
                          1 / _l.kx, 1 / _l.ky, c_white, 1);
}

/// @desc A vertical offset rounded to whole window pixels, so a layer drawn
///       at rest and put `_dy` lower lines up with what is drawn live at the
///       same offset.
function ui_snap_dy(_dy) {
    var _ky = ui_gui_scale_y();
    return floor(_dy * _ky + 0.5) / _ky;
}

/// @desc Set the blend mode. Inside a clear layer, the premultiplied form of
///       it: colour weighted by its alpha, and alpha laid over the layer's
///       (or for `bm_add`, colour added and the layer's alpha left alone).
///       Everything a clear layer draws sets its blend through this.
function ui_blend(_mode) {
    if (!global.ui_premul) {
        gpu_set_blendmode(_mode);
        return;
    }
    if (_mode == bm_add) {
        gpu_set_blendmode_ext_sepalpha(bm_src_alpha, bm_one, bm_zero, bm_one);
    } else {
        gpu_set_blendmode_ext_sepalpha(bm_src_alpha, bm_inv_src_alpha,
                                       bm_one, bm_inv_src_alpha);
    }
}

// Font accessors. Call them: `draw_set_font(fnt_ui())`, not `fnt_ui`
// (`check_font_accessors_called`).
function fnt_small()  { return global.fnt_small; }
function fnt_ui()     { return global.fnt_ui; }
function fnt_talk()   { return global.fnt_talk; }
function fnt_num()    { return global.fnt_num; }
function fnt_head()   { return global.fnt_head; }
function fnt_spell()  { return global.fnt_spell; }
function fnt_title()  { return global.fnt_title; }

/// @desc Set font, colour and alpha in one call.
function text_style(_font, _col, _alpha = 1) {
    draw_set_font(_font);
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
}

/// @desc How tall a line's ink is. `string_height` on a sprite font returns
///       the atlas cell, which is much taller than the letters;
///       `FONT_INK_RATIO` corrects it (`check_font_ink_ratio` re-derives it).
function text_ink_height(_str) {
    return string_height(_str) * FONT_INK_RATIO;
}

/// @desc The y to draw at with `fa_bottom` so the current font's baseline is
///       on `_baseline`. Use this to put different font sizes on one baseline
///       (`fa_middle` centres the whole cell, including descender space).
function text_baseline_y(_baseline, _scale = 1) {
    return _baseline + string_height("0") * FONT_BASELINE_DROP * _scale;
}

/// @desc The y to draw at with `fa_bottom` so a line of capitals is centred
///       on `_cy`. (`fa_middle` centres the cell, which leaves capitals sitting
///       high by half the descender space; noticeable inside a frame.)
function text_cap_middle_y(_cy, _scale = 1) {
    var _cell = string_height("H") * _scale;
    return _cy + _cell * (FONT_INK_RATIO * 0.5 + FONT_BASELINE_DROP);
}

/// @desc Text with a hard dark outline, so it reads over any background.
///       Restores alpha and colour afterwards; leaving them set leaks into
///       the next event's drawing (this once faded the stage background out
///       under the stage-name splash). `text_style` is the deliberate
///       exception, since setting state is its job.
function draw_text_outline(_x, _y, _str, _col, _alpha = 1, _thick = 2,
                           _outline = c_black) {
    draw_set_colour(_outline);
    draw_set_alpha(_alpha * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text(_x + lengthdir_x(_thick, _i * 45),
                  _y + lengthdir_y(_thick, _i * 45), _str);
    }
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    draw_text(_x, _y, _str);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The same, scaled -- for anything that arrives at size and settles.
function draw_text_outline_scaled(_x, _y, _str, _col, _alpha, _scale,
                                  _thick = 2, _outline = c_black) {
    draw_set_colour(_outline);
    draw_set_alpha(_alpha * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text_transformed(_x + lengthdir_x(_thick, _i * 45),
                              _y + lengthdir_y(_thick, _i * 45), _str,
                              _scale, _scale, 0);
    }
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    draw_text_transformed(_x, _y, _str, _scale, _scale, 0);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc Text shrunk to fit `_max_w`, never grown. Returns the scale used.
function draw_text_fit(_x, _y, _str, _max_w, _col, _alpha = 1, _thick = 2,
                      _extra = 1) {
    var _w = string_width(_str);
    var _s = (_w > _max_w && _w > 0) ? (_max_w / _w) : 1;
    // `_extra` multiplies the fitted scale (for text animating in oversized).
    draw_text_outline_scaled(_x, _y, _str, _col, _alpha, _s * _extra, _thick);
    return _s;
}

/// @desc Text with extra letter spacing (`_track` px), drawn a glyph at a
///       time since sprite fonts have no tracking. Used for console tags.
///       `_halign` is applied by measuring the run first. Returns its width.
function draw_text_tracked(_x, _y, _str, _track, _col, _alpha = 1, _thick = 2,
                           _halign = fa_left) {
    var _n = string_length(_str);
    if (_n <= 0) return 0;

    var _w = text_tracked_width(_str, _track);

    var _cx = _x;
    if (_halign == fa_center) _cx -= _w * 0.5;
    else if (_halign == fa_right) _cx -= _w;

    draw_set_halign(fa_left);
    for (var _i = 1; _i <= _n; _i++) {
        var _ch = string_char_at(_str, _i);
        draw_text_outline(_cx, _y, _ch, _col, _alpha, _thick);
        _cx += string_width(_ch) + _track;
    }
    return _w;
}

// ---------------------------------------------------------------------------
// Furniture
// ---------------------------------------------------------------------------

/// @desc A dark panel with a coloured edge.
function draw_panel(_x1, _y1, _x2, _y2, _col, _alpha, _edge = 2) {
    draw_set_alpha(_alpha * 0.72);
    draw_set_colour(COL_VOID);
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    draw_set_alpha(_alpha * 0.9);
    draw_set_colour(_col);
    for (var _i = 0; _i < _edge; _i++) {
        draw_rectangle(_x1 + _i, _y1 + _i, _x2 - _i, _y2 - _i, true);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A number, right-aligned, with an outline, zero-padded to `_pad`.
function draw_number(_x, _y, _n, _font, _col, _alpha, _pad = 0) {
    var _s = string(_n);
    while (string_length(_s) < _pad) _s = "0" + _s;
    draw_set_font(_font);
    draw_set_halign(fa_right);
    draw_set_valign(fa_middle);
    draw_text_outline(_x, _y, _s, _col, _alpha);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc A translucent full-screen scrim (pause, results, the rack's indigo
///       wash).
function draw_scrim(_alpha, _col = c_black) {
    draw_set_alpha(_alpha);
    draw_set_colour(_col);
    draw_rectangle(0, 0, GAME_W, GAME_H, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The fascia: the opaque margin round the field, drawn as an indigo plate
// lit from above (one vertical ramp over the screen's height, so all four
// margin pieces match) with grain and drifting motes over it.
// ---------------------------------------------------------------------------

/// @desc The fascia colour at screen height `_y`: `COL_ARCANE` (indigo) darkening
///       toward `COL_VOID` down the screen. Kept low in brightness so the
///       margin doesn't pull the eye off the field.
function fascia_shade(_y) {
    var _t = clamp(_y / GAME_H, 0, 1);
    return merge_colour(merge_colour(COL_VOID, COL_ARCANE, 0.72), COL_VOID,
                        _t * _t * 0.62 + _t * 0.28);
}

/// @desc One rectangle of fascia: the ramp, the grain over it, and its
///       motes.
function draw_fascia(_x1, _y1, _x2, _y2) {
    if (_x2 <= _x1 || _y2 <= _y1) return;
    draw_fascia_ground(_x1, _y1, _x2, _y2);
    fascia_motes(_x1, _y1, _x2, _y2);
}

/// @desc A rectangle of fascia's ramp and grain, which never change (the
///       field's frame keeps them in a layer).
function draw_fascia_ground(_x1, _y1, _x2, _y2) {
    if (_x2 <= _x1 || _y2 <= _y1) return;

    draw_primitive_begin(pr_trianglestrip);
    var _steps = 8;
    for (var _i = 0; _i <= _steps; _i++) {
        var _y = lerp(_y1, _y2, _i / _steps);
        var _c = fascia_shade(_y);
        draw_vertex_colour(_x1, _y, _c, 1);
        draw_vertex_colour(_x2, _y, _c, 1);
    }
    draw_primitive_end();

    draw_grain(_x1, _y1, _x2, _y2, merge_colour(COL_PARCHMENT, COL_RUNE, 0.4),
               0.075);
}

/// @desc Faint motes drifting up through a fascia rectangle. Positions are
///       derived from the clock (a phase and a rate each), not simulated.
function fascia_motes(_x1, _y1, _x2, _y2) {
    var _w = _x2 - _x1;
    var _h = _y2 - _y1;
    if (_w < 8 || _h < 8) return;

    ui_blend(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 18; _i++) {
        // Seeded off the rectangle so each piece of margin carries its own
        // drift, and off `_i` so no two are in step.
        var _sx = frac(_i * 0.6180339 + _x1 * 0.0013 + _y1 * 0.0007);
        var _p = frac(current_time * (0.000018 + 0.000022 * frac(_i * 0.41))
                      + _i * 0.137 + _sx);
        var _mx = _x1 + _w * _sx;
        var _my = _y2 - _p * (_h + 40) + 20;
        var _a = min(1, _p * 5) * min(1, (1 - _p) * 5)
                 * (0.05 + 0.05 * frac(_i * 0.77));
        var _k = (5 + 5 * frac(_i * 0.31)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _mx, _my, _k, _k, 0,
                        (_i mod 3 == 0) ? COL_RUNE : COL_GILT_LIT, _a);
    }
    ui_blend(bm_normal);
}

/// @desc `spr_ui_grain` tiled over a rectangle, additively, cropping the edge
///       tiles with `draw_sprite_part_ext` (there is no clipping).
function draw_grain(_x1, _y1, _x2, _y2, _col, _alpha) {
    if (_alpha <= 0.004) return;
    var _tw = sprite_get_width(spr_ui_grain);
    var _th = sprite_get_height(spr_ui_grain);

    ui_blend(bm_add);
    // Phased off the screen origin so the tiling lines up across rectangles.
    var _sy = _y1 - (_y1 mod _th);
    while (_sy < _y2) {
        var _sx = _x1 - (_x1 mod _tw);
        var _cy = max(_y1, _sy);
        var _ch = min(_y2, _sy + _th) - _cy;
        while (_sx < _x2) {
            var _cx = max(_x1, _sx);
            var _cw = min(_x2, _sx + _tw) - _cx;
            if (_cw > 0 && _ch > 0) {
                draw_sprite_part_ext(spr_ui_grain, 0, _cx - _sx, _cy - _sy,
                                     _cw, _ch, _cx, _cy, 1, 1, _col, _alpha);
            }
            _sx += _tw;
        }
        _sy += _th;
    }
    ui_blend(bm_normal);
}

/// @desc The four corner ornaments of a rectangle: one sprite, flipped.
///       `_out` pushes them outward from the rectangle.
function draw_corners(_x1, _y1, _x2, _y2, _col, _alpha, _out = 0, _scale = 1) {
    if (_alpha <= 0.004) return;
    var _s = _scale;
    for (var _i = 0; _i < 4; _i++) {
        var _fx = (_i == 1 || _i == 3) ? -1 : 1;
        var _fy = (_i >= 2) ? -1 : 1;
        var _px = (_fx > 0) ? (_x1 - _out) : (_x2 + _out);
        var _py = (_fy > 0) ? (_y1 - _out) : (_y2 + _out);
        draw_sprite_ext(spr_ui_corner, 0, _px, _py, _s * _fx, _s * _fy, 0,
                        _col, _alpha);
    }
}

/// @desc A section divider, centred on `_x` and stretched to `_w`.
///       `spr_ui_rule` has a top-left origin, so half the width is subtracted
///       here.
function draw_rule(_x, _y, _w, _col, _alpha) {
    if (_alpha <= 0.004) return;
    var _sw = sprite_get_width(spr_ui_rule);
    var _sh = sprite_get_height(spr_ui_rule);
    draw_sprite_ext(spr_ui_rule, 0, _x - _w * 0.5, _y - _sh / 2,
                    _w / _sw, 1, 0, _col, _alpha);
}

/// @desc A raised plate (what the console is mounted on): a ground a little
///       lighter than the fascia, grain, a gilt top/left edge and a dark
///       bottom/right edge.
function draw_plate(_x1, _y1, _x2, _y2, _alpha = 1) {
    draw_primitive_begin(pr_trianglestrip);
    var _steps = 8;
    for (var _i = 0; _i <= _steps; _i++) {
        var _y = lerp(_y1, _y2, _i / _steps);
        // A little lighter than the fascia at every height.
        var _c = merge_colour(fascia_shade(_y), COL_ARCANE_LIT, 0.10);
        draw_vertex_colour(_x1, _y, _c, _alpha);
        draw_vertex_colour(_x2, _y, _c, _alpha);
    }
    draw_primitive_end();

    draw_grain(_x1, _y1, _x2, _y2,
               merge_colour(COL_PARCHMENT, COL_RUNE, 0.4), 0.06 * _alpha);

    // The bevel: gilt hairlines top and left, dark bottom and right.
    draw_set_alpha(_alpha * 0.5);
    draw_set_colour(COL_GILT);
    draw_rectangle(_x1, _y1, _x2, _y1 + 1, false);
    draw_rectangle(_x1, _y1, _x1 + 1, _y2, false);
    draw_set_alpha(_alpha * 0.2);
    draw_rectangle(_x1 + 3, _y1 + 3, _x2 - 3, _y2 - 3, true);
    draw_set_alpha(_alpha * 0.6);
    draw_set_colour(COL_VOID);
    draw_rectangle(_x1, _y2 - 1, _x2, _y2, false);
    draw_rectangle(_x2 - 1, _y1, _x2, _y2, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The field's boundary
// ---------------------------------------------------------------------------

/// @desc The layer `field_draw_frame` keeps the margins' ground in: the
///       whole screen, opaque.
function field_frame_layer() {
    return ui_layer_new(0, 0, GAME_W, GAME_H, true);
}

/// @desc Paint the four margins opaque (masking the world, which is drawn
///       across the whole screen) and draw the frame round the field: an
///       inner glow, the gilt rules, and the corner ornaments. Called from the
///       GUI event, which has no shake matrix, so the mask never moves.
///       `_flash` lights the frame in `_flash_col` (the damage flash).
///       `_layer`, if given (`field_frame_layer`), keeps the margins' ramp and
///       grain, which never change; their motes are drawn each frame.
function field_draw_frame(_flash = 0, _flash_col = COL_LIFE,
                          _layer = undefined) {
    // The margins (opaque): above, below, left and right.
    static _m = [[0, 0, GAME_W, FIELD_Y0 - 1],
                 [0, FIELD_Y1 + 1, GAME_W, GAME_H],
                 [0, FIELD_Y0 - 1, FIELD_X0 - 1, FIELD_Y1 + 1],
                 [FIELD_X1 + 1, FIELD_Y0 - 1, GAME_W, FIELD_Y1 + 1]];
    if (_layer == undefined) {
        for (var _i = 0; _i < 4; _i++) {
            draw_fascia(_m[_i][0], _m[_i][1], _m[_i][2], _m[_i][3]);
        }
    } else {
        if (ui_layer_begin(_layer)) {
            for (var _i = 0; _i < 4; _i++) {
                draw_fascia_ground(_m[_i][0], _m[_i][1], _m[_i][2], _m[_i][3]);
            }
            ui_layer_end(_layer);
        }
        // Each margin's motes straight after its ground, as `draw_fascia`
        // has them.
        for (var _i = 0; _i < 4; _i++) {
            ui_layer_put_rect(_layer, _m[_i][0], _m[_i][1], _m[_i][2],
                              _m[_i][3]);
            fascia_motes(_m[_i][0], _m[_i][1], _m[_i][2], _m[_i][3]);
        }
    }

    // A faint glow inward from each field edge, drawn as a gradient strip.
    ui_blend(bm_add);
    var _g = merge_colour(COL_RUNE, COL_ARCANE_LIT, 0.45);
    field_edge_glow(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y0 + FIELD_GLOW,
                    _g, true);     // from the top edge, downward
    field_edge_glow(FIELD_X0, FIELD_Y1, FIELD_X1, FIELD_Y1 - FIELD_GLOW,
                    _g, true);
    field_edge_glow(FIELD_X0, FIELD_Y0, FIELD_X0 + FIELD_GLOW, FIELD_Y1,
                    _g, false);
    field_edge_glow(FIELD_X1, FIELD_Y0, FIELD_X1 - FIELD_GLOW, FIELD_Y1,
                    _g, false);
    ui_blend(bm_normal);

    // The rule: a bright hairline at the field edge and dimmer lines outside
    // it.
    draw_set_alpha(0.9);
    draw_set_colour(COL_GILT_LIT);
    draw_rectangle(FIELD_X0 - 1, FIELD_Y0 - 1, FIELD_X1 + 1, FIELD_Y1 + 1,
                   true);
    draw_set_alpha(0.5);
    draw_set_colour(COL_GILT);
    for (var _i = 2; _i < 2 + FIELD_EDGE; _i++) {
        draw_rectangle(FIELD_X0 - _i, FIELD_Y0 - _i, FIELD_X1 + _i,
                       FIELD_Y1 + _i, true);
    }

    // The outer rule, at `FIELD_RULE_OUT` (derived from where the corner
    // ornaments sit, so it meets them).
    var _orn = COL_GILT;
    draw_set_alpha(0.55);
    draw_set_colour(_orn);
    draw_rectangle(FIELD_X0 - FIELD_RULE_OUT, FIELD_Y0 - FIELD_RULE_OUT,
                   FIELD_X1 + FIELD_RULE_OUT, FIELD_Y1 + FIELD_RULE_OUT, true);

    // The corner ornaments, in the margin.
    draw_corners(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, _orn, 0.95,
                 FIELD_ORN_OUT, FIELD_ORN_SCALE);

    // Damage flash: several fading rules spreading outward, and the corners.
    if (_flash > 0.01) {
        ui_blend(bm_add);
        draw_set_colour(_flash_col);
        for (var _i = 0; _i < 7; _i++) {
            draw_set_alpha(_flash * 0.5 * (1 - _i / 7));
            draw_rectangle(FIELD_X0 - 1 - _i, FIELD_Y0 - 1 - _i,
                           FIELD_X1 + 1 + _i, FIELD_Y1 + 1 + _i, true);
        }
        ui_blend(bm_normal);
        draw_corners(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1,
                     _flash_col, _flash * 0.7, 14, 0.62);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc One edge's worth of spill: a strip fading from the boundary inward.
///       `_vertical` means the gradient runs down y rather than across x.
function field_edge_glow(_x0, _y0, _x1, _y1, _col, _vertical) {
    draw_primitive_begin(pr_trianglestrip);
    if (_vertical) {
        draw_vertex_colour(_x0, _y0, _col, 0.16);
        draw_vertex_colour(_x1, _y0, _col, 0.16);
        draw_vertex_colour(_x0, _y1, _col, 0);
        draw_vertex_colour(_x1, _y1, _col, 0);
    } else {
        draw_vertex_colour(_x0, _y0, _col, 0.16);
        draw_vertex_colour(_x0, _y1, _col, 0.16);
        draw_vertex_colour(_x1, _y0, _col, 0);
        draw_vertex_colour(_x1, _y1, _col, 0);
    }
    draw_primitive_end();
}

/// @desc Is this rectangle entirely outside the field? (`test_hud_layout`)
function rect_clear_of_field(_x1, _y1, _x2, _y2) {
    return (_x2 <= FIELD_X0) || (_x1 >= FIELD_X1)
        || (_y2 <= FIELD_Y0) || (_y1 >= FIELD_Y1);
}

// ---------------------------------------------------------------------------
// Vessels: the capsule-shaped liquid gauges (`draw_gauge_h`), used for life,
// sigil and the boss's health. Adapted from the Wordsearch project's gauges.
//
// Every part (trough, liquid, rim, gloss) is drawn from one capsule contour
// (`capsule_half`, `capsule_ring`) so the parts line up exactly.
// `draw_roundrect_ext` is not used: it silently clamps its radius (asked for
// 26 on a 52px tube it draws about 12), so its corners wouldn't match.
// ---------------------------------------------------------------------------

/// @desc How far the inside of a capsule reaches above and below its centre
///       line at `_x`. Zero outside it.
function capsule_half(_x, _lo, _hi, _r) {
    var _c0 = _lo + _r;
    var _c1 = _hi - _r;
    if (_c1 < _c0) {
        // A capsule shorter than it is tall: the two arcs are all there is.
        var _m = (_lo + _hi) * 0.5;
        _c0 = _m;
        _c1 = _m;
    }
    var _d = 0;
    if (_x < _c0) _d = _c0 - _x;
    else if (_x > _c1) _d = _x - _c1;
    if (_d >= _r) return 0;
    return sqrt(_r * _r - _d * _d);
}

/// @desc The rightmost x the inside of a capsule reaches at `_dy` off its
///       centre line. The same contour read the other way round, for the
///       wavy end, which is sampled down y rather than along x.
function capsule_reach(_dy, _hi, _r) {
    var _a = _r * _r - _dy * _dy;
    return (_hi - _r) + ((_a > 0) ? sqrt(_a) : 0);
}

/// @desc Sample positions along a capsule from `_lo` to `_to`: every
///       `LIQ_CAP_STEP` px within a radius of either end, and coarser
///       (`LIQ_BODY_STEPS` across) along the straight middle. Returned as an
///       array so several strips can share the same edge.
function capsule_samples(_lo, _hi, _r, _to) {
    var _out = [];
    var _step = max(2, (_to - _lo) / LIQ_BODY_STEPS);
    var _px = _lo;
    while (true) {
        array_push(_out, _px);
        if (_px >= _to - 0.001) break;
        var _in_cap = (_px < _lo + _r) || (_px > _hi - _r - 1);
        _px = min(_to, _px + (_in_cap ? LIQ_CAP_STEP : _step));
    }
    return _out;
}

/// @desc A filled capsule, from its own contour.
function capsule_fill(_x, _y, _w, _h, _col, _alpha) {
    var _r  = _h * 0.5;
    var _lo = _x;
    var _hi = _x + _w;
    var _cy = _y + _r;
    var _xs = capsule_samples(_lo, _hi, _r, _hi);
    var _n  = array_length(_xs);

    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i < _n; _i++) {
        var _px = _xs[_i];
        var _hh = capsule_half(_px, _lo, _hi, _r);
        draw_vertex_colour(_px, _cy - _hh, _col, _alpha);
        draw_vertex_colour(_px, _cy + _hh, _col, _alpha);
    }
    draw_primitive_end();
}

/// @desc A capsule outline: the ring between radii `_ro` and `_ri` around cap
///       centres `_cx0` and `_cx1` (an inset stadium keeps the same cap
///       centres with a smaller radius).
function capsule_ring(_cx0, _cx1, _cy, _ro, _ri, _col, _alpha, _steps = 12) {
    if (_alpha <= 0.004 || _ro <= 0) return;
    draw_primitive_begin(pr_trianglestrip);
    for (var _half = 0; _half < 2; _half++) {
        var _cx = (_half == 0) ? _cx1 : _cx0;
        var _a0 = (_half == 0) ? -90 : 90;
        for (var _i = 0; _i <= _steps; _i++) {
            var _a = _a0 + (_i * 180 / _steps);
            var _dx = dcos(_a);
            var _dy = -dsin(_a);
            draw_vertex_colour(_cx + _dx * _ro, _cy + _dy * _ro, _col, _alpha);
            draw_vertex_colour(_cx + _dx * _ri, _cy + _dy * _ri, _col, _alpha);
        }
    }
    // Close onto the start point, the bottom of the right cap (the walk goes
    // -90..90 round the right cap, then 90..270 round the left). Closing onto
    // the top instead draws a diagonal band across the vessel.
    draw_vertex_colour(_cx1, _cy + _ro, _col, _alpha);
    draw_vertex_colour(_cx1, _cy + _ri, _col, _alpha);
    draw_primitive_end();
}

/// @desc How far the liquid surface is displaced at `_along` px: two sine
///       waves at unrelated frequencies moving in opposite directions,
///       amplified by `_slosh`.
function liquid_wave(_along, _seed, _slosh = 0) {
    var _a = 1 + _slosh * 2.2;
    return dsin(_along * LIQ_WAVE_K1 + current_time * LIQ_WAVE_S1 + _seed)
           * LIQ_WAVE_A1 * _a
         + dsin(_along * LIQ_WAVE_K2 + current_time * LIQ_WAVE_S2
                + _seed * 137) * LIQ_WAVE_A2 * _a;
}

/// @desc A soft round light. Every glow in the HUD goes through this, so the
///       one sprite is scaled in one place.
function draw_bloom(_x, _y, _size, _col, _alpha) {
    if (_alpha <= 0.004) return;
    ui_blend(bm_add);
    var _s = _size / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0, _col, _alpha);
    ui_blend(bm_normal);
}

/// @desc An arc drawn as a band, with alpha interpolated from `_a_from` to
///       `_a_to` along it. One triangle strip (additive line segments would
///       double up at the joints). Angles are GameMaker's: 0 is east,
///       increasing anticlockwise.
function draw_arc_band(_x, _y, _r_in, _r_out, _from, _to, _colour, _a_from,
                       _a_to, _steps) {
    _steps = max(2, _steps);
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _steps; _i++) {
        var _t = _i / _steps;
        var _ang = lerp(_from, _to, _t);
        var _a = lerp(_a_from, _a_to, _t);
        draw_vertex_colour(_x + lengthdir_x(_r_in, _ang),
                           _y + lengthdir_y(_r_in, _ang), _colour, _a);
        draw_vertex_colour(_x + lengthdir_x(_r_out, _ang),
                           _y + lengthdir_y(_r_out, _ang), _colour, _a);
    }
    draw_primitive_end();
}

/// @desc Bubbles rising through the liquid from `_bot` to `_surf`, derived
///       from the clock rather than simulated.
function draw_liquid_bubbles(_x0, _x1, _bot, _surf, _seed, _col, _alpha) {
    if (abs(_bot - _surf) < 12) return;
    if (_x1 - _x0 < 10) return;
    ui_blend(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 7; _i++) {
        var _p = frac(current_time * (0.00007 + 0.00005 * frac(_i * 0.37))
                      + _i * 0.143 + _seed * 0.01);
        var _bx = lerp(_x0 + 4, _x1 - 4, frac(_i * 0.61 + _seed * 0.07));
        var _by = lerp(_bot, _surf, _p);
        // Bigger as it rises, and gone before it reaches the surface.
        var _s = (5 + 5 * frac(_i * 0.83)) * (0.6 + 0.7 * _p);
        var _a = _alpha * min(1, _p * 6) * (1 - power(_p, 3));
        var _k = _s / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _bx, _by, _k, _k, 0, _col, _a);
    }
    ui_blend(bm_normal);
}

/// @desc The glass a gauge is drawn in: the trough and its lengthwise
///       highlight.
function draw_gauge_trough(_x, _y, _w, _h, _alpha) {
    capsule_fill(_x, _y, _w, _h, COL_VOID, _alpha * 0.88);

    // A faint highlight band along the glass, inset by the radius so the
    // additive band doesn't spill past the rounded ends.
    var _r = _h * 0.5;
    ui_blend(bm_add);
    draw_set_colour(c_white);
    draw_set_alpha(_alpha * 0.06);
    draw_rectangle(_x + _r, _y + _h * 0.15, _x + _w - _r, _y + _h * 0.34,
                   false);
    ui_blend(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The rim of a gauge, drawn after its contents so it covers the edge
///       where the liquid meets the glass.
function draw_gauge_rim(_x, _y, _w, _h, _ready, _alpha,
                        _col = COL_SILVER, _cold = COL_SLATE) {
    // When ready, the rim is the vessel's own hue lightened and pulsing (not
    // white, which reads as "selected").
    var _rim = _ready
        ? merge_colour(merge_colour(_col, COL_SILVER, 0.45), c_white,
                       0.1 + 0.3 * dsin(current_time * 0.25))
        : _cold;
    // Two pixels thick, from the same contour as the liquid.
    var _r = _h * 0.5;
    capsule_ring(_x + _r, _x + _w - _r, _y + _r, _r, _r - 2, _rim,
                 _alpha * (_ready ? 0.9 : 0.78));
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A horizontal liquid gauge filling from the left (every meter in the
///       game). The liquid body is sampled off the capsule contour; its
///       surface is a wave displaced in x (`liquid_wave`).
///
///       `_opts`: `ready`, `slosh`, `seed`, `quadrants` (division count),
///       `glow`, and `rim` (the rim's colour when not ready; the boss channel
///       uses dark gold).
///
///       It is three parts, drawn in turn: the glass (`draw_gauge_trough`),
///       the contents (`draw_gauge_contents`) and the rim (`draw_gauge_rim`).
///       The HUD keeps the glass in a cached layer and draws the others.
function draw_gauge_h(_x, _y, _w, _h, _fraction, _colour, _alpha, _opts = {}) {
    if (_alpha <= 0.004) return;
    draw_gauge_trough(_x, _y, _w, _h, _alpha);
    draw_gauge_contents(_x, _y, _w, _h, _fraction, _colour, _alpha, _opts);
    draw_gauge_rim(_x, _y, _w, _h, _opts[$ "ready"] ?? false, _alpha, _colour,
                   _opts[$ "rim"] ?? COL_SLATE);
}

/// @desc A gauge's contents (see `draw_gauge_h`): the liquid, the divisions
///       over it, and the sheen when ready.
function draw_gauge_contents(_x, _y, _w, _h, _fraction, _colour, _alpha,
                             _opts = {}) {
    _fraction = clamp(_fraction, 0, 1);
    if (_alpha <= 0.004) return;

    var _ready = _opts[$ "ready"] ?? false;
    var _slosh = _opts[$ "slosh"] ?? 0;
    var _seed  = _opts[$ "seed"] ?? 0;
    var _glow  = _opts[$ "glow"] ?? 0;
    var _rad   = _h / 2;

    // Two pixels, matching the rim drawn over the top of it at the end.
    var _in   = 2;
    var _lo   = _x + _in;                   // the closed end
    var _hi   = _x + _w - _in;
    var _r    = _rad - _in;
    var _cy   = _y + _h * 0.5;
    var _len  = _hi - _lo;
    var _fill = _len * _fraction;
    var _surf = _lo + _fill;

    // The liquid is mostly dark (its colour darkened) with light as
    // highlights; brighter versions looked like plastic candy.
    var _deep = merge_colour(_colour, COL_VOID, 0.80);
    var _lit  = merge_colour(_colour, c_white, 0.16);
    var _face = merge_colour(_colour, COL_VOID, 0.22);

    if (_fill > 0.6) {
        // The wave is drawn only when the surface is clear of both rounded
        // ends.
        var _wavy = (_fill > LIQ_WAVE_AMP + 2)
                    && (_fill < _len - LIQ_WAVE_AMP - 2);
        var _body = _wavy ? (_surf - LIQ_WAVE_AMP) : _surf;

        var _xs = capsule_samples(_lo, _hi, _r, _body);
        var _ns = array_length(_xs);
        // The contour's height at each sample, worked out once for the body
        // and the gloss, and the surface's x at each step down it, once for
        // the wave and its meniscus.
        static _hs = [];
        static _wx = [];

        // The body: lighter along the top, dark along the bottom.
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _ns; _i++) {
            var _bx = _xs[_i];
            var _hh = capsule_half(_bx, _lo, _hi, _r);
            _hs[_i] = _hh;
            draw_vertex_colour(_bx, _cy - _hh, _face, _alpha);
            draw_vertex_colour(_bx, _cy + _hh, _deep, _alpha);
        }
        draw_primitive_end();

        if (_wavy) {
            // The wavy region between the body and the surface, sampled down
            // y and bounded by the contour. Shaded by depth (top to bottom),
            // matching the body, so there is no seam.
            var _hb = capsule_half(_body, _lo, _hi, _r);
            draw_primitive_begin(pr_trianglestrip);
            for (var _i = 0; _i <= LIQ_WAVE_STEPS; _i++) {
                var _t = _i / LIQ_WAVE_STEPS;
                var _dy = lerp(-_hb, _hb, _t);
                var _py = _cy + _dy;
                var _sx = clamp(_surf + liquid_wave(_dy + _r, _seed, _slosh),
                                _body, capsule_reach(_dy, _hi, _r));
                _wx[_i] = _sx;
                var _c = merge_colour(_face, _deep, _t);
                draw_vertex_colour(_body, _py, _c, _alpha);
                draw_vertex_colour(_sx, _py, _c, _alpha);
            }
            draw_primitive_end();

            // The meniscus: a thin additive band riding the wave.
            ui_blend(bm_add);
            draw_primitive_begin(pr_trianglestrip);
            for (var _i = 0; _i <= LIQ_WAVE_STEPS; _i++) {
                var _py = _cy + lerp(-_hb, _hb, _i / LIQ_WAVE_STEPS);
                var _sx = _wx[_i];
                draw_vertex_colour(_sx, _py, _lit, _alpha * 0.34);
                draw_vertex_colour(_sx - 7, _py, _lit, 0);
            }
            draw_primitive_end();
            ui_blend(bm_normal);
        }

        // A faint gloss along the top of the tube, following the contour.
        ui_blend(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _ns; _i++) {
            var _gx = _xs[_i];
            var _hh = _hs[_i];
            draw_vertex_colour(_gx, _cy - _hh, _lit, _alpha * 0.13);
            draw_vertex_colour(_gx, _cy - _hh * 0.52, _lit, 0);
        }
        draw_primitive_end();
        ui_blend(bm_normal);

        // Bubbles rise toward the top of the tube.
        draw_liquid_bubbles(_lo, _body, _cy + _r * 0.7, _cy - _r * 0.7, _seed,
                            merge_colour(_colour, c_white, 0.5), _alpha * 0.42);
        draw_bloom(_surf, _cy, _h * 1.5, _colour,
                   _alpha * (0.11 + 0.16 * _slosh + 0.45 * _glow));
    }

    // Divisions (e.g. one per hit or per bomb), drawn over the liquid and
    // under the rim, trimmed to the contour. Unreached divisions are drawn
    // pale and dim so they stay visible.
    var _divs = _opts[$ "quadrants"] ?? 0;
    for (var _i = 1; _i < _divs; _i++) {
        var _dx = _lo + _len * (_i / _divs);
        var _hh = capsule_half(_dx, _lo, _hi, _r) * 0.72;
        if (_hh <= 1) continue;
        var _passed = (_fraction >= _i / _divs - 0.001);

        // Each is a dark line with a pale line beside it (reads as engraved).
        draw_set_colour(COL_VOID);
        draw_set_alpha(_alpha * (_passed ? 0.85 : 0.45));
        draw_rectangle(_dx - 2, _cy - _hh, _dx, _cy + _hh, false);
        draw_set_colour(_passed ? merge_colour(_colour, c_white, 0.75)
                                : COL_SILVER);
        draw_set_alpha(_alpha * (_passed ? 0.75 : 0.38));
        draw_rectangle(_dx, _cy - _hh, _dx + 1, _cy + _hh, false);
        draw_set_alpha(1);
    }

    // When ready, a sheen travels along the liquid.
    if (_ready && _fill > 1) {
        var _p = frac(current_time * 0.00035);
        var _sx = lerp(_lo - _h, _lo + _fill + _h, _p);
        ui_blend(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i <= 10; _i++) {
            var _t = _i / 10;
            var _px = _sx + lerp(-_h * 0.9, _h * 0.9, _t);
            var _hh = capsule_half(_px, _lo, _hi, _r);
            if (_px > _lo + _fill) _hh = 0;
            var _a = _alpha * 0.16 * (1 - abs(_t - 0.5) * 2)
                     * min(1, (1 - _p) * 5) * min(1, _p * 5);
            draw_vertex_colour(_px, _cy - _hh, c_white, _a);
            draw_vertex_colour(_px, _cy + _hh, c_white, 0);
        }
        draw_primitive_end();
        ui_blend(bm_normal);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The boss rail's parts. The rail itself is drawn in GML because its width
// varies; the chain, terminals and cartouche are sprites (`make_ui.py`).
// ---------------------------------------------------------------------------

/// @desc The rail's half-height at `_x`: full, except within `_cap` px of
///       each end, where it eases down to 62% (a chamfered end; a capsule
///       end made the rail's ends look like blades).
function rail_half(_x, _lo, _hi, _half, _cap) {
    var _d = min(_x - _lo, _hi - _x);
    if (_d >= _cap) return _half;
    return _half * (0.62 + 0.38 * sqrt(max(0, _d) / _cap));
}

/// @desc The gilded rail the boss's health channel is set into, drawn as a
///       shaded cross-section (dark edge, bright bevel, darker body, a bounce
///       light near the bottom) sampled along `rail_half`. Always gilt,
///       whatever the stage.
function draw_rail(_x, _y, _w, _h, _alpha = 1) {
    if (_alpha <= 0.004 || _w <= 0) return;

    var _r   = _h * 0.5;
    var _cap = min(_h * 0.42, _w * 0.5);
    var _lo  = _x;
    var _hi  = _x + _w;
    var _cy  = _y + _r;
    // Sampled finely inside the chamfers, coarsely along the straight run.
    var _xs = capsule_samples(_lo, _hi, _cap, _hi);
    var _n  = array_length(_xs);

    var _dark = merge_colour(COL_GILT, COL_VOID, 0.84);

    // The section's colour stops, top to bottom, as fractions of the local
    // half-height. Mostly dark with a bright line, so the rail isn't the
    // brightest thing across the top of the field. The rail is solid metal;
    // the health channel's own trough is the only recess.
    var _ts = [-1.00, -0.92, -0.72, -0.18, 0.42, 0.86, 1.00];
    var _cs = [_dark,
               COL_GILT_LIT,
               COL_GILT,
               merge_colour(COL_GILT, COL_VOID, 0.44),
               merge_colour(COL_GILT, COL_VOID, 0.68),
               merge_colour(COL_GILT_LIT, COL_GILT, 0.24),
               _dark];

    for (var _b = 0; _b < array_length(_ts) - 1; _b++) {
        var _t0 = _ts[_b];
        var _t1 = _ts[_b + 1];
        if (_t1 <= _t0) continue;
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _n; _i++) {
            var _px = _xs[_i];
            var _hh = rail_half(_px, _lo, _hi, _r, _cap);
            draw_vertex_colour(_px, _cy + _t0 * _hh, _cs[_b], _alpha);
            draw_vertex_colour(_px, _cy + _t1 * _hh, _cs[_b + 1], _alpha);
        }
        draw_primitive_end();
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A chain hanging from `_y0` down to `_y1`, centred on `_x`. Tiled from
///       the top, so lowering the rail reveals more links rather than
///       stretching them; the last link is cut off at `_y1` (the terminal's
///       eye is drawn over it).
function draw_chain(_x, _y0, _y1, _col, _alpha) {
    if (_alpha <= 0.004 || _y1 <= _y0) return;
    var _sw = sprite_get_width(spr_ui_chain);
    var _sh = sprite_get_height(spr_ui_chain);
    var _px = _x - _sw * 0.5;
    var _y = _y0;
    while (_y < _y1) {
        var _take = min(_sh, _y1 - _y);
        draw_sprite_part_ext(spr_ui_chain, 0, 0, 0, _sw, _take,
                             _px, _y, 1, 1, _col, _alpha);
        _y += _sh;
    }
}

/// @desc The width of a tracked string (for alignment, and for sizing a plate
///       behind it).
function text_tracked_width(_str, _track) {
    var _n = string_length(_str);
    if (_n <= 0) return 0;
    var _w = -_track;
    for (var _i = 1; _i <= _n; _i++) {
        _w += string_width(string_char_at(_str, _i)) + _track;
    }
    return _w;
}

/// @desc A framed tablet with chamfered ends: gold moulding, dark field, a
///       small spark in each end. Any width (the boss's nameplate).
function draw_tablet(_cx, _y, _w, _h, _alpha, _chamf = -1) {
    if (_alpha <= 0.004 || _w <= 0) return;
    var _ch = (_chamf < 0) ? (_h * 0.44) : _chamf;
    var _x1 = _cx - _w * 0.5;
    var _x2 = _cx + _w * 0.5;
    var _my = _y + _h * 0.5;

    // The metal, then the dark field inset 3px, as two triangle fans.
    var _pts = [[_x1, _my], [_x1 + _ch, _y], [_x2 - _ch, _y], [_x2, _my],
                [_x2 - _ch, _y + _h], [_x1 + _ch, _y + _h]];
    for (var _pass = 0; _pass < 2; _pass++) {
        var _in = (_pass == 0) ? 0 : 3;
        var _c = (_pass == 0) ? COL_GILT : COL_VOID;
        var _a = (_pass == 0) ? _alpha : _alpha;
        draw_primitive_begin(pr_trianglefan);
        draw_vertex_colour(_cx, _my, _c, _a);
        for (var _i = 0; _i <= 6; _i++) {
            var _p = _pts[_i mod 6];
            var _dx = (_p[0] - _cx);
            var _dy = (_p[1] - _my);
            var _sx = (_w * 0.5 - _in) / max(1, _w * 0.5);
            var _sy = (_h * 0.5 - _in) / max(1, _h * 0.5);
            draw_vertex_colour(_cx + _dx * _sx, _my + _dy * _sy, _c, _a);
        }
        draw_primitive_end();
    }

    // Lit along the top edges, shadowed along the bottom.
    draw_set_alpha(_alpha * 0.9);
    draw_set_colour(COL_GILT_LIT);
    draw_line_width(_pts[0][0], _pts[0][1], _pts[1][0], _pts[1][1], 2);
    draw_line_width(_pts[1][0], _pts[1][1], _pts[2][0], _pts[2][1], 2);
    draw_line_width(_pts[2][0], _pts[2][1], _pts[3][0], _pts[3][1], 2);
    draw_set_alpha(_alpha * 0.85);
    draw_set_colour(merge_colour(COL_GILT, COL_VOID, 0.72));
    draw_line_width(_pts[3][0], _pts[3][1], _pts[4][0], _pts[4][1], 2);
    draw_line_width(_pts[4][0], _pts[4][1], _pts[5][0], _pts[5][1], 2);
    draw_line_width(_pts[5][0], _pts[5][1], _pts[0][0], _pts[0][1], 2);

    // A spark in each chamfered end.
    draw_set_alpha(1);
    draw_set_colour(c_white);
    draw_sprite_ext(spr_ui_mark, 0, _x1 + _ch * 0.42, _my, 0.34, 0.34, 0,
                    COL_GILT_LIT, _alpha * 0.85);
    draw_sprite_ext(spr_ui_mark, 0, _x2 - _ch * 0.42, _my, 0.34, 0.34, 0,
                    COL_GILT_LIT, _alpha * 0.85);
}

// ---------------------------------------------------------------------------
// Counters: numbers whose digits are on wheels that roll between values
// (the boss's percentage and the attack clock). It is an odometer: a wheel
// only turns while the wheel below it is passing from 9 to 0.
// ---------------------------------------------------------------------------

/// @desc Where wheel `_k` of an odometer stands when the counter reads `_p`
///       (in units of the lowest wheel): `floor(_p / 10^k)`, plus the carry,
///       which moves it only while everything below it is in its last unit.
function counter_wheel_pos(_p, _k) {
    var _u = power(10, _k);
    var _whole = floor(_p / _u);
    var _rest = _p - _whole * _u;
    return _whole + clamp(_rest - (_u - 1), 0, 1);
}

/// @desc Text with an outline, scaled on each axis separately. What a
///       counter's drum draws a foreshortened digit with.
function draw_text_outline_ext(_x, _y, _str, _col, _alpha, _xs, _ys,
                               _thick = 2, _outline = c_black) {
    // The outline's vertical reach shrinks with the glyph, or a digit turned
    // most of the way away is a thin sliver inside a thick black box.
    var _ty = _thick * clamp(_ys / max(0.001, _xs), 0.3, 1);
    draw_set_colour(_outline);
    draw_set_alpha(_alpha * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text_transformed(_x + lengthdir_x(_thick, _i * 45),
                              _y + lengthdir_y(_ty, _i * 45), _str,
                              _xs, _ys, 0);
    }
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    draw_text_transformed(_x, _y, _str, _xs, _ys, 0);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The y to draw at with `fa_bottom` so a line of digits in the current
///       font has its ink centred on `_cy`. Digits get their own metric
///       (`FONT_DIGIT_MID_NUM` / `_UI`, re-derived by `check_font_digit_mid`).
function text_digit_middle_y(_cy, _yscale = 1) {
    var _f = (draw_get_font() == fnt_num()) ? FONT_DIGIT_MID_NUM
                                            : FONT_DIGIT_MID_UI;
    return _cy + string_height("0") * _yscale * _f;
}

/// @desc One counter wheel in the current font, centred on (`_cx`, `_cy`),
///       at position `_pos`. The two digits either side of the position sit a
///       quarter-turn apart on a drum: offset by the sine of their angle,
///       squashed and faded by the cosine. As the position falls, digits roll
///       downward. `_blank_zero` hides a 0 (for leading wheels).
function draw_counter_wheel(_cx, _cy, _pos, _col, _alpha, _scale,
                            _blank_zero = false, _thick = 2) {
    if (_alpha <= 0.004) return;
    var _d = floor(_pos);
    var _f = _pos - _d;
    var _r = string_height("0") * FONT_INK_RATIO * _scale * 0.5;

    draw_set_halign(fa_center);
    draw_set_valign(fa_bottom);
    for (var _k = 0; _k < 2; _k++) {
        var _ang = (_k - _f) * 90;       // 0 faces the window, + is below
        var _c = dcos(_ang);
        if (_c < 0.04) continue;
        var _digit = ((_d + _k) mod 10 + 10) mod 10;
        if (_blank_zero && _digit == 0) continue;
        var _ys = _scale * _c;
        var _gy = _cy + _r * dsin(_ang);
        draw_text_outline_ext(_cx, text_digit_middle_y(_gy, _ys),
                              string(_digit), _col, _alpha * power(_c, 1.5),
                              _scale, _ys, _thick);
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
