/// @desc **Chakram Blitz**, Mika's S2.
///
/// The owner's brief: Mika throws a ring at the player. It lays a trail
/// woven like a braided rope (a tight double helix) that starts stationary and
/// then slowly spreads, each bead's heading a step on from the last so the
/// rope comes apart evenly. The throw is smooth and fancy rather than heavy,
/// like a magnetic throw: a rapid acceleration and deceleration, with no
/// crash at the end. Short of the edge of the field the ring comes to rest,
/// its spin building all the while as a yo-yo's does, gives a brief
/// continuous radial burst, and is pulled straight back, so it reads as a
/// throw and a pullback rather than a ring stuck spinning in place. The throw
/// is fast and aggressive, and while the ring charges up a brief warning flash
/// shows the player where not to be; it doesn't stay for the throw. He has two
/// rings and alternates them, and the throws start spaced out and come
/// gradually faster.
///
/// Both are ordinary rings (they hurt to touch and block shots), each riding
/// an anchor this attack moves, so `ring_step` places them. The warning is the
/// ring's lane flash (`ring_lane_flash`). Mika himself fires nothing.
///
/// Every number here is a first guess, waiting on playtesting.

enum ChakramMode {
    Hold,       // resting beside Mika, looping round him while it waits
    Wind,       // drawing back before a throw
    Out,        // thrown, flying out
    Spray,      // at rest short of the wall, spraying
    Back,       // pulled home
}

// ---------------------------------------------------------------------------
// At rest, and the timing of throws
// ---------------------------------------------------------------------------

// Where each ring rests beside Mika (ring 0 on his left, ring 1 on his
// right), how far it bobs there and how fast (degrees of phase a frame), and
// its resting spin (degrees a frame).
#macro CHAKRAM_HOLD_X 170
#macro CHAKRAM_HOLD_Y 40
#macro CHAKRAM_BOB 6
#macro CHAKRAM_BOB_RATE 3
#macro CHAKRAM_HOLD_SPIN 2.5

// While it waits, a ring loops once round him, as if round a level circle
// seen from a little above: out from its resting place, behind him, across
// the other side and in front, and home again, arriving back at rest just as
// its wind-up starts, so every throw leaves from where and when it would
// anyway (`chakram_loop_step`). The loop goes anticlockwise as seen from
// above the field. A wait shorter than `LOOP_MIN` frames is spent at rest.
//
// The depth is faked: at the far side a ring is `LOOP_TILT` pixels higher,
// smaller by `LOOP_DEPTH` of its size and dimmed by `LOOP_DIM`, and in front
// as much lower and larger, easing between with the sine of its angle. On
// the far half it is behind him, so he hides it, and it neither hurts nor
// blocks the player's fire (the ring's `behind`).
#macro CHAKRAM_LOOP_TILT 30
#macro CHAKRAM_LOOP_DEPTH 0.2
#macro CHAKRAM_LOOP_DIM 0.55
#macro CHAKRAM_LOOP_MIN 90

// The attack frame the first throw leaves on. Its wind-up starts
// `CHAKRAM_WIND` frames before, and only once the rings have formed
// (`RING_FORM` frames).
#macro CHAKRAM_FIRST 100

// After the first, the rings take turns, one out at a time: a ring is let go
// a gap after the other is back in his hand. The gap starts at `GAP0` frames
// and shrinks steadily to `GAP1` by attack frame `GAP_RAMP`, so the throws
// start spaced out and come gradually faster. A ring's wind-up never starts
// sooner than `HOLD_MIN` frames after its own catch.
#macro CHAKRAM_GAP0 100
#macro CHAKRAM_GAP1 50
#macro CHAKRAM_GAP_RAMP 1200
#macro CHAKRAM_HOLD_MIN 20

// ---------------------------------------------------------------------------
// The wind-up and the throw
// ---------------------------------------------------------------------------

