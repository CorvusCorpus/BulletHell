/// @desc The pickups enemies drop, and how they reach the player.
///
/// Red is health, blue is sigil, gold is points; a red or blue one is worth
/// `ITEM_HP_VALUE` / `ITEM_MP_VALUE`. They are thrown up, fall, and home in
/// once the player is near or above `ITEM_AUTO_LINE`. Drawn as cut stones
/// (ruby, sapphire crystal, citrine) ray-traced by `tools/make_items.py`;
/// this file spins, pops, twinkles and fades them.

function item_init() {
    global.items = [];
    global.item_n = 0;
    global.item_auto = false;      // set while everything is being pulled in
}

function item_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0, kind: ItemKind.Tally, t: 0, drawn: 0,
        homing: false, seed: 0,
    };
}

function item_alloc() {
    if (global.item_n >= ITEM_MAX) return undefined;
    var _i = global.item_n;
    if (_i >= array_length(global.items)) {
        array_push(global.items, item_blank());
    }
    global.item_n = _i + 1;
    return global.items[_i];
}

function item_kill_at(_i) {
    var _last = global.item_n - 1;
    if (_i != _last) {
        var _t = global.items[_i];
        global.items[_i] = global.items[_last];
        global.items[_last] = _t;
    }
    global.item_n = _last;
}

function item_count() {
    return global.item_n;
}

/// @desc Drop one shard.
function item_spawn(_x, _y, _kind, _vx = undefined, _vy = undefined) {
    var _it = item_alloc();
    if (_it == undefined) return undefined;
    _it.x = _x;
    _it.y = _y;
    _it.vx = (_vx == undefined) ? random_range(-1.6, 1.6) : _vx;
    _it.vy = (_vy == undefined) ? random_range(-5.2, -2.6) : _vy;
    _it.kind = _kind;
    _it.t = 0;
    _it.drawn = 0;
    _it.homing = false;
    // Per-stone variation for the spin and twinkle; only drawing reads it.
    _it.seed = random(1);
    return _it;
}

/// @desc What a dead enemy leaves behind.
function item_drop_spread(_x, _y, _red, _blue, _gold) {
    for (var _i = 0; _i < _red; _i++)  item_spawn(_x, _y, ItemKind.Health);
    for (var _i = 0; _i < _blue; _i++) item_spawn(_x, _y, ItemKind.Mana);
    for (var _i = 0; _i < _gold; _i++) item_spawn(_x, _y, ItemKind.Tally);
}

/// @desc Advance every item. Returns what was collected this frame
///       (`{hp, mp, tally, n}`); the caller applies it to the player.
function item_step(_px, _py) {
    var _got = { hp: 0, mp: 0, tally: 0, n: 0 };

    // Point of collection: above this line every item homes in.
    var _auto = global.item_auto || (_py < ITEM_AUTO_LINE);

    // Catches this frame by kind, and where the first of each landed: one
    // catch burst per kind is thrown after the loop.
    var _caught = [0, 0, 0];
    var _cx = [0, 0, 0];
    var _cy = [0, 0, 0];

    for (var _i = global.item_n - 1; _i >= 0; _i--) {
        var _it = global.items[_i];
        _it.t++;

        var _d = point_distance(_it.x, _it.y, _px, _py);
        if (_auto || _d < ITEM_MAGNET_R) _it.homing = true;

        if (_it.homing) {
            var _dir = point_direction(_it.x, _it.y, _px, _py);
            // Faster the closer it gets.
            var _spd = ITEM_MAGNET_SPD * (1 + 0.9 * (1 - min(1, _d / ITEM_MAGNET_R)));
            _it.vx = lengthdir_x(_spd, _dir);
            _it.vy = lengthdir_y(_spd, _dir);
        } else {
            _it.vy = min(_it.vy + ITEM_GRAVITY, ITEM_TERMINAL);
            _it.vx *= 0.99;
        }

        _it.x += _it.vx;
        _it.y += _it.vy;

        if (_d < ITEM_R) {
            switch (_it.kind) {
                case ItemKind.Health: _got.hp += ITEM_HP_VALUE; break;
                case ItemKind.Mana:   _got.mp += ITEM_MP_VALUE; break;
            }
            _got.tally += TALLY_ITEM;
            _got.n++;
            if (_caught[_it.kind] == 0) {
                _cx[_it.kind] = _it.x;
                _cy[_it.kind] = _it.y;
            }
            _caught[_it.kind]++;
            // Called per item; `sfx` coalesces a frame's requests into one voice.
            sfx(Sfx.Item);
            item_kill_at(_i);
            continue;
        }

        // Off the bottom, or too old. Not culled off the top, because items
        // are thrown upward before they fall.
        if (_it.y > FIELD_Y1 + 80 || _it.t > ITEM_LIFE) {
            item_kill_at(_i);
        }
    }
    for (var _k = 0; _k < 3; _k++) {
        if (_caught[_k] > 0) item_catch_fx(_cx[_k], _cy[_k], _k, _caught[_k]);
    }
    return _got;
}

