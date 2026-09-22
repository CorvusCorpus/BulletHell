/// @desc A boss: one health bar, a table of attacks, and the ceremony round
///       them.
///
/// One bar for the whole fight, with each attack's threshold marked on it
/// (asked for by the owner), rather than Touhou's bar per attack.
///
/// A phase is `{kind, name, col, bg, hp_end, time, attack, move?}` and
/// `attack(_e, _g, _t)` is called once a frame with the frames elapsed. A
/// phase ends on health (checked first) or on time; a timeout ends the attack
/// the same way but awards no capture.

/// @desc Attach boss state to an enemy and put it on the field.
/// @param {array} _phases  the attack table; see the file docstring
function boss_spawn(_x, _y, _hp, _phases, _def) {
    var _e = enemy_spawn(EnemyKind.Boss, _x, _y, _hp, undefined,
                         _def.col, 0, 0, 0);
    if (_e == undefined) return undefined;
    _e.r = _def.radius;
    _e.act = boss_act;
    _e.boss = {
        def: _def,                 // name, title, sprite, colour, backgrounds
        phases: _phases,
        phase: -1,                 // -1 until the declaration finishes
        // The attack the next pause hands over to (practice sets it to start
        // mid-table).
        next_phase: 0,
        phase_t: 0,
        // Frames left of a spell's declaration (`BOSS_SPELL_LEAD`), during
        // which it holds fire.
        lead_t: 0,
        started: false,

        declare_t: BOSS_DECLARE_TIME,
        banner_t: 0,
        eye_t: 0,
        clear_t: 0,
        entry_t: BOSS_ENTRY_TIME,

        home_x: _x,
        home_y: BOSS_HOME_Y,
        drift_t: 0,
        // The column `BossMove.Track` walks toward the player (see
        // `boss_move`).
        track_x: _x,

        hits_this_phase: 0,
        bombs_this_phase: 0,
        // The run's tally when this attack opened, for its mark.
        tally_at_phase: 0,
        captured: 0,               // spells cleared without being hit
        beaten: false,
        death_t: 0,
    };
    _e.touch = false;              // the body only hurts once it is fighting
    // Midbosses get the arrival cue too; only the name splash is the boss's.
    sfx(Sfx.BossAppear);
    return _e;
}

/// @desc The current attack, or `undefined` before the fight starts and after
///       it ends.
function boss_phase(_e) {
    var _b = _e.boss;
    if (_b.phase < 0 || _b.phase >= array_length(_b.phases)) return undefined;
    return _b.phases[_b.phase];
}

/// @desc Where this phase ends, in hit points.
function boss_phase_floor(_e) {
    var _p = boss_phase(_e);
    if (_p == undefined) return 0;
    return _e.hp_max * _p.hp_end;
}

/// @desc Is the boss taking damage right now? False through its entry, its
///       declarations and the pause between attacks.
function boss_vulnerable(_e) {
    var _b = _e.boss;
    return _b.started && _b.clear_t <= 0 && _b.entry_t <= 0
           && _b.declare_t <= 0 && _b.lead_t <= 0 && !_b.beaten;
}

