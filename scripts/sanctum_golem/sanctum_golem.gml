/// @desc The sand golem: stage three's midboss, three non-spells.
///
/// A sand elemental: a hulking torso of churning, wind-blown sand with
/// burning eyes, rising out of its own turning column of sand, its arms
/// streams of sand ending in clenched clumps of it. The one hard thing in it
/// is its heart, a small gold amulet set with a carnelian, which binds the
/// sand to the hall. Its parts are sprites from `tools/make_sanctum_foes.py`
/// (the body and the light in its eyes, heart and seams, both animated in
/// step, and a fist); here they are put together and moved. The fists are
/// only drawn: shots and the player pass through them, and only the body's
/// radius counts.
///
/// Its non-spells:
///   1. Rockslide: a fist rises and slams, throwing a boulder that bursts into
///      sand and a fan of fast rice, while its heart turns out three slow
///      arms of motes.
///   2. Dune sprinklers: both fists held out, each sweeping out sand that
///      brakes and bends, the two woven against each other; its eyes fire
///      fast glass at the player.
///   3. Sandfall: it claps overhead and a dome of sand goes up, stops, and
///      rains; between claps the fists fire fast knives.
///
/// Its attacks are placeholders in the intended shape.

// Where its parts are, from its origin (the heart), matching the art.
#macro GOLEM_EYES_DY -117
#macro GOLEM_HEART_DY 22
#macro GOLEM_SHOULDER_DX 138
#macro GOLEM_SHOULDER_DY -40

// Game frames per frame of its churning.
#macro GOLEM_CHURN 5
#macro GOLEM_FIST_REST_DX 208
#macro GOLEM_FIST_REST_DY 64

// The fists are springs toward where the attack wants them.
#macro GOLEM_FIST_K 0.09
#macro GOLEM_FIST_DAMP 0.26

// The column of sand it stands on: how far below the heart it starts, how
// deep it runs, and how wide it is at the top.
#macro GOLEM_VORTEX_DY 92
#macro GOLEM_VORTEX_H 110
#macro GOLEM_VORTEX_W 104

// Frames it takes to crumble when beaten (before `boss_act` flies it off).
#macro GOLEM_CRUMBLE 70

function golem_def() {
    return {
        name: "THE SAND GOLEM",
        title: "keeper of the hall's door",
        sprite: spr_golem_body,
        col: BCOL_AMBER,
        radius: 78,
        spell_bg: SPELLBG_SIGIL,
        final: false,
        step: golem_step,
        draw: golem_draw,
    };
}

function golem_phases() {
    return [
        { kind: AttackKind.NonSpell, name: "", col: BCOL_AMBER, bg: -1,
          hp_end: 2 / 3, time: 30 * FPS, attack: golem_rockslide,
          move: BossMove.Close, fire_at: 30 },
        { kind: AttackKind.NonSpell, name: "", col: BCOL_GOLD, bg: -1,
          hp_end: 1 / 3, time: 30 * FPS, attack: golem_sprinklers,
          move: BossMove.Fixed, fire_at: 40 },
        { kind: AttackKind.NonSpell, name: "", col: BCOL_AMBER, bg: -1,
          hp_end: 0, time: 32 * FPS, attack: golem_sandfall,
          move: BossMove.Step, fire_at: 50 },
    ];
}

function golem_spawn(_g) {
    var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 180, 1020, golem_phases(),
                        golem_def());
    if (_b != undefined) {
        _b.boss.home_y = BOSS_HOME_Y - 10;
        _b.boss.declare_t = 40;      // a midboss gets no name splash
        _b.mem = golem_body_new();
    }
    return _b;
}

/// @desc The golem's body: where each fist is (from the heart), its
///       velocity, and where the attack wants it; and the light in its eyes.
function golem_body_new() {
    return {
        fx: [-GOLEM_FIST_REST_DX, GOLEM_FIST_REST_DX],
        fy: [GOLEM_FIST_REST_DY, GOLEM_FIST_REST_DY],
        vx: [0, 0],
        vy: [0, 0],
        tx: [-GOLEM_FIST_REST_DX, GOLEM_FIST_REST_DX],
        ty: [GOLEM_FIST_REST_DY, GOLEM_FIST_REST_DY],
        // A fist's turn, in degrees (a slam tips it forward).
        tilt: [0, 0],
        flare: 0,           // eyes and heart, lit up to 1 and fading
        slam: [0, 0],       // a fist's own flash as it strikes
    };
}

