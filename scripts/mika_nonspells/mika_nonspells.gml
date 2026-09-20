/// @desc Mika's non-spells: the seven breathers, and the sand they are made
/// of.
///
/// **What was asked for**, in the owner's words: his regular attacks are
/// "small/sandy bullets continuously spraying in pretty patterns -- brewing
/// sandstorms with magnetism -- from his rings as they spin, which shoot out
/// quickly and then rapidly decelerate to a slower speed then drift in a
/// deterministic pattern". The seven are variations of each other and they are
/// the basic attacks between his spells. See "Mika's fifteen" in `CLAUDE.md`.
///
/// So there is one grain in this file and every non-spell throws it. A grain
/// leaves the metal fast, brakes hard, and settles at a crawl it then keeps
/// for the rest of its life -- and the moment it settles it starts to turn, at
/// a fixed rate, for ever. That is the whole of `mika_sand`, and the three
/// phases are three readings: a streak, a stall, and a drift.
///
/// **The settle is a clamp, not a schedule.** `spd_min` is a field on the
/// bullet and `bullet_step` clamps against it every frame, so "brake to the
/// floor and stay there" costs no queue entry and cannot overshoot into flying
/// backwards, which is what a bare negative acceleration does. What *is*
/// scheduled is the turn, on the one frame the grain reaches its floor --
/// `mika_sand_settle` works out which frame that is, so the drift starts when
/// the stall ends rather than at some number somebody tuned separately.
///
/// **The drift is a constant turn and that is the magnetism.** A fixed number
/// of degrees a frame bends a fast bullet hardly at all and a slow one much
/// harder, so one rule gives the streak a straight throw and the settled grain
/// a long curve -- and every grain from one ring turns the way that ring
/// turns, so the storm builds into bands that wind with the metal that threw
/// them. Nothing in it is random: the same attempt draws the same storm, which
/// is the difference between a pattern somebody can learn and noise they can
/// only survive.
///
/// **And the turn ends.** A grain bends for `MIKA_SAND_BEND` degrees and then
/// holds the heading it has reached, because a turn that never stops is a
/// circle: left to it, the storm arrived at the foot of the field travelling
/// sideways across the player instead of down at them. What a capped bend
/// draws is a stream that curves and then runs true, which is a shape rather
/// than a swirl.
///
/// **The curl has to stay small, and the first pass got that badly wrong.** A
/// settled grain travels a circle of radius `speed / turn`, and at 0.9 degrees
/// a frame on a floor of 1.4 that circle was ninety pixels across -- so every
/// grain of an arm closed a loop, and because they are laid down continuously
/// along one path they closed the *same* loop. What it photographed as was a
/// string of pearls looped over itself: pretty, and nothing whatever to do
/// with sand. A third of that turn on nearly twice the speed is an arc four
/// hundred pixels across, which within a grain's life is a sweep rather than
/// a circuit.
///
/// **And the floor is a drift, not a stall.** At 1.4 a grain crossed the field
/// in ten seconds, so the storm hung where it was thrown and the bottom of the
/// field -- where the player lives -- stayed empty. It also meant nothing ever
/// left by geometry, so every grain in the attack was waiting on its expiry.
///
/// **All of it is still being tuned.** How much sand there is and how slowly
/// it falls are `MIKA_MILL_BEAT`, `MIKA_MILL_WAKE` and `MIKA_SAND_FLOOR`; how the
/// rings behave is the `MIKA_MILL_WIND`/`MIKA_MILL_ORBIT` group. None of those
/// numbers is settled.

// ---------------------------------------------------------------------------
// The grain
// ---------------------------------------------------------------------------

// A grain is born as a mark like everything else. Shorter than the default,
// because at this rate the marks *are* the shimmer coming off the ring and a
// long one would put a second ghost storm over the real one.
#macro MIKA_SAND_DELAY 6

// The grain: the bulk of the storm. Fast out of the metal, hard on the brake,
// and a drift afterwards.
#macro MIKA_SAND_SPD 10.5

// **How long it runs before it brakes at all**, which is the phase the first
// three passes did not have. Braking from the frame it is fired makes the
// throw and the settle one movement about fifteen frames long, and what that
// reads as is a bullet that was fired slowly -- reported as the deceleration
// coming too soon, with the ask that the brake and the drift be noticeable
// phases. Held at its launch speed for a fifth of a second first, a grain
// covers nearly two hundred pixels as a streak, and the brake that follows is
// something the eye catches happening.
#macro MIKA_SAND_HOLD 18
#macro MIKA_SAND_BRAKE 0.55

// What the grain settles to. Slow -- the storm is meant to be flown through
// rather than to pass by -- but not a stall: sand that crawls never leaves,
// so the field stops being a storm and becomes a fog that only thickens.
#macro MIKA_SAND_FLOOR 2.0
#macro MIKA_SAND_CURL 0.32
#macro MIKA_SAND_BEND 46           // degrees of drift, and then it holds


// **A backstop rather than a lifetime.** A grain used to be turning for ever,
// so nothing but the expiry took it off the field and the number had to be
// short enough to keep the pool sane -- which killed the sand somewhere around
// the middle of the field, in front of a player who was waiting for it.
// Reported as the bullets despawning before they reach the bottom of the
// screen. Now that the bend ends, a grain runs true and leaves by geometry
// like everything else in the game, and this is only here to catch the one
// that happens to run parallel to a wall.
#macro MIKA_SAND_LIFE 1500

// **The cycle: one shape per ring, one colour per wake point.**
//
// Each ring throws one shape for the whole attack -- glints off one, grains
// off the other -- so the two storms are told apart by silhouette, which
// survives any distance and any background. The colour is the wake point's, so
// a comet, the trail it drops and the sand it breaks into are all one hue and
// read as one object.
//
// Only the picture changes down a cycle; every grain travels the same path.
// The scale is the one exception and it is the drawn size only --
// `mika_sand_dress` takes the hitbox down with it, so a mote is never bigger
// than it kills.
#macro MIKA_SAND_GRADES 3

/// @desc The table: one cycle per ring that throws sand.
///
///       Returned rather than restated anywhere, so how many cycles there are
///       is `array_length` of the thing itself and a third ring on a later
///       non-spell is a third row and nothing else.
function mika_sand_cycles() {
    static _cycles = [
        // Ring 0 throws nothing but glints, and runs the heat up.
        [ { shape: BSHAPE_MOTE, col: BCOL_EMBER, scale: 0.80 },
          { shape: BSHAPE_MOTE, col: BCOL_AMBER, scale: 0.80 },
          { shape: BSHAPE_MOTE, col: BCOL_BONE,  scale: 0.80 } ],

        // Ring 1 throws nothing but grains, through the same three.
        [ { shape: BSHAPE_PELLET, col: BCOL_EMBER, scale: 0.68 },
          { shape: BSHAPE_PELLET, col: BCOL_AMBER, scale: 0.68 },
          { shape: BSHAPE_PELLET, col: BCOL_BONE,  scale: 0.68 } ],
    ];
    return _cycles;
}

/// @desc What step `_i` of cycle `_cycle` throws: its shape, its hue and the
///       size it is drawn at. Both indices wrap, so a ring beyond the table
///       borrows a cycle rather than raising.
function mika_sand_grade(_cycle, _i) {
    var _all = mika_sand_cycles();
    var _c = _all[_cycle mod array_length(_all)];
    return _c[_i mod array_length(_c)];
}

/// @desc The frame a grain launched at `_spd` reaches `_floor`.
///
///       `bullet_step` applies the acceleration before it moves, so the speed
///       after one step is already `_spd - _brake`; the ceiling is what makes
///       the turn start on the first frame the clamp is holding rather than
///       the last frame it is not.
function mika_sand_settle(_spd, _brake, _floor) {
    return ceil((_spd - _floor) / max(0.0001, _brake));
}