/// @desc One frame of a boss. Called by `enemy_step` through `_e.act`.
function boss_act(_e, _g) {
    var _b = _e.boss;

    if (_b.entry_t > 0) {
        _b.entry_t--;
        enemy_glide(_e, _b.home_x, _b.home_y, 0.06);
        return;
    }

    if (_b.declare_t > 0) {
        _b.declare_t--;
        boss_move(_e, _g, _b.next_phase);
        if (_b.declare_t == 0) {
            _b.started = true;
            _e.touch = true;
            boss_enter_phase(_e, _g, _b.next_phase);
        }
        return;
    }

    if (_b.banner_t > 0) _b.banner_t--;
    if (_b.eye_t > 0) _b.eye_t--;

    if (_b.clear_t > 0) {
        _b.clear_t--;
        boss_move(_e, _g, _b.next_phase);
        if (_b.clear_t == 0) {
            boss_enter_phase(_e, _g, _b.next_phase);
        }
        return;
    }

    if (_b.beaten) {
        // A beaten boss drifts through its death throes, then flies off the
        // top and is culled by `enemy_step` like anything else that leaves.
        _b.death_t++;
        boss_move(_e, _g, -1);
        if (_b.death_t == 90) {
            enemy_leave(_e, 90);
            _e.vy = -7;
        }
        return;
    }

    // A spell's declaration: the boss moves but holds fire, and the phase
    // clock has not started.
    if (_b.lead_t > 0) {
        _b.lead_t--;
        boss_move(_e, _g, _b.phase);
        return;
    }

    boss_move(_e, _g, _b.phase);

    var _p = boss_phase(_e);
    if (_p == undefined) return;

    _p.attack(_e, _g, _b.phase_t);
    _b.phase_t++;

    // Health before time: reaching the threshold on the frame the clock runs
    // out counts as beaten.
    if (_e.hp <= boss_phase_floor(_e)) {
        boss_end_phase(_e, _g, true);
    } else if (_p.time > 0 && _b.phase_t >= _p.time) {
        boss_end_phase(_e, _g, false);
    }
}

// ---------------------------------------------------------------------------
// Movement
//
// Each attack says how the boss moves with its `move` field (`BossMove`):
// `Drift` (the default wide wander), `Close` (the wander kept near the
// station), `Track` (trends toward the player's column), `Fixed` (holds the
// station) or `Step` (holds, hops, holds). It is per attack because one boss
// may want different movement in different attacks.
// ---------------------------------------------------------------------------

/// @desc The movement kind for the attack at index `_i`. Read with
///       `[$ "move"]` because a missing struct field raises in GML. An index
///       off either end of the table (arrival, final pause) drifts.
function boss_move_kind(_b, _i) {
    if (_i < 0 || _i >= array_length(_b.phases)) return BossMove.Drift;
    return _b.phases[_i][$ "move"] ?? BossMove.Drift;
}

/// @desc One frame of movement for the attack at index `_i`. Pauses pass
///       `next_phase`, so a `Fixed` attack reaches its station during the
///       pause before it.
function boss_move(_e, _g, _i) {
    var _b = _e.boss;

    // `drift_t` is advanced at the end: attacks read `boss_holding` before
    // this runs, so advancing it first would make them disagree about the
    // frame.
    var _k = boss_move_kind(_b, _i);

    // The tracked column follows the boss whenever it isn't tracking, so
    // starting to track doesn't lurch across the field.
    if (_k != BossMove.Track) _b.track_x = _e.x;

    switch (_k) {
        case BossMove.Track: boss_move_track(_e, _g); break;
        case BossMove.Fixed: boss_move_hold(_e);      break;
        case BossMove.Step:  boss_move_step(_e);      break;
        case BossMove.Close:
            boss_move_drift(_e, BOSS_CLOSE_X, BOSS_CLOSE_Y);
            break;
        default:             boss_move_drift(_e);     break;
    }

    _b.drift_t++;
}

/// @desc The lissajous wander round the station: `_amp` either side
///       sideways and `_amp_y` vertically.
function boss_move_drift(_e, _amp = BOSS_DRIFT_X, _amp_y = BOSS_DRIFT_Y) {
    var _b = _e.boss;
    var _x = _b.home_x + dsin(_b.drift_t * 0.55) * _amp;
    var _y = _b.home_y + dsin(_b.drift_t * 0.93) * _amp_y;
    _e.x += (_x - _e.x) * BOSS_DRIFT_RATE;
    _e.y += (_y - _e.y) * BOSS_DRIFT_RATE;
}

