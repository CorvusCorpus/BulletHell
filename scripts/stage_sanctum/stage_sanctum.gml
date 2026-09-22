/// @desc Stage three: the Gilded Sanctum, and Mika at the end of it.
///
/// Mika's fight is being rebuilt as fifteen attacks, one slot at a time (see
/// `mika_slots`). The stage as it was before the rebuild is kept on its own
/// rack card in `stage_sanctum_old`. The waves and the Proctor are
/// placeholders and are not part of the rebuild.
///
/// The fight is built on rings (`ring_functions`). Every ring is the same
/// size (`RING_R`; owner's rule).
///
/// Mika is head mage to Ashiah, the Living God of Death.

// ---------------------------------------------------------------------------
// Stage numbers (engine-level ring numbers live in `constants`)
// ---------------------------------------------------------------------------

#macro MIKA_RING_COL BCOL_GOLD

// How many rings his six-ring formations use.
#macro MIKA_RING_N 6

// The radius his formations sit at.
#macro MIKA_ORBIT 300

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

function stage_sanctum_def() {
    return {
        id: "gilded_sanctum",
        name: "THE GILDED SANCTUM",
        subtitle: "the death-god's hall of rings",
        needs: 0,                       // unlocked from the start, for now
        make_bg: bg_sanctum,
        build: stage_sanctum_script,


        // `turned`: Mika is fought after the hall opens, so practice starts
        // him in the open room (see `practice_begin`).
        bosses: [
            { name: "THE PROCTOR", spawn: sanctum_midboss_spawn,
              phases: sanctum_midboss_phases },
            { name: "MIKA", spawn: mika_spawn, phases: mika_phases,
              turned: true },
        ],
    };
}

/// @desc The running order. The second wave group flies in behind two idle
///       rings, so the player meets a ring before the Proctor uses them.
function stage_sanctum_script() {
    var _e = [];

    // --- the way in ----------------------------------------------------
    array_push(_e, ev(80, wave_cross(EnemyKind.Wisp, 6, -1, 210, 56, 5.6, 3,
                                     BCOL_GOLD, sanctum_fodder_pellet)));
    array_push(_e, ev(230, wave_cross(EnemyKind.Wisp, 6, 1, 330, -56, 5.6, 3,
                                      BCOL_AMBER, sanctum_fodder_pellet)));
    array_push(_e, ev_gate(280));

    // --- two idle rings --------------------------------------------------
    array_push(_e, ev(400, wave_sanctum_gateposts()));
    array_push(_e, ev(430, wave_line(EnemyKind.Grimoire, 5,
                                     -100, 160, 0, 0,
                                     420, 260, 270, 0,
                                     220, 14, BCOL_BONE,
                                     sanctum_fodder_fan)));
    array_push(_e, ev_gate(470));

    array_push(_e, ev(600, wave_cross(EnemyKind.Gem, 5, -1, 400, 52, 6.2, 6,
                                      BCOL_AMBER, sanctum_fodder_aimed)));
    array_push(_e, ev(620, wave_cross(EnemyKind.Gem, 5, 1, 400, -52, 6.2, 6,
                                      BCOL_AMBER, sanctum_fodder_aimed)));
    array_push(_e, ev_gate(670));

    // --- the midboss ---------------------------------------------------
    array_push(_e, ev(770, wave_boss(sanctum_midboss_spawn)));
    array_push(_e, ev_gate(790));

    // The hall opens (the camera rises and levels out). Stage time is held
    // while a boss is up, so this fires right after the Proctor is beaten.
    array_push(_e, ev(792, wave_bg_omen()));

    array_push(_e, ev(900, wave_line(EnemyKind.Sentry, 3,
                                     -140, 200, 0, 0,
                                     500, 300, 440, 0,
                                     250, 46, BCOL_GOLD,
                                     sanctum_fodder_sentry)));
    array_push(_e, ev(960, wave_cross(EnemyKind.Wisp, 8, -1, 500, 42, 6.2, 4,
                                      BCOL_BONE, sanctum_fodder_pellet, 10)));
    array_push(_e, ev_gate(1010));

    array_push(_e, ev(1120, wave_sanctum_gateposts()));
    array_push(_e, ev(1150, wave_cross(EnemyKind.Gem, 6, 1, 250, 64, 6.6, 8,
                                       BCOL_GOLD, sanctum_fodder_aimed, 11)));
    array_push(_e, ev(1170, wave_line(EnemyKind.Grimoire, 6,
                                      FIELD_W + 100, 140, 0, 0,
                                      320, 220, 250, 40,
                                      230, 18, BCOL_BONE,
                                      sanctum_fodder_fan)));
    array_push(_e, ev_gate(1220));

    array_push(_e, ev(1320, wave_sweep_field()));
    array_push(_e, ev(1380, wave_boss(mika_spawn)));

    return _e;
}

