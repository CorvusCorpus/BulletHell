/// @desc **Storm Cage**, Mika's S1.
///
/// The owner's brief: three of his rings fly in from off the field and circle
/// the player, strung together by lightning into a spinning triangle that
/// follows the player's movement. A sandstorm of fast grains then floods the
/// field until the spell ends. A grain that meets a ring is stopped; a grain
/// that meets a bolt bursts into glass shards that scatter slowly. The shards
/// keep appearing round the player, so the player has to keep moving rather
/// than camp one spot. The owner's rule for the glass: no odds on whether a
/// grain becomes glass. The storm is two kinds of grain, told apart by colour:
/// amber sand always fuses into glass on a bolt, and ember grit always burns
/// away there. The glass falls off the field rather than expiring.
///
/// The cage is three ordinary rings riding a centre that follows the player,
/// linked with `ring_link`, so the metal and the bolts hurt to touch and block
/// shots as any ring does. The catching of sand is this spell's own
/// (`storm_cage_catch`). Every bullet on the field during it is sand or glass,
/// and glass is told apart by its shape.
///
/// Every number here is a first guess, waiting on playtesting.

// ---------------------------------------------------------------------------
// The cage
// ---------------------------------------------------------------------------

// From the cage's centre to each ring's centre.
#macro STORM_CAGE_R 250

// The triangle's turn and each ring's own spin, degrees a frame.
#macro STORM_CAGE_SPIN 0.85
#macro STORM_CAGE_RING_SPIN 2.2

// The share of the gap to the player the centre closes each frame. Moving
// flat out, the player leads the centre by PLAYER_SPD * (1 - f) / f pixels
// (50 at 0.18), against the triangle's inner radius of STORM_CAGE_R / 2.
#macro STORM_CAGE_FOLLOW 0.18

// Where ring 0 sits when the cage is at rest, in degrees round the centre.
#macro STORM_CAGE_A0 90

// The rings' `col`: the lightning and the rings' glow and sparks (the metal
// keeps its own colours).
#macro STORM_CAGE_COL BCOL_CYAN

// How far from a ring's centre it stops a bullet: the outside of its metal.
#macro STORM_RING_REACH (RING_R + RING_BAND_HALF)

// ---- the arrival ----------------------------------------------------------

// Frames from off the field to station, how far out they start, and how many
// degrees they wind through on the way in.
#macro STORM_FLY 80
#macro STORM_FLY_FROM 1100
#macro STORM_FLY_WIND 200

// The frame the bolts strike. After `RING_FORM`, so the rings are solid.
#macro STORM_STRIKE 92

// ---------------------------------------------------------------------------
// The storm
// ---------------------------------------------------------------------------

// The first grain, and the frames from there to full strength.
#macro STORM_START 130
#macro STORM_RISE 150

// Grains a frame at full strength (fractions carry over between frames).
#macro STORM_RATE 5.0

// A grain's speed, picked between these, and how many degrees either side of
// the wind it may stray.
#macro STORM_SPD_LO 8.5
#macro STORM_SPD_HI 12.0
#macro STORM_SCATTER 6

// The wind's heading (270 is straight down), how far it veers either side,
// and how fast it swings (degrees of phase a frame).
#macro STORM_WIND 270
#macro STORM_VEER 38
#macro STORM_VEER_RATE 0.32

// Gusts: the rate swings this share either side of full strength.
#macro STORM_GUST 0.3
#macro STORM_GUST_RATE 1.1

// How far outside the field a grain starts.
#macro STORM_ENTRY 24

// The colour of the grains that fuse into glass on a bolt (sand). A grain of
// any other colour burns away on a bolt (grit).
#macro STORM_SAND_COL BCOL_AMBER

// ---------------------------------------------------------------------------
// The glass
// ---------------------------------------------------------------------------

// Every grain that touches a bolt bursts into this many shards, spread across
// this many degrees centred on the grain's heading.
#macro STORM_GLASS_N 1
#macro STORM_GLASS_FAN 110

// Launch speed, braking, and the slow drift each shard settles to (picked
// between the two floors).
#macro STORM_GLASS_SPD 2.8
#macro STORM_GLASS_BRAKE 0.09
#macro STORM_GLASS_FLOOR_LO 0.7
#macro STORM_GLASS_FLOOR_HI 1.3