// Frames of wind-up. The ring draws back `CHAKRAM_PULL` pixels directly away
// from the player (quickly, then settling into the full draw) and starts to
// spin up (`chakram_wind_spin`). It follows the player until `CHAKRAM_LOCK`
// frames before the release, when the aim stops following: its lane flashes
// for `CHAKRAM_LANE_T` frames (`ring_lane_flash`) and the band glows
// (`ring_charge`) until it flashes at the release.
#macro CHAKRAM_WIND 65
#macro CHAKRAM_PULL 70
#macro CHAKRAM_LOCK 45
#macro CHAKRAM_LANE_T 22

// The throw takes `FLY_K` times the square root of its length in frames, so
// a longer throw is faster as well as longer. Its speed rises steeply from
// nothing to a peak a quarter of the way through, about twice its average,
// then brakes smoothly to nothing at the stop (`chakram_throw_ease`).
#macro CHAKRAM_FLY_K 1.2

// How far short of the edge of the field the outside of the metal stops.
#macro CHAKRAM_SHORT 48

// ---------------------------------------------------------------------------
// The rope
// ---------------------------------------------------------------------------

/// @desc How the rope is woven and comes apart; one struct, so the whole look
///       is tuned in one place. See `chakram_bead` for how each field is
///       used.
function chakram_rope_style() {
    static _st = {
        // The look. `scale` is drawn size and the hitbox shrinks with it.
        // `depth`, if above 0, draws each bead smaller the further round the
        // back of the helix it is, down to this share of `scale` at the very
        // back (for round shapes). Strand `i` wears `cols[i]`.
        shape: BSHAPE_ORB,
        scale: 0.9,
        depth: 0.65,
        cols: [BCOL_GOLD, BCOL_BONE, BCOL_AMBER],
        // If `back_shape` is a shape (not -1), a bead round the back of the
        // helix is that shape at `back_scale` instead, lying as it likes.
        back_shape: -1,
        back_scale: 1.0,

        // The weave. Beads are laid along the ring's path, one per strand
        // every `gap` pixels of travel, each strand's a share of a gap on from
        // the one before. The strands cross from side to side `amp` pixels
        // either side of the path, each bead `step` degrees further round the
        // helix than the one before, the strands evenly spaced round it, and
        // the helix turns the way the ring spins. With `front`, a bead is
        // only laid where its strand passes in front, so the strands go over
        // and under. With `align`, a bead lies along its strand while the rope
        // is still, then swings to its heading over `unfurl` frames as it lets
        // go; otherwise it points along its heading from the start.
        strands: 2,
        gap: 10,
        amp: 14,
        step: 30,
        front: false,
        align: false,
        unfurl: 20,

        // Coming apart. A bead's heading starts square to the path (strands
        // evenly round) and turns `turn` degrees further with each bead down
        // the rope. Each bead sits still for `hold` frames after its warning
        // mark (`delay` frames) goes live, then gains `acc` a frame up to
        // `max`, so the rope unweaves from the end it was started at.
        turn: 12,
        hold: 45,
        acc: 0.03,
        max: 3.4,
        delay: 12,

        // With `bloom` at 0 or above, the heading and speed come from the
        // helix instead of `turn`: each bead leaves the way its strand bulges
        // there, sideways by the sine of its angle round the helix and along
        // the path by `bloom` times the cosine, at a speed (and gain) scaled
        // by that vector's length (never below `bloom_min` of it). Every bead
        // reaches its top speed together, so the helix swells keeping its
        // shape. `curl` then bends every heading this many degrees a frame,
        // the way the ring spins, for `curl_t` frames after it lets go.
        bloom: 0.35,
        bloom_min: 0.5,
        curl: 0,
        curl_t: 40,
    };
    return _st;
}

// ---------------------------------------------------------------------------
// The spin and the spray
// ---------------------------------------------------------------------------

// Frames the ring stays out, from the stop to the pullback.
#macro CHAKRAM_DWELL 26

// The spin (degrees a frame). As a yo-yo's does, it keeps building from the
// throw until the pullback, gaining `SPIN_GAIN` every frame and passing
// `SPIN_STOP` as the ring stops (`chakram_spin_at`). A longer throw is let go
// spinning slower, so every ring stops at the same spin and sprays the same.
#macro CHAKRAM_SPIN_STOP 15
#macro CHAKRAM_SPIN_GAIN 0.2

