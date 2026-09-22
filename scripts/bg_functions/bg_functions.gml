/// @desc Backgrounds: the shared struct and dispatch (`bg_step`,
///       `bg_draw_back`, `bg_draw_front`), stage one's parallax stack, the
///       mid-stage turn (`omen`), and the spell backgrounds.
///
/// Stage one (`bg_brimstone`) is three layers scrolling down at three rates,
/// each one sprite drawn twice (the art tiles vertically; see
/// `tools/make_bg.py`). The near layer draws over the field, so it is
/// translucent (`BG_NEAR_ALPHA`) and its art keeps out of the middle. Stage two
/// is a corridor (`bg_corridor`, `bg_grove`) and stage three a 3D room
/// (`bg_sanctum`).

/// @desc A parallax background. `_speed` is the middle layer's scroll speed in
///       px/frame. Other kinds start from this struct and override fields.
function bg_new(_ground, _rock, _near, _air, _speed) {
    return {
        // `BGKIND_PARALLAX` or `BGKIND_CORRIDOR` (dispatched on below).
        kind: BGKIND_PARALLAX,

        // Optional overrides for the three entry points (the hall uses these);
        // `undefined` means use the dispatch on `kind`.
        f_step: undefined,
        f_back: undefined,
        f_front: undefined,

        // The mid-stage turn: `bg_set_omen` sets `omen_on`, and `omen` eases
        // 0 -> 1 over `BG_OMEN_TIME`. Backgrounds without a turn ignore it.
        omen: 0,
        omen_on: false,

        // The player's position across the field, -1 (left wall) to +1
        // (right wall), passed in by `bg_step`; 0 on screens with no player.
        aim: 0,

        ground: _ground,
        rock: _rock,
        near: _near,
        air: _air,
        speed: _speed,
        t: 0,

        // Each layer's speed relative to `speed`.
        ground_rate: 0.22,
        rock_rate: 1.0,
        near_rate: 2.1,

        embers: [],
        ember_n: 0,
    };
}

/// @desc Stage one's background.
function bg_brimstone() {
    var _b = bg_new(spr_bg_brim_ground, spr_bg_brim_rock, spr_bg_brim_near,
                    make_colour_rgb(40, 14, 12), 4.6);
    bg_seed_embers(_b, 64, make_colour_rgb(214, 74, 26));
    return _b;
}

/// @desc Seed the drifting embers. Positions are derived from the clock (a
///       phase and rate each) rather than simulated.
function bg_seed_embers(_b, _n, _col) {
    _b.embers = [];
    for (var _i = 0; _i < _n; _i++) {
        array_push(_b.embers, {
            x: FIELD_X0 + random(FIELD_W),
            rate: random_range(0.00035, 0.0016),
            phase: random(1),
            sway: random_range(24, 120),
            sway_rate: random_range(0.6, 2.2),
            size: random_range(2.5, 7),
            col: _col,
        });
    }
    _b.ember_n = _n;
}

function bg_step(_b, _aim = 0) {
    // The player's aim is passed in rather than read from the player, so
    // screens without a run (the rack, the attack list) and suites can step
    // a background.
    _b.aim = clamp(_aim, -1, 1);
    bg_omen_step(_b);
    if (!is_undefined(_b.f_step)) {
        _b.f_step(_b);
        return;
    }
    if (_b.kind == BGKIND_CORRIDOR) {
        grove_step(_b);
        return;
    }
    _b.t++;
}

/// @desc Start the mid-stage turn (from a stage's timeline via
///       `wave_bg_omen`). Idempotent.
function bg_set_omen(_b) {
    _b.omen_on = true;
}

/// @desc Undo the turn instantly (`omen` straight to 0). Only the review card
///       uses this; a stage never should.
function bg_clear_omen(_b) {
    _b.omen_on = false;
    _b.omen = 0;
}

/// @desc Set the background up as it would be when a boss is reached, for
///       practice runs that skip the stage: the opening (`intro`) is finished,
///       and if `_turned`, the turn has already happened.
function bg_skip_to_boss(_b, _turned) {
    if (_b[$ "intro"] != undefined) _b.intro = 1;
    if (_turned) {
        _b.omen_on = true;
        _b.omen = 1;
    }
}

/// @desc Advance the turn one frame.
function bg_omen_step(_b) {
    if (_b.omen_on && _b.omen < 1) {
        _b.omen = min(1, _b.omen + 1 / BG_OMEN_TIME);
    }
}