/// @desc Where the attack wants fist `_k` (0 left, 1 right), from the heart.
function golem_fist_to(_e, _k, _dx, _dy) {
    _e.mem.tx[_k] = _dx;
    _e.mem.ty[_k] = _dy;
}

/// @desc Both fists back to rest.
function golem_fists_rest(_e) {
    golem_fist_to(_e, 0, -GOLEM_FIST_REST_DX, GOLEM_FIST_REST_DY);
    golem_fist_to(_e, 1, GOLEM_FIST_REST_DX, GOLEM_FIST_REST_DY);
}

/// @desc Fist `_k`'s place on the field.
function golem_fist_x(_e, _k) {
    return _e.x + _e.mem.fx[_k];
}

function golem_fist_y(_e, _k) {
    return _e.y + _e.mem.fy[_k];
}

// ---------------------------------------------------------------------------
// Every frame (`def.step`, called by `boss_act`)
// ---------------------------------------------------------------------------

function golem_step(_e, _g) {
    var _m = _e.mem;
    var _b = _e.boss;

    // Between attacks, and before the first, the fists go back to rest.
    if (_b.phase < 0 || _b.clear_t > 0 || _b.beaten) golem_fists_rest(_e);

    for (var _k = 0; _k < 2; _k++) {
        // Idling, each fist floats on its own slow swell.
        var _bob = dsin(_e.t * 2.1 + _k * 140) * 7;
        _m.vx[_k] += (_m.tx[_k] - _m.fx[_k]) * GOLEM_FIST_K
                     - _m.vx[_k] * GOLEM_FIST_DAMP;
        _m.vy[_k] += (_m.ty[_k] + _bob - _m.fy[_k]) * GOLEM_FIST_K
                     - _m.vy[_k] * GOLEM_FIST_DAMP;
        _m.fx[_k] += _m.vx[_k];
        _m.fy[_k] += _m.vy[_k];
        // It tips with how fast it is falling.
        _m.tilt[_k] = lerp(_m.tilt[_k], clamp(_m.vy[_k] * 2.2, -30, 30)
                           * ((_k == 0) ? -1 : 1), 0.3);
        _m.slam[_k] = max(0, _m.slam[_k] - 0.06);
    }
    _m.flare = max(0, _m.flare - 0.035);

    if (!foe_inside(_e, -200)) return;

    // Sand spilling from under the torso.
    if ((_e.t mod 3) == 0 && !_b.beaten) {
        fx_piece(_e.x + random_range(-60, 60), _e.y + GOLEM_VORTEX_DY
                 + GOLEM_VORTEX_H * random_range(0.2, 0.9),
                 random_range(-0.4, 0.4), random_range(0.3, 1.2), spr_fx_grit,
                 irandom(2), irandom_range(40, 70), random_range(6, 10), 0,
                 0.05, 0.99, c_white, 0.5);
    }

    // Arriving: sand gathering in from all round.
    if (_b.entry_t > 0) {
        repeat (3) {
            var _d = random(360);
            var _r = random_range(160, 260);
            var _sx = _e.x + lengthdir_x(_r, _d);
            var _sy = _e.y + lengthdir_y(_r, _d) * 0.8;
            fx_piece(_sx, _sy, (_e.x - _sx) * 0.035, (_e.y - _sy) * 0.035,
                     spr_fx_grit, irandom(2), 30, random_range(7, 11), 0, 0,
                     1.0, c_white, 0.8);
        }
    }

    // Beaten: it comes apart and pours away.
    if (_b.beaten && _b.death_t < GOLEM_CRUMBLE) {
        repeat (6) {
            fx_piece(_e.x + random_range(-150, 150), _e.y + random_range(-150, 90),
                     random_range(-1.5, 1.5), random_range(-1, 1),
                     spr_fx_grit, irandom(2), irandom_range(50, 90),
                     random_range(8, 14), random_range(-5, 5), 0.14, 0.98,
                     c_white, 0.5);
        }
    }
}

// ---------------------------------------------------------------------------
// Drawing (`def.draw`, called by `boss_draw` in place of its sprite)
// ---------------------------------------------------------------------------

