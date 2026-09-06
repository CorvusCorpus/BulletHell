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
    return {
        def: _def,
        events: _def.build(),
        cursor: 0,
        t: 0,
        gated: false,
        gate_grace: 0,     // frames a gate waits before it starts believing
        done: false,
    };
}

/// @desc One timed event.
function ev(_at, _fn) {
    return { at: _at, fn: _fn, gate: false };
}

/// @desc Hold the clock until every fodder enemy is gone.
function ev_gate(_at) {
    return { at: _at, fn: undefined, gate: true };
}

/// @desc Advance the stage one frame.
function stage_step(_s, _g) {
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
