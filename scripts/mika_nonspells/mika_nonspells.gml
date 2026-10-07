/// @desc Mika's seven non-spells (N1-N7) and the sand they are made of.
///
/// The owner's brief for them: "small/sandy bullets continuously spraying in
/// pretty patterns -- brewing sandstorms with magnetism -- from his rings as
/// they spin, which shoot out quickly and then rapidly decelerate to a slower
/// speed then drift in a deterministic pattern". They are variations of each
/// other and act as breathers between his spells. Mika himself fires nothing
/// in any of them at present; the rings throw everything.
///
/// A grain leaves the metal fast, holds that speed briefly, brakes to a floor
/// speed (a clamp via `spd_min`, so it can't overshoot into reverse), then
/// bends by `MIKA_SAND_BEND` degrees and holds the heading it reaches.
///
/// Every number here is unplayed, and N3-N7 are first drafts.

// ---------------------------------------------------------------------------
// The grain
// ---------------------------------------------------------------------------

// The grain's warning-mark delay.
#macro MIKA_SAND_DELAY 6

// Launch speed.
#macro MIKA_SAND_SPD 10.5

// Frames at launch speed before braking, and the braking rate.
#macro MIKA_SAND_HOLD 18
#macro MIKA_SAND_BRAKE 0.55

// The speed it settles to, the turn rate of its drift, and how many degrees
// it bends before holding its heading.
#macro MIKA_SAND_FLOOR 2.0
#macro MIKA_SAND_CURL 0.32
#macro MIKA_SAND_BEND 46


// A backstop lifetime; grains normally leave by crossing the field edge.
#macro MIKA_SAND_LIFE 1500

// Each ring throws one shape for the whole attack; the colour steps through a
// cycle of this many hues. Scale is drawn size only -- `mika_sand_dress`
// shrinks the hitbox with it.
#macro MIKA_SAND_GRADES 3

/// @desc The looks a ring's sand cycles through: one cycle per ring.
function mika_sand_cycles() {
    static _cycles = [
        // Ring 0: glints.
        [ { shape: BSHAPE_MOTE, col: BCOL_EMBER, scale: 1.0 },
          { shape: BSHAPE_MOTE, col: BCOL_AMBER, scale: 1.0 },
          { shape: BSHAPE_MOTE, col: BCOL_BONE,  scale: 1.0 } ],

        // Ring 1: grains.
        [ { shape: BSHAPE_PELLET, col: BCOL_EMBER, scale: 1.0 },
          { shape: BSHAPE_PELLET, col: BCOL_AMBER, scale: 1.0 },
          { shape: BSHAPE_PELLET, col: BCOL_BONE,  scale: 1.0 } ],
    ];
    return _cycles;
}

/// @desc Step `_i` of cycle `_cycle`: shape, hue and drawn scale. Both
///       indices wrap.
function mika_sand_grade(_cycle, _i) {
    var _all = mika_sand_cycles();
    var _c = _all[_cycle mod array_length(_all)];
    return _c[_i mod array_length(_c)];
}

/// @desc The frame a grain launched at `_spd` reaches `_floor`.
///       `bullet_step` applies acceleration before moving, so the speed after
///       one step is already `_spd - _brake`; the ceiling makes the turn start
///       on the first frame the clamp holds.
function mika_sand_settle(_spd, _brake, _floor) {
    return ceil((_spd - _floor) / max(0.0001, _brake));
}

/// @desc One grain leaving `_ring`'s metal at `_at` degrees round the band,
///       travelling `_dir` (the two angles differ: that is the lean off a
///       turning ring), then settling.
function mika_sand(_ring, _at, _dir, _spd, _hold, _brake, _floor, _curl,
                   _bend, _life, _look) {
    // Fired where the metal will be when the mark goes live, not where it is
    // now (see `ring_rim_at_x`).
    var _u = fire(ring_rim_at_x(_ring, _at, MIKA_SAND_DELAY),
                  ring_rim_at_y(_ring, _at, MIKA_SAND_DELAY), _spd, _dir,
                  _look.shape, _look.col, MIKA_SAND_DELAY);
    return mika_sand_dress(_u, _look, _hold, _brake, _floor, _curl, _bend,
                           _life);
}

