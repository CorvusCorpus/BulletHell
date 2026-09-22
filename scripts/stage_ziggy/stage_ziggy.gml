/// @desc Stage one: the Brimstone Reach -- waves, the Warden (midboss), and
///       Ziggy (the tutorial boss).
///
/// Every attack here (the Warden's and Ziggy's) is a placeholder, to be
/// replaced. Each attack is a function of the frame count `_t`.

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

function stage_ziggy_def() {
    return {
        id: "brimstone_reach",
        name: "THE BRIMSTONE REACH",
        subtitle: "Ziggy's proving ground",
        needs: 0,                       // unlocked from the start
        make_bg: bg_brimstone,
        build: stage_ziggy_script,


        // The stage's bosses in order, for attack practice and the encounter
        // count. `phases` is a function returning a fresh table (phase
        // structs are mutable, so they can't be shared between runs).
        bosses: [
            { name: "THE WARDEN", spawn: ziggy_midboss_spawn,
              phases: ziggy_midboss_phases },
            { name: "ZIGGY", spawn: ziggy_spawn, phases: ziggy_phases },
        ],
    };
}

/// @desc The timeline.
function stage_ziggy_script() {
    var _e = [];

    // --- first half: wisps and grimoires -------------------------------
    array_push(_e, ev(70, wave_cross(EnemyKind.Wisp, 6, -1, 180, 62, 5.6, 3,
                                     BCOL_EMBER, ziggy_fodder_pellet)));
    array_push(_e, ev(250, wave_cross(EnemyKind.Wisp, 6, 1, 300, -62, 5.6, 3,
                                      BCOL_AMBER, ziggy_fodder_pellet)));
    array_push(_e, ev(430, wave_line(EnemyKind.Grimoire, 5,
                                     -100, 140, 0, 0,
                                     460, 260, 250, 0,
                                     200, 14, BCOL_AMBER, ziggy_fodder_fan)));
    array_push(_e, ev_gate(470));

    array_push(_e, ev(590, wave_cross(EnemyKind.Gem, 5, -1, 420, 54, 6.4, 6,
                                      BCOL_GOLD, ziggy_fodder_aimed)));
    array_push(_e, ev(610, wave_cross(EnemyKind.Gem, 5, 1, 420, -54, 6.4, 6,
                                      BCOL_GOLD, ziggy_fodder_aimed)));
    array_push(_e, ev_gate(660));

    // --- the midboss ---------------------------------------------------
    array_push(_e, ev(760, wave_boss(ziggy_midboss_spawn)));
    array_push(_e, ev_gate(780));

    // --- second half: heavier, and from both sides ---------------------
    array_push(_e, ev(900, wave_line(EnemyKind.Grimoire, 6,
                                     FIELD_W + 100, 120, 0, 0,
                                     300, 200, 260, 46,
                                     230, 18, BCOL_EMBER, ziggy_fodder_ring)));
    array_push(_e, ev(960, wave_cross(EnemyKind.Wisp, 8, -1, 520, 44, 6.0, 4,
                                      BCOL_CRIMSON, ziggy_fodder_pellet, 10)));
    array_push(_e, ev_gate(1010));

    array_push(_e, ev(1130, wave_cross(EnemyKind.Gem, 6, 1, 240, 66, 6.8, 8,
                                       BCOL_AMBER, ziggy_fodder_aimed, 11)));
    array_push(_e, ev(1150, wave_line(EnemyKind.Sentry, 3,
                                      -140, 200, 0, 0,
                                      520, 300, 440, 0,
                                      250, 46, BCOL_CRIMSON,
                                      ziggy_fodder_sentry)));
    array_push(_e, ev_gate(1200));

    // --- and Ziggy -----------------------------------------------------
    array_push(_e, ev(1300, wave_sweep_field()));
    array_push(_e, ev(1360, wave_boss(ziggy_spawn)));

    return _e;
}

// ---------------------------------------------------------------------------
// What the fodder fires
// ---------------------------------------------------------------------------

function ziggy_fodder_pellet(_e, _g, _t) {
    if ((_t mod 46) != 0) return;
    fire(_e.x, _e.y, 6.2, aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
         BSHAPE_PELLET, BCOL_EMBER, 14);
}

function ziggy_fodder_fan(_e, _g, _t) {
    if ((_t mod 64) != 20) return;
    fire_fan(_e.x, _e.y, 5, 5.6,
             aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 44,
             BSHAPE_RICE, BCOL_AMBER, 16);
}

function ziggy_fodder_aimed(_e, _g, _t) {
    if ((_t mod 54) != 30) return;
    fire_stack(_e.x, _e.y, 3, 5.2, 1.5,
               aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
               BSHAPE_CRYSTAL, BCOL_GOLD, 14);
}

