/// @desc Stage two: the Hollow Grove -- waves, the Husk (midboss), and Velka.
///
/// The work in this stage is the background (`bg_grove`: a night wood whose
/// moon turns to blood halfway through). The Husk's attacks and Velka's first
/// five are placeholders. Her last spell, `Demon Sealing Hex`, is the one
/// designed attack; it was written on the drafting table and moved here.
///
/// The fodder is stage one's greyscale sprites, tinted at draw time.

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

function stage_grove_def() {
    return {
        id: "hollow_grove",
        name: "THE HOLLOW GROVE",
        subtitle: "a wood that keeps its dead",
        // Unlocked from the start for now, while Velka's fight is a
        // placeholder.
        needs: 0,
        make_bg: bg_grove,
        build: stage_grove_script,


        // `turned`: Velka is fought after the wood turns to blood, so she is
        // practised in the blood wood (`practice_begin`).
        bosses: [
            { name: "THE HUSK", spawn: grove_midboss_spawn,
              phases: grove_midboss_phases },
            { name: "VELKA", spawn: velka_spawn, phases: velka_phases,
              turned: true },
        ],
    };
}

/// @desc The running order. The blood-moon turn is the `wave_bg_omen` event
///       just after the midboss's gate; stage time is held while a boss is up,
///       so it fires as soon as the midboss is beaten.
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
    array_push(_e, ev(1360, wave_boss(velka_spawn)));

    return _e;
}

// ---------------------------------------------------------------------------
// What the fodder fires
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
// The midboss (placeholder attacks)
// ---------------------------------------------------------------------------

function grove_midboss_def() {
    return {
        name: "THE HUSK",
        title: "something she left standing",
        // Placeholder art: stage one's stone sentry.
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
// Velka: five placeholder attacks, then `Demon Sealing Hex`.
// ---------------------------------------------------------------------------

function velka_def() {
    return {
        name: "VELKA",
        title: "the fox who keeps the grove's dead",
        sprite: spr_boss_ziggy,       // placeholder art
        eye: spr_eye_ziggy,
        col: BCOL_VIOLET,
        radius: 62,
        spell_bg: SPELLBG_GROVE,
        final: true,
    };
}

function velka_phases() {
    return [
        // Thresholds: the first five attacks keep their shares of her
        // original 1500 HP; the Hex adds `DRAFT_SLOT_HP` (see `velka_spawn`).
        { kind: AttackKind.NonSpell, name: "", col: BCOL_VIOLET, bg: -1,
          hp_end: 0.887, time: 24 * FPS, attack: velka_basic_fans },

        { kind: AttackKind.Spell, name: "Witchlight Vigil",
          col: BCOL_CYAN, bg: BCOL_CYAN,
          hp_end: 0.726, time: 38 * FPS, attack: velka_witchlight,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_VIOLET, bg: -1,
          hp_end: 0.613, time: 24 * FPS, attack: velka_basic_spiral },

        { kind: AttackKind.Spell, name: "Carrion Bloom",
          col: BCOL_ROSE, bg: BCOL_ROSE,
          hp_end: 0.419, time: 40 * FPS, attack: velka_carrion_bloom },

        { kind: AttackKind.Spell, name: "The Long Antler",
          col: BCOL_MAGENTA, bg: BCOL_MAGENTA,
          hp_end: 0.194, time: 46 * FPS, attack: velka_long_antler,
          move: BossMove.Track },

        // `Track`: the player spends much of it pinned inside a ward and
        // can't go to her, so she comes to them. The clock is three full
        // `HEX_CYCLE`s plus a little, so the last pass isn't cut off before
        // its collapse.
        { kind: AttackKind.Spell, name: "Demon Sealing Hex",
          col: BCOL_CRIMSON, bg: BCOL_CRIMSON,
          hp_end: 0.0, time: 53 * FPS, attack: velka_demon_sealing_hex,
          move: BossMove.Track },
    ];
}

/// @desc 1860 = 1500 for the first five attacks + 360 for the Hex.
function velka_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, 1860, velka_phases(),
                      velka_def());
}

