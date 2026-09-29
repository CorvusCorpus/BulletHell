/// @desc Stage three's timeline and its waves: five waves, the sand golem,
///       five more, then Mika.
///
/// Each wave is its own graded encounter (`ev_wave`), fifteen to twenty
/// seconds long. Waves one to four and six to nine are fodder (`sanctum_foes`)
/// flying routes (`enemy_routes`); waves five and ten are Mika's rings
/// passing through the hall, to be outlasted (`sanctum_ring_waves`). The
/// title card plays after the first wave. Between waves the timeline waits
/// for the medal to be thrown and flown home before anything new arrives.
///
/// Waves are written in their own frames from their marker: each
/// `sanctum_wave_N(events, t)` pushes its spawns at `t` plus a local time
/// and returns how long until its gate. The waves are placeholders in the
/// intended shape, each to be replaced in turn.

// Frames from a wave's gate releasing to the next thing arriving: the medal
// (`RANK_CARD_TIME`) and a breath.
#macro SANCTUM_BREATH 120

// Frames from the title card starting to the second wave's marker. Its first
// foes take another second or so to fly in.
#macro SANCTUM_TITLE_LEAD 170

// The orrery the spheres of waves three and eight turn round (field
// coordinates).
#macro SW_ORRERY_X 680
#macro SW_ORRERY_Y 330

/// @desc The ten waves in order: each wave's function and whether it is one
///       to outlast. The timeline and the screenshot scenes (`sanctum_w1`
///       ...) both read this.
function sanctum_wave_table() {
    return [
        { fn: sanctum_wave_1, survival: false },
        { fn: sanctum_wave_2, survival: false },
        { fn: sanctum_wave_3, survival: false },
        { fn: sanctum_wave_4, survival: false },
        { fn: sanctum_rite_hoops_wave, survival: true },
        { fn: sanctum_wave_6, survival: false },
        { fn: sanctum_wave_7, survival: false },
        { fn: sanctum_wave_8, survival: false },
        { fn: sanctum_wave_9, survival: false },
        { fn: sanctum_rite_hourglass_wave, survival: true },
    ];
}

/// @desc The running order.
function stage_sanctum_script() {
    var _e = [];
    var _w = sanctum_wave_table();

    // Everything waits for the hall to start waking (`hall_step`): the dark
    // lifts and the first torches catch before the first wave flies in.
    var _t = SANCTUM_OPENING;

    // --- the way in ------------------------------------------------------
    _t = sanctum_add_wave(_e, _t, _w[0].fn, _w[0].survival);
    array_push(_e, ev(_t, wave_title_card()));
    _t += SANCTUM_TITLE_LEAD;
    for (var _i = 1; _i < 5; _i++) {
        _t = sanctum_add_wave(_e, _t, _w[_i].fn, _w[_i].survival);
    }

    // --- the sand golem --------------------------------------------------
    array_push(_e, ev(_t, wave_boss(golem_spawn)));
    array_push(_e, ev_gate(_t + 20));
    // The hall opens (the camera rises and levels out). Stage time is held
    // while a boss is up, so this fires right after the golem falls.
    array_push(_e, ev(_t + 22, wave_bg_omen()));
    _t += 22 + 150;

    // --- deeper in -------------------------------------------------------
    for (var _i = 5; _i < 10; _i++) {
        _t = sanctum_add_wave(_e, _t, _w[_i].fn, _w[_i].survival);
    }

    // --- and Mika --------------------------------------------------------
    array_push(_e, ev(_t, wave_sweep_field()));
    array_push(_e, ev(_t + 60, wave_boss(mika_spawn)));

    return sanctum_sorted(_e);
}

/// @desc A timeline of wave `_n` (1 to 10) alone, for the screenshot scenes.
function sanctum_one_wave_script(_n) {
    var _all = sanctum_wave_table();
    var _w = _all[_n - 1];
    var _e = [];
    sanctum_add_wave(_e, 30, _w.fn, _w.survival);
    return sanctum_sorted(_e);
}

/// @desc Push one wave's marker, its spawns and its gate at `_t`; returns
///       when the next thing may come (its gate plus `SANCTUM_BREATH`).
///       `_survival` is a wave with nothing to shoot.
function sanctum_add_wave(_e, _t, _wave, _survival) {
    array_push(_e, ev_wave(_t, _survival));
    var _len = _wave(_e, _t + 1);
    array_push(_e, ev_gate(_t + 1 + _len));
    return _t + 1 + _len + SANCTUM_BREATH;
}

