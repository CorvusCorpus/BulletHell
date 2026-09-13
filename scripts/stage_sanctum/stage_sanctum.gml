/// @desc Stage three: the Gilded Sanctum, and Mika at the end of it.
///
/// **A placeholder stage, and what it exists to make playable is the rings.**
/// `scripts/ring_functions` adds the first object in this game that is neither
/// a bullet nor an enemy -- a thing that stops the player's fire, can be
/// charged until its metal kills, can be strung to another one with a line of
/// current, and fires patterns of its own. None of that can be judged from an
/// engine test, so there is a stage: nine graded encounters, every one of them
/// built round a ring, played through the game's own console, ceremony and
/// grading.
///
/// **Every ring is the same size and there are never more than six.** The
/// first pass drew them at four hundred pixels and let each attack pick a
/// radius, which produced architecture rather than the bands he wears -- two
/// of them walled the field, and three concentric ones made a boss who could
/// not be shot at all from outside. `RING_R` is a constant now and there is no
/// way for an attack to ask for a different one, so what the player learns is
/// one object and then six arrangements of it.
///
/// **Every attack here is a placeholder in the sense the whole game's are** --
/// see the note about the bar in `CLAUDE.md`. What is *not* placeholder is the
/// vocabulary: between them these nine use every verb a ring has, which is the
/// same argument the drafting table's first five drafts are chosen on. When
/// Mika is written for real it is these rows that get replaced, and the pool
/// underneath them will not have to change.
///
/// **The background is stage one's, borrowed, and that is temporary and
/// deliberate.** His palace is a corridor and a corridor is a session of its
/// own -- the grove took `bg_corridor` and `bg_grove` between them. Until then
/// the brimstone stack is the honest stand-in: it is nearly black with narrow
/// gold-orange light in it, which is the one palette in the project a black
/// and gold caster reads against without anything being retuned.
///
/// **The spell wash is `SPELLBG_SIGIL` and it very nearly did not work, for a
/// reason worth writing down: the fallback's own motif is a ring.** Two
/// counter-rotating magic circles behind a boss whose entire fight is rings
/// looks like the perfect fit on paper, and photographed it is scenery drawn
/// in the same shape as the one object on the field that has to be told apart
/// from scenery -- which is the ember-and-pellet finding at four hundred
/// pixels. What separates them is *value and hue*, not shape: the wash is
/// indigo for every one of his spells, so his rings are the only warm lit
/// thing in the frame. The first pass ran `Gilded Aperture` gold on gold and
/// came back as three gold bands dissolving into a gold field, which is
/// exactly what `Cinder Waltz` did and exactly what the subtraction rule is
/// for.
///
/// Mika is the head mage of Ashiah, the Living God of Death. What that buys
/// the fight is the reason the rings are his: they are the god's seals, and he
/// is the one who is allowed to open them.

// ---------------------------------------------------------------------------
// The numbers this stage is written in
//
// Written out here rather than in `constants`, because a pattern is meant to
// read as a paragraph -- see the note on speed in `constants`. What is in
// `constants` is the engine's half: how big a ring is, how thick its metal is,
// how long one takes to arrive, how long a charge warns for.
// ---------------------------------------------------------------------------

#macro MIKA_HP 2800
#macro MIKA_RING_COL BCOL_GOLD

// **Six, and it is a ceiling rather than a target.** Six rings of `RING_R` on
// one orbit leave gaps about as wide as a ring, which is what makes an
// aperture an aperture; seven closes them and five makes the arrangement read
// as an accident.
#macro MIKA_RING_N 6

// How far out his formations sit. One number for all of them, so the player
// learns where his furniture lives.
#macro MIKA_ORBIT 300

// ---------------------------------------------------------------------------
// The stage
// ---------------------------------------------------------------------------