// The spray: for `SPRAY_T` frames after the stop, every `SPRAY_EVERY`
// frames, `SPRAY_ARMS` bullets evenly round the rim, each leaving straight
// out. The arms turn the way the ring does at `SPRAY_TWIST` of its spin, so
// they curl into a pinwheel, and alternate colours.
#macro CHAKRAM_SPRAY_T 24
#macro CHAKRAM_SPRAY_EVERY 2
#macro CHAKRAM_SPRAY_ARMS 6
#macro CHAKRAM_SPRAY_TWIST 0.25
#macro CHAKRAM_SPRAY_SPD 4.5
#macro CHAKRAM_SPRAY_DELAY 6
#macro CHAKRAM_SPRAY_SHAPE BSHAPE_NOVA
#macro CHAKRAM_SPRAY_COL_A BCOL_EMBER
#macro CHAKRAM_SPRAY_COL_B BCOL_AMBER

// ---------------------------------------------------------------------------
// The pullback
// ---------------------------------------------------------------------------

// The pullback takes `BACK_K` times the square root of the way home in
// frames. Like the throw it sets off hard and brakes, into his hand, carrying
// past its resting place and settling back; `CATCH_OVER` sets how far past
// (`chakram_back_ease`). The spin falls back to the resting spin on the way.
#macro CHAKRAM_BACK_K 1.4
#macro CHAKRAM_CATCH_OVER 2

// ---------------------------------------------------------------------------
// The attack
// ---------------------------------------------------------------------------

/// @desc **Chakram Blitz.** The two rings' states are kept in a static, since
///       pooled rings are reused (`ring_valid`).
function mika_chakram_blitz(_e, _g, _t) {
    static blitz = undefined;
    if (_t == 0 || blitz == undefined) {
        blitz = [chakram_state(0), chakram_state(1)];
        for (var _i = 0; _i < 2; _i++) {
            var _s = blitz[_i];
            chakram_ring_new(_s, chakram_rest_x(_s, _e),
                             chakram_rest_y(_s, _e, _t));
        }
    }
    chakram_step(blitz[0], blitz[1], _e, _g, _t);
    chakram_step(blitz[1], blitz[0], _e, _g, _t);
}

/// @desc A ring's state. Ring 0 rests on Mika's left and spins clockwise;
///       ring 1 rests on his right and spins anticlockwise.
function chakram_state(_i) {
    return {
        idx: _i,
        side: (_i == 0) ? -1 : 1,
        way: (_i == 0) ? -1 : 1,        // +1 is anticlockwise on screen
        ring: undefined,
        gen: -1,
        at: { x: 0, y: 0 },             // the anchor the ring rides
        mode: ChakramMode.Hold,
        t: 0,                           // frames in this mode
        thrown: false,                  // thrown at least once this attack
        ang: 0,
        spin: CHAKRAM_HOLD_SPIN,
        loop: 0, loop_w: 0,             // how far round its loop, how fast
        loop_to: 0,                     // ...and where this loop ends
        x0: 0, y0: 0,                   // where the throw or return began
        lx: 0, ly: 0,                   // where the throw will leave from
        dir: 0, dist: 0,                // the throw: heading and length
        locked: false,                  // the aim has stopped following
        fly: 0,                         // frames the throw takes
        k: 0,                           // distance along the throw
        bead: 0, beads: 0,              // beads laid, and in the whole rope
        a0: 0,                          // its angle as it stopped
        turned: 0,                      // degrees turned since stopping
    };
}

/// @desc Where ring `_s` rests beside Mika at attack frame `_t`, bob
///       included.
function chakram_rest_x(_s, _e) {
    return _e.x + _s.side * CHAKRAM_HOLD_X;
}

function chakram_rest_y(_s, _e, _t) {
    return _e.y + CHAKRAM_HOLD_Y
           + CHAKRAM_BOB * dsin(_t * CHAKRAM_BOB_RATE + _s.idx * 180);
}

// ---------------------------------------------------------------------------
// The loop while it waits
// ---------------------------------------------------------------------------

/// @desc Ring `_s`'s angle round its loop, degrees anticlockwise from his
///       right: its resting side, plus how far round it has gone.
function chakram_loop_ang(_s) {
    return ((_s.idx == 0) ? 180 : 0) + _s.loop;
}