/// @desc The timeline in order of time, ties kept in the order they were
///       pushed (a wave's marker before its spawns).
function sanctum_sorted(_e) {
    var _n = array_length(_e);
    var _out = array_create(_n);
    for (var _i = 0; _i < _n; _i++) {
        var _v = _e[_i];
        var _j = _i - 1;
        while (_j >= 0 && _out[_j].at > _v.at) {
            _out[_j + 1] = _out[_j];
            _j--;
        }
        _out[_j + 1] = _v;
    }
    return _out;
}

/// @desc The direction from a foe to the player.
function sw_aim(_e, _g) {
    return aim_at(_e.x, _e.y, _g.player.x, _g.player.y);
}

/// @desc Fire one bullet `_off` pixels out from a foe along its heading, so
///       a stream comes out of the foe's edge instead of piling up over it.
function sw_fire_out(_e, _off, _spd, _dir, _shape, _col, _delay) {
    return fire(_e.x + lengthdir_x(_off * _e.scale, _dir),
                _e.y + lengthdir_y(_off * _e.scale, _dir), _spd, _dir, _shape,
                _col, _delay);
}

// ===========================================================================
// Wave 1 -- lamplighters (wisps; the way in)
//
// Stage three's opener. Two streams of wisps sweep in over both top corners
// at once and cross, each wisp firing stacks of tears at the player as it
// comes and leaving a small ring of slow orbs where it turns, so the aimed
// fire is dodged through a thin lattice. Five wisps then stand like candles
// across the top and let go rings, each candle turning its rings the
// opposite way to its neighbours so the lattices shear against each other,
// with a pair of fast grains either side of the player now and then. The
// streams come back through it throwing three-way fans.
// ===========================================================================

function sanctum_wave_1(_e, _t) {
    // At an even pace throughout (an eased leg would bunch the stream
    // where it slows).
    var _sweep = [
        leg_curve(620, 330, 180, 470, 110, Ease.Linear),
        leg_curve(1300, 90, 1060, 380, 110, Ease.Linear),
        leg_exit(25, 8, 1),
    ];
    for (var _k = 0; _k < 6; _k++) {
        for (var _side = 0; _side < 2; _side++) {
            array_push(_e, ev_foe(_t + 20 + _k * 16, EnemyKind.HallWisp, -60,
                                  110, 4, _sweep, sw_wisp_stream,
                                  { mirror: _side == 1, drops: [0, 0, 1] }));
        }
    }

    // The candles, from the middle outward, each turning its rings the other
    // way to the last.
    var _xs = [680, 480, 880, 280, 1080];
    var _spin = [1, -1, -1, 1, 1];
    for (var _k = 0; _k < 5; _k++) {
        var _route = [
            leg_to(_xs[_k], 230, 60, Ease.Out),
            leg_hold(190),
            leg_exit(90, 6.5),
        ];
        array_push(_e, ev_foe(_t + 330 + ((_k + 1) div 2) * 14,
                              EnemyKind.HallWisp, _xs[_k], -60, 16, _route,
                              sw_wisp_candle,
                              { scale: 1.2, drops: [0, 1, 2],
                                data: { spin: _spin[_k] } }));
    }

    for (var _k = 0; _k < 5; _k++) {
        for (var _side = 0; _side < 2; _side++) {
            array_push(_e, ev_foe(_t + 600 + _k * 16, EnemyKind.HallWisp, -60,
                                  110, 4, _sweep, sw_wisp_fan,
                                  { mirror: _side == 1, drops: [0, 0, 1] }));
        }
    }
    return 780;
}

/// @desc On the way in, a fast stack of three tears at the player every so
///       often; at the turn, a ring of slow orbs left behind.
function sw_wisp_stream(_e, _g, _t) {
    if (foe_leg(_e) > 1) return;
    if ((_t mod 40) == 20) {
        fire_stack(_e.x, _e.y, 2, 5.0, 1.4, sw_aim(_e, _g), BSHAPE_DROPLET,
                   BCOL_CYAN, 10);
    }
    if (foe_at(_e, 1, 0)) {
        fire_ring(_e.x, _e.y, 6, 2.2, _t * 7, BSHAPE_ORB, BCOL_SPRING, 8);
    }
}

