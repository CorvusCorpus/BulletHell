/// @desc **Chakram Blitz**, Mika's S2.
///
/// The owner's brief: Mika throws a ring at the player. It lays a trail
/// woven like a braided rope (a tight double helix) that starts stationary and
/// then slowly spreads, each bead's heading a step on from the last so the
/// rope comes apart evenly. At the edge of the field the ring spins up in
/// place against the wall and fires several evenly spaced radial bursts, tied
/// to the ring's own turn so the pattern can be read, then flies
/// back to him. He has two rings and alternates them, so one comes home about
/// when the other has hit the wall and begun to spin. The throws start spaced
/// out and come gradually faster until they reach that rhythm. The
/// rings move with weight: a wind-up before each throw, a launch that picks up
/// speed, a recoil off the wall, and a return that eases off the wall and
/// overshoots into his hand.
///
/// Both are ordinary rings (they hurt to touch and block shots), each riding
/// an anchor this attack moves, so `ring_step` places them. Mika himself fires
/// nothing.
///
/// Every number here is a first guess, waiting on playtesting.

enum ChakramMode {
    Hold,       // resting beside Mika
    Wind,       // drawing back before a throw
    Out,        // thrown, flying to the wall
    Grind,      // spinning up against the wall, bursting
    Back,       // flying home
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

// The attack frame the first throw leaves on. Its wind-up starts
// `CHAKRAM_WIND` frames before; the rings take `RING_FORM` frames to form.
#macro CHAKRAM_FIRST 90

// After the first, a ring is thrown so that it reaches the wall a lag after
// the other ring is caught. The lag starts at `LAG0` frames and shrinks
// steadily to nothing by attack frame `LAG_RAMP`, so the throws come
// gradually faster until each lands as the other ring is caught. A ring's
// wind-up never starts sooner than `HOLD_MIN` frames after its own catch.
#macro CHAKRAM_LAG0 110
#macro CHAKRAM_LAG_RAMP 720
#macro CHAKRAM_HOLD_MIN 20

// ---------------------------------------------------------------------------
// The wind-up and the throw
// ---------------------------------------------------------------------------

// Frames of wind-up. The ring draws back `CHAKRAM_PULL` pixels directly away
// from the player (quickly, then settling into the full draw), spins up to
// its flying spin, and its band glows (`ring_charge`) until it flashes at the
// release.
#macro CHAKRAM_WIND 45
#macro CHAKRAM_PULL 70

// Launch speed, gained a frame, and top speed (pixels a frame); spin in
// flight (degrees a frame).
#macro CHAKRAM_V0 1.0
#macro CHAKRAM_ACC 0.6
#macro CHAKRAM_VMAX 14
#macro CHAKRAM_FLY_SPIN 12

// How far the metal bites into the wall: the centre stops this much closer
// than `RING_R` to the edge of the field.
#macro CHAKRAM_BITE 8

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
// The grind
// ---------------------------------------------------------------------------

// Frames against the wall. The spin rises from the flying spin to
// `GRIND_SPIN`, slowly at first.
#macro CHAKRAM_GRIND 110
#macro CHAKRAM_GRIND_SPIN 24

// The impact: the ring hops `RECOIL` pixels back off the wall and reseats
// over `RECOIL_T` frames. While grinding it rattles along the wall by up to
// `RATTLE` pixels, more as the spin rises.
#macro CHAKRAM_RECOIL 18
#macro CHAKRAM_RECOIL_T 14
#macro CHAKRAM_RATTLE 2.5

// A burst is `BURST_N` bullets evenly round the full circle of the ring,
// each leaving the rim straight out from the centre. The ring bursts once it
// has turned `BURST_FIRST` degrees against the wall, then every further
// `BURST_TURN` degrees, so the bursts come faster as it spins up. Each burst
// is laid at the angle the ring had reached, so with `BURST_TURN` a whole
// turn plus half the gap between bullets, each burst falls in the gaps of the
// one before.
#macro CHAKRAM_BURST_N 24
#macro CHAKRAM_BURST_FIRST 540
#macro CHAKRAM_BURST_TURN 367.5
#macro CHAKRAM_BURST_SPD 3.8

// Warning-mark delay and the look; the colour alternates burst by burst.
// Scale is drawn size; the hitbox shrinks with it.
#macro CHAKRAM_BURST_DELAY 6
#macro CHAKRAM_BURST_SHAPE BSHAPE_MOTE
#macro CHAKRAM_BURST_SCALE 1.65
#macro CHAKRAM_BURST_COL_A BCOL_EMBER
#macro CHAKRAM_BURST_COL_B BCOL_AMBER

// ---------------------------------------------------------------------------
// The return
// ---------------------------------------------------------------------------

// Frames from the wall back to his hand. It leaves the wall slowly, speeds
// up, carries past its resting place and settles back; `CATCH_OVER` sets how
// far past (about 1% of the trip per unit). The spin falls back to the
// resting spin on the way.
#macro CHAKRAM_BACK 64
#macro CHAKRAM_CATCH_OVER 5

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
        x0: 0, y0: 0,                   // where the throw or return began
        dir: 0, dist: 0,                // the throw: heading and length
        nx: 0, ny: -1,                  // the wall it meets, inward normal
        fly: 0,                         // frames the throw takes
        v: 0, k: 0,                     // speed and distance along the throw
        bead: 0, beads: 0,              // beads laid, and in the whole rope
        turned: 0,                      // degrees turned against the wall
        burst_at: 0,                    // ...at which it next bursts
        bursts: 0,                      // bursts this grind, for colours
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
            _s.at.x = _hx;
            _s.at.y = _hy;
            chakram_aim_from_rest(_s, _hx, _hy, _g.player);
            _s.spin = CHAKRAM_HOLD_SPIN;
            if (chakram_throw_in(_s, _o, _t) <= CHAKRAM_WIND
                && ring_solid(_s.ring)) {
                _s.mode = ChakramMode.Wind;
                _s.t = 0;
            } else {
                _s.t++;
            }
            break;

