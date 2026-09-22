/// @desc The old stage three ("SANCTUM, OLD DRAFT"): a frozen copy of
///       `stage_sanctum` from commit 09469bb (waves, the Proctor, and Mika's
///       old seven placeholder attacks), kept on the rack to compare against
///       the rebuild.
///
/// Every name is prefixed `old_`/`OLD_` (GML names are global) and nothing
/// here calls into `stage_sanctum`, so the working stage can change freely.
/// `id` is empty, so `progress_record` files nothing for it. To remove it:
/// delete this file, its line in `rack_list`, `test_old_sanctum`, its line in
/// `test_stage_run`, and the rack's `stage_is_old_draft` branch.

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

#macro OLD_MIKA_HP 2800
#macro OLD_MIKA_RING_COL BCOL_GOLD

// Rings in a full formation (six on one orbit leave gaps about a ring wide).
#macro OLD_MIKA_RING_N 6

// Orbit radius of his formations.
#macro OLD_MIKA_ORBIT 300

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

/// @desc The card: a full stage run, with an empty `id` (the original was
///       `gilded_sanctum`) so it can't write to the save.
function old_stage_sanctum_def() {
    return {
        id: "",
        name: "SANCTUM, OLD DRAFT",
        subtitle: "Mika's placeholder fight",
        needs: 0,
        make_bg: bg_sanctum,
        build: old_stage_sanctum_script,
        old_draft: true,


        // `turned`: he is fought after the hall opens (`practice_begin`).
        bosses: [
            { name: "THE PROCTOR", spawn: old_sanctum_midboss_spawn,
              phases: old_sanctum_midboss_phases },
            { name: "MIKA", spawn: old_mika_spawn, phases: old_mika_phases,
              turned: true },
        ],
    };
}

/// @desc Is this rack entry the old draft of stage three? (Read with `[$ ]`;
///       other entries lack the field.)
function stage_is_old_draft(_def) {
    if (_def == undefined) return false;
    return _def[$ "old_draft"] ?? false;
}

/// @desc The running order.
function old_stage_sanctum_script() {
    var _e = [];

    // --- the way in ----------------------------------------------------
    array_push(_e, ev(80, wave_cross(EnemyKind.Wisp, 6, -1, 210, 56, 5.6, 3,
                                     BCOL_GOLD, old_sanctum_fodder_pellet)));
    array_push(_e, ev(230, wave_cross(EnemyKind.Wisp, 6, 1, 330, -56, 5.6, 3,
                                      BCOL_AMBER, old_sanctum_fodder_pellet)));
    array_push(_e, ev_gate(280));

    // --- and here is what a ring does ----------------------------------
    array_push(_e, ev(400, old_wave_sanctum_gateposts()));
    array_push(_e, ev(430, wave_line(EnemyKind.Grimoire, 5,
                                     -100, 160, 0, 0,
                                     420, 260, 270, 0,
                                     220, 14, BCOL_BONE,
                                     old_sanctum_fodder_fan)));
    array_push(_e, ev_gate(470));

    array_push(_e, ev(600, wave_cross(EnemyKind.Gem, 5, -1, 400, 52, 6.2, 6,
                                      BCOL_AMBER, old_sanctum_fodder_aimed)));
    array_push(_e, ev(620, wave_cross(EnemyKind.Gem, 5, 1, 400, -52, 6.2, 6,
                                      BCOL_AMBER, old_sanctum_fodder_aimed)));
    array_push(_e, ev_gate(670));

    // --- the lesser hand -----------------------------------------------
    array_push(_e, ev(770, wave_boss(old_sanctum_midboss_spawn)));
    array_push(_e, ev_gate(790));

    // The hall opens (the camera rises from the floor to flying height).
    // Just after the midboss's gate, so it fires when the Proctor is beaten.
    array_push(_e, ev(792, wave_bg_omen()));

    array_push(_e, ev(900, wave_line(EnemyKind.Sentry, 3,
                                     -140, 200, 0, 0,
                                     500, 300, 440, 0,
                                     250, 46, BCOL_GOLD,
                                     old_sanctum_fodder_sentry)));
    array_push(_e, ev(960, wave_cross(EnemyKind.Wisp, 8, -1, 500, 42, 6.2, 4,
                                      BCOL_BONE, old_sanctum_fodder_pellet,
                                      10)));
    array_push(_e, ev_gate(1010));

    array_push(_e, ev(1120, old_wave_sanctum_gateposts()));
    array_push(_e, ev(1150, wave_cross(EnemyKind.Gem, 6, 1, 250, 64, 6.6, 8,
                                       BCOL_GOLD, old_sanctum_fodder_aimed,
                                       11)));
    array_push(_e, ev(1170, wave_line(EnemyKind.Grimoire, 6,
                                      FIELD_W + 100, 140, 0, 0,
                                      320, 220, 250, 40,
                                      230, 18, BCOL_BONE,
                                      old_sanctum_fodder_fan)));
    array_push(_e, ev_gate(1220));

    array_push(_e, ev(1320, wave_sweep_field()));
    array_push(_e, ev(1380, wave_boss(old_mika_spawn)));

    return _e;
}

