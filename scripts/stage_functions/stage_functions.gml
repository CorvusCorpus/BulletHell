/// @desc A stage is a timeline, and the timeline is data.
///
/// **Every stage is a list of `{at, fn}` and nothing else.** A stage runs for
/// five to ten minutes and is made of two dozen scripted moments, so the
/// alternative is a two-hundred-line `switch` on a frame counter -- which is
/// the same list with the structure taken out of it, and which cannot be
/// inspected, reordered, or asserted on. `test_stage` walks the table and
/// checks it is sorted and that its boss arrives after its midboss, neither of
/// which is possible against a `switch`.
///
/// **A gate stops the clock rather than skipping ahead.** The shape a stage
/// actually wants is "spawn these, wait until they are gone, spawn the next
/// lot" -- and a wave that takes longer than expected must not have the next
/// one land on top of it. So a gate freezes stage time until the field is
/// clear, which means every `at` after it stays true to the time the designer
/// wrote, measured from where the gate released.
///
/// **The stage does not own the boss's attacks.** It spawns the boss and stops
/// existing; the phase table takes over. That split is what lets a boss be
/// tested without a stage and a stage be tested without a boss.

/// @desc Build a run of a stage from its definition.
function stage_new(_def) {
    var _events = _def.build();
    return {
        def: _def,
        events: _events,
        cursor: 0,
        t: 0,
        gated: false,
        gate_grace: 0,     // frames a gate waits before it starts believing
        done: false,
        // **How many graded encounters this stage holds**, counted from the
        // timeline it just built rather than written down beside it. See
        // `stage_count_encounters`.
        encounters: _def[$ "encounters"] ?? stage_count_encounters(_def, _events),
        // The open encounter, or `undefined` between them. See
        // `stage_encounter_step`.
        enc: undefined,
        enc_n: 0,
    };
}

/// @desc How many encounters a stage contains, before any of them happen.
///
///       **The console draws a socket per encounter**, so it needs the total
///       before the first one has been fought -- that is what says how long
///       this is going to be and how much of it is left, and it is most of
///       why the marks block never reads as empty.
///
///       This used to be a hand-written `encounters` field on every stage
///       definition, standing in for a count nothing could take. It was wrong
///       on stage one from the day it was typed -- fourteen against a true
///       thirteen -- which is what a number maintained by hand in a different
///       file from the thing it counts always eventually is.
///
///       Both halves are countable now:
///
///       - **A group of waves is a gate.** A gate holds the clock until the
///         field is clear, which is exactly the end of an encounter, and the
///         next spawn after it is the beginning of the next one. Every stage
///         also gates immediately after a *boss*, and that gate closes nothing
///         -- so the boss-gates are subtracted, and the number of them is the
///         number of bosses that are not the last one, because the last boss
///         ends the stage rather than handing back to it.
///       - **A boss's encounters are its attacks**, which is what
///         `stage_def.bosses` already lists for attack practice.
///
///       A definition may still carry its own `encounters` and override the
///       lot, which is what the practice, draft and preview cards do: their
///       timelines are empty or synthetic and there is nothing to count.
function stage_count_encounters(_def, _events) {
    var _gates = 0;
    for (var _i = 0; _i < array_length(_events); _i++) {
        if (_events[_i].gate) _gates++;
    }

    var _bosses = _def[$ "bosses"] ?? [];
    var _nb = array_length(_bosses);
    var _total = max(0, _gates - max(0, _nb - 1));

    for (var _i = 0; _i < _nb; _i++) {
        var _mk = _bosses[_i][$ "phases"];
        if (_mk == undefined) continue;
        _total += array_length(_mk());
    }
    return _total;
}

/// @desc One timed event.
function ev(_at, _fn) {
    return { at: _at, fn: _fn, gate: false };
}

/// @desc Hold the clock until every fodder enemy is gone.
function ev_gate(_at) {
    return { at: _at, fn: undefined, gate: true };
}