/// @desc Make an already-fired bullet into a grain: its look, then the hold,
///       brake, bend and lifetime. Used for thrown grains and for the
///       children of a split. Works from the bullet's current speed, so each
///       reaches its floor on its own frame. Passes `undefined` through (a
///       full pool fires nothing).
function mika_sand_dress(_u, _look, _hold, _brake, _floor, _curl, _bend,
                         _life) {
    if (_u == undefined) return undefined;

    // The hitbox shrinks with the drawn size. The shape is set too, because a
    // split child is born wearing its parent's graphic.
    _u.shape = _look.shape;
    _u.col = _look.col;
    _u.scale = _look.scale;
    _u.r = global.bshape_radius[_look.shape] * _look.scale;
    _u.spin = global.bshape_spin[_look.shape];

    // Brake after `_hold` frames, clamped at `_floor`...
    _u.acc = 0;
    bullet_accel_at(_u, _hold, -_brake, _floor);

    // ...then turn from the settle frame for `_bend` degrees, then run true.
    var _settle = _hold + mika_sand_settle(_u.spd, _brake, _floor);

    bullet_turn_at(_u, _settle, _curl);
    if (_bend > 0 && _curl != 0) {
        bullet_turn_at(_u, _settle + ceil(_bend / abs(_curl)), 0);
    }

    // A backstop so a grain running parallel to a wall doesn't live for ever.
    bullet_expire_at(_u, _life);
    return _u;
}

// ---------------------------------------------------------------------------
// The burster: a carrier that breaks into sand
//
// Used only by the `Sand Burst` draft on the drafting table, not by any of
// Mika's slots. A large, slow carrier leaves the metal and splits (a real
// `bullet_split_at`) into grains dressed by `mika_sand_dress`.
// ---------------------------------------------------------------------------

#macro MIKA_CARRY_SHAPE BSHAPE_SPHERE
#macro MIKA_CARRY_COL BCOL_GOLD
#macro MIKA_CARRY_SPD 4.6
#macro MIKA_CARRY_AT 44            // frames from going live to the break
#macro MIKA_CARRY_N 9              // grains it breaks into
#macro MIKA_CARRY_OUT 3.8          // how fast they leave the break

// A burst grain's hold before braking (shorter than a thrown grain's).
#macro MIKA_CARRY_HOLD 7

/// @desc A carrier off `_ring`'s metal at `_at` degrees, travelling `_dir`,
///       that breaks into `MIKA_CARRY_N` grains of `_look` sand. The dress
///       method is bound to this carrier's own settings.
function mika_sand_burst(_ring, _at, _dir, _look, _hold, _brake, _floor,
                         _curl, _bend, _life) {
    var _u = fire(ring_rim_at_x(_ring, _at, MIKA_SAND_DELAY),
                  ring_rim_at_y(_ring, _at, MIKA_SAND_DELAY),
                  MIKA_CARRY_SPD, _dir, MIKA_CARRY_SHAPE, MIKA_CARRY_COL,
                  MIKA_SAND_DELAY);
    if (_u == undefined) return undefined;

    // `flr`, not `floor`: inside a bound method a bare `floor` resolves to the
    // built-in rounding function before the struct member, so the brake would
    // be handed a function reference and never apply.
    bullet_split_at(_u, MIKA_CARRY_AT, MIKA_CARRY_N, MIKA_CARRY_OUT, 0,
                    method({ look: _look, hold: _hold, brake: _brake,
                             flr: _floor, curl: _curl, bend: _bend,
                             life: _life },
                           function(_c, _k) {
        // `_k` is the child's index round the burst (unused here).
        mika_sand_dress(_c, look, hold, brake, flr, curl, bend, life);
    }));
    return _u;
}

// ---------------------------------------------------------------------------
// The mill (N5 to N7, and the rings of N1 to N4's discs)
//
// Rings form on top of Mika, extend to their distance while the orbit winds
// up from a standstill, and throw nothing until they reach speed. Each ring
// then lays streams of beads off its trailing rim -- thrown out from that
// point of the ring, so the sand is left in its wake. A bead brakes to a stop,
// hangs briefly, and splits into grains that drift. (N1 to N4's rings shed
// a disc instead; see "The disc" below.)
// ---------------------------------------------------------------------------

#macro MIKA_MILL_RINGS 2

// How far out the rings ride once up to speed.
#macro MIKA_MILL_DIST 205

// The direction (+1 or -1) is chosen per slot. It flips the orbit, the rim
// the sand leaves from, the lean on the throw and the way the drift bends,
// all together.

// The orbit is a level circle round him seen from above, as
// Chakram Blitz's loop is. On screen it is an ellipse `TILT` times as tall as
// it is wide. At the far side a ring is smaller by `DEPTH` of its size and
// dimmed by `DIM`, and in front as much larger, easing between with the
// sine of its angle. On the far half it is behind him, so he hides it, and it
// neither hurts nor blocks the player's fire. It still throws sand there.
#macro MIKA_MILL_TILT 0.53
#macro MIKA_MILL_DEPTH 0.2
#macro MIKA_MILL_DIM 0.55

