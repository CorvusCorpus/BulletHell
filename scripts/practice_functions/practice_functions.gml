/// @desc Attack practice: one of a boss's attacks, on its own, over and over.
///
/// **This is Touhou's spell practice, and it is the only thing in the game
/// that is not a stage.** Everything else here is Cuphead's shape -- a stage
/// is played in isolation and a clear is permanent -- and that shape already
/// answers "I do not want to replay four stages to reach this boss". What it
/// does not answer is "I do not want to replay four minutes of waves and six
/// attacks to reach *this attack*", which is the loop anybody tuning a pattern
/// is actually in, whether they are playing it or writing it.
///
/// **A practice run is an ordinary run with two things taken away and one
/// added.** The timeline is empty, the boss is put straight onto the field on
/// the chosen attack, and that attack ends the attempt rather than handing
/// over to the next one. Everything else -- the console, the ledger, the spell
/// ceremony, the background, the grading -- is the game's, untouched, because
/// the whole point is to look at the thing that will ship rather than at a
/// diagnostic view of it.
///
/// So it is written as a mode rather than as a debug menu. The two are the
/// same work and only one of them is worth keeping.
///
/// **The request is a struct in a global and `obj_game` reads it in Create.**
/// That is the seam `global.stage_def` already uses to say which stage the
/// rack chose, for the same reason: a room transition carries nothing with it,
/// so what the next room is about has to be written somewhere that outlives
/// the room. `undefined` is the whole of "this is an ordinary run", and
/// nothing else has to test for it.

/// How a practice attempt finished. **Timing out is not dying and neither is
/// breaking it**, and the panel that says so has to tell the three apart -- a
/// spell survived to the clock is a real result in this genre, and reporting
/// it as a loss would be a lie about the rules the fight is played under.
enum PracticeEnd {
    Beaten,      // broken inside its clock
    TimedOut,    // the clock ran out with the boss still on it
    Died,        // the player lost the attempt
}

// ---------------------------------------------------------------------------
// What can be practised
// ---------------------------------------------------------------------------

/// @desc The bosses on a stage, as `{name, spawn, phases}`.
///
///       **Read through the accessor, because most stages have none.** Seven
///       of the eight entries on the rack are unbuilt, and a bare
///       `_def.bosses` on one of those does not answer `undefined` -- a
///       missing struct member in GML *raises*. Same trap as the note about
///       globals in `obj_boot`, one struct over.
function practice_bosses(_def) {
    if (_def == undefined) return [];
    return _def[$ "bosses"] ?? [];
}

/// @desc Can this stage be practised at all?
///
///       **Built, and nothing else.** It is deliberately not gated on the
///       stage being unlocked or on the attack having been reached, which is
///       what Touhou does: the rack's locks exist to pace a first playthrough,
///       and this mode exists so an attack can be drilled or tuned. Gating a
///       tuning tool behind the progression it is used to tune is a circle.
function practice_available(_def) {
    return array_length(practice_bosses(_def)) > 0;
}

/// @desc What an attack is called in a list.
///
///       **A non-spell has no name** -- see `ziggy_phases` -- so it is filed
///       under the boss's, numbered by which pass it is, exactly as the ledger
///       files it in `boss_end_phase`. Two readouts naming the same encounter
///       two different ways is how a list stops being one.
function practice_attack_label(_boss, _phases, _i) {
    var _p = _phases[_i];
    if (_p.kind == AttackKind.Spell && _p.name != "") return _p.name;
    return _boss.name + " " + string(_i + 1);
}

/// @desc How far down the attack list is scrolled, given where it was.
///
///       **It moves only when the cursor would leave the window**, and then
///       only far enough to keep `_margin` of list on the far side of it -- a
///       list that recentred on every keypress would move under the eye the
///       whole time, where this one sits still while the cursor walks and
///       turns the page only at the edge. The margin is what keeps a boss's
///       heading in view above his first attack.
///
///       Everything is in list coordinates: `_sel` is the chosen row's centre
///       measured from the first row's, `_span` is the last row's, and
///       `_window` is how much of that span the plate can show at once. A list
///       that fits answers zero whatever it is asked.
function practice_list_scroll(_scroll, _sel, _span, _window, _margin) {
    var _max = max(0, _span - _window);
    var _m = min(_margin, _window * 0.5);
    var _want = clamp(_scroll, _sel + _m - _window, _sel - _m);
    return clamp(_want, 0, _max);
}