// Then it falls: from this frame of its life, gravity pulls it down at this
// many pixels a frame per frame, up to this falling speed, until it leaves
// the bottom of the field. Its sideways drift carries on.
#macro STORM_GLASS_FALL_AT 45
#macro STORM_GLASS_GRAVITY 0.035
#macro STORM_GLASS_FALL_MAX 6.0

// Warning-mark delay and the look. Scale is drawn size; the hitbox shrinks
// with it.
#macro STORM_GLASS_DELAY 6
#macro STORM_GLASS_SHAPE BSHAPE_CRYSTAL
#macro STORM_GLASS_COL BCOL_CYAN
#macro STORM_GLASS_SCALE 0.6

/// @desc The looks a grain is picked from, each equally often. The amber ones
///       are sand (`STORM_SAND_COL`) and the ember ones grit, so the share of
///       amber looks is the share of grains reaching a bolt that become glass
///       (half, as listed). None may use `STORM_GLASS_SHAPE`: that is how
///       glass is told from the storm.
function storm_sand_looks() {
    static _looks = [
        { shape: BSHAPE_RICE,   col: BCOL_AMBER, scale: 0.85 },
        { shape: BSHAPE_PELLET, col: BCOL_AMBER, scale: 0.72 },
        { shape: BSHAPE_RICE,   col: BCOL_EMBER, scale: 0.85 },
        { shape: BSHAPE_MOTE,   col: BCOL_EMBER, scale: 0.80 },
    ];
    return _looks;
}

// ---------------------------------------------------------------------------
// The attack
// ---------------------------------------------------------------------------

/// @desc **Storm Cage.** The cage is built on the first frame and kept in a
///       static, since pooled rings are reused (`ring_valid`).
function mika_storm_cage(_e, _g, _t) {
    static cage = undefined;
    if (_t == 0 || cage == undefined) {
        cage = storm_cage_new(_g.player.x, _g.player.y);
    }

    storm_cage_follow(cage, _g.player, _t);
    if (_t >= STORM_START) storm_blow(cage, _t);
    storm_cage_catch(cage, _t);
}

/// @desc Three rings far out round (`_x`, `_y`), riding a centre that starts
///       there. The centre is the rings' `src`; `storm_cage_follow` moves it
///       and sets their offsets.
function storm_cage_new(_x, _y) {
    var _c = { x: _x, y: _y, ring: [], gen: [], acc: 0, nx: [], ny: [] };
    for (var _i = 0; _i < 3; _i++) {
        var _a = storm_cage_angle(_i, 0);
        var _ox = lengthdir_x(STORM_FLY_FROM, _a);
        var _oy = lengthdir_y(STORM_FLY_FROM, _a);
        var _r = ring_new(_x + _ox, _y + _oy, STORM_CAGE_COL, 0);
        _c.ring[_i] = _r;
        _c.gen[_i] = (_r == undefined) ? -1 : _r.gen;
        _c.nx[_i] = _x + _ox;
        _c.ny[_i] = _y + _oy;
        if (_r == undefined) continue;
        ring_attach(_r, _c, _ox, _oy);
        // It starts off the field, and goes wherever the player takes it.
        _r.cull = false;
        _r.spin = STORM_CAGE_RING_SPIN;
    }
    return _c;
}

/// @desc How much of the flight in is left at frame `_t`: 1 at the start, 0
///       on station, easing out so the rings arrive without a jolt.
function storm_cage_fly(_t) {
    var _u = clamp(_t / STORM_FLY, 0, 1);
    return power(1 - _u, 3);
}

/// @desc Ring `_i`'s bearing from the centre at frame `_t`.
function storm_cage_angle(_i, _t) {
    return STORM_CAGE_A0 + _i * 120 + STORM_CAGE_SPIN * _t
           + STORM_FLY_WIND * storm_cage_fly(_t);
}