/// @desc A wave event: two idle rings standing in the field for 15 seconds
///       (they only block shots).
function old_wave_sanctum_gateposts() {
    return function(_g) {
        for (var _i = -1; _i <= 1; _i += 2) {
            var _r = ring_new(FIELD_CX + _i * 260, FIELD_Y0 + 420,
                              OLD_MIKA_RING_COL, 15 * FPS);
            if (_r != undefined) _r.spin = _i * 0.35;
        }
    };
}

// ---------------------------------------------------------------------------
// What the fodder fires
// ---------------------------------------------------------------------------

function old_sanctum_fodder_pellet(_e, _g, _t) {
    if ((_t mod 48) != 0) return;
    fire(_e.x, _e.y, 6.0, aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
         BSHAPE_PELLET, BCOL_GOLD, 14);
}

function old_sanctum_fodder_fan(_e, _g, _t) {
    if ((_t mod 64) != 20) return;
    fire_fan(_e.x, _e.y, 5, 5.4,
             aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 44,
             BSHAPE_RICE, BCOL_BONE, 16);
}

function old_sanctum_fodder_aimed(_e, _g, _t) {
    if ((_t mod 54) != 30) return;
    fire_stack(_e.x, _e.y, 3, 5.2, 1.5,
               aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
               BSHAPE_CRYSTAL, BCOL_AMBER, 14);
}

function old_sanctum_fodder_sentry(_e, _g, _t) {
    if ((_t mod 86) == 30) {
        fire_ring(_e.x, _e.y, 14, 4.6, _e.t * 4, BSHAPE_ORB, BCOL_GOLD, 20);
    }
    if ((_t mod 86) == 66) {
        fire_stack(_e.x, _e.y, 4, 6.2, 1.4,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_DART, BCOL_BONE, 16);
    }
}

// ---------------------------------------------------------------------------
// Ring helpers
// ---------------------------------------------------------------------------

/// @desc A ring orbiting the caster at `_dist`, starting at `_ang0`.
///
///       The ring is attached to the boss (`ring_attach`), so it follows his
///       movement. `_shoot(ring, run, frame)` is the ring's own pattern; the
///       member is named `shoot`, not `fire`, because inside a method a struct
///       member shadows the global function of the same name.
function old_mika_orbit_ring(_e, _dist, _ang0, _rate, _col, _shoot, _ttl = 0) {
    var _ring = ring_new(_e.x + lengthdir_x(_dist, _ang0),
                         _e.y + lengthdir_y(_dist, _ang0), _col, _ttl);
    if (_ring == undefined) return undefined;
    ring_attach(_ring, _e, lengthdir_x(_dist, _ang0),
                lengthdir_y(_dist, _ang0));
    _ring.act = method({ dist: _dist, a0: _ang0, rate: _rate, shoot: _shoot },
                       function(_ring, _run, _t) {
        var _a = a0 + _t * rate;
        _ring.ox = lengthdir_x(dist, _a);
        _ring.oy = lengthdir_y(dist, _a);
        // Called through a local: `check_unknown_functions` can't tell a bare
        // `shoot(...)` member call from a call to a missing function.
        var _fn = shoot;
        if (_fn != undefined) _fn(_ring, _run, _t);
    });
    return _ring;
}

/// @desc A ring standing at a point in the field, with a pattern of its own.
function old_mika_place_ring(_x, _y, _col, _shoot, _ttl = 0) {
    var _ring = ring_new(_x, _y, _col, _ttl);
    if (_ring == undefined) return undefined;
    if (_shoot != undefined) _ring.act = _shoot;
    return _ring;
}

