/// @desc Particles, expanding rings, floating text, screen shake and flashes.
///
/// Decoration only: no gameplay code reads any of this back. Particles are a
/// flat pool like the bullets, but when full they overwrite the oldest
/// particle instead of refusing the new one.

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

    // The bullet that last hit the player (`fx_hit_mark`); `t` -1 is none.
    global.hit_mark = { t: -1, spr: -1, shape: 0, col: 0, life: 0, x: 0,
                        y: 0, angle: 0, scale: 1, cx: 0, cy: 0, vx: 0, vy: 0,
                        r: 0 };
}

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

function fx_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0, drag: 0.94, grav: 0,
        life: 0, life0: 1, size: 8, size_end: 0,
        col: c_white, angle: 0, spin: 0, spr: -1,
        // The sprite frame, and whether it is added (light) or laid over
        // (a solid piece: a page, a shard of metal). `fx_alloc` resets these
        // three, since the structs are reused and not every maker sets them.
        img: 0, add: true,
        // How much of its life it spends fading out (1: all of it).
        fade: 0.625,
    };
}

function fx_alloc() {
    var _i = global.fx_n;
    if (_i >= PARTICLE_MAX) {
        // Full: overwrite the one closest to expiring.
        _i = 0;
        for (var _j = 1; _j < global.fx_n; _j++) {
            if (global.fx[_j].life < global.fx[_i].life) _i = _j;
        }
    } else {
        if (_i >= array_length(global.fx)) {
            array_push(global.fx, fx_blank());
        }
        global.fx_n = _i + 1;
    }
    // The fields not every maker sets, back to a spark's.
    var _p = global.fx[_i];
    _p.img = 0;
    _p.add = true;
    _p.fade = 0.625;
    return _p;
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

/// @desc A solid piece thrown off something breaking (a page, a shard of
///       gilt): drawn over the field rather than added, turning as it goes,
///       and fading over the last `_fade` of its life.
function fx_piece(_x, _y, _vx, _vy, _spr, _img, _life, _size, _spin,
                  _grav = 0, _drag = 0.95, _col = c_white, _fade = 0.4) {
    var _p = fx_alloc();
    _p.x = _x; _p.y = _y;
    _p.vx = _vx; _p.vy = _vy;
    _p.drag = _drag;
    _p.grav = _grav;
    _p.life = _life; _p.life0 = max(1, _life);
    _p.size = _size; _p.size_end = _size * 0.6;
    _p.col = _col;
    _p.angle = random(360);
    _p.spin = _spin;
    _p.spr = _spr;
    _p.img = _img;
    _p.add = false;
    _p.fade = max(0.01, _fade);
    return _p;
}

/// @desc A mote of light that drifts and fades: `fx_spark` with its own
///       sprite, frame, drag and gravity.
function fx_mote(_x, _y, _vx, _vy, _spr, _col, _life, _size, _grav = 0,
                 _drag = 0.96) {
    var _p = fx_alloc();
    _p.x = _x; _p.y = _y;
    _p.vx = _vx; _p.vy = _vy;
    _p.drag = _drag;
    _p.grav = _grav;
    _p.life = _life; _p.life0 = max(1, _life);
    _p.size = _size; _p.size_end = 0;
    _p.col = _col;
    _p.angle = 0;
    _p.spin = 0;
    _p.spr = _spr;
    return _p;
}

/// @desc A burst of sparks in every direction.
function fx_burst(_x, _y, _n, _spd0, _spd1, _col, _life, _size) {
    for (var _i = 0; _i < _n; _i++) {
        fx_spark(_x, _y, random(360), random_range(_spd0, _spd1), _col,
                 irandom_range(_life * 0.6, _life), _size);
    }
}

/// @desc The pop a bullet leaves when swept. Kept cheap: a clear can call it
///       thousands of times in one frame.
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

/// @desc Leave the hit mark of bullet `_u`, which has just hit a player of
///       radius `_rad` at (`_x`, `_y`): its look, held where it first
///       touched him on this frame's move (a long bullet, which moves along
///       its own length, where it is drawn). One at a time, since a hit
///       gives grace, and kept out of the particle pool so a full pool or a
///       clear can't take it. Bullets only: lasers, rings and bodies leave
///       none.
function fx_hit_mark(_u, _x, _y, _rad) {
    var _m = global.hit_mark;
    _m.t = 0;
    _m.spr = global.bshape_sprite[_u.shape];
    _m.shape = _u.shape;
    _m.col = _u.col;
    _m.life = _u.life;
    _m.angle = _u.angle;
    _m.scale = _u.scale;
    _m.x = _u.x;
    _m.y = _u.y;
    _m.vx = _u.x - _u.px;
    _m.vy = _u.y - _u.py;
    // About how far its drawing reaches from its origin.
    _m.r = max(sprite_get_width(_m.spr), sprite_get_height(_m.spr)) * 0.4
           * _u.scale;

    // The point on its hitbox nearest him (`cx`, `cy`): on a long bullet's
    // spine, or a round one's centre, `r` toward him.
    var _nx = _m.x;
    var _ny = _m.y;
    if (global.bshape_long[_u.shape]) {
        var _ux = dcos(_u.angle);
        var _uy = -dsin(_u.angle);
        var _a = global.bshape_spine0[_u.shape] * _u.scale;
        var _b = global.bshape_spine1[_u.shape] * _u.scale;
        var _s = clamp((_x - _m.x) * _ux + (_y - _m.y) * _uy, _a, _b);
        _nx = _m.x + _ux * _s;
        _ny = _m.y + _uy * _s;
    } else {
        // The first point of the move from (px, py) where the two circles
        // meet: |a + t d| = reach, the smaller root.
        var _dx = _m.vx;
        var _dy = _m.vy;
        var _ax = _u.px - _x;
        var _ay = _u.py - _y;
        var _reach = _u.r + _rad;
        var _qa = _dx * _dx + _dy * _dy;
        var _qb = 2 * (_ax * _dx + _ay * _dy);
        var _qc = _ax * _ax + _ay * _ay - _reach * _reach;
        var _t = 0;
        if (_qc > 0 && _qa > 0.0001) {
            var _disc = max(0, _qb * _qb - 4 * _qa * _qc);
            _t = clamp((-_qb - sqrt(_disc)) / (2 * _qa), 0, 1);
        }
        _m.x = _u.px + _dx * _t;
        _m.y = _u.py + _dy * _t;
        _nx = _m.x;
        _ny = _m.y;
    }
    var _d = point_direction(_nx, _ny, _x, _y);
    _m.cx = _nx + lengthdir_x(_u.r, _d);
    _m.cy = _ny + lengthdir_y(_u.r, _d);
}

/// @desc An expanding ring (shockwaves). At most 48 at once.
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

/// @desc A local flash of light.
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

/// @desc Wash the whole screen with a colour (decays each frame).
function fx_flash_screen(_col, _amount) {
    global.flash_col = _col;
    global.flash_a = max(global.flash_a, _amount);
}

/// @desc Add screen shake, capped at 28.
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

    var _m = global.hit_mark;
    if (_m.t >= 0) {
        _m.t++;
        if (_m.t >= HIT_MARK_TIME) {
            // It goes as a swept bullet does.
            fx_bullet_pop(_m.x, _m.y, _m.col);
            _m.t = -1;
        }
    }

    global.shake *= 0.86;
    if (global.shake < 0.2) global.shake = 0;
    global.shake_x = random_range(-global.shake, global.shake);
    global.shake_y = random_range(-global.shake, global.shake);

    global.flash_a *= 0.84;
    if (global.flash_a < 0.01) global.flash_a = 0;
}