function stage_sanctum_def() {
    return {
        id: "gilded_sanctum",
        name: "THE GILDED SANCTUM",
        subtitle: "the death-god's hall of rings",
        // **Open from the start, on the same terms stage two is.** The rack's
        // locks pace a first playthrough, and this stage exists so that a
        // mechanic can be *played*; gating the thing that has to be tried
        // behind two stages of progress is the circle the drafting table's
        // note is about. It goes to `2` on the day Mika has a fight worth
        // reaching, and it is one number.
        needs: 0,
        make_bg: bg_sanctum,
        build: stage_sanctum_script,

        // Provisional, exactly as the other two stages': nine attacks -- the
        // Proctor's two and Mika's seven -- and five wave groups nobody grades
        // yet. See `rank_functions`.
        encounters: 14,

        bosses: [
            { name: "THE PROCTOR", spawn: sanctum_midboss_spawn,
              phases: sanctum_midboss_phases },
            { name: "MIKA", spawn: mika_spawn, phases: mika_phases },
        ],
    };
}

/// @desc The running order.
///
///       **The fodder teaches the ring before the Proctor tests it.** The
///       second wave group flies in behind a pair of rings that are doing
///       nothing but sitting there, so the first time a player's shots are
///       eaten it is by an object with nothing else going on, in a wave that
///       cannot kill them for taking a second to work out why.
function stage_sanctum_script() {
    var _e = [];

    // --- the way in ----------------------------------------------------
    array_push(_e, ev(80, wave_cross(EnemyKind.Wisp, 6, -1, 210, 56, 5.6, 3,
                                     BCOL_GOLD, sanctum_fodder_pellet)));
    array_push(_e, ev(230, wave_cross(EnemyKind.Wisp, 6, 1, 330, -56, 5.6, 3,
                                      BCOL_AMBER, sanctum_fodder_pellet)));
    array_push(_e, ev_gate(280));

    // --- and here is what a ring does ----------------------------------
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

    // --- the lesser hand -----------------------------------------------
    array_push(_e, ev(770, wave_boss(sanctum_midboss_spawn)));
    array_push(_e, ev_gate(790));

    // **And the hall opens.** One line, and it is the whole of the stage's
    // second half: `bg_set_omen` eases `reveal` from nought to one, which
    // carries the camera from nine hundred units up aimed at the floor down
    // to flying height and level. Everything before this point is marble and
    // the feet of the stacks; everything after it is the room.
    //
    // **Written just after the gate rather than at a chosen frame**, because
    // the stage clock is held while a boss is on the field -- so this fires
    // on the frame the Proctor is finished with, whenever that turns out to
    // be, rather than at a time somebody guessed the fight would take. Same
    // placement the grove's turn uses, for the same reason.
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

/// @desc Two rings standing in the field with nothing else going on.
///
///       **A wave shape rather than an attack**, because it is the stage
///       introducing a rule and not a boss using one. They do not fire, they
///       do not charge, and they expire on their own -- all they do is eat
///       shots aimed through them, once, in a place where finding that out
///       costs nothing.
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
// What the fodder does
//
// Stage one's rules at stage one's rates, in gold and bone. A wave that can
// kill an attentive player is a wave that has taken the boss's job.
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
// Rings, the way this fight puts them down
//
// Two helpers, because two shapes came up in nearly every attack: a ring that
// rides the caster at a distance, and a ring that stands where it is put.
// Everything else an attack writes by hand.
// ---------------------------------------------------------------------------

/// @desc A ring orbiting the caster at `_dist`, starting at `_ang0`.
///
///       **It rides the boss rather than being repositioned by the attack.**
///       `ring_attach` is the same seam a beam's origin uses, and it buys the
///       thing that makes an orbit read: the ring keeps station through the
///       boss's own drift, so what the player sees is furniture he is carrying
///       rather than two objects that happen to be moving similarly.
///
///       `_shoot` is the ring's own pattern -- a function of (ring, run,
///       frame), which is a boss attack one level down. **Named `shoot` and
///       not `fire`**, because a struct member shadows a global inside a
///       method and `fire` is the most-called function in the game: a member
///       of that name would silently capture every plain shot the closure
///       tried to make.
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
        // Through a local, the way `boss_end_phase` reads `on_phase_end`: a
        // bare `shoot(...)` is a call to a *struct member*, which compiles and
        // which `check_unknown_functions` cannot tell from a call to a
        // function nobody wrote -- and that check is the one thing standing
        // between a typo here and a modal error box under the harness.
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

/// @desc A whole formation of orbiting rings, kept and validated.
///
///       **The references have to be kept and they have to be checked**, which
///       is why this answers a struct rather than an array. Three of his
///       attacks pair rings up with current afterwards, and a ring struct is
///       reused out of the pool -- so a bare array of references is an array
///       that may be pointing at somebody else's rings by the time it is read.
///       `gen` beside each one is the whole answer; see `ring_valid`.
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
// The Proctor
//
// **A lesser hand of the archive, and the stage's second lesson.** The
// gateposts said a ring stops your shots; this one says a ring *moves*, and
// that the thing behind it moves too.
// ---------------------------------------------------------------------------

function sanctum_midboss_def() {
    return {
        name: "THE PROCTOR",
        title: "one of the lesser hands",
        // Stage one's stone sentry, borrowed -- the same decision the grove's
        // midboss records. A placeholder that is obviously a placeholder beats
        // a new one nobody drew.
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
// Seven attacks, and every one of them is about a ring. Three non-spells that
// are one idea getting harder -- rings he carries, rings he throws, rings he
// closes round the player -- and four spells that each add a verb: the
// aperture, the current, the gates, and all of it at once.
// ---------------------------------------------------------------------------

function mika_def() {
    return {
        name: "MIKA",
        title: "head mage to the Living God of Death",
        sprite: spr_boss_mika,
        eye: spr_eye_mika,
        col: BCOL_GOLD,
        radius: 64,
        // **The fallback, and here it is the right answer rather than the
        // absence of one.** `SPELLBG_SIGIL` is two counter-rotating magic
        // circles; the caster's whole fight is rings. See the note at the top
        // of this file about why that nearly went wrong anyway.
        spell_bg: SPELLBG_SIGIL,
        final: true,
    };
}

function mika_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_GOLD, bg: -1,
          hp_end: 0.88, time: 24 * FPS, attack: mika_signet },

        // **Every spell of his washes indigo and none of them washes in its
        // own colour**, which is two rules at once. One background per boss,
        // because an arena is a *place* and a place that changes hue every
        // forty seconds stops being one -- the spell's own colour already
        // lives on its banner, its notch and its bullets. And the wash has to
        // be the colour his rings are not: see the note at the top.
        { kind: AttackKind.Spell, name: "Gilded Aperture",
          col: BCOL_GOLD, bg: BCOL_INDIGO,
          hp_end: 0.74, time: 40 * FPS, attack: mika_gilded_aperture,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_AMBER, bg: -1,
          hp_end: 0.63, time: 24 * FPS, attack: mika_two_coins },

        { kind: AttackKind.Spell, name: "Ashiah's Circuit",
          col: BCOL_CYAN, bg: BCOL_INDIGO,
          hp_end: 0.46, time: 42 * FPS, attack: mika_ashiah_circuit,
          move: BossMove.Fixed },

        { kind: AttackKind.NonSpell, name: "", col: BCOL_BONE, bg: -1,
          hp_end: 0.34, time: 26 * FPS, attack: mika_close_reading,
          move: BossMove.Track },

        { kind: AttackKind.Spell, name: "Three Open Gates",
          col: BCOL_AMBER, bg: BCOL_INDIGO,
          hp_end: 0.18, time: 44 * FPS, attack: mika_three_gates },

        { kind: AttackKind.Spell, name: "Grand Orrery",
          col: BCOL_GOLD, bg: BCOL_INDIGO,
          hp_end: 0.0, time: 50 * FPS, attack: mika_grand_orrery,
          move: BossMove.Fixed },
    ];
}

