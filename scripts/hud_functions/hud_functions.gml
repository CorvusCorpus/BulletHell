/// @desc The HUD: the console to the right of the field, the boss's health
///       rail inside the top of the field, and the ceremony and menu panels.
///
/// The console, top to bottom: the stage name, BEST / SCORE / GRAZE rows, the
/// LIFE and SIGIL meters, and the MARKS standing with a socket per encounter.
///
/// The boss's rail is the one HUD element drawn over the field: a gilded rail
/// hung on two chains, with the health percentage in a cartouche at its left
/// end, the health as liquid in a channel, the attack's clock as a dial at its
/// right end, the caster's name on a plate on top, and a spell's name under
/// its left end. It is lowered in on a spring when a boss appears and raised
/// again when it is beaten.
///
/// The HUD reacts by comparing what it shows with the current values each
/// frame (`hud_step`); nothing in the game notifies it of hits or score.

/// @desc The HUD's per-frame state: eased display values, slosh amounts,
///       one-shot flares, the rig spring, and last frame's values to compare
///       against.
function hud_new() {
    return {
        life_shown: HP_MAX,      // the vessel lags the number, so a hit reads
        mana_shown: 0,
        boss_shown: 1,
        tally_shown: 0,
        spell_a: 0,              // the nameplate easing in behind the banner

        // How hard each meter's liquid is sloshing: kicked when the value
        // jumps, decaying each frame.
        life_slosh: 0,
        mana_slosh: 0,
        boss_slosh: 0,

        // One-shot flares: set to 1 by a change, then decay.
        life_flare: 0,           // health lost -- the meter flushes
        mana_flare: 0,           // sigil gained
        tally_flare: 0,          // points scored -- the numerals swell
        graze_flare: 0,          // a near miss
        boss_flare: 0,           // a phase threshold crossed

        // How far the boss's rail has been lowered (0 stowed, 1 home). A
        // spring, so it overshoots past 1 and settles; `hud_rig_y`
        // extrapolates rather than clamping.
        rig: 0,
        rig_v: 0,

        // The percentage counter's position in tenths of a per cent. It rests
        // on whole tenths and rolls between them (the eased liquid value
        // almost never lands on a whole tenth).
        pct_roll: 1000,

        // The stretch of the boss's health the rail spans, as `[top, bottom]`
        // fractions: the whole fight, or one attack in practice
        // (`hud_boss_span`).
        boss_span: [1, 0],
        rig_seen: 0,             // what it was last frame, to catch the landing
        rig_flare: 0,            // the chains coming up taut

        graze_seen: 0,           // what the counters were last frame
        tally_seen: 0,
        life_seen: HP_MAX,
        mana_seen: 0,
        boss_phase_seen: -99,

        // The rank card, and how many marks it has been shown for
        // (`rank_card`).
        card: rank_card_new(),
    };
}

/// @desc The screen position of mark socket `_i` of `_total` in the console.
///       Shared by the socket row and the rank card's flight.
function hud_mark_xy(_i, _total) {
    var _per = max(1, floor(HUD_COL_W / 46));
    var _pitch = HUD_COL_W / min(max(_total, 1), _per);
    return [HUD_COL_X + _pitch * ((_i mod _per) + 0.5),
            HUD_ROW_MARKS + 64 + (_i div _per) * 42];
}

// ---------------------------------------------------------------------------
// Layout boxes, checked by `test_hud_layout` (nothing but the boss rail may
// overlap the field).
// ---------------------------------------------------------------------------

/// @desc The box readout `_which` occupies, as `[x1, y1, x2, y2]`.
function hud_box(_which) {
    switch (_which) {
        case "stage":
            return [HUD_COL_X, HUD_ROW_STAGE - 8,
                    HUD_COL_X + HUD_COL_W, HUD_RULE_1];
        case "tally":
            return [HUD_COL_X, HUD_ROW_BEST - 12,
                    HUD_COL_X + HUD_COL_W, HUD_ROW_GRAZE + 52];
        case "marks":
            return [HUD_COL_X, HUD_ROW_MARKS - 22,
                    HUD_COL_X + HUD_COL_W, HUD_PANEL_Y1 - HUD_PAD];
        case "life":
            return [HUD_COL_X, HUD_ROW_LIFE - 42,
                    HUD_COL_X + HUD_METER_W, HUD_ROW_LIFE + HUD_METER_H];
        case "mana":
            return [HUD_COL_X, HUD_ROW_SIGIL - 42,
                    HUD_COL_X + HUD_METER_W, HUD_ROW_SIGIL + HUD_METER_H];
        // The boss rail: deliberately over the field, from the field's top
        // edge (where the chains hang from) down to the spell name.
        case "boss":
            return [FIELD_X0 + BOSS_BAR_INSET, FIELD_Y0,
                    FIELD_X1 - BOSS_BAR_INSET, BOSS_SPELL_Y + 20];
    }
    return [0, 0, 0, 0];
}

/// @desc The console boxes, which must never overlap the field.
function hud_console_boxes() {
    return ["stage", "tally", "life", "mana", "marks"];
}

