/// @desc The drafting table: attacks that have no boss yet.
///
/// **A pattern is an idea long before it is a character**, and until now this
/// game had nowhere to put one. Adding an attack meant adding it to a boss,
/// and adding a boss means a phase table, a name, a title, a sprite, a
/// background and a place on the rack -- so the cheapest way to find out
/// whether a pattern is any fun was to bolt it onto Ziggy, play it out of
/// context, and take it off again. That is a bad deal in both directions: it
/// disturbs a fight that is already tuned, and it judges the new pattern
/// against a boss it was never written for.
///
/// So there is one more entry on the rack, it is not a stage, and every attack
/// filed under it is one nobody has claimed. **It is written as content, not
/// as a debug menu** -- the same discipline `practice_functions` keeps and for
/// the same reason: a draft played through the game's own console, ceremony
/// and grading is a draft you have actually seen, and a draft played through a
/// diagnostic view is a draft you will have to judge twice.
///
/// **Its whole surface is a row in `draft_list`.** A name, a hue, a clock and
/// a function of `_t`; everything else -- what span of the bar it owns, which
/// slot it is, whether it is a spell -- is derived, so adding an idea changes
/// exactly one line and taking one away changes exactly one line. That is the
/// entire point. A table of hand-written `hp_end` values would mean the second
/// thing you do after having an idea is arithmetic.
///
/// **Ziggy's sprite stands in for the caster**, because a placeholder that is
/// obviously a placeholder is better than a new one nobody drew: he is the
/// only boss art in the game, `tools/make_boss.py` says so, and a draft is a
/// pattern rather than a portrait. What is not borrowed is his *hue* or his
/// arena -- the aura is violet, which nothing on his stage uses, and the
/// background is the generic pair of magic circles rather than his forge. A
/// draft that arrived in somebody else's colours and somebody else's place
/// would read as an attack of his that had gone wrong.
///
/// **Deleting this file and its line in `rack_list` removes the whole
/// feature**, which is deliberate: everything here is seed content and a
/// scaffold, and the day the drafts have all found bosses is the day the card
/// should stop being on the rack.

// ---------------------------------------------------------------------------
// The rack
// ---------------------------------------------------------------------------

/// @desc Is this rack entry the drafting table rather than a stage?
///
///       **Read through `[$ ]`, because every other entry lacks the field.**
///       A bare `_def.draft` on one of the eight stages does not answer
///       `undefined` -- a missing struct member in GML raises -- which is the
///       same trap `practice_bosses` is written around one file over.
function stage_is_draft(_def) {
    if (_def == undefined) return false;
    return _def[$ "draft"] ?? false;
}

/// @desc What the rack shows: every stage, and the drafting table after them.
///
///       **`stage_list` is left alone and stays honest.** Its docstring says
///       "every stage in the game" and the drafting table is not one -- it has
///       no waves, no place, no clear to earn and no line in the save -- so
///       putting it in there would make that sentence false and would move
///       every assertion that counts the roster. The rack is a *screen*, and
///       what a screen shows is allowed to be a superset of what exists.
///
///       **It appears only while it has something in it.** Empty the drafts
///       and the card goes away by itself, so shipping is deleting rows rather
///       than remembering to hide a menu.
///       **And the same goes for the review card**, which is a stage in every
///       way the rack cares about and in no way `stage_list` does: it has no
///       waves, no boss, no clear and no line in the save. It sits before the
///       drafting table because the table is the one that reads as the end of
///       the rack, and both of them are one line to delete.
///
///       **The old draft of stage three goes first of the three**, on the same
///       terms: a stage to the run and not to the roster, kept while Mika's
///       fight is rebuilt and one line to delete afterwards. See
///       `stage_sanctum_old`.
function rack_list() {
    var _l = stage_list();
    array_push(_l, old_stage_sanctum_def());
    array_push(_l, preview_stage_def());
    if (array_length(draft_list()) > 0) array_push(_l, draft_stage_def());
    return _l;
}

/// @desc The drafting table, shaped exactly like a stage.
///
///       **`build` is `undefined` on purpose, so this is practice-only.** A
///       one-line timeline that put the boss on the field would work and would
///       be tempting -- but a run of a whole stage is the path that reaches
///       `progress_record`, and the one thing a scratchpad must never be able
///       to do is write to somebody's save. `id` is empty for the same reason
///       `practice_new`'s is, and the two guards agree: nothing here has a
///       stage to file a clear against.
///
///       `make_bg` is the brimstone stage's because it is the only background
///       the game has. When there is a second, this is the line that picks.
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

