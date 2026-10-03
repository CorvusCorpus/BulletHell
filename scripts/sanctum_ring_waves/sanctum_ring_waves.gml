/// @desc Waves five and ten: Mika's rings come through the hall on their own,
///       perform, and leave. Nothing in them can be shot; the player
///       outlasts them (`ev_wave`'s survival).
///
/// Every ring of a rite is put down on the same frame, so each ring's own
/// clock (`_t` in its `act`) is the rite's clock, and each ring moves by it
/// and by its place in the rite. Rings waiting to come on are parked above
/// the field. A ring that has flown clear of the
/// field at the end is dismissed; the wave's gate waits for the last one.
/// Both rites are placeholders in the intended shape.

// ===========================================================================
// The hoop rite (wave five)
//
// Mika's rings loose in the hall, going everywhere, so there is nowhere to
// sit still.
//
// 1. Three hoops drop in and ricochet round the whole field, rolling as they
//    go and flinging sand off their rims, which arcs up and falls away; each
//    time one strikes a wall it throws a splash of grains back into the
//    field. At the end they bounce out through the top.
// 2. Hoop rain: eight rings fall one after another, each down a lane that
//    flashes a moment before, gathering speed. As each falls it leaves a
//    ladder of sand hanging either side of it, which then sifts down. A
//    falling hoop can be dodged, or let fall round you through its hole.
// 3. The dance: four rings chase each other along one great figure drawn
//    across the whole field, still flinging sand, and rise away.
// ===========================================================================

#macro RITE_HOOPS 15               // 3 bouncers, 8 falling, 4 dancing
#macro RITE_BOUNCE_OUT 440         // the bouncers stop turning back at the top
#macro RITE_RAIN_AT 470            // the first ring falls...
#macro RITE_RAIN_GAP 44            // ...and each after it this much later
#macro RITE_RAIN_WARN 44           // its lane flashes this long before
#macro RITE_DANCE_AT 820           // the dancers come in...
#macro RITE_DANCE_OUT 1120         // ...and rise away
#macro RITE_HOOP_TIME 1500         // a backstop

/// @desc Push the rite onto a timeline at `_t`; returns its length (the gate
///       then waits for the rings to go).
function sanctum_rite_hoops_wave(_e, _t) {
    array_push(_e, ev(_t + 1, wave_rite_hoops()));
    return RITE_DANCE_OUT + 40;
}

function wave_rite_hoops() {
    return function(_g) {
        // Each ring's own motion, integrated a frame at a time: velocity,
        // and whether it has started (the falling ones wait).
        var _rite = { vx: array_create(RITE_HOOPS, 0),
                      vy: array_create(RITE_HOOPS, 0) };
        // The bouncers: where they come in over the top, and how fast.
        var _bx = [260, 1100, 700];
        var _bv = [[4.2, 3.4], [-3.8, 3.0], [2.6, 4.4]];
        for (var _i = 0; _i < RITE_HOOPS; _i++) {
            var _r = ring_new(FIELD_CX, FIELD_Y0 - 220, MIKA_RING_COL,
                              RITE_HOOP_TIME);
            if (_r == undefined) break;
            // It waits above the field, where it would otherwise be culled.
            _r.cull = false;
            if (_i < 3) {
                _r.x = FIELD_X0 + _bx[_i];
                _r.y = FIELD_Y0 - 120 - _i * 70;
                _rite.vx[_i] = _bv[_i][0];
                _rite.vy[_i] = _bv[_i][1];
            } else {
                _r.x = FIELD_X0 + rite_rain_x(_i - 3);
                _r.y = FIELD_Y0 - 200;
            }
            _r.px = _r.x;
            _r.py = _r.y;
            _r.act = method({ rite: _rite, i: _i }, rite_hoop_ring);
        }
    };
}

/// @desc Where falling ring `_k` (0 to 7) drops, across the field (field
///       coordinates): spread so that one lands away from the last.
function rite_rain_x(_k) {
    static _xs = [300, 980, 620, 180, 1160, 460, 820, 680];
    return _xs[_k mod array_length(_xs)];
}

