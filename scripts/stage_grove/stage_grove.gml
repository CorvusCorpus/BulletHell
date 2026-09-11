/// @desc Stage two: the Hollow Grove, and Velka at the end of it.
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
/// **Nothing here is tuned and it does not pretend to be -- with one
/// exception.** Five of Velka's six attacks are plain shapes at grove hues;
/// they are not her handwriting, because she does not have one yet. What they
/// are for is putting the right number of bullets on the screen at the right
/// sort of speeds so the background can be looked at underneath them, and so
/// the turn has something to happen in the middle of. When she is written for
/// real, those rows are what get replaced and nothing else on this screen has
/// to change.
///
/// **The sixth is `Demon Sealing Hex`, and it is hers.** It was written on the
/// drafting table before anybody had said whose it was, and it moved here as
/// the drafting table says an attack should -- the function and a row, with a
/// real `hp_end`. It is the one designed attack she has, so it is the last
/// thing she does.
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
        // note is about. It goes back to `1` on the day Velka has a fight
        // worth reaching, and it is one number.
        needs: 0,
        make_bg: bg_grove,
        build: stage_grove_script,

        // Provisional, exactly as stage one's is: eight attacks -- the
        // midboss's two and Velka's six -- and five wave groups, and nothing
        // counts the wave groups yet. See `rank_functions`.
        encounters: 13,

        bosses: [
            { name: "THE HUSK", spawn: grove_midboss_spawn,
              phases: grove_midboss_phases },
            { name: "VELKA", spawn: velka_spawn, phases: velka_phases },
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
    array_push(_e, ev(1360, wave_boss(velka_spawn)));

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
// Velka
//
// **A necromancer druid, and very little of that is in her patterns yet.** She
// is listed, named, given a colour and a background, five attacks that are
// deliberately the plainest things this engine can produce, and one that is
// not -- `Demon Sealing Hex`, at the end of the table and of this file. See the
// note at the top. Replacing the five is replacing their rows.
// ---------------------------------------------------------------------------

function velka_def() {
    return {
        name: "VELKA",
        title: "the fox who keeps the grove's dead",
        sprite: spr_boss_ziggy,       // placeholder; see `grove_midboss_def`
        eye: spr_eye_ziggy,
        col: BCOL_VIOLET,
        radius: 62,
        spell_bg: SPELLBG_GROVE,
        final: true,
    };
}

function velka_phases() {
    return [
        // **Every attack keeps the health it had**, and the Hex brings its
        // own: the thresholds are the old spans laid end to end over a bar
        // that grew by one attack's worth, rather than the old thresholds
        // squeezed up to make room. Squeezing would have quietly shortened
        // five attacks to fit a sixth -- the reason `draft_phases` prices a
        // slot rather than dividing the bar.
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

        // **Her last word, and the only one of the six that was designed.**
        // `DRAFT_SLOT_HP` of the bar, which is what it was played against on
        // the drafting table. `Track`, because the player spends most of it
        // walled into a ward and cannot go to her -- see `BossMove`. The clock
        // is three passes of `HEX_CYCLE` and a little, and it is the only
        // clock in the table derived from anything: the attack is `_t mod` a
        // cycle, and a clock that does not divide by one cuts the last pass
        // off before the collapse, which is the half worth reaching.
        { kind: AttackKind.Spell, name: "Demon Sealing Hex",
          col: BCOL_CRIMSON, bg: BCOL_CRIMSON,
          hp_end: 0.0, time: 53 * FPS, attack: velka_demon_sealing_hex,
          move: BossMove.Track },
    ];
}

/// @desc 1860 is the 1500 she had and the Hex's 360.
function velka_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, 1860, velka_phases(),
                      velka_def());
}

