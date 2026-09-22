/// @desc Attack practice (Touhou-style spell practice): play one boss attack
///       on its own, repeatedly.
///
/// A practice run is an ordinary run with an empty timeline, the boss placed
/// straight onto the chosen attack, and that attack ending the attempt.
/// Everything else (console, grading, spell ceremony, background) is the
/// normal game. The request is `global.practice`, read by `obj_game`'s Create
/// (`undefined` means an ordinary run).

/// How a practice attempt finished.
enum PracticeEnd {
    Beaten,      // broken inside its clock
    TimedOut,    // the clock ran out with the boss still on it
    Died,        // the player lost the attempt
}

// ---------------------------------------------------------------------------
// What can be practised
// ---------------------------------------------------------------------------

/// @desc The bosses on a stage, as `{name, spawn, phases}`. Read with `[$ ]`
///       because unbuilt stages have no `bosses` field and a bare read raises.
function practice_bosses(_def) {
    if (_def == undefined) return [];
    return _def[$ "bosses"] ?? [];
}

/// @desc Can this stage be practised? Only requires the stage to have bosses
///       (not to be unlocked, and not for the attack to have been reached).
function practice_available(_def) {
    return array_length(practice_bosses(_def)) > 0;
}

/// @desc What an attack is called in a list: a spell's name, or the boss's
///       name and the attack's number (as `boss_end_phase` labels marks).
function practice_attack_label(_boss, _phases, _i) {
    var _p = _phases[_i];
    if (_p.kind == AttackKind.Spell && _p.name != "") return _p.name;
    return _boss.name + " " + string(_i + 1);
}

/// @desc The attack list's scroll offset. It only moves when the cursor would
///       come within `_margin` of the window's edge. All values are in list
///       coordinates: `_sel` is the chosen row's centre relative to the first
///       row's, `_span` the last row's, `_window` the visible height. A list
///       that fits returns 0.
function practice_list_scroll(_scroll, _sel, _span, _window, _margin) {
    var _max = max(0, _span - _window);
    var _m = min(_margin, _window * 0.5);
    var _want = clamp(_scroll, _sel + _m - _window, _sel - _m);
    return clamp(_want, 0, _max);
}

// ---------------------------------------------------------------------------
// Best score per attack, this session only (`global.practice_best`). Never
// saved: practice must not touch the save file.
// ---------------------------------------------------------------------------

/// @desc The key an attack's best is stored under: stage, boss and phase.
function practice_key(_stage, _boss_i, _phase_i) {
    // Cards with no id (drafting table, old stage three) use their name.
    var _who = (_stage.id != "") ? _stage.id : _stage.name;
    return _who + "/" + string(_boss_i) + "/" + string(_phase_i);
}

function practice_best(_key) {
    return global.practice_best[$ _key] ?? 0;
}

/// @desc File a score against an attack, keeping the higher. Updates only the
///       map, not the def the console is showing, so BEST during an attempt
///       stays the best from before it; the next run picks it up through
///       `practice_seed_best`.
function practice_note_best(_p, _tally) {
    if (_p == undefined) return;
    var _key = practice_key(_p.stage, _p.boss_i, _p.phase_i);
    global.practice_best[$ _key] = max(practice_best(_key), _tally);
}

/// @desc Refresh a request's `def.best` from the map. Called at the start of
///       every run, because a retry reuses the same request struct.
function practice_seed_best(_p) {
    if (_p == undefined) return;
    _p.def.best = practice_best(practice_key(_p.stage, _p.boss_i, _p.phase_i));
}

// ---------------------------------------------------------------------------
// The request
// ---------------------------------------------------------------------------

/// @desc The empty timeline a practice run plays (`stage_step` marks it done
///       on the first frame).
function practice_empty_script() {
    return [];
}

