/// @desc The scrolling world behind the field, and what replaces it when a
///       spell is declared.
///
/// **Three layers, scrolling down at three rates, and nothing else.** The
/// player sprite is a back view -- he is flying away from the camera -- so the
/// world comes toward the viewer, which on a flat screen is the world moving
/// down it. Parallax is the whole of the depth: the ground crawls, the rocks
/// move, the foreground races.
///
/// **Every layer is one sprite drawn twice.** The art tiles seamlessly top to
/// bottom (see `tools/make_bg.py`), so a layer is the sprite at `y` and the
/// sprite at `y - FIELD_H`, and the offset is `scroll mod FIELD_H`. No surface,
/// no tilemap, two draw calls a layer.
///
/// **The near layer draws over the field and keeps out of the middle.** That
/// is a rule enforced in the generator rather than here, because a spire in
/// the centre of the screen is somewhere a bullet can hide, and no amount of
/// care at draw time can fix art that was authored wrong.

/// @desc One stage's backdrop. `_speed` is how fast the world goes past, in
///       pixels a frame at the middle layer.
function bg_new(_ground, _rock, _near, _air, _speed) {
    return {
        // **Which kind of world this is**, and it is the one field every
        // background has. Stage one is a floor scrolling down the screen and
        // stage two is a corridor flown into -- see `bg_corridor` -- and the
        // two have almost nothing in common but the three entry points below,
        // so the dispatch is here rather than either kind pretending to be
        // the other.
        kind: BGKIND_PARALLAX,

        // **A stage may have a second half.** `bg_set_omen` starts it, it
        // eases over `BG_OMEN_TIME`, and a background that has nothing to say
        // about it simply never reads it -- which is stage one. It lives on
        // the base struct rather than on the corridor because "the stage
        // turns" is a fact about a *run*, and the run has to be able to say
        // it without knowing what kind of world it is saying it to.
        omen: 0,
        omen_on: false,

        ground: _ground,
        rock: _rock,
        near: _near,
        air: _air,
        speed: _speed,
        t: 0,

        // How much the three layers lag the middle one. The near layer moving
        // faster than the world is what sells the depth; the ground moving at
        // a fifth is what keeps it from reading as a sliding texture.
        ground_rate: 0.22,
        rock_rate: 1.0,
        near_rate: 2.1,

        embers: [],
        ember_n: 0,
    };
}

/// @desc The brimstone stage. Later stages are another of these.
function bg_brimstone() {
    // The world goes past faster than it did, for the same reason everything
    // else here does: the screen is 1080 tall and a layer crawling at 2.6
    // pixels a frame takes seven seconds to travel its own height, which reads
    // as hanging still. See the note on speed in `constants`.
    var _b = bg_new(spr_bg_brim_ground, spr_bg_brim_rock, spr_bg_brim_near,
                    make_colour_rgb(40, 14, 12), 4.6);
    bg_seed_embers(_b, 64, make_colour_rgb(214, 74, 26));
    return _b;
}

/// @desc The motes drifting up through the scene.
///
///       **Derived from the clock, not simulated.** Each ember is a phase and
///       a rate, and where it is this frame is `frac` of the two -- so there
///       is no pool to step, nothing to respawn, and a background that has
///       been off screen for a minute is already correct on the frame it comes
///       back. The same argument Wordsearch's gauge bubbles are built on.
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

function bg_step(_b) {
    bg_omen_step(_b);
    if (_b.kind == BGKIND_CORRIDOR) {
        grove_step(_b);
        return;
    }
    _b.t++;
}

/// @desc **The stage turns.** Called once, from the timeline, and after that
///       the background has a second half.
///
///       It is a request rather than a state, because the turn takes four and
///       a half seconds and the thing that asks for it -- a line in a stage's
///       running order -- happens on one frame. Idempotent on purpose: asking
///       twice is what a restarted timeline would do.
///
///       **On the base struct rather than on the corridor**, so a stage can
///       say it without knowing what kind of world it is saying it to.
function bg_set_omen(_b) {
    _b.omen_on = true;
}

