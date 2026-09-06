/// @desc Particles, floating text, screen shake and flashes.
///
/// **Everything here is decoration and nothing here may affect the rules.**
/// That is what lets the whole file be skipped by the self-test and by the
/// headless simulation the boss tuning runs on: a suite steps a pattern for
/// nine hundred frames and never draws a pixel, so a particle system that a
/// rule read back from would be a rule that behaves differently when nobody is
/// looking.
///
/// Particles are the same flat pool the bullets use, for the same reason and
/// with the same swap-remove. They are capped, and past the cap the *oldest*
/// is taken rather than the new one refused -- a bullet that fails to spawn is
/// a pattern with a hole in it, and a spark that fails to spawn is nothing, so
/// the two pools want opposite answers when they fill.

function fx_init() {
    global.fx = [];
    global.fx_n = 0;

    global.floaters = [];
    global.floater_n = 0;

    global.shake = 0;
    global.shake_x = 0;
    global.shake_y = 0;

    global.flash_a = 0;          // full-screen wash
    global.flash_col = c_white;

    global.blooms = [];          // expanding rings; the loudest thing here
    global.bloom_n = 0;
}

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

function fx_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0, drag: 0.94, grav: 0,
        life: 0, life0: 1, size: 8, size_end: 0,
        col: c_white, angle: 0, spin: 0, spr: -1,
    };
}

function fx_alloc() {
    var _i = global.fx_n;
    if (_i >= PARTICLE_MAX) {
        // Full: overwrite the oldest. See the file docstring.
        _i = 0;
        for (var _j = 1; _j < global.fx_n; _j++) {
            if (global.fx[_j].life < global.fx[_i].life) _i = _j;
        }
        return global.fx[_i];
    }
    if (_i >= array_length(global.fx)) {
        array_push(global.fx, fx_blank());
    }
    global.fx_n = _i + 1;
    return global.fx[_i];
}

function fx_kill_at(_i) {
    var _last = global.fx_n - 1;
    if (_i != _last) {
        var _t = global.fx[_i];
        global.fx[_i] = global.fx[_last];
        global.fx[_last] = _t;
    }
    global.fx_n = _last;
}

/// @desc One spark, thrown at a speed and an angle.
function fx_spark(_x, _y, _dir, _spd, _col, _life, _size, _spr = -1) {
    var _p = fx_alloc();
    _p.x = _x; _p.y = _y;
    _p.vx = lengthdir_x(_spd, _dir);
    _p.vy = lengthdir_y(_spd, _dir);
    _p.drag = 0.93;
    _p.grav = 0;
    _p.life = _life; _p.life0 = max(1, _life);
    _p.size = _size; _p.size_end = 0;
    _p.col = _col;
    _p.angle = _dir;
    _p.spin = 0;
    _p.spr = (_spr == -1) ? spr_fx_spark : _spr;
    return _p;
}

/// @desc A burst of sparks in every direction.
function fx_burst(_x, _y, _n, _spd0, _spd1, _col, _life, _size) {
    for (var _i = 0; _i < _n; _i++) {
        fx_spark(_x, _y, random(360), random_range(_spd0, _spd1), _col,
                 irandom_range(_life * 0.6, _life), _size);
    }
}

/// @desc What a bullet leaves when it is swept. Small and cheap: this runs
///       four thousand times when a spell is cleared.
function fx_bullet_pop(_x, _y, _col) {
    var _c = global.bullet_colour[_col];
    var _p = fx_alloc();
    _p.x = _x; _p.y = _y;
    _p.vx = 0; _p.vy = 0;
    _p.drag = 1; _p.grav = 0;
    _p.life = 14; _p.life0 = 14;
    _p.size = 22; _p.size_end = 46;
    _p.col = _c;
    _p.angle = 0; _p.spin = 0;
    _p.spr = spr_fx_bloom;
}

/// @desc An expanding ring. The shockwave of a bomb, a spell declaration, a
///       boss dying.
function fx_ring(_x, _y, _r0, _r1, _life, _col, _thick = 1.0) {
    var _i = global.bloom_n;
    if (_i >= 48) return;
    if (_i >= array_length(global.blooms)) {
        array_push(global.blooms, {
            x: 0, y: 0, r0: 0, r1: 0, t: 0, life: 1, col: c_white, thick: 1,
        });
    }
    global.bloom_n = _i + 1;
    var _b = global.blooms[_i];
    _b.x = _x; _b.y = _y;
    _b.r0 = _r0; _b.r1 = _r1;
    _b.t = 0; _b.life = max(1, _life);
    _b.col = _col; _b.thick = _thick;
}

/// @desc A local flash of light, and a nudge to the screen.
function fx_flash_at(_x, _y, _col, _power) {
    var _p = fx_alloc();
    _p.x = _x; _p.y = _y;
    _p.vx = 0; _p.vy = 0;
    _p.drag = 1; _p.grav = 0;
    _p.life = 10; _p.life0 = 10;
    _p.size = 40 + 260 * _power; _p.size_end = 0;
    _p.col = _col;
    _p.angle = 0; _p.spin = 0;
    _p.spr = spr_fx_bloom;
}

/// @desc Wash the whole screen. Used sparingly: a bomb, a spell landing, a hit.
function fx_flash_screen(_col, _amount) {
    global.flash_col = _col;
    global.flash_a = max(global.flash_a, _amount);
}