/// @desc Sand flung off a rolling ring's rim: two grains from opposite
///       points of the band as it turns, leaving along the band, that arc
///       and fall away under their weight.
function rite_fling(_r, _col) {
    var _sign = (_r.spin >= 0) ? 1 : -1;
    for (var _k = 0; _k < 2; _k++) {
        var _at = _r.ang + _k * 180;
        var _u = fire(ring_rim_at_x(_r, _at, 6), ring_rim_at_y(_r, _at, 6),
                      3.0, _at + 90 * _sign, BSHAPE_PELLET, _col, 6);
        if (_u == undefined) continue;
        bullet_force(_u, 0, 0.055, BQ_KEEP, 4.6);
    }
}

/// @desc One ring of the hoop rite, one frame (its `act`; bound to `rite`
///       and its index `i`).
function rite_hoop_ring(_r, _g, _t) {
    if (i < 3) {
        rite_hoop_bounce(_r, _t);
    } else if (i < 11) {
        rite_hoop_fall(_r, _t);
    } else {
        rite_hoop_dance(_r, _t);
    }
}

/// @desc The bouncers: straight lines between walls, rolling the way they
///       travel, flinging sand, splashing grains back off every wall.
function rite_hoop_bounce(_r, _t) {
    var _rad = ring_radius(_r) + 6;
    var _vx = rite.vx[i];
    var _vy = rite.vy[i];
    _r.x += _vx;
    _r.y += _vy;
    var _hit = -1;           // the direction the splash goes, or -1
    if (_r.x < FIELD_X0 + _rad && _vx < 0) {
        _vx = -_vx;
        _hit = 0;
    } else if (_r.x > FIELD_X1 - _rad && _vx > 0) {
        _vx = -_vx;
        _hit = 180;
    }
    if (_r.y > FIELD_Y1 - _rad && _vy > 0) {
        _vy = -_vy;
        _hit = 90;
    } else if (_r.y < FIELD_Y0 + _rad && _vy < 0
               && _t < RITE_BOUNCE_OUT && _r.y > FIELD_Y0) {
        _vy = -_vy;
        _hit = 270;
    }
    rite.vx[i] = _vx;
    rite.vy[i] = _vy;
    // Rolling: turning with its travel across the field.
    _r.spin = _vx * 1.1 + ((_vx >= 0) ? 0.4 : -0.4);

    var _inside = (_r.y > FIELD_Y0 + 20);
    if (_hit >= 0 && _inside) {
        var _cx = _r.x - lengthdir_x(ring_radius(_r), _hit);
        var _cy = _r.y - lengthdir_y(ring_radius(_r), _hit);
        fire_fan(_cx, _cy, 7, 4.2, _hit, 100, BSHAPE_MOTE, BCOL_BONE, 6);
        fx_ring(_cx, _cy, 10, 90, 16, global.bullet_colour[BCOL_GOLD], 0.6);
        sfx(Sfx.WardScatter);
    }
    if (_inside && (_t mod 9) == i * 3) rite_fling(_r, BCOL_AMBER);

    if (_t > RITE_BOUNCE_OUT) rite_dismiss_if_clear(_r);
}

/// @desc The rain: each ring waits above the field, flashes its lane, and
///       falls, leaving a ladder of sand hanging either side of it.
function rite_hoop_fall(_r, _t) {
    var _k = i - 3;
    var _at = RITE_RAIN_AT + _k * RITE_RAIN_GAP;
    var _x = FIELD_X0 + rite_rain_x(_k);
    if (_t < _at) {
        _r.x = _x;
        _r.y = FIELD_Y0 - 200;
        _r.spin = 0.6;
        if (_t == _at - RITE_RAIN_WARN) {
            ring_lane_flash(_r, _x, FIELD_Y0 - 200, 270,
                            FIELD_H + 400, RITE_RAIN_WARN + 30);
        }
        return;
    }
    // Falling, gathering speed to a limit.
    rite.vy[i] = min(7.2, max(2.5, rite.vy[i] + 0.12));
    _r.y += rite.vy[i];
    _r.spin = 2.4 * (((_k mod 2) == 0) ? 1 : -1);

    // The ladder: a grain out either side, braking to hang, then sifting
    // down.
    if (_r.y > FIELD_Y0 + 20 && _r.y < FIELD_Y1 - 40
        && ((_t - _at) mod 13) == 0) {
        for (var _s = 0; _s < 2; _s++) {
            var _dir = _s * 180;
            var _u = fire(ring_rim_at_x(_r, _dir, 6), ring_rim_at_y(_r, _dir, 6),
                          5.0, _dir, BSHAPE_PELLET,
                          (_s == 0) ? BCOL_GOLD : BCOL_AMBER, 6);
            if (_u == undefined) continue;
            bullet_accel_at(_u, 2, -0.22, 0.3);
            bullet_force_at(_u, 60, 0, 0.035, BQ_KEEP, 2.4);
        }
    }
    if (_r.y > FIELD_Y0) rite_dismiss_if_clear(_r);
}

