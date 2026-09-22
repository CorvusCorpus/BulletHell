/// @desc The drafting table: a rack card holding attacks that have no boss
///       yet, played through the normal practice mode.
///
/// Each draft is one row in `draft_list` (a name, a hue, a clock, an attack
/// function, optionally a `move`); its share of the bar, its kind and its
/// background are derived. The caster borrows Ziggy's sprite as a placeholder
/// but uses a violet aura and the generic `SPELLBG_SIGIL` background. Delete
/// this file and its line in `rack_list` to remove the feature.

// ---------------------------------------------------------------------------
// The rack
// ---------------------------------------------------------------------------

/// @desc Is this rack entry the drafting table? Read with `[$ ]` because other
///       entries lack the field and a bare read would raise.
function stage_is_draft(_def) {
    if (_def == undefined) return false;
    return _def[$ "draft"] ?? false;
}

/// @desc What the rack shows: every stage in `stage_list`, then the old stage
///       three, the review card, and the drafting table (only while it has
///       drafts). `stage_list` itself holds only real stages, so counts of
///       stages don't include these cards.
function rack_list() {
    var _l = stage_list();
    array_push(_l, old_stage_sanctum_def());
    array_push(_l, preview_stage_def());
    if (array_length(draft_list()) > 0) array_push(_l, draft_stage_def());
    return _l;
}

/// @desc The drafting table's card, shaped like a stage def. `build` is
///       `undefined`, so it can only be practised, and `id` is empty, so
///       nothing here can write to the save.
function draft_stage_def() {
    return {
        id: "",
        name: "THE DRAFTING TABLE",
        subtitle: "attacks with nobody to cast them",
        needs: 0,
        make_bg: bg_brimstone,
        build: undefined,
        draft: true,
        encounters: 1,
        bosses: [
            { name: "THE UNNAMED", spawn: draft_boss_spawn,
              phases: draft_phases },
        ],
    };
}

// ---------------------------------------------------------------------------
// The caster
// ---------------------------------------------------------------------------

/// @desc Health per draft. The boss's total is this times the number of
///       drafts, so each draft owns the same share however many there are.
#macro DRAFT_SLOT_HP 360

function draft_boss_def() {
    return {
        name: "THE UNNAMED",
        title: "a pattern in search of a caster",
        // Placeholder: Ziggy's art.
        sprite: spr_boss_ziggy,
        eye: spr_eye_ziggy,
        // `boss_draw` tints only the aura and sigil with this.
        col: BCOL_VIOLET,
        radius: 62,
        spell_bg: SPELLBG_SIGIL,
        final: true,
    };
}

function draft_boss_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 200,
                        DRAFT_SLOT_HP * max(1, array_length(draft_list())),
                        draft_phases(), draft_boss_def());
    if (_b != undefined) _b.boss.home_y = BOSS_HOME_Y;
    return _b;
}

// ---------------------------------------------------------------------------
// The drafts
// ---------------------------------------------------------------------------

/// @desc Every unassigned attack. A name makes a row a spell; `move` is
///       optional (default drift). To add an idea: one row here and its
///       function below.
function draft_list() {
    return [
        { name: "",             col: BCOL_INDIGO,  time: 30 * FPS,
          attack: draft_scratch },

        { name: "Falling Sky",  col: BCOL_AZURE,   time: 40 * FPS,
          attack: draft_falling_sky },

        // `Fixed`: nothing in it is aimed, and a moving origin would smear the
        // rosette.
        { name: "Seed & Bloom", col: BCOL_SPRING,  time: 40 * FPS,
          move: BossMove.Fixed, attack: draft_seed_and_bloom },

        { name: "Long Wake",    col: BCOL_CYAN,    time: 38 * FPS,
          attack: draft_long_wake },

        { name: "Second Sight", col: BCOL_MAGENTA, time: 42 * FPS,
          attack: draft_second_sight },

        // Mika's sand thrown in carriers that burst, parked here to be tried
        // before any of his slots uses it.
        { name: "Sand Burst",   col: BCOL_GOLD,    time: 40 * FPS,
          move: BossMove.Close, attack: draft_sand_burst },
    ];
}