/// @desc Loose horizontal tracking: the tracked column walks toward the
///       player's x at a capped speed (`BOSS_TRACK_SPD`), and the boss
///       wanders `BOSS_TRACK_SWAY` about it, squashed against the field's
///       sides. Only x tracks.
function boss_move_track(_e, _g) {
    var _b = _e.boss;

    // Without a run there is no player to track (only in tests).
    if (_g == undefined) {
        boss_move_drift(_e);
        return;
    }

    var _lo = FIELD_X0 + BOSS_TRACK_EDGE;
    var _hi = FIELD_X1 - BOSS_TRACK_EDGE;

    var _want = clamp(_g.player.x, _lo, _hi);
    _b.track_x += clamp(_want - _b.track_x, -BOSS_TRACK_SPD, BOSS_TRACK_SPD);
    _b.track_x = clamp(_b.track_x, _lo, _hi);

    var _x = clamp(_b.track_x + dsin(_b.drift_t * 0.55) * BOSS_TRACK_SWAY,
                   _lo, _hi);
    var _y = _b.home_y + dsin(_b.drift_t * 0.93) * BOSS_DRIFT_Y;
    _e.x += (_x - _e.x) * BOSS_DRIFT_RATE;
    _e.y += (_y - _e.y) * BOSS_DRIFT_RATE;
}

/// @desc Glide to the station and stay there. (The sprite still bobs in
///       `boss_draw`.)
function boss_move_hold(_e) {
    var _b = _e.boss;
    enemy_glide(_e, _b.home_x, _b.home_y, BOSS_DRIFT_RATE);
}

/// @desc `BossMove.Step`: hold for `BOSS_STEP_HOLD`, hop for
///       `BOSS_STEP_MOVE`, hold again. Derived entirely from `drift_t`, and
///       hop `n`'s landing spot is a function of `n`, so it is the same every
///       attempt.
function boss_move_step(_e) {
    var _b = _e.boss;
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    var _n = _b.drift_t div _cyc;

    // While holding, glide to this hop's spot (already there); while moving,
    // to the next one.
    var _to = ((_b.drift_t mod _cyc) < BOSS_STEP_HOLD) ? _n : _n + 1;

    enemy_glide(_e, boss_step_x(_b, _to), boss_step_y(_b, _to),
                BOSS_STEP_RATE);
}

/// @desc Where hop `_n` lands, sideways. Incommensurable angles, so the
///       sequence doesn't repeat within an attack.
function boss_step_x(_b, _n) {
    return _b.home_x + dsin(_n * 137) * BOSS_STEP_X;
}

/// @desc Where hop `_n` lands, vertically (a much smaller range).
function boss_step_y(_b, _n) {
    return _b.home_y + dsin(_n * 71) * BOSS_STEP_Y;
}

/// @desc Is the boss holding still this frame? Always true except during a
///       `Step` hop, and true for anything that isn't a boss (tests pass bare
///       `{x, y}` structs).
function boss_holding(_e) {
    if (_e == undefined) return true;
    var _b = _e[$ "boss"];
    if (_b == undefined) return true;
    if (boss_move_kind(_b, _b.phase) != BossMove.Step) return true;
    // Through a local: `mod (` reads to `check_unknown_functions` as a call to
    // a function named `mod`.
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    return (_b.drift_t mod _cyc) < BOSS_STEP_HOLD;
}