/// @desc Move the centre toward the player, set each ring's offset, and note
///       where each ring will be this frame (`nx`, `ny`). This runs before
///       `ring_step`, which places the rings from the same numbers. From the
///       strike on, the three bolts are re-strung every frame, so they last
///       exactly as long as the attack runs.
function storm_cage_follow(_c, _p, _t) {
    _c.x += (_p.x - _c.x) * STORM_CAGE_FOLLOW;
    _c.y += (_p.y - _c.y) * STORM_CAGE_FOLLOW;

    var _d = STORM_CAGE_R + (STORM_FLY_FROM - STORM_CAGE_R) * storm_cage_fly(_t);
    for (var _i = 0; _i < 3; _i++) {
        var _a = storm_cage_angle(_i, _t);
        var _ox = lengthdir_x(_d, _a);
        var _oy = lengthdir_y(_d, _a);
        _c.nx[_i] = _c.x + _ox;
        _c.ny[_i] = _c.y + _oy;
        var _r = _c.ring[_i];
        if (!ring_valid(_r, _c.gen[_i])) continue;
        _r.ox = _ox;
        _r.oy = _oy;
    }

    if (_t < STORM_STRIKE) return;
    for (var _i = 0; _i < 3; _i++) {
        var _j = (_i + 1) mod 3;
        if (!ring_valid(_c.ring[_i], _c.gen[_i])
            || !ring_valid(_c.ring[_j], _c.gen[_j])) continue;
        ring_link(_c.ring[_i], _c.ring[_j], 2);
        if (_t == STORM_STRIKE) {
            var _mx = (_c.nx[_i] + _c.nx[_j]) * 0.5;
            var _my = (_c.ny[_i] + _c.ny[_j]) * 0.5;
            fx_flash_at(_mx, _my, global.bullet_colour[STORM_CAGE_COL], 0.5);
            fx_flash_at(_c.nx[_i], _c.ny[_i],
                        global.bullet_colour[STORM_CAGE_COL], 0.35);
        }
    }
    if (_t == STORM_STRIKE) {
        fx_shake(8);
        sfx(Sfx.LaserFire);
    }
}

// ---------------------------------------------------------------------------
// The storm
// ---------------------------------------------------------------------------

/// @desc The wind's heading at frame `_t`.
function storm_wind(_t) {
    return STORM_WIND + STORM_VEER * dsin((_t - STORM_START) * STORM_VEER_RATE);
}

/// @desc This frame's grains. Each is dropped on a random line along the wind
///       (uniform across the field, so the flow is even), started where that
///       line enters the field, and set back a random part of one frame's
///       travel so a frame's grains don't start in a row. A grain that would
///       start inside the cage (the cage can hang past the field's edge) is
///       not fired.
function storm_blow(_c, _t) {
    var _u = clamp((_t - STORM_START) / STORM_RISE, 0, 1);
    var _gust = 1 + STORM_GUST * dsin((_t - STORM_START) * STORM_GUST_RATE);
    _c.acc += STORM_RATE * _u * _u * (3 - 2 * _u) * _gust;

    var _wind = storm_wind(_t);
    var _dx = lengthdir_x(1, _wind);
    var _dy = lengthdir_y(1, _wind);
    // Across the wind, and how far the field reaches either side along it.
    var _qx = -_dy;
    var _qy = _dx;
    var _half = abs(_qx) * (FIELD_W * 0.5 + STORM_ENTRY)
                + abs(_qy) * (FIELD_H * 0.5 + STORM_ENTRY);
    var _looks = storm_sand_looks();

    while (_c.acc >= 1) {
        _c.acc -= 1;
        var _s = random_range(-_half, _half);
        var _lx = FIELD_CX + _qx * _s;
        var _ly = FIELD_CY + _qy * _s;
        var _in = storm_entry(_lx, _ly, _dx, _dy);
        if (_in == undefined) continue;

        var _spd = random_range(STORM_SPD_LO, STORM_SPD_HI);
        var _at = _in - random(_spd);
        var _x = _lx + _dx * _at;
        var _y = _ly + _dy * _at;
        if (storm_cage_inside(_c, _x, _y)) continue;

        var _look = _looks[irandom(array_length(_looks) - 1)];
        var _b = fire(_x, _y, _spd,
                      _wind + random_range(-STORM_SCATTER, STORM_SCATTER),
                      _look.shape, _look.col, 0);
        if (_b == undefined) break;
        _b.scale = _look.scale;
        _b.r = global.bshape_radius[_look.shape] * _look.scale;
    }
}