/// @desc One grain, leaving the metal at `_at` degrees round the band and
///       travelling `_dir`, then left to settle.
///
///       **Where it leaves from and which way it goes are two angles**, which
///       is the whole of the lean: a grain thrown off a turning ring leaves
///       one point of the metal and travels off at a slant to it. Passing one
///       angle for both -- which the first version did -- is a dead radial
///       throw from a rotated point, and reads as a sprinkler however far the
///       "lean" is turned up.
///
///       Fired from the rim rather than from the centre, on `ring_fire_rim`'s
///       rule: the ring is what is throwing it, so it has to leave the metal.
///       Written by hand here rather than through that helper because every
///       grain needs its brake, its floor and its curl, and none of those is
///       something the helpers in `ring_functions` can be told.
function mika_sand(_ring, _at, _dir, _spd, _hold, _brake, _floor, _curl,
                   _bend, _life, _look) {
    // **Where the metal is going to be, not where it is.** A grain is born as
    // a mark that holds still for its delay, and the ring is orbiting at six
    // pixels a frame -- so fired at the rim as it stands, the mark is inside
    // the hole by the time it goes live. See `ring_rim_at_x`.
    var _u = fire(ring_rim_at_x(_ring, _at, MIKA_SAND_DELAY),
                  ring_rim_at_y(_ring, _at, MIKA_SAND_DELAY), _spd, _dir,
                  _look.shape, _look.col, MIKA_SAND_DELAY);
    return mika_sand_dress(_u, _look, _hold, _brake, _floor, _curl, _bend,
                           _life);
}

/// @desc Make an already-fired bullet into a grain of sand: give it the look,
///       and give it the streak, the brake and the drift.
///
///       **Split out of `mika_sand` so that a bullet nobody fired from a rim
///       can be sand too.** A burst child is created inside `bullet_step` and
///       handed to a dress method -- see `bullet_spawn_children` -- so the one
///       thing it cannot be is fired by the pattern that wants it. Everything
///       below the muzzle is the same for both, and having it in two places
///       would mean the settle arithmetic drifting apart between a grain that
///       was thrown and a grain that was shed.
///
///       **It takes the bullet's own speed rather than being told one**, which
///       is what makes it work for both callers: a thrown grain is going
///       `MIKA_SAND_SPD` and a burst child is going whatever the burst threw it
///       at, and the frame each reaches the floor is a different frame. Told a
///       speed instead, a burst child would start its drift at the frame a
///       thrown grain would have -- early or late, and by a lot.
///
///       Takes `undefined` and answers it, because `fire` refuses past
///       `BULLET_MAX` and a burst into a full pool dresses nothing.
function mika_sand_dress(_u, _look, _hold, _brake, _floor, _curl, _bend,
                         _life) {
    if (_u == undefined) return undefined;

    // **A grain is a bullet drawn small, and the hitbox goes with it.**
    // `scale` is the picture and `r` is what the collision reads, and the
    // smallest shape in the set is still a thirty-pixel bead at this size --
    // which photographs as a string of beads rather than as sand. Shrinking
    // one without the other is the one thing that may not happen here: the
    // hitbox is the truth the player is shown, and a grain drawn smaller than
    // it kills would be the game lying sixty times a second.
    //
    // Set from the table rather than scaled off what the bullet already is,
    // because a burst child is born wearing its *parent's* graphic -- so there
    // is a shape to change here and not only a size.
    _u.shape = _look.shape;
    _u.col = _look.col;
    _u.scale = _look.scale;
    _u.r = global.bshape_radius[_look.shape] * _look.scale;
    _u.spin = global.bshape_spin[_look.shape];

    // **Two phases: the brake and the drift.** It flies at whatever speed it
    // was given for `_hold` frames before the brake is applied at all --
    // `bullet_accel_at` sets the deceleration *and* the floor it may not go
    // under, which is the clamp the settle is made of. See the note at the
    // top.
    _u.acc = 0;
    bullet_accel_at(_u, _hold, -_brake, _floor);

    // ...and the drift, from the frame it gets there -- for `_bend` degrees,
    // and then it holds the heading it has arrived at.
    //
    // **A turn that never stops is a circle, which is what the first pass
    // shipped.** Left turning for its whole life a grain kept bending past the
    // direction it was thrown in, so by the time the storm reached the foot of
    // the field it was travelling sideways across the player rather than down
    // at them -- reported in those terms. Capping the total turn makes the
    // drift a *bend*: the grain leans onto a new heading and then runs true,
    // so a stream reads as one curve rather than as a spiral that never
    // resolves.
    var _settle = _hold + mika_sand_settle(_u.spd, _brake, _floor);

    bullet_turn_at(_u, _settle, _curl);
    if (_bend > 0 && _curl != 0) {
        bullet_turn_at(_u, _settle + ceil(_bend / abs(_curl)), 0);
    }

    // **And it has to go out.** A grain at a crawl with a turn on it orbits
    // rather than leaving, and the pool is a refusal rather than a resize --
    // so without this the storm fills it and every later attack in the fight
    // quietly stops firing. It fades, which is a courtesy to the eye and
    // never a window in which a ghost can land a hit.
    bullet_expire_at(_u, _life);
    return _u;
}

// ---------------------------------------------------------------------------
// The burster: a carrier that breaks into sand
//
// **Not used by any attack yet.** It is the second thing a ring can throw, and
// it is here because the engine change it needs is done and the vocabulary
// belongs beside the grain rather than in whichever non-spell reaches for it
// first. Nothing in `mika_slots` calls it.
//
// **What it is for**, and it is the one thing the mill cannot do: the mill's
// storm is uniform by construction -- grains leave continuously and settle
// into an even field, which is what a sandstorm is and is also why there is
// nothing in it for the eye to track. A carrier is sparse, slow and large
// enough to be watched individually, and what it leaves behind when it breaks
// is the same sand the mill throws. So the two layers answer different
// questions: the carriers are the figure, the sand is the micrododge. That is
// Touhou 13's shape for a non-spell and it is why it was asked for.
//
// **The burst is a real `bullet_split_at` and not a computed bloom**, which it
// could not have been a day ago. `bullet_spawn_children` threw `fire`'s answer
// away, so a child could only fly straight in its parent's colours for ever --
// which is not sand and cannot be made into sand. It takes a dress method now,
// on ph3's own terms: everything `ObjShot_AddShotA1` lets you do to a shot
// object before registering it, this does to the child at the moment it is
// born. See `bullet_spawn_children`.
//
// The alternative was to compute where the carrier would be and fire a rosette
// from that point on the right frame -- the technique `Demon Sealing Hex` is
// built on, because a bullet cannot be found again. It works, and it is worse:
// the carrier and the bloom would be two independent things that agree only as
// long as nobody retunes either, so a carrier that braked or was nudged would
// leave its own bloom behind. A split cannot come apart from its parent.
// ---------------------------------------------------------------------------

// The carrier. Big, slow and bright: it has to be trackable across the field
// by eye, which is the whole of its job, and it is the one thing on this
// field that is allowed to be read individually.
#macro MIKA_CARRY_SHAPE BSHAPE_SPHERE
#macro MIKA_CARRY_COL BCOL_GOLD
#macro MIKA_CARRY_SPD 4.6
#macro MIKA_CARRY_AT 44            // frames from going live to the break
#macro MIKA_CARRY_N 9              // grains it breaks into
#macro MIKA_CARRY_OUT 3.8          // how fast they leave the break

// **A shorter hold than a thrown grain gets.** A grain off the metal streaks
// for eighteen frames because the streak is what says it was flung; a burst
// child is already where it is going to be, so what its hold buys is only that
// the bloom opens before it settles. Long, it is a second volley fired from
// mid-field and the carrier stops reading as the thing that broke.
#macro MIKA_CARRY_HOLD 7

/// @desc A carrier off `_ring`'s metal at `_at` degrees, travelling `_dir`,
///       which breaks into `MIKA_CARRY_N` grains of `_look` sand.
///
///       **The dress method is the whole point and it is bound, not global.**
///       It closes over this carrier's own sand -- its look, its brake, its
///       floor, its curl -- so two carriers in the air at once can break into
///       two different kinds of sand, which is what lets the burster take the
///       per-ring cycle the mill already has. A single shared configuration
///       would have made the burst's sand a property of the file rather than
///       of the shot, and a later non-spell would have had to fight it.
///
///       Fired from the rim on `mika_sand`'s rule, and led over the delay for
///       `ring_rim_at_x`'s reason: a moving ring's metal is somewhere else by
///       the time a mark goes live.
function mika_sand_burst(_ring, _at, _dir, _look, _hold, _brake, _floor,
                         _curl, _bend, _life) {
    var _u = fire(ring_rim_at_x(_ring, _at, MIKA_SAND_DELAY),
                  ring_rim_at_y(_ring, _at, MIKA_SAND_DELAY),
                  MIKA_CARRY_SPD, _dir, MIKA_CARRY_SHAPE, MIKA_CARRY_COL,
                  MIKA_SAND_DELAY);
    if (_u == undefined) return undefined;

    // **`flr` and not `floor`, and that is not a style choice.** A bound
    // method's fields are read as bare identifiers, and GML resolves a
    // built-in function name before a struct member -- so `floor` inside this
    // body is the *rounding function*, not the number beside it. It compiles,
    // it runs, and what it hands `bullet_accel_at` is a function reference:
    // `min(spd, <function>)` answers the speed, so `spd_min` came out at the
    // burst speed and every grain of the bloom was clamped at the speed it was
    // born with and could never brake. It is the `score` trap exactly -- a
    // built-in name quietly winning -- and nothing in the build or the checks
    // can see it, because a reference to `floor` is a legal expression.
    bullet_split_at(_u, MIKA_CARRY_AT, MIKA_CARRY_N, MIKA_CARRY_OUT, 0,
                    method({ look: _look, hold: _hold, brake: _brake,
                             flr: _floor, curl: _curl, bend: _bend,
                             life: _life },
                           function(_c, _k) {
        // `_k` is the child's index round the burst. Unused here -- the bloom
        // is symmetric on purpose, because an asymmetric one read against a
        // field of even sand is noise rather than a figure -- and it is passed
        // so that a later attack can grade a burst the way an arm is graded.
        mika_sand_dress(_c, look, hold, brake, flr, curl, bend, life);
    }));
    return _u;
}