/// @desc Two rings standing in the field for 15 seconds: they block shots and
///       hurt to touch, and do nothing else.
function wave_sanctum_gateposts() {
    return function(_g) {
        for (var _i = -1; _i <= 1; _i += 2) {
            var _r = ring_new(FIELD_CX + _i * 260, FIELD_Y0 + 420,
                              MIKA_RING_COL, 15 * FPS);
            if (_r != undefined) _r.spin = _i * 0.35;
        }
    };
}

// ---------------------------------------------------------------------------
// Fodder patterns (placeholders)
// ---------------------------------------------------------------------------

function sanctum_fodder_pellet(_e, _g, _t) {
    if ((_t mod 48) != 0) return;
    fire(_e.x, _e.y, 6.0, aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
         BSHAPE_PELLET, BCOL_GOLD, 14);
}

function sanctum_fodder_fan(_e, _g, _t) {
    if ((_t mod 64) != 20) return;
    fire_fan(_e.x, _e.y, 5, 5.4,
             aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 44,
             BSHAPE_RICE, BCOL_BONE, 16);
}

function sanctum_fodder_aimed(_e, _g, _t) {
    if ((_t mod 54) != 30) return;
    fire_stack(_e.x, _e.y, 3, 5.2, 1.5,
               aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
               BSHAPE_CRYSTAL, BCOL_AMBER, 14);
}

function sanctum_fodder_sentry(_e, _g, _t) {
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
// Ring helpers for this fight
// ---------------------------------------------------------------------------

/// @desc A ring orbiting the caster at `_dist`, starting at `_ang0` and
///       turning `_rate` degrees a frame. It is attached to the boss, so it
///       keeps station through the boss's movement. `_shoot(ring, run, frame)`
///       is the ring's own pattern. The member is named `shoot`, not `fire`:
///       inside a method a struct member shadows the global function.
function mika_orbit_ring(_e, _dist, _ang0, _rate, _col, _shoot, _ttl = 0) {
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
        // call to a struct member from a call to a function that doesn't
        // exist.
        var _fn = shoot;
        if (_fn != undefined) _fn(_ring, _run, _t);
    });
    return _ring;
}

/// @desc A ring standing at a point in the field, with a pattern of its own.
function mika_place_ring(_x, _y, _col, _shoot, _ttl = 0) {
    var _ring = ring_new(_x, _y, _col, _ttl);
    if (_ring == undefined) return undefined;
    if (_shoot != undefined) _ring.act = _shoot;
    return _ring;
}

/// @desc A formation of `_n` orbiting rings, returned as `{ring[], gen[]}` so
///       each remembered ring can be checked with `ring_valid` (pooled rings
///       are reused).
function mika_formation(_e, _n, _dist, _rate, _col, _shoot, _ttl, _spin) {
    var _f = { ring: [], gen: [] };
    for (var _i = 0; _i < _n; _i++) {
        var _r = mika_orbit_ring(_e, _dist, _i * (360 / _n), _rate, _col,
                                 _shoot, _ttl);
        _f.ring[_i] = _r;
        _f.gen[_i] = (_r == undefined) ? -1 : _r.gen;
        if (_r != undefined) _r.spin = _spin;
    }
    return _f;
}