/// @desc A three-way fan of tears at the turn.
function sw_wisp_fan(_e, _g, _t) {
    if (!foe_at(_e, 1, 0)) return;
    fire_fan(_e.x, _e.y, 3, 5.8, sw_aim(_e, _g), 24, BSHAPE_DROPLET,
             BCOL_SPRING, 12);
}

/// @desc Rings of orbs one after another, each turned a little further the
///       candle's own way; and between rings a pair of fast grains either
///       side of the player.
function sw_wisp_candle(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e) - 12;
    if (_lt >= 0 && (_lt mod 56) == 0) {
        var _n = _lt div 56;
        fire_ring(_e.x, _e.y, 14, 2.5, 90 + _n * 9 * _e.mem.data.spin,
                  BSHAPE_ORB, ((_n mod 2) == 0) ? BCOL_CYAN : BCOL_SPRING, 8);
    }
    if (_lt >= 0 && (_lt mod 70) == 35) {
        fire_fan(_e.x, _e.y, 2, 7.0, sw_aim(_e, _g), 10, BSHAPE_PELLET,
                 BCOL_BONE, 12);
    }
}

// ===========================================================================
// Wave 2 -- the reading room (spellbooks)
//
// Six books fly in from both sides to a shallow arc of stations and read out
// fans of pages at the player, odd fans and even fans in turn so each
// volley's gaps fall where the last one's pages were. Two great tomes then
// settle over the field and turn out spirals of pages in opposite senses,
// crossing into a lattice, with a fast stack of knives every so often.
// ===========================================================================

function sanctum_wave_2(_e, _t) {
    var _st = [[210, 200], [420, 150], [630, 118]];
    for (var _side = 0; _side < 2; _side++) {
        for (var _k = 0; _k < 3; _k++) {
            var _sx = _st[_k][0];
            var _sy = _st[_k][1];
            var _route = [
                leg_curve(_sx, _sy, _sx * 0.35, _sy + 250, 80, Ease.Out),
                leg_hold(270 + _k * 30),
                leg_curve(-120, _sy + 380, _sx, _sy + 300, 100, Ease.In),
                leg_exit(200, 8),
            ];
            array_push(_e, ev_foe(_t + 10 + _k * 18 + _side * 30,
                                  EnemyKind.HallBook, -90, _sy + 150, 16,
                                  _route, sw_book_fans,
                                  { mirror: _side == 1, data: { k: _k } }));
        }
    }

    for (var _side = 0; _side < 2; _side++) {
        var _route = [
            leg_to(420, 240, 90, Ease.Out),
            leg_hold(430),
            leg_exit(90, 5),
        ];
        array_push(_e, ev_foe(_t + 400, EnemyKind.HallBook, 420, -90, 110,
                              _route, sw_tome_spiral,
                              { mirror: _side == 1, scale: 1.4,
                                drops: [1, 2, 4] }));
    }
    return 900;
}

/// @desc Fans of pages at the player: five fast, then four slower (so the
///       aim line is a gap), in turn.
function sw_book_fans(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e) - 16 - _e.mem.data.k * 10;
    if (_lt < 0 || (_lt mod 48) != 0) return;
    if (((_lt div 48) mod 2) == 0) {
        fire_fan(_e.x, _e.y + 8, 5, 4.4, sw_aim(_e, _g), 48, BSHAPE_CARD,
                 BCOL_AZURE, 10);
    } else {
        fire_fan(_e.x, _e.y + 8, 4, 3.3, sw_aim(_e, _g), 42, BSHAPE_CARD,
                 BCOL_BONE, 10);
    }
}

/// @desc A two-armed spiral of pages that pick up speed as they go, turning
///       the way the tome's side says; and a fast stack of knives.
function sw_tome_spiral(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if (_lt < 30) return;
    if ((_lt mod 5) == 0) {
        var _a = _lt * 6.5 * foe_side(_e);
        for (var _k = 0; _k < 2; _k++) {
            var _u = sw_fire_out(_e, 34, 2.4, _a + _k * 180, BSHAPE_CARD,
                                 BCOL_INDIGO, 8);
            bullet_accel_at(_u, 20, 0.04, 4.2);
        }
    }
    if ((_lt mod 60) == 40) {
        fire_stack(_e.x, _e.y, 4, 7.0, 1.0, sw_aim(_e, _g), BSHAPE_KNIFE,
                   BCOL_BONE, 14);
    }
}

