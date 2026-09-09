/// @desc Stage two: the Hollow Grove, and Briar at the end of it.
///
/// **This stage exists for its background and the fight in it is a
/// placeholder, and both halves of that are deliberate.** What was wanted was
/// a wood flown through at night under a moon that turns to blood -- see
/// `bg_grove` -- and a background cannot be judged from a still: it has to be
/// seen with danmaku over it, a boss in front of it and the console beside it,
/// which means there has to be a stage. So there is one, it is the shortest
/// honest stage this engine can hold, and every pattern in it is built out of
/// helpers that already existed.
///
/// **Nothing here is tuned and it does not pretend to be.** Briar's attacks
/// are five plain shapes at grove hues; they are not her handwriting, because
/// she does not have one yet. What they are for is putting the right number of
/// bullets on the screen at the right sort of speeds so the background can be
/// looked at underneath them, and so the turn has something to happen in the
/// middle of. When she is written for real, this table is what gets replaced
/// and nothing else on this screen has to change.
///
/// The fodder is stage one's, tinted. That is not laziness either -- it is why
/// `tools/make_enemies.py` draws four greyscale shapes and the game tints them
/// at draw time. Crimson wisps over brimstone; jade and violet ones here.

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

function stage_grove_def() {
    return {
        id: "hollow_grove",
        name: "THE HOLLOW GROVE",
        subtitle: "a wood that keeps its dead",
        // **Open from the start, for as long as the fight in it is a
        // placeholder.** The rack's locks are there to pace a first
        // playthrough, and pacing a playthrough of a stage that exists to be
        // *looked at* is a circle -- the same one the drafting table's gating
        // note is about. It goes back to `1` on the day Briar has a fight
        // worth reaching, and it is one number.
        needs: 0,
        make_bg: bg_grove,
        build: stage_grove_script,

        // Provisional, exactly as stage one's is: seven attacks and five wave
        // groups, and nothing counts the wave groups yet. See `rank_functions`.
        encounters: 12,

        bosses: [
            { name: "THE HUSK", spawn: grove_midboss_spawn,
              phases: grove_midboss_phases },
            { name: "BRIAR", spawn: briar_spawn, phases: briar_phases },
        ],
    };
}

/// @desc The running order.
///
///       **The turn is a line in the timeline, and that is the whole of how
///       the blood moon is triggered.** It could have been a hook off
///       `on_boss_beaten`, and that would have been a second way for a run to
///       tell a background something. It does not need one: the stage clock is
///       already held while a boss is on the field, so an event written just
///       after the midboss's gate fires on the frame the midboss is done and
///       not before. A stage says when its own second half begins, in its own
///       running order, where somebody reading it can see it.
function stage_grove_script() {
    var _e = [];

    // --- the way in ----------------------------------------------------
    array_push(_e, ev(80, wave_cross(EnemyKind.Wisp, 6, -1, 200, 58, 5.4, 3,
                                     BCOL_JADE, grove_fodder_pellet)));
    array_push(_e, ev(240, wave_cross(EnemyKind.Wisp, 6, 1, 330, -58, 5.4, 3,
                                      BCOL_SPRING, grove_fodder_pellet)));
    array_push(_e, ev(420, wave_line(EnemyKind.Grimoire, 5,
                                     -100, 150, 0, 0,
                                     440, 250, 260, 0,
                                     200, 14, BCOL_VIOLET,
                                     grove_fodder_fan)));
    array_push(_e, ev_gate(460));

    array_push(_e, ev(580, wave_cross(EnemyKind.Gem, 5, -1, 400, 52, 6.2, 6,
                                      BCOL_CYAN, grove_fodder_aimed)));
    array_push(_e, ev(600, wave_cross(EnemyKind.Gem, 5, 1, 400, -52, 6.2, 6,
                                      BCOL_CYAN, grove_fodder_aimed)));
    array_push(_e, ev_gate(650));

    // --- the thing on the path -----------------------------------------
    array_push(_e, ev(750, wave_boss(grove_midboss_spawn)));
    array_push(_e, ev_gate(770));

    // --- and the wood goes bad -----------------------------------------
    array_push(_e, ev(772, wave_bg_omen()));

    array_push(_e, ev(900, wave_line(EnemyKind.Grimoire, 6,
                                     FIELD_W + 100, 130, 0, 0,
                                     300, 210, 260, 44,
                                     230, 18, BCOL_ROSE,
                                     grove_fodder_ring)));
    array_push(_e, ev(960, wave_cross(EnemyKind.Wisp, 8, -1, 500, 42, 6.0, 4,
                                      BCOL_MAGENTA, grove_fodder_pellet, 10)));
    array_push(_e, ev_gate(1010));

    array_push(_e, ev(1130, wave_cross(EnemyKind.Gem, 6, 1, 250, 64, 6.6, 8,
                                       BCOL_ROSE, grove_fodder_aimed, 11)));
    array_push(_e, ev(1150, wave_line(EnemyKind.Sentry, 3,
                                      -140, 210, 0, 0,
                                      520, 300, 440, 0,
                                      250, 46, BCOL_VIOLET,
                                      grove_fodder_sentry)));
    array_push(_e, ev_gate(1200));

    array_push(_e, ev(1300, wave_sweep_field()));
    array_push(_e, ev(1360, wave_boss(briar_spawn)));

    return _e;
}

