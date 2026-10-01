/// @desc Practice (Touhou-style spell practice): play one boss attack, one
///       whole boss fight, or one wave of fodder on its own, repeatedly.
///
/// A practice run is an ordinary run with a short timeline of its own:
///   - an attack: an empty timeline, the boss placed straight onto the chosen
///     attack, and that attack ending the attempt;
///   - a whole fight: the boss arriving as it does in the stage, and its
///     defeat ending the attempt;
///   - a wave: that wave's slice of the stage's timeline, and its gate
///     releasing ending the attempt.
/// Everything else (console, grading, spell ceremony, background) is the
/// normal game. The request is `global.practice`, read by `obj_game`'s Create
/// (`undefined` means an ordinary run).

/// What a practice request plays.
enum PracticeMode {
    Attack,      // one boss attack
    Fight,       // one boss, every attack
    Wave,        // one wave of fodder
}

/// How a practice attempt finished.
enum PracticeEnd {
    Beaten,      // broken inside its clock
    TimedOut,    // the clock ran out with the boss still on it
    Died,        // the player lost the attempt
    Cleared,     // a whole fight won, or a wave got through
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

/// @desc A stage cut into what can be practised besides single attacks, in
///       the order the stage plays them: `{kind: "wave", n, events, turned}`
///       and `{kind: "boss", boss_i}`. The timeline is cut at its gates; a
///       stretch that brings a boss on is that boss's, and one with anything
///       else in it is a wave. Waves are numbered as the stage grades them
///       ("WAVE 3"). `events` are the wave's own entries (not the title card,
///       sweeps or background turns), `turned` whether the background has
///       turned by then. A boss the timeline never brings on (the drafting
///       table has no timeline) is listed after the rest.
function practice_segments(_def) {
    var _out = [];
    var _bosses = practice_bosses(_def);
    var _nb = array_length(_bosses);
    var _placed = array_create(_nb, false);
    var _build = (_def == undefined) ? undefined : _def[$ "build"];
    var _events = (_build == undefined) ? [] : _build();

    var _turned = false;
    var _n = 0;
    var _boss_i = -1;
    var _body = [];
    var _spawns = 0;
    var _count = array_length(_events);
    for (var _i = 0; _i < _count; _i++) {
        var _e = _events[_i];
        var _role = ev_role(_e);
        if (_role == "boss") {
            if (_boss_i < 0) {
                var _maker = method_get_self(_e.fn).spec.maker;
                for (var _k = 0; _k < _nb; _k++) {
                    if (_bosses[_k].spawn == _maker) _boss_i = _k;
                }
            }
        } else if (_role == "omen") {
            _turned = true;
        } else if (_role == "rewind") {
            _turned = false;
        } else if (_role == "") {
            array_push(_body, _e);
            if (!_e.gate && !_e.wave) _spawns++;
        }

        // A stretch ends at a gate, or at the end of the timeline.
        if (!_e.gate && _i < _count - 1) continue;
        if (_boss_i >= 0) {
            if (!_placed[_boss_i]) {
                array_push(_out, { kind: "boss", boss_i: _boss_i });
                _placed[_boss_i] = true;
            }
        } else if (_spawns > 0) {
            _n++;
            array_push(_out, { kind: "wave", n: _n, events: _body,
                               turned: _turned });
        }
        _boss_i = -1;
        _body = [];
        _spawns = 0;
    }

    for (var _k = 0; _k < _nb; _k++) {
        if (!_placed[_k]) array_push(_out, { kind: "boss", boss_i: _k });
    }
    return _out;
}

/// @desc Wave `_n` of a stage (as `practice_segments` numbers them), or
///       `undefined`.
function practice_wave(_def, _n) {
    var _seg = practice_segments(_def);
    for (var _i = 0; _i < array_length(_seg); _i++) {
        if (_seg[_i].kind == "wave" && _seg[_i].n == _n) return _seg[_i];
    }
    return undefined;
}

/// @desc The timeline that replays wave `_n` alone: its own entries, moved
///       so the first comes at frame 30. Built fresh for every run, since a
///       retry must not share event structs with the last attempt.
function practice_wave_events(_def, _n) {
    var _w = practice_wave(_def, _n);
    if (_w == undefined) return [];
    var _events = _w.events;
    var _shift = 30 - _events[0].at;
    for (var _i = 0; _i < array_length(_events); _i++) {
        _events[_i].at += _shift;
    }
    return _events;
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
///       A whole fight passes "fight" as its phase, and a wave passes "wave"
///       as its boss and its number as its phase.
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
    global.practice_best[$ _p.key] = max(practice_best(_p.key), _tally);
}

/// @desc Refresh a request's `def.best` from the map. Called at the start of
///       every run, because a retry reuses the same request struct.
function practice_seed_best(_p) {
    if (_p == undefined) return;
    _p.def.best = practice_best(_p.key);
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
    var _key = practice_key(_stage, _boss_i, _phase_i);

    return {
        mode: PracticeMode.Attack,
        stage: _stage,
        boss_i: _boss_i,
        phase_i: _phase_i,
        wave_n: 0,
        turned: _boss[$ "turned"] ?? false,
        label: _label,
        key: _key,
        def: {
            id: "",
            name: _label,
            subtitle: _boss.name + "   " + _stage.name,
            needs: 0,
            make_bg: _stage.make_bg,
            build: practice_empty_script,
            music: _stage[$ "music"],
            encounters: 1,
            // The console's BEST row reads this instead of the save
            // (`hud_draw_score`).
            best: practice_best(_key),
        },
    };
}

/// @desc Describe one boss's whole fight to practise: the boss arrives as
///       in the stage and every attack is played. `phase_i` is -1, so the
///       health rail spans the whole fight (`hud_boss_span`).
function practice_new_fight(_stage, _boss_i) {
    var _boss = practice_bosses(_stage)[_boss_i];
    var _key = practice_key(_stage, _boss_i, "fight");
    return {
        mode: PracticeMode.Fight,
        stage: _stage,
        boss_i: _boss_i,
        phase_i: -1,
        wave_n: 0,
        turned: _boss[$ "turned"] ?? false,
        label: _boss.name,
        key: _key,
        def: {
            id: "",
            name: _boss.name,
            subtitle: "WHOLE FIGHT   " + _stage.name,
            needs: 0,
            make_bg: _stage.make_bg,
            build: method({ spawn: _boss.spawn }, function() {
                return [ev(30, wave_boss(spawn))];
            }),
            music: _stage[$ "music"],
            encounters: array_length(_boss.phases()),
            best: practice_best(_key),
        },
    };
}

/// @desc Describe one wave to practise: wave `_n` of the stage's timeline
///       (`practice_segments`), played alone.
function practice_new_wave(_stage, _n) {
    var _w = practice_wave(_stage, _n);
    var _label = "WAVE " + string(_n);
    var _key = practice_key(_stage, "wave", _n);
    return {
        mode: PracticeMode.Wave,
        stage: _stage,
        boss_i: -1,
        phase_i: -1,
        wave_n: _n,
        turned: (_w != undefined) && _w.turned,
        label: _label,
        key: _key,
        def: {
            id: "",
            name: _label,
            subtitle: _stage.name,
            needs: 0,
            make_bg: _stage.make_bg,
            build: method({ stage: _stage, n: _n }, function() {
                return practice_wave_events(stage, n);
            }),
            music: _stage[$ "music"],
            encounters: 1,
            best: practice_best(_key),
        },
    };
}

/// @desc Start a whole-fight or wave attempt; the timeline does the rest.
///       The background is shown as it is at that point in the stage, and
///       a wave's mark is numbered as in the stage.
function practice_begin_run(_g) {
    var _p = _g.practice;
    practice_seed_best(_p);
    var _bg = _g[$ "bg"];
    if (_bg != undefined) bg_skip_to_boss(_bg, _p.turned);
    var _s = _g[$ "stage"];
    if (_s != undefined && _p.mode == PracticeMode.Wave) {
        _s.enc_n = _p.wave_n - 1;
    }
    _g.player.hp = HP_MAX;
    _g.player.mp = MP_MAX;
}

/// @desc Has a wave attempt finished? Its timeline has run out, its gate has
///       released, and its mark is filed.
function practice_wave_done(_g) {
    var _s = _g.stage;
    return _s.done && _s.enc == undefined && enemy_count_fodder() == 0
           && ring_count() == 0;
}

// ---------------------------------------------------------------------------
// Running one
// ---------------------------------------------------------------------------

/// @desc Put the boss on the field, about to start the chosen attack. The boss
///       is made by its own spawner and the attack is entered through the
///       normal between-attacks pause, so the spell ceremony runs as in a
///       fight; the arrival glide and name card are skipped. Health starts
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

/// @desc How a whole fight or a wave attempt ended. The mark shown is the
///       lowest one the attempt filed (a wave files one); dying shows none.
function practice_outcome_run(_g, _how) {
    var _tier = -1;
    if (_how != PracticeEnd.Died) {
        var _m = _g.marks.marks;
        for (var _i = 0; _i < array_length(_m); _i++) {
            _tier = (_tier < 0) ? _m[_i].tier : min(_tier, _m[_i].tier);
        }
    }
    return {
        how: _how,
        hits: _g.player.hit_n,
        bombs: _g.player.bomb_n,
        spell: false,
        tier: _tier,
    };
}

/// @desc The word for what a request plays, for the menus ("RETRY WAVE").
function practice_mode_word(_p) {
    if (_p == undefined) return "ATTACK";
    switch (_p.mode) {
        case PracticeMode.Fight: return "FIGHT";
        case PracticeMode.Wave:  return "WAVE";
    }
    return "ATTACK";
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
        case PracticeEnd.Cleared:  return "CLEARED";
    }
    return "";
}

function practice_end_colour(_r) {
    if (_r == undefined) return COL_SILVER;
    switch (_r.how) {
        case PracticeEnd.Beaten:
        case PracticeEnd.Cleared:  return COL_GRAZE;
        case PracticeEnd.TimedOut: return COL_MANA;
        case PracticeEnd.Died:     return COL_LIFE;
    }
    return COL_SILVER;
}
