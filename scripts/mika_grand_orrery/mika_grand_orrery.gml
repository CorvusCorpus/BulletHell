/// @desc **Grand Orrery**, Mika's S8 and his last spell.
///
/// The owner's brief: Mika holds the middle of the field and throws out all
/// six of his rings, which take up orbits round him at six radii, like a solar
/// system with him as its sun. They come out as his non-spells' rings do, and
/// keep clear of the bottom middle of the field while the spell sets up. They
/// are evenly spaced, all go round at the same rate, and each shows its orbit
/// as a line. Whenever two rings come close, a bolt strings between them,
/// more flavour than threat. It is a rage spell: the more damage he takes over
/// the attack, the more rings wake (lit up) and fire a pattern of their own,
/// so it grows harder as he nears defeat, as a Touhou Extra's last spell
/// does.
///
/// The rings wake from the inside out, one for each sixth of his health for
/// this attack, and all of them once 20 seconds are left on the clock (the
/// owner's call, so the attack can't be camped to a timeout). Each fires one
/// plain rule:
///   0 (gold)    the corona: a dashed spiral of sand thrown straight out from
///               him as it whirls round.
///   1 (cyan)    the pinwheel: three arms of grains from its middle, turning
///               with its spin, so they curl into a spiral as it goes.
///   2 (crimson) the comet: three comets with tails, thrown at the player.
///   3 (jade)    the halo: rings itself in grains, which hang round where it
///               was and then drift outward.
///   4 (azure)   the star: eight beams laid across the field from where it
///               is, an eighth of a turn apart, one aimed at the player.
///   5 (violet)  the burst: rings of darts in every direction from its
///               middle.
///
/// The rings ride Mika (`src`), at offsets this attack sets every frame from
/// closed forms of the frame, so nothing carries over between attempts. They
/// are ordinary rings: they hurt to touch, block shots, and their bolts
/// (`ring_link`) hurt as any arc does. Mika himself fires nothing.
///
/// Every number here is a first guess, waiting on playtesting.

// ---------------------------------------------------------------------------
// The orrery
// ---------------------------------------------------------------------------

#macro ORRERY_N 6

// Where he holds the field (the row's `at`).
#macro ORRERY_X FIELD_CX
#macro ORRERY_Y (FIELD_CY - 60)

// Ring k's orbit radius is `R0 + k * DR` (k = 0 is the innermost).
#macro ORRERY_R0 120
#macro ORRERY_DR 92

// Every ring goes round at this rate, degrees a frame: the even rings
// (0, 2, 4) anticlockwise and the odd ones clockwise (`orrery_way`), so
// neighbouring orbits pass each other.
#macro ORRERY_ORBIT 0.5

// ---- coming out -----------------------------------------------------------

// As in his non-spells' mill (`mika_mill_reach`, `mika_mill_turned`), all six
// form on top of him at once and ease out to their orbits over
// `MIKA_MILL_WIND` frames, while the turn winds up from a standstill to
// `ORRERY_ORBIT` on the same curve.

/// @desc The bearing ring `_k` comes out along, degrees anticlockwise from his
///       right. The six are evenly spaced, a sixth of a turn apart, and each
///       way's three a third of a turn apart, so the two triangles turning
///       through each other line up evenly again every sixth of a turn. Each
///       is a sixth of a turn on from the last, from ring 0 at his lower left,
///       so the first ring to fire is heading for the bottom as it starts. The
///       outer three, whose orbits reach the player, come out upward; only
///       ring 1 comes out downward, well short of the bottom.
function orrery_bearing(_k) {
    static _b = [210, 270, 330, 30, 90, 150];
    return _b[_k];
}

/// @desc The way ring `_k` goes round: +1 anticlockwise, -1 clockwise.
function orrery_way(_k) {
    return ((_k mod 2) == 0) ? 1 : -1;
}

// ---- waking ---------------------------------------------------------------

// The frame the first shots come (the row's `fire_at`). Ring 0 wakes
// `IGNITE` frames before it.
#macro ORRERY_FIRST (MIKA_MILL_WIND + 20)