// ---------------------------------------------------------------------------
// N1 -- the mill
//
// **Two rings and nothing else: Mika fires not one bullet in this attack.**
// That is the brief for his opener and it is also what makes the rings read as
// the thing to watch -- the storm has one source and it is the furniture, not
// the caster. He is still there to be shot at, which is the other half of why
// it works as a breather: the answer is to stand where the metal is not and
// hold the trigger down.
//
// **The rings come out of him and wind up.** They form on top of him at no
// radius at all, extend out to `MIKA_MILL_DIST` while the orbit builds from a
// standstill, and the sand opens on the frame they reach full speed. Nothing
// is fired before that, so the spin-up costs the pattern nothing.
//
// **The sand is kicked up in the rings' wake, not sprayed out of them.** Each
// ring throws from the point of its rim it has just come past -- the trailing
// edge -- outward from Mika and swept back against its travel, so it is left
// behind rather than fired ahead. The rings whip round him and a storm winds
// out of where they have been.
//
// **One stream per ring, and that is what makes it a figure.** Six arms round
// the circumference put sand at every bearing at once, and the drift then
// smeared each of them across most of the gap to its neighbour, so what
// accumulated was an even scatter however tidy a single volley was. Two
// streams half a turn apart, laid down continuously, stay two streams: a
// two-armed spiral winding out of him.
//
// **And a stream starts coarse and ends fine.** What leaves the metal is a
// medium ball; it brakes, and as it settles it breaks into pellets that drift.
// So a stream is a line of beads near the rings and a cloud of sand further
// out, which is how the storm gets to look thick without being a wall.
// ---------------------------------------------------------------------------

#macro MIKA_MILL_RINGS 2

// How far out the two ride once they are up to speed. Closer in than
// `MIKA_ORBIT`, which is where the placeholder attacks still put their
// formations: at three hundred they orbited out near the walls and read as
// furniture he happens to be standing between. In at two hundred they are
// bands he is wearing.
#macro MIKA_MILL_DIST 205

// **Which way round him the rings run is the slot's, not the mill's.** It is
// `+1` or `-1` and it turns the whole gesture over at once: the orbit, the rim
// the sand leaves from, the lean on the throw and the way the drift bends. One
// number, because a mill with any two of those disagreeing is a mill throwing
// sand into its own wake.

// ---- the wind-up ----------------------------------------------------------

// Frames from a standstill to full speed, and how the ramp is shaped: above 1
// keeps it slow early and quick late, so the rings creep out of him and then
// whip. One factor drives the orbit *and* the metal's own rotation, so the two
// are locked through the whole of it.
//
// **It ramps up to the working speed and stops there.** An overshoot that
// settled back afterwards read as the rings slowing down at the exact moment
// the sand started, which is the opposite of what the spin-up is for.
#macro MIKA_MILL_WIND 100
#macro MIKA_MILL_WIND_POW 2.4

// Working speed: degrees a frame the rings walk round him. The orbit is what
// draws the figure -- sand leaves the trailing rim and the rim moves on -- so
// it has to outrun its own sand rather than hold still for it. At this rate
// the metal travels about six times what a settled grain does, and a lap takes
// under three seconds.
//
// **There is no separate spin.** A ring's own rotation used to be a rate of
// its own, which was doing something when the emission point was a bearing on
// the metal; the wake is measured against the ring's travel now, so the
// rotation was free. Tied to the orbit instead, the ring is carried round him
// rigidly -- the same point of the chain faces him the whole way -- and it
// still winds up during the spin-up, because the orbit does.
#macro MIKA_MILL_ORBIT 2.1

// ---- the wake -------------------------------------------------------------

// Streams per ring, and how many degrees of rim their muzzles are spread
// over. Two off each ring is four ribbons on the field; the rings being half a
// turn apart makes the whole figure two-fold.
//
// **Spread, not clustered.** Two muzzles a few degrees apart are one thick
// ribbon rather than two, and because every stream bends at the same rate they
// stay parallel rather than smearing into each other.
#macro MIKA_MILL_WAKE 2
#macro MIKA_MILL_WAKE_ARC 56

// How far the throw is turned off the rim it leaves, toward straight out from
// Mika.
//
// **A bead leaves radially from the *ring*, not from him**, which is the whole
// of the wake and is what the first pass got wrong: aimed out from Mika with a
// sweep-back, the streams were about fifty degrees too far out and sprayed
// across the field instead of wrapping round him -- reported in those terms.
// Off a muzzle on the trailing rim, radially-out-from-the-ring already points
// backward along the orbit, so the sand is left behind by construction and
// this is only a small bias on top of it.
#macro MIKA_MILL_LEAN 10

// Frames between one bead of a stream and the next. Short, because this is a
// stream and not a volley: what sets it is how far the muzzle has swung by the
// time the next bead leaves, and much more than a few degrees reads as a gap
// rather than as a spray. At this beat it is about six.
#macro MIKA_MILL_BEAT 3

// **How far ahead the throw is aimed, in frames.** A bead is born as a mark
// that holds still for `MIKA_SAND_DELAY` frames, and the ring turns about two
// degrees a frame -- so an angle worked out on the frame it is asked for is
// thirteen degrees behind the metal by the time the bead actually leaves.
// `ring_rim_at_x` already leads the *muzzle*; this is the same lead applied to
// the bearing and the throw, which is the half of it that shows.
#macro MIKA_MILL_LEAD MIKA_SAND_DELAY

// ---- the shape of a mill --------------------------------------------------
//
// **How many rings there are, how far out they ride and how much each throws
// is the slot's, not the file's.** The seven non-spells are variations of each
// other, and the first axis anybody reaches for is the number of rings -- so
// the count cannot be a macro that every mill shares. What stays a macro is
// everything a variation does *not* touch: the grain, the wind-up, the lean,
// the lead, and the bead's whole life. A mill that changed those would not be
// a variation of this pattern, it would be a different one.
//
// The four numbers that do vary are one struct, bound into a ring's `act` at
// spawn, so nothing is allocated per frame and no ring can be reading a
// different mill's numbers from the ring beside it.

/// @desc The shape of one mill, filled in from `_spec`.
///
///       **A struct rather than a row of arguments, and that is this project's
///       own scar.** Four `wave_cross` calls once passed eight arguments to a
///       function taking nine and GameMaker compiled every one of them, which
///       is what `check_call_arity` exists for. A mill is up to nine numbers
///       now and most mills want the default for most of them, so what a
///       fourth mill writes down is the handful it actually differs in.
///
///       - `rings`, `dist`, `orbit`, `beat` -- required, and the four a
///         variation has always been about.
///       - `wake`, `arc` -- streams per ring and the rim they are spread over.
///       - `motes`, `flr` -- how many pellets a bead breaks into and how fast
///         they settle. The grain's own character otherwise stays shared.
///       - `rock` -- true for an orbit that reverses on his hops. False, and
///         the mill turns one way for ever, which is what three of the four
///         do. There is no period beside it: the period *is* the hop.
///       - `bolt` -- true if every ring throws an aimed beam at each reversal.
///         Only a rocking mill has reversals, so only a rocking mill can.
///
///       **`flr` and not `floor`**, on the trap `mika_sand_burst` records: a
///       built-in name wins over a struct member read bare, and there is no
///       reason to leave a live mine in a field name.
///
///       **The orbit is in here and the wind-up is not**, which is the split
///       that matters once a mill's radius can change. How the rings get up to
///       speed is the gesture and is shared; how fast they end up going has to
///       move with the radius, because both of the things the orbit is
///       answerable for are *linear* rather than angular -- see
///       `mika_mill_bead_gap`.
function mika_mill_shape(_spec) {
    return {
        rings: _spec.rings,
        dist: _spec.dist,
        orbit: _spec.orbit,
        beat: _spec.beat,
        wake: _spec[$ "wake"] ?? 1,
        arc: _spec[$ "arc"] ?? MIKA_MILL_WAKE_ARC,
        motes: _spec[$ "motes"] ?? MIKA_MILL_MOTES,
        flr: _spec[$ "flr"] ?? MIKA_SAND_FLOOR,
        rock: _spec[$ "rock"] ?? false,
        bolt: _spec[$ "bolt"] ?? false,
    };
}