function item_colour(_kind) {
    switch (_kind) {
        case ItemKind.Health: return COL_LIFE;
        case ItemKind.Mana:   return COL_MANA;
    }
    return COL_GRAZE;
}

function item_sprite(_kind) {
    switch (_kind) {
        case ItemKind.Health: return spr_item_red;
        case ItemKind.Mana:   return spr_item_blue;
    }
    return spr_item_gold;
}

function item_clear_all() {
    global.item_n = 0;
}

/// @desc The burst when stones are caught: a flash, a ring and spinning
///       splinters. Thrown once per kind per frame (many stones landing
///       together would otherwise stack into a white blot); `_n`, the number
///       caught, makes it wider rather than brighter.
function item_catch_fx(_x, _y, _kind, _n) {
    var _col = item_colour(_kind);
    var _more = min(_n - 1, 6);

    var _p = fx_alloc();
    _p.x = _x; _p.y = _y; _p.vx = 0; _p.vy = 0;
    _p.drag = 1; _p.grav = 0;
    _p.life = 10; _p.life0 = 10;
    _p.size = 28 + 5 * _more; _p.size_end = 0;
    _p.col = _col;
    _p.angle = 0; _p.spin = 0;
    _p.spr = spr_fx_bloom;

    _p = fx_alloc();
    _p.x = _x; _p.y = _y; _p.vx = 0; _p.vy = 0;
    _p.drag = 1; _p.grav = 0;
    _p.life = 14; _p.life0 = 14;
    _p.size = 8; _p.size_end = 46 + 6 * _more;
    _p.col = _col;
    _p.angle = 0; _p.spin = 0;
    _p.spr = spr_fx_ring;

    var _k_n = 3 + min(_more, 3);
    var _a0 = random(360);
    for (var _k = 0; _k < _k_n; _k++) {
        var _s = fx_spark(_x, _y, _a0 + _k * 360 / _k_n + random_range(-20, 20),
                          random_range(2.6, 4.6), _col, irandom_range(13, 19),
                          11, spr_fx_shard);
        _s.drag = 0.9;
        _s.spin = random_range(-22, 22);
    }
}

/// @desc Each stone's rotational symmetry. The sprite holds one symmetry
///       period, so this converts frames into a spin rate. Must match `STONES`
///       in `tools/make_items.py`.
function item_symmetry(_kind) {
    switch (_kind) {
        case ItemKind.Health: return 8;     // round brilliant
        case ItemKind.Mana:   return 6;     // hexagonal crystal
    }
    return 4;                               // octahedron
}

/// @desc Which frame a stone is showing. Each turns at its own rate and
///       direction; a new one starts spinning fast and settles (the extra term
///       integrates a rate falling from 3.5x to 1x over its first 30 frames,
///       so the frame never jumps).
function item_frame(_it, _spr) {
    var _n = sprite_get_number(_spr);
    var _rate = ITEM_TURN * item_symmetry(_it.kind) * _n / FPS
                * (0.8 + 0.4 * frac(_it.seed * 7.13));
    var _dir = (frac(_it.seed * 3.71) < 0.5) ? -1 : 1;
    var _t = _it.t;
    var _spun = _t + 2.5 * ((_t < 30) ? (_t - _t * _t / 60) : 15);
    var _f = floor(_it.seed * _n + _dir * _rate * _spun);
    return ((_f mod _n) + _n) mod _n;
}