// ===========================================================================
// Wave 3 -- the orrery (armillary spheres)
//
// Eight spheres drop in one after another and swing into a single orbit, so
// they end up evenly spaced round it. Turning, each throws rice outward and a
// little ahead of itself, so the orrery sheds spiral arms; every two seconds
// all eight fire one fast grain at the player together. They break outward
// and four more materialise across the field, each throwing a crown of knives
// that stops dead, turns on the player and comes in.
// ===========================================================================

function sanctum_wave_3(_e, _t) {
    var _n = 8;
    var _gap = 24;
    var _r = 240;
    var _rate = 360 / (_n * _gap);          // so the eighth closes the circle
    var _arrive = 44;
    var _break = 10 + (_n - 1) * _gap + _arrive + 330;
    for (var _k = 0; _k < _n; _k++) {
        var _t0 = 10 + _k * _gap;
        var _dur = _break - (_t0 + _arrive);
        var _route = [
            // Into the top of the orbit already heading round it.
            leg_curve(SW_ORRERY_X, SW_ORRERY_Y - _r, SW_ORRERY_X + 150,
                      SW_ORRERY_Y - _r, _arrive, Ease.Out),
            leg_orbit(SW_ORRERY_X, SW_ORRERY_Y, _rate * _dur, _dur),
            leg_exit_radial(7),
        ];
        array_push(_e, ev_foe(_t + _t0, EnemyKind.HallSphere,
                              SW_ORRERY_X + 260, -80, 20, _route,
                              sw_orrery_sphere, { data: { t0: _t0 } }));
    }

    var _pos = [[300, 250], [1060, 250], [500, 440], [860, 440]];
    for (var _k = 0; _k < 4; _k++) {
        var _route = [leg_appear(40), leg_hold(270), leg_exit(90, 6)];
        array_push(_e, ev_foe(_t + 610 + (_k div 2) * 70, EnemyKind.HallSphere,
                              _pos[_k][0], _pos[_k][1], 26, _route,
                              sw_sphere_scissors, undefined));
    }
    return 1000;
}

/// @desc Rice thrown outward from the orrery and a little ahead of the
///       sphere's travel; every two seconds, all of them fire at the player
///       at once (they share the wave's clock through `t0`).
function sw_orrery_sphere(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _sync = _t + _e.mem.data.t0;
    if ((_sync mod 6) == 0) {
        var _out = point_direction(FIELD_X0 + SW_ORRERY_X,
                                   FIELD_Y0 + SW_ORRERY_Y, _e.x, _e.y);
        sw_fire_out(_e, 20, 3.6, _out + 24, BSHAPE_RICE, BCOL_GOLD, 6);
    }
    if ((_sync mod 90) == 60) {
        fire(_e.x, _e.y, 8, sw_aim(_e, _g), BSHAPE_RICE, BCOL_AMBER, 16);
    }
}

/// @desc A crown of knives thrown out fast that brake to a stop, hang, then
///       each turn on the player and accelerate in. Three crowns, each turned
///       half a step from the last.
function sw_sphere_scissors(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if (_lt != 20 && _lt != 110 && _lt != 200) return;
    var _a0 = (_lt div 90) * 15;
    for (var _k = 0; _k < 12; _k++) {
        var _u = fire(_e.x, _e.y, 9, _a0 + _k * 30, BSHAPE_KNIFE, BCOL_AMBER,
                      12);
        if (_u == undefined) continue;
        bullet_accel_at(_u, 0, -0.3, 0);
        bullet_aim_at(_u, 52);
        bullet_accel_at(_u, 52, 0.22, 7.5);
    }
}

// ===========================================================================
// Wave 4 -- the procession of lamps (all three)
//
// Streams of wisps weave across the top of the hall weeping tears, which
// hang a moment and fall, so the upper field is a moving curtain. Two books
// in the top corners snipe through it with fast cards. Halfway through, a
// great sphere materialises in the middle and turns out slow gears of large
// orbs, with a quick ring of grains between them.
// ===========================================================================

