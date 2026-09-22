/// @desc The rank card: the medal shown over the field when an encounter is
///       graded.
///
/// Over `RANK_CARD_TIME` frames the medal strikes (arrives oversized and
/// settles), a glint crosses it, its numbers are shown, and then it flies to
/// its socket in the console (`hud_mark_xy`). The medal and its effects are
/// drawn additively, because the card can appear while bullets are live and
/// additive light can't hide a bullet; the text is ordinary outlined text.

/// @desc An idle card. One per run, held on the console.
function rank_card_new() {
    return {
        t: -1,              // -1 is idle; nothing else reads as "no card"
        tier: 0,
        label: "",
        spell: false,
        earned: 0,
        target: 0,
        hits: 0,
        bombs: 0,
        slot: 0,            // which socket it flies home to
        total: 1,
        seen: 0,            // marks the console has already thrown a card for
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
    _c.hits = _mark[$ "hits"] ?? 0;
    _c.bombs = _mark[$ "bombs"] ?? 0;
    _c.slot = _slot;
    _c.total = max(1, _total);

    // Shakes the screen for an Amethyst mark.
    if (_mark.tier >= Mark.Amethyst) fx_shake(10);
    // Reuses the spell-break cue, plus the capture cue for gold and above.
    sfx(Sfx.SpellBreak);
    if (_mark.tier >= Mark.Gold) sfx(Sfx.Capture);
}

/// @desc Advance it.
function rank_card_step(_c) {
    if (_c.t < 0) return;
    _c.t++;
    if (_c.t >= RANK_CARD_TIME) _c.t = -1;
}

/// @desc Is one on screen?
function rank_card_live(_c) {
    return _c.t >= 0;
}

/// @desc Where the medal is this frame, and how big, as `[x, y, scale]`.
///       Over the last `RANK_CARD_FLY` frames it eases to its socket and
///       shrinks to the socket's size.
function rank_card_where(_c) {
    var _t = _c.t;

    // The strike: arrives oversized and settles.
    var _s = 1.0;
    if (_t < RANK_CARD_STRIKE) {
        var _f = _t / RANK_CARD_STRIKE;
        _s = 1.62 - 0.62 * _f * _f;
    } else if (_t < RANK_CARD_SETTLE) {
        // A small elastic wobble.
        var _f = (_t - RANK_CARD_STRIKE) / (RANK_CARD_SETTLE - RANK_CARD_STRIKE);
        _s = 1.0 + 0.055 * dcos(_f * 540) * (1 - _f);
    }

    var _x = FIELD_CX;
    var _y = RANK_CARD_Y;

    // Divided by `RANK_CARD_FLY - 1` because the card's last live frame is
    // `RANK_CARD_TIME - 1`; dividing by the full length would stop the medal
    // short of its socket (`test_rank_card` checks the landing).
    var _fly = _t - (RANK_CARD_TIME - RANK_CARD_FLY);
    if (_fly > 0) {
        var _f = clamp(_fly / max(1, RANK_CARD_FLY - 1), 0, 1);
        // Ease in: slow to leave, fast into the socket.
        var _e = _f * _f * _f;
        var _home = hud_mark_xy(_c.slot, _c.total);
        _x = lerp(_x, _home[0], _e);
        _y = lerp(_y, _home[1], _e);
        _s = lerp(_s, RANK_CARD_HOME_S, _e);
    }
    return [_x, _y, _s];
}

/// @desc How solid the card is: 0 through the flight's end, 1 in the middle.
function rank_card_alpha(_c) {
    var _t = _c.t;
    if (_t < 3) return _t / 3;
    var _fly = _t - (RANK_CARD_TIME - RANK_CARD_FLY);
    if (_fly > 0) return 1 - clamp(_fly / max(1, RANK_CARD_FLY - 1), 0, 1) * 0.55;
    return 1;
}

/// @desc Draw it. The medal and effects are additive; the text is not.
function rank_card_draw(_c) {
    if (_c.t < 0) return;

    var _w = rank_card_where(_c);
    var _x = _w[0], _y = _w[1], _s = _w[2];
    var _a = rank_card_alpha(_c);
    var _col = mark_colour(_c.tier);

    gpu_set_blendmode(bm_add);

    // The strike: a flash and a shockwave, gone within a fifth of a second.
    // Kept small, since a large additive bloom washes out the whole field.
    if (_c.t < RANK_CARD_STRIKE * 3) {
        var _f = _c.t / (RANK_CARD_STRIKE * 3);
        draw_bloom(_x, _y, 380 * (0.5 + _f), _col, (1 - _f) * 0.30 * _a);
        var _rr = 90 + 420 * _f;
        draw_sprite_ext(spr_fx_ring, 0, _x, _y,
                        _rr / sprite_get_width(spr_fx_ring) * 2,
                        _rr / sprite_get_width(spr_fx_ring) * 2, 0,
                        _col, (1 - _f) * 0.55 * _a);
    }

    // The medal's own glow, which travels with it.
    draw_bloom(_x, _y, 300 * _s, _col, 0.30 * _a);

    var _sc = _s * RANK_CARD_SCALE;
    var _frame = min(_c.tier, RANK_CARD_FRAMES - 1);
    draw_sprite_ext(spr_ui_medal, _frame, _x, _y, _sc, _sc, 0, _col, _a);
    // A second, whiter pass: adding the sprite to itself brightens its
    // brightest parts (bevel, facets) most, so it doesn't read as a flat disc.
    draw_sprite_ext(spr_ui_medal, _frame, _x, _y, _sc, _sc, 0,
                    merge_colour(_col, c_white, 0.55), _a * 0.55);

    // The glint: a four-pointed spark crossing the face.
    if (_c.t >= RANK_CARD_STRIKE && _c.t < RANK_CARD_GLINT_END) {
        var _f = (_c.t - RANK_CARD_STRIKE)
                 / (RANK_CARD_GLINT_END - RANK_CARD_STRIKE);
        var _r = 92 * _s;
        var _gx = _x + lerp(-_r, _r, _f);
        var _gy = _y + lerp(_r, -_r, _f) * 0.55;
        var _ga = dsin(_f * 180) * 0.9 * _a;
        var _gs = (0.30 + 0.22 * dsin(_f * 180)) * _s;
        draw_sprite_ext(spr_fx_spark, 0, _gx, _gy, _gs, _gs, 45,
                        c_white, _ga);
        draw_bloom(_gx, _gy, 150 * _s, c_white, _ga * 0.35);
    }

    gpu_set_blendmode(bm_normal);

    // ---- the words: ordinary outlined text, gone before the flight -------
    if (_c.t < RANK_CARD_TIME - RANK_CARD_FLY) {
        var _ta = clamp((_c.t - RANK_CARD_STRIKE) / 10, 0, 1)
                  * clamp((RANK_CARD_TIME - RANK_CARD_FLY - _c.t) / 8, 0, 1);
        // Below the medal's rim (176px authored, drawn at RANK_CARD_SCALE).
        var _ty = _y + 158 * _s;

        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(fnt_head());
        draw_text_outline(_x, _ty, rank_card_title(_c),
                          merge_colour(_col, c_white, 0.25), _ta, 3);

        // Score against target, then what it cost.
        draw_set_font(fnt_small());
        var _met = (_c.earned >= _c.target);
        draw_text_tracked(_x, _ty + 52,
                          string(round(_c.earned)) + "  /  "
                          + string(round(_c.target)), 4,
                          _met ? COL_GRAZE : COL_SILVER, _ta * 0.92, 2,
                          fa_center);
        draw_text_tracked(_x, _ty + 90, rank_card_cost(_c), 6,
                          (_c.hits + _c.bombs > 0) ? COL_LIFE : COL_SILVER,
                          _ta * 0.8, 2, fa_center);

        // The encounter's name, above the medal.
        draw_text_tracked(_x, _y - 132 * _s, _c.label, 8, COL_PARCHMENT,
                          _ta * 0.75, 2, fa_center);

        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
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
