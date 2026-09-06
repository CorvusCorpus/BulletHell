/// @desc A boss: one health bar, a table of attacks, and the ceremony round
///       them.
///
/// **One bar, with the thresholds marked on it.** Touhou gives a boss a stack
/// of health bars, one per attack, and refills the bar between them -- which
/// is legible but says nothing about how far through the fight you are. Here
/// the bar only ever goes down, and every attack's boundary is cut into it as
/// a notch, so a glance answers both "how is this attack going" and "how much
/// of this fight is left". That was asked for explicitly and it is the better
/// readout; what it costs is that a long fight's last attack is a short span
/// of bar, which is why the notches are drawn rather than the phases being
/// equal.
///
/// **The attack table is data and an attack is a function of time.** A phase
/// is `{kind, name, hp_end, time, attack}` and `attack(_e, _g, _t)` is called
/// once a frame with the frames elapsed. That is the whole interface, and it
/// is enough for everything in the genre: a pattern is a `switch` on `_t mod
/// period`, which is exactly how it reads on paper.
///
/// **A phase ends on health or on time, and never on anything else.** Time
/// running out is not a failure -- it ends the attack the same way, awards no
/// capture bonus, and moves on -- which is what stops a player who cannot beat
/// one spell being stuck on it forever.

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
        // **Which attack the ceremony hands over to.** A boss walks its table
        // in order, so in a fight this is always the next one -- but the thing
        // that *knows* it is the pause rather than the pause's caller, and
        // writing it down means a boss can be started anywhere in its table
        // after a real pause rather than only at the top after a declaration.
        // Attack practice is what wanted it; a rematch or a second encounter
        // opening on a later attack would want the same field.
        next_phase: 0,
        phase_t: 0,
        // How long this attack is still declaring itself. See
        // `BOSS_SPELL_LEAD`: a spell holds fire until its card has been
        // shown, which is the genre's rule and was missing.
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

        hits_this_phase: 0,
        bombs_this_phase: 0,
        captured: 0,               // spells cleared without being hit
        beaten: false,
        death_t: 0,
    };
    _e.touch = false;              // the body only hurts once it is fighting
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

/// @desc Is the boss taking damage right now? False through every piece of
///       ceremony, which is what keeps a player from chipping the next attack
///       down while the banner for it is still flying.
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
        boss_drift(_e);
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
        boss_drift(_e);
        if (_b.clear_t == 0) {
            boss_enter_phase(_e, _g, _b.next_phase);
        }
        return;
    }

    if (_b.beaten) {
        // **A beaten boss leaves under its own power rather than vanishing.**
        // It keeps drifting through its own death throes, then flies off the
        // top and is culled by `enemy_step` like anything else that leaves the
        // field -- which is also what clears the way for a stage to carry on
        // after a *midboss*, since the difference between the two is one flag
        // on the definition and not two code paths.
        _b.death_t++;
        boss_drift(_e);
        if (_b.death_t == 90) {
            enemy_leave(_e, 90);
            _e.vy = -7;
        }
        return;
    }

    // **A spell declares itself before it fires.** The boss drifts, the
    // banner flies and the eye card holds, and the phase clock has not
    // started -- so the attack gets its full time either way and the player
    // gets the moment the card is announcing. It is above the attack rather
    // than inside it so that no pattern has to remember to do it, which is
    // the same reason the delay marks live in `fire` rather than in every
    // boss that fires a wall.
    if (_b.lead_t > 0) {
        _b.lead_t--;
        boss_drift(_e);
        return;
    }

    boss_drift(_e);

    var _p = boss_phase(_e);
    if (_p == undefined) return;

    _p.attack(_e, _g, _b.phase_t);
    _b.phase_t++;

    // **Health first, then time.** A boss brought to the threshold on the same
    // frame its timer expires has been beaten, not survived, and checking the
    // other way round would quietly deny the capture bonus on the one attempt
    // that most deserved it.
    if (_e.hp <= boss_phase_floor(_e)) {
        boss_end_phase(_e, _g, true);
    } else if (_p.time > 0 && _b.phase_t >= _p.time) {
        boss_end_phase(_e, _g, false);
    }
}

