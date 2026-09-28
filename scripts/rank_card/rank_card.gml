/// @desc The rank card: the medal shown over the field when an encounter is
///       graded, and the medal itself (`medal_draw`).
///
/// Over `RANK_CARD_TIME` frames the medal spins in like a thrown coin and
/// comes to rest face on (rocking once as it stops), a glint crosses it, its
/// numbers are shown, and then it flies to its socket in the console
/// (`hud_mark_xy`), turning once on the way, and seats there. The medal is
/// solid; its flash, glow and glint are additive.

/// @desc An idle card. One per run, held on the console.
function rank_card_new() {
    return {
        t: -1,              // -1 is idle; nothing else reads as "no card"
        tier: 0,
        label: "",
        spell: false,
        earned: 0,
        target: 0,
        expired: false,     // a timed-out attack: no score line
        hits: 0,
        bombs: 0,
        slot: 0,            // which socket it flies home to
        total: 1,
        seen: 0,            // marks the console has already thrown a card for
        land: 0,            // 1 as it seats in its socket, then decays
    };
}

/// @desc Show the card for a mark that has just been filed. Called by the HUD
///       when it sees a new mark in the ledger (not by `rank_note`).
function rank_card_show(_c, _mark, _slot, _total) {
    _c.t = 0;
    _c.tier = _mark.tier;
    _c.label = _mark.label;
    _c.spell = _mark.spell;
    _c.earned = _mark[$ "earned"] ?? 0;
    _c.target = _mark[$ "target"] ?? 0;
    _c.expired = _mark[$ "expired"] ?? false;
    _c.hits = _mark[$ "hits"] ?? 0;
    _c.bombs = _mark[$ "bombs"] ?? 0;
    _c.slot = _slot;
    _c.total = max(1, _total);
    _c.land = 0;

    // Shakes the screen for an Amethyst mark.
    if (_mark.tier >= Mark.Amethyst) fx_shake(10);
    sfx(sfx_for_mark(_mark.tier));
}

/// @desc Advance it. The landing flare runs on after the card is idle.
function rank_card_step(_c) {
    _c.land = max(0, _c.land - 0.05);
    if (_c.t < 0) return;
    _c.t++;
    if (_c.t >= RANK_CARD_TIME) {
        _c.t = -1;
        _c.land = 1;
    }
}

/// @desc Is one on screen?
function rank_card_live(_c) {
    return _c.t >= 0;
}

/// @desc How far into its flight home the card is, 0 to 1 (0 before it
///       leaves).
///
///       Divided by `RANK_CARD_FLY - 1` because the card's last live frame is
///       `RANK_CARD_TIME - 1`; dividing by the full length would stop the
///       medal short of its socket (`test_rank_card` checks the landing).
function rank_card_flight(_c) {
    var _fly = _c.t - (RANK_CARD_TIME - RANK_CARD_FLY);
    return (_fly > 0) ? clamp(_fly / max(1, RANK_CARD_FLY - 1), 0, 1) : 0;
}

/// @desc Where the medal is this frame, and how big, as `[x, y, scale]`.
///       It arrives oversized and shrinks as its spin slows; over the last
///       `RANK_CARD_FLY` frames it eases to its socket and shrinks to the
///       socket medal's size.
function rank_card_where(_c) {
    var _t = _c.t;

    var _s = 1.0;
    if (_t < RANK_CARD_SPIN) {
        var _f = 1 - _t / RANK_CARD_SPIN;
        _s = 1 + 0.4 * _f * _f * _f;
    }

    var _x = FIELD_CX;
    var _y = RANK_CARD_Y;

    var _f = rank_card_flight(_c);
    if (_f > 0) {
        // Ease in: slow to leave, fast into the socket.
        var _e = _f * _f * _f;
        var _home = hud_mark_xy(_c.slot, _c.total);
        _x = lerp(_x, _home[0], _e);
        _y = lerp(_y, _home[1], _e);
        _s = lerp(_s, RANK_CARD_HOME_S, _e);
    }
    return [_x, _y, _s];
}