/// @desc Watch for a group of waves beginning and ending, and grade it.
///
/// **A wave had no beginning, no end and no outcome, and that is the whole of
/// why the marks block was half a readout.** Giving it those turned out not to
/// need a new kind of timeline entry: a group of waves is exactly the stretch
/// during which there is fodder on the field, which is the same predicate a
/// gate already tests. So an encounter opens on the frame fodder appears and
/// closes on the frame the last of it is gone.
///
/// **Detected rather than declared**, deliberately. The alternative was a call
/// inside `wave_line` and `wave_cross` announcing themselves, and a wave shape
/// written next year would have had to remember to make it -- where a shape
/// that forgets this one is simply not counted, silently, which is the class
/// of bug `test_corridor` walks the background struct to avoid rather than
/// naming the rings it knows about.
///
/// Everything it needs is a difference between two snapshots, which is why
/// nothing anywhere had to start keeping books: the score, the hits, the bombs
/// and what the enemies were worth are all running totals already.
function stage_encounter_step(_s, _g) {
    var _live = (_g[$ "boss_ref"] == undefined) && enemy_count_fodder() > 0;

    if (_s.enc == undefined) {
        // **Not during a boss.** A boss that summons fodder is still a boss
        // encounter, graded by its own phase table, and an attack that opened
        // a second mark underneath itself would file two marks for one thing.
        if (!_live) return;
        _s.enc_n++;
        _s.enc = {
            // **Frames the encounter was open, not stage time.** `_s.t` is
            // frozen for the whole of a gate, and a gate is where most of a
            // wave group is actually fought -- so stage time would measure
            // the stretch from the spawn to the gate's own `at` and call a
            // forty-second fight four seconds long. The target is a rate over
            // a duration, so that duration has to be the real one.
            frames: 0,
            tally0: _g.tally,
            hits0: _g.player.hit_n,
            bombs0: _g.player.bomb_n,
            worth0: global.enemy_worth,
            n: _s.enc_n,
        };
        return;
    }

    if (_live) {
        _s.enc.frames++;
        return;
    }
    stage_encounter_close(_s, _g);
}

/// @desc File the mark for the group that has just finished.
function stage_encounter_close(_s, _g) {
    var _e = _s.enc;
    if (_e == undefined) return;
    _s.enc = undefined;

    var _earned = _g.tally - _e.tally0;
    var _hits = _g.player.hit_n - _e.hits0;
    var _bombs = _g.player.bomb_n - _e.bombs0;
    var _worth = global.enemy_worth - _e.worth0;
    var _target = rank_wave_target(_worth, _e.frames);

    // **"WAVE 3" rather than the stage's name.** A non-spell borrows its
    // caster's name and numbers the pass for the same reason -- a list of
    // identical rows reads as the list having repeated itself rather than as
    // several encounters against the same kind of thing.
    rank_note(_g[$ "marks"], "WAVE " + string(_e.n),
              rank_for_encounter(_hits, _bombs, _earned >= _target), false,
              _earned, _target, _hits, _bombs);
}

/// @desc Advance the stage one frame.
function stage_step(_s, _g) {
    // **Before every early return below it**, which there are three of: a
    // gate holds the clock and returns, and so does a stage that has run out
    // of events -- and a group of waves can perfectly well still be on the
    // field through either. It is the same reason `sfx_step` is called from
    // the top of a controller's Step rather than wherever it reads best.
    stage_encounter_step(_s, _g);

    if (_s.done) return;

    if (_s.gated) {
        // **The grace matters.** A gate placed on the same frame as a spawn
        // would see an empty field -- the enemies do not exist until their own
        // event has run -- and release immediately, which collapses the whole
        // timeline into one frame. Half a second is longer than any spawn
        // takes and shorter than any wave.
        if (_s.gate_grace > 0) {
            _s.gate_grace--;
            return;
        }
        if (enemy_count_fodder() > 0) return;
        _s.gated = false;
    }

    _s.t++;

    while (_s.cursor < array_length(_s.events)) {
        var _e = _s.events[_s.cursor];
        if (_e.at > _s.t) break;
        _s.cursor++;
        if (_e.gate) {
            _s.gated = true;
            _s.gate_grace = 30;
            return;
        }
        _e.fn(_g);
    }

    if (_s.cursor >= array_length(_s.events) && !_s.gated) {
        _s.done = true;
    }
}

