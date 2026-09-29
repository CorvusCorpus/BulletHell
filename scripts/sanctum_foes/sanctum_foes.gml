/// @desc Stage three's fodder: the soul-flame wisp, the flying spellbook and
///       the armillary sphere (`EnemyKind.HallWisp`, `HallBook`,
///       `HallSphere`). How they look, what they give off while they fly,
///       and how they break. Their art is `tools/make_sanctum_foes.py`, in its
///       own colours; nothing here tints it.
///
/// Where they fly and what they fire is their wave's business
/// (`sanctum_waves`), through `enemy_routes`.

// Hit radii (shooting them, and a little over half of it for touching them),
// against the art's size in `make_sanctum_foes.py`.
#macro HALL_WISP_R 28
#macro HALL_BOOK_R 42
#macro HALL_SPHERE_R 38

// The glow each kind stands in, and the colour it breaks in.
#macro HALL_WISP_GLOW $F2E23C      // turquoise (BGR)
#macro HALL_BOOK_GLOW $F07A3A      // lapis
#macro HALL_SPHERE_GLOW $52C8FF    // amber

// ---------------------------------------------------------------------------
// While it flies
// ---------------------------------------------------------------------------

/// @desc What a hall foe gives off every frame: embers off a wisp, the odd
///       loose page off a book. Called by `enemy_step` after `act`.
function hall_foe_ambient(_e) {
    if (_e.alpha < 1 || !foe_inside(_e, -20)) return;
    switch (_e.kind) {
        case EnemyKind.HallWisp:
            // An ember every few frames, rising off the tip and fading.
            if ((_e.t mod 5) == 0) {
                fx_mote(_e.x + random_range(-9, 9) * _e.scale,
                        _e.y - 18 * _e.scale,
                        random_range(-0.5, 0.5) + (_e.x - _e.px) * 0.3,
                        random_range(-1.9, -0.9), spr_fx_bloom,
                        (irandom(3) == 0) ? c_white : HALL_WISP_GLOW,
                        irandom_range(24, 40), 12 * _e.scale, -0.015, 0.97);
            }
            break;

        case EnemyKind.HallBook:
            // Now and then a leaf works loose and flutters away.
            if ((_e.t mod 53) == 17) {
                fx_piece(_e.x + random_range(-20, 20) * _e.scale,
                         _e.y + random_range(-6, 10) * _e.scale,
                         random_range(-1.2, 1.2), random_range(0.4, 1.2),
                         spr_fx_page, irandom(2), irandom_range(60, 90),
                         20 * _e.scale, random_range(-6, 6), 0.02, 0.97,
                         c_white, 0.6);
            }
            break;
    }
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw one hall foe: its glow, its body, and its hit flash; while it
///       is materialising, the glyph it comes out of.
function hall_foe_draw(_e) {
    var _spr = enemy_sprite(_e.kind);
    var _n = sprite_get_number(_spr);
    var _s = _e.scale;
    var _a = _e.alpha;
    var _vx = _e.x - _e.px;
    var _vy = _e.y - _e.py;
    var _app = (_e.mem == undefined) ? -1 : (_e.mem[$ "appear"] ?? -1);

    // The glyph it steps out of.
    if (_app >= 0) hall_foe_draw_summon(_e, _app);
    if (_a <= 0.01) return;

    // Growing into its size as it materialises.
    if (_app >= 0) _s *= 0.6 + 0.4 * _app;

    var _fr = 0;
    var _ang = 0;
    var _glow = HALL_WISP_GLOW;
    var _gsize = 5.2;
    var _galpha = 0.34;
    switch (_e.kind) {
        case EnemyKind.HallWisp:
            _fr = (_e.t div 4) mod _n;
            // It leans into its motion like a flame dragged through air.
            _ang = clamp(-_vx * 2.2, -22, 22);
            _glow = HALL_WISP_GLOW;
            _gsize = 5.6;
            _galpha = 0.40 + 0.08 * dsin(_e.t * 9);
            // A faint smear behind it while it moves.
            var _sp = point_distance(0, 0, _vx, _vy);
            if (_sp > 1.5) {
                gpu_set_blendmode(bm_add);
                for (var _k = 1; _k <= 3; _k++) {
                    draw_sprite_ext(_spr, (_fr + _k) mod _n,
                                    _e.x - _vx * _k * 2.4, _e.y - _vy * _k * 2.4,
                                    _s, _s, _ang, HALL_WISP_GLOW,
                                    _a * 0.16 * (1 - _k / 4));
                }
                gpu_set_blendmode(bm_normal);
            }
            break;

        case EnemyKind.HallBook:
            // Its covers beat like wings; faster while it is travelling.
            var _beat = (point_distance(0, 0, _vx, _vy) > 2) ? 3 : 4;
            _fr = (_e.t div _beat) mod _n;
            _ang = clamp(-_vx * 1.6, -14, 14);
            _glow = HALL_BOOK_GLOW;
            _gsize = 4.2;
            _galpha = 0.26;
            break;

        case EnemyKind.HallSphere:
            _fr = (_e.t div 3) mod _n;
            _glow = HALL_SPHERE_GLOW;
            _gsize = 4.4;
            _galpha = 0.30 + 0.06 * dsin(_e.t * 4);
            break;
    }

    // The light it stands in.
    var _gs = (_e.r / max(0.1, _e.scale)) * _s * _gsize
              / sprite_get_width(spr_fx_bloom);
    gpu_set_blendmode(bm_add);
    draw_sprite_ext(spr_fx_bloom, 0, _e.x, _e.y, _gs, _gs, 0, _glow,
                    _galpha * _a);
    gpu_set_blendmode(bm_normal);

    draw_sprite_ext(_spr, _fr, _e.x, _e.y, _s, _s, _ang, c_white, _a);

    // The heart of it, lit: a wisp's core and a sphere's.
    if (_e.kind != EnemyKind.HallBook) {
        var _cs = (_e.kind == EnemyKind.HallWisp) ? 0.44 : 0.36;
        var _pulse = 0.55 + 0.25 * dsin(_e.t * 11 + _e.x);
        draw_bloom(_e.x, _e.y + ((_e.kind == EnemyKind.HallWisp) ? 6 * _s : 0),
                   _e.r * 2 * _cs * 3 * _s / max(0.1, _e.scale),
                   merge_colour(_glow, c_white, 0.5), _pulse * 0.45 * _a);
    }

    // Hit flash: the body added again in white.
    if (_e.flash > 0) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(_spr, _fr, _e.x, _e.y, _s, _s, _ang, c_white,
                        _e.flash / ENEMY_FLASH * 0.75 * _a);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc The glyph a foe materialises out of, `_p` (0 to 1) of the way:
///       a gilt circle opening and turning under it, brightest as the foe
///       arrives, then gone.
function hall_foe_draw_summon(_e, _p) {
    var _w = sprite_get_width(spr_fx_summon);
    var _open = 1 - (1 - _p) * (1 - _p);
    var _size = _e.r * 4.2 * (0.45 + 0.55 * _open);
    var _k = _size / _w;
    var _a = sin(_p * pi) * 0.9 + 0.1 * _p;
    gpu_set_blendmode(bm_add);
    draw_sprite_ext(spr_fx_summon, 0, _e.x, _e.y, _k, _k, _e.t * 1.6,
                    COL_GILT_LIT, _a);
    draw_sprite_ext(spr_fx_summon, 0, _e.x, _e.y, _k * 0.62, _k * 0.62,
                    -_e.t * 2.4, COL_RUNE, _a * 0.6);
    gpu_set_blendmode(bm_normal);
    draw_bloom(_e.x, _e.y, _size * 1.3, COL_GILT_LIT, _a * 0.28);
}

// ---------------------------------------------------------------------------
// Breaking
// ---------------------------------------------------------------------------

/// @desc How a hall foe breaks (`enemy_die`): a wisp gutters out in a puff
///       of embers, a book bursts into its pages, a sphere comes apart in
///       shards of gilt.
function hall_foe_death(_e) {
    var _s = _e.scale;
    switch (_e.kind) {
        case EnemyKind.HallWisp:
            fx_flash_at(_e.x, _e.y, HALL_WISP_GLOW, 0.20 * _s);
            fx_ring(_e.x, _e.y, 6, 70 * _s, 18, HALL_WISP_GLOW, 0.7);
            for (var _i = 0; _i < 12; _i++) {
                var _d = random(360);
                var _v = random_range(1.5, 4.5);
                fx_mote(_e.x, _e.y, lengthdir_x(_v, _d),
                        lengthdir_y(_v, _d) - 1.2, spr_fx_bloom,
                        (_i mod 3 == 0) ? c_white : HALL_WISP_GLOW,
                        irandom_range(22, 38), 16 * _s, -0.03, 0.93);
            }
            fx_burst(_e.x, _e.y, 8, 2, 6, HALL_WISP_GLOW, 20, 12);
            break;

        case EnemyKind.HallBook:
            fx_flash_at(_e.x, _e.y, HALL_BOOK_GLOW, 0.16 * _s);
            fx_ring(_e.x, _e.y, 8, 80 * _s, 20, COL_GILT_LIT, 0.5);
            for (var _i = 0; _i < 14; _i++) {
                var _d = _i * (360 / 14) + random_range(-10, 10);
                var _v = random_range(2, 6.5);
                fx_piece(_e.x, _e.y, lengthdir_x(_v, _d), lengthdir_y(_v, _d),
                         spr_fx_page, _i mod 3, irandom_range(46, 80),
                         random_range(18, 26) * _s, random_range(-9, 9),
                         0.06, 0.94, c_white, 0.45);
            }
            fx_burst(_e.x, _e.y, 10, 2, 7, COL_GILT_LIT, 24, 14);
            break;

        case EnemyKind.HallSphere:
            fx_flash_at(_e.x, _e.y, HALL_SPHERE_GLOW, 0.26 * _s);
            fx_ring(_e.x, _e.y, 10, 96 * _s, 22, HALL_SPHERE_GLOW, 0.8);
            fx_ring(_e.x, _e.y, 4, 52 * _s, 14, c_white, 0.6);
            for (var _i = 0; _i < 10; _i++) {
                var _d = _i * 36 + random_range(-14, 14);
                var _v = random_range(2.5, 7);
                fx_piece(_e.x, _e.y, lengthdir_x(_v, _d), lengthdir_y(_v, _d),
                         spr_fx_gilt, _i mod 3, irandom_range(30, 50),
                         random_range(14, 22) * _s, random_range(-14, 14),
                         0.12, 0.95, c_white, 0.5);
            }
            fx_burst(_e.x, _e.y, 12, 2, 8, HALL_SPHERE_GLOW, 26, 16);
            break;
    }
}