// ---- the wind-up ----------------------------------------------------------

// Frames from a standstill to full speed, and the ramp's shape (above 1 is
// slow early, quick late). One factor drives the orbit and the rings' own
// rotation. It ramps to working speed and stops there, with no overshoot.
#macro MIKA_MILL_WIND 100
#macro MIKA_MILL_WIND_POW 2.4

// Working orbit speed, degrees a frame. The rings turn rigidly with the orbit
// (no separate spin).
#macro MIKA_MILL_ORBIT 2.1

// ---- the wake -------------------------------------------------------------

// The degrees of rim a ring's streams are spread over, when it throws more
// than one.
#macro MIKA_MILL_WAKE_ARC 56

// How far the throw is turned off straight-out-from-the-ring. A bead leaves
// radially from the ring, not from Mika; on the trailing rim that already
// points back along the orbit, and this is a small bias on top.
#macro MIKA_MILL_LEAN 10

// Frames between beads of one stream.
#macro MIKA_MILL_BEAT 3

// How far ahead, in frames, the throw's bearing is computed: a bead holds
// still as a mark for `MIKA_SAND_DELAY` frames while the ring keeps turning.
#macro MIKA_MILL_LEAD MIKA_SAND_DELAY

// ---- the shape of a mill --------------------------------------------------
//
// What varies between the non-spells (ring count, distance, orbit, beat,
// streams, pellets, floor, rocking, bolts) is one struct, bound into each
// ring's `act` at spawn. Everything else is shared through the macros here.

/// @desc One mill's shape, from `_spec`. `rings`, `dist`, `orbit` and `beat`
///       are required; the rest default:
///       - `wake`, `arc`: streams per ring and the rim they are spread over.
///       - `motes`, `flr`: pellets a bead breaks into, and their settle speed.
///       - `rock`: true for an orbit that reverses on each of his hops.
///       - `bolt`: true if every ring throws an aimed beam at each reversal
///         (only meaningful with `rock`).
///       - `disc`: true if the rings shed a disc of sand (`mika_disc_shed`)
///         instead of throwing beads.
///       - `wind`: frames the rings take to wind up (`MIKA_MILL_WIND`).
///       - `bands`: a disc's bands (`mika_disc_band`); N1's three by
///         default.
///       - `pace`: how fast a disc's sand spreads, is let go and drifts,
///         against N1's (1). The rings' `orbit` and `wind` are given to
///         match it (see `mika_woven_disc`).
///       `flr` not `floor`: see the note in `mika_sand_burst`.
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
        disc: _spec[$ "disc"] ?? false,
        wind: _spec[$ "wind"] ?? MIKA_MILL_WIND,
        bands: _spec[$ "bands"] ?? mika_disc_bands(),
        pace: _spec[$ "pace"] ?? 1,
    };
}

/// @desc The launch speed of the pellets a bead breaks into. Derived from the
///       floor, because `BQ.Accel` clamps its floor to `min(spd, floor)`: a
///       pellet launched slower than its floor would silently keep its launch
///       speed.
function mika_mill_mote_spd(_mill) {
    return max(MIKA_MILL_MOTE_SPD, _mill.flr * MIKA_MILL_MOTE_LEAD);
}

/// @desc The distance in pixels between consecutive beads of one stream.
///       Mills at different radii are compared on this rather than on degrees.
function mika_mill_bead_gap(_mill) {
    return _mill.dist * _mill.orbit * _mill.beat * pi / 180;
}

/// @desc How fast a mill's rings travel along their orbit, in pixels a frame.
///       The wake only reads if this outruns the sand's floor speed.
function mika_mill_rim_spd(_mill) {
    return _mill.dist * _mill.orbit * pi / 180;
}

// ---- the bead -------------------------------------------------------------

#macro MIKA_MILL_HEAD_SHAPE BSHAPE_ORB
#macro MIKA_MILL_HEAD_SCALE 1.0
// The bead streaks out, brakes to a standstill (floor 0), hangs, and bursts.
// Launch speed, hold and brake together set how far out it stops.
#macro MIKA_MILL_HEAD_SPD 13.5
#macro MIKA_MILL_HEAD_HOLD 3         // frames at launch speed before braking
#macro MIKA_MILL_HEAD_BRAKE 0.65
#macro MIKA_MILL_HEAD_FLOOR 0

// The break: frames it hangs at a standstill before splitting (counted from
// the stop), how many pellets, how fast they leave, and their angular offset.
#macro MIKA_MILL_HANG 8
#macro MIKA_MILL_MOTES 3
#macro MIKA_MILL_MOTE_SPD 3.2
#macro MIKA_MILL_MOTE_OFF 0          // one carries on down the stream