function mika_spawn(_g) {
    return boss_spawn(FIELD_CX, FIELD_Y0 - 200, MIKA_HP, mika_phases(),
                      mika_def());
}

/// @desc Two rings on a long lead, and him firing past them.
///
///       The opening, and the whole of what it teaches is that a ring has to
///       be gone round. Two rather than one, because with a single ring the
///       answer is "stand anywhere else" and the player never finds out what
///       the object does.
function mika_signet(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, 2, 230, 0.85, MIKA_RING_COL, mika_signet_rim, 0,
                       0.6);
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

function mika_signet_rim(_ring, _g, _t) {
    if ((_t mod 52) != 22) return;
    ring_fire_rim(_ring, 9, 3.8, _t * 2.4, BSHAPE_ORB, MIKA_RING_COL, 18);
}

/// @desc **Gilded Aperture.** Six rings on one orbit round him, turning, and
///       the gaps between them are the only line to the boss.
///
///       **The aperture is the *gap*, which is what the first version got
///       wrong.** That one drew three enormous rings concentric on him, on the
///       reasoning that each one the player got inside was one fewer band in
///       the way -- an idea that reads well written down and which in practice
///       is a boss who cannot be shot at all from anywhere sensible. Six rings
///       of one size on a ring of their own leaves six windows about as wide
///       as a ring, and they sweep: the answer is to find where the window is
///       now and be under it, which is a *positional* question with an answer
///       that is always somewhere.
///
///       It is `Fixed` for the reason `Seed & Bloom` is: the formation is
///       measured from its own origin, and an origin wandering four hundred
///       pixels would turn a thing to be lined up with into a thing to be
///       chased.
///
///       The volleys are **tangential** -- they run round the orbit rather
///       than out of it -- because radial ones would put a wall in every one
///       of the windows the attack exists to open.
function mika_gilded_aperture(_e, _g, _t) {
    if (_t == 0) {
        mika_formation(_e, MIKA_RING_N, MIKA_ORBIT, 0.55, MIKA_RING_COL,
                       mika_aperture_rim, 0, 1.0);
    }
    // His own fire is slow, wide and aimed, so the player cannot simply park
    // under a window and stay there. Nothing here is a wall: the walls turn.
    if ((_t mod 96) == 46) {
        fire_fan_stack(_e.x, _e.y, 9, 2, 4.6, 1.0,
                       aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 60,
                       BSHAPE_RICE, BCOL_BONE, 22);
    }
}