/// @desc A formation of `_n` orbiting rings. Returns `{ring[], gen[]}`: ring
///       structs are reused by the pool, so each reference is kept with its
///       `gen` and checked with `ring_valid` before use.
function old_mika_formation(_e, _n, _dist, _rate, _col, _shoot, _ttl, _spin) {
    var _f = { ring: [], gen: [] };
    for (var _i = 0; _i < _n; _i++) {
        var _r = old_mika_orbit_ring(_e, _dist, _i * (360 / _n), _rate, _col,
                                 _shoot, _ttl);
        _f.ring[_i] = _r;
        _f.gen[_i] = (_r == undefined) ? -1 : _r.gen;
        if (_r != undefined) _r.spin = _spin;
    }
    return _f;
}

/// @desc String current between two members of a formation, if both are still
///       the rings they were.
function old_mika_link(_f, _a, _b, _frames) {
    if (ring_valid(_f.ring[_a], _f.gen[_a])
        && ring_valid(_f.ring[_b], _f.gen[_b])) {
        ring_link(_f.ring[_a], _f.ring[_b], _frames);
    }
}

// ---------------------------------------------------------------------------
// The Proctor (midboss)
// ---------------------------------------------------------------------------

function old_sanctum_midboss_def() {
    return {
        name: "THE PROCTOR",
        title: "one of the lesser hands",
        // Placeholder art: stage one's stone sentry.
        sprite: spr_foe_sentry,
        eye: spr_eye_mika,
        col: BCOL_GOLD,
        radius: 46,
        spell_bg: SPELLBG_SIGIL,
        final: false,
    };
}

function old_sanctum_midboss_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_GOLD, bg: -1,
          hp_end: 0.45, time: 24 * FPS, attack: old_proctor_marking },
        { kind: AttackKind.Spell, name: "Second Reading",
          col: BCOL_AMBER, bg: BCOL_INDIGO,
          hp_end: 0.0, time: 30 * FPS, attack: old_proctor_second_reading },
    ];
}

function old_sanctum_midboss_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 140, 300,
                        old_sanctum_midboss_phases(),
                        old_sanctum_midboss_def());
    if (_b != undefined) {
        _b.boss.home_y = BOSS_HOME_Y - 30;
        _b.boss.declare_t = 40;      // a midboss gets no name splash
    }
    return _b;
}

/// @desc Two rings circling him, throwing bullets off their rims.
function old_proctor_marking(_e, _g, _t) {
    if (_t == 0) {
        old_mika_formation(_e, 2, 210, 1.05, BCOL_GOLD, old_proctor_rim, 0,
                           0.7);
    }
    if ((_t mod 84) == 40) {
        fire_fan_stack(_e.x, _e.y, 7, 2, 5.0, 1.1,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                       BSHAPE_RICE, BCOL_BONE, 20);
    }
}

function old_proctor_rim(_ring, _g, _t) {
    if ((_t mod 58) != 24) return;
    ring_fire_rim(_ring, 8, 3.6, _t * 2.7, BSHAPE_ORB, BCOL_GOLD, 18);
}

/// @desc Three rings walking down the field, each with a beam through it.
function old_proctor_second_reading(_e, _g, _t) {
    var _cycle = _t mod 220;
    if (_cycle == 0) {
        for (var _i = 0; _i < 3; _i++) {
            var _r = old_mika_place_ring(
                FIELD_X0 + FIELD_W * (0.25 + _i * 0.25), FIELD_Y0 + 150,
                BCOL_AMBER, old_proctor_walker, 200);
            if (_r == undefined) break;
            _r.vy = 2.4;
            _r.vx = (_i - 1) * 0.9;
            _r.spin = ((_i mod 2) ? -1 : 1) * 1.1;
        }
    }
    if ((_t mod 26) == 12) {
        fire_ring(_e.x, _e.y, 8, 3.8, _t * 4.6, BSHAPE_PELLET, BCOL_GOLD, 16);
    }
}

function old_proctor_walker(_ring, _g, _t) {
    if (_t == 26) {
        ring_beam(_ring, 90, 2200, 26, BCOL_AMBER, 60, 90, 20);
    }
    if ((_t mod 46) == 20) {
        ring_fire_tangent(_ring, 6, 3.4, _t * 3.1, BSHAPE_MOTE, BCOL_AMBER,
                          1, 16);
    }
}