// Ring k wakes once he has lost k sixths of his health for this attack, or
// once `LATE` frames or fewer are left on the clock, whatever his health (so
// holding fire doesn't keep the attack easy until it times out). At most one
// wakes every `WAKE_GAP` frames, in order, so a burst of damage doesn't wake
// several at once. A ring lights up over `IGNITE` frames and starts firing
// when fully lit.
#macro ORRERY_WAKE_GAP 50
#macro ORRERY_IGNITE 45
#macro ORRERY_LATE (20 * FPS)

// The look: asleep, a ring looks as any ring does (it hurts to touch either
// way) and turns slowly; awake it glows (`GLOW`, swelling by `PULSE` every
// `PULSE_T` frames) and spins faster. Spin is degrees a frame.
#macro ORRERY_GLOW 0.5
#macro ORRERY_PULSE 0.15
#macro ORRERY_PULSE_T 50
#macro ORRERY_SPIN_ASLEEP 0.6
#macro ORRERY_SPIN_AWAKE 2.6

// Each ring shows its orbit (`track`) as a gold line: this strong asleep, and
// this awake.
#macro ORRERY_TRACK_COL make_colour_rgb(226, 184, 100)
#macro ORRERY_TRACK_ASLEEP 0.45
#macro ORRERY_TRACK_AWAKE 0.8

/// @desc Ring `_k`'s colour: its glow, the sparks off its metal, and its
///       pattern. Warm at the middle, cool at the edge.
function orrery_col(_k) {
    static _c = [BCOL_GOLD, BCOL_CYAN, BCOL_CRIMSON, BCOL_JADE, BCOL_AZURE,
                 BCOL_VIOLET];
    return _c[_k];
}

// ---- the bolts ------------------------------------------------------------

// A bolt strings between two rings whose centres are nearer than this. Each
// ring strings at most one, to its nearest inner neighbour in reach.
#macro ORRERY_BOLT_D 200
#macro ORRERY_BOLT_COL BCOL_CYAN

// ---------------------------------------------------------------------------
// The attack
// ---------------------------------------------------------------------------

/// @desc **Grand Orrery.** The rings' state is kept in a static, since pooled
///       rings are reused (`ring_valid`).
function mika_grand_orrery(_e, _g, _t) {
    static orrery = undefined;
    if (_t == 0 || orrery == undefined) orrery = orrery_new();

    if (_t >= ORRERY_FIRST - ORRERY_IGNITE) orrery_wake(orrery, _e, _t);

    for (var _k = 0; _k < ORRERY_N; _k++) {
        orrery_ring_step(orrery, _k, _e, _g, _t);
    }
    orrery_bolts(orrery, _e, _t);
}

function orrery_new() {
    var _o = { ring: [], gen: [], wake: [], woken: 0, last: -100000,
               bolt: [] };
    for (var _k = 0; _k < ORRERY_N; _k++) {
        _o.ring[_k] = undefined;
        _o.gen[_k] = -1;
        _o.wake[_k] = -1;          // the frame it woke, or -1
        _o.bolt[_k] = -1;          // the ring it strung to last frame, or -1
    }
    return _o;
}

/// @desc Frames left on this attack's clock at attack frame `_t`, or
///       `infinity` without a boss or a clock (in tests).
function orrery_time_left(_e, _t) {
    if (_e[$ "boss"] == undefined) return infinity;
    var _p = boss_phase(_e);
    if (_p == undefined || _p.time <= 0) return infinity;
    return _p.time - _t;
}

/// @desc How far through his health for this attack he is: 0 as it opens, 1
///       at its threshold. 0 without a boss (in tests).
function orrery_rage(_e) {
    var _b = _e[$ "boss"];
    if (_b == undefined) return 0;
    var _p = boss_phase(_e);
    if (_p == undefined) return 0;
    var _hi = _e.hp_max * ((_b.phase > 0) ? _b.phases[_b.phase - 1].hp_end
                                          : 1);
    var _lo = _e.hp_max * _p.hp_end;
    if (_hi - _lo < 1) return 0;
    return clamp((_hi - _e.hp) / (_hi - _lo), 0, 1);
}