        case ChakramMode.Wind:
            _s.t++;
            chakram_aim_from_rest(_s, _hx, _hy, _g.player);
            _u = clamp(_s.t / CHAKRAM_WIND, 0, 1);
            var _draw = 1 - power(1 - _u, 3);
            _s.at.x = _hx - lengthdir_x(CHAKRAM_PULL * _draw, _s.dir);
            _s.at.y = _hy - lengthdir_y(CHAKRAM_PULL * _draw, _s.dir);
            _s.spin = lerp(CHAKRAM_HOLD_SPIN, CHAKRAM_FLY_SPIN, _u * _u);
            // The glow runs out, with its flash, as the ring is let go.
            var _glow = max(1, CHAKRAM_WIND - RING_WARN);
            if (_s.t == _glow) {
                ring_charge(_s.ring, CHAKRAM_WIND - _glow, 1);
            }
            if (_s.t >= CHAKRAM_WIND) chakram_release(_s);
            break;

        case ChakramMode.Out:
            _s.t++;
            _s.v = min(_s.v + CHAKRAM_ACC, CHAKRAM_VMAX);
            _s.k = min(_s.k + _s.v, _s.dist);
            _s.at.x = _s.x0 + lengthdir_x(_s.k, _s.dir);
            _s.at.y = _s.y0 + lengthdir_y(_s.k, _s.dir);
            _s.spin = CHAKRAM_FLY_SPIN;
            var _st = chakram_rope_style();
            while (_s.bead < _s.beads && _s.bead * _st.gap <= _s.k) {
                for (var _j = 0; _j < _st.strands; _j++) {
                    chakram_bead(_st, _s.x0, _s.y0, _s.dir, _s.way, _s.bead,
                                 _j);
                }
                _s.bead++;
            }
            if (_s.k >= _s.dist) chakram_impact(_s);
            break;

        case ChakramMode.Grind:
            _s.t++;
            _u = clamp(_s.t / CHAKRAM_GRIND, 0, 1);
            _s.spin = lerp(CHAKRAM_FLY_SPIN, CHAKRAM_GRIND_SPIN, _u * _u);
            chakram_grind_place(_s, _u);
            if (_s.t >= CHAKRAM_GRIND) {
                _s.mode = ChakramMode.Back;
                _s.t = 0;
                _s.x0 = _s.at.x;
                _s.y0 = _s.at.y;
            }
            break;