function golem_draw(_e) {
    var _m = _e.mem;
    var _b = _e.boss;
    var _t = _e.t;

    // How whole it is: gathering on arrival, crumbling when beaten.
    var _whole = 1;
    if (_b.entry_t > 0) {
        _whole = clamp(1.25 * (1 - _b.entry_t / BOSS_ENTRY_TIME), 0, 1);
    }
    if (_b.beaten) _whole = clamp(1 - _b.death_t / GOLEM_CRUMBLE, 0, 1);
    if (_whole <= 0.01) return;

    var _bob = dsin(_t * 1.5) * 6;
    var _x = _e.x;
    var _y = _e.y + _bob;

    golem_draw_vortex(_x, _y, _t, _whole);
    for (var _k = 0; _k < 2; _k++) golem_draw_stream(_e, _k, _x, _y, _t, _whole);

    // A warm light round it.
    draw_bloom(_x, _y + 20, 520, $3C9AE0, 0.22 * _whole);

    var _fr = (_t div GOLEM_CHURN) mod sprite_get_number(spr_golem_body);
    draw_sprite_ext(spr_golem_body, _fr, _x, _y, 1, 1, 0, c_white, _whole);

    // The fire in it (eyes, heart, the gaps in the sand): a slow breath,
    // and a flare when it strikes.
    var _glow = (0.45 + 0.15 * dsin(_t * 3.1) + 0.6 * _m.flare) * _whole;
    gpu_set_blendmode(bm_add);
    draw_sprite_ext(spr_golem_glow, _fr, _x, _y, 1, 1, 0, c_white,
                    min(1, _glow));
    gpu_set_blendmode(bm_normal);
    draw_bloom(_x, _y + GOLEM_HEART_DY, 90 + 60 * _m.flare, $40B8FF,
               (0.30 + 0.35 * _m.flare) * _whole);
    for (var _s = -1; _s <= 1; _s += 2) {
        draw_bloom(_x + _s * 22, _y + GOLEM_EYES_DY, 44 + 50 * _m.flare,
                   $40C8FF, (0.25 + 0.5 * _m.flare) * _whole);
    }

    for (var _k = 0; _k < 2; _k++) {
        var _fx = _x + _m.fx[_k];
        var _fy = _y + _m.fy[_k];
        var _xs = (_k == 0) ? 1 : -1;
        var _ff = ((_t div GOLEM_CHURN) + _k * 3)
                  mod sprite_get_number(spr_golem_fist);
        draw_sprite_ext(spr_golem_fist, _ff, _fx, _fy, _xs, 1, _m.tilt[_k],
                        c_white, _whole);
        if (_m.slam[_k] > 0) {
            draw_bloom(_fx, _fy + 30, 160 * _m.slam[_k] + 40, $40C0FF,
                       _m.slam[_k] * 0.5);
        }
    }

    // Hit flash: the sand added again in white.
    if (_e.flash > 0) {
        var _fa = _e.flash / ENEMY_FLASH * 0.30 * _whole;
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_golem_body, _fr, _x, _y, 1, 1, 0, c_white, _fa);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The column of sand it stands on: grains wound round a narrowing
///       spiral, the far side dimmer, turning faster toward the foot.
function golem_draw_vortex(_x, _y, _t, _a) {
    var _n = 80;
    draw_bloom(_x, _y + GOLEM_VORTEX_DY + GOLEM_VORTEX_H * 0.45, 260,
               $2E88D8, 0.20 * _a);
    for (var _i = 0; _i < _n; _i++) {
        var _h = frac(_i * 0.6180339 + _t * 0.004);
        var _rad = lerp(GOLEM_VORTEX_W, 14, _h * _h * 0.8 + _h * 0.2);
        var _ang = _i * 137.5 + _t * (3.5 + 5 * _h);
        var _front = dsin(_ang);
        var _px = _x + dcos(_ang) * _rad;
        var _py = _y + GOLEM_VORTEX_DY + _h * GOLEM_VORTEX_H
                  + _front * _rad * 0.22;
        var _al = _a * (0.35 + 0.45 * (0.5 + 0.5 * _front))
                  * min(1, (1 - _h) * 4);
        var _sz = (0.55 + 0.35 * (0.5 + 0.5 * _front)) * (1 - _h * 0.4);
        draw_sprite_ext(spr_fx_grit, _i mod 3, _px, _py, _sz, _sz,
                        _ang * 2, c_white, _al);
    }
}

/// @desc Its arm: sand streaming from shoulder `_k` to its fist along a
///       sagging curve, as a haze of dust under grains that flow down it and
///       waver across it, thickest at the shoulder.
function golem_draw_stream(_e, _k, _x, _y, _t, _a) {
    var _s = (_k == 0) ? -1 : 1;
    var _x0 = _x + _s * GOLEM_SHOULDER_DX;
    var _y0 = _y + GOLEM_SHOULDER_DY;
    var _x1 = _x + _e.mem.fx[_k];
    var _y1 = _y + _e.mem.fy[_k] - 40;
    var _cx = (_x0 + _x1) * 0.5;
    var _cy = max(_y0, _y1) + 40;

    // The haze.
    var _bw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i <= 12; _i++) {
        var _u = _i / 12;
        var _v = 1 - _u;
        var _px = _v * _v * _x0 + 2 * _v * _u * _cx + _u * _u * _x1;
        var _py = _v * _v * _y0 + 2 * _v * _u * _cy + _u * _u * _y1;
        var _sz = lerp(96, 54, _u) / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _px, _py, _sz, _sz, 0, $4C86C8,
                        _a * 0.22);
    }

    // The grains.
    var _n = 44;
    for (var _i = 0; _i < _n; _i++) {
        var _u = frac(_i / _n + _t * 0.016);
        var _v = 1 - _u;
        var _px = _v * _v * _x0 + 2 * _v * _u * _cx + _u * _u * _x1;
        var _py = _v * _v * _y0 + 2 * _v * _u * _cy + _u * _u * _y1;
        var _spread = lerp(22, 12, _u);
        var _w = dsin(_i * 97 + _t * 6) * _spread;
        var _al = _a * min(1, sin(_u * pi) * 2) * 0.9;
        var _sz = 0.7 + 0.5 * frac(_i * 0.618);
        draw_sprite_ext(spr_fx_grit, _i mod 3, _px + _w, _py + _w * 0.45,
                        _sz, _sz, _i * 40 + _t * 3, c_white, _al);
    }
}

