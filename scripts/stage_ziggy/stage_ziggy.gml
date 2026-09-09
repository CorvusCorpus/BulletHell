/// @desc Stage one: the Brimstone Reach, and Ziggy at the end of it.
///
/// **This is content, and it is written to be read as content.** Every attack
/// is a function of the frame count and nothing else, so a pattern is a
/// paragraph you can read top to bottom: what fires, how often, and what shape
/// it makes. Nothing here reaches into the engine; it calls `fire`,
/// `fire_ring`, `fire_fan`, `laser_beam` and `laser_curve`, which is the whole
/// vocabulary.
///
/// **Ziggy is Szuix's friend, and his fight is written that way.** He is the
/// first boss in the game and the tutorial for the whole genre: his non-spells
/// are wide and slow, every spell introduces exactly one new idea, and the
/// last one is the only place he plays for real. The spell names are his
/// boasting.
///
/// The attack table descends: `hp_end` is where each attack hands over, and
/// the bar is notched at every one of them. See `boss_functions`.

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

        // **How many graded encounters this stage has, and it is provisional.**
        // The console draws a socket per encounter so the ledger shows what is
        // still to come rather than only what has happened, and it needs the
        // total before the first one has been fought. Counting it from the
        // timeline is what should happen and cannot yet: a wave is a line in a
        // `{at, fn}` table, not a thing with a beginning and an outcome, so
        // there is nothing to count. See the note at the top of
        // `rank_functions` -- this number is the stand-in for the change that
        // makes waves gradable, and it is nine (the two midboss attacks and
        // Ziggy's seven) plus the five wave groups nobody grades yet.
        encounters: 14,

        // **Who can be practised, in the order they are met.** Attack practice
        // needs a boss's table before anything has been spawned, so a boss is
        // listed as a name, a spawner and the *function* that returns its
        // phases rather than as the phases themselves -- a table built once at
        // stage-definition time would be shared by every run that read it, and
        // a phase struct is mutable.
        //
        // It is a field on the stage rather than a list of its own because a
        // boss belongs to a stage: adding stage two means adding its bosses in
        // the same place its waves and its background go, and the practice
        // screen lays itself out from whatever it finds. See
        // `practice_functions`.
        bosses: [
            { name: "THE WARDEN", spawn: ziggy_midboss_spawn,
              phases: ziggy_midboss_phases },
            { name: "ZIGGY", spawn: ziggy_spawn, phases: ziggy_phases },
        ],
    };
}

/// @desc The timeline. Read it as a running order.
/// **The running order, and it has to run.** Every crossing speed here is
/// roughly double what it was, and the reason is the shape of the room rather
/// than taste: a wave crossing a 1920-wide field at 2.6 pixels a frame is on
/// screen for twelve seconds, which is not a wave, it is a procession. At 5.6
/// it crosses in six. The numbers it was written against are the genre's own,
/// and the genre's playfield is 384 wide -- where 2.6 crosses in two and a
/// half seconds and is exactly right.
///
/// The `at` times came down with them. They were spaced for waves that took
/// twelve seconds to leave, so shortening the waves without shortening the
/// gaps would have traded a slow stage for an empty one.
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
// What the fodder does
//
// **Fodder fires slowly and always telegraphs.** A wave exists to be cleared
// and to pay for the clearing; a wave that can kill an attentive player is a
// wave that has taken the boss's job.
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
        // A carved stone told to watch is the one caster a magic circle
        // actually suits, so the Warden keeps the generic style -- which is
        // also what proves the dispatch is doing something, since Ziggy on the
        // same stage does not.
        spell_bg: SPELLBG_SIGIL,
        final: false,        // beating it does not end the stage
    };
}

/// @desc The Warden's two attacks.
///
///       **A function of its own rather than a list inside the spawner**, so
///       the table can be read without putting an enemy on the field. Attack
///       practice lists a boss's attacks before it has spawned anything, and
///       `ziggy_phases` was already written this way -- having one boss's
///       table reachable and the other's buried inside its spawner is the kind
///       of inconsistency that turns a list into two code paths.
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
        // A midboss gets no name splash: the ceremony is the *boss's*, and
        // spending it here would make the real arrival mean less.
        _b.boss.declare_t = 40;
    }
    return _b;
}

/// @desc A slowly turning wheel of spokes. The first pattern in the game that
///       has to be *walked through* rather than shot around.
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