/// @desc Wake the next ring if his health or the clock says so and the last
///       woke long enough ago. Ring 0 wakes as soon as this is first asked.
function orrery_wake(_o, _e, _t) {
    if (_o.woken >= ORRERY_N) return;
    if (_t - _o.last < ORRERY_WAKE_GAP) return;
    var _k = _o.woken;
    if (orrery_rage(_e) < _k / ORRERY_N
        && orrery_time_left(_e, _t) > ORRERY_LATE) return;
    _o.wake[_k] = _t;
    _o.woken++;
    _o.last = _t;

    var _x = orrery_x(_e, _k, _t);
    var _y = orrery_y(_e, _k, _t);
    var _col = global.bullet_colour[orrery_col(_k)];
    fx_flash_at(_x, _y, _col, 0.35);
    fx_ring(_x, _y, RING_R, RING_R * 2.2, 24, _col, 0.9);
    sfx(Sfx.WardBurst);
}

// ---------------------------------------------------------------------------
// Orbits
// ---------------------------------------------------------------------------

function orrery_radius(_k) {
    return ORRERY_R0 + _k * ORRERY_DR;
}

/// @desc Ring `_k`'s bearing from him at frame `_t`: where it came out,
///       then turning. The rate rises as the mill's does
///       (`(t / WIND)^POW`), whose integral is used here.
function orrery_angle(_k, _t) {
    var _ramp = MIKA_MILL_WIND / (MIKA_MILL_WIND_POW + 1);
    var _turn = 0;
    if (_t <= 0) {
        _turn = 0;
    } else if (_t < MIKA_MILL_WIND) {
        _turn = _ramp * power(_t / MIKA_MILL_WIND, MIKA_MILL_WIND_POW + 1);
    } else {
        _turn = _ramp + (_t - MIKA_MILL_WIND);
    }
    return orrery_bearing(_k) + orrery_way(_k) * ORRERY_ORBIT * _turn;
}

/// @desc How far out ring `_k` is at frame `_t`: on him as it forms, its
///       orbit's radius once the wind-up is over (`mika_mill_reach`).
function orrery_reach(_k, _t) {
    return mika_mill_reach(_t, orrery_radius(_k));
}

/// @desc Where ring `_k`'s centre is at frame `_t` (he holds still, so this
///       is good for frames ahead too).
function orrery_x(_e, _k, _t) {
    return _e.x + lengthdir_x(orrery_reach(_k, _t), orrery_angle(_k, _t));
}

function orrery_y(_e, _k, _t) {
    return _e.y + lengthdir_y(orrery_reach(_k, _t), orrery_angle(_k, _t));
}

// ---------------------------------------------------------------------------
// Each ring
// ---------------------------------------------------------------------------

/// @desc One frame of ring `_k`: put down on the first frame, placed on its
///       orbit,
///       lit if awake, and firing once fully lit. Runs before `ring_step`,
///       which puts the ring at the offset set here.
function orrery_ring_step(_o, _k, _e, _g, _t) {
    var _r = _o.ring[_k];
    if (!ring_valid(_r, _o.gen[_k])) {
        // Put down now, or put back on its orbit if the pool refused it.
        _r = ring_new(orrery_x(_e, _k, _t), orrery_y(_e, _k, _t),
                      orrery_col(_k), 0);
        _o.ring[_k] = _r;
        _o.gen[_k] = (_r == undefined) ? -1 : _r.gen;
        if (_r == undefined) return;
        ring_attach(_r, _e, 0, 0);
        // The outer orbits pass off the top of the field.
        _r.cull = false;
        _r.arc_col = ORRERY_BOLT_COL;
        _r.ang = orrery_bearing(_k);
    }

    var _rad = orrery_reach(_k, _t);
    var _a = orrery_angle(_k, _t);
    _r.ox = lengthdir_x(_rad, _a);
    _r.oy = lengthdir_y(_rad, _a);

    var _lit = 0;
    if (_o.wake[_k] >= 0) {
        _lit = clamp((_t - _o.wake[_k]) / ORRERY_IGNITE, 0, 1);
    }
    var _swell = 0.5 + 0.5 * dsin((_t - _o.wake[_k]) * 360 / ORRERY_PULSE_T);
    _r.glow = _lit * (ORRERY_GLOW + ORRERY_PULSE * _swell);
    _r.spin = orrery_way(_k)
              * lerp(ORRERY_SPIN_ASLEEP, ORRERY_SPIN_AWAKE, _lit * _lit);
    // The line grows out from him with the ring.
    _r.track = _rad;
    _r.track_col = ORRERY_TRACK_COL;
    _r.track_a = lerp(ORRERY_TRACK_ASLEEP, ORRERY_TRACK_AWAKE, _lit);

    if (_lit < 1) return;
    var _u = _t - _o.wake[_k] - ORRERY_IGNITE;
    switch (_k) {
        case 0: orrery_corona(_e, _t, _u); break;
        case 1: orrery_pinwheel(_e, _r, 1, _t, _u); break;
        case 2: orrery_comet(_e, _g, _t, _u); break;
        case 3: orrery_halo(_e, 3, _t, _u); break;
        case 4: orrery_star(_e, _g, _t, _u); break;
        case 5: orrery_burst(_e, _t, _u); break;
    }
}