/// @desc Ease the turn along. One line, and every background gets it.
function bg_omen_step(_b) {
    if (_b.omen_on && _b.omen < 1) {
        _b.omen = min(1, _b.omen + 1 / BG_OMEN_TIME);
    }
}

/// @desc Where a layer's top edge is this frame.
function bg_offset(_b, _rate) {
    // `mod` on a negative in GML answers a negative, and a negative offset
    // leaves a band of nothing across the top of the screen. Adding the height
    // back before the second `mod` is what keeps it in [0, FIELD_H).
    var _v = (_b.t * _b.speed * _rate) mod FIELD_H;
    return (_v + FIELD_H) mod FIELD_H;
}

/// @desc The two layers that go *behind* the field.
///
///       **`_fill` scales the world up to cover the whole screen**, which the
///       stage rack needs and a run must never have. The layers are generated
///       at the field's size -- see the note at the top of `tools/make_bg.py`
///       -- so a screen with no field on it got the world in a 1360-wide
///       rectangle with a hard vertical edge down it and flat black beyond,
///       which on the rack read as the art having failed to load. Scaling is
///       the right answer rather than tiling sideways, because the layers tile
///       seamlessly *top to bottom only*: a second copy laid alongside would
///       trade one visible seam for another. Behind the rack's own scrim the
///       enlargement is invisible.
function bg_draw_back(_b, _fill = false) {
    if (_b.kind == BGKIND_CORRIDOR) {
        grove_draw_back(_b, _fill);
        return;
    }
    draw_clear(_b.air);

    var _s  = _fill ? (GAME_W / FIELD_W) : 1;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;
    var _th = FIELD_H * _s;

    // Pinned to the field's top-left, because that is where the world is
    // now. The layers are generated at FIELD_W x FIELD_H -- see the note at
    // the top of `tools/make_bg.py` -- so a layer exactly covers the field and
    // nothing has to be clipped.
    // **Explicit colour and alpha, like every other sprite draw in the game.**
    // These two were the only bare `draw_sprite` calls left, and bare means
    // "use whatever blend colour and alpha are currently set" -- so the ground
    // layer, and only the ground layer, inherited whatever the *previous
    // frame's GUI event* finished on. The stage-name splash fading its text
    // out was enough to fade the world out with it. The layer below states
    // what it wants; so does this one now.
    var _gy = _y0 + bg_offset(_b, _b.ground_rate) * _s;
    draw_sprite_ext(_b.ground, 0, _x0, _gy, _s, _s, 0, c_white, 1);
    draw_sprite_ext(_b.ground, 0, _x0, _gy - _th, _s, _s, 0, c_white, 1);

    var _ry = _y0 + bg_offset(_b, _b.rock_rate) * _s;
    draw_sprite_ext(_b.rock, 0, _x0, _ry, _s, _s, 0, c_white, 1);
    draw_sprite_ext(_b.rock, 0, _x0, _ry - _th, _s, _s, 0, c_white, 1);

    bg_draw_embers(_b, _x0, _y0, _s);
}