/// @desc Start attack `_i`. A spell gets a declaration (banner, eye card,
///       background, `BOSS_SPELL_LEAD` of held fire); a non-spell opens at
///       once.
function boss_enter_phase(_e, _g, _i) {
    var _b = _e.boss;
    _b.phase = _i;
    _b.phase_t = 0;
    _b.hits_this_phase = 0;
    _b.bombs_this_phase = 0;
    _b.tally_at_phase = (_g == undefined) ? 0 : _g.tally;

    if (_i >= array_length(_b.phases)) {
        boss_finish(_e, _g);
        return;
    }

    var _p = _b.phases[_i];
    _b.lead_t = 0;
    if (_p.kind == AttackKind.Spell) {
        _b.lead_t = BOSS_SPELL_LEAD;
        _b.banner_t = BOSS_SPELL_BANNER;
        _b.eye_t = BOSS_EYE_TIME;
        fx_flash_screen(global.bullet_colour[_p.col], 0.5);
        fx_ring(_e.x, _e.y, 30, 640, 44, global.bullet_colour[_p.col], 1.0);
        fx_shake(11);
        sfx(Sfx.SpellDeclare);
        if (_g != undefined) {
            _g.spell_bg = _p.bg;
            // `[$ ]`: a boss def without `spell_bg` gets the fallback rather
            // than raising.
            _g.spell_style = _b.def[$ "spell_bg"] ?? SPELLBG_SIGIL;
        }
    } else {
        if (_g != undefined) _g.spell_bg = -1;
    }
}

/// @desc Finish the current attack. `_beaten` is false when the timer ran out.
function boss_end_phase(_e, _g, _beaten) {
    var _b = _e.boss;
    var _p = boss_phase(_e);

    // Pull health down to the threshold even on a timeout, so the bar always
    // matches the attack the boss is on.
    _e.hp = min(_e.hp, boss_phase_floor(_e));

    var _swept = bullet_clear_all(true);
    laser_clear_all();
    // Rings never leave on their own, so the next attack would inherit them.
    ring_clear_all();

    var _col = (_p == undefined) ? COL_GRAZE : global.bullet_colour[_p.col];
    // Broken and survived have different cues.
    sfx(_beaten ? Sfx.SpellBreak : Sfx.SpellSurvive);
    fx_flash_screen(c_white, 0.65);
    fx_shake(18);
    fx_ring(_e.x, _e.y, 20, 520, 40, _col, 1.0);
    fx_ring(_e.x, _e.y, 10, 300, 26, c_white, 0.8);
    fx_burst(_e.x, _e.y, 34, 3, 13, _col, 40, 20);

    // The drop for clearing an attack, health included.
    item_drop_spread(_e.x, _e.y, 6, 10, 8);

    if (_g != undefined) {
        var _spell = (_p != undefined && _p.kind == AttackKind.Spell);

        // The share of the attack's clock left when it ended (0 on a timeout).
        var _frac = (_p != undefined && _p.time > 0)
            ? clamp(1 - _b.phase_t / _p.time, 0, 1) : 0;

        // A flat award plus a speed bonus priced as the grazing that finishing
        // early gave up (`rank_speed_award`). Not voided by a hit.
        _g.tally += _spell ? TALLY_SPELL_CLEAR : TALLY_PHASE_CLEAR;
        _g.tally += rank_speed_award(_p, _frac);
        _g.tally += _swept * 10;

        // File this attack's mark. It must come before the capture bonus is
        // paid: a capture already requires a clean attack, so counting its
        // bonus toward the threshold would count "not hit" twice. A non-spell
        // is labelled by the boss's name and its position in the table.
        // `_g[$ "marks"]`: test stand-ins may have no ledger, and a bare
        // missing-field read raises.
        var _label = (_spell && _p.name != "")
            ? _p.name
            : (_b.def.name + " " + string(_b.phase + 1));
        var _earned = _g.tally - _b.tally_at_phase;
        var _target = rank_attack_target(_p);
        rank_note(_g[$ "marks"], _label,
                  rank_for_encounter(_b.hits_this_phase, _b.bombs_this_phase,
                                     _earned >= _target),
                  _spell, _earned, _target,
                  _b.hits_this_phase, _b.bombs_this_phase);

        // A capture: the spell broken with no hit and no sigil.
        if (_beaten && _spell
            && _b.hits_this_phase == 0 && _b.bombs_this_phase == 0) {
            _b.captured++;
            _g.tally += TALLY_SPELL_CAPTURE;
            // Plays over the break cue.
            sfx(Sfx.Capture);
            fx_text(FIELD_CX, FIELD_CY - 120, "SPELL CAPTURED", COL_GRAZE,
                    96, 2.4);
        }

        // Tell the run how the attack ended; only here can a broken spell be
        // told from a survived one (the health is pulled to the threshold
        // either way). Practice uses it to end the attempt.
        var _ended = _g[$ "on_phase_end"];
        if (_ended != undefined) _ended(_e, _beaten);
    }

    _b.next_phase = _b.phase + 1;
    _b.clear_t = BOSS_PHASE_PAUSE;
    if (_g != undefined) _g.spell_bg = -1;
}