/// @desc String a bolt from each ring to its nearest inner neighbour within
///       `ORRERY_BOLT_D`, re-strung every frame so it lasts exactly as long
///       as they are close. A new bolt flashes as it strikes. None while the
///       rings are still coming out.
function orrery_bolts(_o, _e, _t) {
    if (_t < MIKA_MILL_WIND) return;
    for (var _j = 1; _j < ORRERY_N; _j++) {
        var _to = -1;
        if (ring_valid(_o.ring[_j], _o.gen[_j]) && ring_solid(_o.ring[_j])) {
            var _xj = orrery_x(_e, _j, _t);
            var _yj = orrery_y(_e, _j, _t);
            var _best = ORRERY_BOLT_D;
            for (var _i = 0; _i < _j; _i++) {
                if (!ring_valid(_o.ring[_i], _o.gen[_i])
                    || !ring_solid(_o.ring[_i])) continue;
                var _d = point_distance(_xj, _yj, orrery_x(_e, _i, _t),
                                        orrery_y(_e, _i, _t));
                if (_d < _best) {
                    _best = _d;
                    _to = _i;
                }
            }
        }
        if (_to >= 0) {
            ring_link(_o.ring[_j], _o.ring[_to], 2);
            if (_o.bolt[_j] != _to) {
                fx_flash_at((orrery_x(_e, _j, _t) + orrery_x(_e, _to, _t)) / 2,
                            (orrery_y(_e, _j, _t) + orrery_y(_e, _to, _t)) / 2,
                            global.bullet_colour[ORRERY_BOLT_COL], 0.15);
            }
        }
        _o.bolt[_j] = _to;
    }
}

// ---------------------------------------------------------------------------
// The patterns. `_u` is frames since the ring started firing.
// ---------------------------------------------------------------------------

/// @desc A grain fired at (`_x`, `_y`) that holds its speed `_hold` frames,
///       then brakes by `_brake` a frame to `_floor` and keeps going.
function orrery_grain(_x, _y, _spd, _dir, _shape, _col, _delay, _hold, _brake,
                      _floor) {
    var _b = fire(_x, _y, _spd, _dir, _shape, _col, _delay);
    bullet_accel_at(_b, _hold, -_brake, _floor);
    return _b;
}

// ---- 0: the corona --------------------------------------------------------

// Every `BEAT` frames, in dashes of `ON` beats with gaps of `OFF`, two grains
// leave the ring's middle straight out from him: a pellet and a mote, braking
// to different speeds, so the one spiral arm splits in two as it goes out.
#macro ORRERY_CORONA_BEAT 3
#macro ORRERY_CORONA_ON 5
#macro ORRERY_CORONA_OFF 3
#macro ORRERY_CORONA_DELAY 6
#macro ORRERY_CORONA_SPD 9
#macro ORRERY_CORONA_HOLD 4
#macro ORRERY_CORONA_BRAKE 0.45
#macro ORRERY_CORONA_FLOOR_A 2.6
#macro ORRERY_CORONA_FLOOR_B 1.8

function orrery_corona(_e, _t, _u) {
    if ((_u mod ORRERY_CORONA_BEAT) != 0) return;
    // Through a local: `mod (` reads to `check_unknown_functions` as a call.
    var _cyc = ORRERY_CORONA_ON + ORRERY_CORONA_OFF;
    if (((_u div ORRERY_CORONA_BEAT) mod _cyc) >= ORRERY_CORONA_ON) return;

    // Where the ring's middle will be when the marks go live.
    var _at = _t + ORRERY_CORONA_DELAY;
    var _a = orrery_angle(0, _at);
    var _x = orrery_x(_e, 0, _at);
    var _y = orrery_y(_e, 0, _at);
    orrery_grain(_x, _y, ORRERY_CORONA_SPD, _a, BSHAPE_PELLET, BCOL_GOLD,
                 ORRERY_CORONA_DELAY, ORRERY_CORONA_HOLD, ORRERY_CORONA_BRAKE,
                 ORRERY_CORONA_FLOOR_A);
    orrery_grain(_x, _y, ORRERY_CORONA_SPD, _a, BSHAPE_MOTE, BCOL_BONE,
                 ORRERY_CORONA_DELAY, ORRERY_CORONA_HOLD, ORRERY_CORONA_BRAKE,
                 ORRERY_CORONA_FLOOR_B);
}