/// @desc How fast a mill throws the pellets a bead breaks into.
///
///       **Derived from the floor rather than set beside it**, because a floor
///       above the speed the pellet is launched at is *silently ignored*:
///       `BQ.Accel` takes `min(spd, floor)` so that a bullet can never be
///       accelerated by a brake, which is right and which means a mill that
///       raised its floor past `MIKA_MILL_MOTE_SPD` would quietly get the old
///       floor back with nothing to say so. One rule removes the coupling
///       instead of a second number that has to be remembered.
function mika_mill_mote_spd(_mill) {
    return max(MIKA_MILL_MOTE_SPD, _mill.flr * MIKA_MILL_MOTE_LEAD);
}

/// @desc How far apart along its own track a mill lays consecutive beads of
///       one stream, in pixels.
///
///       **This is the number the beat is really set by, and at one radius it
///       was indistinguishable from the one that is written down.** The mill's
///       own note says the beat is set by how far the muzzle has swung between
///       beads and that much more than a few degrees reads as a gap rather
///       than as a spray -- which was true and is only half the statement,
///       because it was written when every mill rode at `MIKA_MILL_DIST` and
///       degrees and pixels were the same sentence. They are not: a ring half
///       again as far out covers half again as much ground in the same six
///       degrees, and what the eye reads is the distance between one bead and
///       the next, not the angle between them.
///
///       So a bigger mill has to slow its orbit rather than keep it, and this
///       is what any two mills are held level against.
function mika_mill_bead_gap(_mill) {
    return _mill.dist * _mill.orbit * _mill.beat * pi / 180;
}

/// @desc How fast a mill's metal travels along its own track, in pixels a
///       frame. The other thing the orbit answers for: a wake only reads if
///       the metal outruns the sand it is leaving, which is a race in pixels
///       against `MIKA_SAND_FLOOR` and not in degrees against anything.
function mika_mill_rim_spd(_mill) {
    return _mill.dist * _mill.orbit * pi / 180;
}

/// @desc N1 and N2's mill: two rings, half a turn apart, two streams each.
function mika_mill_pair() {
    return mika_mill_shape({ rings: MIKA_MILL_RINGS, dist: MIKA_MILL_DIST,
                             orbit: MIKA_MILL_ORBIT, beat: MIKA_MILL_BEAT,
                             wake: MIKA_MILL_WAKE, arc: MIKA_MILL_WAKE_ARC });
}

// ---- the bead -------------------------------------------------------------

// **Medium-small.** It only has to be bigger than the sand it breaks into --
// a bead the player can see individually, not an obstacle in its own right.
#macro MIKA_MILL_HEAD_SHAPE BSHAPE_ORB
#macro MIKA_MILL_HEAD_SCALE 1.0
// **The floor is zero, and that is the beat.** Braking to a crawl and coasting
// read as one long slow phase rather than as an arrival -- the brake and the
// break ran into each other and what was between them was just a slower
// bullet, reported twice as the bead coasting. Nothing is a clearer arrival
// than a standstill: it streaks out, runs down to nothing, hangs, and bursts.
// Zero is a clamp like any other floor, so it cannot overshoot into travelling
// backwards.
//
// **These three are one trade and any two of them fix the third**: how fast it
// leaves, how long the brake takes, and how far out it stops. A brake that is
// over in a dozen frames is not a deceleration, it is an impact; a gradual one
// from a slow launch is a bullet that was never going anywhere; and a gradual
// one from a fast launch stops most of the way to the wall, which is the
// spray-across-the-field the figure was tightened to get rid of.
//
// What is here leans on the launch: fast out, a third of a second of visible
// slowing, and it comes to rest about a hundred and eighty pixels off the
// metal. Dropping the launch speed instead was tried first and it is the wrong
// lever -- it buys the same stopping distance by making the thing that is
// supposed to be slowing down slower to begin with, so there is less to see.
#macro MIKA_MILL_HEAD_SPD 13.5
#macro MIKA_MILL_HEAD_HOLD 3         // frames at launch speed before braking
#macro MIKA_MILL_HEAD_BRAKE 0.65
#macro MIKA_MILL_HEAD_FLOOR 0

// The break: how long it hangs first, how many pellets, how fast they leave,
// and where round the bead they go.
//
// **How long it hangs at a standstill before it breaks**, counted from the
// frame it stops rather than from the frame it was fired -- so retuning the
// brake moves the whole of the bead's life together instead of eating the
// hang.
//
// Short, because a standstill is read the instant it happens: fourteen frames
// of it was reported as jarring, and what a pause this length has to do is
// separate the arrival from the burst rather than be a phase of its own. The
// slowing is what carries the beat now.
#macro MIKA_MILL_HANG 8
#macro MIKA_MILL_MOTES 3
#macro MIKA_MILL_MOTE_SPD 3.2
#macro MIKA_MILL_MOTE_OFF 0          // one carries on down the stream

// How far above a mill's own settle floor a pellet is launched, when that
// floor is high enough to matter. See `mika_mill_mote_spd`: a brake may never
// become an accelerator, so a pellet born slower than the floor it asks for
// keeps the speed it was born with instead.
#macro MIKA_MILL_MOTE_LEAD 1.3
#macro MIKA_MILL_MOTE_HOLD 6

/// @desc The wind-up factor at frame `_t`: 0 at rest, 1 at working speed, and
///       1 for ever after.
function mika_mill_wind(_t) {
    if (_t >= MIKA_MILL_WIND) return 1;
    return power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW);
}

/// @desc How far round him a ring has walked by frame `_t`, in degrees -- the
///       integral of the mill's rate.
///
///       Closed form, so a ring's position is a function of the frame and
///       nothing has to be carried between frames or reset between attempts.
///       **That is what lets the orbit reverse at all**: a swinging mill is
///       still a function of `_t`, so it is the same swing on the tenth
///       attempt as on the first and no state survives a phase change.
///
///       A rocking mill winds up exactly as the others do and then reverses
///       on every hop: `mika_mill_rock` is the closed-form integral of the
///       swing, and it comes back to where it started once a full rock, so the
///       rings genuinely rock rather than drifting round.
function mika_mill_turned(_t, _mill, _flip) {
    var _ramp = _mill.orbit * MIKA_MILL_WIND / (MIKA_MILL_WIND_POW + 1);
    if (_t < MIKA_MILL_WIND) {
        return _ramp * power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW + 1);
    }
    var _u = _t - MIKA_MILL_WIND;
    if (!_mill.rock || _t < _flip) return _ramp + _mill.orbit * _u;
    return _ramp + _mill.orbit * ((_flip - MIKA_MILL_WIND)
                                  + mika_mill_rock(_t - _flip));
}