/// @desc Clear every effect.
function fx_clear() {
    global.fx_n = 0;
    global.floater_n = 0;
    global.bloom_n = 0;
    global.shake = 0;
    global.flash_a = 0;
    global.hit_mark.t = -1;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

function fx_draw() {
    // Solid pieces first, laid over the field; then the light, added.
    for (var _i = 0; _i < global.fx_n; _i++) {
        var _p = global.fx[_i];
        if (_p.add) continue;
        var _t = _p.life / _p.life0;                  // 1 at birth, 0 at death
        var _size = lerp(_p.size_end, _p.size, _t);
        var _s = _size / max(1, sprite_get_width(_p.spr));
        draw_sprite_ext(_p.spr, _p.img, _p.x, _p.y, _s, _s, _p.angle, _p.col,
                        min(1, _t / _p.fade));
    }

    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.fx_n; _i++) {
        var _p = global.fx[_i];
        if (!_p.add) continue;
        var _t = _p.life / _p.life0;                  // 1 at birth, 0 at death
        var _size = lerp(_p.size_end, _p.size, _t);
        var _s = _size / max(1, sprite_get_width(_p.spr));
        draw_sprite_ext(_p.spr, _p.img, _p.x, _p.y, _s, _s, _p.angle, _p.col,
                        min(1, _t / _p.fade));
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

/// @desc The floating text, drawn on the GUI layer (so it doesn't shake).
///       Drawn after the field's mask, so positions are clamped inside the
///       field or the text would spill into the HUD margin.
/// @desc The hit mark (`fx_hit_mark`), drawn as a sequence:
///       - Impact: the bullet flashes white, shows its own negative for two
///         frames (`sh_invert`), and comes back as itself under a fading
///         sheen, swollen a little by the blow. Where it touched him a strike
///         bursts (`spr_fx_strike` frame 1) and a burst of strokes is thrown
///         out (frame 2), the longest along the way it was going.
///       - Its last positions trail behind it as afterimages, so the way it
///         came reads, and fade.
///       - The lock (frame 0) closes on it from wide, overshooting a little,
///         then turns slowly and breathes while it is held, over a soft shade
///         and a red under-glow that set it off the field.
///       - Release: the lock opens out and fades as the bullet shrinks away,
///         and it pops as a swept bullet does (`fx_step`).
///       Drawn over the bullets and the hit's own sparks, under the player's
///       hitbox.
function fx_hit_mark_draw() {
    var _m = global.hit_mark;
    if (_m.t < 0) return;
    var _t = _m.t;
    var _img = bullet_frame(_m.shape, _m.col, _m.life);
    var _hot = merge_colour(COL_LIFE, c_white, 0.55);
    var _bw = sprite_get_width(spr_fx_bloom);
    // The release: 0 until the last `HIT_MARK_OUT` frames, then easing in to
    // 1.
    var _rel = clamp((_t - (HIT_MARK_TIME - HIT_MARK_OUT)) / HIT_MARK_OUT,
                     0, 1);
    _rel *= _rel;
    var _live = 1 - _rel;

    // The shade, and the red under-glow breathing in it.
    var _gs = _m.r * 4.0 / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _m.x, _m.y, _gs, _gs, 0, c_black,
                    0.4 * _live * min(1, _t / 3));
    gpu_set_blendmode(bm_add);
    _gs = _m.r * 3.0 / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _m.x, _m.y, _gs, _gs, 0, COL_LIFE,
                    (0.22 + 0.08 * dsin(_t * 9)) * _live);
    gpu_set_blendmode(bm_normal);

    // The afterimages, back along the way it came.
    var _sp = point_distance(0, 0, _m.vx, _m.vy);
    var _trail = 1 - min(1, _t / 14);
    if (_sp > 0.5 && _trail > 0) {
        // In frames of its travel apart, so slow sand still spreads them.
        var _gap = clamp(_sp * 1.6, 5, 16) / _sp;
        for (var _k = 4; _k >= 1; _k--) {
            draw_sprite_ext(_m.spr, _img, _m.x - _m.vx * _gap * _k,
                            _m.y - _m.vy * _gap * _k, _m.scale, _m.scale,
                            _m.angle, c_white,
                            0.4 * (1 - _k / 5) * _trail * _trail);
        }
    }

    // The bullet.
    var _punch = max(0, 1 - _t / 7);
    var _bs = _m.scale * (1 + 0.2 * _punch * _punch) * lerp(1, 0.5, _rel);
    if (_t < 2) {
        gpu_set_fog(true, c_white, 0, 0);
        draw_sprite_ext(_m.spr, _img, _m.x, _m.y, _bs, _bs, _m.angle,
                        c_white, 1);
        gpu_set_fog(false, c_black, 0, 0);
    } else if (_t < 4) {
        shader_set(sh_invert);
        draw_sprite_ext(_m.spr, _img, _m.x, _m.y, _bs, _bs, _m.angle,
                        c_white, 1);
        shader_reset();
    } else {
        draw_sprite_ext(_m.spr, _img, _m.x, _m.y, _bs, _bs, _m.angle,
                        c_white, _live);
        var _sheen = 1 - min(1, (_t - 4) / 8);
        if (_sheen > 0) {
            gpu_set_fog(true, c_white, 0, 0);
            draw_sprite_ext(_m.spr, _img, _m.x, _m.y, _bs, _bs, _m.angle,
                            c_white, 0.7 * _sheen * _sheen);
            gpu_set_fog(false, c_black, 0, 0);
        }
    }

    gpu_set_blendmode(bm_add);

    // The lock: an ease out that overshoots, then a slow turn and a breath;
    // its ring sits a little outside the bullet's reach.
    var _in = min(1, _t / HIT_MARK_CLOSE);
    var _q = _in - 1;
    var _back = 1 + 2.70158 * _q * _q * _q + 1.70158 * _q * _q;
    var _turn = 1 - power(1 - _in, 3);
    var _ls = (_m.r + 10) / HIT_MARK_LOCK_R * lerp(2.3, 1, _back)
              * (1 + 0.025 * dsin(_t * 9)) * (1 + 0.5 * _rel);
    var _la = min(1, _t / 3) * _live;
    var _rot = lerp(70, 0, _turn) - _t * 0.8 - 30 * _rel;
    draw_sprite_ext(spr_fx_strike, 0, _m.x, _m.y, _ls * 1.04, _ls * 1.04,
                    _rot, COL_LIFE, 0.7 * _la);
    draw_sprite_ext(spr_fx_strike, 0, _m.x, _m.y, _ls, _ls, _rot, _hot, _la);

    // The strike, bursting in two frames and shrinking away by the
    // sixteenth, and its strokes thrown out.
    var _sk = (_t < 2) ? lerp(0.4, 1, _t / 2) : max(0, 1 - sqr((_t - 2) / 14));
    if (_sk > 0) {
        var _ss = 0.62 * _sk;
        var _bs2 = 70 * _sk / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _m.cx, _m.cy, _bs2, _bs2, 0,
                        COL_LIFE, 0.55 * _sk);
        draw_sprite_ext(spr_fx_strike, 1, _m.cx, _m.cy, _ss * 1.25,
                        _ss * 1.25, _t * 2, COL_LIFE, 0.8 * _sk);
        draw_sprite_ext(spr_fx_strike, 1, _m.cx, _m.cy, _ss, _ss, _t * 2,
                        c_white, _sk);
    }
    var _bk = min(1, _t / 14);
    if (_bk < 1) {
        var _bsc = lerp(0.3, 0.8, 1 - power(1 - _bk, 3));
        draw_sprite_ext(spr_fx_strike, 2, _m.cx, _m.cy, _bsc, _bsc,
                        point_direction(0, 0, _m.vx, _m.vy), _hot, 1 - _bk);
    }
    gpu_set_blendmode(bm_normal);
}

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

/// @desc The full-screen wash, drawn last (over the HUD too).
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