// ---------------------------------------------------------------------------
// The best on an attack, this session
// ---------------------------------------------------------------------------
//
// **Kept in memory and never written to disk, which is the whole design.** A
// score on one attack is not a stage result and `progress_record` must not be
// able to hear about it -- a stage marked cleared because somebody drilled its
// first non-spell would be permanent, silent and wrong. But a console with a
// BEST row reading zero forever is a dead readout in the one place the player
// is looking, and "am I doing better than last time" is precisely the question
// somebody retrying an attack is asking.
//
// So it lives for as long as the process does. That is honest about what it
// is: a session's worth of attempts at one pattern, which is the unit anybody
// drilling or tuning works in anyway.

/// @desc What an attack is filed under. The stage, the boss and the phase --
///       an index alone would move under the map the first time a phase was
///       inserted into a table, which is a thing this mode exists to make easy.
function practice_key(_stage, _boss_i, _phase_i) {
    // A card with no id -- the drafting table, the old draft of stage three
    // -- is filed under its name, or every one of them would share one best.
    var _who = (_stage.id != "") ? _stage.id : _stage.name;
    return _who + "/" + string(_boss_i) + "/" + string(_phase_i);
}

function practice_best(_key) {
    return global.practice_best[$ _key] ?? 0;
}

/// @desc File a score against an attack, keeping the higher.
///
///       **The map only.** The definition the console is reading is left where
///       it was, because BEST during an attempt has to mean the best *before*
///       it -- writing this attempt's score into it the moment the attack ends
///       would have BEST and SCORE converge on the same number while the
///       player watched, which says nothing and looks like a bug. The next run
///       picks it up through `practice_seed_best`.
function practice_note_best(_p, _tally) {
    if (_p == undefined) return;
    var _key = practice_key(_p.stage, _p.boss_i, _p.phase_i);
    global.practice_best[$ _key] = max(practice_best(_key), _tally);
}

/// @desc Refresh a request's definition with the best so far. Called at the
///       start of every run, because a retry is a room restart and reuses the
///       request struct it started with -- so the number in it is as old as
///       the first attempt unless somebody asks the map again.
function practice_seed_best(_p) {
    if (_p == undefined) return;
    _p.def.best = practice_best(practice_key(_p.stage, _p.boss_i, _p.phase_i));
}

// ---------------------------------------------------------------------------
// The request
// ---------------------------------------------------------------------------

/// @desc The empty timeline a practice run plays.
///
///       **An empty stage rather than a suppressed one.** `obj_game` builds a
///       stage from its definition and steps it every frame, and the honest
///       way to have no waves is a timeline with no events in it -- which
///       `stage_step` marks done on its first frame and never looks at again.
///       The alternative is a `practice` test inside `stage_step`, which puts
///       a mode's name inside a rule that has nothing to do with the mode.
function practice_empty_script() {
    return [];
}

/// @desc Describe one attack to practise. What `obj_game` reads out of
///       `global.practice`.
///
///       **The definition it carries is stage-def shaped**, so the run, the
///       console and the background all take it without knowing this mode
///       exists. `name` and `subtitle` are the attack and who is casting it,
///       which is what the head of the console should say when the stage is
///       not the subject. `encounters` is 1 because a practice attempt has
///       exactly one graded encounter in it, and a row of fourteen sockets
///       would be a promise of thirteen more.
///
///       `id` is empty on purpose. It is the key `progress_stage` reads and
///       `progress_record` writes, and a practice attempt is not a stage
///       result: it must not be able to file one, and it has no best to show.
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
            // The console's BEST row reads this in preference to the saved
            // stage record, which a practice run does not have and must not
            // write. See `practice_note_best` and `hud_draw_score`.
            best: practice_best(practice_key(_stage, _boss_i, _phase_i)),
        },
    };
}

// ---------------------------------------------------------------------------
// Running one
// ---------------------------------------------------------------------------

