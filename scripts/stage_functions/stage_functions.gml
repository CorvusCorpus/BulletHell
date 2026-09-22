/// @desc Stage timelines, gates, wave shapes and encounter grading.
///
/// A stage's `build()` returns a timeline: a sorted list of `ev(at, fn)` and
/// `ev_gate(at)` entries. A gate freezes stage time until no fodder is on the
/// field, so later `at` values stay relative to when the gate released. Stage
/// time doesn't advance while a boss is up. The stage spawns its bosses; their
/// phase tables run the fights.

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
        // How many graded encounters the stage holds (a def may override).
        encounters: _def[$ "encounters"] ?? stage_count_encounters(_def, _events),
        // The open encounter, or `undefined` between them
        // (`stage_encounter_step`).
        enc: undefined,
        enc_n: 0,
    };
}

/// @desc How many encounters a stage contains, for the console's row of
///       sockets. Each gate closes a group of waves, except the gates that
///       follow a boss that is not the last one (those close nothing); each
///       boss attack is one encounter. A definition may set `encounters`
///       itself, as the practice, drafting and preview cards do.
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

/// @desc Open and close wave-group encounters. A group is the stretch during
///       which fodder is on the field (outside boss fights): it opens on the
///       frame fodder appears and is graded on the frame the last of it goes.
///       Detected rather than declared, so any wave shape is graded without
///       reporting anything.
function stage_encounter_step(_s, _g) {
    var _live = (_g[$ "boss_ref"] == undefined) && enemy_count_fodder() > 0;

    if (_s.enc == undefined) {
        // Not during a boss: its attacks are graded by its phase table.
        if (!_live) return;
        _s.enc_n++;
        _s.enc = {
            // Real frames open, not stage time (which is frozen during a
            // gate, where most of a group is fought).
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

    rank_note(_g[$ "marks"], "WAVE " + string(_e.n),
              rank_for_encounter(_hits, _bombs, _earned >= _target), false,
              _earned, _target, _hits, _bombs);
}

/// @desc Advance the stage one frame.
function stage_step(_s, _g) {
    // Before the early returns below: a group of waves can still be on the
    // field while a gate holds or after the timeline has run out.
    stage_encounter_step(_s, _g);

    if (_s.done) return;

    if (_s.gated) {
        // The grace stops a gate placed right after a spawn from seeing an
        // empty field (enemies exist only once their event has run) and
        // releasing at once.
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

/// @desc How far through the timeline the stage is, 0 to 1.
function stage_progress(_s) {
    var _n = array_length(_s.events);
    return (_n <= 0) ? 1 : (_s.cursor / _n);
}

// ---------------------------------------------------------------------------
// Wave shapes
//
// Each returns an event's `fn`. Coordinates are relative to the field
// (`FIELD_X0/Y0` are added here).
// ---------------------------------------------------------------------------

/// @desc A line of enemies that fly in to posts, hold and fire for `_hold`
///       frames, then leave. `_fire(enemy, g, t)` is called every frame once
///       an enemy has arrived.
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
///       while, then leave.
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
        // Leave upward and outward, away from the player.
        enemy_leave(_e, (_e.x < FIELD_CX) ? 200 : 340);
    }
}

/// @desc A stream of enemies crossing the field without stopping, from the
///       left (`_from < 0`) or right. `_y` is from the top of the field.
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
        // Held at its spawn point off screen until its turn.
        return;
    }
    enemy_weave(_e, _m.dir, _m.spd, 34, 110);
    if (_m.fire != undefined) _m.fire(_e, _g, _m.fired_t);
    _m.fired_t++;
}

/// @desc Put a boss on the field.
function wave_boss(_maker) {
    var _spec = { maker: _maker };
    return method({ spec: _spec }, function(_g) {
        _g.boss_ref = spec.maker(_g);
        _g.phase = Phase.BossDeclare;
    });
}

/// @desc Start the background's mid-stage turn (`bg_set_omen`). Placed just
///       after a midboss's gate, it fires as soon as the midboss is beaten.
///       Harmless on a background with no turn.
function wave_bg_omen() {
    return function(_g) {
        bg_set_omen(_g.bg);
    };
}

/// @desc Reset the background's turn (`bg_clear_omen`). Only the review card
///       uses this.
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

/// @desc Empty every pool. The pools are globals that outlive a room, so this
///       is what starting a run means; `obj_game`'s Create is its only caller
///       (`check_run_clears_the_field` checks that it is called).
function run_clear_field() {
    danmaku_init();
    laser_init();
    ring_init();
    item_init();
    enemy_init();
    fx_clear();
}

/// @desc Start the current stage again: a room restart, so `obj_game`'s Create
///       (and `run_clear_field`) does the reset.
function game_reset_stage() {
    room_restart();
}