function sanctum_wave_4(_e, _t) {
    var _starts = [0, 200, 400, 600];
    var _ys = [140, 250, 140, 250];
    for (var _s = 0; _s < 4; _s++) {
        var _route = sw_weave_route(_ys[_s]);
        for (var _k = 0; _k < 7; _k++) {
            array_push(_e, ev_foe(_t + _starts[_s] + _k * 20, EnemyKind.HallWisp,
                                  -60, _ys[_s], 3, _route, sw_wisp_tears,
                                  { mirror: (_s mod 2) == 1,
                                    drops: [0, 0, 1] }));
        }
    }

    for (var _side = 0; _side < 2; _side++) {
        var _route = [
            leg_curve(150, 110, 40, 220, 70, Ease.Out),
            leg_hold(720),
            leg_curve(-120, 60, 90, 20, 70, Ease.In),
            leg_exit(180, 7),
        ];
        array_push(_e, ev_foe(_t + 40, EnemyKind.HallBook, -90, 250, 24,
                              _route, sw_book_snipe,
                              { mirror: _side == 1 }));
    }

    array_push(_e, ev_foe(_t + 390, EnemyKind.HallSphere, 680, 220, 150,
                          [leg_appear(50), leg_hold(420), leg_exit(90, 5)],
                          sw_sphere_gears,
                          { scale: 1.35, drops: [1, 2, 4] }));
    return 900;
}

/// @desc Across the field in a long wave, from the left edge (or the right,
///       mirrored) at height `_y`.
function sw_weave_route(_y) {
    return [
        leg_curve(340, _y + 70, 150, _y + 110, 80, Ease.Linear),
        leg_curve(680, _y - 10, 520, _y - 60, 80, Ease.Linear),
        leg_curve(1020, _y + 70, 850, _y + 110, 80, Ease.Linear),
        leg_curve(1440, _y, 1220, _y - 60, 90, Ease.Linear),
        leg_exit(0, 7),
    ];
}

/// @desc A tear every few frames that hangs, then falls, speeding up.
function sw_wisp_tears(_e, _g, _t) {
    if ((_t mod 16) != 6) return;
    var _u = fire(_e.x, _e.y + 10, 0.6, 270, BSHAPE_DROPLET, BCOL_CYAN, 8);
    bullet_force(_u, 0, 0.07, BQ_KEEP, 5.2);
}

/// @desc Three fast cards at the player.
function sw_book_snipe(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    if ((foe_leg_t(_e) mod 40) != 30) return;
    fire_fan(_e.x, _e.y, 3, 7.8, sw_aim(_e, _g), 12, BSHAPE_CARD, BCOL_AZURE,
             12);
}

/// @desc Four slow arms of large orbs turning like a gear, and a quick ring
///       of grains between turns.
function sw_sphere_gears(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if (_lt < 20) return;
    if ((_lt mod 14) == 0) {
        var _a = _lt * 0.64;
        for (var _k = 0; _k < 4; _k++) {
            sw_fire_out(_e, 40, 2.2, _a + _k * 90, BSHAPE_BALL, BCOL_GOLD, 10);
        }
    }
    if ((_lt mod 60) == 30) {
        fire_ring(_e.x, _e.y, 20, 3.4, _lt * 1.3, BSHAPE_PELLET, BCOL_AMBER, 8);
    }
}

// ===========================================================================
// Wave 6 -- the midnight carousel (spellbooks)
//
// Eight books come down as one wheel, turning, and throw pages outward from
// its hub, so it sheds curving arms; then the wheel lifts away. Two great
// tomes hold the sides with fast knives. Last, a line of books crosses each
// way along the top, raining cards.
// ===========================================================================

function sanctum_wave_6(_e, _t) {
    var _n = 8;
    for (var _k = 0; _k < _n; _k++) {
        var _a0 = 90 + _k * (360 / _n);
        array_push(_e, ev_foe(_t + 1, EnemyKind.HallBook,
                              680 + lengthdir_x(SW_WHEEL_R, _a0),
                              SW_WHEEL_Y0 + lengthdir_y(SW_WHEEL_R, _a0), 18,
                              [leg_path(sw_wheel_path, SW_WHEEL_TIME),
                               leg_exit(90, 8)],
                              sw_wheel_book,
                              { data: { a0: _a0, k: _k } }));
    }

    for (var _side = 0; _side < 2; _side++) {
        var _route = [
            leg_curve(140, 420, 60, 300, 80, Ease.Out),
            leg_hold(420),
            leg_curve(-130, 520, 60, 540, 80, Ease.In),
            leg_exit(180, 7),
        ];
        array_push(_e, ev_foe(_t + 300, EnemyKind.HallBook, -100, 300, 110,
                              _route, sw_tome_knives,
                              { mirror: _side == 1, scale: 1.4,
                                drops: [1, 2, 4] }));
    }

    for (var _side = 0; _side < 2; _side++) {
        var _y = (_side == 0) ? 170 : 250;
        var _route = [leg_to(1460, _y + 20, 320, Ease.Linear), leg_exit(0, 7)];
        for (var _k = 0; _k < 6; _k++) {
            array_push(_e, ev_foe(_t + 600 + _side * 150 + _k * 22,
                                  EnemyKind.HallBook, -90, _y, 14, _route,
                                  sw_book_rain,
                                  { mirror: _side == 1, data: { k: _k } }));
        }
    }
    return 1000;
}