/// @desc Put the boss on the field, already fighting the chosen attack.
///
///       **Every step of this is one of the game's own verbs**, which is the
///       discipline `shot_boss` keeps in `shot_scenes` and for the same
///       reason: a state assembled by hand is a state the game cannot reach,
///       and practising one would be practising something that is not in the
///       game. The boss is spawned by its own spawner and started by
///       `boss_enter_phase`, so the spell's banner, its eye card and its
///       background all arrive exactly as they do in a fight.
///
///       What *is* skipped is the arrival glide and the boss's name splash.
///       Those belong to the stage: they are the ceremony of the boss turning
///       up, and it has already turned up. The spell's own ceremony is kept,
///       because that is a property of the attack and the attack is the
///       subject.
///
///       The health starts where the attack does, so the attack is fought
///       over exactly the health it is fought over in a stage and breaks at
///       the same threshold. **What the rail shows is the attack alone** --
///       100.0 to 0.0 rather than the stretch of the fight it occupies -- and
///       that is the HUD's reading of the same numbers, not a change to them:
///       see `hud_boss_span`.
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

    // **And the world the boss is fought in, not the one the stage opens
    // on.** A boss entry says `turned` when it comes after its stage's turn;
    // see `bg_skip_to_boss`. Guarded because the suites start runs with no
    // background at all.
    var _bg = _g[$ "bg"];
    if (_bg != undefined) bg_skip_to_boss(_bg, _boss[$ "turned"] ?? false);

    // **The attack does not start on frame one, and this is the boss's own
    // pause rather than a new one.** An attack opening the instant the room
    // does gives the player no time to read where the boss is or to get off
    // the spawn point, and in a mode whose whole purpose is repetition that is
    // a tax paid on every attempt. In a fight the beat already exists: an
    // attack is entered out of `clear_t`, from wherever the last one left you.
    //
    // So practice arrives *in* that pause. `phase` stays at -1 so nothing
    // names an attack that has not begun -- the alternative, sitting on
    // `phase_i - 1`, would have the bar counting down the previous attack's
    // clock -- and `next_phase` is what the pause hands over to.
    _e.boss.phase = -1;
    _e.boss.next_phase = _p.phase_i;
    _e.boss.clear_t = PRACTICE_READY;

    // **Full life and full sigil, every attempt.** A practice attempt is about
    // the attack and not about what the four minutes before it left behind, and
    // starting one on whatever health a stage happened to hand over would make
    // two attempts at the same pattern incomparable. The sigil is full for the
    // same reason pointed the other way: a bomb is part of how a spell is
    // fought, and an attack that could only be rehearsed without one is an
    // attack whose real answer cannot be rehearsed.
    _g.player.hp = HP_MAX;
    _g.player.mp = MP_MAX;
    return _e;
}

/// @desc How an attempt ended, read off the fight that ended it.
///
///       **Every input already exists**, which is what `rank_for_attack` is
///       built on too: a phase that has ended knows whether it was broken, how
///       many times the player was hit during it and how many sigils they
///       spent. The panel is a read, not a second set of books.
function practice_outcome(_e, _how, _ledger) {
    var _b = (_e == undefined) ? undefined : _e.boss;
    var _p = (_e == undefined) ? undefined : boss_phase(_e);
    var _n = rank_count(_ledger);

    return {
        how: _how,
        hits: (_b == undefined) ? 0 : _b.hits_this_phase,
        bombs: (_b == undefined) ? 0 : _b.bombs_this_phase,
        spell: (_p != undefined && _p.kind == AttackKind.Spell),
        // The mark the fight just filed, or none -- which is what dying is,
        // since an attempt that ended before the phase did was never graded.
        tier: (_n > 0) ? _ledger.marks[_n - 1].tier : -1,
    };
}

/// @desc The headline the result panel prints.
function practice_end_name(_r) {
    if (_r == undefined) return "";
    switch (_r.how) {
        case PracticeEnd.Beaten:
            // **Captured is a different word from broken, and the distinction
            // is the whole of the genre's scoring.** A spell broken while
            // untouched is the thing being practised *for*; telling somebody
            // who has just managed it that they cleared it would report the
            // good outcome as the ordinary one.
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