/// @desc The phase table derived from `draft_list`: equal shares of the bar,
///       kind and background from whether the row is named. Built fresh on
///       every call, because phase structs are mutable.
function draft_phases() {
    var _l = draft_list();
    var _n = array_length(_l);
    var _out = [];
    for (var _i = 0; _i < _n; _i++) {
        var _d = _l[_i];
        var _spell = (_d.name != "");
        array_push(_out, {
            kind: _spell ? AttackKind.Spell : AttackKind.NonSpell,
            name: _d.name,
            col: _d.col,
            bg: _spell ? _d.col : -1,
            // An equal share, and the last one lands exactly on zero.
            hp_end: 1 - (_i + 1) / _n,
            time: _d.time,
            move: _d[$ "move"] ?? BossMove.Drift,
            attack: _d.attack,
        });
    }
    return _out;
}

// ---------------------------------------------------------------------------
// The drafts' patterns
//
// Seed content: between them they exercise the engine features the stages
// don't use (the Cartesian model, splits, wakes, lifetimes, mid-flight
// graphic changes, homing).
// ---------------------------------------------------------------------------

/// @desc The blank page to copy: an aimed fan on a beat and a slow ring.
function draft_scratch(_e, _g, _t) {
    if ((_t mod 44) == 0) {
        fire_fan(_e.x, _e.y, 7, 6.0,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 50,
                 BSHAPE_RICE, BCOL_INDIGO, 16);
    }
    if ((_t mod 88) == 40) {
        fire_ring(_e.x, _e.y, 18, 4.2, _t * 2.1, BSHAPE_ORB, BCOL_AZURE, 20);
    }
}

/// @desc **Falling Sky** -- lobbed shots under capped gravity (the Cartesian
///       model, `bullet_force`), with a thin aimed line underneath.
function draft_falling_sky(_e, _g, _t) {
    if ((_t mod 26) == 0) {
        // Lobbed out to alternating sides, so the arcs cross.
        var _side = ((_t div 26) mod 2 == 0) ? 1 : -1;
        for (var _i = 0; _i < 3; _i++) {
            var _u = fire_xy(_e.x, _e.y,
                             _side * (3.4 + _i * 1.5), -4.6 - _i * 0.5,
                             BSHAPE_BALL, BCOL_AZURE, 16);
            // Gravity with a terminal fall speed.
            bullet_force(_u, 0, 0.13, BQ_KEEP, 7.5);
        }
    }

    if ((_t mod 96) == 60) {
        fire_stack(_e.x, _e.y, 3, 6.4, 1.3,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_NEEDLE, BCOL_CYAN, 20);
    }
}

/// @desc **Seed & Bloom** -- slow shots that split into eight where they have
///       travelled to.
function draft_seed_and_bloom(_e, _g, _t) {
    if ((_t mod 34) == 0) {
        var _n = 6;
        for (var _i = 0; _i < _n; _i++) {
            var _u = fire(_e.x, _e.y, 3.2, _t * 2.6 + _i * (360 / _n),
                          BSHAPE_CRYSTAL, BCOL_SPRING, 14);
            bullet_split_at(_u, 62, 8, 4.4, _t * 1.3);
        }
    }
}

/// @desc **Long Wake** -- turning shots that shed pairs of bullets sideways as
///       they go (the wake length is limited by `BULLET_QUEUE_MAX`).
function draft_long_wake(_e, _g, _t) {
    if ((_t mod 40) == 0) {
        var _n = 4;
        var _base = _t * 3.1;
        for (var _i = 0; _i < _n; _i++) {
            var _u = fire(_e.x, _e.y, 5.4, _base + _i * (360 / _n),
                          BSHAPE_MOTE, BCOL_CYAN, 14);
            bullet_turn_at(_u, 0, 1.5);
            // A pair shed sideways every six frames, eight times.
            bullet_shed_every(_u, 12, 6, 8, 2, 2.6, 90, 6);
            // A lifetime, because a bullet turning this hard can orbit and
            // never leave.
            bullet_expire_at(_u, 260);
        }
    }
}