/// @desc Four eyes that open one after another, each sweeping a beam. The
///       stage's introduction to the laser, at the slowest speed it will ever
///       be shown at.
function warden_vigil(_e, _g, _t) {
    var _cycle = _t mod 132;
    if (_cycle == 0) {
        var _base = aim_at(_e.x, _e.y, _g.player.x, _g.player.y);
        for (var _i = 0; _i < 4; _i++) {
            // **Long enough to cross the field from anywhere on it.** A beam
            // measured for a narrow playfield stops in mid-air on a wide one,
            // and a wall of light that ends halfway across the screen reads as
            // the boss having missed rather than as something to get out of.
            var _l = laser_beam(_e.x, _e.y, _base + _i * 90, 2300, 30,
                                BCOL_GOLD, 66, 60, 22);
            if (_l != undefined) {
                _l.src = _e;             // it follows him as he drifts
                _l.turn = 0.38;          // and sweeps
            }
        }
    }
    // Filler between the beams, so the gaps are not empty. Slow, wide, and
    // aimed nowhere -- it is texture, and the beams are the pattern.
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
        // His four spells are four rooms in one forge. See
        // `spell_bg_brimstone`.
        spell_bg: SPELLBG_BRIMSTONE,
        final: true,
    };
}

/// @desc The seven attacks, in order. The `hp_end` column is the fight.
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
//
// **All three are the same idea at three speeds**, which is what a non-spell
// is for: it is the boss's handwriting, and the spells are the sentences. Wide
// aimed fans of flame, a slow ring underneath, and nothing that has to be read
// twice.

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
    // A two-armed spiral, and the arms turn at slightly different rates, so
    // the interference between them is the pattern rather than the arms.
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
        // A ring that is *not* aimed, immediately followed by an aimed stack
        // through the gap it leaves. The two together are the whole lesson of
        // a non-spell: read the shape, then read the aim.
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

/// @desc **Cinder Waltz** -- two arms of flame turning in opposite directions.
///
///       The first spell in the game, and it teaches one thing: a pattern that
///       looks like a wall is usually a spiral with gaps in it, and the gaps
///       move at a speed you can walk at. Nothing here is aimed, so it is
///       survivable by standing still in the right place -- which is exactly
///       the lesson a first spell should hand over.
function ziggy_cinder_waltz(_e, _g, _t) {
    if ((_t mod 4) != 0) return;

    // **The arms turn more slowly than they used to, because the bullets in
    // them travel faster.** What the player reads in a spiral is the *gap*,
    // and how wide a gap is depends on both numbers at once: leaving the turn
    // rate alone while doubling the speed pulls every arm out into a straight
    // radial line and the spiral stops being one. Halving the turn as the
    // speed doubled keeps the arm the same shape on screen and simply feeds it
    // twice as fast, which is the thing that was actually wanted.
    var _arms = 3;
    var _turn = _t * 1.7;
    for (var _i = 0; _i < _arms; _i++) {
        var _a = _turn + _i * (360 / _arms);
        fire(_e.x, _e.y, 5.6, _a, BSHAPE_FLAME, BCOL_AMBER, 12);
        fire(_e.x, _e.y, 5.6, -_a + 40, BSHAPE_FLAME, BCOL_EMBER, 12);
    }

    // Every second and a bit, one slow ring of big orbs -- the "and breathe"
    // beat that keeps a fast spiral from being a blur.
    if ((_t mod 88) == 0) {
        fire_ring(_e.x, _e.y, 12, 3.0, _turn * 0.5, BSHAPE_BALL, BCOL_CRIMSON,
                  26);
    }
}

/// @desc **Meteor Fall** -- spheres drift down and burst into rings.
///
///       This is the spell that teaches `bullet_split_at`, and it is why
///       splitting bullets keep the parent's colour: the burst has to be
///       legible as *that* sphere going off rather than as bullets appearing.
///
///       The spheres are slow and the shards are fast, so the danger is where
///       the sphere *was* a moment ago -- which is a different kind of reading
///       from anything before it in the stage.
function ziggy_meteor_fall(_e, _g, _t) {
    if ((_t mod 30) == 0) {
        // Four rather than three: the field is wide, and three meteors spread
        // across 1920 pixels leaves lanes a player can stand in without ever
        // reading the pattern.
        var _n = 4;
        for (var _i = 0; _i < _n; _i++) {
            var _x = FIELD_X0 + 180 + random(FIELD_W - 360);
            var _b = fire(_x, FIELD_Y0 - 60, 3.4, 90 - 180, BSHAPE_SPHERE,
                          BCOL_CRIMSON, 24);
            if (_b == undefined) continue;
            _b.dir = 90 + 180;            // straight down
            _b.spin = 1.2;
            // Twelve shards leaving at 6.2, the ring starting anywhere, and
            // the frame scattered so four meteors never burst in chorus.
            bullet_split_at(_b, 40 + irandom(34), 12, 6.2, random(30));
        }
    }

    // Ziggy's own contribution, so the spell is not purely weather.
    if ((_t mod 68) == 34) {
        fire_fan(_e.x, _e.y, 9, 5.2,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 70,
                 BSHAPE_RICE, BCOL_EMBER, 20);
    }
}