/// @desc How far through the written timeline the stage is, 0 to 1. Only ever
///       used for the loading-bar-ish tick on the pause screen; the stage
///       itself never reads it.
function stage_progress(_s) {
    var _n = array_length(_s.events);
    return (_n <= 0) ? 1 : (_s.cursor / _n);
}

// ---------------------------------------------------------------------------
// Wave shapes
//
// The handful of arrangements every stage in this game is built out of. They
// are functions that *return* an event's `fn`, so a stage's table reads as a
// list of formations at times rather than as a list of closures.
// ---------------------------------------------------------------------------

/// @desc A line of enemies that fly in, hold, fire, and leave.
///
///       The workhorse. `_fire` is called every frame with (enemy, g, t) once
///       the enemy has arrived, and `_hold` is how long it stays.
///
///       **Every coordinate here is relative to the field, not to the
///       screen.** A stage author is thinking "a hundred and forty pixels down
///       from the top of the play area", and having them write
///       `FIELD_Y0 + 140` at forty call sites is both noise and a place to
///       forget. The offset is added once, here, which also means the whole of
///       `stage_ziggy` survived the field becoming a rectangle without a
///       single number in it changing.
function wave_line(_kind, _n, _x0, _y0, _dx, _dy, _tx0, _ty0, _tdx, _tdy,
                   _hold, _hp, _col, _fire, _stagger = 8) {
    var _spec = {
        kind: _kind, n: _n,
        x0: _x0, y0: _y0, dx: _dx, dy: _dy,
        tx0: _tx0, ty0: _ty0, tdx: _tdx, tdy: _tdy,
        hold: _hold, hp: _hp, col: _col, fire: _fire, stagger: _stagger,
    };
    return method({ spec: _spec }, function(_g) {
        var _s = spec;
        for (var _i = 0; _i < _s.n; _i++) {
            var _e = enemy_spawn(_s.kind,
                                 FIELD_X0 + _s.x0 + _s.dx * _i,
                                 FIELD_Y0 + _s.y0 + _s.dy * _i,
                                 _s.hp, enemy_act_hold, _s.col, 0, 1, 2);
            if (_e == undefined) break;
            _e.mem = {
                tx: FIELD_X0 + _s.tx0 + _s.tdx * _i,
                ty: FIELD_Y0 + _s.ty0 + _s.tdy * _i,
                wait: _i * _s.stagger,
                hold: _s.hold,
                fire: _s.fire,
                arrived: false,
                fired_t: 0,
            };
        }
    });
}

/// @desc The behaviour `wave_line` installs: glide to a post, fire for a
///       while, then leave the way it is facing.
function enemy_act_hold(_e, _g) {
    var _m = _e.mem;
    if (_m.wait > 0) {
        _m.wait--;
        return;
    }

    if (!_m.arrived) {
        _m.arrived = enemy_glide(_e, _m.tx, _m.ty, 0.062);
        return;
    }

    if (_m.fire != undefined) {
        _m.fire(_e, _g, _m.fired_t);
    }
    _m.fired_t++;

    if (_m.fired_t >= _m.hold) {
        // Away from the player, so a departing wave never sweeps *through*
        // them -- an enemy body hurts, and being hit by something that had
        // stopped attacking is the least readable death in the game.
        enemy_leave(_e, (_e.x < FIELD_CX) ? 200 : 340);
    }
}

/// @desc A stream of enemies crossing the field without stopping.
///
///       `_y` is measured from the top of the field, as everything a stage
///       writes is -- see `wave_line`.
function wave_cross(_kind, _n, _from, _y, _spread, _spd, _hp, _col, _fire,
                    _stagger = 14) {
    var _spec = {
        kind: _kind, n: _n, from: _from, y: _y, spread: _spread,
        spd: _spd, hp: _hp, col: _col, fire: _fire, stagger: _stagger,
    };
    return method({ spec: _spec }, function(_g) {
        var _s = spec;
        for (var _i = 0; _i < _s.n; _i++) {
            var _x = (_s.from < 0) ? FIELD_X0 - 80 : FIELD_X1 + 80;
            var _e = enemy_spawn(_s.kind, _x,
                                 FIELD_Y0 + _s.y + _s.spread * _i, _s.hp,
                                 enemy_act_cross, _s.col, 0, 1, 2);
            if (_e == undefined) break;
            _e.mem = {
                wait: _i * _s.stagger,
                dir: (_s.from < 0) ? 0 : 180,
                spd: _s.spd,
                fire: _s.fire,
                fired_t: 0,
            };
        }
    });
}