/// @desc The dancers: one after another along one great figure over the
///       whole field (a Lissajous curve), then rising away.
function rite_hoop_dance(_r, _t) {
    var _k = i - 11;
    var _d = _t - RITE_DANCE_AT + 60;
    // The figure, and each dancer a quarter of the way behind the last.
    var _ph = _d * 0.75 - _k * 55;
    var _fx = 680 + 500 * dsin(_ph * 1.0);
    var _fy = 440 + 300 * dsin(_ph * 1.5 + 30);
    // Coming in from above the top and, at the end, rising back out.
    var _in = clamp(_d / 90, 0, 1);
    var _out = clamp((_t - RITE_DANCE_OUT) / 80, 0, 1);
    var _lift = (1 - ease_apply(Ease.Out, _in)) * 700
                + ease_apply(Ease.In, _out) * 1100;
    if (_t < RITE_DANCE_AT - 60) {
        _r.x = FIELD_X0 + _fx;
        _r.y = FIELD_Y0 - 220;
        return;
    }
    _r.x = FIELD_X0 + _fx;
    _r.y = FIELD_Y0 + _fy - _lift;
    _r.spin = ring_vel_x(_r) * 0.9 + 0.3;
    if (_r.y > FIELD_Y0 + 20 && ((_t + _k * 3) mod 11) == 0) {
        rite_fling(_r, (_k mod 2 == 0) ? BCOL_GOLD : BCOL_AMBER);
    }
    if (_t > RITE_DANCE_OUT) rite_dismiss_if_clear(_r);
}

/// @desc Dismiss a ring once it is wholly off the field.
function rite_dismiss_if_clear(_r) {
    var _m = ring_radius(_r) + 8;
    if (_r.x < FIELD_X0 - _m || _r.x > FIELD_X1 + _m
        || _r.y < FIELD_Y0 - _m || _r.y > FIELD_Y1 + _m) {
        ring_dismiss(_r, 1);
    }
}

// ===========================================================================
// The hourglass rite (wave ten)
//
// Three rings fly one great upright figure of eight, top of the hall to
// bottom, a third of a lap apart, laying beads of sand behind them that hang
// where they were left and then pour down, so the figure empties into
// falling ropes wherever it has been; where a ring crosses the middle it lets
// go a small ring of motes. A fourth comes down and the four close into a
// diamond strung with current, which glides from side to side across the
// hall, turning, throwing knives off its rims and now and then a grain of
// glass at the player. The diamond collapses to a point, the four spin up and
// loose a sunflower of knives, and they rise away.
// ===========================================================================

#macro RITE_HG_CX 680              // field coordinates
#macro RITE_HG_CY 420
#macro RITE_HG_A 330               // the figure's lobes, either side...
#macro RITE_HG_B 300               // ...and half its height
#macro RITE_HG_RATE 0.7            // degrees of the figure a frame
#macro RITE_HG_ON 3                // rings flying the figure
#macro RITE_HG_IN 110              // arriving
#macro RITE_HG_POUR_TO 640         // the figure ends here
#macro RITE_HG_GATHER 650          // closing into the diamond...
#macro RITE_HG_GATHER_LEN 90
#macro RITE_HG_DIAMOND_R 230
#macro RITE_HG_LINK 780
#macro RITE_HG_UNLINK 990
#macro RITE_HG_COLLAPSE 1000       // drawing to a point...
#macro RITE_HG_BLOOM 1080          // ...the sunflower...
#macro RITE_HG_RISE 1140           // ...and away
#macro RITE_HG_TIME 1400           // a backstop

// Where the diamond glides (its middle swings this far either side of the
// hall's middle, and rises and falls a little), and where it collapses to.
#macro RITE_HG_DX 680
#macro RITE_HG_DY 380
#macro RITE_HG_SWING 300
#macro RITE_HG_PX 680
#macro RITE_HG_PY 210

function sanctum_rite_hourglass_wave(_e, _t) {
    array_push(_e, ev(_t + 1, wave_rite_hourglass()));
    return RITE_HG_RISE + 40;
}