        case ChakramMode.Back:
            _s.t++;
            _u = clamp(_s.t / CHAKRAM_BACK, 0, 1);
            var _w = chakram_back_ease(_u);
            _s.at.x = lerp(_s.x0, _hx, _w);
            _s.at.y = lerp(_s.y0, _hy, _w);
            _s.spin = lerp(CHAKRAM_GRIND_SPIN, CHAKRAM_HOLD_SPIN, _u);
            if (_s.t >= CHAKRAM_BACK) {
                _s.mode = ChakramMode.Hold;
                _s.t = 0;
                sfx(Sfx.WardClose);
                fx_flash_at(_hx, _hy, global.bullet_colour[MIKA_RING_COL],
                            0.15);
            }
            break;
    }

    // The ring's turn is set here rather than by `ring_step`, so the bursts
    // follow the drawn ring.
    _s.ang += _s.way * _s.spin;
    _s.ring.ang = _s.ang;
    _s.ring.spin = 0;

    if (_s.mode == ChakramMode.Grind) chakram_grind(_s);
}

/// @desc The return's share of the trip at `_u` (0 to 1): smootherstep, so it
///       leaves the wall slowly and arrives without a jolt, plus a bump that
///       carries it past its resting place late in the trip and back. Both
///       terms start and end with zero speed.
function chakram_back_ease(_u) {
    var _s = _u * _u * _u * (_u * (_u * 6 - 15) + 10);
    return _s + CHAKRAM_CATCH_OVER * _u * _u * _u * (1 - _u) * (1 - _u);
}

// ---------------------------------------------------------------------------
// The throw
// ---------------------------------------------------------------------------

/// @desc Aim a resting or winding ring at the player: the heading from its
///       resting place, and the throw measured from where the full draw puts
///       it.
function chakram_aim_from_rest(_s, _hx, _hy, _p) {
    var _dir = aim_at(_hx, _hy, _p.x, _p.y);
    chakram_aim(_s, _hx - lengthdir_x(CHAKRAM_PULL, _dir),
                _hy - lengthdir_y(CHAKRAM_PULL, _dir), _dir);
}

/// @desc Aim ring `_s` from (`_x`, `_y`) at `_dir` degrees: how far its centre
///       can travel before the metal meets the edge of the field (`dist`), and
///       that edge's inward normal (`nx`, `ny`).
function chakram_aim(_s, _x, _y, _dir) {
    var _b = RING_R - CHAKRAM_BITE;
    var _dx = lengthdir_x(1, _dir);
    var _dy = lengthdir_y(1, _dir);
    var _best = 100000;
    var _k = 0;
    _s.nx = 0;
    _s.ny = -1;

    if (_dx > 0.0001) {
        _k = (FIELD_X1 - _b - _x) / _dx;
        if (_k < _best) { _best = _k; _s.nx = -1; _s.ny = 0; }
    } else if (_dx < -0.0001) {
        _k = (FIELD_X0 + _b - _x) / _dx;
        if (_k < _best) { _best = _k; _s.nx = 1; _s.ny = 0; }
    }
    if (_dy > 0.0001) {
        _k = (FIELD_Y1 - _b - _y) / _dy;
        if (_k < _best) { _best = _k; _s.nx = 0; _s.ny = -1; }
    } else if (_dy < -0.0001) {
        _k = (FIELD_Y0 + _b - _y) / _dy;
        if (_k < _best) { _best = _k; _s.nx = 0; _s.ny = 1; }
    }

    _s.dir = _dir;
    _s.dist = max(0, _best);
}

/// @desc Frames a throw of `_dist` pixels takes, stepped exactly as the
///       `Out` mode steps it.
function chakram_fly_frames(_dist) {
    var _v = CHAKRAM_V0;
    var _k = 0;
    var _n = 0;
    do {
        _n++;
        _v = min(_v + CHAKRAM_ACC, CHAKRAM_VMAX);
        _k += _v;
    } until (_k >= _dist);
    return _n;
}

/// @desc Let go of a wound-up ring down the line it was last aimed along.
function chakram_release(_s) {
    _s.mode = ChakramMode.Out;
    _s.t = 0;
    _s.x0 = _s.at.x;
    _s.y0 = _s.at.y;
    _s.thrown = true;
    _s.v = CHAKRAM_V0;
    _s.k = 0;
    _s.fly = chakram_fly_frames(_s.dist);
    _s.bead = 0;
    _s.beads = floor(_s.dist / chakram_rope_style().gap) + 1;
    _s.spin = CHAKRAM_FLY_SPIN;
    sfx(Sfx.WardScatter);
}