// ---------------------------------------------------------------------------
// Non-spell 1: rockslide
// ---------------------------------------------------------------------------

#macro GOLEM_SLAM_CYCLE 110
#macro GOLEM_SLAM_AT 34            // frames from the rise to the strike

function golem_rockslide(_e, _g, _t) {
    var _c = _t mod GOLEM_SLAM_CYCLE;
    var _k = (_t div GOLEM_SLAM_CYCLE) mod 2;
    var _s = (_k == 0) ? -1 : 1;

    // The fist rises, strikes down and forward, and settles.
    if (_c == 0) golem_fist_to(_e, _k, _s * 170, -70);
    if (_c == GOLEM_SLAM_AT - 6) golem_fist_to(_e, _k, _s * 150, 150);
    if (_c == GOLEM_SLAM_AT + 24) {
        golem_fist_to(_e, _k, _s * GOLEM_FIST_REST_DX, GOLEM_FIST_REST_DY);
    }

    if (_c == GOLEM_SLAM_AT) {
        var _fx = golem_fist_x(_e, _k);
        var _fy = golem_fist_y(_e, _k) + 30;
        var _aim = aim_at(_fx, _fy, _g.player.x, _g.player.y);
        _e.mem.slam[_k] = 1;
        _e.mem.flare = 0.6;
        fx_shake(6);
        fx_ring(_fx, _fy, 20, 150, 18, $40C0FF, 0.7);

        // The boulder: slow, then it bursts into sand that brakes and hangs.
        var _u = fire(_fx, _fy, 3.6, _aim, BSHAPE_SPHERE, BCOL_AMBER, 10);
        // As a method: a split only calls back a method, not a bare
        // function.
        bullet_split_at(_u, 55, 14, 3.4, (_t div GOLEM_SLAM_CYCLE) * 13,
                        method(undefined, golem_rubble_dress));

        // And a fast fan of rice off the strike.
        fire_fan(_fx, _fy, 9, 7.2, _aim, 72, BSHAPE_RICE, BCOL_BONE, 12);
    }

    // Its heart turns out three slow arms of motes all the while.
    if (_t >= 30 && (_t mod 6) == 0) {
        var _a = _t * 1.8;
        for (var _i = 0; _i < 3; _i++) {
            fire(_e.x, _e.y + GOLEM_HEART_DY, 2.7, _a + _i * 120, BSHAPE_MOTE,
                 BCOL_AMBER, 6);
        }
    }
}