/// @desc Shake. **Additive and capped**, so ten small events do not add up to
///       an earthquake -- which is exactly what happens on a cleared spell,
///       where four thousand bullets pop on the same frame.
function fx_shake(_amount) {
    global.shake = min(28, global.shake + _amount);
}

// ---------------------------------------------------------------------------
// Floating text
// ---------------------------------------------------------------------------

function fx_text(_x, _y, _str, _col, _life = 46, _size = 1.0) {
    var _i = global.floater_n;
    if (_i >= FLOATER_MAX) return;
    if (_i >= array_length(global.floaters)) {
        array_push(global.floaters, {
            x: 0, y: 0, vy: 0, t: 0, life: 1, str: "", col: c_white, size: 1,
        });
    }
    global.floater_n = _i + 1;
    var _f = global.floaters[_i];
    _f.x = _x; _f.y = _y;
    _f.vy = -1.6;
    _f.t = 0; _f.life = _life;
    _f.str = _str; _f.col = _col; _f.size = _size;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function fx_step() {
    for (var _i = global.fx_n - 1; _i >= 0; _i--) {
        var _p = global.fx[_i];
        _p.x += _p.vx;
        _p.y += _p.vy;
        _p.vx *= _p.drag;
        _p.vy = _p.vy * _p.drag + _p.grav;
        _p.angle += _p.spin;
        _p.life--;
        if (_p.life <= 0) fx_kill_at(_i);
    }

    for (var _i = global.bloom_n - 1; _i >= 0; _i--) {
        var _b = global.blooms[_i];
        _b.t++;
        if (_b.t >= _b.life) {
            var _last = global.bloom_n - 1;
            if (_i != _last) {
                var _t = global.blooms[_i];
                global.blooms[_i] = global.blooms[_last];
                global.blooms[_last] = _t;
            }
            global.bloom_n = _last;
        }
    }

    for (var _i = global.floater_n - 1; _i >= 0; _i--) {
        var _f = global.floaters[_i];
        _f.y += _f.vy;
        _f.vy *= 0.94;
        _f.t++;
        if (_f.t >= _f.life) {
            var _last = global.floater_n - 1;
            if (_i != _last) {
                var _t = global.floaters[_i];
                global.floaters[_i] = global.floaters[_last];
                global.floaters[_last] = _t;
            }
            global.floater_n = _last;
        }
    }

    global.shake *= 0.86;
    if (global.shake < 0.2) global.shake = 0;
    global.shake_x = random_range(-global.shake, global.shake);
    global.shake_y = random_range(-global.shake, global.shake);

    global.flash_a *= 0.84;
    if (global.flash_a < 0.01) global.flash_a = 0;
}

/// @desc Throw everything away. A room change, or a suite starting.
function fx_clear() {
    global.fx_n = 0;
    global.floater_n = 0;
    global.bloom_n = 0;
    global.shake = 0;
    global.flash_a = 0;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

function fx_draw() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.fx_n; _i++) {
        var _p = global.fx[_i];
        var _t = _p.life / _p.life0;                  // 1 at birth, 0 at death
        var _size = lerp(_p.size_end, _p.size, _t);
        var _s = _size / max(1, sprite_get_width(_p.spr));
        draw_sprite_ext(_p.spr, 0, _p.x, _p.y, _s, _s, _p.angle, _p.col,
                        min(1, _t * 1.6));
    }

    for (var _i = 0; _i < global.bloom_n; _i++) {
        var _b = global.blooms[_i];
        var _t = _b.t / _b.life;
        var _r = lerp(_b.r0, _b.r1, 1 - (1 - _t) * (1 - _t));   // ease out
        var _a = (1 - _t) * (1 - _t);
        var _s = _r * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _b.x, _b.y, _s, _s, 0, _b.col,
                        _a * _b.thick);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Floating text, drawn in the GUI layer so it is never scaled by a
///       camera and never lost behind a bullet.
/// @desc The floating text, drawn on the GUI layer so it does not shake.
///
///       **Held inside the field.** These carry world positions -- a score
///       popping off a killed enemy, a bomb's caption -- but they are drawn in
///       the GUI event, which is *after* `field_draw_frame` has painted out
///       everything that is not the field. So they are the one thing in the
///       game that can put world content in the HUD margin, and a "+250"
///       drifting up past the score readout is exactly the kind of leak the
///       boundary exists to stop.
///
///       Clamped rather than culled: a score that vanished because the enemy
///       died near the edge would be a reward the player was told about only
///       sometimes.
function fx_draw_text() {
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    for (var _i = 0; _i < global.floater_n; _i++) {
        var _f = global.floaters[_i];
        var _t = _f.t / _f.life;
        var _a = (_t < 0.15) ? (_t / 0.15) : (1 - (_t - 0.15) / 0.85);
        text_style(fnt_small(), _f.col, _a);
        draw_text_transformed(clamp(_f.x, FIELD_X0 + 60, FIELD_X1 - 60),
                              clamp(_f.y, FIELD_Y0 + 30, FIELD_Y1 - 30),
                              _f.str, _f.size, _f.size, 0);
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc The full-screen wash. Drawn last of everything, over the HUD, because
///       a flash that the HUD sat on top of would read as the HUD lighting up.
function fx_draw_flash() {
    if (global.flash_a <= 0) return;
    gpu_set_blendmode(bm_add);
    draw_set_alpha(global.flash_a);
    draw_set_colour(global.flash_col);
    draw_rectangle(0, 0, GAME_W, GAME_H, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
    gpu_set_blendmode(bm_normal);
}