// The wheel: its radius, where its hub starts (above the field), where it
// turns, and how long it is on the field before it lifts away.
#macro SW_WHEEL_R 220
#macro SW_WHEEL_Y0 -140
#macro SW_WHEEL_Y1 270
#macro SW_WHEEL_TIME 640

/// @desc A book's place on the wheel: the hub comes down, holds while the
///       wheel turns, and lifts away.
function sw_wheel_path(_e, _k, _lt) {
    var _d = _e.mem.data;
    var _cy;
    if (_lt < 150) {
        _cy = lerp(SW_WHEEL_Y0, SW_WHEEL_Y1, ease_apply(Ease.Out, _lt / 150));
    } else if (_lt < SW_WHEEL_TIME - 160) {
        _cy = SW_WHEEL_Y1;
    } else {
        var _f = (_lt - (SW_WHEEL_TIME - 160)) / 160;
        _cy = lerp(SW_WHEEL_Y1, SW_WHEEL_Y0 - 200, ease_apply(Ease.In, _f));
    }
    _e.mem.ox = FIELD_X0 + 680;
    _e.mem.oy = FIELD_Y0 + _cy;
    var _a = _d.a0 + _lt * 0.8;
    _e.x = _e.mem.ox + lengthdir_x(SW_WHEEL_R, _a);
    _e.y = _e.mem.oy + lengthdir_y(SW_WHEEL_R, _a);
}

/// @desc Two pages outward from the wheel's hub, every sixteen frames.
function sw_wheel_book(_e, _g, _t) {
    if (foe_leg(_e) != 0) return;
    var _lt = foe_leg_t(_e);
    if (_lt < 90 || ((_lt + _e.mem.data.k * 2) mod 16) != 0) return;
    var _out = point_direction(_e.mem.ox, _e.mem.oy, _e.x, _e.y);
    var _col = ((_e.mem.data.k mod 2) == 0) ? BCOL_INDIGO : BCOL_AZURE;
    fire(_e.x, _e.y, 3.4, _out + 8, BSHAPE_CARD, _col, 8);
    fire(_e.x, _e.y, 3.4, _out - 8, BSHAPE_CARD, _col, 8);
}

/// @desc A fast stack of five knives at the player, and a slower three-way
///       of cards between.
function sw_tome_knives(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if ((_lt mod 60) == 20) {
        fire_stack(_e.x, _e.y, 5, 6, 1, sw_aim(_e, _g), BSHAPE_KNIFE,
                   BCOL_BONE, 14);
    }
    if ((_lt mod 60) == 50) {
        fire_fan(_e.x, _e.y, 3, 4.6, sw_aim(_e, _g), 40, BSHAPE_CARD,
                 BCOL_INDIGO, 10);
    }
}

/// @desc A narrow fan of cards straight down, every so often.
function sw_book_rain(_e, _g, _t) {
    if (((_t + _e.mem.data.k * 5) mod 24) != 0) return;
    fire_fan(_e.x, _e.y, 3, 5.0, 270, 24, BSHAPE_CARD, BCOL_BONE, 8);
}

// ===========================================================================
// Wave 7 -- the soul tide (wisps)
//
// Vees of wisps drop in and dive at the player, stop short, throw tears at
// close range and climb away. Two great wisps materialise and breathe rings
// of flame that curl as they spread, one each way. Streams of wisps cross
// the middle of the hall, each firing one fast grain as it turns.
// ===========================================================================