/// @desc How far along the line (`_x`, `_y`) + k (`_dx`, `_dy`) it enters the
///       box `STORM_ENTRY` outside the field, or `undefined` if it misses.
function storm_entry(_x, _y, _dx, _dy) {
    var _lo = -100000;
    var _hi = 100000;

    if (abs(_dx) > 0.0001) {
        var _x0 = (FIELD_X0 - STORM_ENTRY - _x) / _dx;
        var _x1 = (FIELD_X1 + STORM_ENTRY - _x) / _dx;
        _lo = max(_lo, min(_x0, _x1));
        _hi = min(_hi, max(_x0, _x1));
    } else if (_x < FIELD_X0 - STORM_ENTRY || _x > FIELD_X1 + STORM_ENTRY) {
        return undefined;
    }

    if (abs(_dy) > 0.0001) {
        var _y0 = (FIELD_Y0 - STORM_ENTRY - _y) / _dy;
        var _y1 = (FIELD_Y1 + STORM_ENTRY - _y) / _dy;
        _lo = max(_lo, min(_y0, _y1));
        _hi = min(_hi, max(_y0, _y1));
    } else if (_y < FIELD_Y0 - STORM_ENTRY || _y > FIELD_Y1 + STORM_ENTRY) {
        return undefined;
    }

    return (_lo > _hi) ? undefined : _lo;
}

/// @desc Is a point inside the cage this frame: inside the triangle between
///       the rings' centres, or on a ring?
function storm_cage_inside(_c, _x, _y) {
    var _neg = false;
    var _pos = false;
    for (var _i = 0; _i < 3; _i++) {
        var _j = (_i + 1) mod 3;
        if (point_distance(_x, _y, _c.nx[_i], _c.ny[_i]) < STORM_RING_REACH) {
            return true;
        }
        var _s = (_c.nx[_j] - _c.nx[_i]) * (_y - _c.ny[_i])
                 - (_c.ny[_j] - _c.ny[_i]) * (_x - _c.nx[_i]);
        if (_s < 0) _neg = true; else _pos = true;
    }
    return !(_neg && _pos);
}

// ---------------------------------------------------------------------------
// The catch
// ---------------------------------------------------------------------------

/// @desc Stop every grain that meets a ring. On a bolt, sand bursts into
///       glass and grit burns away. Glass passes through both (the owner's
///       call: rings eating the glass made the attack too easy).
///
///       Everything is measured over the frame: each bullet from its last
///       position to this one, each bolt from where its rings were (their
///       `x`, `y`, not yet stepped) to where they will be (`nx`, `ny`), so a
///       grain can't slip between frames past a bolt that is turning and
///       moving with the player.
function storm_cage_catch(_c, _t) {
    var _solid = [false, false, false];
    var _px = [0, 0, 0];
    var _py = [0, 0, 0];
    var _any = false;
    for (var _i = 0; _i < 3; _i++) {
        var _r = _c.ring[_i];
        if (!ring_valid(_r, _c.gen[_i]) || !ring_solid(_r)) continue;
        _solid[_i] = true;
        _px[_i] = _r.x;
        _py[_i] = _r.y;
        _any = true;
    }
    if (!_any) return;

    var _bolt = [false, false, false];
    if (_t >= STORM_STRIKE) {
        for (var _i = 0; _i < 3; _i++) {
            _bolt[_i] = _solid[_i] && _solid[(_i + 1) mod 3];
        }
    }

    // Nothing further than this from the centre can reach a ring or a bolt
    // this frame (the fastest grain's step, with room to spare).
    var _far = STORM_CAGE_R + STORM_RING_REACH + STORM_SPD_HI + 24;
    var _far2 = _far * _far;
    var _cx = _c.x;
    var _cy = _c.y;
    var _arc = ring_arc_half();

    var _pool = global.bullets;
    for (var _n = global.bullet_n - 1; _n >= 0; _n--) {
        var _u = _pool[_n];
        if (_u.delay > 0 || _u.fade_t > 0) continue;
        if (_u.shape == STORM_GLASS_SHAPE) continue;
        var _ex = _u.x - _cx;
        var _ey = _u.y - _cy;
        if (_ex * _ex + _ey * _ey > _far2) continue;

        // The rings.
        var _gone = false;
        for (var _i = 0; _i < 3; _i++) {
            if (!_solid[_i]) continue;
            if (point_seg_dist(_c.nx[_i], _c.ny[_i], _u.px, _u.py, _u.x, _u.y)
                < STORM_RING_REACH + _u.r) {
                fx_spark(_u.x, _u.y, _u.dir + 180 + random_range(-50, 50),
                         random_range(1, 2.5), global.bullet_colour[_u.col],
                         10, 8);
                bullet_kill_at(_n);
                _gone = true;
                break;
            }
        }
        if (_gone) continue;

        // The bolts.
        for (var _i = 0; _i < 3; _i++) {
            if (!_bolt[_i]) continue;
            var _j = (_i + 1) mod 3;
            var _s = storm_bolt_meets(_px[_i], _py[_i], _px[_j], _py[_j],
                                      _c.nx[_i], _c.ny[_i],
                                      _c.nx[_j], _c.ny[_j],
                                      _u.px, _u.py, _u.x, _u.y,
                                      _u.r + _arc);
            if (_s < 0) continue;
            // Shattered before the grain is killed: the kill moves the last
            // live bullet (possibly a new shard) into this slot, which the
            // loop has already passed.
            var _hx = lerp(_c.nx[_i], _c.nx[_j], _s);
            var _hy = lerp(_c.ny[_i], _c.ny[_j], _s);
            if (_u.col == STORM_SAND_COL) {
                storm_shatter(_u, _hx, _hy);
            } else {
                fx_spark(_hx, _hy, _u.dir + random_range(-40, 40),
                         random_range(1.5, 3.5), global.bullet_colour[_u.col],
                         12, 9);
            }
            bullet_kill_at(_n);
            break;
        }
    }
}