/// @desc Where a layer's top edge is this frame.
function bg_offset(_b, _rate) {
    // GML's `mod` keeps the sign of a negative; fold into [0, FIELD_H).
    var _v = (_b.t * _b.speed * _rate) mod FIELD_H;
    return (_v + FIELD_H) mod FIELD_H;
}

/// @desc The layers behind the field. `_fill` scales the world up to cover the
///       whole screen (for the rack, which has no field); the layers are
///       generated at field size and only tile vertically, so they are scaled
///       rather than tiled sideways.
function bg_draw_back(_b, _fill = false) {
    if (!is_undefined(_b.f_back)) {
        _b.f_back(_b, _fill);
        return;
    }
    if (_b.kind == BGKIND_CORRIDOR) {
        grove_draw_back(_b, _fill);
        return;
    }
    draw_clear(_b.air);

    var _s  = _fill ? (GAME_W / FIELD_W) : 1;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;
    var _th = FIELD_H * _s;

    // The layers are exactly field-sized and pinned to its top-left. Drawn
    // with explicit colour and alpha (a bare `draw_sprite` inherits leftover
    // draw state).
    var _gy = _y0 + bg_offset(_b, _b.ground_rate) * _s;
    draw_sprite_ext(_b.ground, 0, _x0, _gy, _s, _s, 0, c_white, 1);
    draw_sprite_ext(_b.ground, 0, _x0, _gy - _th, _s, _s, 0, c_white, 1);

    var _ry = _y0 + bg_offset(_b, _b.rock_rate) * _s;
    draw_sprite_ext(_b.rock, 0, _x0, _ry, _s, _s, 0, c_white, 1);
    draw_sprite_ext(_b.rock, 0, _x0, _ry - _th, _s, _s, 0, c_white, 1);

    bg_draw_embers(_b, _x0, _y0, _s);
}

/// @desc The near layer, drawn over the field: translucent at most
///       (`BG_NEAR_ALPHA`, so bullets show through), and faded most of the
///       way out by `_spell` (the spell background's 0..1 fade).
function bg_draw_front(_b, _spell = 0, _fill = false) {
    if (!is_undefined(_b.f_front)) {
        _b.f_front(_b, _spell, _fill);
        return;
    }
    if (_b.kind == BGKIND_CORRIDOR) {
        grove_draw_front(_b, _spell, _fill);
        return;
    }
    var _a = BG_NEAR_ALPHA * (1 - 0.86 * clamp(_spell, 0, 1));
    if (_a <= 0.01) return;
    var _s  = _fill ? (GAME_W / FIELD_W) : 1;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;
    var _ny = _y0 + bg_offset(_b, _b.near_rate) * _s;
    draw_sprite_ext(_b.near, 0, _x0, _ny, _s, _s, 0, c_white, _a);
    draw_sprite_ext(_b.near, 0, _x0, _ny - FIELD_H * _s, _s, _s, 0, c_white, _a);
}

/// @desc The embers drifting up through the scene: small, faint and deep red,
///       so they aren't mistaken for bullets (which also carry a dark contour
///       additive scenery can't draw).
function bg_draw_embers(_b, _x0 = FIELD_X0, _y0 = FIELD_Y0, _k = 1) {
    gpu_set_blendmode(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < _b.ember_n; _i++) {
        var _e = _b.embers[_i];
        // Rising: 1 at the bottom of the cycle, 0 at the top.
        var _p = frac(_e.phase + _b.t * _e.rate);
        // Seeded in field coordinates and drawn in the view's (the rack's is
        // enlarged).
        var _y = _y0 + (FIELD_H + 40 - _p * (FIELD_H + 80)) * _k;
        var _x = _x0 + (_e.x - FIELD_X0
                        + dsin(_b.t * _e.sway_rate + _i * 40) * _e.sway) * _k;
        // Fades in at the bottom and out at the top.
        var _a = min(1, _p * 5) * min(1, (1 - _p) * 4) * 0.42;
        var _s = _e.size * 2.2 * _k / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0, _e.col, _a);
    }
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The spell background
// ---------------------------------------------------------------------------