// How far above a mill's own settle floor a pellet is launched when that
// floor is high (see `mika_mill_mote_spd`), and the pellets' hold.
#macro MIKA_MILL_MOTE_LEAD 1.3
#macro MIKA_MILL_MOTE_HOLD 6

/// @desc The wind-up factor at frame `_t`: 0 at rest, 1 at working speed and
///       after.
function mika_mill_wind(_t) {
    if (_t >= MIKA_MILL_WIND) return 1;
    return power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW);
}

/// @desc How far round Mika a ring has turned by frame `_t`, in degrees: the
///       closed-form integral of the mill's rate (wind-up, then working
///       speed, then for a rocking mill `mika_mill_rock` from its first
///       reversal `_flip`). Being a pure function of `_t` means nothing carries
///       over between frames or attempts.
function mika_mill_turned(_t, _mill, _flip) {
    var _w = _mill.wind;
    var _ramp = _mill.orbit * _w / (MIKA_MILL_WIND_POW + 1);
    if (_t < _w) {
        return _ramp * power(_t / _w, MIKA_MILL_WIND_POW + 1);
    }
    var _u = _t - _w;
    if (!_mill.rock || _t < _flip) return _ramp + _mill.orbit * _u;
    return _ramp + _mill.orbit * ((_flip - _w)
                                  + mika_mill_rock(_t - _flip));
}

/// @desc The orbit's rate at frame `_t` as a fraction of working speed: 1 one
///       way, -1 the other. A rocking mill reverses only during his hops
///       (`BOSS_STEP_MOVE`), when `mika_mill_rim` throws nothing anyway, so it
///       is at full speed on every frame it fires. The first reversal is
///       `_flip` (see `mika_mill_flip_at`). The rim, the lean and the bend are
///       all multiplied by this. A mill that doesn't rock answers 1.
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