// ---------------------------------------------------------------------------
// What the fodder does
//
// Stage one's rules at stage one's rates: fodder fires slowly and always
// telegraphs, because a wave that can kill an attentive player is a wave that
// has taken the boss's job. What is different is the hues, and only because
// the wood is cold where the forge was hot.
// ---------------------------------------------------------------------------

function grove_fodder_pellet(_e, _g, _t) {
    if ((_t mod 48) != 0) return;
    fire(_e.x, _e.y, 6.0, aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
         BSHAPE_PELLET, BCOL_JADE, 14);
}

function grove_fodder_fan(_e, _g, _t) {
    if ((_t mod 64) != 20) return;
    fire_fan(_e.x, _e.y, 5, 5.4,
             aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 44,
             BSHAPE_RICE, BCOL_VIOLET, 16);
}

function grove_fodder_aimed(_e, _g, _t) {
    if ((_t mod 54) != 30) return;
    fire_stack(_e.x, _e.y, 3, 5.2, 1.5,
               aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
               BSHAPE_CRYSTAL, BCOL_CYAN, 14);
}

function grove_fodder_ring(_e, _g, _t) {
    if ((_t mod 76) != 40) return;
    fire_ring(_e.x, _e.y, 10, 4.4, _e.t * 7, BSHAPE_ORB, BCOL_ROSE, 18);
}

function grove_fodder_sentry(_e, _g, _t) {
    if ((_t mod 86) == 30) {
        fire_ring(_e.x, _e.y, 14, 4.6, _e.t * 4, BSHAPE_ORB, BCOL_VIOLET, 20);
    }
    if ((_t mod 86) == 66) {
        fire_stack(_e.x, _e.y, 4, 6.2, 1.4,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_DART, BCOL_MAGENTA, 16);
    }
}

// ---------------------------------------------------------------------------
// The midboss
// ---------------------------------------------------------------------------

function grove_midboss_def() {
    return {
        name: "THE HUSK",
        title: "something she left standing",
        // **Stage one's stone sentry, borrowed.** A placeholder that is
        // obviously a placeholder beats a new one nobody drew -- the same
        // decision the drafting table makes about Ziggy's sprite.
        sprite: spr_foe_sentry,
        eye: spr_eye_ziggy,
        col: BCOL_JADE,
        radius: 46,
        spell_bg: SPELLBG_GROVE,
        final: false,
    };
}

function grove_midboss_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_JADE, bg: -1,
          hp_end: 0.44, time: 24 * FPS, attack: husk_rattle },
        { kind: AttackKind.Spell, name: "Rootbound",
          col: BCOL_SPRING, bg: BCOL_SPRING,
          hp_end: 0.0, time: 32 * FPS, attack: husk_rootbound },
    ];
}

function grove_midboss_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 140, 250, grove_midboss_phases(),
                        grove_midboss_def());
    if (_b != undefined) {
        _b.boss.home_y = BOSS_HOME_Y - 30;
        _b.boss.declare_t = 40;      // a midboss gets no name splash
    }
    return _b;
}

/// @desc A slow ring with an aimed volley through it.
function husk_rattle(_e, _g, _t) {
    if ((_t mod 9) == 0) {
        fire_ring(_e.x, _e.y, 5, 5.0, _t * 3.1, BSHAPE_ORB, BCOL_JADE, 12);
    }
    if ((_t mod 90) == 46) {
        fire_fan_stack(_e.x, _e.y, 7, 3, 5.2, 1.1,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 34,
                       BSHAPE_RICE, BCOL_SPRING, 18);
    }
}

/// @desc Beams standing up out of the ground, and a drizzle between them.
function husk_rootbound(_e, _g, _t) {
    var _cycle = _t mod 144;
    if (_cycle == 0) {
        var _base = aim_at(_e.x, _e.y, _g.player.x, _g.player.y);
        for (var _i = 0; _i < 3; _i++) {
            var _l = laser_beam(_e.x, _e.y, _base + _i * 120, 2300, 28,
                                BCOL_SPRING, 66, 60, 22);
            if (_l != undefined) {
                _l.src = _e;
                _l.turn = 0.34;
            }
        }
    }
    if ((_t mod 26) == 0) {
        fire_ring(_e.x, _e.y, 9, 3.8, _t * 4.3, BSHAPE_PELLET, BCOL_JADE, 14);
    }
}

// ---------------------------------------------------------------------------
// Briar
//
// **A necromancer druid, and none of that is in her patterns yet.** She is
// listed, named, given a colour and a background and five attacks that are
// deliberately the plainest things this engine can produce -- see the note at
// the top of this file. Replacing them is replacing this table.
// ---------------------------------------------------------------------------