function enemy_act_cross(_e, _g) {
    var _m = _e.mem;
    if (_m.wait > 0) {
        _m.wait--;
        // Held off screen. Kept at its spawn edge rather than drifting, or a
        // staggered wave arrives already spread out along its own path.
        return;
    }
    enemy_weave(_e, _m.dir, _m.spd, 34, 110);
    if (_m.fire != undefined) _m.fire(_e, _g, _m.fired_t);
    _m.fired_t++;
}

/// @desc Put the boss on the field. The last event in every stage table.
function wave_boss(_maker) {
    var _spec = { maker: _maker };
    return method({ spec: _spec }, function(_g) {
        _g.boss_ref = spec.maker(_g);
        _g.phase = Phase.BossDeclare;
    });
}

/// @desc **The stage turns.** One line in a running order, and after it the
///       background has a second half -- see `bg_set_omen`.
///
///       It is a wave shape rather than a hook off `on_boss_beaten` because
///       the timeline is already the right place to say when a stage's second
///       half begins, and putting it there means somebody reading the running
///       order can see it happen. It also comes free: the stage clock is held
///       while a boss is on the field, so an event written just after a
///       midboss's gate fires on the frame that midboss is finished and not
///       one before.
///
///       A stage whose background has nothing to say about a turn may still
///       call it. `bg_omen_step` eases a number nobody reads.
function wave_bg_omen() {
    return function(_g) {
        bg_set_omen(_g.bg);
    };
}

/// @desc Put the stage's turn back to its beginning. See `bg_clear_omen`:
///       this is the review card's, and a stage that used it would be saying
///       its second half had un-happened.
function wave_bg_rewind() {
    return function(_g) {
        bg_clear_omen(_g.bg);
    };
}

/// @desc Sweep the field so the next section starts clean.
function wave_sweep_field() {
    return function(_g) {
        enemy_sweep_fodder(_g);
    };
}

/// @desc Empty every pool the field is made of. **What "starting a run"
///       means.**
///
///       Every pool in this game is a global, allocated once in `obj_boot` and
///       reused for the life of the process -- which is the right shape for a
///       pool and is exactly why something has to say when a *run* begins.
///       This is that something, and `obj_game`'s Create is its only caller,
///       so there is one answer to "what is on the field at frame zero" and it
///       is the same answer however the room was entered.
///
///       **It used not to be, and it cost two bugs that looked unrelated.**
///       The clearing lived in `game_reset_stage` instead -- the pause menu's
///       restart -- so that one path started clean and the ordinary one did
///       not. Finish a stage, take the result screen back to the rack, pick a
///       stage, and the run began with the *previous* run's bullets, lasers,
///       items and enemies still in the pools. Including the boss: Ziggy would
///       still be there at the start of the next attempt, still stepping his
///       phase table and still firing, and the patterns of a fight that had
///       already ended would open the new one.
///
///       He was also **invisible** while doing it, for a second reason -- see
///       `enemy_draw` -- so what reached the player was bullets out of nowhere
///       and damage from nothing. The two reports were one cause with two
///       symptoms, and neither was reachable from the pause menu, which is the
///       path that happened to be correct and the path everything was tested
///       through.
///
///       The irony is that `game_reset_stage`'s own comment already said this
///       was the design. It just was not.
function run_clear_field() {
    danmaku_init();
    laser_init();
    ring_init();
    item_init();
    enemy_init();
    fx_clear();
}

/// @desc Start the current stage again from the top.
///
///       **A room restart, and nothing else.** Every pool this game owns is a
///       global, and reinitialising them here is a list that will be wrong the
///       first time a pool is added -- silently, and in the direction of a
///       stage that starts with the last attempt's bullets still on it.
///       `obj_game`'s Create is the one place that knows what a fresh run is,
///       so restarting the room is the only reset that cannot drift from it.
function game_reset_stage() {
    room_restart();
}