function sanctum_wave_7(_e, _t) {
    var _vx = [340, 1020, 680, 460, 900];
    var _vt = [0, 130, 260, 400, 400];
    for (var _v = 0; _v < 5; _v++) {
        sw_push_vee(_e, _t + _vt[_v], _vx[_v], (_vx[_v] < 680) ? -1 : 1);
    }

    for (var _side = 0; _side < 2; _side++) {
        array_push(_e, ev_foe(_t + 520, EnemyKind.HallWisp, 360, 330, 50,
                              [leg_appear(45), leg_hold(330), leg_exit(90, 5)],
                              sw_wisp_bloom,
                              { mirror: _side == 1, scale: 1.5,
                                drops: [1, 1, 3] }));
    }

    var _cross = [
        leg_curve(420, 260, 200, 470, 90, Ease.Linear),
        leg_curve(900, -100, 700, 150, 90, Ease.Linear),
        leg_exit(90, 8, 1),
    ];
    for (var _side = 0; _side < 2; _side++) {
        for (var _k = 0; _k < 8; _k++) {
            array_push(_e, ev_foe(_t + 620 + _side * 80 + _k * 14,
                                  EnemyKind.HallWisp, -60, 420, 3, _cross,
                                  sw_wisp_snap,
                                  { mirror: _side == 1, drops: [0, 0, 1] }));
        }
    }
    return 980;
}

/// @desc A vee of five wisps over column `_x` that drops in, dives at the
///       player, fires, and climbs away toward `_away` (-1 left, +1 right).
function sw_push_vee(_e, _t, _x, _away) {
    var _ox = [0, -55, 55, -110, 110];
    var _oy = [0, -40, -40, -80, -80];
    for (var _k = 0; _k < 5; _k++) {
        var _px = _x + _ox[_k];
        var _route = [
            leg_to(_px, 200 + _oy[_k], 60, Ease.Out),
            leg_hold(18),
            leg_aim(280, 50, Ease.InOut, 170),
            leg_hold(26),
            leg_curve(_px + _away * 520, -120, _px + _away * 80, 140, 80,
                      Ease.In),
            leg_exit(90, 8),
        ];
        array_push(_e, ev_foe(_t, EnemyKind.HallWisp, _px, -60 + _oy[_k], 4,
                              _route, sw_wisp_dive, { drops: [0, 0, 1] }));
    }
}

/// @desc Tears at close range, once the dive has stopped.
function sw_wisp_dive(_e, _g, _t) {
    if (!foe_at(_e, 3, 4)) return;
    fire_fan(_e.x, _e.y, 3, 6.0, sw_aim(_e, _g), 26, BSHAPE_DROPLET,
             BCOL_CYAN, 14);
}

/// @desc Rings of flame that curl as they spread, the way the wisp's side
///       says, then run straight.
function sw_wisp_bloom(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if ((_lt mod 80) != 20) return;
    var _turn = 0.55 * foe_side(_e);
    var _a0 = (_lt div 80) * 9;
    for (var _k = 0; _k < 20; _k++) {
        var _u = sw_fire_out(_e, 26, 3.4, _a0 + _k * 18, BSHAPE_FLAME,
                             BCOL_CYAN, 10);
        bullet_turn_at(_u, 0, _turn);
        bullet_turn_at(_u, 70, 0);
    }
}

/// @desc One fast grain at the player as the stream turns.
function sw_wisp_snap(_e, _g, _t) {
    if (!foe_at(_e, 1, 0)) return;
    fire(_e.x, _e.y, 7.2, sw_aim(_e, _g), BSHAPE_PELLET, BCOL_SPRING, 12);
}

// ===========================================================================
// Wave 8 -- clockwork heavens (armillary spheres)
//
// Six spheres materialise on a wide orbit and three on a close one, turning
// opposite ways. The wide ring sheds grains outward in a turning sunburst and
// now and then a fast stack at the player; the close ring takes turns firing
// telegraphed beams at the player. Then the whole engine flies apart.
// ===========================================================================

function sanctum_wave_8(_e, _t) {
    for (var _k = 0; _k < 6; _k++) {
        var _a = 90 + _k * 60;
        array_push(_e, ev_foe(_t + 10 + _k * 8, EnemyKind.HallSphere,
                              SW_ORRERY_X + lengthdir_x(320, _a),
                              SW_ORRERY_Y + lengthdir_y(320, _a), 22,
                              [leg_appear(40),
                               leg_orbit(SW_ORRERY_X, SW_ORRERY_Y, -270,
                                         540 - _k * 8),
                               leg_exit_radial(6)],
                              sw_engine_outer, { data: { k: _k } }));
    }
    for (var _k = 0; _k < 3; _k++) {
        var _a = 30 + _k * 120;
        array_push(_e, ev_foe(_t + 60 + _k * 8, EnemyKind.HallSphere,
                              SW_ORRERY_X + lengthdir_x(140, _a),
                              SW_ORRERY_Y + lengthdir_y(140, _a), 30,
                              [leg_appear(40),
                               leg_orbit(SW_ORRERY_X, SW_ORRERY_Y, 500,
                                         500 - _k * 8),
                               leg_exit_radial(6)],
                              sw_engine_inner,
                              { data: { k: _k, beam: undefined } }));
    }
    return 800;
}