/// @desc How much health one draft slot is worth.
///
///       **The boss's health is derived from how many drafts there are**, so
///       every slot owns the same span of the bar whatever else is on the
///       table. That is the property worth having: an attack you tuned last
///       week must not get shorter because somebody added an idea underneath
///       it, and a draft has no fight around it to earn an uneven share of a
///       bar with.
///
///       The number itself is Ziggy's first non-spell, near enough -- 10% of
///       3400 -- so a draft takes about as long to break as the opening attack
///       of the only fight in the game. A draft that could not be broken at
///       all would only ever end on its clock, and "was that beatable" is half
///       of what anybody is asking.
#macro DRAFT_SLOT_HP 360

function draft_boss_def() {
    return {
        name: "THE UNNAMED",
        title: "a pattern in search of a caster",
        // Ziggy's art, and only his art. See the note at the top.
        sprite: spr_boss_ziggy,
        eye: spr_eye_ziggy,
        // Violet: a hue nothing on the brimstone stage fires, so the aura and
        // the sigil under a draft say "this is not Ziggy" before it has fired
        // anything. `boss_draw` tints only those two things, so borrowing the
        // sprite does not borrow the colour.
        col: BCOL_VIOLET,
        radius: 62,
        // **The generic circles, which is what they are for.** `SPELLBG_SIGIL`
        // survives as the fallback because it suits a caster with no place of
        // its own, and a draft is exactly that: Ziggy's forge is a *place*,
        // and lending it to somebody else's spell would say something about
        // the spell that is not true yet.
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

/// @desc Every unassigned attack, in whatever order they were had.
///
///       **A name makes it a spell.** That is the only difference between the
///       two kinds that a draft has to state: a named attack gets the banner,
///       the eye card, the wash and a taller notch, and an unnamed one opens
///       immediately with none of it. Writing `kind` and `bg` out as well
///       would be saying the same thing three times and getting it wrong once.
///
///       **The names are single**, as the rest of the game's are -- "Falling
///       Sky", not "Weight Sign -- Falling Sky". See the note in `CLAUDE.md`
///       about the two-part form.
///
///       **`move` is the one optional column**, and it is optional for the
///       same reason: an attack that says nothing about how its caster carries
///       itself gets the drift, which is right for nearly all of them. See
///       `BossMove` -- it is worth naming only when a pattern is actively
///       fighting the wander.
///
///       To add an idea: one row here and one function below it. Nothing else
///       in the game has to hear about it.
function draft_list() {
    return [
        { name: "",             col: BCOL_INDIGO,  time: 30 * FPS,
          attack: draft_scratch },

        { name: "Falling Sky",  col: BCOL_AZURE,   time: 40 * FPS,
          attack: draft_falling_sky },

        // **The only draft with nothing aimed in it**, so a moving origin
        // buys it nothing and costs it its symmetry: the rosette is measured
        // from wherever the boss happens to be, and a boss crossing the field
        // while it fires smears one figure into a comma.
        { name: "Seed & Bloom", col: BCOL_SPRING,  time: 40 * FPS,
          move: BossMove.Fixed, attack: draft_seed_and_bloom },

        { name: "Long Wake",    col: BCOL_CYAN,    time: 38 * FPS,
          attack: draft_long_wake },

        { name: "Second Sight", col: BCOL_MAGENTA, time: 42 * FPS,
          attack: draft_second_sight },

        // **The burster, which is a mechanic on the table rather than an
        // idea on it.** Every other row here is a pattern nobody has claimed;
        // this one is Mika's vocabulary, parked where it can be played before
        // any of his fifteen slots commits to it. `Close`, because he carries
        // the rings and a boss crossing the field drags the whole figure with
        // him. Moving it to a slot is moving the function; deleting this row
        // is all it takes to withdraw it.
        { name: "Sand Burst",   col: BCOL_GOLD,    time: 40 * FPS,
          move: BossMove.Close, attack: draft_sand_burst },
    ];
}

/// @desc The phase table the fight and the attack list both read.
///
///       **Everything but the row is computed**, which is what keeps adding a
///       draft down to one line: the kind and the background follow from
///       whether it is named, and the span of the bar is an equal share. It is
///       built fresh on every call for the reason `ziggy_phases` is -- a table
///       built once would be shared by every run that read it, and a phase
///       struct is mutable.
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
            // Optional in the row and written out here, so a phase struct is
            // the same shape whatever it came from. A row that says nothing
            // drifts, which is what `boss_move_kind` would have answered
            // anyway -- stating it costs nothing and means the table can be
            // read without knowing the default.
            move: _d[$ "move"] ?? BossMove.Drift,
            attack: _d.attack,
        });
    }
    return _out;
}

// ---------------------------------------------------------------------------
// What they do
//
// **These are seed content and they are meant to be thrown away.** What they
// are here for, besides giving the card something to hold on its first day, is
// that between them they use every verb the engine has and the shipped stage
// does not -- the Cartesian model, a split, a wake, a mid-flight change of
// graphic, a lifetime and a homing modifier. `CLAUDE.md` lists all of those
// under "engine and tested and unused", and a verb that has never been played
// is a verb nobody knows the feel of.
//
// So each one is a single idea, written the way a boss's attack is written: a
// function of the frames elapsed and nothing else.
// ---------------------------------------------------------------------------