function ziggy_fodder_ring(_e, _g, _t) {
    if ((_t mod 76) != 40) return;
    fire_ring(_e.x, _e.y, 10, 4.6, _e.t * 7, BSHAPE_ORB, BCOL_EMBER, 18);
}

function ziggy_fodder_sentry(_e, _g, _t) {
    // Heavier fodder: a slow ring and an aimed pair, on different cycles so it
    // never fires everything on one frame.
    if ((_t mod 86) == 30) {
        fire_ring(_e.x, _e.y, 14, 4.8, _e.t * 4, BSHAPE_ORB, BCOL_CRIMSON, 20);
    }
    if ((_t mod 86) == 66) {
        fire_stack(_e.x, _e.y, 4, 6.4, 1.4,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_DART, BCOL_AMBER, 16);
    }
}

// ---------------------------------------------------------------------------
// The midboss
// ---------------------------------------------------------------------------

function ziggy_midboss_def() {
    return {
        name: "THE WARDEN",
        title: "a stone that was told to watch",
        sprite: spr_foe_sentry,
        eye: spr_eye_ziggy,
        col: BCOL_AMBER,
        radius: 46,
        spell_bg: SPELLBG_SIGIL,
        final: false,        // beating it does not end the stage
    };
}

/// @desc The Warden's two attacks.
function ziggy_midboss_phases() {
    return [
        {
            kind: AttackKind.NonSpell, name: "", col: BCOL_AMBER, bg: -1,
            hp_end: 0.45, time: 26 * FPS, attack: warden_wheel,
        },
        {
            kind: AttackKind.Spell, name: "Unblinking Vigil",
            col: BCOL_GOLD, bg: BCOL_GOLD,
            hp_end: 0.0, time: 34 * FPS, attack: warden_vigil,
        },
    ];
}

function ziggy_midboss_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 140, 260, ziggy_midboss_phases(),
                        ziggy_midboss_def());
    if (_b != undefined) {
        _b.boss.home_y = BOSS_HOME_Y - 30;
        // Shorter declaration: no name splash for a midboss.
        _b.boss.declare_t = 40;
    }
    return _b;
}

/// @desc A slowly turning wheel of spokes, plus an aimed fan.
function warden_wheel(_e, _g, _t) {
    if ((_t mod 7) == 0) {
        var _spin = _t * 2.4;
        fire_ring(_e.x, _e.y, 6, 5.4, _spin, BSHAPE_ORB, BCOL_AMBER, 12);
    }
    if ((_t mod 84) == 42) {
        fire_fan(_e.x, _e.y, 7, 6.6,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 36,
                 BSHAPE_RICE, BCOL_EMBER, 18);
    }
}

/// @desc Four beams aimed around the player that follow the Warden and sweep
///       slowly, with a slow ring between them.
function warden_vigil(_e, _g, _t) {
    var _cycle = _t mod 132;
    if (_cycle == 0) {
        var _base = aim_at(_e.x, _e.y, _g.player.x, _g.player.y);
        for (var _i = 0; _i < 4; _i++) {
            // Long enough to cross the whole field from anywhere.
            var _l = laser_beam(_e.x, _e.y, _base + _i * 90, 2300, 30,
                                BCOL_GOLD, 66, 60, 22);
            if (_l != undefined) {
                _l.src = _e;             // it follows him as he drifts
                _l.turn = 0.38;          // and sweeps
            }
        }
    }
    // Slow unaimed filler between the beams.
    if ((_t mod 24) == 0) {
        fire_ring(_e.x, _e.y, 9, 4.0, _t * 3.7, BSHAPE_PELLET, BCOL_AMBER, 14);
    }
}

// ---------------------------------------------------------------------------
// Ziggy
// ---------------------------------------------------------------------------

function ziggy_def() {
    return {
        name: "ZIGGY",
        title: "the imp who never backed down",
        sprite: spr_boss_ziggy,
        eye: spr_eye_ziggy,
        col: BCOL_CRIMSON,
        radius: 62,
        spell_bg: SPELLBG_BRIMSTONE,
        final: true,
    };
}