/// @desc The integral of `mika_mill_swing` from a reversal to `_u` frames
///       later, in units of the working rate. A full rock (hop, hold, hop
///       back, hold) integrates to zero, so the rings come back rather than
///       creeping round. A hop's half cosine contributes the
///       `BOSS_STEP_MOVE / pi` terms.
function mika_mill_rock(_u) {
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    var _k = BOSS_STEP_MOVE / pi;
    // Through a local: `mod (` reads to `check_unknown_functions` as a call to
    // a function named `mod`.
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
// The bolt (N7): at each reversal every ring casts a beam aimed at where the
// player is standing. The beam's root rides the ring (`src`) and its line
// stays trained on the spot it was cast at (`look`), so it pivots about that
// spot as the ring moves.
// ---------------------------------------------------------------------------

#macro MIKA_RUSH_BOLT_LEN 2400
#macro MIKA_RUSH_BOLT_WID 34
#macro MIKA_RUSH_BOLT_COL BCOL_CYAN

// The warning runs through the hop and the beam fires as the sand resumes.
#macro MIKA_RUSH_BOLT_WARN 66
#macro MIKA_RUSH_BOLT_HOT 42

/// @desc One ring's bolt, cast on the frame its mill turns over. Answers the
///       laser, or `undefined` (no bolt on this mill, not a reversal frame,
///       or the laser pool is full).
function mika_mill_bolt(_ring, _g, _t, _mill, _flip) {
    if (!_mill.bolt) return undefined;
    if (_t < _flip) return undefined;
    var _cyc = BOSS_STEP_HOLD + BOSS_STEP_MOVE;
    if (((_t - _flip) mod _cyc) != 0) return undefined;

    // From the ring's middle; `ring_beam` sets `src` so the root stays there.
    var _l = ring_beam(_ring, aim_at(_ring.x, _ring.y, _g.player.x,
                                     _g.player.y),
                       MIKA_RUSH_BOLT_LEN, MIKA_RUSH_BOLT_WID,
                       MIKA_RUSH_BOLT_COL, MIKA_RUSH_BOLT_WARN,
                       MIKA_RUSH_BOLT_HOT);

    // A copy of the player's position: passing the player struct itself
    // would make the beam track them for its whole life.
    if (_l != undefined) _l.look = { x: _g.player.x, y: _g.player.y };
    return _l;
}

/// @desc The attack frame at which a rocking mill first reverses: the first
///       of Mika's hops that starts at or after the wind-up ends. Read once at
///       spawn, since `drift_t` runs freely across attacks. Without a boss
///       (in tests) it assumes his cycle starts with the attack.
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

/// @desc How far out from Mika a ring rides at frame `_t`: zero when it
///       forms, `_dist` once the wind-up (`_wind` frames) is over, eased at
///       both ends.
function mika_mill_reach(_t, _dist, _wind = MIKA_MILL_WIND) {
    var _u = clamp(_t / _wind, 0, 1);
    return _dist * _u * _u * (3 - 2 * _u);
}

/// @desc The look of ring `_cycle`'s sand at hue step `_hue`. One look per
///       ring, so the two storms are told apart by shape.
function mika_mill_look(_cycle, _hue) {
    return mika_sand_grade(_cycle, _hue);
}

/// @desc The dress method a bead hands its pellets, cached per (ring, hue,
///       direction, floor) so beads don't allocate a method each.
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

/// @desc One bead off `_ring`'s metal at `_at` degrees, travelling `_dir`,
///       that brakes to a stop, hangs, and splits into sand. Fired where the
///       metal will be when the mark goes live (`ring_rim_at_x`).
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

/// @desc The `act` for one of a mill's rings: ride the orbit, turn with it,
///       lay down its streams (or shed into `_disc`, the disc's holder from
///       `mika_disc_holder`, when the mill has one), and cast a bolt at
///       reversals. The
///       orbit angle is computed from the frame rather than read off the ring,
///       whose velocity is dominated by Mika's own movement. Settings are
///       bound into the method, not written onto the pooled ring.
function mika_mill_ring_for(_cycle, _a0, _way, _hue, _mill, _flip,
                            _disc = undefined) {
    return method({ cyc: _cycle, a0: _a0, way: _way, hue: _hue, mill: _mill,
                    flip: _flip, disc: _disc },
                  function(_ring, _g, _t) {
        var _rad = mika_mill_reach(_t, mill.dist, mill.wind);
        var _orb = a0 + way * mika_mill_turned(_t, mill, flip);
        _ring.ox = lengthdir_x(_rad, _orb);
        _ring.oy = lengthdir_y(_rad * MIKA_MILL_TILT, _orb);
        // Rigid with the orbit: set outright, with `spin` zero so `ring_step`
        // does not add to it.
        _ring.spin = 0;
        _ring.ang = _orb;

        // Its depth: 1 at the far side (the top of the ellipse), -1 in front.
        var _far = dsin(_orb);
        _ring.depth = 1 - MIKA_MILL_DEPTH * _far;
        _ring.shade = MIKA_MILL_DIM * max(0, _far);
        _ring.behind = (_far > 0);

        if (disc != undefined) {
            mika_disc_shed(_ring, _t, cyc, hue,
                           a0 + way * mika_mill_turned(_t + MIKA_MILL_LEAD,
                                                       mill, flip),
                           mill, disc);
        } else {
            // The wake, with both the swing and the orbit read at the lead
            // frame (see `MIKA_MILL_LEAD`), so they agree about the
            // direction.
            mika_mill_rim(_ring, _g, _t, cyc, hue,
                          way * mika_mill_swing(_t + MIKA_MILL_LEAD, mill,
                                                flip),
                          a0 + way * mika_mill_turned(_t + MIKA_MILL_LEAD,
                                                      mill, flip),
                          mill);
        }

        // The bolt is cast into the hop, so it sits outside the rim's guards.
        mika_mill_bolt(_ring, _g, _t, mill, flip);
    });
}

/// @desc Put a mill down: `_mill.rings` rings evenly round Mika, running
///       `_way` (+1 or -1), ring `i` using hue step `_hues[i]` of its cycle.
function mika_mill_spawn(_e, _way, _hues, _mill) {
    // The frame a rocking mill first reverses; see `mika_mill_flip_at`.
    var _flip = mika_mill_flip_at(_e);
    // Where a disc's sand is circling now, shared by all its rings.
    var _disc = _mill.disc ? mika_disc_holder(_e, _way, _mill) : undefined;
    for (var _i = 0; _i < _mill.rings; _i++) {
        // On top of him, at no radius: `mika_mill_reach` takes them out.
        var _r = ring_new(_e.x, _e.y, MIKA_RING_COL, 0);
        if (_r == undefined) break;
        ring_attach(_r, _e, 0, 0);
        _r.act = mika_mill_ring_for(_i, _i * (360 / _mill.rings), _way,
                                    _hues[_i mod array_length(_hues)], _mill,
                                    _flip, _disc);
    }
}

/// @desc **N1.** The disc (`mika_disc_shed`), turning clockwise as the
///       sketch does: ring 0's bands are ember glints, ring 1's amber grains,
///       and the middle band gold.
function mika_n1_sanddisc(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [0, 1], mika_disc());
}