/// @desc Describe one attack to practise (stored in `global.practice`). Its
///       `def` is shaped like a stage def so the run, console and background
///       use it unchanged: `name` is the attack, `subtitle` the caster,
///       `encounters` 1. `id` is empty so the run can't write to the save.
function practice_new(_stage, _boss_i, _phase_i) {
    var _bosses = practice_bosses(_stage);
    var _boss = _bosses[_boss_i];
    var _phases = _boss.phases();
    var _label = practice_attack_label(_boss, _phases, _phase_i);

    return {
        stage: _stage,
        boss_i: _boss_i,
        phase_i: _phase_i,
        label: _label,
        def: {
            id: "",
            name: _label,
            subtitle: _boss.name + "   " + _stage.name,
            needs: 0,
            make_bg: _stage.make_bg,
            build: practice_empty_script,
            encounters: 1,
            // The console's BEST row reads this instead of the save
            // (`hud_draw_score`).
            best: practice_best(practice_key(_stage, _boss_i, _phase_i)),
        },
    };
}

// ---------------------------------------------------------------------------
// Running one
// ---------------------------------------------------------------------------

/// @desc Put the boss on the field, about to start the chosen attack. The boss
///       is made by its own spawner and the attack is entered through the
///       normal between-attacks pause, so the spell ceremony runs as in a
///       fight; the arrival glide and name splash are skipped. Health starts
///       where the attack starts in the full fight (the HUD shows the attack's
///       own span as 100 to 0; see `hud_boss_span`).
function practice_begin(_g) {
    var _p = _g.practice;
    practice_seed_best(_p);
    var _boss = practice_bosses(_p.stage)[_p.boss_i];

    var _e = _boss.spawn(_g);
    if (_e == undefined) return undefined;

    _g.boss_ref = _e;
    _e.boss.entry_t = 0;
    _e.boss.declare_t = 0;
    _e.boss.started = true;
    _e.x = _e.boss.home_x;
    _e.y = _e.boss.home_y;
    _e.touch = true;

    if (_p.phase_i > 0) {
        _e.hp = _e.hp_max * _e.boss.phases[_p.phase_i - 1].hp_end;
    }

    // Show the background as it is when this boss is fought (`turned` on the
    // boss entry means after the stage's mid-point turn). Guarded because
    // suites start runs with no background.
    var _bg = _g[$ "bg"];
    if (_bg != undefined) bg_skip_to_boss(_bg, _boss[$ "turned"] ?? false);

    // Start in the between-attacks pause (`PRACTICE_READY` frames) so the
    // player has time to position. `phase` stays -1 until the attack begins,
    // so the HUD doesn't show the previous attack's clock.
    _e.boss.phase = -1;
    _e.boss.next_phase = _p.phase_i;
    _e.boss.clear_t = PRACTICE_READY;

    // Full life and full sigil on every attempt.
    _g.player.hp = HP_MAX;
    _g.player.mp = MP_MAX;
    return _e;
}

/// @desc How an attempt ended, for the result panel: how, hits and bombs in
///       the phase, whether it was a spell, and the mark filed (-1 if none).
function practice_outcome(_e, _how, _ledger) {
    var _b = (_e == undefined) ? undefined : _e.boss;
    var _p = (_e == undefined) ? undefined : boss_phase(_e);
    var _n = rank_count(_ledger);

    return {
        how: _how,
        hits: (_b == undefined) ? 0 : _b.hits_this_phase,
        bombs: (_b == undefined) ? 0 : _b.bombs_this_phase,
        spell: (_p != undefined && _p.kind == AttackKind.Spell),
        // The last mark filed, or -1 (dying ends the attempt ungraded).
        tier: (_n > 0) ? _ledger.marks[_n - 1].tier : -1,
    };
}

/// @desc The headline the result panel prints.
function practice_end_name(_r) {
    if (_r == undefined) return "";
    switch (_r.how) {
        case PracticeEnd.Beaten:
            // A spell broken with no hits or bombs is a capture.
            if (_r.spell && _r.hits == 0 && _r.bombs == 0) return "CAPTURED";
            return "BROKEN";
        case PracticeEnd.TimedOut: return "SURVIVED";
        case PracticeEnd.Died:     return "DEFEATED";
    }
    return "";
}

function practice_end_colour(_r) {
    if (_r == undefined) return COL_SILVER;
    switch (_r.how) {
        case PracticeEnd.Beaten:   return COL_GRAZE;
        case PracticeEnd.TimedOut: return COL_MANA;
        case PracticeEnd.Died:     return COL_LIFE;
    }
    return COL_SILVER;
}