/// @desc Wide aimed fans with a lazy ring under them. Her handwriting, for as
///       long as she has none of her own.
function velka_basic_fans(_e, _g, _t) {
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
function velka_basic_spiral(_e, _g, _t) {
    if ((_t mod 4) != 0) return;
    fire_ring(_e.x, _e.y, 2, 5.6, _t * 3.3, BSHAPE_PELLET, BCOL_VIOLET, 12);
}

/// @desc Lanterns hung round her, each sweeping a beam. The midboss's idea
///       again, from a station she does not leave.
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

/// @desc Rosettes that open where they land: a shell that breaks into six.
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

/// @desc Long curved lashes that come to her rather than her coming to them.
///       The one attack of hers that tracks, so a cornered player is not
///       simply out of reach of the whole fight.
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
// **Velka's, and the first attack in the game that is a piece of theatre
// rather than a verb.** It was written on the drafting table, where the attacks
// beside it each exist to make one engine feature playable; this one existed to
// find out whether the engine could hold a *composed* attack -- four movements
// that answer each other, with the shape on screen meaning something for a
// whole minute rather than for the second a bullet takes to cross. It is hers
// now, and it is the last thing she does: see `velka_phases`.
//
// The idea is a ward drawn round the player and then broken two different
// ways. A red seal with no gap in it, fired into while the player is pinned
// inside, and then thrown outwards. A blue seal with gaps a focused player can
// thread, fired into on the same terms, and then pulled *inwards* -- so the
// blue half is the same picture asking the opposite question. The red one says
// "stay in here and dodge"; the blue one says "get out while you can", and it
// only says it once.
//
// Three things are worth reading before changing any of it.
//
// **It is a rigid rotation, not a spiral.** Every rune is given a tangent
// heading, a speed proportional to its distance from the middle and the one
// turn rate they all share, which traces a true circle -- so the whole seal
// revolves as one object and the pentagram is still a pentagram a thousand
// frames later. Two of the three traces turn one way and the outer ring turns
// the other, which is the pair of counter-rotating circles the spell's own
// background is made of.
//
// **Nothing is inspected once it is fired.** The engine has no way to reach
// back into the pool for "the bullets of this seal", and it should not have
// one -- so every rune is told its whole future at the moment it is placed,
// through the queue: stop turning, then move, then either scatter or collapse,
// then either burst or go out. That is what `BQ` is for, and it is what keeps
// the attack a function of `_t`.
//
// **The collapse is arithmetic, and it is the only real maths here.** A rune
// two hundred pixels out and a rune four hundred pixels out have to reach the
// middle on the same frame or the seal arrives as a smear instead of as a
// point, so the speed is proportional to the distance and the acceleration is
// too. That makes the contraction self-similar: the seal keeps its shape all
// the way down and vanishes into a dot. `test_hex_seal` asserts it, because it
// is exactly the kind of thing that looks right in a screenshot taken on the
// wrong frame.
// ---------------------------------------------------------------------------

/// The ward. The star's five points stand on the inner ring; the outer ring is
/// the seal's own boundary, drawn round the outside of it.
#macro HEX_R_IN  296
#macro HEX_R_OUT 356

/// **The ward is drawn in beads, and the bead is the smallest thing that can
/// still be a bead.** The first version used `BSHAPE_RUNE` -- ten and a half
/// of hitbox, fifty-odd of picture -- and a ward made of those is a *heavy*
/// object: two hundred stones, each big enough to be looked at individually,
/// which is the drawing of a seal rather than a seal. It read as somebody
/// laying paving.
///
/// `BSHAPE_ORB` at seven is half the hitbox and about half the drawn width, so
/// twice as many fit in the same figure and the figure is what the eye gets
/// instead of the pieces. That is the difference between a shrine spell and a
/// miko spell in the genre this is borrowing from: the same shape, drawn in a
/// finer hand.
///
/// **The pellet is the one step too far.** At 4.2 it is the smallest thing the
/// game fires, and a ward made of them stops reading as an object at all --
/// which matters here more than anywhere, because this is the only pattern in
/// the game the player is asked to look at rather than through.
#macro HEX_BEAD BSHAPE_ORB

/// How far apart the beads stand, which is the whole difference between the
/// two halves.
///
/// **A gap is worth what is left of it once both hitboxes are taken out.** A
/// bead's is 7 and the player's is `PLAYER_R`, so a 20-pixel ring has a
/// corridor of *minus two* and is a wall, and the blue seal's 52 leaves
/// thirty, which is the width this genre calls comfortable.
///
/// **The red seal's arms are wider than its rings on purpose.** Sealed means
/// sealed at the boundary; a star that also sealed would cut the inside into
/// six rooms of about 190 pixels and then ask the player to dodge aimed fans
/// in one of them. So the ring seals and the star only divides, and 44 is
/// wider than a bead is drawn -- the arms read as a row of stones with air
/// between them rather than as rope, which is the difference between a
/// crossing and a crossing the player has to take on faith.
#macro HEX_GAP_RED_RING 20
#macro HEX_GAP_RED_ARM  44
#macro HEX_GAP_BLUE     52

/// The inscription. Every bead spends this long as a delay mark, so a seal
/// closing on top of a standing player is a warning rather than a death --
/// which is the rule `fire` is built on, and the reason this attack is allowed
/// to draw where the player is rather than around them.
///
/// **Eighteen frames was not enough and the reason is that this warning is not
/// like the others.** Everywhere else in the game a delay mark says "something
/// is about to be here", and the player is already moving and already looking.
/// Here it says "the room you are standing in is about to have a wall in it",
/// which is a bigger thing to be told and takes longer to act on -- and the
/// player is most likely mid-dash when it arrives, because the seal opens on
/// whatever frame the previous movement ended. Half a second is long enough to
/// stop, read the shape and pick a side of it.
#macro HEX_SEAL_DELAY 34

/// Degrees a frame. Slow enough to read as the seal being alive rather than as
/// something spinning, and slow enough that a rune's own speed -- radius times
/// this -- is under a pixel a frame at the outer ring.
#macro HEX_SPIN 0.11

/// The four movements, in frames. `HEX_CYCLE` is their sum and the attack is
/// `_t mod` it, so the clock in `velka_phases` decides how many times round the
/// player goes and nothing here has to know.
/// **The inscription is slow, and that is the beat that was wrong.** At
/// fifty-four frames the ward closed in under a second: the pens outran the
/// eye, and a player who happened to be crossing the middle of it found the
/// wall already drawn. Ninety frames is a pen you can follow -- you can see
/// which arm is coming for the space you are in, and move before it gets
/// there, which is the whole reason the figure is drawn rather than placed.
///
/// **And the scatter needs somewhere to go.** At ninety-six frames the red
/// ward was still visibly in the air when the blue one started closing, so two
/// figures overlapped and neither read. It is a movement of its own now.
///
/// **The blue half is longer than the red one, and the extra is all silence.**
/// See `HEX_HOLD_BLUE`: the two halves fire the same number of volleys on the
/// same beat, and the blue one holds its fire for longer afterwards because
/// what it is asking for takes longer to do.
#macro HEX_DRAW     90
#macro HEX_RED_FAN  220
#macro HEX_SCATTER  164
#macro HEX_BLUE_FAN 260
#macro HEX_IMPLODE  108
#macro HEX_BURST    110

/// **The boss stops shooting before the ward moves, and that silence is a
/// beat rather than a gap in the design.**
///
/// The two breaks are the only moments in this attack where the whole field
/// changes at once, and both of them are things the *ward* does rather than
/// things the boss visibly does -- so they need the player looking at the
/// ward. Firing into the last frames before one means the player is reading a
/// volley when the wall starts moving, and finds out about the collapse from
/// the health bar.
///
/// It is also the only way the blue half's question can be asked honestly. The
/// player is being told to leave, and being told while under fire is being
/// told to do two things at once; the last volley lands, the field goes quiet,
/// and what happens next is entirely up to them.
///
/// Long enough that the last volley fired has also *arrived* -- a bullet at
/// four and a half pixels a frame crosses the ward in about eighty.
///
/// **The two halves need different amounts of it, which is why this is two
/// numbers.** They were one, and one number could only be right for the half
/// whose break is cheaper to read. The red break is a *scatter*: the player is
/// already in the safest place there is, and what the hold buys them is a look
/// at the ward before it comes loose. The blue break is a collapse, and the
/// hold is not there to be looked at -- it is the window in which the player
/// has to find a gap, cross the ring and be outside it. That is a journey of
/// up to three hundred and fifty pixels through a wall with corridors thirty
/// wide, and eighty frames was not enough of one: what it produced was an
/// attack whose honest answer was to already be leaving when the last volley
/// was fired, which is asking the player to act on a cue that has not been
/// given yet.
///
/// The blue half's `HEX_BLUE_FAN` grew by the same amount, so this is time
/// added rather than volleys taken away -- both halves still fire four.
#macro HEX_HOLD_RED  80
#macro HEX_HOLD_BLUE 120
#macro HEX_CYCLE (HEX_DRAW + HEX_RED_FAN + HEX_SCATTER + HEX_DRAW + HEX_BLUE_FAN + HEX_IMPLODE + HEX_BURST)

/// Where each movement starts, counted from the top of a cycle. Derived rather
/// than written down, so moving one beat moves every beat after it.
#macro HEX_RED_FAN0   HEX_DRAW
#macro HEX_SCATTER_AT (HEX_RED_FAN0 + HEX_RED_FAN)
#macro HEX_BLUE_DRAW0 (HEX_SCATTER_AT + HEX_SCATTER)
#macro HEX_BLUE_FAN0  (HEX_BLUE_DRAW0 + HEX_DRAW)
#macro HEX_IMPLODE_AT (HEX_BLUE_FAN0 + HEX_BLUE_FAN)
#macro HEX_BURST_AT   (HEX_IMPLODE_AT + HEX_IMPLODE)

/// The scatter: a ward that comes loose before it comes apart.
///
/// **It used to start at a quarter of a pixel a frame and that was still a
/// jump**, because a bead on the outer ring is already travelling at two
/// thirds of one and it is travelling *sideways*. What the player saw was two
/// hundred bullets change direction on the same frame with no notice. Starting
/// at a fiftieth means the first thing that happens is the figure going soft
/// -- beads drifting off the line they were on, the circle losing its edge --
/// and only then does anything move at all. Forty frames in they have covered
/// twenty pixels; the ward has visibly failed and nothing has crossed the room
/// yet.
///
/// **And it never gets fast.** A cap of two and a half is under half what the
/// stage's own waves travel at, which makes the broken ward the one thing in
/// this attack that can be outrun rather than only threaded -- and it is the
/// difference between debris and a second attack. It is also what lets it be
/// *permanent*: nothing here expires, every bead leaves by leaving, and the
/// slowest of them is off the field inside six hundred frames, which is well
/// under a cycle.
#macro HEX_SCATTER_SPD 0.02
#macro HEX_SCATTER_ACC 0.028
#macro HEX_SCATTER_CAP 2.6

/// **How much faster a collapsing bead ends than it starts.**
///
/// The same complaint as the scatter's and the same fix, except that here the
/// speed cannot simply be lowered -- every bead has to cross its own distance
/// in exactly `HEX_IMPLODE` frames, so slowing the start means steepening the
/// finish, and this number is the whole of that trade. At four the outer ring
/// left at nearly three pixels a frame from a standing start, which is a snap.
///
/// **Twelve was still a start rather than a stir, and that is the second thing
/// this movement was getting wrong.** At twelve the outer ring left at eight
/// tenths of a pixel a frame and had covered nineteen in the first twelve
/// frames -- which is a ward that has plainly begun to move, on a movement
/// whose one cue *is* the ward beginning to move. A player reading it correctly
/// still learnt about the collapse from the collapse.
///
/// At twenty-six it leaves at a quarter of a pixel a frame -- under a third of
/// the speed it was already turning at -- and has covered under seven pixels
/// after twelve. So the first thing that happens is the figure going soft,
/// exactly as the scatter's does, and the player who is watching gets most of
/// a second of notice before anything has crossed any distance. `HEX_IMPLODE`
/// grew alongside it so that the finish did not have to steepen to pay for the
/// start: it arrives at six and a third rather than at ten.
///
/// It has to be smaller than `HEX_IMPLODE` or the profile has no solution.
#macro HEX_IMPLODE_RAMP 26

/// **What is shot at the player is white, in both movements, always.** The
/// first pass fired the red seal's fans in ember, which is a warm hue a few
/// steps from crimson -- and photographed against two hundred crimson runes
/// the one thing on the field that had to be dodged *right now* was the
/// hardest thing on it to find. The seal is the room and the fan is the
/// threat, and the colour should say which is which before the shape does.
/// White reads against crimson and against azure, which is the other half of
/// why it wins: one hue for the threat across a spell whose ground changes
/// colour halfway through.
///
/// **It said `BCOL_VIOLET` and the comment above it said white**, which is the
/// worst version of this defect rather than a smaller one: violet is
/// (176, 84, 250) and azure is (68, 140, 255), so against the blue ward the
/// fan was doing exactly what the ember one did against the red -- and the
/// paragraph explaining why that was wrong was sitting directly above the line
/// doing it. A comment that describes the fix is the hardest possible place to
/// notice the fix is not there, which is the same trap the note in `CLAUDE.md`
/// about `GAME_ERROR` records.
///
/// Found by sampling a screenshot, because nothing else could: every hue in
/// the table is a legal argument, the build is clean, and `test_hex_seal`
/// picks the volleys out by shape.
#macro HEX_COL_FAN BCOL_BONE

/// **How far off its share a bursting rune may throw, as a fraction of the
/// share.** At zero the detonation leaves on evenly spaced radials, which is
/// what it used to do and is the thing that made it read as a firework rather
/// than as something breaking: two hundred pieces of a shattered object do not
/// come off at regular intervals. At 1.6 a pair can land nearly on top of its
/// neighbour or leave twice the gap, and what the eye gets is a spray.
///
/// It is jitter from a *hash* and not from `random`, on the same terms as
/// `hex_spray_dir`: the detonation goes out the same way on the tenth attempt
/// as on the first, which is the difference between irregular and unlearnable.
#macro HEX_BURST_JITTER 1.6

/// **How much of the seal actually goes off.** Every third rune was the first
/// answer and it was too many: a hundred and eleven runes, a third of them
/// throwing a pair each, is seventy-four bullets over three shells -- which at
/// the radius they start from is twenty-five to a ring, drawn forty-eight
/// pixels wide and thirty apart. Three *solid* rings, expanding. It is a
/// beautiful photograph and it is not a pattern; there is nothing in it to
/// aim at.
///
/// **Every fifth was the answer to that and it overshot**, because the fault
/// was never the count. It was that everything thrown was the same size at one
/// of three speeds, and a hundred identical pellets on three radii is a wall
/// however few of them there are -- so cutting the count fixed the wall by
/// making the detonation small. Reported, accurately, as pathetic.
///
/// What carries the weight now is `hex_debris`: seven kinds at seven speeds,
/// so the burst thins along the radius by itself and every gap in it is a gap
/// something has *left*. That is what a count can go back up against, and
/// every fourth is where it lands.
#macro HEX_BURST_EVERY 4

/// **How far the middle may be from the player.** The seal is drawn round
/// them, and a player in a corner would otherwise put most of it outside the
/// field -- where the frame's mask hides it, so a rune that is still perfectly
/// lethal is also invisible. Clamped this much, the worst case leaves the seal
/// overhanging by less than `CULL_MARGIN` and the player still well inside the
/// inner ring.
#macro HEX_CLAMP 210

/// @desc **Demon Sealing Hex** -- a ward drawn round the player, twice, and
///       broken two different ways.
///
///       See the block above for what it is doing and why. What is here is the
///       clock: four movements, and the one thing that has to be remembered
///       between frames.
///
///       **The middle is caught once and held.** A seal takes fifty-four
///       frames to inscribe and the player moves during them, so re-reading
///       their position every frame would smear the pentagram into a comet
///       instead of drawing one. `static` is the right scope for that and the
///       only one this file should reach for: a global would have to be
///       declared in `obj_boot` and would outlive the fight, and a field
///       bolted onto the boss or onto the phase table would be writing state
///       into somebody else's data. Nothing reads it before the frame that
///       writes it, so it does not matter what it holds between runs.
function velka_demon_sealing_hex(_e, _g, _t) {
    static seal = { x: FIELD_CX, y: FIELD_CY };

    var _c = _t mod HEX_CYCLE;

    if (_c == 0 || _c == HEX_BLUE_DRAW0) {
        seal.x = clamp(_g.player.x, FIELD_X0 + HEX_CLAMP, FIELD_X1 - HEX_CLAMP);
        seal.y = clamp(_g.player.y, FIELD_Y0 + HEX_CLAMP, FIELD_Y1 - HEX_CLAMP);
        // A ring thrown out to where the seal is about to close, so the shape
        // is announced before the first rune of it lands. The delay marks say
        // the same thing rune by rune; this says it all at once.
        fx_ring(seal.x, seal.y, 40, HEX_R_OUT, 26,
                global.bullet_colour[(_c == 0) ? BCOL_CRIMSON : BCOL_AZURE],
                0.7);
    }

    if (_c < HEX_DRAW) {
        hex_seal_step(seal.x, seal.y, _c, false);

    } else if (_c < HEX_SCATTER_AT) {
        // Sealed in, and shot at. Aimed, because the cell is small and an
        // unaimed fan into it would be luck either way.
        var _rf = _c - HEX_RED_FAN0;
        if (_rf < HEX_RED_FAN - HEX_HOLD_RED && (_rf mod 38) == 8) {
            // **A volley rather than a fan.** Three rows at three speeds, each
            // turned half a step from the one in front, so what arrives is
            // three arcs a beat apart with their gaps on different lines --
            // one move, then two more. A single fan into a room this size is
            // one sidestep and then nothing for most of a second.
            fire_fan_stack(_e.x, _e.y, 5, 3, 4.4, 1.0,
                           aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 46,
                           BSHAPE_RICE, HEX_COL_FAN, 20, 4.6);
        }

    } else if (_c < HEX_BLUE_DRAW0) {
        // Nothing is fired here. The seal is coming apart on instructions it
        // was given when it was drawn, and that is the whole movement.

    } else if (_c < HEX_BLUE_FAN0) {
        hex_seal_step(seal.x, seal.y, _c - HEX_BLUE_DRAW0, true);

    } else if (_c < HEX_IMPLODE_AT) {
        var _bf = _c - HEX_BLUE_FAN0;
        if (_bf < HEX_BLUE_FAN - HEX_HOLD_BLUE && (_bf mod 40) == 8) {
            // Wider and one row shallower than the red half's, because this
            // movement is asking the player to travel rather than to hold
            // still, and a volley they cannot leave is a beat with only one
            // answer.
            fire_fan_stack(_e.x, _e.y, 7, 2, 4.6, 1.2,
                           aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 66,
                           BSHAPE_RICE, HEX_COL_FAN, 20, 5.4);
        }
    }

    // Both breaks are announced, because both are a change the ward makes to
    // itself rather than something the boss visibly does -- and a wall that
    // starts moving with no cue is a wall the player finds out about by dying.
    // The holds are what make the cue audible: the boss has been quiet for
    // `HEX_HOLD_RED` frames by the time the scatter fires and `HEX_HOLD_BLUE`
    // by the time the collapse does, and the blue one is longer because
    // leaving takes longer than looking.
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
        // **The one place in this attack allowed to be loud.** Everything else
        // it does is a shape the player has to read, and value spent on
        // spectacle is value taken off the bullets -- but this is a single
        // frame, on a field the collapse has just emptied, and what it is
        // announcing has genuinely just happened.
        //
        // Three rings at three rates and a shower of sparks, none of which can
        // hurt anybody: the *size* of a detonation is carried by the effects
        // and the *danger* by the debris, and separating those is what lets
        // the burst read as enormous without being a wall. Adding bullets to
        // make it feel bigger is the move that produced three solid rings the
        // first time round.
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

/// @desc Lay down the slice of one seal that belongs to this frame of its
///       inscription.
///
///       **Seven traces are drawn at once and all seven finish together**,
///       which is what the player sees and is the only reason it is written
///       this way. They have wildly different lengths -- an arm is 590 pixels
///       and the outer ring is 2160 -- so a trace does not lay down one rune a
///       frame. It lays down the runes whose index falls in this frame's share
///       of its own length, which is `n * f / DRAW` to `n * (f + 1) / DRAW`:
///       the arms crawl, the rings race, and the last rune of every one of
///       them lands on frame `HEX_DRAW - 1`.
///
///       `_idx` is a running index across the whole seal rather than across a
///       trace, because the detonation takes every third rune of the seal and
///       wants them spread over all of it.
function hex_seal_step(_cx, _cy, _f, _blue) {
    var _arm = 2 * HEX_R_IN * dsin(72);

    var _gap_arm  = _blue ? HEX_GAP_BLUE : HEX_GAP_RED_ARM;
    var _gap_ring = _blue ? HEX_GAP_BLUE : HEX_GAP_RED_RING;

    var _arm_n = max(2, round(_arm / _gap_arm));
    var _out_n = max(8, round(2 * pi * HEX_R_OUT / _gap_ring));
    var _in_n  = max(8, round(2 * pi * HEX_R_IN  / _gap_ring));
    var _n     = _arm_n * 5 + _out_n + _in_n;

    var _col = _blue ? BCOL_AZURE : BCOL_CRIMSON;

    // How long a rune placed on this frame has to stand before the seal
    // breaks, counted in the frames it is *live* -- a delay mark does not move
    // and does not tick the queue, so it comes out of the sum.
    var _wait = HEX_DRAW + (_blue ? HEX_BLUE_FAN : HEX_RED_FAN)
                - _f - HEX_SEAL_DELAY;

    // ---- the star ---------------------------------------------------------
    //
    // Five arms, each running from its own point to the point two round. Each
    // stops short of its far end, so a vertex belongs to exactly one arm and
    // is not drawn twice.
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
    // The outer one is written clockwise and the inner one anticlockwise, and
    // each then *turns* the way it was written -- so the trace does not stop
    // when the seal is finished, it slows to the pace of the ward.
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

    // **Half a step off the top, and that half step is a bug fix.** Both
    // rings are laid out from 90 degrees and their bead counts are coprime, so
    // they line up *exactly once* -- at the top, where they start. What that
    // draws is a radial channel straight through the pair at one point of the
    // circle, which reads as a gap in a ward that has none, and it was
    // reported that way. Offsetting the inner ring by half its own step means
    // there is nowhere the two agree, so the band is even the whole way round.
    // It also moves the ring off the star's top vertex, which sits on this
    // radius and was doubling a bead.
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

/// @desc Which way one bead of a broken ward goes: anywhere, and the same
///       anywhere every time.
///
///       **This is not `fire_spray` and the difference is the whole reason it
///       is written out.** A pattern made of noise is a pattern nobody can
///       learn, which is why that helper is used once in the whole game -- but
///       what makes noise unlearnable is that it is *different every attempt*,
///       not that it is irregular. A hash of the bead's own index is fixed for
///       the life of the game: the ward comes apart in the same two hundred
///       and seventy directions on the tenth attempt as on the first, so it
///       can be read, remembered and answered, and it still looks like
///       something falling to pieces rather than something being tidied away.
///
///       The mixing matters more than it looks. Beads are indexed in the order
///       they are drawn, so consecutive indices are next to each other on the
///       figure -- and any plain stride would send neighbours off in a
///       marching sequence of headings, which the eye reads instantly as a
///       fan. This is the usual sine hash, and it is used because it does not
///       have that property.
function hex_spray_dir(_i) {
    return hex_hash(_i, 78.233) * 360;
}

/// @desc A number in `[0, 1)` from an index and a seed, fixed for the life of
///       the game. The usual sine hash, factored out because the detonation
///       wants three independent ones off the same rune -- see
///       `hex_spray_dir` for the argument that this and not `random` is what a
///       pattern should be irregular *with*.
function hex_hash(_i, _seed) {
    // **`frac` keeps the sign in GML**, so this is `(-1, 1)` and not `[0, 1)`
    // without the fold. `hex_spray_dir` never noticed, because a negative
    // fraction of a turn is the same heading as its complement -- but an index
    // into a table is not an angle, and half the detonation would have come
    // off as the first row of `hex_debris`: chunks, all of them, at the one
    // speed. Which is a shell, and a shell is what this was getting away from.
    var _v = frac(sin(_i * 12.9898 + _seed) * 43758.5453);
    return (_v < 0) ? _v + 1 : _v;
}

/// @desc One kind of debris the detonation throws: a shape, and the speed
///       something that size comes off at.
///
///       **Same colour, different stone.** The burst used to be one shape at
///       one of three speeds -- a hundred pellets on three radii -- and what
///       that draws is three expanding rings, which is a firework. A ward
///       coming apart is not sorted; it throws chunks and grit in the same
///       breath, and the eye reads *that* as an explosion long before it has
///       counted anything. The hue stays cyan across all seven, because what
///       is being said is "these are all one thing breaking" and colour is how
///       this game says that -- it is the same argument that makes a split
///       inherit its parent's colour, applied to a burst that deliberately
///       does not inherit its parent's shape.
///
///       **The heavy pieces are the slow ones, and that is the design rather
///       than a garnish.** It reads as mass, so the cloud grades itself -- grit
///       out at the edge, chunks still near the middle -- which puts gaps along
///       the radius that nothing had to author. And it means the player who
///       answered the blue half and left gets the sparks, while the one who is
///       still standing in the middle of it gets everything: the detonation
///       pays out by how far away you managed to get, which is the one thing
///       this half of the attack is asking for.
///
///       Nothing here comes to a point at the fast end by accident either. A
///       mote and a pellet are the two smallest things the game fires, and the
///       two that read as sparks rather than as shot.
///
///       `_h` is a hash in `[0, 1)`, not an index, so the caller never has to
///       know how many kinds there are.
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

/// @desc One bead of a seal: placed, set turning about the middle, and told
///       what to do when the seal breaks `_wait` frames from now.
///
///       **Every instruction it will ever get is given here.** See the block
///       at the top of this section: nothing can find this bullet again.
function hex_rune(_cx, _cy, _x, _y, _col, _spin, _wait, _blue, _idx, _n, _f) {
    var _r = point_distance(_cx, _cy, _x, _y);

    // **The figure is laid out in the ward's own turning frame, and without
    // that the ring does not close.**
    //
    // Every bead turns at the same rate, but it only starts turning when it
    // goes live -- so a bead placed on the last frame of the inscription has
    // turned nothing while the one placed on the first frame has been turning
    // for the whole of it. The ring is drawn from the top all the way round
    // and comes back to a start that has moved: what that leaves is one gap at
    // the seam four times wider than every other gap, frozen in the moment the
    // last bead goes live, in a ward whose entire claim is that it has no gap
    // in it. It was reported as exactly that, and it is one of those defects
    // that is obvious in a picture and invisible in the arithmetic that made
    // it -- the placement is uniform, and the *placing* is what is not.
    //
    // Adding back the turn this bead is going to miss puts it where it will
    // need to have been. So the pen runs slightly ahead of the figure while it
    // writes, and every bead rotates into its place behind it: the ring is
    // only truly round once the last one is live, which is what
    // `test_hex_seal` waits for before it measures.
    var _phi = point_direction(_cx, _cy, _x, _y) + _spin * _f;
    _x = _cx + lengthdir_x(_r, _phi);
    _y = _cy + lengthdir_y(_r, _phi);

    // A true circle: heading tangent to it, speed the arc it covers in a
    // frame. Speed and turn together are what make the path curve, and a speed
    // proportional to the radius is what makes every rune keep station with
    // every other one.
    var _u = fire(_x, _y, _r * degtorad(abs(_spin)),
                  _phi + ((_spin >= 0) ? 90 : -90),
                  HEX_BEAD, _col, HEX_SEAL_DELAY);
    if (_u == undefined) return;
    _u.turn = _spin;

    // **Where the middle will be from here by the time the seal breaks.** A
    // rigid rotation carries the bearing to the centre round with the rune, by
    // exactly the angle the rune itself has travelled -- `_spin` degrees for
    // each of the `_wait` frames it is alive first. Reading the bearing now
    // and using it then would aim every rune at where the middle used to be,
    // and the collapse would miss by the angle the seal had turned through.
    var _turned = _phi + _spin * _wait;

    // The orbit has to be cancelled or it would bend the break into a spiral.
    bullet_turn_at(_u, _wait, 0);

    if (!_blue) {
        // **Every which way, and that is the difference between a break and a
        // dismissal.** The first version threw each bead outward along its own
        // radius, give or take twenty degrees, and the figure kept its shape
        // all the way off the screen -- which looks like the ward being
        // *lifted*, and, worse, means the room it was enclosing is the one
        // place in the field nothing is travelling through. A player who spent
        // the last three seconds learning to stand in the middle of it was
        // rewarded with three more seconds of standing in the middle of it.
        //
        // Scattered across the whole circle, half of it comes back through
        // that room, and the safe place stops being safe at the moment the
        // thing making it safe comes apart.
        bullet_move_at(_u, _wait, HEX_SCATTER_SPD, hex_spray_dir(_idx));
        bullet_accel_at(_u, _wait, HEX_SCATTER_ACC, HEX_SCATTER_CAP);
        // **Nothing expires. Every bead leaves by leaving.**
        //
        // An earlier pass gave these a lifetime, so that the red ward was
        // certain to be gone before the blue one closed. It bought tidiness
        // and paid for it in the only currency this genre has: a bullet that
        // winks out in the middle of the field is a bullet the player learnt
        // to respect and was then told not to bother, and the next thing they
        // learn is that some of the bullets here are not real. `CULL_MARGIN`
        // is what removes these, on the same terms as everything else in the
        // game, and the slowness is what makes that affordable -- see
        // `HEX_SCATTER_CAP`.
        //
        // What it costs is that the last of the debris is still drifting while
        // the next ward is being inscribed. That reads as debris, because it
        // is slow and scattered and the wrong colour, and it is a better thing
        // to be looking at than a field that tidies itself.
        return;
    }

    // ---- the collapse -----------------------------------------------------
    //
    // Speed and acceleration both proportional to the distance, and scaled so
    // that the distance covered over `HEX_IMPLODE` frames is *exactly* the
    // distance to the middle. Every rune therefore arrives on the same frame
    // whichever ring it stood on, and the seal shrinks as a seal rather than
    // collapsing tip first.
    //
    // The two numbers are the only ones here that are solved rather than
    // chosen. Writing `T` for the travel, `R` for `HEX_IMPLODE_RAMP` and `c0`,
    // `ca` for the fractions of the distance: the step applies the
    // acceleration before it moves, so what is covered is
    // `T*c0 + ca*T*(T+1)/2` and that has to come to 1; and the last frame is
    // asked to be `R` times the speed of the first, which fixes `ca/c0` at
    // `(R-1)/(T-R)`. Everything else follows, and `R` is the only one of the
    // three anybody should be editing.
    var _ratio = (HEX_IMPLODE_RAMP - 1) / (HEX_IMPLODE - HEX_IMPLODE_RAMP);
    var _c0    = 1 / (HEX_IMPLODE * (1 + _ratio * (HEX_IMPLODE + 1) / 2));
    var _into  = _turned + 180;

    bullet_move_at(_u, _wait, _r * _c0, _into);
    bullet_accel_at(_u, _wait, _r * _c0 * _ratio, BQ_KEEP);

    var _land = _wait + HEX_IMPLODE;

    if ((_idx mod HEX_BURST_EVERY) != 0) {
        // Spent on arrival: it stops dead on the point and goes out. Stopping
        // matters -- a rune that sailed on through would come out of the far
        // side of the detonation looking like part of it.
        bullet_move_at(_u, _land, 0, BQ_KEEP);
        bullet_expire_at(_u, _land, 14);
        return;
    }

    // ---- and the detonation -----------------------------------------------
    //
    // **One bead in four bursts, and the burst is authored rather than
    // inherited.** All of them arrive at the same point, so their headings are
    // whatever the seal's geometry happened to give them -- dense along the
    // arms, even round the rings -- and a split fired straight down those
    // would be a burst with a bald patch in it. The offset is worked back from
    // the heading this rune is going to have, so the pair it throws lands on
    // an angle this function chose.
    //
    // **The share is what stops it having a hole in it and the jitter is what
    // stops it having spokes**, and both are needed. An even share alone is a
    // sunburst: two hundred pieces of a broken object arriving on regularly
    // spaced radials, which is a firework rather than a detonation. A jitter
    // alone would leave the holes to luck. So the runes are dealt evenly round
    // the circle and then each is knocked off its own share by up to
    // `HEX_BURST_JITTER` of one, from a hash of its own index -- so the spray
    // is irregular, has no hole in it, and is the *same* spray every attempt.
    //
    // Three hashes off the same rune, on three seeds: which way it throws, how
    // hard, and what it throws. Independent, so no two of them line up into a
    // pattern the eye can find.
    var _ex   = (_n + HEX_BURST_EVERY - 1) div HEX_BURST_EVERY;
    var _q    = _idx div HEX_BURST_EVERY;
    var _step = 180 / max(1, _ex);
    var _want = _q * _step
              + (hex_hash(_q, 4.117) - 0.5) * _step * HEX_BURST_JITTER;

    // **What comes out is not what went in.** See `hex_debris`: seven kinds
    // graded by mass, so the cloud sorts itself as it expands and the heavy
    // half of it never leaves the middle. The speed carries a sixth either way
    // on top of the kind's own, which is enough that two pieces of the same
    // stone do not travel as a pair -- the grading is a trend and not a set of
    // shells, and a shell is the thing this is getting away from.
    var _d = hex_debris(hex_hash(_q, 27.611));
    bullet_graphic_at(_u, _land, _d.shape, BCOL_CYAN);
    bullet_split_at(_u, _land, 2,
                    _d.spd * (0.84 + 0.32 * hex_hash(_q, 61.409)),
                    _want - _into);
}