// ---- 1: the pinwheel -----------------------------------------------------

// Every `BEAT` frames, one grain along each of `ARMS` arms evenly round, from
// the ring's middle. The arms turn with the ring's own spin, so they curl into
// a spiral that goes round with the ring. A grain leaves at `SPD`, holds it
// `HOLD` frames, then brakes by `BRAKE` a frame to `FLOOR`.
#macro ORRERY_WHEEL_BEAT 8
#macro ORRERY_WHEEL_ARMS 3
#macro ORRERY_WHEEL_DELAY 6
#macro ORRERY_WHEEL_SPD 7
#macro ORRERY_WHEEL_HOLD 4
#macro ORRERY_WHEEL_BRAKE 0.3
#macro ORRERY_WHEEL_FLOOR 2.4

function orrery_pinwheel(_e, _r, _k, _t, _u) {
    if ((_u mod ORRERY_WHEEL_BEAT) != 0) return;
    var _at = _t + ORRERY_WHEEL_DELAY;
    var _cx = orrery_x(_e, _k, _at);
    var _cy = orrery_y(_e, _k, _at);
    var _way = orrery_way(_k);
    // Where the ring's turn will have taken the arms when the marks go live.
    var _a0 = _r.ang + _r.spin * ORRERY_WHEEL_DELAY;
    for (var _i = 0; _i < ORRERY_WHEEL_ARMS; _i++) {
        var _a = _a0 + _i * (360 / ORRERY_WHEEL_ARMS);
        var _b = orrery_grain(_cx, _cy, ORRERY_WHEEL_SPD,
                              _a + 90 * _way, BSHAPE_RICE, orrery_col(_k),
                              ORRERY_WHEEL_DELAY, ORRERY_WHEEL_HOLD,
                              ORRERY_WHEEL_BRAKE, ORRERY_WHEEL_FLOOR);
        if (_b == undefined) break;
    }
}

// ---- 2: the comet ---------------------------------------------------------

// Every `EVERY` frames, three comets from the ring's middle: one aimed at the
// player and one `SPREAD` degrees either side. A comet is a head and `TAIL`
// pellets down the same line, each `STEP` slower than the one before.
#macro ORRERY_COMET_EVERY 90
#macro ORRERY_COMET_DELAY 14
#macro ORRERY_COMET_SPREAD 22
#macro ORRERY_COMET_TAIL 4
#macro ORRERY_COMET_SPD 5.6
#macro ORRERY_COMET_STEP 0.45

function orrery_comet(_e, _g, _t, _u) {
    if ((_u mod ORRERY_COMET_EVERY) != 0) return;
    var _at = _t + ORRERY_COMET_DELAY;
    var _x = orrery_x(_e, 2, _at);
    var _y = orrery_y(_e, 2, _at);
    var _p = _g.player;
    var _aim = aim_at(_x, _y, _p.x, _p.y);
    for (var _s = -1; _s <= 1; _s++) {
        var _dir = _aim + _s * ORRERY_COMET_SPREAD;
        fire(_x, _y, ORRERY_COMET_SPD, _dir,
             (_s == 0) ? BSHAPE_BALL : BSHAPE_ORB, BCOL_CRIMSON,
             ORRERY_COMET_DELAY);
        for (var _i = 1; _i <= ORRERY_COMET_TAIL; _i++) {
            fire(_x, _y, ORRERY_COMET_SPD - _i * ORRERY_COMET_STEP, _dir,
                 BSHAPE_PELLET, BCOL_EMBER, ORRERY_COMET_DELAY);
        }
    }
}

// ---- 3: the halo ---------------------------------------------------------