/// @desc **Cyan, not amber.** The rings are the gold thing on this field and
///       nothing else may be: a gold volley off a gold ring photographed as a
///       haze of sparkles with the obstacles somewhere inside it, which is the
///       ember-and-pellet finding for the third time in this file. Cyan is the
///       arcane accent the whole interface already uses and it is the furthest
///       thing from gold that still reads on indigo.
function mika_aperture_rim(_ring, _g, _t) {
    if ((_t mod 50) != 22) return;
    ring_fire_tangent(_ring, 5, 3.2, _t * 2.2, BSHAPE_MOTE, BCOL_CYAN, 1, 16);
}

/// @desc Three rings walking across the field, and a spiral under them.
///
///       The middle non-spell, and the one that says a ring is not always
///       where he is: these have to be read as obstacles moving through the
///       place the player was going to stand.
function mika_two_coins(_e, _g, _t) {
    var _cycle = _t mod 190;
    if (_cycle == 0) {
        var _lap = _t div 190;
        for (var _i = 0; _i < 3; _i++) {
            var _from = ((_lap mod 2) ? -1 : 1);
            var _r = mika_place_ring(
                FIELD_CX + _from * (FIELD_W * 0.5 + 160),
                FIELD_Y0 + 260 + _i * 170, BCOL_AMBER, mika_coin_rim, 200);
            if (_r == undefined) break;
            _r.vx = -_from * 4.2;
            _r.spin = -_from * 1.3;
        }
    }
    if ((_t mod 5) == 0) {
        fire_ring(_e.x, _e.y, 2, 5.4, _t * 3.1, BSHAPE_PELLET, BCOL_GOLD, 12);
    }
}

function mika_coin_rim(_ring, _g, _t) {
    if ((_t mod 40) != 16) return;
    ring_fire_rim(_ring, 7, 3.4, _t * 3.3, BSHAPE_ORB, BCOL_AMBER, 16);
}