/// @desc String current between two members of a formation, if both are still
///       the rings they were.
function mika_link(_f, _a, _b, _frames) {
    if (ring_valid(_f.ring[_a], _f.gen[_a])
        && ring_valid(_f.ring[_b], _f.gen[_b])) {
        ring_link(_f.ring[_a], _f.ring[_b], _frames);
    }
}

// ---------------------------------------------------------------------------
// The Proctor (midboss; placeholder)
// ---------------------------------------------------------------------------

function sanctum_midboss_def() {
    return {
        name: "THE PROCTOR",
        title: "one of the lesser hands",
        // Placeholder art: stage one's sentry.
        sprite: spr_foe_sentry,
        eye: spr_eye_mika,
        col: BCOL_GOLD,
        radius: 46,
        spell_bg: SPELLBG_SIGIL,
        final: false,
    };
}

function sanctum_midboss_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_GOLD, bg: -1,
          hp_end: 0.45, time: 24 * FPS, attack: proctor_marking },
        { kind: AttackKind.Spell, name: "Second Reading",
          col: BCOL_AMBER, bg: BCOL_INDIGO,
          hp_end: 0.0, time: 30 * FPS, attack: proctor_second_reading },
    ];
}

function sanctum_midboss_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 140, 300,
                        sanctum_midboss_phases(), sanctum_midboss_def());
    if (_b != undefined) {
        _b.boss.home_y = BOSS_HOME_Y - 30;
        _b.boss.declare_t = 40;      // a midboss gets no name splash
    }
    return _b;
}

/// @desc Two rings circling him, throwing bullets off their rims.
function proctor_marking(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, 2, 210, 1.05, BCOL_GOLD, proctor_rim, 0, 0.7);
    }
    if ((_t mod 84) == 40) {
        fire_fan_stack(_e.x, _e.y, 7, 2, 5.0, 1.1,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                       BSHAPE_RICE, BCOL_BONE, 20);
    }
}

function proctor_rim(_ring, _g, _t) {
    if ((_t mod 58) != 24) return;
    ring_fire_rim(_ring, 8, 3.6, _t * 2.7, BSHAPE_ORB, BCOL_GOLD, 18);
}