/// @desc Grains outward in a turning sunburst; a fast stack at the player
///       every two and a half seconds.
function sw_engine_outer(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if ((_lt mod 12) == 0) {
        var _out = point_direction(FIELD_X0 + SW_ORRERY_X,
                                   FIELD_Y0 + SW_ORRERY_Y, _e.x, _e.y);
        fire(_e.x, _e.y, 3.2, _out - 20, BSHAPE_PELLET, BCOL_GOLD, 6);
    }
    if (((_lt + _e.mem.data.k * 25) mod 150) == 90) {
        fire_stack(_e.x, _e.y, 3, 6, 1, sw_aim(_e, _g), BSHAPE_RICE,
                   BCOL_AMBER, 14);
    }
}

/// @desc A telegraphed beam at the player, the three taking turns. The beam
///       rides a marker the sphere moves each frame, so it neither drifts off
///       the sphere nor follows a slot the pool has handed to someone else.
function sw_engine_inner(_e, _g, _t) {
    var _d = _e.mem.data;
    if (_d.beam != undefined) {
        _d.beam.x = _e.x;
        _d.beam.y = _e.y;
    }
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if (((_lt + _d.k * 36) mod 108) != 60) return;
    _d.beam = { x: _e.x, y: _e.y };
    var _l = laser_beam(_e.x, _e.y, sw_aim(_e, _g), 1800, 20, BCOL_AMBER, 40,
                        18, 14);
    if (_l != undefined) _l.src = _d.beam;
}

// ===========================================================================
// Wave 9 -- the grand procession (all three)
//
// Two columns of books come slowly down the sides and throw fans of cards
// across the hall at each other, crossing into a mesh. A great sphere in the
// middle turns out a three-armed pinwheel of rice, and vees of wisps dive
// through it all.
// ===========================================================================

function sanctum_wave_9(_e, _t) {
    for (var _side = 0; _side < 2; _side++) {
        for (var _k = 0; _k < 4; _k++) {
            var _route = [
                leg_to(250, 120 + _k * 110, 300, Ease.Out),
                leg_hold(220 - _k * 20),
                leg_exit(180, 6),
            ];
            array_push(_e, ev_foe(_t + _k * 24, EnemyKind.HallBook, 250,
                                  -80 - _k * 40, 18, _route, sw_book_mesh,
                                  { mirror: _side == 1, data: { k: _k } }));
        }
    }

    array_push(_e, ev_foe(_t + 220, EnemyKind.HallSphere, 680, 200, 150,
                          [leg_appear(50), leg_hold(520), leg_exit(90, 5)],
                          sw_sphere_pinwheel,
                          { scale: 1.4, drops: [1, 2, 4] }));

    sw_push_vee(_e, _t + 420, 420, -1);
    sw_push_vee(_e, _t + 560, 940, 1);
    sw_push_vee(_e, _t + 700, 680, 1);
    return 980;
}

/// @desc A fan of cards across the hall, dipping a little.
function sw_book_mesh(_e, _g, _t) {
    if (_t < 60 || ((_t + _e.mem.data.k * 10) mod 56) != 0) return;
    var _dir = (foe_side(_e) > 0) ? -12 : 192;
    fire_fan(_e.x, _e.y, 3, 3.8, _dir, 22, BSHAPE_CARD,
             ((_e.mem.data.k mod 2) == 0) ? BCOL_AZURE : BCOL_BONE, 8);
}

/// @desc Three arms of rice turning steadily, each grain picking up speed.
function sw_sphere_pinwheel(_e, _g, _t) {
    if (foe_leg(_e) != 1) return;
    var _lt = foe_leg_t(_e);
    if (_lt < 20 || (_lt mod 6) != 0) return;
    var _a = _lt * 0.92;
    for (var _k = 0; _k < 3; _k++) {
        var _u = sw_fire_out(_e, 36, 3.0, _a + _k * 120, BSHAPE_RICE,
                             BCOL_GOLD, 6);
        bullet_accel_at(_u, 12, 0.03, 4.6);
    }
}