/// @desc How fast a mill's rings are going round him at frame `_t`, as a
///       fraction of their working rate: 1 flat out one way, -1 flat out the
///       other, and passing through zero only while he is hopping.
///
///       **The reversal is the hop, and that is the whole of the timing.**
///       `boss_holding` is false for `BOSS_STEP_MOVE` frames in every
///       `BOSS_STEP_HOLD + BOSS_STEP_MOVE`, and `mika_mill_rim` already throws
///       nothing through it -- because sand laid down while the origin slides
///       smears the figure. So the one window in which a mill is silent is
///       also the one window in which a reversal costs nothing, and putting
///       the two together means the rings spend every firing frame flat out
///       and turn over in the gap.
///
///       That removes the defect the first version of this shipped with: a
///       free-running cosine passed through zero wherever it liked, so twice a
///       cycle the metal was stationary *while throwing*, and a stationary
///       ring has no trailing edge to leave a wake off. It also makes the beat
///       of the thing his: 3.25 seconds of steady rotation, a hop, 3.25 the
///       other way.
///
///       **And the first reversal is the first hop the wind-up has finished
///       before, which is the other half of the timing.** The rings reach
///       speed on their own clock and his hops are on his, so a mill measured
///       straight off his cycle could have its first reversal land *inside*
///       its own spin-up -- and what that reaches a player as is rings that
///       wind up one way and throw the first wave of sand going the other. It
///       was reported in exactly those words. `mika_mill_flip_at` is the fix:
///       the schedule starts at a frame rather than running free, so the
///       wind-up is always one unbroken turn in the direction the attack then
///       opens in, and every reversal after it is still on a hop.
///
///       **One number carries the whole of the direction**, which is what
///       makes a reversing mill possible without a second code path. The rim
///       the sand leaves from, the lean on the throw and the way the grain
///       bends are all multiplied by it, so at full speed a rocking mill is
///       the crown exactly.
///
///       A mill that does not rock answers 1 for ever, so nothing about the
///       other three changed.
function mika_mill_swing(_t, _mill, _flip) {
    if (!_mill.rock) return 1;
    // One unbroken turn out of the wind-up and up to the first hop past it.
    if (_t < _flip) return 1;

    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    var _per = 2 * _cyc;
    var _v = (_t - _flip) mod _per;

    // Through the hop, as a half cosine: it leaves at full speed and arrives
    // at full speed the other way, with no corner at either end.
    if (_v < BOSS_STEP_MOVE) return dcos(180 * _v / BOSS_STEP_MOVE);
    if (_v < BOSS_STEP_MOVE + BOSS_STEP_HOLD) return -1;
    if (_v < 2 * BOSS_STEP_MOVE + BOSS_STEP_HOLD) {
        return -dcos(180 * (_v - BOSS_STEP_MOVE - BOSS_STEP_HOLD)
                     / BOSS_STEP_MOVE);
    }
    return 1;
}

/// @desc The integral of `mika_mill_swing` from zero to `_s`, in frames --
///       which is how far round a rocking mill has turned, in units of its own
///       working rate.
///
///       **Closed form and periodic**, which is what lets a reversing orbit
///       stay a pure function of the frame: a full rock integrates to exactly
///       zero, so the rings come back rather than creeping round, and no state
///       has to survive a phase change or be reset between attempts.
///
///       `_u` is counted from a reversal, so the four pieces are a hop, a
///       hold, the hop back and the hold home. A hold contributes its own
///       length; a hop contributes nothing at all over its whole width,
///       because half a cosine is as much one way as the other -- though it
///       does carry the swing out past the hold's own reach and back on the
///       way through, which is where the odd `BOSS_STEP_MOVE / pi` comes from.
function mika_mill_rock(_u) {
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    var _k = BOSS_STEP_MOVE / pi;
    // Through a local, because `mod (` reads as a call to a function named
    // `mod` to `check_unknown_functions` -- which is the one check standing
    // between a typo here and a modal error box under the harness. Same note
    // `boss_holding` carries.
    var _per = 2 * _cyc;
    var _v = _u mod _per;
    if (_v < BOSS_STEP_MOVE) return _k * dsin(180 * _v / BOSS_STEP_MOVE);
    if (_v < BOSS_STEP_MOVE + BOSS_STEP_HOLD) return -(_v - BOSS_STEP_MOVE);
    if (_v < 2 * BOSS_STEP_MOVE + BOSS_STEP_HOLD) {
        return -BOSS_STEP_HOLD
               - _k * dsin(180 * (_v - BOSS_STEP_MOVE - BOSS_STEP_HOLD)
                           / BOSS_STEP_MOVE);
    }
    return -BOSS_STEP_HOLD + (_v - 2 * BOSS_STEP_MOVE - BOSS_STEP_HOLD);
}

// ---------------------------------------------------------------------------
// The bolt: an aimed beam at the inflection
//
// **A mill is at its thinnest where it turns over, and that is exactly where
// it was letting the player stand still.** Nothing is thrown through a hop --
// which is the reversal's whole affordance -- so a rocking mill hands out a
// three-quarter-second rest every four seconds, in the one attack of the seven
// whose field is already half the density of the others. Reported as a notch
// easier than the rest of them, and this is where the slack was.
//
// So each ring throws one beam at each reversal, aimed at where the player is
// standing when it is cast. The warning runs through the hop and the beam
// fires as the sand comes back, so the quiet second is spent *reading a line
// and leaving it* rather than resting on it.
//
// **The beam is mounted on its ring and trained on the spot**, and getting
// there took one wrong answer first. The two obvious constructions are each
// half right: a beam that *follows* its ring keeps its root on the metal and
// slides off the spot it was aimed at, and a beam that stays where it was cast
// keeps the spot and comes adrift from the ring that threw it. The first
// version shipped the second, on the reasoning that a warned line the player
// cannot step off is worse than a detached root -- and what that reached a
// person as was six beams visibly hanging in the air nowhere near the rings.
//
// **`look` is the third answer and it is the one the engine was missing.**
// `src` pulls the root along with the ring and `look` re-aims the line at the
// world point it was cast at, so the beam pivots about that point like a
// searchlight on a moving mount: the root is on the metal, the spot stays
// covered for the whole life of the bolt, and what sweeps is everywhere else.
// A player who stands still is hit; a player who leaves gets a line that turns
// past them, which is more pressure than the fixed version ever had and is why
// the warning and the beam can both afford to be long.
//
// **Every ring aims true rather than spreading**, so six rays cross at one
// point and radiate out of it. The answer is to leave the point and be in one
// of the six gaps, which widen with distance -- a positional question with an
// answer everywhere, which is the same shape `Gilded Aperture` is built on. If
// it reads as one decision rather than six, the knob is a spread on the aim
// and it is one line.
//
// **It is gated on the reversal and not on `boss_holding`.** The two coincide
// by construction -- `mika_mill_swing` only leaves full speed during a hop --
// and keying it to the reversal is what keeps the bolt and the turn one event
// rather than two that happen to agree.
// ---------------------------------------------------------------------------

// Long enough to cross the field from a ring at his station, on the rule a
// laser's length is measured against the room rather than against itself.
#macro MIKA_RUSH_BOLT_LEN 2400
#macro MIKA_RUSH_BOLT_WID 34

// **Cyan, which is the one family his sand never reaches.** He fires gold,
// amber and bone; the current between two rings is already cyan, so a bolt out
// of the metal reads as the same substance and as nothing that can be confused
// with a grain.
#macro MIKA_RUSH_BOLT_COL BCOL_CYAN

// The warning covers the hop and runs into the hold, so the beam fires with
// the sand already back: the move has to be made before the storm returns,
// which is the whole point of putting the bolt here. Longer than `RING_WARN`
// because it is asking for more than a sidestep -- six lines cross at one
// point and the answer is which of the six gaps to be in.
#macro MIKA_RUSH_BOLT_WARN 66

// And it stays lit for most of a second, which a fixed line could not have
// afforded: trained on its point, a long beam is a long *pivot*, so the extra
// frames buy a sweep rather than a wall standing where nobody is any more.
#macro MIKA_RUSH_BOLT_HOT 42

/// @desc One ring's bolt, cast on the frame its mill turns over.
///
///       Answers the laser, or `undefined` on a mill that has none and when
///       the pool is full -- `laser_beam` refuses like everything else.
function mika_mill_bolt(_ring, _g, _t, _mill, _flip) {
    if (!_mill.bolt) return undefined;
    if (_t < _flip) return undefined;
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    if (((_t - _flip) mod _cyc) != 0) return undefined;

    // From the ring's own middle, because the hole is what a ring fires
    // through, and `ring_beam` for the `src` that keeps the root there.
    var _l = ring_beam(_ring, aim_at(_ring.x, _ring.y, _g.player.x,
                                     _g.player.y),
                       MIKA_RUSH_BOLT_LEN, MIKA_RUSH_BOLT_WID,
                       MIKA_RUSH_BOLT_COL, MIKA_RUSH_BOLT_WARN,
                       MIKA_RUSH_BOLT_HOT);

    // **The spot is a copy, not the player.** Handed the player's own struct
    // the bolt would track them for its whole life, which is a beam nobody can
    // dodge; what is wanted is where they were standing when it was cast.
    if (_l != undefined) _l.look = { x: _g.player.x, y: _g.player.y };
    return _l;
}