/// @desc Ziggy's seven attacks, in order.
function ziggy_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
          hp_end: 0.90, time: 24 * FPS, attack: ziggy_basic_fans },

        { kind: AttackKind.Spell, name: "Cinder Waltz",
          col: BCOL_AMBER, bg: BCOL_AMBER,
          hp_end: 0.75, time: 42 * FPS, attack: ziggy_cinder_waltz },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
          hp_end: 0.65, time: 24 * FPS, attack: ziggy_basic_spiral },

        { kind: AttackKind.Spell, name: "Meteor Fall",
          col: BCOL_CRIMSON, bg: BCOL_CRIMSON,
          hp_end: 0.50, time: 46 * FPS, attack: ziggy_meteor_fall },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_EMBER, bg: -1,
          hp_end: 0.40, time: 24 * FPS, attack: ziggy_basic_scatter },

        { kind: AttackKind.Spell, name: "Sundering Lash",
          col: BCOL_GOLD, bg: BCOL_GOLD,
          hp_end: 0.20, time: 50 * FPS, attack: ziggy_sundering_lash },

        { kind: AttackKind.Spell, name: "No Mere Pawn",
          col: BCOL_ROSE, bg: BCOL_ROSE,
          hp_end: 0.0, time: 60 * FPS, attack: ziggy_no_mere_pawn },
    ];
}

function ziggy_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 200, 3400, ziggy_phases(),
                        ziggy_def());
    if (_b != undefined) _b.boss.home_y = BOSS_HOME_Y;
    return _b;
}

// --- the three non-spells --------------------------------------------------

function ziggy_basic_fans(_e, _g, _t) {
    if ((_t mod 40) == 0) {
        fire_fan(_e.x, _e.y, 7, 6.3,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 54,
                 BSHAPE_FLAME, BCOL_EMBER, 16);
    }
    if ((_t mod 80) == 30) {
        fire_ring(_e.x, _e.y, 16, 4.4, _t * 2.3, BSHAPE_ORB, BCOL_CRIMSON, 20);
    }
}

function ziggy_basic_spiral(_e, _g, _t) {
    // A two-armed spiral whose arms turn at different rates.
    if ((_t mod 4) == 0) {
        fire(_e.x, _e.y, 5.6, _t * 5.1, BSHAPE_ORB, BCOL_EMBER, 10);
        fire(_e.x, _e.y, 5.6, 180 - _t * 4.1, BSHAPE_ORB, BCOL_AMBER, 10);
    }
    if ((_t mod 96) == 52) {
        fire_stack(_e.x, _e.y, 5, 6.6, 1.2,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_DART, BCOL_CRIMSON, 18);
    }
}

function ziggy_basic_scatter(_e, _g, _t) {
    if ((_t mod 62) == 0) {
        // An unaimed ring, followed by an aimed stack.
        fire_ring(_e.x, _e.y, 22, 4.9, _t * 3.1, BSHAPE_PELLET, BCOL_EMBER, 18);
    }
    if ((_t mod 62) == 24) {
        fire_stack(_e.x, _e.y, 4, 7.6, 1.5,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_NEEDLE, BCOL_GOLD, 14);
    }
    if ((_t mod 22) == 11) {
        fire_spray(_e.x, _e.y, 2, 3.0, 4.8, 90, 160,
                   BSHAPE_MOTE, BCOL_AMBER, 12);
    }
}

// --- the spells ------------------------------------------------------------

/// @desc **Cinder Waltz** -- two sets of three flame arms turning in opposite
///       directions, with a slow ring of large orbs. Nothing is aimed.
function ziggy_cinder_waltz(_e, _g, _t) {
    if ((_t mod 4) != 0) return;

    // A spiral's shape is the ratio of turn rate to bullet speed: change the
    // speed and the turn must change with it, or the arms straighten out.
    var _arms = 3;
    var _turn = _t * 1.7;
    for (var _i = 0; _i < _arms; _i++) {
        var _a = _turn + _i * (360 / _arms);
        fire(_e.x, _e.y, 5.6, _a, BSHAPE_FLAME, BCOL_AMBER, 12);
        fire(_e.x, _e.y, 5.6, -_a + 40, BSHAPE_FLAME, BCOL_EMBER, 12);
    }

    // A slow ring of big orbs every 88 frames.
    if ((_t mod 88) == 0) {
        fire_ring(_e.x, _e.y, 12, 3.0, _turn * 0.5, BSHAPE_BALL, BCOL_CRIMSON,
                  26);
    }
}

/// @desc **Meteor Fall** -- spheres fall from random x positions and split
///       into rings of 12 (`bullet_split_at`), plus an aimed fan from Ziggy.
function ziggy_meteor_fall(_e, _g, _t) {
    if ((_t mod 30) == 0) {
        var _n = 4;
        for (var _i = 0; _i < _n; _i++) {
            var _x = FIELD_X0 + 180 + random(FIELD_W - 360);
            var _b = fire(_x, FIELD_Y0 - 60, 3.4, 90 - 180, BSHAPE_SPHERE,
                          BCOL_CRIMSON, 24);
            if (_b == undefined) continue;
            _b.dir = 90 + 180;            // straight down
            _b.spin = 1.2;
            // Split frame randomised so the meteors don't burst together.
            bullet_split_at(_b, 40 + irandom(34), 12, 6.2, random(30));
        }
    }

    if ((_t mod 68) == 34) {
        fire_fan(_e.x, _e.y, 9, 5.2,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 70,
                 BSHAPE_RICE, BCOL_EMBER, 20);
    }
}