/// @desc The frame the ring meets the wall.
function chakram_impact(_s) {
    _s.mode = ChakramMode.Grind;
    _s.t = 0;
    _s.x0 = _s.at.x;
    _s.y0 = _s.at.y;
    _s.turned = 0;
    _s.burst_at = CHAKRAM_BURST_FIRST;
    _s.bursts = 0;
    var _b = RING_R - CHAKRAM_BITE;
    fx_flash_at(_s.at.x - _s.nx * _b, _s.at.y - _s.ny * _b,
                global.bullet_colour[MIKA_RING_COL], 0.5);
    fx_burst(_s.at.x - _s.nx * _b, _s.at.y - _s.ny * _b, 12, 3, 9,
             global.bullet_colour[CHAKRAM_BURST_COL_A], 20, 10);
    fx_shake(8);
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
                   + CHAKRAM_GRIND + CHAKRAM_BACK;
        case ChakramMode.Out:
            return _s.fly - _s.t + CHAKRAM_GRIND + CHAKRAM_BACK;
        case ChakramMode.Grind:
            return CHAKRAM_GRIND - _s.t + CHAKRAM_BACK;
        case ChakramMode.Back:
            return CHAKRAM_BACK - _s.t;
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

    // Both resting, once both have been thrown, happens only after a lost
    // ring is put back: the one that has rested longer goes first.
    if (_s.thrown && _o.mode == ChakramMode.Hold) {
        if (_o.t > _s.t || (_o.t == _s.t && _o.idx < _s.idx)) {
            return CHAKRAM_WIND + 1;
        }
        return _rest;
    }

    // Reach the wall the lag after the other ring is caught.
    var _lag = CHAKRAM_LAG0 * max(0, 1 - _t / CHAKRAM_LAG_RAMP);
    return max(_rest, chakram_home_in(_o) + _lag
                      - chakram_fly_frames(_s.dist));
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
// The grind
// ---------------------------------------------------------------------------

/// @desc Where the grinding ring sits: at the wall, hopped back by the
///       recoil just after impact, and rattling along the wall.
function chakram_grind_place(_s, _u) {
    var _hop = 0;
    if (_s.t < CHAKRAM_RECOIL_T) {
        _hop = CHAKRAM_RECOIL * dsin(180 * _s.t / CHAKRAM_RECOIL_T);
    }
    var _rattle = CHAKRAM_RATTLE * _u * dsin(_s.t * 131);
    _s.at.x = _s.x0 + _s.nx * _hop - _s.ny * _rattle;
    _s.at.y = _s.y0 + _s.ny * _hop + _s.nx * _rattle;
}

/// @desc One frame of grinding: a shower of sparks (not bullets) where the
///       ring meets the wall, thrown the way the rim moves there, and a burst
///       each time the ring has turned far enough.
function chakram_grind(_s) {
    var _b = RING_R - CHAKRAM_BITE;
    var _along = point_direction(0, 0, -_s.nx, -_s.ny) + 90 * _s.way;
    fx_spark(_s.at.x - _s.nx * _b, _s.at.y - _s.ny * _b,
             _along + _s.way * random_range(0, 60), random_range(3, 9),
             global.bullet_colour[CHAKRAM_BURST_COL_A], 14, 8);

    _s.turned += _s.spin;
    if (_s.turned < _s.burst_at) return;
    // The ring's angle when it reached the mark (this frame's turn can carry
    // it a little past), so every burst sits exactly `BURST_TURN` on from the
    // last.
    chakram_burst(_s, _s.ang - _s.way * (_s.turned - _s.burst_at));
    _s.burst_at += CHAKRAM_BURST_TURN;
    _s.bursts++;
}

/// @desc One burst: bullets evenly round the full circle of the ring from
///       angle `_a0`, leaving the rim straight out.
function chakram_burst(_s, _a0) {
    var _col = ((_s.bursts mod 2) == 0) ? CHAKRAM_BURST_COL_A
                                        : CHAKRAM_BURST_COL_B;
    var _r = global.bshape_radius[CHAKRAM_BURST_SHAPE] * CHAKRAM_BURST_SCALE;
    for (var _i = 0; _i < CHAKRAM_BURST_N; _i++) {
        var _a = _a0 + _i * (360 / CHAKRAM_BURST_N);
        var _u = fire(_s.at.x + lengthdir_x(RING_R, _a),
                      _s.at.y + lengthdir_y(RING_R, _a),
                      CHAKRAM_BURST_SPD, _a, CHAKRAM_BURST_SHAPE, _col,
                      CHAKRAM_BURST_DELAY);
        if (_u == undefined) break;
        _u.scale = CHAKRAM_BURST_SCALE;
        _u.r = _r;
    }
    fx_flash_at(_s.at.x, _s.at.y, global.bullet_colour[_col], 0.3);
    fx_shake(3);
}