function wave_rite_hourglass() {
    return function(_g) {
        var _rite = { ring: [], gen: [] };
        for (var _i = 0; _i < 4; _i++) {
            var _r = ring_new(FIELD_CX, FIELD_Y0 - 200, MIKA_RING_COL,
                              RITE_HG_TIME);
            if (_r == undefined) break;
            _r.cull = false;
            _r.act = method({ rite: _rite, i: _i }, rite_hg_ring);
            array_push(_rite.ring, _r);
            array_push(_rite.gen, _r.gen);
            var _p = rite_hg_where(_i, 0);
            _r.x = FIELD_X0 + _p[0];
            _r.y = FIELD_Y0 + _p[1];
        }
    };
}

/// @desc A point on the upright figure of eight at `_phi` degrees (field
///       coordinates), as `[x, y]`.
function rite_hg_figure(_phi) {
    return [RITE_HG_CX + RITE_HG_A * dsin(2 * _phi),
            RITE_HG_CY + RITE_HG_B * dsin(_phi)];
}

/// @desc How far round the figure ring `_i` (0 to 2) is at frame `_t`, in
///       degrees: a third of a lap apart, so no two cross the middle
///       together.
function rite_hg_phase(_i, _t) {
    return -90 + _i * 120 + RITE_HG_RATE * max(0, _t - RITE_HG_IN);
}

/// @desc The diamond: ring `_i`'s place on it at frame `_t`, as `[x, y]`.
function rite_hg_diamond(_i, _t) {
    var _turn = 0.7 * max(0, _t - (RITE_HG_GATHER + RITE_HG_GATHER_LEN));
    var _r = RITE_HG_DIAMOND_R;
    var _cx = rite_hg_diamond_x(min(_t, RITE_HG_COLLAPSE));
    var _cy = rite_hg_diamond_y(min(_t, RITE_HG_COLLAPSE));
    if (_t >= RITE_HG_COLLAPSE) {
        var _k = ease_apply(Ease.InOut, (_t - RITE_HG_COLLAPSE) / 80);
        _r = lerp(_r, 44, _k);
        _cx = lerp(_cx, RITE_HG_PX, _k);
        _cy = lerp(_cy, RITE_HG_PY, _k);
        // It spins up as it closes.
        var _d = _t - RITE_HG_COLLAPSE;
        _turn += 0.02 * _d * _d;
    }
    var _a = 90 + _i * 90 + _turn;
    return [_cx + lengthdir_x(_r, _a), _cy + lengthdir_y(_r, _a)];
}

/// @desc The diamond's middle at frame `_t` (field coordinates): gliding
///       from side to side across the hall, rising and falling a little.
function rite_hg_diamond_x(_t) {
    var _d = max(0, _t - RITE_HG_GATHER);
    return RITE_HG_DX + RITE_HG_SWING * dsin(_d * 0.62);
}

function rite_hg_diamond_y(_t) {
    var _d = max(0, _t - RITE_HG_GATHER);
    return RITE_HG_DY + 70 * dsin(_d * 1.24 + 90) - 70;
}

/// @desc Where ring `_i` is at frame `_t` (field coordinates), as `[x, y]`.
function rite_hg_where(_i, _t) {
    // The fourth waits above the field until the diamond.
    var _park = [RITE_HG_CX + 160, -190];

    // Arriving: each from above the top, down onto its place on the figure.
    if (_t < RITE_HG_IN) {
        if (_i >= RITE_HG_ON) return _park;
        var _k = ease_apply(Ease.Out, _t / RITE_HG_IN);
        var _to = rite_hg_figure(rite_hg_phase(_i, RITE_HG_IN));
        var _from = [_to[0], -200];
        return [lerp(_from[0], _to[0], _k), lerp(_from[1], _to[1], _k)];
    }

    var _here;
    if (_i < RITE_HG_ON) {
        _here = rite_hg_figure(rite_hg_phase(_i, min(_t, RITE_HG_GATHER)));
    } else {
        _here = _park;
    }
    if (_t < RITE_HG_GATHER) return _here;

    // Closing into the diamond, and in it.
    var _slot = rite_hg_diamond(_i, _t);
    if (_t < RITE_HG_GATHER + RITE_HG_GATHER_LEN) {
        var _k = ease_apply(Ease.InOut,
                            (_t - RITE_HG_GATHER) / RITE_HG_GATHER_LEN);
        return [lerp(_here[0], _slot[0], _k), lerp(_here[1], _slot[1], _k)];
    }
    if (_t < RITE_HG_RISE) return _slot;

    // Rising away, each fanning out a little as it goes.
    var _d = _t - RITE_HG_RISE;
    return [_slot[0] + (_i - 1.5) * _d * 1.6, _slot[1] - 0.05 * _d * _d];
}