/// @desc **Sundering Lash** -- three long telegraphed beams that follow Ziggy
///       and sweep, alternating direction each cycle, with a ring of cards and
///       an aimed stack.
function ziggy_sundering_lash(_e, _g, _t) {
    var _cycle = _t mod 118;

    if (_cycle == 0) {
        var _sweep = ((_t div 118) mod 2 == 0) ? 0.46 : -0.46;
        var _base = 90 + irandom_range(-40, 40);
        for (var _i = 0; _i < 3; _i++) {
            // Longer than the field's diagonal, so the beam has no visible end.
            var _l = laser_beam(_e.x, _e.y, _base + _i * 120, 2400, 44,
                                BCOL_GOLD, 80, 60, 24);
            if (_l != undefined) {
                _l.src = _e;
                _l.turn = _sweep;
            }
        }
    }

    if ((_t mod 16) == 8) {
        fire_ring(_e.x, _e.y, 7, 4.2, _t * 4.7, BSHAPE_CARD, BCOL_EMBER, 16);
    }
    if (_cycle == 92) {
        fire_stack(_e.x, _e.y, 3, 7.0, 1.6,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_NEEDLE, BCOL_CRIMSON, 20);
    }
}

/// @desc **No Mere Pawn** -- the last spell: curved lasers, a counter-turning
///       ring of stars, an aimed fan, and after 18 seconds a slow wall of
///       ovals from the top.
function ziggy_no_mere_pawn(_e, _g, _t) {
    // Four curved lasers every 108 frames, alternating their curl. As with a
    // spiral, the curve's shape is the ratio of curl to speed.
    if ((_t mod 108) == 0) {
        var _curl = ((_t div 108) mod 2 == 0) ? 1.3 : -1.3;
        for (var _i = 0; _i < 4; _i++) {
            laser_curve(_e.x, _e.y, _t * 2.6 + _i * 90, 12.0, _curl, 34,
                        BCOL_ROSE, 108);
        }
    }

    // A ring turning the opposite way to the lasers.
    if ((_t mod 8) == 0) {
        fire_ring(_e.x, _e.y, 5, 5.1, -_t * 4.4, BSHAPE_STAR, BCOL_MAGENTA, 12);
    }

    if ((_t mod 84) == 52) {
        fire_fan(_e.x, _e.y, 11, 6.3,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 84,
                 BSHAPE_FLAME, BCOL_CRIMSON, 22);
    }

    // After 18 seconds: a slow wall of bullets falling from the top.
    if (_t > 18 * FPS && (_t mod 36) == 0) {
        var _off = ((_t div 36) mod 2) * 110;
        for (var _x = FIELD_X0 + 110 + _off; _x < FIELD_X1; _x += 220) {
            fire(_x, FIELD_Y0 - 40, 4.2, 270, BSHAPE_OVAL, BCOL_AMBER, 22);
        }
    }
}

// ---------------------------------------------------------------------------
// The roster
// ---------------------------------------------------------------------------

/// @desc Every stage in the game: the three built ones and six planned ones
///       (drawn locked on the rack; `build` undefined means not built).
function stage_list() {
    var _list = [stage_ziggy_def(), stage_grove_def(), stage_sanctum_def()];
    var _planned = [
        ["THE RED CHAPEL", "something old, and thirsty", 3],
        ["THE GLASS DESERT", "a palace under moving sand", 4],
        ["THE ROOKERY", "the birdmen's high nests", 5],
        ["THE DROWNED LIBRARY", "where the words went", 6],
        ["THE CLOCKWORK MIRE", "a swamp that keeps time", 7],
        ["THE SALT THRONE", "a court of dried things", 8],
    ];
    for (var _i = 0; _i < array_length(_planned); _i++) {
        array_push(_list, {
            id: "planned_" + string(_i),
            name: _planned[_i][0],
            subtitle: _planned[_i][1],
            needs: _planned[_i][2],
            make_bg: undefined,
            build: undefined,
        });
    }
    return _list;
}

/// @desc Is this a stage that can actually be played?
function stage_is_built(_def) {
    return _def.build != undefined;
}