/// @desc The blank page. **Copy this one.**
///
///       Deliberately the plainest thing in the file: an aimed fan on a beat
///       and a slow unaimed ring underneath it, which is the shape of every
///       non-spell in the game. It is here so that starting a new idea is
///       renaming a copy rather than remembering what the arguments are.
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

/// @desc **Falling Sky** -- shots that are thrown rather than fired.
///
///       The Cartesian half of the engine, which nothing in the game uses. A
///       force in a single axis has no polar expression at all: `dir` and
///       `spd` bend a path along its own direction, so a bullet that *falls*
///       cannot be written as a heading and a number. See `bullet_force`.
///
///       What it buys is a pattern whose threat arrives on a delay you can
///       see coming -- the lobs hang, and where they hang is where you must
///       not be in a second and a half.
function draft_falling_sky(_e, _g, _t) {
    if ((_t mod 26) == 0) {
        // Lobbed out to both sides, alternating, so the arcs cross.
        var _side = ((_t div 26) mod 2 == 0) ? 1 : -1;
        for (var _i = 0; _i < 3; _i++) {
            var _u = fire_xy(_e.x, _e.y,
                             _side * (3.4 + _i * 1.5), -4.6 - _i * 0.5,
                             BSHAPE_BALL, BCOL_AZURE, 16);
            // Gravity, capped, so a long fall does not end at a speed nobody
            // can read. The cap is what makes this a lob rather than a drop.
            bullet_force(_u, 0, 0.13, BQ_KEEP, 7.5);
        }
    }

    // A thin aimed line underneath, so the answer is not "stand at the bottom
    // and wait for them to land".
    if ((_t mod 96) == 60) {
        fire_stack(_e.x, _e.y, 3, 6.4, 1.3,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_NEEDLE, BCOL_CYAN, 20);
    }
}

/// @desc **Seed & Bloom** -- slow shots that burst where they stop.
///
///       A split: the parent dies and its children carry its shape and colour,
///       which is what makes a burst read as *that bullet* going off rather
///       than as one bullet vanishing and some unrelated ones appearing.
///
///       The idea being tried is that the dangerous moment is not where the
///       seed is but where it is *going to be*, and the seed travels slowly
///       enough to say so.
function draft_seed_and_bloom(_e, _g, _t) {
    if ((_t mod 34) == 0) {
        var _n = 6;
        for (var _i = 0; _i < _n; _i++) {
            var _u = fire(_e.x, _e.y, 3.2, _t * 2.6 + _i * (360 / _n),
                          BSHAPE_CRYSTAL, BCOL_SPRING, 14);
            // Far enough out to have travelled somewhere, soon enough that the
            // player is still watching it when it goes.
            bullet_split_at(_u, 62, 8, 4.4, _t * 1.3);
        }
    }
}

/// @desc **Long Wake** -- shots that leave a trail of themselves behind.
///
///       A shed rather than a split: the parent lives, so what is drawn is one
///       bullet with a history rather than a burst. Nothing in the game does
///       this and it is the cheapest way to get a curved wall out of straight
///       bullets.
///
///       `BULLET_QUEUE_MAX` is the ceiling on how long a wake can be, which is
///       a real limit and the reason this drops eight and not eighty.
function draft_long_wake(_e, _g, _t) {
    if ((_t mod 40) == 0) {
        var _n = 4;
        var _base = _t * 3.1;
        for (var _i = 0; _i < _n; _i++) {
            var _u = fire(_e.x, _e.y, 5.4, _base + _i * (360 / _n),
                          BSHAPE_MOTE, BCOL_CYAN, 14);
            // Turning as it goes, so the wake is laid down along an arc.
            bullet_turn_at(_u, 0, 1.5);
            // One pair shed sideways every six frames, eight times over: a
            // herringbone rather than a line, because a wake laid straight
            // behind a bullet is invisible from in front of it.
            bullet_shed_every(_u, 12, 6, 8, 2, 2.6, 90, 6);
            // **And it has to expire.** A bullet with a turn rate high enough
            // to orbit never leaves by geometry, and the pool refuses rather
            // than resizing -- so without this the later attacks on the table
            // quietly stop firing. See `bullet_expire_at`.
            bullet_expire_at(_u, 260);
        }
    }
}