/// @desc Advance the HUD one frame: ease displayed values toward the truth
///       and light flares for what changed.
function hud_step(_h, _g) {
    var _p = _g.player;

    // The meters lag behind the real values so changes drain visibly. The
    // slosh is proportional to the remaining difference.
    _h.life_slosh = max(_h.life_slosh * 0.94,
                        min(1, abs(_p.hp - _h.life_shown) / HP_PER_HIT));
    _h.mana_slosh = max(_h.mana_slosh * 0.94,
                        min(1, abs(_p.mp - _h.mana_shown) / MP_PER_BOMB));

    _h.life_shown += (_p.hp - _h.life_shown) * 0.16;
    _h.mana_shown += (_p.mp - _h.mana_shown) * 0.22;
    _h.tally_shown += (_g.tally - _h.tally_shown) * 0.20;

    // Decay the flares first, then re-light any that changed.
    _h.life_flare = max(0, _h.life_flare - 0.045);
    _h.mana_flare = max(0, _h.mana_flare - 0.05);
    _h.tally_flare = max(0, _h.tally_flare - 0.06);
    _h.graze_flare = max(0, _h.graze_flare - 0.09);
    _h.boss_flare = max(0, _h.boss_flare - 0.03);

    // The ledger's flare (set by `rank_note`) is decayed here.
    var _led = _g[$ "marks"];
    if (_led != undefined) _led.flare = max(0, _led.flare - 0.018);

    // Show the rank card when the ledger has a mark the HUD hasn't seen.
    var _got = rank_count(_led);
    if (_got > _h.card.seen) {
        var _stage = _g[$ "stage"];
        var _total = (_stage != undefined) ? _stage.encounters : _got;
        rank_card_show(_h.card, _led.marks[_got - 1], _got - 1,
                       max(_got, _total));
    }
    _h.card.seen = _got;
    rank_card_step(_h.card);

    // Life flares only on loss, not on pickups.
    if (_p.hp < _h.life_seen - 0.01) _h.life_flare = 1;
    if (_p.mp > _h.mana_seen + 0.01) {
        _h.mana_flare = max(_h.mana_flare, 0.6);
    }
    if (_g.tally > _h.tally_seen) {
        // Scaled by the amount scored (12000 or more saturates it).
        _h.tally_flare = max(_h.tally_flare,
                             min(1, (_g.tally - _h.tally_seen) / 12000));
    }
    if (_p.graze_n > _h.graze_seen) _h.graze_flare = 1;

    _h.life_seen = _p.hp;
    _h.mana_seen = _p.mp;
    _h.tally_seen = _g.tally;
    _h.graze_seen = _p.graze_n;

    var _boss = enemy_find_boss();
    // In practice the rail spans only the practised attack, so it reads 100
    // to 0 (`hud_boss_span`).
    _h.boss_span = hud_boss_span(_g, _boss);
    var _want = (_boss == undefined) ? 1
              : hud_span_frac(_h.boss_span, _boss.hp / _boss.hp_max);
    _h.boss_slosh = max(_h.boss_slosh * 0.93,
                        min(1, abs(_want - _h.boss_shown) * 6));
    _h.boss_shown += (_want - _h.boss_shown) * 0.18;

    // The percentage counter moves at `COUNTER_EASE` of the gap (with a
    // minimum step) and snaps onto whole tenths. Floored, so any damage at
    // all moves it off 100.0.
    var _pct_want = clamp(floor(_want * 1000 + 0.0001), 0, 1000);
    var _pd = _pct_want - _h.pct_roll;
    if (abs(_pd) <= COUNTER_MIN_STEP) {
        _h.pct_roll = _pct_want;
    } else {
        _h.pct_roll += sign(_pd) * max(abs(_pd) * COUNTER_EASE,
                                       COUNTER_MIN_STEP);
    }

    // The rig is lowered while a boss is on the field and not beaten (and
    // not after a practice attempt ends), and raised otherwise.
    var _over = (_g[$ "phase"] == Phase.Won || _g[$ "phase"] == Phase.Lost);
    var _hung = (_boss != undefined) && !_boss.boss.beaten
                && !(_over && _g[$ "practice"] != undefined);
    _h.rig_v += ((_hung ? 1 : 0) - _h.rig) * BOSS_RIG_K
                - _h.rig_v * BOSS_RIG_D;
    _h.rig = max(0, _h.rig + _h.rig_v);

    // The landing flare fires when the rig crosses 1.
    _h.rig_flare = max(0, _h.rig_flare - 0.045);
    if (_h.rig >= 1 && _h.rig_seen < 1) _h.rig_flare = 1;
    _h.rig_seen = _h.rig;

    var _ph_now = (_boss == undefined) ? -99 : _boss.boss.phase;
    if (_ph_now != _h.boss_phase_seen) {
        if (_h.boss_phase_seen != -99 && _ph_now > _h.boss_phase_seen) {
            _h.boss_flare = 1;
        }
        _h.boss_phase_seen = _ph_now;
    }

    // The spell name under the rail fades in once the banner is gone.
    var _want_spell = 0;
    if (_boss != undefined && _boss.boss.started && !_boss.boss.beaten) {
        var _ph = boss_phase(_boss);
        if (_ph != undefined && _ph.kind == AttackKind.Spell
            && _boss.boss.clear_t <= 0 && _boss.boss.banner_t <= 0) {
            _want_spell = 1;
        }
    }
    _h.spell_a += (_want_spell - _h.spell_a) * 0.10;
}

// ---------------------------------------------------------------------------
// The console
// ---------------------------------------------------------------------------

/// @desc Draw the console and the rank card. (The boss rail is drawn
///       separately by `hud_draw_boss_line`, before the field's frame.)
function hud_draw(_h, _g) {
    var _boss = enemy_find_boss();

    hud_draw_plate();
    hud_draw_stage(_g);
    hud_draw_score(_h, _g);
    hud_draw_meters(_h, _g);
    hud_draw_marks(_h, _g);

    // Last, over everything else.
    rank_card_draw(_h.card);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The console's plate, its divider rules and corner pieces, and the
///       crest at its head.
function hud_draw_plate() {
    draw_plate(HUD_PANEL_X0, HUD_PANEL_Y0, HUD_PANEL_X1, HUD_PANEL_Y1);

    var _mid = HUD_COL_X + HUD_COL_W * 0.5;
    draw_rule(_mid, HUD_RULE_1, HUD_COL_W, COL_GILT, 0.9);
    draw_rule(_mid, HUD_RULE_2, HUD_COL_W, COL_GILT, 0.9);
    draw_rule(_mid, HUD_RULE_3, HUD_COL_W, COL_GILT, 0.9);

    draw_corners(HUD_PANEL_X0, HUD_PANEL_Y0, HUD_PANEL_X1, HUD_PANEL_Y1,
                 COL_GILT, 0.75, -6, 0.58);

    // The crest at the head of the console.
    var _cw = HUD_COL_W;
    var _cs = _cw / sprite_get_width(spr_ui_crest);
    draw_sprite_ext(spr_ui_crest, 0, _mid - _cw * 0.5,
                    HUD_PANEL_Y0 + HUD_ROW_CREST, _cs, _cs, 0, COL_GILT, 0.9);
}

/// @desc The stage's name and subtitle, at the head of the console.
function hud_draw_stage(_g) {
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    draw_set_font(fnt_ui());
    draw_text_fit(HUD_COL_X, HUD_ROW_STAGE, string_upper(_g.def.name),
                  HUD_COL_W, COL_GILT_LIT, 0.95, 2);
    draw_set_font(fnt_small());
    draw_text_fit(HUD_COL_X, HUD_ROW_STAGE + 44, _g.def.subtitle,
                  HUD_COL_W, merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.45),
                  1, 2);
}