/// @desc The spell background, drawn over the stage background during a
///       spell. The style comes from the boss (`def.spell_bg`: one per boss,
///       the owner's rule). `_col` is the phase's `bg` colour: the sigil style
///       tints with it; the brimstone and grove styles ignore it.
///
///       Every style darkens the field (a dark wash with dim motifs) rather
///       than brightening it, so the bullets stay the brightest thing.
function spell_bg_draw(_style, _col, _t, _fade) {
    if (_fade <= 0.01) return;
    switch (_style) {
        case SPELLBG_BRIMSTONE: spell_bg_brimstone(_col, _t, _fade); break;
        case SPELLBG_GROVE:     spell_bg_grove(_col, _t, _fade); break;
        default:                spell_bg_sigil(_col, _t, _fade); break;
    }
}

/// @desc A dark wash over the field, faintly tinted with `_col`.
function spell_bg_wash(_col, _fade, _amount = 0.26) {
    draw_set_alpha(_fade);
    draw_set_colour(merge_colour(c_black, global.bullet_dim[_col], _amount));
    draw_rectangle(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The default style: two counter-rotating sigils, a bloom and rings
///       pushing outward.
function spell_bg_sigil(_col, _t, _fade) {
    var _c = global.bullet_colour[_col];
    spell_bg_wash(_col, _fade);

    gpu_set_blendmode(bm_add);

    // Centred on the boss's home station (not the field centre, and not the
    // boss's live position, so it doesn't slide as the boss drifts).
    var _cy = BOSS_HOME_Y;

    // A slow bloom behind everything, breathing.
    var _bs = (FIELD_W * 1.5) / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, FIELD_CX, _cy, _bs, _bs, 0,
                    _c, 0.10 * _fade * (0.8 + 0.2 * dsin(_t * 1.1)));

    // Counter-rotating sigils at unrelated rates.
    var _ss = 1500 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, _cy, _ss, _ss,
                    _t * 0.13, _c, 0.13 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, _cy, _ss * 0.62,
                    _ss * 0.62, -_t * 0.21, c_white, 0.07 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, _cy, _ss * 1.55,
                    _ss * 1.55, _t * 0.07, _c, 0.07 * _fade);

    // Rings pushing outward on a four-second cycle.
    for (var _i = 0; _i < 3; _i++) {
        var _p = frac(_t / 240 + _i / 3);
        var _r = 120 + _p * 1500;
        var _rs = _r * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, FIELD_CX, _cy, _rs, _rs, 0, _c,
                        (1 - _p) * 0.13 * _fade);
    }

    gpu_set_blendmode(bm_normal);
}