/// @desc **N2.** N1 mirrored: the disc turning counterclockwise, with the
///       hues swapped, so ring 0's bands are amber glints and ring 1's ember
///       grains (the middle band is gold in both).
function mika_n2_sanddisc(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [1, 0], mika_disc());
}

/// @desc One ring's wake at orbit angle `_orb`, with swing `_sw`. Nothing is
///       thrown during the wind-up or while Mika is hopping between stations
///       (`boss_holding`); the beat is counted from the end of the wind-up.
function mika_mill_rim(_ring, _g, _t, _cycle, _hue, _sw, _orb, _mill) {
    if (_t < _mill.wind) return;

    // Sand laid down while the origin slides would smear the figure.
    if (!boss_holding(_ring.src)) return;

    if (((_t - _mill.wind) mod _mill.beat) != 0) return;

    // The trailing rim: straight back along the ring's path on screen (the
    // ellipse's tangent), turned by the swing (at a reversal it is the outer
    // rim). On a circle this is `_orb - 90 * _sw`.
    var _back = darctan2(-MIKA_MILL_TILT * dcos(_orb), dsin(_orb))
                + 90 * (1 - _sw);

    // The curl is quantised to quarters so `mika_mill_dress`'s cache stays
    // small.
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
// The disc (N1 and N2)
//
// The mill's two rings on their 2.5D orbit, shedding sand that keeps circling
// in the rings' own plane (`BMod.Orbit`): three bands, the first starting
// inside each ring's metal and the others beyond it, with gaps between. A grain
// circles slower the further out it is and drifts outward; after
// `MIKA_DISC_FREE` frames it is let go along its path, flung a little faster
// than it was going, and brakes to a drift.
//
// Nothing is shed while Mika hops, as with the bead mill. Sand circles the
// spot where it was shed: when he lands somewhere new, the next grains start
// a disc round him there, and the old one goes on round its own centre until
// it has all been let go. Picked from the browser sketches
// (`tools/sketch/sets/mika_n1.js`, "Sand disc").
// ---------------------------------------------------------------------------

// N1 is the browser sketch's sand disc with everything running 1.5 times as
// fast -- the rings' turn included, so the shape is the sketch's -- and
// shedding every other frame. The rings' wind-up and working orbit (degrees a
// frame):
#macro MIKA_DISC_WIND 67
#macro MIKA_DISC_ORBIT 3.15

// Frames between sheddings, per ring.
#macro MIKA_DISC_BEAT 2

// How far beyond the rings' orbit the three bands start.
#macro MIKA_DISC_IN 34
#macro MIKA_DISC_MID 92
#macro MIKA_DISC_OUT 150

// Pixels a frame a grain drifts outward, and the frames it circles before it
// is let go (so how far out it gets).
#macro MIKA_DISC_GROW 1.35
#macro MIKA_DISC_FREE 222

// Let go: its speed along its path times `FLING`, held for `HOLD` frames, then
// braked by `BRAKE` a frame to `FLOOR`.
#macro MIKA_DISC_FLING 1.5
#macro MIKA_DISC_HOLD 7
#macro MIKA_DISC_BRAKE 0.11
#macro MIKA_DISC_FLOOR 3.0

// How far Mika must have moved from a disc's centre for new sand to start a
// disc round him instead (he settles onto a station by easing in).
#macro MIKA_DISC_RECENTRE 4

/// @desc One band of a disc: sand shed `_off` beyond the rings' orbit, of
///       shape `_shape` and colour `_col` (-1 for each: the ring's own sand,
///       `mika_mill_look`), circling with the rings, or against them at the
///       same rate if `_back`.
function mika_disc_band(_off, _shape = -1, _col = -1, _back = false) {
    return { off: _off, shape: _shape, col: _col, back: _back };
}

/// @desc N1's three bands: the ring's own sand, gold, its own sand again.
function mika_disc_bands() {
    return [ mika_disc_band(MIKA_DISC_IN),
             mika_disc_band(MIKA_DISC_MID, BSHAPE_PELLET, BCOL_GOLD),
             mika_disc_band(MIKA_DISC_OUT) ];
}

/// @desc N1's mill: the pair's two rings at the pair's distance, shedding a
///       disc.
function mika_disc() {
    return mika_mill_shape({ rings: MIKA_MILL_RINGS, dist: MIKA_MILL_DIST,
                             orbit: MIKA_DISC_ORBIT, beat: MIKA_DISC_BEAT,
                             wind: MIKA_DISC_WIND, disc: true });
}

/// @desc An orbit for a disc's sand (see `bullet_orbit`), round (`_x`, `_y`)
///       at the rings' tilt, turning `_way` at the rings' rate at their
///       radius. It never moves: the grains on it circle that spot. The
///       mill's `pace` runs the sand's numbers faster or slower together, so
///       its paths keep their shape.
function mika_disc_orbit(_x, _y, _way, _mill) {
    var _k = _mill.pace;
    return { x: _x, y: _y, tilt: MIKA_MILL_TILT, way: _way,
             rate: _mill.orbit, ref: _mill.dist, grow: MIKA_DISC_GROW * _k,
             free_at: floor(MIKA_DISC_FREE / _k + 0.5),
             fling: MIKA_DISC_FLING,
             hold: floor(MIKA_DISC_HOLD / _k + 0.5),
             brake: MIKA_DISC_BRAKE * _k * _k, flr: MIKA_DISC_FLOOR * _k };
}

/// @desc What a disc's rings share: the orbits new sand goes onto, `cur`
///       turning with the rings and `back` against them, both replaced by
///       `mika_disc_shed` when Mika has moved.
function mika_disc_holder(_e, _way, _mill) {
    return { cur: mika_disc_orbit(_e.x, _e.y, _way, _mill),
             back: mika_disc_orbit(_e.x, _e.y, -_way, _mill), way: _way,
             mill: _mill };
}

/// @desc One ring's shedding, at orbit angle `_orb`: a grain into each of the
///       mill's bands (`mika_disc_band`), at the ring's own angle. Nothing is
///       shed during the wind-up or while Mika hops (`boss_holding`).
function mika_disc_shed(_ring, _t, _cycle, _hue, _orb, _mill, _disc) {
    if (_t < _mill.wind) return;
    if (!boss_holding(_ring.src)) return;
    if (((_t - _mill.wind) mod _mill.beat) != 0) return;

    // He has landed somewhere new: the sand from here on circles him here.
    var _src = _ring.src;
    if (point_distance(_disc.cur.x, _disc.cur.y, _src.x, _src.y)
        > MIKA_DISC_RECENTRE) {
        _disc.cur = mika_disc_orbit(_src.x, _src.y, _disc.way, _disc.mill);
        _disc.back = mika_disc_orbit(_src.x, _src.y, -_disc.way, _disc.mill);
    }

    var _own = mika_mill_look(_cycle, _hue);
    var _bands = _mill.bands;
    for (var _k = 0; _k < array_length(_bands); _k++) {
        var _b = _bands[_k];
        mika_disc_grain(_b.back ? _disc.back : _disc.cur, _orb,
                        _mill.dist + _b.off,
                        (_b.shape < 0) ? _own.shape : _b.shape,
                        (_b.col < 0) ? _own.col : _b.col);
    }
}

/// @desc One grain on orbit `_o`, placed on it at once; it sits there as a
///       warning mark for `MIKA_SAND_DELAY` frames.
function mika_disc_grain(_o, _ang, _rad, _shape, _col) {
    var _u = fire(_o.x, _o.y, 0, 0, _shape, _col, MIKA_SAND_DELAY);
    bullet_orbit(_u, _o, _ang, _rad);
    // The sand's backstop, though a grain normally leaves the field first.
    bullet_expire_at(_u, MIKA_SAND_LIFE);
}

// ---------------------------------------------------------------------------
// N3 and N4 -- the woven disc
//
// The disc on four rings, a quarter turn apart on N1's orbit and at its speed.
// Each ring sheds a pair into one band: one grain circles with the rings as
// N1's sand does, the other against them at the same rate, so the two are let
// go as mirror images and their streams cross. Picked from the browser
// sketches (`tools/sketch/sets/mika_n3.js`, "Woven disc").
// ---------------------------------------------------------------------------

#macro MIKA_WOVEN_RINGS 4

/// @desc N3 and N4's mill: four rings shedding a pair into one band, the
///       grain circling with them of shape `_with_shape` and colour
///       `_with_col`, the one circling against them `_back_shape`,
///       `_back_col`. `_pace` runs the whole of it -- the rings' turn and
///       wind-up too, so the shape holds -- faster or slower than N1's; the
///       shedding beat stays, so a slower one lays its sand closer.
function mika_woven_disc(_with_shape, _with_col, _back_shape, _back_col,
                         _pace = 1) {
    return mika_mill_shape({
        rings: MIKA_WOVEN_RINGS, dist: MIKA_MILL_DIST,
        orbit: MIKA_DISC_ORBIT * _pace, beat: MIKA_DISC_BEAT,
        wind: floor(MIKA_DISC_WIND / _pace + 0.5), disc: true, pace: _pace,
        bands: [ mika_disc_band(MIKA_DISC_IN, _with_shape, _with_col),
                 mika_disc_band(MIKA_DISC_IN, _back_shape, _back_col, true) ],
    });
}

// N4 runs at this much of N3's pace: slower, and with the same shedding beat,
// denser.
#macro MIKA_N4_PACE 0.8
#macro MIKA_N4_WIND floor(MIKA_DISC_WIND / MIKA_N4_PACE + 0.5)

/// @desc **N3.** The woven disc, turning clockwise as N1 does: ember glints
///       circle with the rings, amber grains against them.
function mika_n3_woven(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [0], mika_woven_disc(BSHAPE_MOTE, BCOL_EMBER,
                                                 BSHAPE_PELLET, BCOL_AMBER));
}