/// @desc The BEST, SCORE and GRAZE rows. The score swells briefly when
///       points are scored.
function hud_draw_score(_h, _g) {
    var _p = _g.player;
    // BEST: the def's own `best` if it has one (practice: best this session),
    // otherwise the saved record for the stage.
    var _best = _g.def[$ "best"] ?? progress_stage(_g.def.id).best;

    // Highlighted once this attempt has beaten it.
    var _beaten = (_g.tally > _best && _best > 0);
    hud_row(HUD_ROW_BEST, "BEST", string(max(_best, 0)), fnt_ui(),
            _beaten ? merge_colour(COL_GRAZE, c_white,
                                   0.3 + 0.3 * dsin(_g.t * 4))
                    : merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.15),
            _beaten ? 1 : 0.8);

    var _f = _h.tally_flare;
    if (_f > 0.02) {
        draw_bloom(HUD_COL_X + HUD_COL_W * 0.72, HUD_ROW_SCORE,
                   HUD_COL_W * 0.9, COL_GRAZE, _f * 0.24);
    }
    hud_row(HUD_ROW_SCORE, "SCORE", string(round(_h.tally_shown)), fnt_num(),
            merge_colour(COL_GRAZE, c_white, _f * 0.65), 1, 1 + _f * 0.09);

    hud_row(HUD_ROW_GRAZE, "GRAZE", string(_p.graze_n), fnt_ui(),
            merge_colour(COL_PARCHMENT, COL_RUNE,
                         0.2 + _h.graze_flare * 0.8), 1);
}