/// @desc One ring of the hourglass rite, one frame (its `act`; bound to
///       `rite` and its index `i`).
function rite_hg_ring(_r, _g, _t) {
    var _p = rite_hg_where(i, _t);
    _r.x = FIELD_X0 + _p[0];
    _r.y = FIELD_Y0 + _p[1];
    _r.spin = (_t >= RITE_HG_COLLAPSE) ? 4.5 : ((i mod 2 == 0) ? 1.2 : -1.2);

    // The figure: beads off the trailing rim that hang, then pour.
    if (i < RITE_HG_ON && _t >= RITE_HG_IN && _t < RITE_HG_POUR_TO) {
        var _vx = ring_vel_x(_r);
        var _vy = ring_vel_y(_r);
        if (((_t + i) mod 3) == 0 && (_vx != 0 || _vy != 0)) {
            var _back = point_direction(0, 0, -_vx, -_vy);
            var _u = fire(ring_rim_at_x(_r, _back, 6),
                          ring_rim_at_y(_r, _back, 6), 0, 270,
                          BSHAPE_PELLET,
                          ((i mod 2) == 0) ? BCOL_AMBER : BCOL_GOLD, 6);
            if (_u != undefined) {
                bullet_force_at(_u, 50, 0, 0.05, BQ_KEEP, 4.2);
            }
        }
        // Crossing the middle of the figure: a small ring of motes.
        var _ph = rite_hg_phase(i, _t);
        if ((floor(_ph / 180) != floor((_ph - RITE_HG_RATE) / 180))) {
            ring_fire_rim(_r, 10, 2.2, _t * 7, BSHAPE_MOTE, BCOL_BONE, 8);
        }
    }

    // The diamond: flare, string current round it, and throw knives.
    if (_t == RITE_HG_LINK - RING_WARN) ring_charge(_r, RING_WARN, 30);
    if (_t == RITE_HG_LINK) {
        var _j = (i + 1) mod 4;
        if (_j < array_length(rite.ring)
            && ring_valid(rite.ring[_j], rite.gen[_j])) {
            ring_link(_r, rite.ring[_j], RITE_HG_UNLINK - RITE_HG_LINK);
        }
    }
    if (_t >= RITE_HG_GATHER + RITE_HG_GATHER_LEN && _t < RITE_HG_COLLAPSE) {
        var _out = point_direction(FIELD_X0 + rite_hg_diamond_x(_t),
                                   FIELD_Y0 + rite_hg_diamond_y(_t),
                                   _r.x, _r.y);
        if (((_t + i * 3) mod 10) == 0) {
            fire(ring_rim_at_x(_r, _out, 8), ring_rim_at_y(_r, _out, 8), 4.4,
                 _out + 58, BSHAPE_KNIFE, BCOL_BONE, 8);
        }
        if (((_t + i * 11) mod 45) == 0) {
            var _aim = point_direction(_r.x, _r.y, _g.player.x, _g.player.y);
            fire(ring_rim_at_x(_r, _aim, 12), ring_rim_at_y(_r, _aim, 12), 7.5,
                 _aim, BSHAPE_CRYSTAL, BCOL_AMBER, 12);
        }
    }

    // The sunflower: five courses of knives, each turned by the golden
    // angle from the last. Ring 0 throws it for all four, from the point
    // they have closed on.
    if (i == 0 && _t >= RITE_HG_BLOOM && _t < RITE_HG_BLOOM + 50
        && ((_t - RITE_HG_BLOOM) mod 10) == 0) {
        var _c = (_t - RITE_HG_BLOOM) div 10;
        var _bx = FIELD_X0 + RITE_HG_PX;
        var _by = FIELD_Y0 + RITE_HG_PY;
        fire_ring(_bx, _by, 24, 3.0 + _c * 0.6, _c * 137.5, BSHAPE_KNIFE,
                  ((_c mod 2) == 0) ? BCOL_GOLD : BCOL_AMBER, 10);
        fx_ring(_bx, _by, 20, 180, 20, global.bullet_colour[BCOL_GOLD], 0.7);
    }

    if (_t > RITE_HG_RISE) rite_dismiss_if_clear(_r);
}