/// @desc **N4.** N3 mirrored -- turning counterclockwise, with amber grains
///       circling with the rings and ember glints against them -- at
///       `MIKA_N4_PACE` of its pace, so slower and denser.
function mika_n4_woven(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0], mika_woven_disc(BSHAPE_PELLET, BCOL_AMBER,
                                                BSHAPE_MOTE, BCOL_EMBER,
                                                MIKA_N4_PACE));
}

// ---------------------------------------------------------------------------
// N5 and N6 -- the crown (draft)
//
// All six of his rings (`MIKA_RING_N`) at `MIKA_ORBIT`, the radius his
// six-ring formations use. The orbit is slower than the pair's, because the
// same angle covers more ground at this radius (compare mills with
// `mika_mill_bead_gap` and `mika_mill_rim_spd`).
// ---------------------------------------------------------------------------

#macro MIKA_CROWN_RINGS MIKA_RING_N
#macro MIKA_CROWN_DIST MIKA_ORBIT
#macro MIKA_CROWN_WAKE 1
#macro MIKA_CROWN_WAKE_ARC MIKA_MILL_WAKE_ARC
#macro MIKA_CROWN_BEAT 4
#macro MIKA_CROWN_ORBIT 1.30

/// @desc N5 and N6's mill: six rings, a sixth of a turn apart, one stream
///       each.
function mika_mill_crown() {
    return mika_mill_shape({ rings: MIKA_CROWN_RINGS, dist: MIKA_CROWN_DIST,
                             orbit: MIKA_CROWN_ORBIT, beat: MIKA_CROWN_BEAT,
                             wake: MIKA_CROWN_WAKE,
                             arc: MIKA_CROWN_WAKE_ARC });
}