/// @desc A boulder's rubble: grains that brake to a crawl and drift on.
function golem_rubble_dress(_c, _k) {
    mika_sand_dress(_c, mika_sand_grade(1, _k), 6, 0.12, 1.5, 0, 0, 1200);
}

// ---------------------------------------------------------------------------
// Non-spell 2: dune sprinklers
// ---------------------------------------------------------------------------

function golem_sprinklers(_e, _g, _t) {
    // The fists held out and a little up.
    if (_t == 0) {
        golem_fist_to(_e, 0, -236, -10);
        golem_fist_to(_e, 1, 236, -10);
    }
    if (_t < 40) return;

    // Each fist sweeps its spray to and fro across the field below it, the
    // two in mirror, the sand bending opposite ways.
    if ((_t mod 3) == 0) {
        for (var _k = 0; _k < 2; _k++) {
            var _s = (_k == 0) ? -1 : 1;
            var _sweep = 270 + _s * (18 + 52 * (0.5 + 0.5 * dsin(_t * 2.2)));
            var _u = fire(golem_fist_x(_e, _k), golem_fist_y(_e, _k) + 24,
                          8.5, _sweep, BSHAPE_PELLET, BCOL_AMBER, 6);
            mika_sand_dress(_u, mika_sand_grade(_k, _t div 24), 10, 0.45, 2.0,
                            0.3 * -_s, 40, 1200);
        }
    }

    // Its eyes flare and fire fast glass at the player.
    if ((_t mod 90) == 60) {
        var _ex = _e.x;
        var _ey = _e.y + GOLEM_EYES_DY;
        _e.mem.flare = 1;
        fire_fan(_ex, _ey, 3, 9, aim_at(_ex, _ey, _g.player.x, _g.player.y),
                 10, BSHAPE_CRYSTAL, BCOL_GOLD, 14);
    }
}

// ---------------------------------------------------------------------------
// Non-spell 3: sandfall
// ---------------------------------------------------------------------------

#macro GOLEM_CLAP_CYCLE 150
#macro GOLEM_CLAP_AT 46

function golem_sandfall(_e, _g, _t) {
    var _c = _t mod GOLEM_CLAP_CYCLE;
    var _n = _t div GOLEM_CLAP_CYCLE;

    // Up, apart, overhead...
    if (_c == 0) {
        golem_fist_to(_e, 0, -120, -170);
        golem_fist_to(_e, 1, 120, -170);
    }
    // ...together...
    if (_c == GOLEM_CLAP_AT - 8) {
        golem_fist_to(_e, 0, -42, -150);
        golem_fist_to(_e, 1, 42, -150);
    }
    // ...and back down to fire.
    if (_c == GOLEM_CLAP_AT + 20) golem_fists_rest(_e);

    // The clap: a dome of sand goes up, stops, and rains.
    if (_c == GOLEM_CLAP_AT) {
        var _cx = _e.x;
        var _cy = _e.y - 150;
        _e.mem.flare = 1;
        _e.mem.slam[0] = 1;
        _e.mem.slam[1] = 1;
        fx_shake(8);
        fx_ring(_cx, _cy, 30, 260, 24, $40C0FF, 0.8);
        for (var _i = 0; _i < 40; _i++) {
            var _u = fire(_cx, _cy, 6.5, _i * 9 + _n * 4.5, BSHAPE_PELLET,
                          ((_i mod 2) == 0) ? BCOL_AMBER : BCOL_GOLD, 8);
            if (_u == undefined) continue;
            bullet_accel_at(_u, 4, -0.2, 0.6);
            bullet_force_at(_u, 60, 0, 0.045, BQ_KEEP, 3.6);
            bullet_expire_at(_u, 1200);
        }
    }

    // Between claps, each fist fires a fast stack of knives at the player.
    if (_c == 100 || _c == 116) {
        var _k = (_c == 100) ? 0 : 1;
        var _fx = golem_fist_x(_e, _k);
        var _fy = golem_fist_y(_e, _k);
        fire_stack(_fx, _fy, 5, 6, 1, aim_at(_fx, _fy, _g.player.x, _g.player.y),
                   BSHAPE_KNIFE, BCOL_BONE, 14);
    }
}