/// @desc **Ashiah's Circuit.** Six rings on an orbit, strung together in pairs
///       with current, turning -- a cage with doors in it.
///
///       The one attack in the fight whose danger is *not* on the rings. The
///       player reads each bar off the two objects at its ends, which is a
///       different kind of reading from anything else here -- and it is why
///       the bolt is drawn off the same segment `ring_hits` tests, jittered
///       only within the width it kills at.
///
///       **Three chords rather than six, and which three moves.** Stringing
///       every neighbour would close the cage, and a closed cage round a boss
///       is the unanswerable defect the aperture was already rewritten to get
///       rid of. Linking alternate pairs leaves three doors; shifting the
///       pairing every few seconds moves them, so standing in one is a lease
///       rather than a solution.
function mika_ashiah_circuit(_e, _g, _t) {
    static circuit = { ring: [], gen: [] };

    if (_t == 0) {
        circuit = mika_formation(_e, MIKA_RING_N, MIKA_ORBIT, 0.60, BCOL_CYAN,
                                 mika_circuit_rim, 0, 1.2);
    }

    // The pairing walks: (0,1)(2,3)(4,5), then (1,2)(3,4)(5,0). Two states, so
    // every door becomes a bar and every bar becomes a door.
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

/// @desc Six rings set round wherever the player is, which then charge and
///       close in.
///
///       **The one attack answered by leaving rather than by dodging**, and
///       the reason he tracks during it: the ring of rings is drawn round the
///       player, so the player is inside it, so a boss that wandered off would
///       be a boss they could not shoot for the whole attack. Same finding as
///       `Demon Sealing Hex` and the same fix -- see `BossMove`.
///
///       The order of the three things it does is the whole of what makes it
///       fair. The rings arrive harmless and wide apart, *then* the metal
///       warns, and only then do they move inward. A player who reads it and
///       walks out through a gap is never touched; a player who stands in the
///       middle admiring it is closed in on by a wall they watched being
///       built.
///
///       **Closing in is movement and not growth**, which is what a fixed ring
///       size buys: six objects converging is legible in a way one object
///       silently changing scale never was.
function mika_close_reading(_e, _g, _t) {
    static reading = { ring: [], gen: [] };

    var _cycle = _t mod 230;

    if (_cycle == 0) {
        var _cx = clamp(_g.player.x, FIELD_X0 + 300, FIELD_X1 - 300);
        var _cy = clamp(_g.player.y, FIELD_Y0 + 340, FIELD_Y1 - 300);
        reading = { ring: [], gen: [] };
        for (var _i = 0; _i < MIKA_RING_N; _i++) {
            var _a = _i * (360 / MIKA_RING_N) + _t;
            var _r = mika_place_ring(_cx + lengthdir_x(300, _a),
                                     _cy + lengthdir_y(300, _a),
                                     BCOL_BONE, mika_reading_rim, 210);
            reading.ring[_i] = _r;
            reading.gen[_i] = (_r == undefined) ? -1 : _r.gen;
            if (_r != undefined) _r.spin = 0.9;
        }
        fx_ring(_cx, _cy, 40, 300, 24, global.bullet_colour[BCOL_BONE], 0.7);
    }

    // Charge, then close. Read back through the serial rather than trusted:
    // the pool hands slots out again, and a phase change or a full pool is
    // enough for these to be somebody else's rings by now.
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

function mika_reading_rim(_ring, _g, _t) {
    if ((_t mod 50) != 24) return;
    // Outward, which keeps the middle of the figure the safe place right up
    // until the rings themselves arrive in it. Firing inward would answer the
    // attack's own question before it has been asked.
    ring_fire_rim(_ring, 7, 2.8, _t * 2.1, BSHAPE_MOTE, BCOL_BONE, 18);
}

/// @desc **Three Open Gates.** Three rings standing across the field, each
///       with a beam through its middle, all three turning.
///
///       The verb this one adds is `ring_beam`: a laser anchored at a ring's
///       *centre*, which follows it. Through the middle rather than off the
///       rim, because the hole is what a ring is for -- a beam leaving the
///       edge would be a gun somebody had bolted a hoop to.
///
///       The gates drift apart and back on their own, so the three beams are
///       never the same three angles twice, and the rings themselves are still
///       eating shots the whole time.
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

/// @desc **Grand Orrery.** Everything he has, turning at once.
///
///       Six rings on two orbits, adjacent pairs strung with current in
///       rotation, one band charged at a time, and volleys off every rim. It
///       is the last attack, so it is the one that is allowed to be a sum
///       rather than an idea -- and it is where the four verbs a ring has are
///       on screen together, which is the only honest way to find out whether
///       they read as four things or as one mess.
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

    // One pair strung at a time, walking round the six. The link is renewed
    // rather than held, so a ring lost to a full pool takes one beat out of
    // the rotation instead of the whole attack.
    if ((_t mod 84) == 0) {
        var _k = (_t div 84) mod MIKA_RING_N;
        mika_link(orrery, _k, (_k + 1) mod MIKA_RING_N, 68);
    }

    // ...and one band charged at a time, on a different period, so the two
    // never lock into one rhythm.
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