// Every `EVERY` frames, `N` rice evenly round from the ring's middle. They
// brake to a stop a little way outside the metal (`SPD` and `BRAKE` set how
// far: about SPD^2 / (2 BRAKE)), hang there for `HANG` frames as a ring of
// spokes the ring leaves behind, then gather speed outward to `OUT`. Each
// halo is turned half a step from the last.
#macro ORRERY_HALO_EVERY 72
#macro ORRERY_HALO_N 20
#macro ORRERY_HALO_DELAY 8
#macro ORRERY_HALO_SPD 11.5
#macro ORRERY_HALO_BRAKE 0.55
#macro ORRERY_HALO_HANG 30
#macro ORRERY_HALO_GO 0.05
#macro ORRERY_HALO_OUT 2.4

function orrery_halo(_e, _k, _t, _u) {
    if ((_u mod ORRERY_HALO_EVERY) != 0) return;
    var _at = _t + ORRERY_HALO_DELAY;
    var _cx = orrery_x(_e, _k, _at);
    var _cy = orrery_y(_e, _k, _at);
    var _step = 360 / ORRERY_HALO_N;
    var _a0 = orrery_angle(_k, _at)
              + (((_u div ORRERY_HALO_EVERY) mod 2) ? _step * 0.5 : 0);
    // The frame it stops: `bullet_step` brakes before moving.
    var _stop = ceil(ORRERY_HALO_SPD / ORRERY_HALO_BRAKE);
    for (var _i = 0; _i < ORRERY_HALO_N; _i++) {
        var _a = _a0 + _i * _step;
        var _b = orrery_grain(_cx, _cy,
                              ORRERY_HALO_SPD, _a, BSHAPE_RICE, orrery_col(_k),
                              ORRERY_HALO_DELAY, 0, ORRERY_HALO_BRAKE, 0);
        if (_b == undefined) break;
        bullet_accel_at(_b, _stop + ORRERY_HALO_HANG, ORRERY_HALO_GO,
                        ORRERY_HALO_OUT);
    }
}

// ---- 4: the star ----------------------------------------------------------

// Every `EVERY` frames, `RAYS` beams laid from where the ring's middle is,
// evenly round and `LEN` long (across the field), one aimed at the player.
// They stay where they were laid (the ring goes on without them): `WARN`
// frames of warning, `HOT` frames firing.
#macro ORRERY_BEAM_EVERY 240
#macro ORRERY_BEAM_RAYS 8
#macro ORRERY_BEAM_LEN 2000
#macro ORRERY_BEAM_WID 26
#macro ORRERY_BEAM_WARN 70
#macro ORRERY_BEAM_HOT 50

function orrery_star(_e, _g, _t, _u) {
    if ((_u mod ORRERY_BEAM_EVERY) != 0) return;
    var _x = orrery_x(_e, 4, _t);
    var _y = orrery_y(_e, 4, _t);
    var _step = 360 / ORRERY_BEAM_RAYS;
    var _a = aim_at(_x, _y, _g.player.x, _g.player.y);
    for (var _i = 0; _i < ORRERY_BEAM_RAYS; _i++) {
        laser_beam(_x, _y, _a + _i * _step, ORRERY_BEAM_LEN, ORRERY_BEAM_WID,
                   BCOL_AZURE, ORRERY_BEAM_WARN, ORRERY_BEAM_HOT);
    }
}

// ---- 5: the burst ---------------------------------------------------------

// Every `EVERY` frames, a ring of `N` darts from the ring's middle, evenly in
// every direction at `SPD`. Each ring is turned half a step from the last.
#macro ORRERY_BURST_EVERY 80
#macro ORRERY_BURST_DELAY 10
#macro ORRERY_BURST_N 16
#macro ORRERY_BURST_SPD 3.4

function orrery_burst(_e, _t, _u) {
    if ((_u mod ORRERY_BURST_EVERY) != 0) return;
    var _at = _t + ORRERY_BURST_DELAY;
    var _step = 360 / ORRERY_BURST_N;
    var _a0 = orrery_angle(5, _at)
              + (((_u div ORRERY_BURST_EVERY) mod 2) ? _step * 0.5 : 0);
    fire_ring(orrery_x(_e, 5, _at), orrery_y(_e, 5, _at), ORRERY_BURST_N,
              ORRERY_BURST_SPD, _a0, BSHAPE_DART, BCOL_VIOLET,
              ORRERY_BURST_DELAY);
}