/// @desc Ziggy's spell background: a forge in fixed red, grey and black (it
///       doesn't use `_col`). Six layers: a near-black wash, a faint grey crack
///       texture, a deep glow behind his station, the glowing crack network
///       (`spr_spell_veins`) centred on his station with a heat wave pulsing
///       out along it every four seconds, his horns rising from the bottom
///       corners, and smoke, ash and embers. Then a vignette.
function spell_bg_brimstone(_col, _t, _fade) {
    // Fixed colours.
    var _hot  = make_colour_rgb(232, 96, 34);    // the fire in the cracks
    var _deep = make_colour_rgb(126, 28, 16);    // rock lit from underneath
    var _ash  = make_colour_rgb(126, 124, 132);  // smoke and cinder

    draw_set_alpha(_fade);
    draw_set_colour(make_colour_rgb(14, 8, 9));
    draw_rectangle(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    // Everything is arranged about his home station.
    var _fx = FIELD_CX;
    var _fy = BOSS_HOME_Y;

    gpu_set_blendmode(bm_add);

    // 1. The crack network, huge, grey and faint (texture in the dark).
    var _vs = 2600 / sprite_get_width(spr_spell_veins);
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy + 120, _vs * 2.4, _vs * 2.4,
                    -_t * 0.011, _ash, 0.030 * _fade);

    // 2. A deep glow behind him.
    var _bs = (FIELD_W * 1.30) / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _fx, _fy, _bs, _bs, 0, _deep,
                    0.16 * _fade * (0.82 + 0.18 * dsin(_t * 1.3)));

    // 3. The standing fracture.
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _vs, _vs, _t * 0.045,
                    _hot, 0.085 * _fade * (0.85 + 0.15 * dsin(_t * 2.6)));

    // 4. The heat wave: the network drawn again, expanding, every 240 frames.
    var _pulse = frac(_t / 240);
    var _ps = _vs * (0.5 + _pulse * 0.95);
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _ps, _ps, -_t * 0.028,
                    _hot, (1 - _pulse) * 0.075 * _fade);
    // ...with a faint white copy just outside it.
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _ps * 1.02, _ps * 1.02,
                    -_t * 0.028, c_white,
                    (1 - _pulse) * _pulse * 0.055 * _fade);

    // 5. His horns, from the bottom corners (mirrored with a negative xscale).
    var _hs = 0.74;
    var _ha = 0.44 * _fade * (0.88 + 0.12 * dsin(_t * 0.9));
    draw_sprite_ext(spr_spell_horn, 0, FIELD_X0 + 40, FIELD_Y1 + 20,
                    _hs, _hs, 0, _hot, _ha);
    draw_sprite_ext(spr_spell_horn, 0, FIELD_X1 - 40, FIELD_Y1 + 20,
                    -_hs, _hs, 0, _hot, _ha);

    // 6. Smoke columns, and ash and embers rising (derived from the clock).
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 5; _i++) {
        var _cx = FIELD_X0 + (0.10 + 0.20 * _i) * FIELD_W
                  + dsin(_t * 0.35 + _i * 70) * 60;
        var _cs = (300 + 90 * frac(_i * 0.53)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _cx, FIELD_Y1 - 160, _cs, _cs * 3.2, 0,
                        _ash, 0.040 * _fade * (0.7 + 0.3 * dsin(_t * 0.8 + _i * 90)));
    }

    // Grey ash and red embers.
    for (var _i = 0; _i < 40; _i++) {
        var _p = frac(_t * (0.0016 + 0.0011 * frac(_i * 0.37)) + _i * 0.117);
        var _x = FIELD_X0 + frac(_i * 0.618) * FIELD_W
                 + dsin(_t * 0.8 + _i * 47) * (40 + 60 * frac(_i * 0.23));
        var _y = FIELD_Y1 + 60 - _p * (FIELD_H + 120);
        var _a = min(1, _p * 6) * (1 - _p) * _fade;
        var _grey = (_i mod 3) != 0;
        var _s = ((_grey ? 26 : 13) + 14 * frac(_i * 0.71)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        _grey ? _ash : _hot, _a * (_grey ? 0.22 : 0.40));
    }

    gpu_set_blendmode(bm_normal);

    // A vignette, drawn last with normal blending.
    spell_bg_vignette(_fade * 0.55);
}

/// @desc Darken the field inward from its edges; `_amount` is the alpha at
///       the very edge.
function spell_bg_vignette(_amount) {
    if (_amount <= 0.004) return;
    var _d = 260;                     // how far in it reaches
    var _c = make_colour_rgb(6, 3, 4);

    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(FIELD_X0, FIELD_Y0, _c, _amount);
    draw_vertex_colour(FIELD_X1, FIELD_Y0, _c, _amount);
    draw_vertex_colour(FIELD_X0, FIELD_Y0 + _d, _c, 0);
    draw_vertex_colour(FIELD_X1, FIELD_Y0 + _d, _c, 0);
    draw_primitive_end();

    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(FIELD_X0, FIELD_Y1, _c, _amount);
    draw_vertex_colour(FIELD_X1, FIELD_Y1, _c, _amount);
    draw_vertex_colour(FIELD_X0, FIELD_Y1 - _d, _c, 0);
    draw_vertex_colour(FIELD_X1, FIELD_Y1 - _d, _c, 0);
    draw_primitive_end();

    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(FIELD_X0, FIELD_Y0, _c, _amount);
    draw_vertex_colour(FIELD_X0, FIELD_Y1, _c, _amount);
    draw_vertex_colour(FIELD_X0 + _d, FIELD_Y0, _c, 0);
    draw_vertex_colour(FIELD_X0 + _d, FIELD_Y1, _c, 0);
    draw_primitive_end();

    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(FIELD_X1, FIELD_Y0, _c, _amount);
    draw_vertex_colour(FIELD_X1, FIELD_Y1, _c, _amount);
    draw_vertex_colour(FIELD_X1 - _d, FIELD_Y0, _c, 0);
    draw_vertex_colour(FIELD_X1 - _d, FIELD_Y1, _c, 0);
    draw_primitive_end();

    draw_set_alpha(1);
    draw_set_colour(c_white);
}