/// @desc **Second Sight** -- shots that decide what they are halfway there.
///
///       Three verbs at once, and the point of the draft is whether the change
///       reads: a slow orb that turns into a fast dart, aims itself at the
///       player on the same frame, and is gone a few seconds later. The
///       hitbox follows the picture, because `bullet_table` decides both.
///
///       It is the one idea here that is about *timing* rather than about
///       shape, so it is the one most likely to be wrong -- which is what a
///       drafting table is for.
function draft_second_sight(_e, _g, _t) {
    if ((_t mod 18) == 0) {
        var _u = fire(_e.x, _e.y, 2.4, _t * 6.7, BSHAPE_BUBBLE, BCOL_MAGENTA,
                      14);
        // The turn is the tell: it becomes something with a point on it, and
        // then it looks at you.
        bullet_graphic_at(_u, 46, BSHAPE_DART, BCOL_ROSE);
        bullet_aim_at(_u, 46);
        bullet_move_at(_u, 46, 7.2);
        bullet_expire_at(_u, 220);
    }

    // A handful of slow hunters underneath, weakly homing and capped, so the
    // field has something in it that follows rather than something that was
    // aimed once. A bullet that turns as fast as it likes is unavoidable
    // rather than hard, which is where the cap comes from.
    if ((_t mod 74) == 30) {
        for (var _i = -1; _i <= 1; _i++) {
            var _h = fire(_e.x, _e.y, 3.4,
                          aim_at(_e.x, _e.y, _g.player.x, _g.player.y)
                          + _i * 36,
                          BSHAPE_BUTTERFLY, BCOL_VIOLET, 22);
            if (_h != undefined) {
                _h.bmod = BMod.Home;
                _h.mod_a = 0.9;      // degrees a frame, and that is plenty
            }
            bullet_expire_at(_h, 300);
        }
    }
}

// ---------------------------------------------------------------------------
// Sand Burst -- the two-stage throw
//
// **What this is on the table for**: the mill's storm is uniform by
// construction and there is nothing in it for the eye to follow, which is the
// complaint it was built under. A carrier is sparse and slow enough to be
// tracked individually, and what it leaves when it breaks is the same sand.
// Two layers, two jobs: the carriers are the figure and the sand is the
// micrododge.
//
// **The sand itself is `mika_nonspells`' and nothing here reimplements it** --
// this file supplies the rings, the beat and the arms, and `mika_sand_burst`
// supplies the throw. What is deliberately *not* borrowed is the mill's own
// numbers: the beat is five times longer and there are two arms rather than
// six, because a carrier is meant to be counted and a grain is not.
// ---------------------------------------------------------------------------

#macro DRAFT_BURST_RINGS 2
#macro DRAFT_BURST_DIST 205
#macro DRAFT_BURST_ORBIT 1.5
#macro DRAFT_BURST_SPIN (DRAFT_BURST_ORBIT * 1.5)
#macro DRAFT_BURST_ARMS 2
#macro DRAFT_BURST_BEAT 34
#macro DRAFT_BURST_LEAN 12

/// @desc The mill's rim routine one layer up: which cycle of sand this ring's
///       carriers break into. Bound rather than written onto the ring, for
///       `mika_n1_ring_for`'s reason -- a ring is a pooled struct and a field
///       bolted onto one is a field its next occupant inherits.
function draft_burst_rim_for(_cycle) {
    return method({ cycle: _cycle }, function(_ring, _g, _t) {
        draft_burst_rim(_ring, _g, _t, cycle);
    });
}

/// @desc What one ring does: two carriers off opposite sides of its metal,
///       every `DRAFT_BURST_BEAT` frames.
function draft_burst_rim(_ring, _g, _t, _cycle) {
    if ((_t mod DRAFT_BURST_BEAT) != 0) return;

    var _sign = (_ring.spin >= 0) ? 1 : -1;
    var _volley = _t div DRAFT_BURST_BEAT;

    for (var _i = 0; _i < DRAFT_BURST_ARMS; _i++) {
        // The metal as it will stand when the mark goes live, and a lean
        // with the spin -- both on `ring_rim_at_x`'s reasoning. The lean is
        // half the mill's, because a carrier is a lob rather than a fling and
        // a strongly slanted one reads as having been thrown past the player
        // rather than at them.
        var _at = _ring.ang + _ring.spin * MIKA_SAND_DELAY
                  + _i * (360 / DRAFT_BURST_ARMS);
        var _dir = _at + DRAFT_BURST_LEAN * _sign;

        // Per arm: a spray is a colour, as the mill's wake points are.
        mika_sand_burst(_ring, _at, _dir, mika_sand_grade(_cycle, _i),
                        MIKA_CARRY_HOLD,
                        MIKA_SAND_BRAKE, MIKA_SAND_FLOOR,
                        MIKA_SAND_CURL * _sign, MIKA_SAND_BEND,
                        MIKA_SAND_LIFE);
    }
}

/// @desc **Sand Burst.** Two rings riding him, throwing carriers that break
///       into sand. He fires nothing himself, on the mill's reasoning: the
///       rings are the thing to watch.
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