/// @desc The one layer that goes *in front* of the field.
///
///       **It is never opaque.** See `BG_NEAR_ALPHA`: this is the only piece
///       of the world drawn over the top of live danmaku, and at ninety-four
///       per cent it did not hide scenery, it hid bullets -- which reads to a
///       player as taking damage from nothing.
///
///       **It stands down for a spell background.** This layer is the only
///       piece of the world drawn over the top of the danmaku, so when
///       `spell_bg_draw` washes the stage out it is the one thing left
///       competing with the pattern -- and photographed mid-spell that is
///       exactly what it was: the world correctly gone, and two columns of lit
///       basalt still standing over the field on either side, brighter than
///       anything behind them. A background that works by *subtraction* cannot
///       have a foreground that opted out of it.
///
///       It is faded rather than switched off, and it never goes all the way,
///       because a foreground that vanished on the declaration frame would
///       flatten the depth at the exact moment the screen is trying to be
///       dramatic. `_spell` is the same eased 0..1 the wash uses, so the two
///       move together.
function bg_draw_front(_b, _spell = 0, _fill = false) {
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

/// @desc The motes drifting up through the scene.
///
///       **Small, dim, and a deeper red than any bullet.** This was the one
///       piece of scenery that had to be re-tuned rather than re-drawn, and
///       what forced it was a screenshot: at ten to twenty-eight pixels
///       across, in the same bright orange the ember bullets use, they were
///       the *same object* as a `BSHAPE_PELLET` in `BCOL_EMBER`. A player
///       cannot be asked to tell an obstacle from scenery by watching which of
///       them accelerates.
///
///       Three things separate them now and only the first is a number here.
///       They are half the size and much fainter. They are pushed toward the
///       deep red the lava is, which is a hue no bullet in the game uses. And
///       -- the one that actually does the work -- every bullet wears a hard
///       dark contour, which is a mark an additive light cannot make: light
///       can only ever brighten what is behind it, so a dark edge means an
///       object. See `CONTOUR` in `tools/make_bullets.py`.
function bg_draw_embers(_b, _x0 = FIELD_X0, _y0 = FIELD_Y0, _k = 1) {
    gpu_set_blendmode(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < _b.ember_n; _i++) {
        var _e = _b.embers[_i];
        // Rising: 1 at the bottom of the cycle, 0 at the top.
        var _p = frac(_e.phase + _b.t * _e.rate);
        // Seeded in field coordinates and drawn in the view's, so the same
        // motes rise through the rack's enlarged world as through the field's.
        var _y = _y0 + (FIELD_H + 40 - _p * (FIELD_H + 80)) * _k;
        var _x = _x0 + (_e.x - FIELD_X0
                        + dsin(_b.t * _e.sway_rate + _i * 40) * _e.sway) * _k;
        // Fades in at the bottom and out at the top, so nothing pops.
        var _a = min(1, _p * 5) * min(1, (1 - _p) * 4) * 0.42;
        var _s = _e.size * 2.2 * _k / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0, _e.col, _a);
    }
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The spell background
// ---------------------------------------------------------------------------

/// @desc What a spell replaces the stage with.
///
///       **Drawn in code rather than as art, and that is what makes it cheap
///       to give every spell its own.** A painted background per spell is a
///       1920x1080 sprite per spell, eleven of them for one boss, and a
///       texture page nobody can budget. What is actually wanted is "the world
///       goes away and something of this boss takes over", and that is a
///       handful of tintable motifs arranged by a function -- which costs a
///       hue and a style per spell and nothing per pixel.
///
///       **The style is the boss's, not the spell's**, which is the change
///       that mattered. Every boss used to get the same two counter-rotating
///       magic circles, and a magic circle says nothing about *who is casting*
///       -- it is the visual equivalent of naming an attack "Attack". A style
///       is a `SPELLBG_*` on the boss's definition and a function here, so a
///       new boss is one field and one function; the spell's own hue still
///       tints it, so a boss's four spells are recognisably a set without
///       being the same picture.
///
///       Whatever the style, it works by **subtraction**. The field does not
///       get brighter; the world behind it stops competing. It is the same
///       reasoning the spirit in the Wordsearch project is built on, and it is
///       the rule the first version of this broke -- flooding the screen with
///       the spell's own colour so that `Cinder Waltz` was gold bullets on a
///       gold field.
function spell_bg_draw(_style, _col, _t, _fade) {
    if (_fade <= 0.01) return;
    switch (_style) {
        case SPELLBG_BRIMSTONE: spell_bg_brimstone(_col, _t, _fade); break;
        case SPELLBG_GROVE:     spell_bg_grove(_col, _t, _fade); break;
        default:                spell_bg_sigil(_col, _t, _fade); break;
    }
}

/// @desc The wash every style starts from: the world, turned down.
///
///       **Dark, and that is the whole mechanism.** The temptation is to flood
///       the screen with the spell's colour, and photographed that way the
///       first version of this was a gold screen with gold bullets on it --
///       the pattern lost, which is the one thing a spell background must
///       never do.
function spell_bg_wash(_col, _fade, _amount = 0.26) {
    draw_set_alpha(_fade);
    draw_set_colour(merge_colour(c_black, global.bullet_dim[_col], _amount));
    draw_rectangle(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The default: two counter-rotating sigils, a bloom and pushing rings.
///
///       Kept as the fallback rather than deleted, because it is the right
///       answer for a boss whose whole idea *is* ceremony -- the Warden is a
///       carved stone told to watch, and a magic circle is exactly what one of
///       those stands in. What it is not is a default that suits everybody.
function spell_bg_sigil(_col, _t, _fade) {
    var _c = global.bullet_colour[_col];
    spell_bg_wash(_col, _fade);

    gpu_set_blendmode(bm_add);

    // A slow bloom behind everything, breathing.
    var _bs = (FIELD_W * 1.5) / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, FIELD_CX, FIELD_CY * 0.85, _bs, _bs, 0,
                    _c, 0.10 * _fade * (0.8 + 0.2 * dsin(_t * 1.1)));

    // Two sigils, counter-rotating at unrelated rates so the pattern they make
    // together never visibly repeats.
    var _ss = 1500 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, FIELD_CY, _ss, _ss,
                    _t * 0.13, _c, 0.13 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, FIELD_CY, _ss * 0.62,
                    _ss * 0.62, -_t * 0.21, c_white, 0.07 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, FIELD_CX, FIELD_CY, _ss * 1.55,
                    _ss * 1.55, _t * 0.07, _c, 0.07 * _fade);

    // Rings pushing outward on a four-second cycle, which is what keeps the
    // background moving when the sigils are only turning.
    for (var _i = 0; _i < 3; _i++) {
        var _p = frac(_t / 240 + _i / 3);
        var _r = 120 + _p * 1500;
        var _rs = _r * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, FIELD_CX, FIELD_CY, _rs, _rs, 0, _c,
                        (1 - _p) * 0.13 * _fade);
    }

    gpu_set_blendmode(bm_normal);
}