/// @desc Three rings walking down the field, each with a beam through it.
function proctor_second_reading(_e, _g, _t) {
    var _cycle = _t mod 220;
    if (_cycle == 0) {
        for (var _i = 0; _i < 3; _i++) {
            var _r = mika_place_ring(FIELD_X0 + FIELD_W * (0.25 + _i * 0.25),
                                     FIELD_Y0 + 150, BCOL_AMBER,
                                     proctor_walker, 200);
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

function proctor_walker(_ring, _g, _t) {
    if (_t == 26) {
        ring_beam(_ring, 90, 2200, 26, BCOL_AMBER, 60, 90, 20);
    }
    if ((_t mod 46) == 20) {
        ring_fire_tangent(_ring, 6, 3.4, _t * 3.1, BSHAPE_MOTE, BCOL_AMBER,
                          1, 16);
    }
}

// ---------------------------------------------------------------------------
// Mika
//
// Fifteen attacks (owner's brief): seven non-spells that are variations of
// each other and act as breathers, each followed by a spell, then an eighth
// spell to finish. Every one hand-crafted, complex and built round Mika and
// his rings. Slots are named `N1`..`N7` and `S1`..`S8` (`mika_slot_name`).
// ---------------------------------------------------------------------------

#macro MIKA_NONSPELLS 7
#macro MIKA_SPELLS 8

// The background wash all his spells currently use.
#macro MIKA_SPELL_WASH BCOL_INDIGO

function mika_def() {
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

/// @desc The fifteen slots, one row each in fight order. This is the only
///       list to edit; `mika_phases` derives the phase table from it.
///
///       A row is `{name, col, hp, time, attack, move?}`. A name makes it a
///       spell. `hp` is the share of his health the slot is worth; thresholds
///       and his total are summed from it, so retuning one slot moves nothing
///       else.
///
///       Current state (keep this true):
///           N1  written: the mill           S1  old placeholder, Gilded Aperture
///           N2  written: the mill mirrored  S2  old placeholder, Ashiah's Circuit
///           N3  draft: the quad             S3  old placeholder, Three Open Gates
///           N4  draft: the quad mirrored    S4  unwritten
///           N5  draft: the crown            S5  unwritten
///           N6  draft: the crown mirrored   S6  unwritten
///           N7  draft: the rush             S7  unwritten
///                                           S8  old placeholder, Grand Orrery
///
///       To write a slot: put the attack in its own script under the
///       `Scripts/mika` folder (the non-spells share `mika_nonspells`), point
///       the row at it, and give it a health share and a clock.
function mika_slots() {
    return [
        // N1 -- the mill (`mika_nonspells`). `Step`: he holds still while the
        // rings throw and hops between bursts. Its health is priced for his
        // rings blocking part of the player's fire.
        { name: "", col: BCOL_AMBER, hp: 260, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n1_sandmill },
        // S1
        { name: "Gilded Aperture", col: BCOL_GOLD, hp: 392, time: 40 * FPS,
          move: BossMove.Fixed, attack: mika_gilded_aperture },

        // N2 -- N1 mirrored.
        { name: "", col: BCOL_AMBER, hp: 260, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n2_sandmill },
        // S2
        { name: "Ashiah's Circuit", col: BCOL_CYAN, hp: 476,
          time: 42 * FPS, move: BossMove.Fixed, attack: mika_ashiah_circuit },

        // N3 -- the quad (draft). Four rings block more of the player's fire:
        // measured headlessly, 16% of shots reach him against 24% for the
        // pair, so its health is N1's times 0.69.
        { name: "", col: BCOL_AMBER, hp: 180, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n3_sandquad },
        // S3
        { name: "Three Open Gates", col: BCOL_AMBER, hp: 448,
          time: 44 * FPS, attack: mika_three_gates },

        // N4 -- N3 mirrored.
        { name: "", col: BCOL_AMBER, hp: 180, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n4_sandquad },
        mika_unwritten_row(true, 4),     // S4

        // N5 -- the crown (draft). 14% of shots reach him through six rings,
        // so its health is N1's times 0.60.
        { name: "", col: BCOL_AMBER, hp: 156, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n5_sandcrown },
        mika_unwritten_row(true, 5),     // S5

        // N6 -- N5 mirrored.
        { name: "", col: BCOL_AMBER, hp: 156, time: 35 * FPS,
          move: BossMove.Step, attack: mika_n6_sandcrown },
        mika_unwritten_row(true, 6),     // S6

        // N7 -- the rush (draft). A shorter clock; health is N1's times 0.60
        // (the same blocking as the crown), scaled by 30/35 for the clock.
        { name: "", col: BCOL_AMBER, hp: 134, time: 30 * FPS,
          move: BossMove.Step, attack: mika_n7_sandrush },
        mika_unwritten_row(true, 7),     // S7

        // S8
        { name: "Grand Orrery", col: BCOL_GOLD, hp: 504, time: 50 * FPS,
          move: BossMove.Fixed, attack: mika_grand_orrery },
    ];
}

/// @desc His whole health: every slot's share, summed.
function mika_hp() {
    var _l = mika_slots();
    var _sum = 0;
    for (var _i = 0; _i < array_length(_l); _i++) _sum += _l[_i].hp;
    return _sum;
}

/// @desc The phase table the fight and the attack list read, derived from
///       `mika_slots`. Built fresh on every call, because phase structs are
///       mutable.
function mika_phases() {
    var _l = mika_slots();
    var _n = array_length(_l);
    var _total = 0;
    for (var _i = 0; _i < _n; _i++) _total += _l[_i].hp;

    var _out = [];
    var _left = _total;
    for (var _i = 0; _i < _n; _i++) {
        var _s = _l[_i];
        var _spell = (_s.name != "");
        _left -= _s.hp;
        array_push(_out, {
            kind: _spell ? AttackKind.Spell : AttackKind.NonSpell,
            name: _s.name,
            col: _s.col,
            bg: _spell ? MIKA_SPELL_WASH : -1,
            // Exactly zero on the last slot: the sum is taken back off in the
            // order it was added.
            hp_end: _left / _total,
            time: _s.time,
            move: _s[$ "move"] ?? BossMove.Drift,
            attack: _s.attack,
        });
    }
    return _out;
}

function mika_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, mika_hp(), mika_phases(),
                      mika_def());
}

/// @desc The slot name of phase `_i`: `N1`..`N7` for the non-spells,
///       `S1`..`S8` for the spells. Used by the screenshot scenes.
function mika_slot_name(_i) {
    if (_i >= 2 * MIKA_NONSPELLS) {
        return "S" + string(_i - MIKA_NONSPELLS + 1);
    }
    return (((_i mod 2) == 0) ? "N" : "S") + string((_i div 2) + 1);
}

// ---------------------------------------------------------------------------
// Unwritten slots
//
// A plain stub so the fight and the attack list run through every slot: a
// ring or two turning round him and one slow pattern. Stub spells are named
// `Unwritten Spell N`.
// ---------------------------------------------------------------------------

/// @desc The row for slot `N_k` or `S_k` while it is unwritten.
function mika_unwritten_row(_spell, _k) {
    return {
        name: _spell ? ("Unwritten Spell " + string(_k)) : "",
        col: BCOL_BONE,
        hp: _spell ? 440 : 320,
        time: (_spell ? 40 : 24) * FPS,
        attack: _spell ? mika_unwritten_spell : mika_unwritten_nonspell,
    };
}

function mika_unwritten_nonspell(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, 1, 250, 0.8, BCOL_BONE, undefined, 0, 0.6);
    }
    if ((_t mod 60) == 30) {
        fire_fan(_e.x, _e.y, 5, 5.0,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 40,
                 BSHAPE_RICE, BCOL_BONE, 18);
    }
}