/// @desc Where resting ring `_s` is on its loop at attack frame `_t`: the
///       level circle through its resting place, seen from a little above,
///       so the far side is higher and the near side lower.
function chakram_loop_x(_s, _e) {
    return _e.x + CHAKRAM_HOLD_X * dcos(chakram_loop_ang(_s));
}

function chakram_loop_y(_s, _e, _t) {
    return chakram_rest_y(_s, _e, _t)
           - CHAKRAM_LOOP_TILT * dsin(chakram_loop_ang(_s));
}

/// @desc One frame of resting ring `_s`'s loop, re-planned every frame so it
///       ends at rest (`loop_to`) as its wind-up starts (`chakram_wind_in`):
///       a cubic from where it is (`loop`, turning at `loop_w`) that arrives
///       with no turn left, in the frames there are.
function chakram_loop_step(_s, _o, _t) {
    var _r = chakram_wind_in(_s, _o, _t);
    if (_r < 1) {
        _s.loop = _s.loop_to;
        _s.loop_w = 0;
        return;
    }
    var _d = _s.loop_to - _s.loop;
    var _qa = (3 * _d / _r - 2 * _s.loop_w) / _r;
    var _qb = (_s.loop_w * _r - 2 * _d) / (_r * _r * _r);
    _s.loop += _s.loop_w + _qa + _qb;
    _s.loop_w += 2 * _qa + 3 * _qb;
}

/// @desc Frames until resting ring `_s`'s wind-up starts, given the other
///       ring `_o`. When `_o` goes first (its first throw is still to come, it
///       is winding up, or it is resting and has rested longer), that is
///       after `_o`'s whole throw and the gap; otherwise it is `_s`'s own
///       `chakram_throw_in`, whose answer while it has to wait is not a time.
function chakram_wind_in(_s, _o, _t) {
    var _o_in = -1;
    if (_o.mode == ChakramMode.Wind) {
        _o_in = CHAKRAM_WIND - _o.t;
    } else if (_o.mode == ChakramMode.Hold) {
        if (!_o.thrown && _o.idx == 0) {
            _o_in = max(0, CHAKRAM_FIRST - _t);
        } else if (_s.thrown || _s.idx == 1) {
            if (_o.t > _s.t || (_o.t == _s.t && _o.idx < _s.idx)) {
                _o_in = chakram_throw_in(_o, _s, _t);
            }
        }
    }
    if (_o_in < 0) return chakram_throw_in(_s, _o, _t) - CHAKRAM_WIND;
    return _o_in + chakram_fly_frames(_o.dist) + CHAKRAM_DWELL
           + chakram_back_frames(_o.dist) + chakram_gap(_t) - CHAKRAM_WIND;
}

/// @desc Put ring `_s` down at (`_x`, `_y`), resting.
function chakram_ring_new(_s, _x, _y) {
    _s.at.x = _x;
    _s.at.y = _y;
    _s.mode = ChakramMode.Hold;
    _s.t = 0;
    var _r = ring_new(_x, _y, MIKA_RING_COL, 0);
    _s.ring = _r;
    _s.gen = (_r == undefined) ? -1 : _r.gen;
    if (_r != undefined) ring_attach(_r, _s.at, 0, 0);
}