/// @desc Wide aimed fans with a lazy ring under them.
function velka_basic_fans(_e, _g, _t) {
    if ((_t mod 74) == 30) {
        fire_fan_stack(_e.x, _e.y, 9, 3, 5.0, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                       BSHAPE_RICE, BCOL_VIOLET, 20);
    }
    // Cyan rather than a red hue: it has to stay visible over the blood moon.
    if ((_t mod 18) == 0) {
        fire_ring(_e.x, _e.y, 7, 3.6, _t * 5.5, BSHAPE_ORB, BCOL_CYAN, 14);
    }
}

/// @desc A two-armed spiral.
function velka_basic_spiral(_e, _g, _t) {
    if ((_t mod 4) != 0) return;
    fire_ring(_e.x, _e.y, 2, 5.6, _t * 3.3, BSHAPE_PELLET, BCOL_VIOLET, 12);
}

/// @desc Five beams round her, sweeping in alternate directions, from a
///       station she doesn't leave.
function velka_witchlight(_e, _g, _t) {
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

/// @desc Shells that each break into six.
function velka_carrion_bloom(_e, _g, _t) {
    if ((_t mod 40) != 0) return;
    var _base = _t * 6.5;
    for (var _i = 0; _i < 5; _i++) {
        var _b = fire(_e.x, _e.y, 4.4, _base + _i * 72,
                      BSHAPE_ORB, BCOL_ROSE, 20);
        if (_b == undefined) break;
        bullet_split_at(_b, 46, 6, 3.4);
    }
}

/// @desc Pairs of long curved lasers aimed either side of the player, a
///       crystal spiral, and an aimed fan. She tracks the player's column.
function velka_long_antler(_e, _g, _t) {
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

// ---------------------------------------------------------------------------
// Demon Sealing Hex
//
// The one finished attack in the game, and the reference for what a finished
// attack should be. A ward is drawn round the player and broken, twice:
//
//   1. A red seal (a pentagram inside two rings, no gaps in the outer
//      boundary) is inscribed; the player, sealed inside, is fired at with
//      aimed volleys; the boss goes quiet; the seal scatters outward.
//   2. A blue seal with gaps a focused player can thread is inscribed and
//      fired into; the boss goes quiet; the seal collapses to a point and
//      detonates. The player is meant to get out before it collapses.
//
// How it works:
//   - Rigid rotation: every bead gets a heading tangent to its circle, a speed
//     proportional to its radius (`r * spin` in radians) and the same turn
//     rate, so the whole seal revolves as one object. The outer ring turns
//     the opposite way to the star and inner ring.
//   - Nothing is inspected after it is fired (there is no way to find "the
//     bullets of this seal"), so every bead is given its whole future through
//     the event queue when it is placed: stop turning, then move, then scatter
//     or collapse, then burst or expire.
//   - The collapse is solved so every bead reaches the centre on the same
//     frame whatever its radius (see `hex_rune`); `test_hex_seal` checks it.
//   - Irregularity (scatter directions, debris) comes from a hash of the
//     bead's index, not `random`, so it is the same on every attempt.
// ---------------------------------------------------------------------------

/// The ward's radii: the star's points stand on the inner ring.
#macro HEX_R_IN  296
#macro HEX_R_OUT 356

/// The bead shape. `BSHAPE_RUNE` was too large (the seal read as individual
/// stones) and `BSHAPE_PELLET` too small (it stopped reading as an object).
#macro HEX_BEAD BSHAPE_ORB

/// Spacing between beads, in px. After subtracting the bead's and the
/// player's hitboxes, 20 leaves no corridor (a wall) and 52 leaves about 30px.
/// The red seal's rings are sealed; its star arms are spaced wider so they
/// divide the inside without walling it into small cells.
#macro HEX_GAP_RED_RING 20
#macro HEX_GAP_RED_ARM  44
#macro HEX_GAP_BLUE     52

/// The beads' delay-mark time. Longer than usual because the warning here is
/// "a wall is about to appear around you", and the player needs time to stop
/// and pick a side.
#macro HEX_SEAL_DELAY 34

/// Degrees a frame the seal turns.
#macro HEX_SPIN 0.11

/// The movements, in frames: inscribe red, red volleys (+hold), scatter,
/// inscribe blue, blue volleys (+hold), collapse, detonation. `HEX_CYCLE` is
/// their sum and the attack runs `_t mod HEX_CYCLE`. The inscription is slow
/// enough for the player to follow which arm is coming toward them.
#macro HEX_DRAW     90
#macro HEX_RED_FAN  220
#macro HEX_SCATTER  164
#macro HEX_BLUE_FAN 260
#macro HEX_IMPLODE  108
#macro HEX_BURST    110

/// Frames at the end of each volley phase where the boss stops firing before
/// the seal breaks, so the player is watching the ward when it moves (and the
/// last volley has arrived). The blue hold is longer because escaping through
/// the gaps takes longer than watching a scatter.
#macro HEX_HOLD_RED  80
#macro HEX_HOLD_BLUE 120
#macro HEX_CYCLE (HEX_DRAW + HEX_RED_FAN + HEX_SCATTER + HEX_DRAW + HEX_BLUE_FAN + HEX_IMPLODE + HEX_BURST)

/// Where each movement starts within a cycle.
#macro HEX_RED_FAN0   HEX_DRAW
#macro HEX_SCATTER_AT (HEX_RED_FAN0 + HEX_RED_FAN)
#macro HEX_BLUE_DRAW0 (HEX_SCATTER_AT + HEX_SCATTER)
#macro HEX_BLUE_FAN0  (HEX_BLUE_DRAW0 + HEX_DRAW)
#macro HEX_IMPLODE_AT (HEX_BLUE_FAN0 + HEX_BLUE_FAN)
#macro HEX_BURST_AT   (HEX_IMPLODE_AT + HEX_IMPLODE)

/// The scatter: starts almost still (so the ward visibly loosens before
/// anything moves), accelerates, and is capped slow enough to outrun. Scattered
/// beads never expire; they leave the field and are culled.
#macro HEX_SCATTER_SPD 0.02
#macro HEX_SCATTER_ACC 0.028
#macro HEX_SCATTER_CAP 2.6

/// How many times faster a collapsing bead's last frame is than its first.
/// Higher means a gentler start and a steeper finish (every bead must cover
/// its distance in exactly `HEX_IMPLODE` frames). Must be less than
/// `HEX_IMPLODE`.
#macro HEX_IMPLODE_RAMP 26

/// The volleys fired into the seal: white (bone), so they stand out against
/// both the crimson and the azure ward.
#macro HEX_COL_FAN BCOL_BONE

/// How far a detonating bead's direction may stray from its even share of the
/// circle, as a fraction of the share (hashed, so fixed per attempt).
#macro HEX_BURST_JITTER 1.6

/// One bead in this many becomes detonation debris; the rest go out on
/// arrival.
#macro HEX_BURST_EVERY 4

/// How far from the field's edge the seal's centre is clamped, so a player in
/// a corner doesn't put most of the seal off the field (where it would be
/// hidden by the frame but still lethal).
#macro HEX_CLAMP 210

/// @desc **Demon Sealing Hex.** The clock for the four movements. The seal's
///       centre is taken from the player's position at the start of each
///       inscription and held (in a `static`), because reading it every frame
///       would smear the figure as the player moves.
function velka_demon_sealing_hex(_e, _g, _t) {
    static seal = { x: FIELD_CX, y: FIELD_CY };

    var _c = _t mod HEX_CYCLE;

    if (_c == 0 || _c == HEX_BLUE_DRAW0) {
        seal.x = clamp(_g.player.x, FIELD_X0 + HEX_CLAMP, FIELD_X1 - HEX_CLAMP);
        seal.y = clamp(_g.player.y, FIELD_Y0 + HEX_CLAMP, FIELD_Y1 - HEX_CLAMP);
        // A ring thrown out to where the seal is about to close.
        fx_ring(seal.x, seal.y, 40, HEX_R_OUT, 26,
                global.bullet_colour[(_c == 0) ? BCOL_CRIMSON : BCOL_AZURE],
                0.7);
    }

    if (_c < HEX_DRAW) {
        hex_seal_step(seal.x, seal.y, _c, false);

    } else if (_c < HEX_SCATTER_AT) {
        // Sealed in and shot at with aimed volleys.
        var _rf = _c - HEX_RED_FAN0;
        if (_rf < HEX_RED_FAN - HEX_HOLD_RED && (_rf mod 38) == 8) {
            // Three rows at three speeds, each offset half a step, so the
            // volley arrives as three arcs with gaps on different lines.
            fire_fan_stack(_e.x, _e.y, 5, 3, 4.4, 1.0,
                           aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                           BSHAPE_RICE, HEX_COL_FAN, 20, 4.6);
        }

    } else if (_c < HEX_BLUE_DRAW0) {
        // The scatter: the beads were given their instructions when placed.

    } else if (_c < HEX_BLUE_FAN0) {
        hex_seal_step(seal.x, seal.y, _c - HEX_BLUE_DRAW0, true);

    } else if (_c < HEX_IMPLODE_AT) {
        var _bf = _c - HEX_BLUE_FAN0;
        if (_bf < HEX_BLUE_FAN - HEX_HOLD_BLUE && (_bf mod 40) == 8) {
            // Wider and one row fewer than the red half's: this half asks the
            // player to move.
            fire_fan_stack(_e.x, _e.y, 7, 2, 4.6, 1.2,
                           aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 66,
                           BSHAPE_RICE, HEX_COL_FAN, 20, 5.4);
        }
    }

    // Cues for the two breaks and the detonation (effects only).
    if (_c == HEX_SCATTER_AT) {
        fx_shake(4);
        fx_ring(seal.x, seal.y, HEX_R_OUT - 40, HEX_R_OUT + 90, 30,
                global.bullet_colour[BCOL_CRIMSON], 0.7);
    }
    if (_c == HEX_IMPLODE_AT) {
        fx_shake(6);
        fx_ring(seal.x, seal.y, HEX_R_OUT, 30, HEX_IMPLODE,
                global.bullet_colour[BCOL_AZURE], 0.8);
    }
    if (_c == HEX_BURST_AT) {
        // The detonation's size is carried by harmless effects; the danger is
        // only the debris bullets (`hex_rune`).
        fx_flash_at(seal.x, seal.y, global.bullet_colour[BCOL_CYAN], 0.95);
        fx_ring(seal.x, seal.y, 10, 260, 18, c_white, 0.85);
        fx_ring(seal.x, seal.y, 20, 520, 40,
                global.bullet_colour[BCOL_CYAN], 1.0);
        fx_ring(seal.x, seal.y, 60, 900, 64,
                global.bullet_colour[BCOL_AZURE], 0.5);
        fx_burst(seal.x, seal.y, 54, 4, 17,
                 global.bullet_colour[BCOL_CYAN], 46, 22);
        fx_shake(16);
    }
}

/// @desc Place this frame's share of one seal's beads. The seven traces (five
///       star arms, two rings) have very different lengths but all finish on
///       frame `HEX_DRAW - 1`: each frame, a trace places the beads with index
///       from `n * f / HEX_DRAW` to `n * (f + 1) / HEX_DRAW`. `_idx` runs
///       across the whole seal, so the detonation's every-Nth pick is spread
///       over all of it.
function hex_seal_step(_cx, _cy, _f, _blue) {
    var _arm = 2 * HEX_R_IN * dsin(72);

    var _gap_arm  = _blue ? HEX_GAP_BLUE : HEX_GAP_RED_ARM;
    var _gap_ring = _blue ? HEX_GAP_BLUE : HEX_GAP_RED_RING;

    var _arm_n = max(2, round(_arm / _gap_arm));
    var _out_n = max(8, round(2 * pi * HEX_R_OUT / _gap_ring));
    var _in_n  = max(8, round(2 * pi * HEX_R_IN  / _gap_ring));
    var _n     = _arm_n * 5 + _out_n + _in_n;

    var _col = _blue ? BCOL_AZURE : BCOL_CRIMSON;

    // Live frames a bead placed now has before the seal breaks (delay-mark
    // frames don't tick the queue, so they're subtracted).
    var _wait = HEX_DRAW + (_blue ? HEX_BLUE_FAN : HEX_RED_FAN)
                - _f - HEX_SEAL_DELAY;

    // ---- the star ---------------------------------------------------------
    //
    // Five arms, each from its point to the point two round. Each stops short
    // of its far end, so no vertex is drawn twice.
    var _base = 0;
    for (var _j = 0; _j < 5; _j++) {
        var _a0 = 90 + _j * 72;
        var _a1 = 90 + ((_j + 2) mod 5) * 72;
        var _x0 = _cx + lengthdir_x(HEX_R_IN, _a0);
        var _y0 = _cy + lengthdir_y(HEX_R_IN, _a0);
        var _x1 = _cx + lengthdir_x(HEX_R_IN, _a1);
        var _y1 = _cy + lengthdir_y(HEX_R_IN, _a1);

        var _p0 = (_arm_n * _f) div HEX_DRAW;
        var _p1 = (_arm_n * (_f + 1)) div HEX_DRAW;
        for (var _k = _p0; _k < _p1; _k++) {
            var _s = _k / _arm_n;
            hex_rune(_cx, _cy, lerp(_x0, _x1, _s), lerp(_y0, _y1, _s),
                     _col, HEX_SPIN, _wait, _blue, _base + _k, _n, _f);
        }
        _base += _arm_n;
    }

    // ---- the two rings ----------------------------------------------------
    //
    // The outer ring is written clockwise and turns clockwise; the inner one
    // anticlockwise.
    var _o0 = (_out_n * _f) div HEX_DRAW;
    var _o1 = (_out_n * (_f + 1)) div HEX_DRAW;
    for (var _k = _o0; _k < _o1; _k++) {
        var _ao = 90 - _k * (360 / _out_n);
        hex_rune(_cx, _cy,
                 _cx + lengthdir_x(HEX_R_OUT, _ao),
                 _cy + lengthdir_y(HEX_R_OUT, _ao),
                 _col, -HEX_SPIN, _wait, _blue, _base + _k, _n, _f);
    }
    _base += _out_n;

    // The inner ring is offset half a step: both rings start at 90 degrees,
    // and if aligned there their beads would line up into a visible radial
    // gap. The offset also avoids doubling a bead on the star's top point.
    var _i0 = (_in_n * _f) div HEX_DRAW;
    var _i1 = (_in_n * (_f + 1)) div HEX_DRAW;
    for (var _k = _i0; _k < _i1; _k++) {
        var _ai = 90 + (_k + 0.5) * (360 / _in_n);
        hex_rune(_cx, _cy,
                 _cx + lengthdir_x(HEX_R_IN, _ai),
                 _cy + lengthdir_y(HEX_R_IN, _ai),
                 _col, HEX_SPIN, _wait, _blue, _base + _k, _n, _f);
    }
}

/// @desc Scatter direction for bead `_i`: a hash, so irregular but the same
///       on every attempt. (A plain stride would send neighbouring beads off
///       in a visible fan.)
function hex_spray_dir(_i) {
    return hex_hash(_i, 78.233) * 360;
}

/// @desc A number in `[0, 1)` from an index and a seed (sine hash; fixed for
///       the life of the game).
function hex_hash(_i, _seed) {
    // `frac` keeps the sign in GML, so fold negatives into [0, 1).
    var _v = frac(sin(_i * 12.9898 + _seed) * 43758.5453);
    return (_v < 0) ? _v + 1 : _v;
}

/// @desc The detonation's debris kinds: a shape and its speed, heavier shapes
///       slower, so the cloud sorts itself by distance as it expands. All
///       drawn cyan. `_h` is a hash in `[0, 1)`.
function hex_debris(_h) {
    static kinds = [
        { shape: BSHAPE_BALL,    spd: 2.8 },   // r 15.0
        { shape: BSHAPE_STAR6,   spd: 3.3 },   // r 14.0, and it turns
        { shape: BSHAPE_RUNE,    spd: 3.9 },   // r 10.5 -- a piece of the ward
        { shape: BSHAPE_CRYSTAL, spd: 4.5 },   // r  9.0
        { shape: BSHAPE_ORB,     spd: 5.2 },   // r  7.0 -- the ward's own bead
        { shape: BSHAPE_MOTE,    spd: 6.0 },   // r  5.6
        { shape: BSHAPE_PELLET,  spd: 6.9 },   // r  4.2
    ];
    var _n = array_length(kinds);
    return kinds[clamp(floor(_h * _n), 0, _n - 1)];
}

/// @desc One bead of a seal: placed, set turning about the centre, and given
///       every instruction for when the seal breaks `_wait` frames later.
function hex_rune(_cx, _cy, _x, _y, _col, _spin, _wait, _blue, _idx, _n, _f) {
    var _r = point_distance(_cx, _cy, _x, _y);

    // Lay the bead out in the ward's turning frame: a bead only starts
    // turning when it goes live, so one placed `_f` frames into the
    // inscription is rotated ahead by the turn it has missed. Without this
    // the ring doesn't close (one gap at the seam several times wider than
    // the rest). The ring is only exactly round once the last bead is live,
    // which is what `test_hex_seal` waits for.
    var _phi = point_direction(_cx, _cy, _x, _y) + _spin * _f;
    _x = _cx + lengthdir_x(_r, _phi);
    _y = _cy + lengthdir_y(_r, _phi);

    // A true circle: heading tangent to it, speed = the arc covered per frame.
    var _u = fire(_x, _y, _r * degtorad(abs(_spin)),
                  _phi + ((_spin >= 0) ? 90 : -90),
                  HEX_BEAD, _col, HEX_SEAL_DELAY);
    if (_u == undefined) return;
    _u.turn = _spin;

    // The bead's bearing from the centre when the seal breaks: it will have
    // turned `_spin` degrees a frame for `_wait` frames by then.
    var _turned = _phi + _spin * _wait;

    // Stop orbiting when the seal breaks.
    bullet_turn_at(_u, _wait, 0);

    if (!_blue) {
        // Scatter in a hashed direction (not outward along the radius), so
        // debris also crosses the space the seal enclosed. Scattered beads
        // never expire; they are culled off the field like everything else.
        bullet_move_at(_u, _wait, HEX_SCATTER_SPD, hex_spray_dir(_idx));
        bullet_accel_at(_u, _wait, HEX_SCATTER_ACC, HEX_SCATTER_CAP);
        return;
    }

    // ---- the collapse -----------------------------------------------------
    //
    // Speed and acceleration are both proportional to the distance, scaled so
    // the distance covered in `HEX_IMPLODE` frames is exactly the distance to
    // the centre; every bead arrives on the same frame and the seal shrinks
    // keeping its shape. With T = `HEX_IMPLODE`, R = `HEX_IMPLODE_RAMP`, and
    // c0, ca the start speed and acceleration as fractions of the distance:
    // the step applies acceleration before moving, so the distance covered is
    // `T*c0 + ca*T*(T+1)/2`, which must equal 1; and the last frame's speed is
    // R times the first's, which fixes `ca/c0 = (R-1)/(T-R)`.
    var _ratio = (HEX_IMPLODE_RAMP - 1) / (HEX_IMPLODE - HEX_IMPLODE_RAMP);
    var _c0    = 1 / (HEX_IMPLODE * (1 + _ratio * (HEX_IMPLODE + 1) / 2));
    var _into  = _turned + 180;

    bullet_move_at(_u, _wait, _r * _c0, _into);
    bullet_accel_at(_u, _wait, _r * _c0 * _ratio, BQ_KEEP);

    var _land = _wait + HEX_IMPLODE;

    if ((_idx mod HEX_BURST_EVERY) != 0) {
        // Stop dead on the centre and go out (a bead that carried on through
        // would look like part of the detonation).
        bullet_move_at(_u, _land, 0, BQ_KEEP);
        bullet_expire_at(_u, _land, 14);
        return;
    }

    // ---- the detonation ---------------------------------------------------
    //
    // Each detonating bead splits into a pair at an angle chosen here: the
    // detonating beads are dealt evenly round the circle (so the burst has no
    // hole) and each is knocked off its share by up to `HEX_BURST_JITTER`
    // (so it has no regular spokes). The split offset is relative to the
    // heading the bead arrives with (`_into`). Three independent hashes pick
    // the direction, the debris kind and a +/-16% speed variation.
    var _ex   = (_n + HEX_BURST_EVERY - 1) div HEX_BURST_EVERY;
    var _q    = _idx div HEX_BURST_EVERY;
    var _step = 180 / max(1, _ex);
    var _want = _q * _step
              + (hex_hash(_q, 4.117) - 0.5) * _step * HEX_BURST_JITTER;

    var _d = hex_debris(hex_hash(_q, 27.611));
    bullet_graphic_at(_u, _land, _d.shape, BCOL_CYAN);
    bullet_split_at(_u, _land, 2,
                    _d.spd * (0.84 + 0.32 * hex_hash(_q, 61.409)),
                    _want - _into);
}