function mika_unwritten_spell(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, 2, 250, 0.8, BCOL_BONE, undefined, 0, 0.6);
    }
    if ((_t mod 50) == 20) {
        fire_ring(_e.x, _e.y, 16, 3.8, _t * 3.3, BSHAPE_ORB, BCOL_BONE, 20);
    }
}

// ---------------------------------------------------------------------------
// Old placeholders still in S1-S3 and S8
//
// Delete each one, and anything only it uses, when its slot is written. The
// frozen copies in `stage_sanctum_old` keep them playable.
// ---------------------------------------------------------------------------

/// @desc **Gilded Aperture.** Six rings on one orbit round him, turning; the
///       gaps between them are the lines to the boss. `Fixed`, because the
///       formation is measured from his position. Its volleys run round the
///       orbit rather than out of it, so they don't close the gaps.
function mika_gilded_aperture(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, MIKA_RING_N, MIKA_ORBIT, 0.55, MIKA_RING_COL,
                       mika_aperture_rim, 0, 1.0);
    }
    // His own fire: slow, wide and aimed.
    if ((_t mod 96) == 46) {
        fire_fan_stack(_e.x, _e.y, 9, 2, 4.6, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 60,
                       BSHAPE_RICE, BCOL_BONE, 22);
    }
}

/// @desc The aperture rings' volleys, in cyan so they stand apart from the
///       gold rings.
function mika_aperture_rim(_ring, _g, _t) {
    if ((_t mod 50) != 22) return;
    ring_fire_tangent(_ring, 5, 3.2, _t * 2.2, BSHAPE_MOTE, BCOL_CYAN, 1, 16);
}