/// @desc Where along a bolt a grain meets it this frame, from 0 at one ring
///       to 1 at the other, or -1 if it doesn't. The bolt ran from (`_ax0`,
///       `_ay0`)-(`_bx0`, `_by0`) to (`_ax1`, `_ay1`)-(`_bx1`, `_by1`); the
///       grain from (`_gx0`, `_gy0`) to (`_gx1`, `_gy1`). It meets the bolt if
///       it ends the frame within `_reach` of it, or if it changed sides of
///       the bolt's line while level with it.
function storm_bolt_meets(_ax0, _ay0, _bx0, _by0, _ax1, _ay1, _bx1, _by1,
                          _gx0, _gy0, _gx1, _gy1, _reach) {
    var _ex = _bx1 - _ax1;
    var _ey = _by1 - _ay1;
    var _len2 = _ex * _ex + _ey * _ey;
    if (_len2 < 1) return -1;

    var _s = ((_gx1 - _ax1) * _ex + (_gy1 - _ay1) * _ey) / _len2;
    if (_s < 0 || _s > 1) return -1;

    // The side of the line, scaled by the bolt's length.
    var _side1 = _ex * (_gy1 - _ay1) - _ey * (_gx1 - _ax1);
    if (_side1 * _side1 < _reach * _reach * _len2) return _s;

    var _side0 = (_bx0 - _ax0) * (_gy0 - _ay0) - (_by0 - _ay0) * (_gx0 - _ax0);
    if ((_side0 < 0) != (_side1 < 0)) return _s;
    return -1;
}

/// @desc A bolt has caught grain `_u` at (`_x`, `_y`): it bursts into glass
///       carrying on roughly the way the grain was going. Each shard brakes
///       to a slow drift, then falls (`STORM_GLASS_FALL_AT`) until it leaves
///       the bottom of the field; nothing else removes it.
function storm_shatter(_u, _x, _y) {
    fx_flash_at(_x, _y, global.bullet_colour[STORM_GLASS_COL], 0.10);
    for (var _i = 0; _i < STORM_GLASS_N; _i++) {
        var _b = fire(_x, _y, STORM_GLASS_SPD,
                      _u.dir + random_range(-STORM_GLASS_FAN * 0.5,
                                            STORM_GLASS_FAN * 0.5),
                      STORM_GLASS_SHAPE, STORM_GLASS_COL, STORM_GLASS_DELAY);
        if (_b == undefined) return;
        _b.scale = STORM_GLASS_SCALE;
        _b.r = global.bshape_radius[STORM_GLASS_SHAPE] * STORM_GLASS_SCALE;
        bullet_accel_at(_b, 0, -STORM_GLASS_BRAKE,
                        random_range(STORM_GLASS_FLOOR_LO,
                                     STORM_GLASS_FLOOR_HI));
        bullet_force_at(_b, STORM_GLASS_FALL_AT, 0, STORM_GLASS_GRAVITY,
                        BQ_KEEP, STORM_GLASS_FALL_MAX);
    }
}