/// @desc The boss is out of attacks.
function boss_finish(_e, _g) {
    var _b = _e.boss;
    _b.beaten = true;
    _e.touch = false;
    _e.hp = 0;
    bullet_clear_all(true);
    laser_clear_all();
    ring_clear_all();
    sfx(Sfx.BossDie);
    fx_flash_screen(c_white, 0.9);
    fx_shake(26);
    for (var _i = 0; _i < 6; _i++) {
        fx_ring(_e.x + random_range(-70, 70), _e.y + random_range(-50, 50),
                10, 240 + _i * 60, 40 + _i * 6,
                global.bullet_colour[_b.def.col], 0.9);
    }
    fx_burst(_e.x, _e.y, 60, 2, 16, global.bullet_colour[_b.def.col], 70, 22);
    item_drop_spread(_e.x, _e.y, 20, 20, 30);
    if (_g != undefined) _g.on_boss_beaten(_e);
}

/// @desc Is this the boss whose death ends the stage? A midboss is not.
function boss_is_final(_e) {
    return _e != undefined && _e.boss != undefined && _e.boss.def.final;
}

/// @desc Record that the player was hit or bombed during this attack (for
///       its mark and the capture). Called by the run.
function boss_note_hit(_e) {
    if (_e != undefined && _e.boss != undefined) _e.boss.hits_this_phase++;
}

function boss_note_bomb(_e) {
    if (_e != undefined && _e.boss != undefined) _e.boss.bombs_this_phase++;
}

/// @desc Seconds left on the current attack, or -1 if it is untimed.
function boss_time_left(_e) {
    var _p = boss_phase(_e);
    if (_p == undefined || _p.time <= 0) return -1;
    return max(0, (_p.time - _e.boss.phase_t)) / FPS;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc The boss: a sigil and glow under it, its sprite, and a hit flash.
///       Frames advance every 7 game frames whatever the sprite says.
function boss_draw(_e) {
    var _b = _e.boss;
    var _col = global.bullet_colour[_b.def.col];
    var _t = _e.t;

    // Counter-rotating rings under the boss, which also mark where it is when
    // its sprite is lost in its own pattern.
    gpu_set_blendmode(bm_add);
    var _rs = 300 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, _e.x, _e.y, _rs, _rs * 0.42,
                    _t * 0.30, _col, 0.42);
    draw_sprite_ext(spr_boss_sigil, 0, _e.x, _e.y, _rs * 0.66, _rs * 0.28,
                    -_t * 0.52, c_white, 0.24);

    var _gs = 420 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _e.x, _e.y, _gs, _gs, 0, _col,
                    0.24 + 0.06 * dsin(_t * 2.2));
    gpu_set_blendmode(bm_normal);

    var _spr = _b.def.sprite;
    var _n = sprite_get_number(_spr);
    var _fr = (_t div 7) mod _n;
    var _bob = dsin(_t * 1.5) * 9;
    draw_sprite_ext(_spr, _fr, _e.x, _e.y + _bob, 1, 1, 0, c_white, 1);

    if (_e.flash > 0) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(_spr, _fr, _e.x, _e.y + _bob, 1, 1, 0, c_white,
                        _e.flash / ENEMY_FLASH * 0.8);
        gpu_set_blendmode(bm_normal);
    }
}