function briar_def() {
    return {
        name: "BRIAR",
        title: "the fox who keeps the grove's dead",
        sprite: spr_boss_ziggy,       // placeholder; see `grove_midboss_def`
        eye: spr_eye_ziggy,
        col: BCOL_VIOLET,
        radius: 62,
        spell_bg: SPELLBG_GROVE,
        final: true,
    };
}

function briar_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_VIOLET, bg: -1,
          hp_end: 0.86, time: 24 * FPS, attack: briar_basic_fans },

        { kind: AttackKind.Spell, name: "Witchlight Vigil",
          col: BCOL_CYAN, bg: BCOL_CYAN,
          hp_end: 0.66, time: 38 * FPS, attack: briar_witchlight,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_VIOLET, bg: -1,
          hp_end: 0.52, time: 24 * FPS, attack: briar_basic_spiral },

        { kind: AttackKind.Spell, name: "Carrion Bloom",
          col: BCOL_ROSE, bg: BCOL_ROSE,
          hp_end: 0.28, time: 40 * FPS, attack: briar_carrion_bloom },

        { kind: AttackKind.Spell, name: "The Long Antler",
          col: BCOL_MAGENTA, bg: BCOL_MAGENTA,
          hp_end: 0.0, time: 46 * FPS, attack: briar_long_antler,
          move: BossMove.Track },
    ];
}

function briar_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, 1500, briar_phases(),
                      briar_def());
}

/// @desc Wide aimed fans with a lazy ring under them. Her handwriting, for as
///       long as she has none of her own.
function briar_basic_fans(_e, _g, _t) {
    if ((_t mod 74) == 30) {
        fire_fan_stack(_e.x, _e.y, 9, 3, 5.0, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                       BSHAPE_RICE, BCOL_VIOLET, 20);
    }
    // **Cyan, not rose.** Her wood is red for the whole of the second half
    // of the stage and a rose bullet over a blood moon is a bullet nobody can
    // find -- which is a fairness problem rather than a taste one. The one
    // rule the palette of this game is built on is that a bullet reads
    // against whatever is behind it.
    if ((_t mod 18) == 0) {
        fire_ring(_e.x, _e.y, 7, 3.6, _t * 5.5, BSHAPE_ORB, BCOL_CYAN, 14);
    }
}

/// @desc A two-armed spiral. Slow turn against a fast bullet, because the
///       shape of a spiral is the ratio of the two and this field is wide.
function briar_basic_spiral(_e, _g, _t) {
    if ((_t mod 4) != 0) return;
    fire_ring(_e.x, _e.y, 2, 5.6, _t * 3.3, BSHAPE_PELLET, BCOL_VIOLET, 12);
}

/// @desc Lanterns hung round her, each sweeping a beam. The midboss's idea
///       again, from a station she does not leave.
function briar_witchlight(_e, _g, _t) {
    var _cycle = _t mod 156;
    if (_cycle == 0) {
        var _base = _t * 0.7;
        for (var _i = 0; _i < 5; _i++) {
            var _l = laser_beam(_e.x, _e.y, _base + _i * 72, 2400, 26,
                                BCOL_CYAN, 70, 66, 24);
            if (_l != undefined) {
                _l.src = _e;
                _l.turn = 0.30 * ((_i mod 2) ? 1 : -1);
            }
        }
    }
    if ((_t mod 20) == 10) {
        fire_ring(_e.x, _e.y, 12, 3.4, -_t * 2.2, BSHAPE_MOTE, BCOL_JADE, 16);
    }
}

/// @desc Rosettes that open where they land: a shell that breaks into six.
function briar_carrion_bloom(_e, _g, _t) {
    if ((_t mod 40) != 0) return;
    var _base = _t * 6.5;
    for (var _i = 0; _i < 5; _i++) {
        var _b = fire(_e.x, _e.y, 4.4, _base + _i * 72,
                      BSHAPE_ORB, BCOL_ROSE, 20);
        if (_b == undefined) break;
        bullet_split_at(_b, 46, 6, 3.4);
    }
}

/// @desc Long curved lashes that come to her rather than her coming to them.
///       The one attack of hers that tracks, so a cornered player is not
///       simply out of reach of the whole fight.
function briar_long_antler(_e, _g, _t) {
    if ((_t mod 92) == 0) {
        for (var _i = 0; _i < 2; _i++) {
            laser_curve(_e.x, _e.y,
                        aim_at(_e.x, _e.y, _g.player.x, _g.player.y)
                        + (_i ? 26 : -26),
                        5.6, (_i ? 1.5 : -1.5), 22, BCOL_MAGENTA, 150);
        }
    }
    if ((_t mod 11) == 0) {
        fire_ring(_e.x, _e.y, 3, 5.0, _t * 4.1, BSHAPE_CRYSTAL,
                  BCOL_VIOLET, 14);
    }
    if ((_t mod 120) == 62) {
        fire_fan_stack(_e.x, _e.y, 11, 2, 5.4, 1.2,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 52,
                       BSHAPE_RICE, BCOL_CYAN, 20);
    }
}