/// @desc One frame of ring `_s` (`_o` is the other ring). Runs before
///       `ring_step`, which moves the ring onto its anchor.
function chakram_step(_s, _o, _e, _g, _t) {
    var _hx = chakram_rest_x(_s, _e);
    var _hy = chakram_rest_y(_s, _e, _t);

    // A ring the pool refused is put back in his hand.
    if (!ring_valid(_s.ring, _s.gen)) {
        chakram_ring_new(_s, _hx, _hy);
        if (!ring_valid(_s.ring, _s.gen)) return;
    }

    var _u = 0;
    switch (_s.mode) {
        case ChakramMode.Hold:
            chakram_aim_from_rest(_s, _hx, _hy, _g.player);
            // A loop round him, if the wait is long enough for one.
            if (_s.t == 0) {
                _s.loop = 0;
                _s.loop_w = 0;
                _s.loop_to = (chakram_wind_in(_s, _o, _t) >= CHAKRAM_LOOP_MIN)
                    ? 360 : 0;
            }
            chakram_loop_step(_s, _o, _t);
            _s.at.x = chakram_loop_x(_s, _e);
            _s.at.y = chakram_loop_y(_s, _e, _t);
            _s.spin = CHAKRAM_HOLD_SPIN;
            if (chakram_throw_in(_s, _o, _t) <= CHAKRAM_WIND
                && ring_solid(_s.ring)) {
                _s.mode = ChakramMode.Wind;
                _s.t = 0;
                _s.locked = false;
            } else {
                _s.t++;
            }
            break;

        case ChakramMode.Wind:
            _s.t++;
            if (!_s.locked) {
                chakram_aim_from_rest(_s, _hx, _hy, _g.player);
                // The aim locks, the lane flashes and the band starts to
                // glow; the glow runs out, with its flash, as the ring is let
                // go.
                if (_s.t >= CHAKRAM_WIND - CHAKRAM_LOCK) {
                    _s.locked = true;
                    ring_lane_flash(_s.ring, _s.lx, _s.ly, _s.dir, _s.dist,
                                    CHAKRAM_LANE_T);
                    ring_charge(_s.ring, CHAKRAM_LOCK, 1);
                }
            }
            // Drawn back towards where the throw leaves from, which holds
            // still once the aim has locked.
            _u = clamp(_s.t / CHAKRAM_WIND, 0, 1);
            var _draw = 1 - power(1 - _u, 3);
            _s.at.x = lerp(_hx, _s.lx, _draw);
            _s.at.y = lerp(_hy, _s.ly, _draw);
            _s.spin = chakram_wind_spin(_s, _u);
            if (_s.t >= CHAKRAM_WIND) chakram_release(_s);
            break;

        case ChakramMode.Out:
            _s.t++;
            _s.k = _s.dist * chakram_throw_ease(min(1, _s.t / _s.fly));
            _s.at.x = _s.x0 + lengthdir_x(_s.k, _s.dir);
            _s.at.y = _s.y0 + lengthdir_y(_s.k, _s.dir);
            _s.spin = chakram_spin_at(_s.t - _s.fly);
            var _st = chakram_rope_style();
            while (_s.bead < _s.beads && _s.bead * _st.gap <= _s.k) {
                for (var _j = 0; _j < _st.strands; _j++) {
                    chakram_bead(_st, _s.x0, _s.y0, _s.dir, _s.way, _s.bead,
                                 _j);
                }
                _s.bead++;
            }
            if (_s.t >= _s.fly) chakram_stop(_s);
            break;

        case ChakramMode.Spray:
            _s.t++;
            _s.spin = chakram_spin_at(_s.t);
            if (_s.t >= CHAKRAM_DWELL) {
                _s.mode = ChakramMode.Back;
                _s.t = 0;
                _s.x0 = _s.at.x;
                _s.y0 = _s.at.y;
            }
            break;

        case ChakramMode.Back:
            _s.t++;
            var _back = chakram_back_frames(_s.dist);
            _u = clamp(_s.t / _back, 0, 1);
            var _w = chakram_back_ease(_u);
            _s.at.x = lerp(_s.x0, _hx, _w);
            _s.at.y = lerp(_s.y0, _hy, _w);
            _s.spin = lerp(chakram_spin_at(CHAKRAM_DWELL), CHAKRAM_HOLD_SPIN,
                           _u);
            if (_s.t >= _back) {
                _s.mode = ChakramMode.Hold;
                _s.t = 0;
                sfx(Sfx.WardClose);
                fx_flash_at(_hx, _hy, global.bullet_colour[MIKA_RING_COL],
                            0.15);
            }
            break;
    }

    // The ring's turn is set here rather than by `ring_step`, so the spray
    // follows the drawn ring.
    _s.ang += _s.way * _s.spin;
    _s.ring.ang = _s.ang;
    _s.ring.spin = 0;

    // Its depth on the loop: 1 at the far side, -1 in front, 0 at his flanks,
    // where the loop starts and ends (with a margin, since the sine of 180 is
    // not quite 0), so a ring at rest or in play is as it always was.
    var _far = (_s.mode == ChakramMode.Hold) ? dsin(chakram_loop_ang(_s)) : 0;
    if (abs(_far) < 0.001) _far = 0;
    _s.ring.depth = 1 - CHAKRAM_LOOP_DEPTH * _far;
    _s.ring.shade = CHAKRAM_LOOP_DIM * max(0, _far);
    _s.ring.behind = (_far > 0);

    if (_s.mode == ChakramMode.Spray) chakram_spray(_s);
}