/// @desc The frame of an attack at which a rocking mill first turns over: the
///       first hop of his that begins at or after the wind-up has finished.
///
///       **Read once and carried, rather than read every frame.** It is what
///       lines a rocking mill's reversals up with his hops, and `drift_t` is
///       free-running -- it is not reset per attack, because a hop is derived
///       from it and one must not be left half-finished by a phase change. So
///       what a mill needs is one frame number, and it is a constant for the
///       life of the attack.
///
///       **At or after the wind-up, which is the part that was missing.** A
///       schedule read straight off his cycle could put a reversal inside the
///       spin-up, and the rings would then wind up one way and open the attack
///       going the other -- reported exactly so. Starting the schedule at a
///       frame instead of letting it run free costs nothing and cannot do
///       that: every reversal is still on a hop, because the frame chosen is
///       one.
///
///       Answers `MIKA_MILL_WIND`'s own first hop where there is no boss to
///       ask, which is how the suites pose a mill at a bare position.
function mika_mill_flip_at(_e) {
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    var _hop = 0;
    if (_e != undefined) {
        var _b = _e[$ "boss"];
        if (_b != undefined) _hop = _b.drift_t mod _cyc;
    }
    // Where his next hop starts, in this attack's own frames.
    var _at = (BOSS_STEP_HOLD - _hop) mod _cyc;
    if (_at < 0) _at += _cyc;
    while (_at < MIKA_MILL_WIND) _at += _cyc;
    return _at;
}

/// @desc How far out from him a ring is riding at frame `_t`: nothing at all
///       on the frame it forms, `_dist` by the time the spin-up is over. Eased
///       at both ends -- a ring that shot out and stopped dead would read as
///       having hit something.
///
///       **The wind-up is the mill's and the reach is the slot's**, which is
///       why only the distance is an argument: a four-ring mill wants its
///       rings further out to keep the gaps between them open, and it does not
///       want a different spin-up, because the spin-up is the gesture the
///       player has already learnt.
function mika_mill_reach(_t, _dist) {
    var _u = clamp(_t / MIKA_MILL_WIND, 0, 1);
    return _dist * _u * _u * (3 - 2 * _u);
}

/// @desc What a bead of ring `_cycle`'s stream looks like -- the shape, hue and
///       size its pellets carry. `_hue` is which step of that ring's cycle the
///       slot wants, so two slots can run the same two shapes in swapped
///       colours.
///
///       **One look per ring rather than one per bead.** Cycled along a stream
///       it bands the stream, and with only two streams on the field the thing
///       worth saying is which ring threw which: ring 0's storm is one shape
///       and one hue, ring 1's is another, and a glance tells them apart at
///       any distance.
function mika_mill_look(_cycle, _hue) {
    return mika_sand_grade(_cycle, _hue);
}

/// @desc The method a bead hands the pellets it breaks into. Built once per
///       (ring, hue, direction) and kept -- there are only a handful and a
///       bead is thrown every few frames, so a fresh method per bead is churn
///       for nothing.
function mika_mill_dress(_cycle, _hue, _sw, _mill) {
    static _cache = {};
    var _key = string(_cycle) + ":" + string(_hue) + ":" + string(_sw)
               + ":" + string(_mill.flr);
    if (!variable_struct_exists(_cache, _key)) {
        _cache[$ _key] = method({ look: mika_mill_look(_cycle, _hue),
                                  curl: MIKA_SAND_CURL * _sw,
                                  flr: _mill.flr },
                                function(_c, _k) {
            mika_sand_dress(_c, look, MIKA_MILL_MOTE_HOLD, MIKA_SAND_BRAKE,
                            flr, curl, MIKA_SAND_BEND, MIKA_SAND_LIFE);
        });
    }
    return _cache[$ _key];
}

/// @desc One bead off `_ring`'s metal at `_at` degrees round the band,
///       travelling `_dir`, which brakes and then breaks into sand.
///
///       Fired from where the metal is going to be rather than where it is,
///       on `ring_rim_at_x`'s rule: a mark holds still for its delay, and a
///       ring moving eight pixels a frame would otherwise have the hole arrive
///       where the mark is sitting.
///
///       The gentle turn is set outright rather than scheduled because it is
///       on from the first frame, which costs no queue entry.
function mika_bead(_ring, _at, _dir, _look, _dress, _curl, _mill) {
    var _u = fire(ring_rim_at_x(_ring, _at, MIKA_SAND_DELAY),
                  ring_rim_at_y(_ring, _at, MIKA_SAND_DELAY),
                  MIKA_MILL_HEAD_SPD, _dir, MIKA_MILL_HEAD_SHAPE, _look.col,
                  MIKA_SAND_DELAY);
    if (_u == undefined) return undefined;

    _u.scale = MIKA_MILL_HEAD_SCALE;
    _u.r = global.bshape_radius[MIKA_MILL_HEAD_SHAPE] * MIKA_MILL_HEAD_SCALE;
    _u.turn = _curl;

    bullet_accel_at(_u, MIKA_MILL_HEAD_HOLD, -MIKA_MILL_HEAD_BRAKE,
                    MIKA_MILL_HEAD_FLOOR);
    var _break = MIKA_MILL_HEAD_HOLD
                 + mika_sand_settle(MIKA_MILL_HEAD_SPD, MIKA_MILL_HEAD_BRAKE,
                                    MIKA_MILL_HEAD_FLOOR)
                 + MIKA_MILL_HANG;
    bullet_split_at(_u, _break, _mill.motes, mika_mill_mote_spd(_mill),
                    MIKA_MILL_MOTE_OFF, _dress);
    return _u;
}

/// @desc What one of the mill's rings does every frame: ride its orbit, turn
///       its metal, and lay down its stream.
///
///       **The orbit angle is worked out here and handed down** rather than
///       read off the ring, because the wake is defined against the ring's
///       travel and the ring's own velocity is dominated by the boss's hops.
///       Deriving the travel from the orbit keeps the figure the same shape
///       whether or not he is moving.
///
///       The cycle is bound into the method rather than written onto the ring
///       for the pool's reason: a ring is a reused struct, so a field bolted
///       onto one is a field the next user of that slot inherits.
function mika_mill_ring_for(_cycle, _a0, _way, _hue, _mill, _flip) {
    return method({ cyc: _cycle, a0: _a0, way: _way, hue: _hue, mill: _mill,
                    flip: _flip },
                  function(_ring, _g, _t) {
        var _rad = mika_mill_reach(_t, mill.dist);
        var _orb = a0 + way * mika_mill_turned(_t, mill, flip);
        _ring.ox = lengthdir_x(_rad, _orb);
        _ring.oy = lengthdir_y(_rad, _orb);
        // Rigid with the orbit rather than turning on its own: set outright,
        // and `spin` left at zero so `ring_step` does not add to it. A
        // constant here would turn the chain's marking relative to him, which
        // is the only thing left that it changes.
        _ring.spin = 0;
        _ring.ang = _orb;

        // The wake is aimed at where the metal will be when the bead goes
        // live, not where it is now. See `MIKA_MILL_LEAD`.
        // **The swing is read at the lead frame too.** It multiplies the
        // direction, so reading it now and the orbit later would have a
        // reversing mill disagree with itself about which way it is going for
        // the six frames a bead spends as a mark.
        mika_mill_rim(_ring, _g, _t, cyc, hue,
                      way * mika_mill_swing(_t + MIKA_MILL_LEAD, mill, flip),
                      a0 + way * mika_mill_turned(_t + MIKA_MILL_LEAD, mill,
                                                  flip),
                      mill);

        // ...and the bolt, which is outside the rim's guards on purpose: the
        // rim throws nothing through a hop and the bolt is thrown *into* one.
        mika_mill_bolt(_ring, _g, _t, mill, flip);
    });
}

/// @desc Put a mill down: `_mill.rings` rings out of him, evenly round him,
///       running `_way`, ring `i` throwing step `_hues[i]` of its own cycle.
///
///       **`_hues` is per ring rather than per slot** so that two slots can
///       run the same two shapes in swapped colours, which is all N2 is.
///
///       **Evenly spaced, derived from the count**, so a mill of any size is
///       the same gesture: two rings come out half a turn apart and four come
///       out a quarter apart, and neither had to be told.
function mika_mill_spawn(_e, _way, _hues, _mill) {
    // The frame a rocking mill first turns over on: his next hop after the
    // wind-up. Read once, here, and carried -- see `mika_mill_flip_at`.
    var _flip = mika_mill_flip_at(_e);
    for (var _i = 0; _i < _mill.rings; _i++) {
        // On top of him, at no radius: `mika_mill_reach` takes them out.
        var _r = ring_new(_e.x, _e.y, MIKA_RING_COL, 0);
        if (_r == undefined) break;
        ring_attach(_r, _e, 0, 0);
        _r.act = mika_mill_ring_for(_i, _i * (360 / _mill.rings), _way,
                                    _hues[_i mod array_length(_hues)], _mill,
                                    _flip);
    }
}