/// @desc One console row: a tracked tag on the left and a value on the right,
///       both vertically centred on `_y` (so different font sizes line up).
function hud_row(_y, _tag, _value, _font, _col, _alpha = 1, _scale = 1) {
    draw_set_valign(fa_middle);

    draw_set_halign(fa_left);
    draw_set_font(fnt_small());
    // Tags are antique gold (`HUD_TAG_COL`).
    draw_text_tracked(HUD_COL_X, _y, _tag, 6, HUD_TAG_COL, 1, 2);

    draw_set_halign(fa_right);
    draw_set_font(_font);
    draw_text_outline_scaled(HUD_COL_X + HUD_COL_W, _y, _value, _col, _alpha,
                             _scale, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The MARKS section: the overall standing, and a row of sockets, one
///       per encounter in the stage (`stage_count_encounters`), filled as
///       marks are earned.
function hud_draw_marks(_h, _g) {
    var _x = HUD_COL_X;
    var _y = HUD_ROW_MARKS;
    var _cx = _x + HUD_COL_W * 0.5;
    var _led = _g[$ "marks"];

    // A faint rotating watermark behind the section.
    var _ring = merge_colour(COL_GILT, COL_RUNE, 0.35);
    var _rs = 330 / sprite_get_width(spr_boss_sigil);
    var _wy = (_y + HUD_PANEL_Y1) * 0.5;
    draw_sprite_ext(spr_boss_sigil, 0, _cx, _wy, _rs, _rs,
                    current_time * 0.004, _ring, 0.14);
    draw_sprite_ext(spr_boss_sigil, 0, _cx, _wy, _rs * 0.66, _rs * 0.66,
                    -current_time * 0.006, _ring, 0.11);

    // Nothing is shown as the standing until the first mark.
    var _overall = rank_overall(_led);
    var _perfect = rank_is_perfect(_led);
    var _flare = (_led == undefined) ? 0 : _led.flare;
    if (_overall < 0) {
        draw_set_valign(fa_middle);
        draw_set_halign(fa_left);
        draw_set_font(fnt_small());
        draw_text_tracked(_x, _y, "MARKS", 6, HUD_TAG_COL, 1, 2);
        draw_text_tracked(_x + HUD_COL_W, _y, "UNMARKED", 6,
                          merge_colour(HUD_TAG_COL, COL_ARCANE, 0.45), 1, 2,
                          fa_right);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    } else {
        // The short standing name ("ABSOLUTE" for the perfect standing).
        var _oc = rank_overall_colour(_led);
        if (_flare > 0.02 || _perfect) {
            draw_bloom(_x + HUD_COL_W - 60, _y, 220, _oc,
                       max(_flare * 0.35, _perfect ? 0.22 : 0));
        }
        hud_row(_y, "MARKS", rank_overall_name(_led, true), fnt_ui(),
                merge_colour(_oc, c_white, _flare * 0.5), 1);
    }

    hud_draw_block_rule(_x, _y + 26,
                        (_overall < 0) ? COL_GILT : rank_overall_colour(_led),
                        0.6);

    // ---- the sockets ------------------------------------------------------
    //
    // `max`, so a stage that files more marks than it counted grows the row.
    var _got = rank_count(_led);
    var _stage = _g[$ "stage"];
    var _want = (_stage != undefined)
        ? _stage.encounters : (_g.def[$ "encounters"] ?? _got);
    var _total = max(_got, _want);
    if (_total > 0) {
        for (var _i = 0; _i < _total; _i++) {
            var _at = hud_mark_xy(_i, _total);
            var _mx = _at[0];
            var _cy2 = _at[1];

            if (_i < _got) {
                var _m = _led.marks[_i];
                var _mc = mark_colour(_m.tier);
                // The newest mark glows while the ledger's flare lasts.
                var _new = (_i == _got - 1) ? _flare : 0;
                if (_m.tier >= Mark.Gold) {
                    draw_bloom(_mx, _cy2, 44, _mc, 0.18 + _new * 0.5);
                }
                var _s = 1 + _new * 0.35;
                draw_sprite_ext(spr_ui_mark, _m.spell ? 1 : 0, _mx, _cy2,
                                _s, _s, 0,
                                merge_colour(_mc, c_white, _new * 0.6), 1);
            } else {
                // An empty socket.
                draw_sprite_ext(spr_ui_mark, 2, _mx, _cy2, 1, 1, 0,
                                merge_colour(COL_GILT, COL_ARCANE, 0.4), 0.85);
            }
        }
    }

}

/// @desc The hairline under a section's tag.
function hud_draw_block_rule(_x, _y, _col, _alpha) {
    draw_set_alpha(_alpha);
    draw_set_colour(_col);
    draw_rectangle(_x, _y, _x + HUD_COL_W, _y + 2, false);
    draw_set_alpha(_alpha * 0.35);
    draw_rectangle(_x, _y + 2, _x + HUD_COL_W, _y + 3, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The LIFE and SIGIL meters.
function hud_draw_meters(_h, _g) {
    var _p = _g.player;

    // At one hit from death the life colour pulses.
    var _low = (_p.hp <= HP_PER_HIT);
    var _life_col = _low
        ? merge_colour(COL_LIFE, c_white, 0.35 + 0.35 * dsin(_g.t * 9))
        : COL_LIFE;

    hud_meter(HUD_ROW_LIFE, "LIFE", string(round(_p.hp)),
              _h.life_shown / HP_MAX, _life_col,
              HP_MAX div HP_PER_HIT, _h.life_slosh, _h.life_flare, _low, 11);

    // The sigil liquid is greyed until there is enough for a bomb; "ready"
    // is shown by the label, the rim and a sheen, not by lightening the
    // liquid.
    var _ready = _p.mp >= MP_PER_BOMB;
    var _mana_col = _ready ? COL_MANA
                           : merge_colour(COL_MANA, COL_SLATE, 0.5);

    hud_meter(HUD_ROW_SIGIL, _ready ? "SIGIL  READY" : "SIGIL",
              string(round(_p.mp)), _h.mana_shown / MP_MAX, _mana_col,
              MP_MAX div MP_PER_BOMB, _h.mana_slosh, _h.mana_flare, _ready, 71);
}

/// @desc One meter: a row with its name and value, and the tube under it.
function hud_meter(_y, _name, _value, _fraction, _col, _divs, _slosh, _flare,
                   _ready, _seed) {
    hud_row(_y - 24, _name, _value, fnt_ui(),
            merge_colour(COL_PARCHMENT, c_white, _flare * 0.8), 1);

    draw_gauge_h(HUD_COL_X, _y, HUD_METER_W, HUD_METER_H, _fraction, _col, 1, {
        quadrants: _divs,
        slosh: _slosh,
        seed: _seed,
        ready: _ready,
        glow: _flare,
    });

    // A brief additive flush of the meter's colour when it changes.
    if (_flare > 0.02) {
        draw_bloom(HUD_COL_X + HUD_METER_W * 0.5, _y + HUD_METER_H * 0.5,
                   HUD_METER_W * 1.1, _col, _flare * 0.30);
    }
}

// ---------------------------------------------------------------------------
// The boss's rail
// ---------------------------------------------------------------------------

/// @desc The stretch of the boss's health the rail spans, as `[top, bottom]`
///       fractions of its whole health: `[1, 0]`, or in practice the
///       practised attack's own span from the phase table. Read from the
///       practice request, because the attempt starts in a pause where the
///       boss has no phase yet.
function hud_boss_span(_g, _boss) {
    var _pr = _g[$ "practice"];
    if (_pr == undefined || _boss == undefined) return [1, 0];
    var _ph = _boss.boss.phases;
    var _i = _pr.phase_i;
    if (_i < 0 || _i >= array_length(_ph)) return [1, 0];
    var _top = (_i > 0) ? _ph[_i - 1].hp_end : 1;
    return [_top, _ph[_i].hp_end];
}

/// @desc A fraction of a boss's whole health, as a fraction of `_span`.
function hud_span_frac(_span, _f) {
    var _d = _span[0] - _span[1];
    if (_d <= 0.0001) return clamp(_f, 0, 1);
    return clamp((_f - _span[1]) / _d, 0, 1);
}

/// @desc The rail's y this frame, from the rig position.
function hud_rig_y(_h) {
    return lerp(BOSS_RIG_STOW, BOSS_BAR_Y, _h.rig);
}

/// @desc Draw the boss's rail and everything on it. Called from `obj_game`'s
///       GUI event before `field_draw_frame`: the frame's opaque margins then
///       cut the chains off at the field edge and hide the rail while it is
///       stowed above the field.
function hud_draw_boss_line(_h, _g) {
    if (_h.rig <= 0.004) return;

    var _boss = enemy_find_boss();
    var _x1 = FIELD_X0 + BOSS_BAR_INSET;
    var _x2 = FIELD_X1 - BOSS_BAR_INSET;
    var _y  = hud_rig_y(_h);
    var _cy = _y + BOSS_BAR_H * 0.5;
    var _a  = clamp(_h.rig * 1.6, 0, 1);

    // The liquid is the current attack's hue, or the boss's own colour
    // before the first attack.
    var _p = (_boss == undefined) ? undefined : boss_phase(_boss);
    var _col = COL_LIFE;
    if (_p != undefined) _col = global.bullet_colour[_p.col];
    else if (_boss != undefined) {
        _col = global.bullet_colour[_boss.boss.def.col];
    }

    // --- chains and rail (the terminals are drawn last, over the rail) ----
    var _eye = _cy - (sprite_get_yoffset(spr_ui_hanger) - UI_HANGER_EYE);
    for (var _s = 0; _s < 2; _s++) {
        var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
        draw_chain(_hx, FIELD_Y0 - 30, _eye, COL_GILT, _a);
    }

    draw_rail(_x1, _y, _x2 - _x1, BOSS_BAR_H, _a);

    // --- the health channel, between the cartouche and the dial -----------
    var _px0 = _x1 + BOSS_RIG_END + 22;
    var _dx  = _x2 - BOSS_RIG_END - 28 - BOSS_DIAL_D * 0.5;
    var _ch_x = _px0 + BOSS_PCT_W + 14;
    var _ch_w = (_dx - BOSS_DIAL_D * 0.5 - 14) - _ch_x;
    var _ch_y = _cy - BOSS_BAR_CHANNEL * 0.5;

    // The channel's rim is a dark gold, to match the rail it is set into.
    draw_gauge_h(_ch_x, _ch_y, _ch_w, BOSS_BAR_CHANNEL, _h.boss_shown, _col,
                 _a, {
        slosh: _h.boss_slosh,
        glow: _h.boss_flare,
        seed: 29,
        rim: merge_colour(COL_GILT, COL_VOID, 0.52),
    });

    // A thin shadow along the channel's upper edge, so it reads as a recess.
    gpu_set_blendmode(bm_normal);
    draw_primitive_begin(pr_trianglestrip);
    var _lipr = BOSS_BAR_CHANNEL * 0.5;
    var _lxs = capsule_samples(_ch_x, _ch_x + _ch_w, _lipr, _ch_x + _ch_w);
    for (var _i = 0; _i < array_length(_lxs); _i++) {
        var _lx = _lxs[_i];
        var _lh = capsule_half(_lx, _ch_x, _ch_x + _ch_w, _lipr);
        draw_vertex_colour(_lx, _cy - _lh, COL_VOID, _a * 0.55);
        draw_vertex_colour(_lx, _cy - _lh + 2.4, COL_VOID, 0);
    }
    draw_primitive_end();

    hud_rail_scale(_h, _boss, _ch_x, _ch_w, _cy, _col, _a);

    // --- the readouts ------------------------------------------------------
    // (The dial is drawn even with no clock, as part of the rail.)
    var _ta = clamp((_h.rig - 0.42) * 2.4, 0, 1);
    hud_draw_boss_dial(_h, _boss, _dx, _cy, _a);
    if (_boss != undefined) {
        hud_draw_boss_pct(_h, _px0, _cy, _col, _a);
        hud_draw_boss_plate(_boss, _y - BOSS_BAR_Y, _a, _ta);
        hud_draw_boss_caption(_h, _boss, _p, _y - BOSS_BAR_Y, _ta);
    }

    // The terminals last, over the rail.
    for (var _s = 0; _s < 2; _s++) {
        var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
        draw_sprite_ext(spr_ui_hanger, 0, _hx, _cy, 1, 1, 0, COL_GILT, _a);
    }

    // The landing flare: additive flashes at the terminals, and a sheen
    // running out along the rail from the middle.
    if (_h.rig_flare > 0.02) {
        var _f = _h.rig_flare;
        for (var _s = 0; _s < 2; _s++) {
            var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
            draw_bloom(_hx, _cy, 120 * (1.4 - _f), COL_GILT_LIT, _f * 0.5);
        }
        gpu_set_blendmode(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        var _sw = (_x2 - _x1) * 0.5 * (1 - _f);
        for (var _s = -1; _s <= 1; _s += 2) {
            draw_vertex_colour(FIELD_CX + _sw * _s, _y, COL_GILT_LIT, 0);
            draw_vertex_colour(FIELD_CX + _sw * _s, _y + BOSS_BAR_H,
                               COL_GILT_LIT, 0);
        }
        draw_primitive_end();
        draw_bloom(FIELD_CX + _sw, _cy, 90, COL_GILT_LIT, _f * 0.35);
        draw_bloom(FIELD_CX - _sw, _cy, 90, COL_GILT_LIT, _f * 0.35);
        gpu_set_blendmode(bm_normal);
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The rail's scale: tick marks along both flanges (longer every
///       fifth), and each phase boundary as a groove through the channel
///       (dark over liquid, pale over empty) with a notch through the flanges
///       (full depth for a spell) and, for a spell, a small lozenge under the
///       rail. The boundary currently being fought toward pulses.
function hud_rail_scale(_h, _boss, _x, _w, _cy, _col, _alpha) {
    var _r = BOSS_BAR_CHANNEL * 0.5;
    var _lo = _x + _r;
    var _hi = _x + _w - _r;

    // The tick marks.
    var _top = _cy - BOSS_BAR_H * 0.5;
    var _bot = _cy + BOSS_BAR_H * 0.5;
    draw_set_colour(COL_GILT_LIT);
    for (var _i = 1; _i < RAIL_GRADS; _i++) {
        var _gx = lerp(_lo, _hi, _i / RAIL_GRADS);
        var _major = (_i mod 5 == 0);
        var _len = _major ? 4.6 : 2.6;
        // Each tick is a dark line with a pale one beside it (a single gilt
        // hairline on gilt is invisible).
        draw_set_colour(COL_VOID);
        draw_set_alpha(_alpha * (_major ? 0.75 : 0.5));
        draw_rectangle(_gx - 1, _top + 2.4, _gx, _top + 2.4 + _len, false);
        draw_rectangle(_gx - 1, _bot - 2.4 - _len, _gx, _bot - 2.4, false);
        draw_set_colour(COL_GILT_LIT);
        draw_set_alpha(_alpha * (_major ? 0.6 : 0.36));
        draw_rectangle(_gx, _top + 2.4, _gx + 1, _top + 2.4 + _len, false);
        draw_rectangle(_gx, _bot - 2.4 - _len, _gx + 1, _bot - 2.4, false);
    }

    if (_boss == undefined) {
        draw_set_alpha(1);
        draw_set_colour(c_white);
        return;
    }

    // Phase boundaries, from the phase table.
    var _ph = _boss.boss.phases;
    var _now = _boss.boss.phase;
    for (var _i = 0; _i < array_length(_ph); _i++) {
        // Boundaries outside the rail's span (in practice) are skipped.
        var _f = hud_span_frac(_h.boss_span, _ph[_i].hp_end);
        if (_f <= 0.001 || _f >= 0.999) continue;
        var _nx = _lo + (_hi - _lo) * _f;
        var _spell = (_ph[_i].kind == AttackKind.Spell);
        var _on_liquid = (_f <= _h.boss_shown + 0.001);

        // The boundary of the current attack pulses.
        var _live = (_i == _now);
        var _puls = _live ? (0.55 + 0.45 * dsin(current_time * 0.22)) : 1;

        // The groove through the channel.
        draw_set_colour(_on_liquid ? COL_VOID : COL_GILT_LIT);
        draw_set_alpha(_alpha * (_on_liquid ? 0.9 : 0.75) * _puls);
        draw_rectangle(_nx - 1, _cy - _r + 0.5, _nx, _cy + _r - 0.5, false);
        draw_set_colour(_on_liquid ? merge_colour(_col, c_white, 0.7)
                                   : COL_GILT);
        draw_set_alpha(_alpha * (_on_liquid ? 0.6 : 0.4) * _puls);
        draw_rectangle(_nx, _cy - _r + 0.5, _nx + 1, _cy + _r - 0.5, false);

        // The key cut through the flanges: a full-depth notch for a spell and
        // a shallow one for a non-spell.
        var _deep = _spell ? (BOSS_BAR_H * 0.5) : (BOSS_BAR_H * 0.5 - 4);
        draw_set_colour(COL_GILT_LIT);
        draw_set_alpha(_alpha * (_spell ? 0.85 : 0.5) * _puls);
        draw_rectangle(_nx - 1, _cy - _deep, _nx + 1, _cy - _r, false);
        draw_rectangle(_nx - 1, _cy + _r, _nx + 1, _cy + _deep, false);

        if (_spell) {
            // The spell lozenge, under the rail.
            var _sy = _cy + BOSS_BAR_H * 0.5 + 4;
            var _sr = 5 * (_live ? (0.9 + 0.22 * dsin(current_time * 0.22))
                                 : 1);
            draw_set_alpha(_alpha * 0.9);
            draw_set_colour(COL_GILT_LIT);
            draw_triangle(_nx, _sy - _sr, _nx - _sr * 0.62, _sy,
                          _nx + _sr * 0.62, _sy, false);
            draw_triangle(_nx, _sy + _sr, _nx - _sr * 0.62, _sy,
                          _nx + _sr * 0.62, _sy, false);
            if (_live) draw_bloom(_nx, _sy, 34, COL_GILT_LIT, 0.30 * _alpha);
        }
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The boss's health percentage (to a tenth) in the cartouche at the
///       rail's left end, drawn as rolling counter wheels driven by
///       `pct_roll` (`draw_counter_wheel`).
function hud_draw_boss_pct(_h, _x, _cy, _col, _alpha) {
    // An opaque ground shaded like a drum, lighter across the middle.
    var _gx = _x + 9;
    var _gw = BOSS_PCT_W - 18;
    var _gh = BOSS_PCT_H - 14;
    var _gr = _gh * 0.5;
    var _gxs = capsule_samples(_gx, _gx + _gw, _gr, _gx + _gw);
    var _drum = merge_colour(COL_VOID, COL_ARCANE, 0.6);
    for (var _side = -1; _side <= 1; _side += 2) {
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < array_length(_gxs); _i++) {
            var _px = _gxs[_i];
            var _hh = capsule_half(_px, _gx, _gx + _gw, _gr);
            draw_vertex_colour(_px, _cy, _drum, _alpha);
            draw_vertex_colour(_px, _cy + _side * _hh, COL_VOID, _alpha);
        }
        draw_primitive_end();
    }

    // The digits whiten while turning and when a threshold falls.
    var _hot = min(1, _h.boss_slosh * 1.3 + _h.boss_flare);
    var _tint = merge_colour(COL_GILT_LIT, c_white, _hot * 0.7);
    var _p = clamp(_h.pct_roll, 0, 1000);      // tenths of a per cent
    var _sc = BOSS_PCT_SCALE;

    // Fixed columns laid out from the right, so the decimal point stays put.
    // The whole part is centred on the rail by its digits' ink; the tenth,
    // point and % sign share its baseline.
    draw_set_font(fnt_num());
    var _num_ink = string_height("0") * FONT_INK_RATIO * _sc;
    var _cw = string_width("0") * _sc;
    var _base = _cy + _num_ink * 0.5;
    var _rx = _x + BOSS_PCT_W - UI_PLAQUE_CHAMF - 7;

    draw_set_font(fnt_small());
    var _wpc = string_width("%");
    draw_set_halign(fa_right);
    draw_set_valign(fa_bottom);
    draw_text_outline(_rx, text_baseline_y(_base), "%", COL_GILT,
                      _alpha * 0.9, 2);

    draw_set_font(fnt_ui());
    var _tw = string_width("0");
    var _ui_ink = string_height("0") * FONT_INK_RATIO;
    var _tx = _rx - _wpc - 3 - _tw * 0.5;
    draw_counter_wheel(_tx, _base - _ui_ink * 0.5, counter_wheel_pos(_p, 0),
                       _tint, _alpha, 1, false, 2);

    var _wdot = string_width(".");
    var _dot_r = _tx - _tw * 0.5 - 1;
    draw_set_halign(fa_right);
    draw_set_valign(fa_bottom);
    draw_text_outline(_dot_r, text_baseline_y(_base), ".", _tint, _alpha, 2);

    // Units, tens and hundreds. Leading zeros are hidden (the hundreds wheel
    // never shows 0; the tens wheel shows 0 only under a 1).
    draw_set_font(fnt_num());
    var _ox = _dot_r - _wdot - 2 - _cw * 0.5;
    draw_counter_wheel(_ox, _cy, counter_wheel_pos(_p, 1), _tint, _alpha,
                       _sc, false, 3);
    draw_counter_wheel(_ox - _cw, _cy, counter_wheel_pos(_p, 2), _tint,
                       _alpha, _sc, _p < 100, 3);
    draw_counter_wheel(_ox - _cw * 2, _cy, counter_wheel_pos(_p, 3), _tint,
                       _alpha, _sc, true, 3);

    // The cartouche frame goes on last, over the wheels, hiding digits that
    // are partway turned out of the window.
    draw_sprite_ext(spr_ui_plaque, 0, _x + BOSS_PCT_W * 0.5, _cy, 1, 1, 0,
                    COL_GILT, _alpha);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc The attack's clock as a dial at the rail's right end: a faint full
///       ring, a bright arc for the time left sweeping back to 12 o'clock,
///       and the seconds on counter wheels in the middle. Additive.
function hud_draw_boss_dial(_h, _boss, _cx, _cy, _alpha) {
    if (_alpha <= 0.004) return;

    var _r = BOSS_DIAL_D * 0.5;
    var _secs = (_boss == undefined) ? -1 : boss_time_left(_boss);
    var _p = (_boss == undefined) ? undefined : boss_phase(_boss);
    var _whole = (_p == undefined) ? 0 : max(1, _p.time);
    var _frac = (_secs < 0) ? 0 : clamp(_secs * FPS / _whole, 0, 1);
    var _urgent = (_secs >= 0 && _secs < BOSS_DIAL_URGENT);

    // The dial's opaque face.
    draw_set_colour(COL_VOID);
    draw_set_alpha(_alpha);
    draw_circle(_cx, _cy, _r - BOSS_DIAL_D * 0.09, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    var _bz = BOSS_DIAL_D / sprite_get_width(spr_ui_dial);
    draw_sprite_ext(spr_ui_dial, 0, _cx, _cy, _bz, _bz, 0, COL_GILT, _alpha);

    if (_secs < 0) return;

    var _col = _urgent ? merge_colour(COL_GILT_LIT, COL_LIFE, 0.72)
                       : COL_GILT_LIT;
    var _lit = merge_colour(_col, c_white, 0.22);
    var _flick = _urgent ? (0.62 + 0.38 * dsin(current_time * 0.4)) : 1;
    var _rad = _r - BOSS_DIAL_D * 0.165;
    var _to = 90 - 360 * _frac;
    var _steps = max(2, ceil(360 * _frac / 6));
    var _a = _alpha * _flick;

    gpu_set_blendmode(bm_add);
    // The full clock, faint.
    draw_arc_band(_cx, _cy, _rad - 2, _rad + 2, 0, 360, COL_GILT,
                  0.10 * _alpha, 0.10 * _alpha, 48);
    if (_frac > 0.001) {
        // The time left: dim at the tail, bright at the head.
        draw_arc_band(_cx, _cy, _rad - 6, _rad + 6, 90, _to, _col,
                      0.03 * _a, 0.13 * _a, _steps);
        draw_arc_band(_cx, _cy, _rad - 2.5, _rad + 2.5, 90, _to, _lit,
                      0.10 * _a, 0.52 * _a, _steps);
    }
    gpu_set_blendmode(bm_normal);
    if (_frac > 0.001) {
        draw_bloom(_cx + lengthdir_x(_rad, _to), _cy + lengthdir_y(_rad, _to),
                   BOSS_DIAL_D * 0.34, _lit, 0.42 * _a);
    }

    // The seconds, on wheels that turn over in the first `DIAL_TICK_SHARE`
    // of each second.
    var _n = floor(_secs);
    var _u = clamp((_secs - _n - (1 - DIAL_TICK_SHARE)) / DIAL_TICK_SHARE,
                   0, 1);
    var _pos = _n + _u * _u * (3 - 2 * _u);
    var _ncol = _urgent ? merge_colour(COL_LIFE, c_white,
                                       0.35 + 0.35 * dsin(current_time * 0.4))
                        : COL_GILT_LIT;

    // One digit is centred; two straddle the centre, sliding between the two
    // layouts as the tens wheel turns away.
    draw_set_font(fnt_num());
    var _ncw = string_width("0") * BOSS_DIAL_SCALE;
    var _two = clamp(_pos - 9, 0, 1);
    var _ones_x = _cx + _ncw * 0.5 * _two;
    draw_counter_wheel(_ones_x, _cy, counter_wheel_pos(_pos, 0), _ncol,
                       _alpha, BOSS_DIAL_SCALE, false, 3);
    draw_counter_wheel(_ones_x - _ncw, _cy, counter_wheel_pos(_pos, 1), _ncol,
                       _alpha, BOSS_DIAL_SCALE, true, 3);
    draw_set_alpha(1);
}

/// @desc The caster's name on a plate standing on top of the rail. The plate
///       comes down with the rig (`_hw`); the name fades in later (`_ta`).
function hud_draw_boss_plate(_boss, _dy, _hw, _ta) {
    if (_hw <= 0.004) return;

    // The plate is sized to the tracked name.
    var _nm = string_upper(_boss.boss.def.name);
    draw_set_font(fnt_ui());
    var _nw = text_tracked_width(_nm, BOSS_NAME_TRACK);
    var _pw = min(BOSS_PLATE_MAX_W, _nw + BOSS_PLATE_PAD * 2);
    draw_tablet(FIELD_CX, BOSS_PLATE_Y + _dy, _pw, BOSS_PLATE_H, _hw);

    if (_ta <= 0.02) return;
    // Centred by the capitals' ink rather than the font cell
    // (`text_cap_middle_y`).
    draw_set_valign(fa_bottom);
    draw_text_tracked(FIELD_CX, text_cap_middle_y(BOSS_NAME_Y + _dy), _nm,
                      BOSS_NAME_TRACK, COL_GILT_LIT, _ta * 0.96, 3,
                      fa_center);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc What is printed under the rail: the spell's name, during a spell.
function hud_draw_boss_caption(_h, _boss, _p, _dy, _alpha) {
    if (_alpha <= 0.02) return;
    if (_p != undefined && _p.kind == AttackKind.Spell) {
        hud_draw_spell_name(_h, _boss, _p, _dy, _alpha);
    }
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}


// ---------------------------------------------------------------------------
// The ceremony
// ---------------------------------------------------------------------------

/// @desc The boss's name splash: a band, a name, a title, and a ring.
function hud_draw_declare(_boss) {
    var _b = _boss.boss;
    var _t = BOSS_DECLARE_TIME - _b.declare_t;        // frames elapsed
    var _in = min(1, _t / 18);
    var _out = min(1, _b.declare_t / 22);
    var _a = _in * _out;
    if (_a <= 0.01) return;

    draw_band(FIELD_CY, 320, 0.72 * _a);

    // The name arrives oversized and settles.
    var _scale = 1 + 0.5 * (1 - _in) * (1 - _in);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline_scaled(FIELD_CX, FIELD_CY - 40, _b.def.name,
                             global.bullet_colour[_b.def.col], _a, _scale, 3);
    draw_set_font(fnt_head());
    draw_text_outline(FIELD_CX, FIELD_CY + 80, _b.def.title, COL_SILVER,
                      _a * 0.9, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The spell banner and the eye card, both fading out over their own
///       lifetimes.
function hud_draw_spell(_boss) {
    var _b = _boss.boss;
    var _p = boss_phase(_boss);
    if (_p == undefined || _p.kind != AttackKind.Spell) return;

    var _col = global.bullet_colour[_p.col];

    if (_b.eye_t > 0) draw_eye_card(_b.def.eye, _b.eye_t / BOSS_EYE_TIME);

    if (_b.banner_t > 0) {
        var _t = _b.banner_t / BOSS_SPELL_BANNER;
        var _in = min(1, (1 - _t) * 6);
        var _a = _in * min(1, _t * 3.2);

        // The banner is shown across the field and slides out to the right
        // as it fades.
        var _slide = (1 - _in) * 280;
        var _y = FIELD_CY + 260;

        draw_band(_y, 200, 0.6 * _a);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(fnt_spell());
        draw_text_fit(FIELD_CX + _slide, _y, _p.name,
                      FIELD_W - 120, _col, _a, 3);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }
}

/// @desc The spell's name under the left end of the rail, for as long as the
///       spell lasts. `spell_a` only starts rising once the banner has gone,
///       so the name isn't shown in two places at once.
function hud_draw_spell_name(_h, _boss, _p, _dy = 0, _alpha = 1) {
    if (_h.spell_a <= 0.02 || _boss == undefined || _p == undefined) return;

    var _a = _h.spell_a * _alpha;
    var _col = global.bullet_colour[_p.col];

    // Fitted to `BOSS_SPELL_W` (a long name shrinks rather than running into
    // the middle). The scale is computed here because centring by ink needs
    // it.
    draw_set_font(fnt_ui());
    var _w = string_width(_p.name);
    var _s = (_w > BOSS_SPELL_W && _w > 0) ? (BOSS_SPELL_W / _w) : 1;
    draw_set_valign(fa_bottom);
    draw_set_halign(fa_left);
    draw_text_fit(FIELD_X0 + BOSS_BAR_INSET,
                  text_cap_middle_y(BOSS_SPELL_Y + _dy, _s), _p.name,
                  BOSS_SPELL_W, _col, _a, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc The pause menu. The scrim covers the whole screen; the text is
///       centred on the field (as with every panel here).
function hud_draw_pause(_g) {
    draw_scrim(0.68);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_CY - 170, "PAUSED", COL_SILVER, 1, 3);

    // In practice the middle row restarts the attack rather than the stage.
    var _practice = (_g[$ "practice"] != undefined);
    var _rows = _practice ? ["RESUME", "RESTART ATTACK", "BACK TO ATTACKS"]
                          : ["RESUME", "RESTART STAGE", "ABANDON"];
    draw_set_font(fnt_head());
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _sel = (_g.pause_row == _i);
        draw_text_outline(FIELD_CX, FIELD_CY - 10 + _i * 78, _rows[_i],
                          _sel ? COL_GRAZE : COL_SILVER, _sel ? 1 : 0.6, 2);
    }
    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 76,
                      "ARROWS  CHOOSE      Z  CONFIRM      ESC  RESUME",
                      COL_SILVER, 0.55, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The end-of-stage result panel, win or lose.
function hud_draw_result(_g) {
    var _won = (_g.phase == Phase.Won);
    var _t = min(1, _g.result_t / 40);
    draw_scrim(0.78 * _t);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_Y0 + 190,
                      _won ? "STAGE CLEAR" : "DEFEATED",
                      _won ? COL_GRAZE : COL_LIFE, _t, 3);

    // The overall standing, placed clear of the 132px title above it.
    var _led = _g[$ "marks"];
    if (rank_count(_led) > 0) {
        draw_set_font(fnt_small());
        draw_text_tracked(FIELD_CX, FIELD_Y0 + 318, "STANDING", 10,
                          COL_SILVER, _t * 0.7, 2, fa_center);
        draw_set_halign(fa_center);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, FIELD_Y0 + 376, rank_overall_name(_led),
                          rank_overall_colour(_led), _t, 3);
    }

    var _boss = _g.boss_ref;
    var _caught = (_boss == undefined) ? 0 : _boss.boss.captured;

    var _rows = [
        ["SCORE", string(_g.tally)],
        ["GRAZE", string(_g.player.graze_n)],
        ["SPELLS CAPTURED", string(_caught)],
        ["TIMES HIT", string(_g.player.hit_n)],
        ["SIGILS SPENT", string(_g.player.bomb_n)],
    ];
    // Labels are smaller than values, so the longest label fits the field.
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _y = FIELD_Y0 + 476 + _i * 78;
        draw_set_halign(fa_right);
        draw_set_font(fnt_ui());
        draw_text_outline(FIELD_CX - 30, _y, _rows[_i][0], COL_SILVER,
                          _t * 0.8, 2);
        draw_set_halign(fa_left);
        draw_set_font(fnt_num());
        draw_text_outline(FIELD_CX + 30, _y, _rows[_i][1], c_white, _t, 2);
    }

    draw_set_halign(fa_center);
    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 76, "Z  CONTINUE", COL_GRAZE,
                      _t * (0.6 + 0.4 * dsin(_g.t * 4)), 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The READY count before a practised attack opens, during the boss's
///       between-attacks pause.
function hud_draw_practice_ready(_boss) {
    var _left = _boss.boss.clear_t;
    if (_left <= 0) return;

    var _n = ceil(_left / FPS);
    // Where this second is up to: 1 on the tick, 0 at the next one.
    var _f = ((_left - 1) mod FPS) / FPS;
    // Each number snaps in and fades and grows across its second.
    var _a = min(1, _f * 3.2);

    draw_set_valign(fa_middle);
    draw_set_font(fnt_small());
    draw_text_tracked(FIELD_CX, FIELD_CY - 78, "READY", 12, COL_GILT,
                      0.7, 2, fa_center);

    draw_set_halign(fa_center);
    draw_set_font(fnt_title());
    draw_text_outline_scaled(FIELD_CX, FIELD_CY + 16, string(_n),
                             COL_GILT_LIT, _a, 1 + (1 - _a) * 0.45, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The practice result panel: the outcome (`practice_end_name`), the
///       attack, the mark, hits and sigils, and a menu (retry / choose
///       another / back to title).
function hud_draw_practice_result(_g) {
    var _r = _g[$ "practice_result"];
    var _t = min(1, _g.result_t / 40);
    // A darker scrim than the stage result (the field keeps running under it).
    draw_scrim(0.84 * _t);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    var _col = practice_end_colour(_r);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_Y0 + 200, practice_end_name(_r), _col,
                      _t, 3);

    // The attack's name, fitted to width.
    draw_set_font(fnt_head());
    draw_text_fit(FIELD_CX, FIELD_Y0 + 292, string_upper(_g.def.name),
                  FIELD_W - 260, COL_PARCHMENT, _t, 2);

    // ---- the mark (the console's mark sprite, at 3x) ---------------------
    var _my = FIELD_Y0 + 396;
    if (_r != undefined && _r.tier >= 0) {
        var _mc = mark_colour(_r.tier);
        draw_bloom(FIELD_CX, _my, 260, _mc, _t * 0.3);
        draw_sprite_ext(spr_ui_mark, _r.spell ? 1 : 0, FIELD_CX, _my,
                        3, 3, 0, _mc, _t);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, _my + 82, mark_name(_r.tier), _mc, _t, 2);
    } else {
        // Dying leaves no mark.
        draw_sprite_ext(spr_ui_mark, 2, FIELD_CX, _my, 3, 3, 0,
                        merge_colour(COL_GILT, COL_ARCANE, 0.4), _t * 0.8);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, _my + 82, "UNMARKED",
                          merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.5),
                          _t * 0.8, 2);
    }

    // ---- hits and sigils ---------------------------------------------------
    var _hits  = (_r == undefined) ? 0 : _r.hits;
    var _bombs = (_r == undefined) ? 0 : _r.bombs;
    var _rows = [["TIMES HIT", string(_hits)],
                 ["SIGILS SPENT", string(_bombs)]];
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _y = FIELD_Y0 + 560 + _i * 58;
        draw_set_halign(fa_right);
        draw_set_font(fnt_ui());
        draw_text_outline(FIELD_CX - 26, _y, _rows[_i][0], COL_SILVER,
                          _t * 0.8, 2);
        draw_set_halign(fa_left);
        draw_set_font(fnt_num());
        draw_text_outline(FIELD_CX + 26, _y, _rows[_i][1], c_white,
                          _t * 0.9, 2);
    }

    // ---- and the three ways on -------------------------------------------
    draw_set_halign(fa_center);
    draw_set_font(fnt_head());
    // Placed so the last row clears the hint line.
    // "BACK TO TITLE", not "QUIT TO TITLE": the sprite fonts have no kerning,
    // and a large Cinzel "Q" leaves a gap that reads as "Q UIT".
    var _menu = ["RETRY ATTACK", "CHOOSE ANOTHER", "BACK TO TITLE"];
    for (var _i = 0; _i < array_length(_menu); _i++) {
        var _sel = (_g.result_row == _i);
        draw_text_outline(FIELD_CX, FIELD_Y0 + 724 + _i * 68, _menu[_i],
                          _sel ? COL_GRAZE : COL_SILVER,
                          _t * (_sel ? 1 : 0.55), 2);
    }

    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 72,
                      "ARROWS  CHOOSE      Z  CONFIRM",
                      merge_colour(COL_PARCHMENT, COL_GILT, 0.4), _t * 0.6, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