// ---------------------------------------------------------------------------
// Mika's old seven attacks
// ---------------------------------------------------------------------------

function old_mika_def() {
    return {
        name: "MIKA",
        title: "head mage to the Living God of Death",
        sprite: spr_boss_mika,
        eye: spr_eye_mika,
        col: BCOL_GOLD,
        radius: 64,
        spell_bg: SPELLBG_SIGIL,
        final: true,
    };
}

function old_mika_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_GOLD, bg: -1,
          hp_end: 0.88, time: 24 * FPS, attack: old_mika_signet },

        { kind: AttackKind.Spell, name: "Gilded Aperture",
          col: BCOL_GOLD, bg: BCOL_INDIGO,
          hp_end: 0.74, time: 40 * FPS, attack: old_mika_gilded_aperture,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_AMBER, bg: -1,
          hp_end: 0.63, time: 24 * FPS, attack: old_mika_two_coins },

        { kind: AttackKind.Spell, name: "Ashiah's Circuit",
          col: BCOL_CYAN, bg: BCOL_INDIGO,
          hp_end: 0.46, time: 42 * FPS, attack: old_mika_ashiah_circuit,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_BONE, bg: -1,
          hp_end: 0.34, time: 26 * FPS, attack: old_mika_close_reading,
          move: BossMove.Track },

        { kind: AttackKind.Spell, name: "Three Open Gates",
          col: BCOL_AMBER, bg: BCOL_INDIGO,
          hp_end: 0.18, time: 44 * FPS, attack: old_mika_three_gates },

        { kind: AttackKind.Spell, name: "Grand Orrery",
          col: BCOL_GOLD, bg: BCOL_INDIGO,
          hp_end: 0.0, time: 50 * FPS, attack: old_mika_grand_orrery,
          move: BossMove.Fixed },
    ];
}

function old_mika_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, OLD_MIKA_HP, old_mika_phases(),
                      old_mika_def());
}

/// @desc Two rings on a long lead, and him firing past them.
function old_mika_signet(_e, _g, _t) {
    if (_t == 0) {
        old_mika_formation(_e, 2, 230, 0.85, OLD_MIKA_RING_COL,
                           old_mika_signet_rim, 0, 0.6);
    }
    if ((_t mod 78) == 34) {
        fire_fan_stack(_e.x, _e.y, 7, 2, 5.2, 1.1,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                       BSHAPE_RICE, BCOL_BONE, 20);
    }
    if ((_t mod 20) == 0) {
        fire_ring(_e.x, _e.y, 4, 3.6, _t * 5.3, BSHAPE_ORB, BCOL_AMBER, 14);
    }
}

function old_mika_signet_rim(_ring, _g, _t) {
    if ((_t mod 52) != 22) return;
    ring_fire_rim(_ring, 9, 3.8, _t * 2.4, BSHAPE_ORB, OLD_MIKA_RING_COL, 18);
}

/// @desc **Gilded Aperture.** Six rings orbiting him; the turning gaps between
///       them are the line of fire to the boss. The rings' volleys are
///       tangential so they don't wall off the gaps.
function old_mika_gilded_aperture(_e, _g, _t) {
    if (_t == 0) {
        old_mika_formation(_e, OLD_MIKA_RING_N, OLD_MIKA_ORBIT, 0.55,
                           OLD_MIKA_RING_COL, old_mika_aperture_rim, 0, 1.0);
    }
    // A slow, wide aimed fan of his own.
    if ((_t mod 96) == 46) {
        fire_fan_stack(_e.x, _e.y, 9, 2, 4.6, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 60,
                       BSHAPE_RICE, BCOL_BONE, 22);
    }
}

/// @desc The aperture rings' volley, in cyan (gold volleys off gold rings were
///       hard to read).
function old_mika_aperture_rim(_ring, _g, _t) {
    if ((_t mod 50) != 22) return;
    ring_fire_tangent(_ring, 5, 3.2, _t * 2.2, BSHAPE_MOTE, BCOL_CYAN, 1, 16);
}