/// @desc **N1.** The mill, running one way round him, ring 0 throwing ember
///       glints and ring 1 amber grains.
function mika_n1_sandmill(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1], mika_mill_pair());
}

/// @desc **N2.** The same mill turned over: the rings run the other way round
///       him and the two storms trade hues, so the glints are the amber pair
///       and the grains the ember one.
///
///       **A copy rather than a variation**, deliberately -- the brief for the
///       seven non-spells is that they are variations of each other, and the
///       first one worth making is the one that reads immediately: the whole
///       figure is mirrored and the colours are the other way round, so a
///       player who has learnt N1 has to unlearn the direction rather than the
///       shape.
function mika_n2_sandmill(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [1, 0], mika_mill_pair());
}

/// @desc The wake of one ring, at the orbit angle it will be at when the bead
///       goes live.
///
///       Nothing is thrown until the spin-up is over, and the beat is counted
///       from there so the first bead lands on the frame the mill starts.
function mika_mill_rim(_ring, _g, _t, _cycle, _hue, _sw, _orb, _mill) {
    if (_t < MIKA_MILL_WIND) return;

    // **Nothing is thrown while he is moving between stations.** The streams
    // are read as an accumulation over several seconds, so anything laid down
    // while the origin is sliding is laid down in the wrong place and smears
    // the figure. `boss_holding` is false only for `BossMove.Step`'s hop,
    // which is three quarters of a second in four -- the beat is still counted
    // off `_t`, so the streams pick up in phase rather than restarting.
    if (!boss_holding(_ring.src)) return;

    if (((_t - MIKA_MILL_WIND) mod _mill.beat) != 0) return;

    // The ring travels along the tangent, so the rim it has just come past is
    // a quarter turn back from where it is heading. That is where the sand
    // leaves from, and it leaves straight out from *that point of the ring* --
    // which, on the trailing rim, is backward along the orbit.
    // **A quarter turn back from where it is heading, scaled by how fast it
    // is going.** At full speed that is the trailing rim exactly, which is
    // every mill but the rush; at a reversal it is the outer rim, straight out
    // from him, because a stationary ring has no trailing edge.
    var _back = _orb - 90 * _sw;

    // **The curl is quantised and the muzzle is not.** Where a bead leaves
    // from is computed per bead and costs nothing; what it breaks into is a
    // bound method held in a cache, and a continuous key would mint one per
    // frame for ever. Quarters are finer than the eye reads on a bend of
    // `MIKA_SAND_BEND` degrees, and a mill that does not sway lands on 1 or -1
    // exactly, so its cache is the single entry it always was.
    var _q = round(_sw * 4) / 4;

    var _mid = (_mill.wake - 1) * 0.5;
    var _gap = (_mill.wake > 1) ? _mill.arc / (_mill.wake - 1) : 0;
    var _look = mika_mill_look(_cycle, _hue);
    var _dress = mika_mill_dress(_cycle, _hue, _q, _mill);

    for (var _j = 0; _j < _mill.wake; _j++) {
        var _at = _back + (_j - _mid) * _gap;
        mika_bead(_ring, _at, _at + MIKA_MILL_LEAN * _sw, _look, _dress,
                  MIKA_SAND_CURL * _q, _mill);
    }
}

// ---------------------------------------------------------------------------
// N3 and N4 -- the quad
//
// **The same mill with four rings instead of two, and that is the whole of
// the variation.** The grain is N1's grain, the bead is N1's bead, the
// wind-up is N1's wind-up and the streams are laid down at N1's rate: a
// player who has learnt the mill reads every ribbon in this the same way. The
// figure they are arranged into is what changed, and it changed by one
// number.
//
// **A DRAFT.** Every number below is a first guess written to be played
// against N1, not a tuned attack -- see the note at the top of `mika_slots`.
// The three knobs most likely to want moving are the distance, whether each
// ring throws one stream or two, and the beat that has to come down with it.
//
// **Two rings make two pairs of arms and four rings make four single ones**,
// which is the reading the count buys. N1's four ribbons are two tight pairs
// half a turn apart, so the corridors between them alternate narrow and wide
// and a player who finds the wide one can sit in it. Four rings a quarter
// turn apart with one ribbon each put the same four arms at ninety degrees,
// so every corridor is the same width and none of them is a place to live.
// That is the micrododge the four-ring arrangement is for.
//
// **The density does not move, and that is deliberate rather than
// incidental.** Four rings throwing what two threw is twice the sand, which
// is not a variation of a breather, it is a spell. Cutting each ring to one
// stream puts the arithmetic back exactly where it was: `MIKA_MILL_RINGS`
// times `MIKA_MILL_WAKE` over `MIKA_MILL_BEAT` is four beads every three
// frames, and so is `MIKA_QUAD_RINGS` times `MIKA_QUAD_WAKE` over
// `MIKA_QUAD_BEAT`. The beat is untouched for the same reason: what sets it
// is how far the muzzle swings between beads -- the orbit times the beat,
// which is about six degrees -- and stretching the beat to afford two streams
// a ring would turn a spray into burst fire, which is the failure the beat's
// own note records.
//
// **They ride further out, because four of them do not fit where two did.**
// At `MIKA_MILL_DIST` the four rims would leave gaps of about a hundred and
// eighty pixels; the extra thirty of radius opens them to two hundred and
// twenty-five, which is a door rather than a slot. It also takes a little off
// how much of him they hide: a ring blocks the player's fire across its own
// width, so four of them close in are a collar he can be shot through about
// half the time, and the further out they ride the narrower each one's shadow
// on the column under him.
// ---------------------------------------------------------------------------

#macro MIKA_QUAD_RINGS 4
#macro MIKA_QUAD_DIST 235

// **One stream a ring, which is the count's other half.** See above: four
// rings throwing two streams each is twice N1's sand, and twice a breather's
// sand is not a breather.
#macro MIKA_QUAD_WAKE 1

// Unused while the wake is one, and here so that the first thing a playtest
// reaches for has a number to move rather than a hole. Pointed at the pair's
// so the two mills stay one family until somebody decides otherwise.
#macro MIKA_QUAD_WAKE_ARC MIKA_MILL_WAKE_ARC

// N1's beat and N1's orbit, untouched. Thirty more pixels of radius is a
// bead gap of twenty-six against N1's twenty-two, which is close enough to the
// same ribbon that nothing had to move for it -- see `mika_mill_bead_gap`.
#macro MIKA_QUAD_BEAT MIKA_MILL_BEAT
#macro MIKA_QUAD_ORBIT MIKA_MILL_ORBIT

/// @desc N3 and N4's mill: four rings, a quarter turn apart, one stream each.
function mika_mill_quad() {
    return mika_mill_shape({ rings: MIKA_QUAD_RINGS, dist: MIKA_QUAD_DIST,
                             orbit: MIKA_QUAD_ORBIT, beat: MIKA_QUAD_BEAT,
                             wake: MIKA_QUAD_WAKE,
                             arc: MIKA_QUAD_WAKE_ARC });
}

/// @desc **N3.** The quad, running the same way round him N1 does.
///
///       **Opposite rings share a look and adjacent ones do not**, which is
///       what `[0, 1, 0, 1]` says: `mika_sand_grade` wraps, so ring 2 borrows
///       ring 0's cycle and ring 3 borrows ring 1's, and the hues are handed
///       out to match. What that draws is glints, grains, glints, grains
///       round him -- the two storms N1 has, interleaved, so the four-fold
///       figure is read as two two-fold ones crossing. Four different looks
///       would be four things to tell apart at the moment the player is
///       telling arms apart, which is one job too many for the channel.
function mika_n3_sandquad(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1, 0, 1], mika_mill_quad());
}

/// @desc **N4.** The quad turned over, on N2's terms exactly: the rings run
///       the other way round him and the two storms trade hues. The same two
///       arguments carry the whole of the difference, because the direction
///       turns the orbit, the rim the sand leaves from, the lean on the throw
///       and the way the drift bends over together.
function mika_n4_sandquad(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [1, 0, 1, 0], mika_mill_quad());
}