/// @desc **Second Sight** -- slow orbs that turn into fast darts aimed at the
///       player partway, plus a few weakly homing hunters.
function draft_second_sight(_e, _g, _t) {
    if ((_t mod 18) == 0) {
        var _u = fire(_e.x, _e.y, 2.4, _t * 6.7, BSHAPE_BUBBLE, BCOL_MAGENTA,
                      14);
        bullet_graphic_at(_u, 46, BSHAPE_DART, BCOL_ROSE);
        bullet_aim_at(_u, 46);
        bullet_move_at(_u, 46, 7.2);
        bullet_expire_at(_u, 220);
    }

    if ((_t mod 74) == 30) {
        for (var _i = -1; _i <= 1; _i++) {
            var _h = fire(_e.x, _e.y, 3.4,
                          aim_at(_e.x, _e.y, _g.player.x, _g.player.y)
                          + _i * 36,
                          BSHAPE_BUTTERFLY, BCOL_VIOLET, 22);
            if (_h != undefined) {
                _h.bmod = BMod.Home;
                _h.mod_a = 0.9;      // max turn, degrees a frame
            }
            bullet_expire_at(_h, 300);
        }
    }
}

// ---------------------------------------------------------------------------
// Sand Burst: two rings riding the caster, each throwing two carriers per
// beat that break into Mika's sand (`mika_sand_burst` in `mika_nonspells`).
// ---------------------------------------------------------------------------

#macro DRAFT_BURST_RINGS 2
#macro DRAFT_BURST_DIST 205
#macro DRAFT_BURST_ORBIT 1.5
#macro DRAFT_BURST_SPIN (DRAFT_BURST_ORBIT * 1.5)
#macro DRAFT_BURST_ARMS 2
#macro DRAFT_BURST_BEAT 34
#macro DRAFT_BURST_LEAN 12

/// @desc A ring `act` that throws carriers of sand cycle `_cycle` (bound as a
///       method rather than stored on the pooled ring).
function draft_burst_rim_for(_cycle) {
    return method({ cycle: _cycle }, function(_ring, _g, _t) {
        draft_burst_rim(_ring, _g, _t, cycle);
    });
}

/// @desc One ring's volley: carriers off opposite sides of its metal every
///       `DRAFT_BURST_BEAT` frames.
function draft_burst_rim(_ring, _g, _t, _cycle) {
    if ((_t mod DRAFT_BURST_BEAT) != 0) return;

    var _sign = (_ring.spin >= 0) ? 1 : -1;
    var _volley = _t div DRAFT_BURST_BEAT;

    for (var _i = 0; _i < DRAFT_BURST_ARMS; _i++) {
        // Where the metal will be when the mark goes live, leaning with the
        // spin.
        var _at = _ring.ang + _ring.spin * MIKA_SAND_DELAY
                  + _i * (360 / DRAFT_BURST_ARMS);
        var _dir = _at + DRAFT_BURST_LEAN * _sign;

        // Each arm uses a different step of the ring's colour cycle.
        mika_sand_burst(_ring, _at, _dir, mika_sand_grade(_cycle, _i),
                        MIKA_CARRY_HOLD,
                        MIKA_SAND_BRAKE, MIKA_SAND_FLOOR,
                        MIKA_SAND_CURL * _sign, MIKA_SAND_BEND,
                        MIKA_SAND_LIFE);
    }
}

/// @desc **Sand Burst.** Two rings riding the caster, throwing carriers that
///       break into sand. The caster fires nothing itself.
function draft_sand_burst(_e, _g, _t) {
    if (_t != 0) return;

    for (var _i = 0; _i < DRAFT_BURST_RINGS; _i++) {
        var _r = mika_orbit_ring(_e, DRAFT_BURST_DIST,
                                 _i * (360 / DRAFT_BURST_RINGS),
                                 DRAFT_BURST_ORBIT, MIKA_RING_COL,
                                 draft_burst_rim_for(_i));
        if (_r == undefined) break;
        _r.spin = DRAFT_BURST_SPIN;
    }
}