/// @desc Three rings walking across the field, and a spiral under them.
function old_mika_two_coins(_e, _g, _t) {
    var _cycle = _t mod 190;
    if (_cycle == 0) {
        var _lap = _t div 190;
        for (var _i = 0; _i < 3; _i++) {
            var _from = ((_lap mod 2) ? -1 : 1);
            var _r = old_mika_place_ring(
                FIELD_CX + _from * (FIELD_W * 0.5 + 160),
                FIELD_Y0 + 260 + _i * 170, BCOL_AMBER, old_mika_coin_rim, 200);
            if (_r == undefined) break;
            _r.vx = -_from * 4.2;
            _r.spin = -_from * 1.3;
        }
    }
    if ((_t mod 5) == 0) {
        fire_ring(_e.x, _e.y, 2, 5.4, _t * 3.1, BSHAPE_PELLET, BCOL_GOLD, 12);
    }
}

function old_mika_coin_rim(_ring, _g, _t) {
    if ((_t mod 40) != 16) return;
    ring_fire_rim(_ring, 7, 3.4, _t * 3.3, BSHAPE_ORB, BCOL_AMBER, 16);
}

/// @desc **Ashiah's Circuit.** Six orbiting rings with current strung between
///       alternate pairs (three bars, three doors); the pairing shifts every
///       190 frames so the doors move.
function old_mika_ashiah_circuit(_e, _g, _t) {
    static circuit = { ring: [], gen: [] };

    if (_t == 0) {
        circuit = old_mika_formation(_e, OLD_MIKA_RING_N, OLD_MIKA_ORBIT,
                                     0.60, BCOL_CYAN, old_mika_circuit_rim,
                                     0, 1.2);
    }

    // Pairing alternates between (0,1)(2,3)(4,5) and (1,2)(3,4)(5,0).
    if ((_t mod 190) == 0) {
        var _off = ((_t div 190) mod 2);
        for (var _k = 0; _k < 3; _k++) {
            var _a = (_k * 2 + _off) mod OLD_MIKA_RING_N;
            var _b = (_a + 1) mod OLD_MIKA_RING_N;
            old_mika_link(circuit, _a, _b, 160);
        }
    }

    if ((_t mod 34) == 16) {
        fire_ring(_e.x, _e.y, 5, 3.4, _t * 6.7, BSHAPE_MOTE, BCOL_BONE, 16);
    }
}

function old_mika_circuit_rim(_ring, _g, _t) {
    if ((_t mod 74) != 30) return;
    ring_fire_rim(_ring, 5, 3.2, _t * 4.1, BSHAPE_ORB, BCOL_CYAN, 18);
}

/// @desc Six rings placed round wherever the player is, which then charge and
///       move inward. The boss tracks the player during it (`BossMove.Track`).
function old_mika_close_reading(_e, _g, _t) {
    static reading = { ring: [], gen: [] };

    var _cycle = _t mod 230;

    if (_cycle == 0) {
        var _cx = clamp(_g.player.x, FIELD_X0 + 300, FIELD_X1 - 300);
        var _cy = clamp(_g.player.y, FIELD_Y0 + 340, FIELD_Y1 - 300);
        reading = { ring: [], gen: [] };
        for (var _i = 0; _i < OLD_MIKA_RING_N; _i++) {
            var _a = _i * (360 / OLD_MIKA_RING_N) + _t;
            var _r = old_mika_place_ring(_cx + lengthdir_x(300, _a),
                                     _cy + lengthdir_y(300, _a),
                                     BCOL_BONE, old_mika_reading_rim, 210);
            reading.ring[_i] = _r;
            reading.gen[_i] = (_r == undefined) ? -1 : _r.gen;
            if (_r != undefined) _r.spin = 0.9;
        }
        fx_ring(_cx, _cy, 40, 300, 24, global.bullet_colour[BCOL_BONE], 0.7);
    }

    // Charge, then close. References are checked with `ring_valid`, since the
    // pool may have reused these slots.
    if (_cycle == 120) {
        for (var _i = 0; _i < array_length(reading.ring); _i++) {
            if (ring_valid(reading.ring[_i], reading.gen[_i])) {
                ring_charge(reading.ring[_i], RING_WARN, 80);
            }
        }
    }
    if (_cycle == 120 + RING_WARN) {
        for (var _i = 0; _i < array_length(reading.ring); _i++) {
            var _r = reading.ring[_i];
            if (!ring_valid(_r, reading.gen[_i])) continue;
            var _in = point_direction(_r.x, _r.y, _g.player.x, _g.player.y);
            _r.vx = lengthdir_x(1.7, _in);
            _r.vy = lengthdir_y(1.7, _in);
        }
    }

    if ((_t mod 88) == 40) {
        fire_fan(_e.x, _e.y, 9, 5.0,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 70,
                 BSHAPE_RICE, BCOL_GOLD, 20);
    }
}