/// @desc How far the medal is turned about its upright, in degrees (0 is
///       face on). It spins in `RANK_CARD_TURNS` times, slowing to a stop,
///       rocks once past it, and turns once more early in its flight, ending
///       face on while it is still large.
function rank_card_turn(_c) {
    var _t = _c.t;
    if (_t < RANK_CARD_SPIN) {
        var _f = 1 - _t / RANK_CARD_SPIN;
        return 360 * RANK_CARD_TURNS * _f * _f;
    }
    if (_t < RANK_CARD_SPIN + RANK_CARD_ROCK) {
        var _g = (_t - RANK_CARD_SPIN) / RANK_CARD_ROCK;
        return -14 * dsin(_g * 360) * (1 - _g) * (1 - _g);
    }
    var _f = clamp(rank_card_flight(_c) / 0.6, 0, 1);
    return -360 * _f * _f * (3 - 2 * _f);
}

/// @desc How solid the card is: it takes three frames to appear.
function rank_card_alpha(_c) {
    return clamp(_c.t / 3, 0, 1);
}

/// @desc Draw it.
function rank_card_draw(_c) {
    if (_c.t < 0) return;

    var _w = rank_card_where(_c);
    var _x = _w[0], _y = _w[1], _s = _w[2];
    var _a = rank_card_alpha(_c);
    var _col = mark_colour(_c.tier);

    // The arrival: a flash and a shockwave, gone within a third of a second.
    // Kept small, since a large additive bloom washes out the whole field.
    if (_c.t < RANK_CARD_FLASH) {
        var _f = _c.t / RANK_CARD_FLASH;
        draw_bloom(_x, _y, MEDAL_D * 1.8 * (0.5 + _f), _col,
                   (1 - _f) * 0.30 * _a);
        var _rr = MEDAL_D * 0.42 + 420 * _f;
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_fx_ring, 0, _x, _y,
                        _rr / sprite_get_width(spr_fx_ring) * 2,
                        _rr / sprite_get_width(spr_fx_ring) * 2, 0,
                        _col, (1 - _f) * 0.55 * _a);
        gpu_set_blendmode(bm_normal);
    }

    // The glow behind the medal, which travels with it.
    draw_bloom(_x, _y, MEDAL_D * 1.45 * _s, _col, 0.30 * _a);

    // The medal. Once it is small it gives way to the console's own medal,
    // which is drawn for that size.
    var _d = MEDAL_D * _s;
    var _small = clamp((MARK_D * 2.4 - _d) / (MARK_D * 1.2), 0, 1);
    if (_small < 1) {
        medal_draw(_c.tier, _c.spell, _x, _y, _s, rank_card_turn(_c), _a);
    }
    if (_small > 0) {
        var _ms = _d / MARK_D;
        draw_sprite_ext(spr_ui_mark_medal,
                        _c.tier + (_c.spell ? Mark.Count : 0), _x, _y,
                        _ms, _ms, 0, c_white, _a * _small);
    }

    // The glint: a four-pointed spark crossing the face once it is still.
    if (_c.t >= RANK_CARD_SPIN && _c.t < RANK_CARD_GLINT_END) {
        var _f = (_c.t - RANK_CARD_SPIN) / (RANK_CARD_GLINT_END - RANK_CARD_SPIN);
        var _r = MEDAL_D * 0.42 * _s;
        var _gx = _x + lerp(-_r, _r, _f);
        var _gy = _y + lerp(_r, -_r, _f) * 0.55;
        var _ga = dsin(_f * 180) * 0.9 * _a;
        var _gs = (0.30 + 0.22 * dsin(_f * 180)) * _s;
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_fx_spark, 0, _gx, _gy, _gs, _gs, 45,
                        c_white, _ga);
        gpu_set_blendmode(bm_normal);
        draw_bloom(_gx, _gy, 150 * _s, c_white, _ga * 0.35);
    }

    // ---- the words: ordinary outlined text, gone before the flight -------
    if (_c.t < RANK_CARD_TIME - RANK_CARD_FLY) {
        var _ta = clamp((_c.t - 8) / 10, 0, 1)
                  * clamp((RANK_CARD_TIME - RANK_CARD_FLY - _c.t) / 8, 0, 1);
        // Clear of the medal, or of a spell's star above and below it.
        var _rad = MEDAL_D * 0.5 * (_c.spell ? MEDAL_STAR_AXIS : 1);
        var _ty = _y + (_rad + 46) * _s;

        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(fnt_head());
        draw_text_outline(_x, _ty, rank_card_title(_c),
                          merge_colour(_col, c_white, 0.25), _ta, 3);

        // Score against target (or that the clock ran out, which can't meet
        // it), then what it cost.
        draw_set_font(fnt_small());
        var _met = !_c.expired && (_c.earned >= _c.target);
        draw_text_tracked(_x, _ty + 52,
                          _c.expired ? "TIME OUT"
                                     : string(round(_c.earned)) + "  /  "
                                       + string(round(_c.target)), 4,
                          _met ? COL_GRAZE : COL_SILVER, _ta * 0.92, 2,
                          fa_center);
        draw_text_tracked(_x, _ty + 90, rank_card_cost(_c), 6,
                          (_c.hits + _c.bombs > 0) ? COL_LIFE : COL_SILVER,
                          _ta * 0.8, 2, fa_center);

        // The encounter's name, above the medal.
        draw_text_tracked(_x, _y - (_rad + 24) * _s, _c.label, 8,
                          COL_PARCHMENT, _ta * 0.75, 2, fa_center);

        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc Draw a rank medal of tier `_tier` centred on (`_x`, `_y`), `_s`
///       times the card's size, turned `_turn` degrees about its upright like
///       a spun coin: its edge shows as it turns, past a quarter turn its
///       reverse, and the face darkens as it turns from the light (up and to
///       the left) and flashes as it passes the angle that throws the light
///       at the viewer. A spell's medal is mounted on a star that turns with
///       it.
function medal_draw(_tier, _spell, _x, _y, _s, _turn, _alpha) {
    var _t = clamp(_tier, 0, Mark.Count - 1);
    var _c = dcos(_turn);
    var _sn = dsin(_turn);
    var _xs = max(abs(_c), 0.02) * _s;
    // How far the front face sits from the middle, across the screen.
    var _half = MEDAL_THICK * 0.5 * _s * _sn;

    if (_spell) {
        draw_sprite_ext(spr_ui_medal_star, _t, _x, _y, _xs, _s, 0, c_white,
                        _alpha);
    }

    // The edge: the medal's silhouette, stepped from the back face to the
    // front about a pixel at a time.
    var _n = ceil(abs(_half) * 2);
    for (var _k = 0; _k <= _n; _k++) {
        var _ex = _x - _half + 2 * _half * (_k / max(1, _n));
        draw_sprite_ext(spr_ui_medal_edge, _t, _ex, _y, _xs, _s, 0, c_white,
                        _alpha);
    }

    // The face toward the viewer, and which way it is heading.
    var _front = (_c >= 0);
    var _nx = _front ? _sn : -_sn;
    var _nz = abs(_c);
    var _spr = _front ? spr_ui_medal : spr_ui_medal_back;
    var _fx = _x + (_front ? _half : -_half);
    var _lit = clamp(0.35 + 0.65 * (-0.5 * _nx + 0.62 * _nz) / 0.62, 0.3, 1);
    var _v = 255 * _lit;
    draw_sprite_ext(_spr, _t, _fx, _y, _xs, _s, 0, make_colour_rgb(_v, _v, _v),
                    _alpha);

    var _sheen = max(0, 1 - abs(angle_difference(darctan2(_nx, _nz),
                                                 MEDAL_SHEEN_AT)) / 24);
    if (_sheen > 0) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(_spr, _t, _fx, _y, _xs, _s, 0, c_white,
                        _alpha * _sheen * _sheen * 0.6);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The word under the medal: the tier's name. (The perfect standing is
///       about a whole stage, so it never appears here.)
function rank_card_title(_c) {
    return mark_name(_c.tier);
}

/// @desc What it cost: "FLAWLESS", or the hits and sigils spent.
function rank_card_cost(_c) {
    if (_c.hits <= 0 && _c.bombs <= 0) return "FLAWLESS";
    var _s = "";
    if (_c.hits > 0) {
        _s += string(_c.hits) + ((_c.hits == 1) ? " HIT" : " HITS");
    }
    if (_c.bombs > 0) {
        if (_s != "") _s += "     ";
        _s += string(_c.bombs) + ((_c.bombs == 1) ? " SIGIL" : " SIGILS");
    }
    return _s;
}
