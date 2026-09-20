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
#macro MIKA_MILL_MOTE_HOLD 6

/// @desc The wind-up factor at frame `_t`: 0 at rest, 1 at working speed, and
///       1 for ever after.
function mika_mill_wind(_t) {
    if (_t >= MIKA_MILL_WIND) return 1;
    return power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW);
}

/// @desc How far round him a ring has walked by frame `_t`, in degrees -- the
///       integral of `MIKA_MILL_ORBIT * mika_mill_wind`.
///
///       Closed form, so a ring's position is a function of the frame and
///       nothing has to be carried between frames or reset between attempts.
function mika_mill_turned(_t) {
    var _ramp = MIKA_MILL_ORBIT * MIKA_MILL_WIND / (MIKA_MILL_WIND_POW + 1);
    if (_t < MIKA_MILL_WIND) {
        return _ramp * power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW + 1);
    }
    return _ramp + MIKA_MILL_ORBIT * (_t - MIKA_MILL_WIND);
}

/// @desc How far out from him a ring is riding at frame `_t`: nothing at all
///       on the frame it forms, its full distance by the time the spin-up is
///       over. Eased at both ends -- a ring that shot out and stopped dead
///       would read as having hit something.
function mika_mill_reach(_t) {
    var _u = clamp(_t / MIKA_MILL_WIND, 0, 1);
    return MIKA_MILL_DIST * _u * _u * (3 - 2 * _u);
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
function mika_mill_dress(_cycle, _hue, _way) {
    static _cache = {};
    var _key = string(_cycle) + ":" + string(_hue) + ":" + string(_way);
    if (!variable_struct_exists(_cache, _key)) {
        _cache[$ _key] = method({ look: mika_mill_look(_cycle, _hue),
                                  curl: MIKA_SAND_CURL * _way },
                                function(_c, _k) {
            mika_sand_dress(_c, look, MIKA_MILL_MOTE_HOLD, MIKA_SAND_BRAKE,
                            MIKA_SAND_FLOOR, curl,
                            MIKA_SAND_BEND, MIKA_SAND_LIFE);
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
function mika_bead(_ring, _at, _dir, _look, _dress, _curl) {
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
    bullet_split_at(_u, _break, MIKA_MILL_MOTES, MIKA_MILL_MOTE_SPD,
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
function mika_mill_ring_for(_cycle, _a0, _way, _hue) {
    return method({ cyc: _cycle, a0: _a0, way: _way, hue: _hue },
                  function(_ring, _g, _t) {
        var _rad = mika_mill_reach(_t);
        var _orb = a0 + way * mika_mill_turned(_t);
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
        mika_mill_rim(_ring, _g, _t, cyc, hue, way,
                      a0 + way * mika_mill_turned(_t + MIKA_MILL_LEAD));
    });
}

/// @desc Put a mill down: two rings out of him, half a turn apart, running
///       `_way` round him, ring `i` throwing step `_hues[i]` of its own cycle.
///
///       **`_hues` is per ring rather than per slot** so that two slots can
///       run the same two shapes in swapped colours, which is all N2 is.
function mika_mill_spawn(_e, _way, _hues) {
    for (var _i = 0; _i < MIKA_MILL_RINGS; _i++) {
        // On top of him, at no radius: `mika_mill_reach` takes them out.
        var _r = ring_new(_e.x, _e.y, MIKA_RING_COL, 0);
        if (_r == undefined) break;
        ring_attach(_r, _e, 0, 0);
        _r.act = mika_mill_ring_for(_i, _i * (360 / MIKA_MILL_RINGS), _way,
                                    _hues[_i mod array_length(_hues)]);
    }
}

/// @desc **N1.** The mill, running one way round him, ring 0 throwing ember
///       glints and ring 1 amber grains.
function mika_n1_sandmill(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1]);
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
    mika_mill_spawn(_e, -1, [1, 0]);
}

/// @desc The wake of one ring, at the orbit angle it will be at when the bead
///       goes live.
///
///       Nothing is thrown until the spin-up is over, and the beat is counted
///       from there so the first bead lands on the frame the mill starts.
function mika_mill_rim(_ring, _g, _t, _cycle, _hue, _way, _orb) {
    if (_t < MIKA_MILL_WIND) return;

    // **Nothing is thrown while he is moving between stations.** The streams
    // are read as an accumulation over several seconds, so anything laid down
    // while the origin is sliding is laid down in the wrong place and smears
    // the figure. `boss_holding` is false only for `BossMove.Step`'s hop,
    // which is three quarters of a second in four -- the beat is still counted
    // off `_t`, so the streams pick up in phase rather than restarting.
    if (!boss_holding(_ring.src)) return;

    if (((_t - MIKA_MILL_WIND) mod MIKA_MILL_BEAT) != 0) return;

    // The ring travels along the tangent, so the rim it has just come past is
    // a quarter turn back from where it is heading. That is where the sand
    // leaves from, and it leaves straight out from *that point of the ring* --
    // which, on the trailing rim, is backward along the orbit.
    var _back = _orb - 90 * _way;

    var _mid = (MIKA_MILL_WAKE - 1) * 0.5;
    var _gap = (MIKA_MILL_WAKE > 1) ? MIKA_MILL_WAKE_ARC / (MIKA_MILL_WAKE - 1) : 0;
    var _look = mika_mill_look(_cycle, _hue);
    var _dress = mika_mill_dress(_cycle, _hue, _way);

    for (var _j = 0; _j < MIKA_MILL_WAKE; _j++) {
        var _at = _back + (_j - _mid) * _gap;
        mika_bead(_ring, _at, _at + MIKA_MILL_LEAN * _way, _look, _dress,
                  MIKA_SAND_CURL * _way);
    }
}