function old_mika_reading_rim(_ring, _g, _t) {
    if ((_t mod 50) != 24) return;
    // Fired outward, keeping the middle clear until the rings close in.
    ring_fire_rim(_ring, 7, 2.8, _t * 2.1, BSHAPE_MOTE, BCOL_BONE, 18);
}

/// @desc **Three Open Gates.** Three rings standing across the field, each
///       with a turning beam anchored at its centre (`ring_beam`); the rings
///       drift apart and back.
function old_mika_three_gates(_e, _g, _t) {
    if ((_t mod 260) == 0) {
        for (var _i = 0; _i < 3; _i++) {
            var _r = old_mika_place_ring(
                FIELD_X0 + FIELD_W * (0.25 + _i * 0.25),
                FIELD_Y0 + 330 + ((_i mod 2) ? 110 : 0),
                BCOL_AMBER, old_mika_gate_beam, 250);
            if (_r == undefined) break;
            _r.spin = ((_i mod 2) ? -1 : 1) * 1.2;
            _r.vx = (_i - 1) * 0.9;
        }
    }
    if ((_t mod 30) == 14) {
        fire_ring(_e.x, _e.y, 7, 3.6, -_t * 3.7, BSHAPE_PELLET, BCOL_GOLD, 16);
    }
}

function old_mika_gate_beam(_ring, _g, _t) {
    var _c = _t mod 120;
    if (_c == 10) {
        var _l = ring_beam(_ring, 90 + dsin(_t * 0.7) * 40, 2400, 30,
                           BCOL_AMBER, 66, 70, 22);
        if (_l != undefined) _l.turn = ((_ring.spin > 0) ? 1 : -1) * 0.42;
    }
    if ((_t mod 38) == 22) {
        ring_fire_rim(_ring, 5, 3.0, _t * 2.9, BSHAPE_MOTE, BCOL_AMBER, 16);
    }
}

/// @desc **Grand Orrery.** Six rings on two counter-rotating orbits: one
///       adjacent pair strung with current at a time, one ring charged at a
///       time, volleys off every rim, and an aimed fan.
function old_mika_grand_orrery(_e, _g, _t) {
    static orrery = { ring: [], gen: [] };

    if (_t == 0) {
        orrery = { ring: [], gen: [] };
        for (var _i = 0; _i < OLD_MIKA_RING_N; _i++) {
            var _inner = (_i mod 2) == 0;
            var _r = old_mika_orbit_ring(_e, _inner ? 200 : 360, _i * 60,
                                     _inner ? 0.85 : -0.55, OLD_MIKA_RING_COL,
                                     _inner ? old_mika_orrery_in
                                            : old_mika_orrery_out);
            orrery.ring[_i] = _r;
            orrery.gen[_i] = (_r == undefined) ? -1 : _r.gen;
            if (_r != undefined) _r.spin = _inner ? 1.3 : -0.9;
        }
    }

    // One pair linked at a time, walking round the six.
    if ((_t mod 84) == 0) {
        var _k = (_t div 84) mod OLD_MIKA_RING_N;
        old_mika_link(orrery, _k, (_k + 1) mod OLD_MIKA_RING_N, 68);
    }

    // One ring charged at a time, on a different period.
    if ((_t mod 130) == 60) {
        var _c = (_t div 130) mod OLD_MIKA_RING_N;
        if (ring_valid(orrery.ring[_c], orrery.gen[_c])) {
            ring_charge(orrery.ring[_c], RING_WARN, 78);
        }
    }

    if ((_t mod 118) == 58) {
        fire_fan_stack(_e.x, _e.y, 9, 3, 4.8, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 56,
                       BSHAPE_RICE, BCOL_BONE, 22);
    }
}

function old_mika_orrery_in(_ring, _g, _t) {
    if ((_t mod 58) != 26) return;
    ring_fire_tangent(_ring, 5, 3.2, _t * 3.3, BSHAPE_MOTE, OLD_MIKA_RING_COL,
                      1, 18);
}

function old_mika_orrery_out(_ring, _g, _t) {
    if ((_t mod 70) != 34) return;
    ring_fire_rim(_ring, 6, 3.4, -_t * 2.6, BSHAPE_ORB, BCOL_AMBER, 20);
}