/// @desc Ziggy's: the world becomes the inside of a forge.
///
///       **One background for all of his spells, in red, grey and black.** An
///       earlier version tinted this with each spell's own hue, so `Cinder
///       Waltz` ran gold and `Meteor Fall` ran crimson. That is a feature
///       nobody asked for and it is worse than not having it: a boss's arena
///       is a *place*, and a place that changes colour every forty seconds
///       stops being one. Ziggy is a red imp who throws fire; his forge is red
///       and it stays red, and the spell's own colour lives where it belongs
///       -- on the bullets, the banner and the notch in his health bar.
///
///       Nothing here reads `_col`. That is deliberate and it is the point.
///
///       **What makes it his rather than generic fire** is that the light has
///       a source and the source is him: `spr_spell_veins` is drawn centred on
///       his station, so the rock fractures outward from wherever he is
///       standing rather than from the middle of the screen. Every four
///       seconds a wavefront of heat travels out along those cracks, which is
///       the one thing in here that is doing something rather than turning.
///       And his horns rise out of the bottom corners, lit along their leading
///       edge -- a black silhouette on a near-black wash is nothing at all, so
///       what reads is the contour, and the eye completes it into a mass.
///
///       **Six layers, back to front**, which is most of what separates this
///       from a rotating sprite: a wash, a cold grey texture, a deep glow, the
///       fracture, the horns, then ash and embers moving in front of all of
///       it. Each is cheap; the depth is in there being six of them at four
///       different rates.
///
///       It works by **subtraction** like every spell background here. The
///       whole thing lives under half opacity and the brightest thing in it is
///       a crack a few pixels wide, because the field has to stay the lit
///       thing on the screen.
function spell_bg_brimstone(_col, _t, _fade) {
    // Fixed. Not `global.bullet_colour[_col]`.
    var _hot  = make_colour_rgb(232, 96, 34);    // the fire in the cracks
    var _deep = make_colour_rgb(126, 28, 16);    // rock lit from underneath
    var _ash  = make_colour_rgb(126, 124, 132);  // smoke and cinder

    // Barely any colour in the wash: this style carries its hue in the cracks,
    // and a tinted floor under tinted cracks is the gold-on-gold mistake with
    // one more step in it.
    draw_set_alpha(_fade);
    draw_set_colour(make_colour_rgb(14, 8, 9));
    draw_rectangle(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    // Where the fire is coming from: his station, not the middle of the field.
    // Everything else in here is arranged about this point.
    var _fx = FIELD_CX;
    var _fy = BOSS_HOME_Y;

    gpu_set_blendmode(bm_add);

    // 1. The cold rock. The same crack network, enormous, grey and nearly
    //    invisible -- it is texture rather than light, and it is what stops the
    //    black between the hot cracks reading as flat black.
    var _vs = 2600 / sprite_get_width(spr_spell_veins);
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy + 120, _vs * 2.4, _vs * 2.4,
                    -_t * 0.011, _ash, 0.030 * _fade);

    // 2. The forge itself: a deep glow behind him, breathing.
    var _bs = (FIELD_W * 1.30) / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _fx, _fy, _bs, _bs, 0, _deep,
                    0.16 * _fade * (0.82 + 0.18 * dsin(_t * 1.3)));

    // 3. The standing fracture.
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _vs, _vs, _t * 0.045,
                    _hot, 0.085 * _fade * (0.85 + 0.15 * dsin(_t * 2.6)));

    // 4. **The wavefront.** `_pulse` runs 0..1 every four seconds and the
    //    network is drawn again, larger and expanding, which reads as heat
    //    travelling out along it. One extra draw of a sprite already loaded,
    //    and it is the difference between a background that moves and one that
    //    merely rotates.
    var _pulse = frac(_t / 240);
    var _ps = _vs * (0.5 + _pulse * 0.95);
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _ps, _ps, -_t * 0.028,
                    _hot, (1 - _pulse) * 0.075 * _fade);
    // ...with a white edge on the leading part of it only, which is what makes
    // it read as heat rather than as a second, dimmer copy.
    draw_sprite_ext(spr_spell_veins, 0, _fx, _fy, _ps * 1.02, _ps * 1.02,
                    -_t * 0.028, c_white,
                    (1 - _pulse) * _pulse * 0.055 * _fade);

    // 5. His horns, out of the bottom corners of the field. Mirrored rather
    //    than drawn twice: a negative xscale about the root is exactly the
    //    other side of a head.
    var _hs = 0.74;
    var _ha = 0.44 * _fade * (0.88 + 0.12 * dsin(_t * 0.9));
    draw_sprite_ext(spr_spell_horn, 0, FIELD_X0 + 40, FIELD_Y1 + 20,
                    _hs, _hs, 0, _hot, _ha);
    draw_sprite_ext(spr_spell_horn, 0, FIELD_X1 - 40, FIELD_Y1 + 20,
                    -_hs, _hs, 0, _hot, _ha);

    // 6. Columns of smoke standing in the heat, and ash and cinder going up
    //    through them. All of it derived from the clock the way
    //    `bg_draw_embers` is -- there is no pool here and nothing to step, so
    //    a background that has been off screen for a minute is already correct
    //    on the frame it comes back.
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 5; _i++) {
        var _cx = FIELD_X0 + (0.10 + 0.20 * _i) * FIELD_W
                  + dsin(_t * 0.35 + _i * 70) * 60;
        var _cs = (300 + 90 * frac(_i * 0.53)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _cx, FIELD_Y1 - 160, _cs, _cs * 3.2, 0,
                        _ash, 0.040 * _fade * (0.7 + 0.3 * dsin(_t * 0.8 + _i * 90)));
    }

    // **The ash is grey and the embers are red**, which is the whole of the
    // palette brief in two lines: grey is the only thing in this game that is
    // never a bullet, so it can be as busy as it likes.
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

    // **A vignette, drawn last and normally rather than additively.** Four
    // strips darkening the field's own edges inward. It is the cheapest single
    // thing that separates a background somebody made from a background
    // something generated: without it, a radial composition sits in a
    // rectangle with four bright corners and the eye goes to the corners.
    spell_bg_vignette(_fade * 0.55);
}

/// @desc Darken the field inward from its own edges. `_amount` is how black
///       the very edge goes.
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