/// @desc A thrown ring's spin (degrees a frame) `_tau` frames after it stops,
///       negative while in flight: one straight rise through `SPIN_STOP` at
///       the stop.
function chakram_spin_at(_tau) {
    return CHAKRAM_SPIN_STOP + CHAKRAM_SPIN_GAIN * _tau;
}

/// @desc Ring `_s`'s spin at share `_u` (0 to 1) of its wind-up: from its
///       resting spin to the spin it is let go with, arriving already gaining
///       at the steady rate the throw keeps (`chakram_spin_at`), so the spin-up
///       never pauses at the release. It is a cubic with no gain at the start
///       and that rate at the end; the throw's length is this frame's aim.
function chakram_wind_spin(_s, _u) {
    var _d = chakram_spin_at(-chakram_fly_frames(_s.dist)) - CHAKRAM_HOLD_SPIN;
    var _k = 0;
    if (abs(_d) > 0.01) {
        _k = clamp(CHAKRAM_WIND * CHAKRAM_SPIN_GAIN / _d, 0, 3);
    }
    return CHAKRAM_HOLD_SPIN + _d * _u * _u * ((3 - _k) + (_k - 2) * _u);
}

/// @desc The throw's share of its length at `_u` (0 to 1) of its time. Its
///       speed goes as u(1 - u)^3: zero at both ends, rising steeply to a
///       peak at a quarter of the way through and braking smoothly after.
function chakram_throw_ease(_u) {
    var _v = 1 - _u;
    return 1 - _v * _v * _v * _v * (1 + 4 * _u);
}

/// @desc The pullback's share of the way home at `_u` (0 to 1): the throw's
///       ease, plus a bump that carries it past its resting place late in the
///       trip and back. Both terms start and end with zero speed.
function chakram_back_ease(_u) {
    return chakram_throw_ease(_u)
           + CHAKRAM_CATCH_OVER * _u * _u * _u * (1 - _u) * (1 - _u);
}

// ---------------------------------------------------------------------------
// The throw
// ---------------------------------------------------------------------------

/// @desc Aim a resting or winding ring at the player: the heading from its
///       resting place, and the throw measured from where the full draw puts
///       it (`lx`, `ly`).
function chakram_aim_from_rest(_s, _hx, _hy, _p) {
    var _dir = aim_at(_hx, _hy, _p.x, _p.y);
    _s.lx = _hx - lengthdir_x(CHAKRAM_PULL, _dir);
    _s.ly = _hy - lengthdir_y(CHAKRAM_PULL, _dir);
    chakram_aim(_s, _s.lx, _s.ly, _dir);
}

/// @desc Aim ring `_s` from (`_x`, `_y`) at `_dir` degrees: how far its centre
///       travels before the metal comes within `CHAKRAM_SHORT` of the edge of
///       the field (`dist`).
function chakram_aim(_s, _x, _y, _dir) {
    var _b = RING_R + RING_BAND_HALF + CHAKRAM_SHORT;
    var _dx = lengthdir_x(1, _dir);
    var _dy = lengthdir_y(1, _dir);
    var _best = 100000;

    if (_dx > 0.0001) {
        _best = min(_best, (FIELD_X1 - _b - _x) / _dx);
    } else if (_dx < -0.0001) {
        _best = min(_best, (FIELD_X0 + _b - _x) / _dx);
    }
    if (_dy > 0.0001) {
        _best = min(_best, (FIELD_Y1 - _b - _y) / _dy);
    } else if (_dy < -0.0001) {
        _best = min(_best, (FIELD_Y0 + _b - _y) / _dy);
    }

    _s.dir = _dir;
    _s.dist = max(0, _best);
}