/// @desc **Ashiah's Circuit.** Six rings on an orbit, alternate pairs strung
///       with lethal current (three bars, three open doors); the pairing
///       shifts every few seconds so the doors move.
function mika_ashiah_circuit(_e, _g, _t) {
    static circuit = { ring: [], gen: [] };

    if (_t == 0) {
        circuit = mika_formation(_e, MIKA_RING_N, MIKA_ORBIT, 0.60, BCOL_CYAN,
                                 mika_circuit_rim, 0, 1.2);
    }

    // The pairing alternates between (0,1)(2,3)(4,5) and (1,2)(3,4)(5,0).
    if ((_t mod 190) == 0) {
        var _off = ((_t div 190) mod 2);
        for (var _k = 0; _k < 3; _k++) {
            var _a = (_k * 2 + _off) mod MIKA_RING_N;
            var _b = (_a + 1) mod MIKA_RING_N;
            mika_link(circuit, _a, _b, 160);
        }
    }

    if ((_t mod 34) == 16) {
        fire_ring(_e.x, _e.y, 5, 3.4, _t * 6.7, BSHAPE_MOTE, BCOL_BONE, 16);
    }
}

function mika_circuit_rim(_ring, _g, _t) {
    if ((_t mod 74) != 30) return;
    ring_fire_rim(_ring, 5, 3.2, _t * 4.1, BSHAPE_ORB, BCOL_CYAN, 18);
}

/// @desc **Three Open Gates.** Three rings drifting across the field, each
///       with a turning beam through its middle (`ring_beam`).
function mika_three_gates(_e, _g, _t) {
    if ((_t mod 260) == 0) {
        for (var _i = 0; _i < 3; _i++) {
            var _r = mika_place_ring(
                FIELD_X0 + FIELD_W * (0.25 + _i * 0.25),
                FIELD_Y0 + 330 + ((_i mod 2) ? 110 : 0),
                BCOL_AMBER, mika_gate_beam, 250);
            if (_r == undefined) break;
            _r.spin = ((_i mod 2) ? -1 : 1) * 1.2;
            _r.vx = (_i - 1) * 0.9;
        }
    }
    if ((_t mod 30) == 14) {
        fire_ring(_e.x, _e.y, 7, 3.6, -_t * 3.7, BSHAPE_PELLET, BCOL_GOLD, 16);
    }
}

function mika_gate_beam(_ring, _g, _t) {
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

/// @desc **Grand Orrery.** Six rings on two counter-rotating orbits, one
///       adjacent pair strung with current at a time, one band charged at a
///       time, and volleys off every rim.
function mika_grand_orrery(_e, _g, _t) {
    static orrery = { ring: [], gen: [] };

    if (_t == 0) {
        orrery = { ring: [], gen: [] };
        for (var _i = 0; _i < MIKA_RING_N; _i++) {
            var _inner = (_i mod 2) == 0;
            var _r = mika_orbit_ring(_e, _inner ? 200 : 360, _i * 60,
                                     _inner ? 0.85 : -0.55, MIKA_RING_COL,
                                     _inner ? mika_orrery_in
                                            : mika_orrery_out);
            orrery.ring[_i] = _r;
            orrery.gen[_i] = (_r == undefined) ? -1 : _r.gen;
            if (_r != undefined) _r.spin = _inner ? 1.3 : -0.9;
        }
    }

    // One pair strung at a time, walking round the six.
    if ((_t mod 84) == 0) {
        var _k = (_t div 84) mod MIKA_RING_N;
        mika_link(orrery, _k, (_k + 1) mod MIKA_RING_N, 68);
    }

    // One band charged at a time, on a different period.
    if ((_t mod 130) == 60) {
        var _c = (_t div 130) mod MIKA_RING_N;
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

function mika_orrery_in(_ring, _g, _t) {
    if ((_t mod 58) != 26) return;
    ring_fire_tangent(_ring, 5, 3.2, _t * 3.3, BSHAPE_MOTE, MIKA_RING_COL,
                      1, 18);
}

function mika_orrery_out(_ring, _g, _t) {
    if ((_t mod 70) != 34) return;
    ring_fire_rim(_ring, 6, 3.4, -_t * 2.6, BSHAPE_ORB, BCOL_AMBER, 20);
}