/// @desc The drift. A boss that stood still would make every aimed pattern it
///       fires leave from the same pixel, and the player would learn the pixel
///       rather than the pattern.
///       **How far it wanders is a property of the field, not of the boss.**
///       At 210 pixels either side of centre on a 1920-wide screen a boss
///       patrols the middle ninth of it and everything aimed leaves from
///       roughly the same place, which is the thing drifting was supposed to
///       prevent. `BOSS_DRIFT_X` is wide enough that the player has to keep
///       turning round to find him.
function boss_drift(_e) {
    var _b = _e.boss;
    _b.drift_t++;
    var _x = _b.home_x + dsin(_b.drift_t * 0.55) * BOSS_DRIFT_X;
    var _y = _b.home_y + dsin(_b.drift_t * 0.93) * BOSS_DRIFT_Y;
    _e.x += (_x - _e.x) * BOSS_DRIFT_RATE;
    _e.y += (_y - _e.y) * BOSS_DRIFT_RATE;
}

/// @desc Start attack `_i`. Sets up the ceremony a spell gets and a non-spell
///       does not.
function boss_enter_phase(_e, _g, _i) {
    var _b = _e.boss;
    _b.phase = _i;
    _b.phase_t = 0;
    _b.hits_this_phase = 0;
    _b.bombs_this_phase = 0;

    if (_i >= array_length(_b.phases)) {
        boss_finish(_e, _g);
        return;
    }

    var _p = _b.phases[_i];
    // **A non-spell opens at once and a spell waits for its card.** The
    // pause between attacks is the breathing room a non-spell gets; a spell
    // gets that and its declaration, which is the difference the ceremony is
    // there to draw.
    _b.lead_t = 0;
    if (_p.kind == AttackKind.Spell) {
        _b.lead_t = BOSS_SPELL_LEAD;
        _b.banner_t = BOSS_SPELL_BANNER;
        _b.eye_t = BOSS_EYE_TIME;
        fx_flash_screen(global.bullet_colour[_p.col], 0.5);
        fx_ring(_e.x, _e.y, 30, 640, 44, global.bullet_colour[_p.col], 1.0);
        fx_shake(11);
        if (_g != undefined) {
            _g.spell_bg = _p.bg;
            // Read through the accessor rather than with a dot, so a boss
            // definition written before styles existed gets the fallback
            // instead of throwing. A missing struct member is not `undefined`
            // in GML -- it raises -- which is the same trap the note about
            // globals in `obj_boot` is about.
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

    // Pull health down to the floor even on a timeout, so the bar can never
    // disagree with which attack the boss is on. Without it, surviving a
    // spell leaves the bar above a notch that has already been passed.
    _e.hp = min(_e.hp, boss_phase_floor(_e));

    var _swept = bullet_clear_all(true);
    laser_clear_all();

    var _col = (_p == undefined) ? COL_GRAZE : global.bullet_colour[_p.col];
    fx_flash_screen(c_white, 0.65);
    fx_shake(18);
    fx_ring(_e.x, _e.y, 20, 520, 40, _col, 1.0);
    fx_ring(_e.x, _e.y, 10, 300, 26, c_white, 0.8);
    fx_burst(_e.x, _e.y, 34, 3, 13, _col, 40, 20);

    // The drop for clearing an attack. Health as well as special: a fight this
    // long has to be survivable by somebody who is losing it slowly.
    item_drop_spread(_e.x, _e.y, 6, 10, 8);

    if (_g != undefined) {
        _g.tally += (_p != undefined && _p.kind == AttackKind.Spell)
                    ? TALLY_SPELL_CLEAR : TALLY_PHASE_CLEAR;
        _g.tally += _swept * 10;

        // **A capture needs the spell beaten *and* untouched.** That is the
        // Touhou rule and it is the right one: a bonus for merely surviving
        // rewards hiding in a corner, and this rewards beating it cleanly.
        if (_beaten && _p != undefined && _p.kind == AttackKind.Spell
            && _b.hits_this_phase == 0 && _b.bombs_this_phase == 0) {
            _b.captured++;
            _g.tally += TALLY_SPELL_CLEAR;
            fx_text(FIELD_CX, FIELD_CY - 120, "SPELL CAPTURED", COL_GRAZE,
                    96, 2.4);
        }
        // **The mark for this attack, filed here because this is the only
        // place that knows how it ended.** Everything a grade needs is already
        // on the boss -- whether it was beaten or timed out, how many times
        // the player was hit and how many sigils they spent -- so grading is a
        // read rather than a new piece of bookkeeping. See `rank_for_attack`.
        //
        // A non-spell has no name (see `ziggy_phases`), so the label is the
        // boss's plus which pass it was -- "ZIGGY 3". The boss's name alone
        // was the first version and it put three identical rows in the ledger,
        // which reads as the list having repeated itself rather than as three
        // encounters that happened to be against the same thing. A non-spell
        // is the boss's handwriting rather than a sentence, and numbering the
        // passes is the honest way to say that in a list.
        var _frac = (_p != undefined && _p.time > 0)
            ? clamp(1 - _b.phase_t / _p.time, 0, 1) : 0;
        var _spell = (_p != undefined && _p.kind == AttackKind.Spell);
        var _label = (_spell && _p.name != "")
            ? _p.name
            : (_b.def.name + " " + string(_b.phase + 1));
        // **`_g[$ "marks"]`, not `_g.marks`.** A missing struct member in GML
        // *raises*; it does not read as `undefined`. The suites drive a boss
        // with a stub controller, so a bare read here turns "this run has no
        // ledger" into a crash in the middle of an unrelated assertion --
        // which is the same trap the note about globals in `obj_boot` is
        // about, and `rank_note` already answers to `undefined`.
        rank_note(_g[$ "marks"], _label,
                  rank_for_attack(_beaten, _b.hits_this_phase,
                                  _b.bombs_this_phase, _frac), _spell);

        // **The run is told the attack ended, because this is the only place
        // that knows how it ended.** `_beaten` is the difference between a
        // spell broken and a spell survived, and it is not recoverable
        // afterwards: the line above pulls the health down to the threshold on
        // a timeout as well, precisely so the bar cannot disagree with which
        // attack the boss is on -- which means a watcher comparing health
        // against the floor sees the same number either way.
        //
        // It is the third hook of exactly this shape, beside `on_boss_beaten`
        // and `on_player_hit`, and it keeps the same direction: the boss
        // decides, the run reacts. Attack practice is what reacts today -- it
        // ends the attempt here instead of letting `clear_t` hand over to the
        // next attack -- and a per-attack replay or a training log would hang
        // off the same line.
        //
        // **`_g[$ ...]`, not `_g.on_phase_end`.** The suites drive a boss with
        // a stub controller, and a missing struct member in GML raises rather
        // than reading as `undefined` -- the same trap the note beside
        // `_g[$ "marks"]` above is about.
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

/// @desc Tell the boss the player was hit or bombed during this attack, so the
///       capture bonus knows. Called from the run rather than found here,
///       because the boss cannot see the player's health.
function boss_note_hit(_e) {
    if (_e != undefined && _e.boss != undefined) _e.boss.hits_this_phase++;
}

function boss_note_bomb(_e) {
    if (_e != undefined && _e.boss != undefined) _e.boss.bombs_this_phase++;
}

/// @desc Seconds left on the current attack, or -1 if it is untimed. What the
///       clock in the corner of the HUD prints.
function boss_time_left(_e) {
    var _p = boss_phase(_e);
    if (_p == undefined || _p.time <= 0) return -1;
    return max(0, (_p.time - _e.boss.phase_t)) / FPS;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc The boss itself: its aura, its sprite, and the sigil under it.
function boss_draw(_e) {
    var _b = _e.boss;
    var _col = global.bullet_colour[_b.def.col];
    var _t = _e.t;

    // The sigil: a slow counter-rotating pair of rings on the floor beneath
    // the boss. It is the cheapest possible way to say "this one is not
    // fodder" and it is what marks the boss's position when its sprite is lost
    // behind its own pattern.
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