/// @desc Frames a throw of `_dist` pixels takes.
function chakram_fly_frames(_dist) {
    return max(1, ceil(CHAKRAM_FLY_K * sqrt(max(0, _dist))));
}

/// @desc Frames the pullback after a throw of `_dist` pixels takes: the way
///       home is the throw and the draw.
function chakram_back_frames(_dist) {
    return max(1, ceil(CHAKRAM_BACK_K * sqrt(max(0, _dist) + CHAKRAM_PULL)));
}

/// @desc Let go of a wound-up ring down the line it was last aimed along.
function chakram_release(_s) {
    _s.mode = ChakramMode.Out;
    _s.t = 0;
    _s.x0 = _s.at.x;
    _s.y0 = _s.at.y;
    _s.thrown = true;
    _s.k = 0;
    _s.fly = chakram_fly_frames(_s.dist);
    _s.bead = 0;
    _s.beads = floor(_s.dist / chakram_rope_style().gap) + 1;
    sfx(Sfx.WardScatter);
}

/// @desc The frame the ring comes to rest at the end of its throw, with a
///       soft flash and a pulse off the metal as the spray starts.
function chakram_stop(_s) {
    _s.mode = ChakramMode.Spray;
    _s.t = 0;
    _s.x0 = _s.at.x;
    _s.y0 = _s.at.y;
    _s.a0 = _s.ang;
    _s.turned = 0;
    var _col = global.bullet_colour[MIKA_RING_COL];
    fx_flash_at(_s.at.x, _s.at.y, _col, 0.2);
    fx_ring(_s.at.x, _s.at.y, RING_R, RING_R * 1.4, 14, _col, 0.6);
    sfx(Sfx.WardBurst);
}

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

/// @desc Frames until ring `_s` is back in Mika's hand. A resting ring
///       answers minus how long it has rested.
function chakram_home_in(_s) {
    switch (_s.mode) {
        case ChakramMode.Wind:
            return CHAKRAM_WIND - _s.t + chakram_fly_frames(_s.dist)
                   + CHAKRAM_DWELL + chakram_back_frames(_s.dist);
        case ChakramMode.Out:
            return _s.fly - _s.t + CHAKRAM_DWELL
                   + chakram_back_frames(_s.dist);
        case ChakramMode.Spray:
            return CHAKRAM_DWELL - _s.t + chakram_back_frames(_s.dist);
        case ChakramMode.Back:
            return chakram_back_frames(_s.dist) - _s.t;
    }
    return -_s.t;
}

/// @desc Frames until resting ring `_s` is let go (its wind-up starts
///       `CHAKRAM_WIND` before), given the other ring `_o` and the attack
///       frame `_t`. Needs this frame's aim.
function chakram_throw_in(_s, _o, _t) {
    // Ring 0 opens; after that neither ring goes again until the other has
    // been thrown once.
    if (!_s.thrown && _s.idx == 0) return CHAKRAM_FIRST - _t;
    if (!_o.thrown) return CHAKRAM_WIND + 1;

    var _rest = _s.thrown ? CHAKRAM_HOLD_MIN + CHAKRAM_WIND - _s.t : 0;

    // With both resting, the one that has rested longer goes next.
    if (_o.mode == ChakramMode.Hold
        && (_o.t > _s.t || (_o.t == _s.t && _o.idx < _s.idx))) {
        return CHAKRAM_WIND + 1;
    }

    // Let go the gap after the other ring is caught (`chakram_home_in` of a
    // resting ring is minus how long it has rested).
    return max(_rest, chakram_home_in(_o) + chakram_gap(_t));
}

/// @desc The gap between one ring's catch and the next throw at attack frame
///       `_t`.
function chakram_gap(_t) {
    return lerp(CHAKRAM_GAP0, CHAKRAM_GAP1, min(1, _t / CHAKRAM_GAP_RAMP));
}

// ---------------------------------------------------------------------------
// The rope
// ---------------------------------------------------------------------------