/// @desc **N5.** The crown, turning N1's way. Alternate rings share a look.
function mika_n5_sandcrown(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1, 0, 1, 0, 1], mika_mill_crown());
}

/// @desc **N6.** N5 mirrored, with hues swapped.
function mika_n6_sandcrown(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, -1, [1, 0, 1, 0, 1, 0], mika_mill_crown());
}


// ---------------------------------------------------------------------------
// N7 -- the rush (draft)
//
// The last breather, asked for as "more desperate as the fight approaches the
// climax". Six rings whose orbit reverses on each of Mika's hops (and so has
// no mirrored partner), faster-settling sand, beads that split in two, and a
// bolt from every ring at each reversal. The first reversal waits for the
// wind-up to finish (`mika_mill_flip_at`).
// ---------------------------------------------------------------------------

#macro MIKA_RUSH_RINGS MIKA_RING_N
#macro MIKA_RUSH_DIST MIKA_ORBIT
#macro MIKA_RUSH_WAKE 1

// Orbit speed between reversals (about a full turn each way per hold), and
// the beat.
#macro MIKA_RUSH_ORBIT 1.72
#macro MIKA_RUSH_BEAT 3

// Pellets per bead, and the settle floor.
#macro MIKA_RUSH_MOTES 2
#macro MIKA_RUSH_FLOOR 3.6

/// @desc N7's mill: six rings at `MIKA_ORBIT`, reversing on his hops, with
///       bolts.
function mika_mill_rush() {
    return mika_mill_shape({ rings: MIKA_RUSH_RINGS, dist: MIKA_RUSH_DIST,
                             orbit: MIKA_RUSH_ORBIT, beat: MIKA_RUSH_BEAT,
                             wake: MIKA_RUSH_WAKE, motes: MIKA_RUSH_MOTES,
                             flr: MIKA_RUSH_FLOOR, rock: true, bolt: true });
}

/// @desc **N7.** The rush, with N5's hues.
function mika_n7_sandrush(_e, _g, _t) {
    if (_t != 0) return;
    mika_mill_spawn(_e, 1, [0, 1, 0, 1, 0, 1], mika_mill_rush());
}
