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
function rack_list() {
    var _l = stage_list();
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

        // **The attack that wanted `BossMove` to exist.** The player spends
        // most of it walled into a ward drawn round them, so they cannot go to
        // the boss and the boss has to come to them or the attack has no
        // answer but its clock. Loose rather than fixed, because every volley
        // fired into the cell is aimed and a caster parked overhead would fire
        // all of them straight down.
        // **The clock is three passes of `HEX_CYCLE` and a little.** It is
        // the only row here whose time is derived from anything: the attack is
        // `_t mod` a cycle of seventeen and a half seconds, so a clock that
        // does not divide by one cuts the last pass off in the middle of a
        // movement -- most likely before the collapse, which is the half of
        // the attack worth reaching. It went up with the cycle rather than
        // staying at forty-eight for that reason and no other.
        { name: "Demon Sealing Hex", col: BCOL_CRIMSON, time: 53 * FPS,
          move: BossMove.Track, attack: draft_demon_sealing_hex },
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
// Demon Sealing Hex
//
// **The first draft here that is a piece of theatre rather than a verb.** The
// five above it each exist to make one engine feature playable; this one
// exists to find out whether the engine can hold a *composed* attack -- four
// movements that answer each other, with the shape on screen meaning something
// for a whole minute rather than for the second a bullet takes to cross.
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
/// `_t mod` it, so the clock in `draft_list` decides how many times round the
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
///       declared in `obj_boot` and would outlive the draft, and a field
///       bolted onto the boss or onto the phase table would be writing state
///       into somebody else's data. Nothing reads it before the frame that
///       writes it, so it does not matter what it holds between runs.
function draft_demon_sealing_hex(_e, _g, _t) {
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