/// @desc A new stone's scale: up from nothing with a small overshoot.
function item_pop(_t) {
    if (_t >= ITEM_POP) return 1;
    var _u = _t / ITEM_POP - 1;
    return 1 + 2.70158 * _u * _u * _u + 1.70158 * _u * _u;
}

/// @desc 0..1: how brightly a stone is twinkling. Once as it arrives, then
///       every couple of seconds on its own clock.
function item_glint(_it) {
    var _u = (_it.t - 3) / ITEM_GLINT_LEN;
    if (_u >= 0 && _u < 1) return dsin(_u * 180);
    var _every = ITEM_GLINT_EVERY * (0.8 + 0.4 * _it.seed);
    _u = ((_it.t + _it.seed * _every) mod _every) / ITEM_GLINT_LEN;
    return (_u < 1) ? dsin(_u * 180) : 0;
}

/// @desc A stone's alpha: 1 until the last `ITEM_FADE` frames of its life,
///       then fading out with a quickening flicker.
function item_alpha(_it) {
    var _left = ITEM_LIFE - _it.t;
    if (_left >= ITEM_FADE) return 1;
    var _u = max(0, _left) / ITEM_FADE;
    return _u * (0.7 + 0.3 * dcos(_it.t * lerp(40, 14, _u)));
}

/// @desc Draw every stone (under the bullets; see `obj_game`'s Draw). Three
///       passes by blend mode: an additive glow (plus a streak while homing),
///       the stone itself, then an additive highlight and twinkle.
function item_draw() {
    var _bw = sprite_get_width(spr_fx_bloom);
    var _sw = sprite_get_width(spr_fx_spark);
    var _gw = sprite_get_width(spr_fx_glint);

    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.item_n; _i++) {
        var _it = global.items[_i];
        var _a = item_alpha(_it);
        var _col = item_colour(_it.kind);
        var _g = item_glint(_it);
        var _s = ITEM_GLOW_PX * (1 + 0.3 * _g) * item_pop(_it.t) / _bw;
        draw_sprite_ext(spr_fx_bloom, 0, _it.x, _it.y, _s, _s, 0, _col,
                        (0.30 + 0.25 * _g) * _a);
        if (_it.homing) {
            var _v = point_distance(0, 0, _it.vx, _it.vy);
            var _dir = point_direction(0, 0, _it.vx, _it.vy);
            var _len = min(96, _v * 5);
            draw_sprite_ext(spr_fx_spark, 0,
                            _it.x - lengthdir_x(_len * 0.45, _dir),
                            _it.y - lengthdir_y(_len * 0.45, _dir),
                            _len / _sw, 0.6, _dir, _col, 0.4 * _a);
        }
    }

    gpu_set_blendmode(bm_normal);
    for (var _i = 0; _i < global.item_n; _i++) {
        var _it = global.items[_i];
        var _spr = item_sprite(_it.kind);
        var _s = item_pop(_it.t);
        var _rock = _it.homing ? 0 : dsin(_it.t * 1.9 + _it.seed * 360) * 7;
        draw_sprite_ext(_spr, item_frame(_it, _spr), _it.x, _it.y, _s, _s,
                        _rock, c_white, item_alpha(_it));
    }

    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.item_n; _i++) {
        var _it = global.items[_i];
        var _a = item_alpha(_it);
        var _spr = item_sprite(_it.kind);
        if (_it.homing) {
            var _s = item_pop(_it.t);
            draw_sprite_ext(_spr, item_frame(_it, _spr), _it.x, _it.y, _s, _s,
                            0, c_white, 0.3 * _a);
        }
        var _g = item_glint(_it);
        if (_g > 0) {
            // On the upper-left facet, the lit side in every frame.
            var _gs = (10 + 26 * _g) / _gw;
            draw_sprite_ext(spr_fx_glint, 0,
                            _it.x - sprite_get_width(_spr) * 0.16,
                            _it.y - sprite_get_height(_spr) * 0.18,
                            _gs, _gs, _g * 35,
                            merge_colour(item_colour(_it.kind), c_white, 0.6),
                            _g * _a);
        }
    }
    gpu_set_blendmode(bm_normal);
}