// ---------------------------------------------------------------------------
// N5 and N6 -- the crown
//
// **All six of his rings, which is where the count stops.** `MIKA_RING_N` is
// six because six of them on one orbit leave gaps about as wide as a ring and
// seven closes them, so the top of the non-spell ladder is the whole set
// turning round him at once -- and it is the same arrangement `Gilded
// Aperture` is built on, at the same radius, which is the useful part: the
// breather teaches the formation and the spell two slots later tests it.
//
// **A DRAFT**, on the quad's terms exactly. Every number below is a first
// guess written to be played against N3.
//
// **They ride at `MIKA_ORBIT`, which is where all his six-ring formations
// sit.** Not a number picked for this attack: one radius for his furniture is
// what lets the player learn where it lives, and the gaps between six rims out
// there are about a hundred and seventy pixels -- a ring's own width, which is
// the aperture's whole design.
//
// **And the orbit had to come down, which is the finding this slot turned
// up.** The mill's note says the beat is set by how far the muzzle swings
// between beads and that much more than a few degrees reads as a gap; that was
// written when every mill rode at `MIKA_MILL_DIST`, where degrees and pixels
// were the same sentence. At three hundred they are not. Six rings need a
// slower beat to keep the sand affordable, and N1's orbit at N1's beat out
// here would lay beads forty-four pixels apart against N1's twenty-two -- a
// ribbon of separate shots rather than a spray, which is the exact failure the
// beat's own note names. `mika_mill_bead_gap` is the invariant that survives a
// change of radius and `mika_mill_rim_spd` is the other half of what the orbit
// answers for; both are checked against the pair rather than against a number.
//
// What that buys is a statelier figure: a lap takes four and a half seconds
// against N1's three, so the crown wheels where the mill whips. Which is the
// right reading for the last of the breathers.
// ---------------------------------------------------------------------------

#macro MIKA_CROWN_RINGS MIKA_RING_N
#macro MIKA_CROWN_DIST MIKA_ORBIT

// **One stream a ring still.** Six times two is three times N1's sand, which
// is not a breather by any reading.
#macro MIKA_CROWN_WAKE 1
#macro MIKA_CROWN_WAKE_ARC MIKA_MILL_WAKE_ARC

// **The beat is the one place the density moves, and it moves up rather than
// exactly.** Six rings over a beat of four is three beads every two frames
// against the pair's four every three -- an eighth more sand, because six
// into four beads a frame does not go and the last breather before his spells
// is the right place for the rounding to land heavy rather than light.
#macro MIKA_CROWN_BEAT 4

// Set so the bead gap out at `MIKA_ORBIT` lands beside the pair's and the
// metal still comfortably outruns `MIKA_SAND_FLOOR`. See above; both are
// asserted rather than trusted.
#macro MIKA_CROWN_ORBIT 1.30

/// @desc N5 and N6's mill: six rings, a sixth of a turn apart, one stream
///       each, out where his formations live.
function mika_mill_crown() {
    return mika_mill_shape({ rings: MIKA_CROWN_RINGS, dist: MIKA_CROWN_DIST,
                             orbit: MIKA_CROWN_ORBIT, beat: MIKA_CROWN_BEAT,
                             wake: MIKA_CROWN_WAKE,
                             arc: MIKA_CROWN_WAKE_ARC });
}

/// @desc **N5.** The crown, running the way round him N1 and N3 do.
///
///       **Alternate rings share a look**, which is what the table wrapping
///       gives once there are more rings than cycles: glint, grain, glint,
///       grain round him, so each shape draws a three-fold figure and the two
///       cross. The quad's opposite rings paired the same way for the same
///       reason -- what the wrap guarantees is that a ring's look is its
///       index's parity, and what falls out of that is a figure of
///       `rings / 2` fold in each shape.
function mika_n5_sandcrown(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1, 0, 1, 0, 1], mika_mill_crown());
}

/// @desc **N6.** The crown turned over, on N2's and N4's terms: the rings run
///       the other way round him and the two storms trade hues.
function mika_n6_sandcrown(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [1, 0, 1, 0, 1, 0], mika_mill_crown());
}


// ---------------------------------------------------------------------------
// N7 -- the rush
//
// **The last breather, and the one with no mirror.** Six of them go out in
// pairs -- a mill and the same mill turned over -- and seven is odd, so the
// last one has no partner to be the reverse of. So it is its own: the orbit
// does not pick a direction, it **swings between both**, and what would have
// been N8 is folded into N7 as the other half of its own cycle. That is the
// structure's own argument for the shape rather than a decoration on it.
//
// **And it is where he runs out.** It is the last thing between the player and
// his final spell, so it is the one breather allowed to stop being restful:
// rapid, thin and unsettled where the crown is broad and stately. Asked for in
// those terms -- more desperate as the fight approaches the climax.
//
// **A DRAFT**, on the quad's and the crown's terms. Every number is a first
// guess written to be played against N5.
//
// Four things carry it and each is one field of the mill:
//
// - **The swing, and it is timed to his hops.** The rings hold flat out one
//   way for the whole of `BOSS_STEP_HOLD` -- three and a quarter seconds --
//   and turn over during `BOSS_STEP_MOVE`, which is the three quarters of a
//   second he spends hopping. There is no period of its own: the period is
//   the hop.
//
//   **That is the fix for the first version and it fixes two things at
//   once.** A free-running cosine was reported as far too rapid, and it was:
//   1.4 seconds a reversal is a twitch rather than a change of mind. It also
//   passed through zero wherever it liked, so twice a cycle the metal was
//   stationary *while throwing* -- and a stationary ring has no trailing edge
//   to leave a wake off, which was written down here as a cost worth paying.
//   It was not: the mill is already silent through a hop, because sand laid
//   down while the origin slides smears the figure. Putting the reversal
//   inside that silence means the rings spend every firing frame flat out and
//   turn over in the gap, and the cost disappears rather than being accepted.
// - **The sand is faster.** A higher settle floor is the one lever that is
//   both halves of "rapid but sparse": a grain that settles quicker crosses
//   the field quicker, so it is harder to stand next to *and* it is gone
//   sooner, which thins the field without firing less.
// - **A bead breaks into two, not three.** The other third of the thinning,
//   and with an even count the two go fore and aft rather than one carrying on
//   down the stream -- a bead shearing in half rather than blooming, which is
//   the right picture for this one.
// - **The beat is the mill's own three again.** More beads a second than the
//   crown throws, which is the "rapid" the count cannot supply once the rings
//   have run out at six.
//
// - **And a bolt at every reversal**, aimed at wherever the player is
//   standing. That is the fifth thing and it was added last: everything above
//   made the attack *thin*, and thin turned out to read as easy, because the
//   hop is a window in which nothing is thrown at all. See the bolt's own
//   section for why it does not follow its ring.
//
// **And the wake is never thrown away**, which the first version of this
// accepted and did not need to. See `mika_mill_swing`: the reversal lives
// entirely inside the hop, and the mill does not throw through a hop.
//
// **And the wind-up turns the way the first sand does.** The rings reach speed
// on their own clock and his hops are on his, so a schedule read straight off
// his cycle could put the first reversal inside the spin-up -- rings winding up
// one way and opening the attack going the other, which is how it was
// reported. The schedule starts at the first hop the wind-up has finished
// before, so the spin-up is one unbroken turn and every reversal after it is
// still a hop. See `mika_mill_flip_at`.
// ---------------------------------------------------------------------------

#macro MIKA_RUSH_RINGS MIKA_RING_N
#macro MIKA_RUSH_DIST MIKA_ORBIT
#macro MIKA_RUSH_WAKE 1

// Rate, held flat out between reversals. Set so the bead gap out at
// `MIKA_ORBIT` on a beat of three lands beside the crown's -- see
// `mika_mill_bead_gap`, which is what any two mills are held level against.
//
// Over one hold that is about a full turn, so a ring goes all the way round
// one way and all the way back: a wind and an unwind rather than a wobble.
#macro MIKA_RUSH_ORBIT 1.72
#macro MIKA_RUSH_BEAT 3

// Thinner and quicker. See above; both are measured rather than argued.
#macro MIKA_RUSH_MOTES 2
#macro MIKA_RUSH_FLOOR 3.6

/// @desc N7's mill: six rings out where his formations live, rocking between
///       full speed one way and full speed the other.
function mika_mill_rush() {
    return mika_mill_shape({ rings: MIKA_RUSH_RINGS, dist: MIKA_RUSH_DIST,
                             orbit: MIKA_RUSH_ORBIT, beat: MIKA_RUSH_BEAT,
                             wake: MIKA_RUSH_WAKE, motes: MIKA_RUSH_MOTES,
                             flr: MIKA_RUSH_FLOOR, rock: true, bolt: true });
}

/// @desc **N7.** The rush: the crown's six rings, reversing.
///
///       **The hues are N5's**, deliberately. This slot already varies the
///       movement, the settle and the break, and a fourth channel saying "this
///       is the last one" would be the one that competes with reading the
///       arms. What says it is the last one is that the figure will not hold
///       still.
function mika_n7_sandrush(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1, 0, 1, 0, 1], mika_mill_rush());
}