/// @desc Lay bead `_k` of strand `_strand` of a rope in style `_st`
///       (`chakram_rope_style`), started at (`_x0`, `_y0`) and running `_dir`,
///       its helix turning `_way` (+1 or -1). It is placed on the path, not
///       on the ring, so beads are evenly spaced whatever the ring's speed.
function chakram_bead(_st, _x0, _y0, _dir, _way, _k, _strand) {
    // Each strand sits a share of a bead on, so crossings don't stack.
    var _n = _k + _strand / _st.strands;
    var _phi = _way * _n * _st.step + _strand * 360 / _st.strands;
    // +1 where the strand passes nearest the viewer, -1 at the back.
    var _near = dcos(_phi);
    if (_st.front && _near < 0) return;

    var _along = _n * _st.gap;
    var _side = _st.amp * dsin(_phi);
    var _x = _x0 + lengthdir_x(_along, _dir) + lengthdir_x(_side, _dir + 90);
    var _y = _y0 + lengthdir_y(_along, _dir) + lengthdir_y(_side, _dir + 90);

    var _head = _dir + 90 + _way * _n * _st.turn + _strand * 360 / _st.strands;
    var _gain = 1;
    if (_st.bloom >= 0) {
        var _va = _st.bloom * _near;
        var _vl = dsin(_phi);
        _head = _dir + darctan2(_vl, _va);
        _gain = max(_st.bloom_min, point_distance(0, 0, _va, _vl));
    }
    var _shape = _st.shape;
    var _sc = _st.scale;
    var _align = _st.align;
    if (_st.back_shape >= 0 && _near < 0) {
        _shape = _st.back_shape;
        _sc = _st.back_scale;
        _align = false;
    }
    if (_st.depth > 0) _sc *= lerp(_st.depth, 1, (_near + 1) * 0.5);

    // Lying along the strand: the slope of the strand's sine here.
    var _rest = _head;
    if (_align) {
        _rest = _dir + darctan(_st.amp * _near * _way * _st.step * pi / 180
                               / _st.gap);
    }

    var _u = fire(_x, _y, 0, _rest, _shape,
                  _st.cols[_strand mod array_length(_st.cols)], _st.delay);
    if (_u == undefined) return;
    _u.scale = _sc;
    _u.r = global.bshape_radius[_shape] * _sc;

    bullet_accel_at(_u, _st.hold, _st.acc * _gain, _st.max * _gain);
    var _curl_at = _st.hold;
    if (_align) {
        bullet_turn_at(_u, _st.hold,
                       angle_difference(_head, _rest) / max(1, _st.unfurl));
        bullet_turn_at(_u, _st.hold + _st.unfurl, 0);
        _curl_at += _st.unfurl;
    }
    if (_st.curl != 0) {
        bullet_turn_at(_u, _curl_at, _way * _st.curl);
        bullet_turn_at(_u, _curl_at + _st.curl_t, 0);
    }
}

// ---------------------------------------------------------------------------
// The spray
// ---------------------------------------------------------------------------

/// @desc One frame at rest: every `SPRAY_EVERY` frames for `SPRAY_T` frames,
///       a bullet from each arm, straight out from the rim. The arms start
///       at the angle the ring stopped at and turn with it at `SPRAY_TWIST`
///       of its spin.
function chakram_spray(_s) {
    _s.turned += _s.spin;
    if (_s.t > CHAKRAM_SPRAY_T || (_s.t - 1) mod CHAKRAM_SPRAY_EVERY != 0) {
        return;
    }
    var _a0 = _s.a0 + _s.way * _s.turned * CHAKRAM_SPRAY_TWIST;
    for (var _i = 0; _i < CHAKRAM_SPRAY_ARMS; _i++) {
        var _a = _a0 + _i * (360 / CHAKRAM_SPRAY_ARMS);
        var _col = ((_i mod 2) == 0) ? CHAKRAM_SPRAY_COL_A
                                     : CHAKRAM_SPRAY_COL_B;
        var _u = fire(_s.at.x + lengthdir_x(RING_R, _a),
                      _s.at.y + lengthdir_y(RING_R, _a),
                      CHAKRAM_SPRAY_SPD, _a, CHAKRAM_SPRAY_SHAPE, _col,
                      CHAKRAM_SPRAY_DELAY);
        if (_u == undefined) break;
    }
}