/// @desc **Sundering Lash** -- telegraphed beams across the whole field.
///
///       Three beams at a time, warned for well over a second, sweeping in
///       alternate directions. The warning is the spell: everything about the
///       pattern is knowable before any of it can hurt, and what the player is
///       being asked for is the nerve to stand still while it is drawn.
function ziggy_sundering_lash(_e, _g, _t) {
    var _cycle = _t mod 118;

    if (_cycle == 0) {
        var _sweep = ((_t div 118) mod 2 == 0) ? 0.46 : -0.46;
        var _base = 90 + irandom_range(-40, 40);
        for (var _i = 0; _i < 3; _i++) {
            // 2400 long, because the diagonal of this field is 2200 -- a beam
            // shorter than that has an end, and a wall of light with a visible
            // end is a wall the player walks round.
            var _l = laser_beam(_e.x, _e.y, _base + _i * 120, 2400, 44,
                                BCOL_GOLD, 80, 60, 24);
            if (_l != undefined) {
                _l.src = _e;
                _l.turn = _sweep;
            }
        }
    }

    // Bullets down the safe lanes, so standing in a gap is not free.
    if ((_t mod 16) == 8) {
        fire_ring(_e.x, _e.y, 7, 4.2, _t * 4.7, BSHAPE_CARD, BCOL_EMBER, 16);
    }
    if (_cycle == 92) {
        fire_stack(_e.x, _e.y, 3, 7.0, 1.6,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_NEEDLE, BCOL_CRIMSON, 20);
    }
}

/// @desc **No Mere Pawn** -- the finale, and the only time he plays for real.
///
///       Curved lasers spiralling out of him, rings between them, and an aimed
///       stack that arrives on the beat. It is everything the stage has taught,
///       run at once -- which is what a last spell is for, and why nothing in
///       it is new.
function ziggy_no_mere_pawn(_e, _g, _t) {
    // Four curved lashes, thrown every two seconds, alternating their curl.
    if ((_t mod 108) == 0) {
        // The curl comes down as the speed goes up, for the reason spelled out
        // in `ziggy_cinder_waltz`: a lash is a *shape*, and its shape is the
        // ratio of the two. Turned as hard at twelve pixels a frame it would
        // close into a circle round him instead of reaching the player.
        var _curl = ((_t div 108) mod 2 == 0) ? 1.3 : -1.3;
        for (var _i = 0; _i < 4; _i++) {
            laser_curve(_e.x, _e.y, _t * 2.6 + _i * 90, 12.0, _curl, 34,
                        BCOL_ROSE, 108);
        }
    }

    // The ring, turning the other way from the lashes so the two never lock
    // into one shape.
    if ((_t mod 8) == 0) {
        fire_ring(_e.x, _e.y, 5, 5.1, -_t * 4.4, BSHAPE_STAR, BCOL_MAGENTA, 12);
    }

    // And the aimed pressure, which is what stops the answer being "find the
    // one safe spot and stay in it".
    if ((_t mod 84) == 52) {
        fire_fan(_e.x, _e.y, 11, 6.3,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 84,
                 BSHAPE_FLAME, BCOL_CRIMSON, 22);
    }

    // In the last stretch he adds a slow wall from the top -- the only thing
    // in the fight that is not centred on him, so the player has to stop
    // reading his position and start reading the screen.
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

/// @desc Every stage in the game. **Twelve slots, one of them awake** -- the
///       select screen draws every entry and marks the unbuilt ones locked, so
///       filling one in is a `stage_def` and its content file rather than a
///       change to the screen. The same argument the Wordsearch roster makes
///       for drawing twelve character slots from the first build.
function stage_list() {
    var _list = [stage_ziggy_def(), stage_grove_def()];
    var _planned = [
        ["THE RED CHAPEL", "something old, and thirsty", 2],
        ["THE GLASS DESERT", "a palace under moving sand", 3],
        ["THE ROOKERY", "the birdmen's high nests", 4],
        ["THE DROWNED LIBRARY", "where the words went", 5],
        ["THE CLOCKWORK MIRE", "a swamp that keeps time", 6],
        ["THE SALT THRONE", "a court of dried things", 7],
    ];
    for (var _i = 0; _i < array_length(_planned); _i++) {
        array_push(_list, {
            id: "planned_" + string(_i),
            name: _planned[_i][0],
            subtitle: _planned[_i][1],
            needs: _planned[_i][2],
            make_bg: undefined,       // undefined is the whole of "not built"
            build: undefined,
        });
    }
    return _list;
}

/// @desc Is this a stage that can actually be played?
function stage_is_built(_def) {
    return _def.build != undefined;
}
