/// @desc Velka's wood in real 3D (the review card flies it): the Hollow
///       Grove's night forest rebuilt as geometry under a moon that turns to
///       blood, drawn with a camera, the depth buffer and per-pixel light.
///
/// - The trees are meshes grown in `tools/make_wood.py` (`wood_table`), loaded
///   from `datafiles/wood/` into vertex buffers, and planted in rows either
///   side of a wandering path by a hash of their slot (`wood_rows`), so the
///   wood is the same on every attempt and never repeats. Each tree is one
///   strip: bark tubes, and twigs as ribbons the shader turns to face the
///   camera (`sh_wood`).
/// - The ground is a function of position (`wood_ground_y`, also in the
///   shaders): flat tiles are raised to it on the GPU, and every mesh stands
///   on it the same way, so nothing floats.
/// - Light (`sh_wood`): the night sky, the moon with real shadows (a shadow
///   map drawn from its side, `wood_draw_shadow`), the witch-lights and wisps
///   as point lights, height fog toward the sky's own colour.
/// - The wood is drawn into a float surface and finished there
///   (`wood_post`): bloom, the moon's rays through the trees, a roll-off of
///   the highlights and a dither.
/// - The turn (`omen`) is the grove's: the stars go out, a shadow crosses the
///   moon and the wood goes dark, the moon comes out red, and a red wavefront
///   runs down the wood toward the camera, turning everything behind it.
/// - Every GPU state changed here is put back afterwards.

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// @desc Build the wood background.
function bg_wood() {
    // The base struct's parallax sprites are unused; they point at existing
    // sprites because a reference to a deleted asset throws at run time.
    var _b = bg_new(spr_wood_floor, spr_wood_floor, spr_wood_floor,
                    c_black, WOOD_SPEED);
    _b.kind = BGKIND_WOOD;
    _b.f_step = wood_step;
    _b.f_back = wood_draw_back;
    _b.f_front = wood_draw_front;
    _b.f_free = wood_free;

    _b.t = 0;
    _b.dist = 0;
    _b.spd = WOOD_SPEED;
    _b.rush = WOOD_SPEED;
    _b.swell = 1;
    // The opening: 0 is still in the fog, 1 is open (`WOOD_INTRO_TIME`).
    _b.intro = 0;
    // How much moonlight there is (dimmed by the eclipse).
    _b.light = WOOD_NIGHT_LIGHT;
    // The wavefront, as a distance ahead of the camera; far beyond the wood
    // until the turn launches it.
    _b.wave = WOOD_WAVE_Z0 * 4;

    // The camera: where it is, which way it looks (degrees), and how far it
    // has slid toward the player's side.
    _b.cam_x = 0;
    _b.cam_y = WOOD_CAM_H;
    _b.cam_z = 0;
    _b.yaw = 0;
    _b.pitch = WOOD_PITCH;
    _b.lean = 0;

    // Surfaces, made when first drawn (`wood_surface`).
    _b.surf = -1;
    _b.shadow = -1;
    _b.bloom_a = -1;
    _b.bloom_b = -1;
    _b.ray_a = -1;
    _b.ray_b = -1;
    _b.shadow_vp = matrix_build_identity();
    _b.shadow_org = [0, 0, 0];
    _b.shadow_dir = [0, -1, 0];

    _b.owned = [];
    wood_load(_b);
    wood_build_ground(_b);
    wood_build_sky(_b);
    _b.rows = wood_rows_new();
    // This frame's trees in view, far to near, and the charms hanging from
    // them (`wood_gather`).
    _b.seen = [];
    _b.seen_n = 0;
    _b.charm_seen = [];
    _b.charm_n = 0;
    // The wisps drifting through the wood (`wood_wisps_step`): each a row of
    // `[x, y, z, brightness, seed]`, and the buffer their glows are built in.
    _b.wisps = [];
    for (var _i = 0; _i < WOOD_WISPS; _i++) array_push(_b.wisps, array_create(5, 0));
    _b.vb_wisp = vertex_create_buffer();
    return _b;
}

/// @desc The vertex format everything in the wood is built in (see
///       `tools/wood_mesh.py`, which writes it byte for byte): position,
///       normal, colour, texture coordinates, and four more floats (the
///       anchor's x and z, `kind * 4 + conform`, and the wind's share).
function wood_format() {
    static _f = undefined;
    if (_f == undefined) {
        vertex_format_begin();
        vertex_format_add_position_3d();
        vertex_format_add_normal();
        vertex_format_add_colour();
        vertex_format_add_texcoord();
        vertex_format_add_custom(vertex_type_float4, vertex_usage_texcoord);
        _f = vertex_format_end();
    }
    return _f;
}

/// @desc Note a vertex buffer the wood owns, for `wood_free`.
function wood_own(_b, _vb) {
    if (_vb != -1) array_push(_b.owned, _vb);
    return _vb;
}

/// @desc A frozen vertex buffer from one of `datafiles/wood/`'s strips (zlib
///       data, as `wood_mesh.pack` writes it), or -1 if it is missing.
function wood_load_strip(_b, _file) {
    if (!file_exists(_file)) {
        show_debug_message("WOOD missing " + _file);
        return -1;
    }
    var _z = buffer_load(_file);
    var _raw = buffer_decompress(_z);
    buffer_delete(_z);
    if (_raw < 0) {
        show_debug_message("WOOD unreadable " + _file);
        return -1;
    }
    var _vb = vertex_create_buffer_from_buffer(_raw, wood_format());
    buffer_delete(_raw);
    if (vertex_get_number(_vb) <= 0) {
        vertex_delete_buffer(_vb);
        return -1;
    }
    vertex_freeze(_vb);
    return wood_own(_b, _vb);
}

/// @desc Load every tree, and index them by species.
function wood_load(_b) {
    var _n = array_length(global.wood_trees);
    _b.trees = array_create(_n, -1);
    _b.trees_far = array_create(_n, -1);
    _b.species = {};
    for (var _i = 0; _i < _n; _i++) {
        var _t = global.wood_trees[_i];
        _b.trees[_i] = wood_load_strip(_b, _t.file);
        _b.trees_far[_i] = wood_load_strip(_b, _t.far);
        var _l = _b.species[$ _t.species];
        if (_l == undefined) {
            _l = [];
            _b.species[$ _t.species] = _l;
        }
        array_push(_l, _i);
    }
    // The charms (triangle lists).
    var _nc = array_length(global.wood_charms);
    _b.charms = array_create(_nc, -1);
    for (var _i = 0; _i < _nc; _i++) {
        _b.charms[_i] = wood_load_strip(_b, global.wood_charms[_i].file);
    }
}

/// @desc Free what the wood holds outside its struct (`bg_free`).
function wood_free(_b) {
    for (var _i = 0; _i < array_length(_b.owned); _i++) {
        vertex_delete_buffer(_b.owned[_i]);
    }
    _b.owned = [];
    vertex_delete_buffer(_b.vb_wisp);
    _b.vb_wisp = vertex_create_buffer();
    var _s = [_b.surf, _b.shadow, _b.bloom_a, _b.bloom_b, _b.ray_a, _b.ray_b];
    for (var _i = 0; _i < array_length(_s); _i++) {
        if (surface_exists(_s[_i])) surface_free(_s[_i]);
    }
    _b.surf = -1;
    _b.shadow = -1;
    _b.bloom_a = -1;
    _b.bloom_b = -1;
    _b.ray_a = -1;
    _b.ray_b = -1;
}

/// @desc A stable pseudo-random number in [0, 1) from two numbers, so the
///       wood is the same on every attempt.
function wood_hash(_a, _b) {
    var _v = frac(sin(_a * 127.1 + _b * 311.7) * 43758.5453);
    return (_v < 0) ? _v + 1 : _v;
}

/// @desc One vertex in the wood's format.
function wood_vertex(_vb, _x, _y, _z, _nx, _ny, _nz, _col, _a, _u, _v,
                     _e0, _e1, _e2, _e3) {
    vertex_position_3d(_vb, _x, _y, _z);
    vertex_normal(_vb, _nx, _ny, _nz);
    vertex_colour(_vb, _col, _a);
    vertex_texcoord(_vb, _u, _v);
    vertex_float4(_vb, _e0, _e1, _e2, _e3);
}

// ---------------------------------------------------------------------------
// The ground
// ---------------------------------------------------------------------------

/// @desc The middle of the path at depth `_z`. The same sum as `path_x` in
///       the wood's shaders; change them together.
function wood_path_x(_z) {
    return 150 * sin(_z * 0.000982) + 60 * sin(_z * 0.002327 + 1.3);
}

/// @desc The ground's height at `(_x, _z)`: the path worn a little into it,
///       banks rising away from it either side, and hummocks out in the wood.
///       The same as `ground` in the wood's shaders; change them together.
function wood_ground_y(_x, _z) {
    var _dx = _x - wood_path_x(_z);
    var _a = abs(_dx);
    var _trough = -14 * (1 - wood_smooth(140, 300, _a));
    var _bank = 60 * wood_smooth(220, 1100, _a)
                * (0.65 + 0.35 * sin(_z * 0.0011 + sign(_dx) * 1.7));
    var _hum = 30 * sin(_x * 0.0031 + _z * 0.0017)
                  * sin(_z * 0.0023 - _x * 0.0013 + 1.1)
             + 16 * sin(_x * 0.0071 - _z * 0.0049 + 2.3)
                  * sin(_z * 0.0063 + _x * 0.0029);
    _hum *= wood_smooth(160, 500, _a);
    return _trough + _bank + _hum;
}

/// @desc GLSL's smoothstep.
function wood_smooth(_e0, _e1, _x) {
    var _t = clamp((_x - _e0) / (_e1 - _e0), 0, 1);
    return _t * _t * (3 - 2 * _t);
}

/// @desc Column `_i`'s x across a ground tile: close together near the path
///       (where the camera sees the ground up close), wide apart out in the
///       wood.
function wood_ground_col(_i) {
    var _u = _i / WOOD_GROUND_NX * 2 - 1;
    return sign(_u) * power(abs(_u), 1.7) * WOOD_GROUND_HALF;
}

/// @desc One ground tile: a flat grid `WOOD_TILE_Z` deep, as one strip, row
///       by row. The shader raises it to the ground (`conform` 1) and lays
///       its texture by world position, so one tile serves everywhere.
function wood_build_ground(_b) {
    var _vb = vertex_create_buffer();
    vertex_begin(_vb, wood_format());
    var _nx = WOOD_GROUND_NX;
    for (var _j = 0; _j < WOOD_GROUND_NZ; _j++) {
        var _z0 = WOOD_TILE_Z * _j / WOOD_GROUND_NZ;
        var _z1 = WOOD_TILE_Z * (_j + 1) / WOOD_GROUND_NZ;
        for (var _i = 0; _i <= _nx; _i++) {
            var _x = wood_ground_col(_i);
            // A row starts with its first vertex twice (and the one before
            // ended with its last twice), which joins the rows by triangles
            // of no area.
            if (_i == 0 && _j > 0) {
                wood_vertex(_vb, _x, 0, _z0, 0, 1, 0, c_white, 1, 0, 0,
                            _x, _z0, 1, 0);
            }
            wood_vertex(_vb, _x, 0, _z0, 0, 1, 0, c_white, 1, 0, 0,
                        _x, _z0, 1, 0);
            wood_vertex(_vb, _x, 0, _z1, 0, 1, 0, c_white, 1, 0, 0,
                        _x, _z1, 1, 0);
            if (_i == _nx && _j < WOOD_GROUND_NZ - 1) {
                wood_vertex(_vb, _x, 0, _z1, 0, 1, 0, c_white, 1, 0, 0,
                            _x, _z1, 1, 0);
            }
        }
    }
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_ground = wood_own(_b, _vb);
}

// ---------------------------------------------------------------------------
// The sky
// ---------------------------------------------------------------------------

/// @desc A unit direction from an azimuth (0 is straight down the wood, +z;
///       90 is +x) and an elevation, in degrees.
function wood_dir(_az, _el) {
    var _c = dcos(_el);
    return [_c * dsin(_az), dsin(_el), _c * dcos(_az)];
}

/// @desc The moon's direction (where its disc is).
function wood_moon_vis() {
    return wood_dir(0, WOOD_MOON_EL);
}

/// @desc Build the sky: the dome, the stars, the moon, its corona, clouds.
///       All as triangle lists (cards are few), frozen.
function wood_build_sky(_b) {
    var _f = wood_format();

    // The dome: rings of quads from below the horizon to the top.
    var _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    var _rows = 14;
    var _cols = 36;
    for (var _j = 0; _j < _rows; _j++) {
        var _e0 = lerp(-30, 90, _j / _rows);
        var _e1 = lerp(-30, 90, (_j + 1) / _rows);
        for (var _i = 0; _i < _cols; _i++) {
            var _a0 = 360 * _i / _cols;
            var _a1 = 360 * (_i + 1) / _cols;
            var _p = [wood_dir(_a0, _e1), wood_dir(_a1, _e1),
                      wood_dir(_a1, _e0), wood_dir(_a0, _e0)];
            var _o = [0, 1, 2, 0, 2, 3];
            for (var _k = 0; _k < 6; _k++) {
                var _q = _p[_o[_k]];
                wood_vertex(_vb, _q[0] * WOOD_SKY_R, _q[1] * WOOD_SKY_R,
                            _q[2] * WOOD_SKY_R, -_q[0], -_q[1], -_q[2],
                            c_white, 1, 0, 0, 0, 0, 0, 0);
            }
        }
    }
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_dome = wood_own(_b, _vb);

    // The stars: spread evenly by area over the sky, fewer toward the
    // horizon, where the haze swallows them.
    _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    for (var _i = 0; _i < WOOD_STARS; _i++) {
        var _el = darcsin(wood_hash(_i, 70));
        if (_el < 4) continue;
        var _d = wood_dir(wood_hash(_i, 71) * 360, _el);
        var _m = wood_hash(_i, 75);
        var _sz = WOOD_STAR_SIZE * ((_m > 0.96) ? 2.2 : ((_m > 0.8) ? 1.2 : 0.7))
                  * (0.75 + 0.5 * wood_hash(_i, 77));
        var _a = ((_m > 0.96) ? 0.95 : ((_m > 0.8) ? 0.65 : 0.38))
                 * clamp((_el - 4) / 14, 0, 1);
        var _h = wood_hash(_i, 76);
        var _col = (_h > 0.9) ? make_colour_rgb(255, 226, 190)
                 : ((_h > 0.45) ? make_colour_rgb(236, 246, 255)
                                : make_colour_rgb(190, 222, 255));
        wood_card_list(_vb, _d, _sz, WOOD_SKY_R * 0.96, _col, _a,
                       wood_hash(_i, 78));
    }
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_stars = wood_own(_b, _vb);

    // The moon: one card, sized so its disc (0.94 of the card) spans
    // `WOOD_MOON_R` degrees either side of its centre.
    var _md = wood_moon_vis();
    var _dist = WOOD_SKY_R * 0.92;
    _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    wood_card_list(_vb, _md, _dist * dtan(WOOD_MOON_R) / 0.94, _dist,
                   c_white, 1, 0);
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_moon = wood_own(_b, _vb);

    // The rim of light at totality (and the ring that leaves the moon after
    // it): a ring card a little wider than the disc, just in front of it.
    _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    wood_card_list(_vb, _md, _dist * dtan(WOOD_MOON_R) * 1.12, _dist * 0.985,
                   make_colour_rgb(255, 120, 90), 1, 0);
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_rim = wood_own(_b, _vb);

    // Its corona: a wide soft glow and a tight bright one, just in front.
    _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    wood_card_list(_vb, _md, _dist * dtan(WOOD_MOON_R) * 4.2, _dist * 0.995,
                   c_white, 0.30, 0);
    wood_card_list(_vb, _md, _dist * dtan(WOOD_MOON_R) * 1.65, _dist * 0.99,
                   c_white, 0.55, 0);
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_corona = wood_own(_b, _vb);

    // Clouds: a few long thin banks low over the far wood and across the
    // moon (the wood turns them slowly round the sky, `wood_draw_sky`).
    _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    for (var _i = 0; _i < WOOD_CLOUDS; _i++) {
        var _az = (wood_hash(_i, 91) * 2 - 1) * 60;
        var _el = 2 + wood_hash(_i, 92) * 13;
        var _w = WOOD_SKY_R * (0.30 + 0.30 * wood_hash(_i, 93));
        wood_cloud_card(_vb, wood_dir(_az, _el), _w, _w * 0.16,
                        WOOD_SKY_R * (0.90 - 0.002 * _i),
                        0.55 + 0.45 * wood_hash(_i, 94));
    }
    vertex_end(_vb);
    vertex_freeze(_vb);
    _b.vb_cloud = wood_own(_b, _vb);
}

/// @desc A sky card as a triangle list (six vertices).
function wood_card_list(_vb, _d, _r, _dist, _col, _a, _seed) {
    wood_card_list_ext(_vb, _d, _r, _r, _dist, _col, _a, _seed);
}

/// @desc ...with its own half-width and half-height.
function wood_card_list_ext(_vb, _d, _rw, _rh, _dist, _col, _a, _seed) {
    var _up = (abs(_d[1]) > 0.985) ? [0, 0, 1] : [0, 1, 0];
    var _rx = _up[1] * _d[2] - _up[2] * _d[1];
    var _ry = _up[2] * _d[0] - _up[0] * _d[2];
    var _rz = _up[0] * _d[1] - _up[1] * _d[0];
    var _rl = max(0.0001, sqrt(_rx * _rx + _ry * _ry + _rz * _rz));
    _rx /= _rl; _ry /= _rl; _rz /= _rl;
    var _ux = _d[1] * _rz - _d[2] * _ry;
    var _uy = _d[2] * _rx - _d[0] * _rz;
    var _uz = _d[0] * _ry - _d[1] * _rx;
    var _px = _d[0] * _dist, _py = _d[1] * _dist, _pz = _d[2] * _dist;
    // tl, tr, br, tl, br, bl
    var _c = [[-1, 1, 0, 0], [1, 1, 1, 0], [1, -1, 1, 1],
              [-1, 1, 0, 0], [1, -1, 1, 1], [-1, -1, 0, 1]];
    for (var _k = 0; _k < 6; _k++) {
        var _sx = _c[_k][0] * _rw, _sy = _c[_k][1] * _rh;
        wood_vertex(_vb, _px + _rx * _sx + _ux * _sy,
                    _py + _ry * _sx + _uy * _sy,
                    _pz + _rz * _sx + _uz * _sy,
                    -_d[0], -_d[1], -_d[2], _col, _a,
                    _c[_k][2], _c[_k][3], _seed, 0, 0, 0);
    }
}

/// @desc A cloud bank: a wide card.
function wood_cloud_card(_vb, _d, _rw, _rh, _dist, _a) {
    wood_card_list_ext(_vb, _d, _rw, _rh, _dist, c_white, _a, 0);
}

// ---------------------------------------------------------------------------
// The trees: rows either side of the path, planted by slot
// ---------------------------------------------------------------------------

/// @desc The rows of the wood, from the path outward: how far from the path's
///       middle a row's trees stand, how long a slot is along the path (each
///       slot holds at most one tree a side), the chance a slot holds one, and
///       which species grow there. Each row keeps the slots in reach worked
///       out (`cache`), since a slot's tree never changes.
function wood_rows_new() {
    var _rows = [
        { inner: WOOD_ROW0_IN, outer: WOOD_ROW0_OUT, slot: 520, chance: 0.50,
          kinds: ["snag", "snag", "ancient", "oak"] },
        { inner: 620, outer: 1150, slot: 250, chance: 0.80,
          kinds: ["oak", "oak", "crook", "weeper", "snag", "sapling"] },
        { inner: 1150, outer: 2000, slot: 260, chance: 0.88,
          kinds: ["oak", "crook", "weeper", "snag", "ancient", "oak"] },
        { inner: 2000, outer: 3300, slot: 300, chance: 0.92,
          kinds: ["oak", "snag", "weeper", "crook", "oak"] },
        { inner: 3300, outer: 5200, slot: 360, chance: 0.92,
          kinds: ["oak", "snag", "weeper", "oak"] },
    ];
    for (var _r = 0; _r < array_length(_rows); _r++) {
        var _row = _rows[_r];
        var _n = ceil((WOOD_FAR + WOOD_BEHIND) / _row.slot) + 3;
        _row.n = _n;
        _row.cache = array_create(_n, undefined);
        for (var _i = 0; _i < _n; _i++) {
            _row.cache[_i] = { idx: -999999, trees: [] };
        }
    }
    return _rows;
}

/// @desc Work out slot `_i` of row `_r`: for each side of the path, whether a
///       tree stands there, which, where, turned how. A tree reaches toward
///       its local +x, so it is turned to reach over the path.
function wood_slot_fill(_b, _row, _r, _slot, _i) {
    _slot.idx = _i;
    _slot.trees = [];
    for (var _s = -1; _s <= 1; _s += 2) {
        var _key = _i * 13 + _r * 977 + (_s + 1) * 31;
        if (wood_hash(_key, 1) > _row.chance) continue;
        var _kinds = _row.kinds;
        var _sp = _kinds[floor(wood_hash(_key, 2) * array_length(_kinds))
                         mod array_length(_kinds)];
        var _list = _b.species[$ _sp];
        if (_list == undefined) continue;
        var _m = _list[floor(wood_hash(_key, 3) * array_length(_list))
                       mod array_length(_list)];
        if (_b.trees[_m] == -1) continue;
        var _info = global.wood_trees[_m];
        var _z = (_i + 0.15 + 0.7 * wood_hash(_key, 4)) * _row.slot;
        var _off = lerp(_row.inner, _row.outer, wood_hash(_key, 5));
        // Keep a tree's trunk clear of the path whatever its size.
        _off = max(_off, WOOD_PATH_CLEAR + _info.r0 * 1.6);
        var _x = wood_path_x(_z) + _s * _off;
        var _yaw = ((_s < 0) ? 0 : 180) + (wood_hash(_key, 6) * 2 - 1) * 40;
        var _sc = 0.86 + 0.32 * wood_hash(_key, 7);
        var _mz = (wood_hash(_key, 8) < 0.5) ? -1 : 1;
        var _t = {
            mesh: _m,
            x: _x,
            z: _z,
            y: wood_ground_y(_x, _z),
            mat: matrix_build(_x, 0, _z, 0, _yaw, 0, _sc, _sc, _sc * _mz),
            // A sphere round it, for culling: its centre's height, radius.
            cy: _info.height * _sc * 0.5,
            rad: max(_info.spread, _info.height * 0.5) * _sc * 1.05,
            row: _r,
            d2: 0,
            charms: [],
        };
        array_push(_slot.trees, _t);
        if (_r <= 1) wood_hang_charms(_t, _info, _key);
    }
}

/// @desc Hang charms from a tree near the path: one (two, on a big tree) of
///       its hang points over the path side, by chance, each with a charm
///       of its own kind and swing. The point a charm hangs from is fixed in
///       the world once worked out; only its swing moves.
function wood_hang_charms(_t, _info, _key) {
    var _hp = _info.hangs;
    var _n = array_length(_hp);
    if (_n == 0) return;
    if (wood_hash(_key, 21) > WOOD_CHARM_ODDS) return;
    var _count = (_info.height > 900 && wood_hash(_key, 22) < 0.45) ? 2 : 1;
    var _nk = array_length(global.wood_charms);
    for (var _c = 0; _c < _count; _c++) {
        // The first few points are the furthest over the path; one in the
        // lane is passed over (its limb is lifted out of the lane).
        var _h = _hp[floor(wood_hash(_key, 23 + _c) * min(_n, 6)) mod _n];
        var _p = matrix_transform_vertex(_t.mat, _h[0], _h[1], _h[2]);
        var _kind = floor(wood_hash(_key, 25 + _c) * _nk) mod _nk;
        var _drop = global.wood_charms[_kind].drop * WOOD_CHARM_SCALE * 1.15;
        if (abs(_p[0] - wood_path_x(_p[2])) < WOOD_LANE_W * 1.1
            && _p[1] + _t.y - _drop < WOOD_LANE_TOP + 60) continue;
        array_push(_t.charms, {
            kind: _kind,
            x: _p[0],
            y: _p[1] + _t.y,
            z: _p[2],
            yaw: (wood_hash(_key, 27 + _c) * 2 - 1) * 28,
            ph: wood_hash(_key, 29 + _c) * 360,
            ph2: wood_hash(_key, 31 + _c) * 360,
            amp: WOOD_CHARM_SWING * (0.6 + 0.8 * wood_hash(_key, 33 + _c)),
            s: WOOD_CHARM_SCALE * (0.85 + 0.3 * wood_hash(_key, 35 + _c)),
            seed: _key * 0.37 + _c,
            mat: matrix_build_identity(),
            light: [0, 0, 0],
        });
    }
}

/// @desc Gather this frame's trees in view into `_b.seen`, far to near.
function wood_gather(_b) {
    _b.seen_n = 0;
    var _cz = _b.cam_z;
    var _fx = dsin(_b.yaw), _fz = dcos(_b.yaw);
    var _rx = _fz, _rz = -_fx;
    var _th = dtan(WOOD_FOV * 0.5) * (FIELD_W / FIELD_H) * 1.08;
    var _rows = _b.rows;
    for (var _r = 0; _r < array_length(_rows); _r++) {
        var _row = _rows[_r];
        var _i0 = floor((_cz - WOOD_BEHIND) / _row.slot);
        var _i1 = floor((_cz + WOOD_FAR) / _row.slot);
        for (var _i = _i0; _i <= _i1; _i++) {
            var _slot = _row.cache[((_i mod _row.n) + _row.n) mod _row.n];
            if (_slot.idx != _i) wood_slot_fill(_b, _row, _r, _slot, _i);
            var _tr = _slot.trees;
            for (var _k = 0; _k < array_length(_tr); _k++) {
                var _t = _tr[_k];
                var _dx = _t.x - _b.cam_x;
                var _dz = _t.z - _cz;
                var _f = _dx * _fx + _dz * _fz;
                if (_f < -_t.rad) continue;
                var _s = _dx * _rx + _dz * _rz;
                if (abs(_s) - _t.rad * 1.15 > max(_f, 0) * _th) continue;
                _t.d2 = _dx * _dx + _dz * _dz;
                if (_b.seen_n >= array_length(_b.seen)) array_push(_b.seen, _t);
                else _b.seen[_b.seen_n] = _t;
                _b.seen_n++;
            }
        }
    }
    // Far to near, so a twig's soft edge blends over what is behind it.
    if (array_length(_b.seen) > _b.seen_n) array_resize(_b.seen, _b.seen_n);
    array_sort(_b.seen, function(_p, _q) { return sign(_q.d2 - _p.d2); });

    // The charms on them, swung for this frame.
    _b.charm_n = 0;
    for (var _i = 0; _i < _b.seen_n; _i++) {
        var _ch = _b.seen[_i].charms;
        for (var _k = 0; _k < array_length(_ch); _k++) {
            var _c = _ch[_k];
            var _ax = dsin(_b.t * 1.1 + _c.ph) * _c.amp;
            var _az = dsin(_b.t * 0.83 + _c.ph2) * _c.amp * 0.6;
            _c.mat = matrix_build(_c.x, _c.y, _c.z, _ax, _c.yaw, _az,
                                  _c.s, _c.s, _c.s);
            var _g = global.wood_charms[_c.kind].glow;
            _c.light = matrix_transform_vertex(_c.mat, _g[0], _g[1], _g[2]);
            if (_b.charm_n >= array_length(_b.charm_seen)) {
                array_push(_b.charm_seen, _c);
            } else {
                _b.charm_seen[_b.charm_n] = _c;
            }
            _b.charm_n++;
        }
    }
}

// ---------------------------------------------------------------------------
// The wisps: will-o'-the-wisps drifting through the trees beside the path,
// each a light that wanders past the trunks
// ---------------------------------------------------------------------------

/// @desc Where each wisp is this frame. A wisp keeps to a stretch of wood
///       `WOOD_WISP_SPAN` long that the camera flies through (so it is fixed
///       in the world but for its own wandering), and when the camera has
///       passed it, it is somewhere new far ahead (its `lap`).
function wood_wisps_step(_b) {
    for (var _i = 0; _i < WOOD_WISPS; _i++) {
        var _w = _b.wisps[_i];
        var _ph = wood_hash(_i, 61);
        var _u = frac(_ph + _b.dist / WOOD_WISP_SPAN);
        if (_u < 0) _u += 1;
        var _lap = floor(_ph + _b.dist / WOOD_WISP_SPAN) * 7 + _i;
        var _rel = WOOD_WISP_SPAN * (1 - _u) + 150;
        var _z = _b.dist + _rel + wood_wisp_wander(_b.t, _i, 2);
        var _side = (wood_hash(_lap, 62) < 0.5) ? -1 : 1;
        var _off = 330 + wood_hash(_lap, 63) * 900;
        var _x = wood_path_x(_z) + _side * _off + wood_wisp_wander(_b.t, _i, 0);
        var _y = wood_ground_y(_x, _z) + 70 + wood_hash(_lap, 64) * 260
                 + wood_wisp_wander(_b.t, _i, 1);
        // In over the far end, out before the camera.
        var _a = min(1, _u * 5) * min(1, (1 - _u) * 6)
                 * (0.82 + 0.18 * dsin(_b.t * 2.3 + _i * 61));
        _w[0] = _x;
        _w[1] = _y;
        _w[2] = _z;
        _w[3] = _a;
        _w[4] = _i * 13.7;
    }
}

/// @desc How far wisp `_i` has wandered from its line at time `_t`, along
///       axis `_ax` (0 across, 1 up, 2 along).
function wood_wisp_wander(_t, _i, _ax) {
    switch (_ax) {
        case 0: return dsin(_t * 0.43 + _i * 51) * 140 + dsin(_t * 0.97 + _i * 23) * 50;
        case 1: return dsin(_t * 0.71 + _i * 37) * 40;
    }
    return dsin(_t * 0.31 + _i * 77) * 160;
}

// ---------------------------------------------------------------------------
// The clock
// ---------------------------------------------------------------------------

function wood_step(_b) {
    _b.t++;

    // The opening eases in: it drives the speed and the fog.
    if (_b.intro < 1) _b.intro = min(1, _b.intro + 1 / WOOD_INTRO_TIME);
    var _in = wood_ease(_b.intro);

    // The speed and the light follow the (eased) turn.
    var _e = wood_ease(_b.omen);
    _b.spd = lerp(WOOD_SPEED, WOOD_SPEED_FAST, _e) * lerp(WOOD_INTRO_SPD, 1, _in);
    _b.light = WOOD_NIGHT_LIGHT * (1 - 0.88 * wood_totality(_b));
    _b.swell = 1 + WOOD_SWELL_SURGE * dsin(_b.t * 360 / WOOD_SWELL) * _in;
    _b.rush = _b.spd * _b.swell;
    _b.dist += _b.rush;

    // The camera follows the path, a little behind its bends, and leans
    // toward the player's side (eased and capped, so dodging doesn't shake
    // it).
    var _z = _b.dist;
    var _want = WOOD_LEAN * _b.aim * _in;
    _b.lean += clamp((_want - _b.lean) * WOOD_LEAN_EASE, -WOOD_LEAN_SPD,
                     WOOD_LEAN_SPD);
    var _px = wood_path_x(_z);
    var _ahead = wood_path_x(_z + WOOD_LOOK_AHEAD);
    var _wander = WOOD_SWAY * _in
                  * (0.72 * dsin(_b.t * 360 / WOOD_SWAY_P1)
                     + 0.28 * dsin(_b.t * 360 / WOOD_SWAY_P2 + 47));
    _b.cam_x = _px + _b.lean;
    _b.cam_z = _z;
    _b.cam_y = wood_ground_y(_px, _z) + WOOD_CAM_H
               + WOOD_RISE * _in * (0.74 * dsin(_b.t * 360 / WOOD_RISE_P1 + 23)
                                    + 0.26 * dsin(_b.t * 360 / WOOD_RISE_P2 + 131));
    _b.yaw = radtodeg(arctan2(_ahead - _px, WOOD_LOOK_AHEAD)) * WOOD_YAW_FOLLOW
             + _wander;
    _b.pitch = WOOD_PITCH;

    // The wavefront launches at totality and runs the wood's whole depth.
    var _w = wood_wave_t(_b);
    _b.wave = (_w <= 0) ? WOOD_WAVE_Z0 * 4
                        : WOOD_WAVE_Z0 * (1 - _w) - WOOD_WAVE_FEATHER;

    wood_wisps_step(_b);
}

/// @desc 0..1: how red something `_rel` ahead of the camera has become (the
///       wavefront has passed it).
function wood_blood_at(_b, _rel) {
    return clamp((_rel - _b.wave) / WOOD_WAVE_FEATHER, 0, 1);
}

/// @desc 0..1: a bump where the wavefront is passing (charms flare as it
///       reaches them).
function wood_flare_at(_b, _rel) {
    if (_b.wave > WOOD_WAVE_Z0 * 2) return 0;
    return clamp(1 - abs(_rel - _b.wave) / WOOD_CHARM_FLARE, 0, 1);
}

/// @desc A witch-light's flicker; `_s` tells one from another.
function wood_flicker(_s, _t) {
    return 1 + 0.10 * sin(_t * 0.11 + _s * 12.9898)
             + 0.07 * sin(_t * 0.37 + _s * 78.233)
             + 0.04 * sin(_t * 1.13 + _s * 37.719);
}

/// @desc A charm's light this frame, as `[r, g, b]` (over 1 is bright): the
///       cold witch-light, orange behind the wavefront, flaring as it passes.
function wood_charm_light(_b, _c) {
    var _rel = _c.z - _b.cam_z;
    var _bl = wood_blood_at(_b, _rel);
    var _k = (1 + 2.5 * wood_flare_at(_b, _rel)) * wood_flicker(_c.seed, _b.t);
    var _col = merge_colour(WOOD_CHARM_COL_N, WOOD_CHARM_COL_B, _bl);
    return wood_rgb(_col, _k);
}

/// @desc Smoothstep of 0..1.
function wood_ease(_o) {
    var _k = clamp(_o, 0, 1);
    return _k * _k * (3 - 2 * _k);
}

/// @desc How far through the wavefront's own travel the turn is, 0..1.
function wood_wave_t(_b) {
    if (_b.omen <= WOOD_WAVE_START) return 0;
    return (_b.omen - WOOD_WAVE_START) / (1 - WOOD_WAVE_START);
}

/// @desc The shadow's transit across the moon, 0..1 (half is totality).
function wood_eclipse(_b) {
    return clamp(_b.omen / WOOD_WAVE_START, 0, 1);
}

/// @desc 0..1: how total the eclipse is.
function wood_totality(_b) {
    return clamp(1 - abs(wood_eclipse(_b) - 0.5) * 4.4, 0, 1);
}

/// @desc How far the sky, moon and stars have turned red (they are at
///       infinity, so they follow the turn rather than the wavefront).
function wood_sky_blood(_b) {
    return wood_ease(clamp((_b.omen - 0.18) / 0.34, 0, 1));
}

// ---------------------------------------------------------------------------
// The draw
// ---------------------------------------------------------------------------

/// @desc A surface of the given size and format: `_s` if it still exists at
///       that size, else a new one (surfaces can be lost at any time).
function wood_surface(_s, _w, _h, _fmt = surface_rgba8unorm, _depth = false) {
    if (surface_exists(_s)) {
        if (surface_get_width(_s) == _w && surface_get_height(_s) == _h) {
            return _s;
        }
        surface_free(_s);
    }
    if (!surface_format_is_supported(_fmt)) _fmt = surface_rgba8unorm;
    surface_depth_disable(!_depth);
    var _n = surface_create(_w, _h, _fmt);
    surface_depth_disable(false);
    return _n;
}

/// @desc The palettes, as the shaders take them: `[r, g, b]` 0..1, night
///       and blood.
function wood_rgb(_c, _k = 1) {
    return [colour_get_red(_c) / 255 * _k, colour_get_green(_c) / 255 * _k,
            colour_get_blue(_c) / 255 * _k];
}

/// @desc The uniforms of `sh_wood`, looked up once.
function wood_uniforms() {
    static _u = undefined;
    if (_u == undefined) {
        _u = {};
        var _names = ["u_cam", "u_eye", "u_time", "u_wind", "u_pix",
                      "u_shadow", "u_ground", "u_floor", "u_shadowp", "u_lorg", "u_ldir", "u_lrange",
                      "u_alpharef", "u_mat", "u_glowcol", "u_raise", "u_lane",
                      "u_moon",
                      "u_moon_vis",
                      "u_light", "u_wave", "u_flare", "u_sky_a", "u_sky_b",
                      "u_bounce_a", "u_bounce_b", "u_moon_a", "u_moon_b",
                      "u_rim_a", "u_rim_b", "u_hor_a", "u_hor_b", "u_zen_a",
                      "u_zen_b", "u_haze_a", "u_haze_b", "u_fogp", "u_fogfar",
                      "u_lpos", "u_lcol"];
        for (var _i = 0; _i < array_length(_names); _i++) {
            _u[$ _names[_i]] = shader_get_uniform(sh_wood, _names[_i]);
        }
        _u.s_nmap = shader_get_sampler_index(sh_wood, "u_nmap");
        _u.s_tex2 = shader_get_sampler_index(sh_wood, "u_tex2");
        _u.s_nmap2 = shader_get_sampler_index(sh_wood, "u_nmap2");
        _u.s_shadow = shader_get_sampler_index(sh_wood, "u_shadowmap");
    }
    return _u;
}

/// @desc Set a vec3 uniform from `[r, g, b]`.
function wood_u3(_h, _v) {
    shader_set_uniform_f(_h, _v[0], _v[1], _v[2]);
}

/// @desc This frame's light, shared by every pass.
function wood_light_state() {
    static _s = {
        sb: 0, light: 1, wave: 0, flare: 0, moon: [0, 1, 0], moon_vis: [0, 0, 1],
        lpos: array_create(WOOD_LIGHTS * 4, 0),
        lcol: array_create(WOOD_LIGHTS * 4, 0),
    };
    return _s;
}

/// @desc Work out this frame's light from the background's state.
function wood_light_frame(_b) {
    var _l = wood_light_state();
    _l.sb = wood_sky_blood(_b);
    _l.light = _b.light;
    _l.wave = _b.wave;
    // The front's own light: a flare as it runs (gone once it has passed
    // the camera).
    var _w = wood_wave_t(_b);
    _l.flare = (_w > 0 && _w < 1) ? (1 - _w * 0.6) : 0;
    var _m = WOOD_MOON_DIR;
    var _ml = point_distance_3d(0, 0, 0, _m[0], _m[1], _m[2]);
    _l.moon = [_m[0] / _ml, _m[1] / _ml, _m[2] / _ml];
    _l.moon_vis = wood_moon_vis();
    wood_lights(_b, _l);
}

/// @desc The point lights the shader takes this frame: the nearest of the
///       charms in view and the wisps, `WOOD_LIGHTS` at most. A light fades
///       out toward `WOOD_LIGHT_FAR`, so the one that drops off the end of
///       the list is already dark.
function wood_lights(_b, _l) {
    static _cand = [];
    var _n = 0;
    for (var _i = 0; _i < _b.charm_n; _i++) {
        var _c = _b.charm_seen[_i];
        var _p = _c.light;
        var _d2 = sqr(_p[0] - _b.cam_x) + sqr(_p[2] - _b.cam_z);
        if (_d2 > sqr(WOOD_LIGHT_FAR)) continue;
        var _rgb = wood_charm_light(_b, _c);
        var _k = WOOD_CHARM_POW;
        if (_n >= array_length(_cand)) array_push(_cand, array_create(8, 0));
        var _e = _cand[_n];
        _e[0] = _d2; _e[1] = _p[0]; _e[2] = _p[1]; _e[3] = _p[2];
        _e[4] = WOOD_CHARM_REACH; _e[5] = _rgb[0] * _k; _e[6] = _rgb[1] * _k;
        _e[7] = _rgb[2] * _k;
        _n++;
    }
    for (var _i = 0; _i < WOOD_WISPS; _i++) {
        var _w = _b.wisps[_i];
        if (_w[3] <= 0.01) continue;
        var _d2 = sqr(_w[0] - _b.cam_x) + sqr(_w[2] - _b.cam_z);
        if (_d2 > sqr(WOOD_LIGHT_FAR)) continue;
        var _bl = wood_blood_at(_b, _w[2] - _b.cam_z);
        var _rgb = wood_rgb(merge_colour(WOOD_WISP_COL_N, WOOD_WISP_COL_B, _bl),
                            WOOD_WISP_POW * _w[3]);
        if (_n >= array_length(_cand)) array_push(_cand, array_create(8, 0));
        var _e = _cand[_n];
        _e[0] = _d2; _e[1] = _w[0]; _e[2] = _w[1]; _e[3] = _w[2];
        _e[4] = WOOD_WISP_REACH; _e[5] = _rgb[0]; _e[6] = _rgb[1]; _e[7] = _rgb[2];
        _n++;
    }
    // The nearest first (a short partial selection: the list is small).
    var _take = min(_n, WOOD_LIGHTS);
    for (var _i = 0; _i < _take; _i++) {
        var _best = _i;
        for (var _j = _i + 1; _j < _n; _j++) {
            if (_cand[_j][0] < _cand[_best][0]) _best = _j;
        }
        if (_best != _i) {
            var _tmp = _cand[_i];
            _cand[_i] = _cand[_best];
            _cand[_best] = _tmp;
        }
    }
    for (var _i = 0; _i < WOOD_LIGHTS; _i++) {
        var _o = _i * 4;
        if (_i < _take) {
            var _e = _cand[_i];
            var _fade = 1 - wood_smooth(WOOD_LIGHT_FAR * 0.6, WOOD_LIGHT_FAR,
                                        sqrt(_e[0]));
            _l.lpos[_o] = _e[1];
            _l.lpos[_o + 1] = _e[2];
            _l.lpos[_o + 2] = _e[3];
            _l.lpos[_o + 3] = _e[4];
            _l.lcol[_o] = _e[5] * _fade;
            _l.lcol[_o + 1] = _e[6] * _fade;
            _l.lcol[_o + 2] = _e[7] * _fade;
            _l.lcol[_o + 3] = 0;
        } else {
            for (var _q = 0; _q < 4; _q++) {
                _l.lpos[_o + _q] = 0;
                _l.lcol[_o + _q] = 0;
            }
        }
    }
}

/// @desc Set `sh_wood` and every uniform the frame shares.
function wood_shader(_b) {
    var _u = wood_uniforms();
    var _l = wood_light_state();
    shader_set(sh_wood);
    shader_set_uniform_f(_u.u_cam, _b.cam_x, _b.cam_y, _b.cam_z);
    shader_set_uniform_f(_u.u_eye, _b.cam_x, _b.cam_y, _b.cam_z);
    shader_set_uniform_f(_u.u_time, _b.t mod 100000);
    var _wd = WOOD_WIND_DIR;
    shader_set_uniform_f(_u.u_wind, WOOD_WIND, 1, _wd[0], _wd[1]);
    shader_set_uniform_f(_u.u_pix, 2 * dtan(WOOD_FOV * 0.5) / FIELD_H);
    shader_set_uniform_matrix_array(_u.u_shadow, _b.shadow_vp);
    shader_set_uniform_f(_u.u_shadowp, 1 / WOOD_SHADOW_SIZE, WOOD_SHADOW_BIAS,
                         WOOD_SHADOW_DARK * _l.light / WOOD_NIGHT_LIGHT,
                         WOOD_SHADOW_REACH);
    shader_set_uniform_f(_u.u_lorg, _b.shadow_org[0], _b.shadow_org[1],
                         _b.shadow_org[2]);
    shader_set_uniform_f(_u.u_ldir, _b.shadow_dir[0], _b.shadow_dir[1],
                         _b.shadow_dir[2]);
    shader_set_uniform_f(_u.u_lrange, WOOD_SHADOW_RANGE);
    wood_floor(0);
    shader_set_uniform_f(_u.u_alpharef, 0.02);
    shader_set_uniform_f(_u.u_glowcol, 1, 1, 1);
    shader_set_uniform_f(_u.u_raise, 1);
    wood_lane(_u.u_lane);
    wood_u3(_u.u_moon, _l.moon);
    wood_u3(_u.u_moon_vis, _l.moon_vis);
    shader_set_uniform_f(_u.u_light, _l.light);
    shader_set_uniform_f(_u.u_wave, _l.wave, WOOD_WAVE_FEATHER);
    var _fc = WOOD_FLARE_COL;
    shader_set_uniform_f(_u.u_flare, _fc[0] * _l.flare, _fc[1] * _l.flare,
                         _fc[2] * _l.flare, WOOD_WAVE_FLARE);
    wood_u3(_u.u_sky_a, WOOD_SKY_N);
    wood_u3(_u.u_sky_b, WOOD_SKY_B);
    wood_u3(_u.u_bounce_a, WOOD_BOUNCE_N);
    wood_u3(_u.u_bounce_b, WOOD_BOUNCE_B);
    wood_u3(_u.u_moon_a, WOOD_MOONLIGHT_N);
    wood_u3(_u.u_moon_b, WOOD_MOONLIGHT_B);
    wood_u3(_u.u_rim_a, WOOD_RIM_N);
    wood_u3(_u.u_rim_b, WOOD_RIM_B);
    wood_u3(_u.u_hor_a, WOOD_HOR_N);
    wood_u3(_u.u_hor_b, WOOD_HOR_B);
    wood_u3(_u.u_zen_a, WOOD_ZEN_N);
    wood_u3(_u.u_zen_b, WOOD_ZEN_B);
    wood_u3(_u.u_haze_a, WOOD_HAZE_N);
    wood_u3(_u.u_haze_b, WOOD_HAZE_B);
    var _fog = wood_fog(_b);
    shader_set_uniform_f(_u.u_fogp, _fog, WOOD_FOG_FALL, WOOD_FOG_BASE, 1);
    shader_set_uniform_f(_u.u_fogfar, WOOD_FAR * 0.78, WOOD_FAR * 0.97);
    shader_set_uniform_f_array(_u.u_lpos, _l.lpos);
    shader_set_uniform_f_array(_u.u_lcol, _l.lcol);
    texture_set_stage(_u.s_shadow, surface_get_texture(_b.shadow));
    gpu_set_tex_filter_ext(_u.s_shadow, false);
    gpu_set_tex_mip_enable_ext(_u.s_shadow, mip_off);
    gpu_set_texrepeat_ext(_u.s_shadow, false);
}

/// @desc Whether the next submits are the ground's own tiles, in both of the
///       shader's stages (each takes its own copy: see `sh_wood.fsh`).
function wood_floor(_on) {
    var _u = wood_uniforms();
    shader_set_uniform_f(_u.u_ground, _on);
    shader_set_uniform_f(_u.u_floor, _on);
}

/// @desc Set a shader's `u_lane`: the lane down the path the camera flies,
///       which the shaders keep clear (`lane` in `sh_wood.vsh`).
function wood_lane(_h) {
    shader_set_uniform_f(_h, WOOD_LANE_W, WOOD_LANE_TOP, WOOD_LANE_LO, 1);
}

/// @desc Whether a point is inside the lane the shaders keep clear (charms
///       aren't hung there: the limb they would hang from is lifted out of
///       it).
function wood_in_lane(_x, _y, _z) {
    return abs(_x - wood_path_x(_z)) < WOOD_LANE_W && _y < WOOD_LANE_TOP + 40;
}

/// @desc How thick the air is: dense while the opening's fog lifts.
function wood_fog(_b) {
    var _in = wood_ease(_b.intro);
    return lerp(WOOD_FOG_OPEN, WOOD_FOG, _in);
}

/// @desc The surface a lit buffer is made of: `[gloss, shininess,
///       translucency, bump]`.
function wood_mat(_m) {
    shader_set_uniform_f(wood_uniforms().u_mat, _m[0], _m[1], _m[2], _m[3]);
}

/// @desc Point the shader's textures at a material: the base texture (stage
///       0, through the submit), its normal map, and a second pair.
function wood_textures(_nmap, _tex2 = -1, _nmap2 = -1) {
    var _u = wood_uniforms();
    texture_set_stage(_u.s_nmap, sprite_get_texture(_nmap, 0));
    gpu_set_texrepeat_ext(_u.s_nmap, true);
    gpu_set_tex_mip_enable_ext(_u.s_nmap, mip_markedonly);
    gpu_set_tex_filter_ext(_u.s_nmap, true);
    if (_tex2 != -1) {
        texture_set_stage(_u.s_tex2, sprite_get_texture(_tex2, 0));
        gpu_set_texrepeat_ext(_u.s_tex2, true);
        gpu_set_tex_mip_enable_ext(_u.s_tex2, mip_markedonly);
        gpu_set_tex_filter_ext(_u.s_tex2, true);
        texture_set_stage(_u.s_nmap2, sprite_get_texture(_nmap2, 0));
        gpu_set_texrepeat_ext(_u.s_nmap2, true);
        gpu_set_tex_mip_enable_ext(_u.s_nmap2, mip_markedonly);
        gpu_set_tex_filter_ext(_u.s_nmap2, true);
    }
}

/// @desc The camera's view matrix.
function wood_view(_b) {
    var _fx = dsin(_b.yaw) * dcos(_b.pitch);
    var _fy = dsin(_b.pitch);
    var _fz = dcos(_b.yaw) * dcos(_b.pitch);
    return matrix_build_lookat(_b.cam_x, _b.cam_y, _b.cam_z,
                               _b.cam_x + _fx * 100, _b.cam_y + _fy * 100,
                               _b.cam_z + _fz * 100, 0, 1, 0);
}

/// @desc Draw the wood into its surface, then finish it into the field (or
///       the whole screen with `_fill`).
function wood_draw_back(_b, _fill) {
    var _w = _fill ? GAME_W : FIELD_W;
    var _h = _fill ? GAME_H : FIELD_H;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;

    var _old_w = matrix_get(matrix_world);
    var _old_v = matrix_get(matrix_view);
    var _old_p = matrix_get(matrix_projection);
    var _st_cull = gpu_get_cullmode();
    var _st_filt = gpu_get_texfilter();
    var _st_zt = gpu_get_ztestenable();
    var _st_zw = gpu_get_zwriteenable();
    var _st_mip = gpu_get_tex_mip_enable();
    var _st_mipf = gpu_get_tex_mip_filter();
    var _st_aniso = gpu_get_tex_max_aniso();
    var _st_rep = gpu_get_texrepeat();
    var _st_blend = gpu_get_blendenable();

    wood_light_frame(_b);
    wood_gather(_b);
    wood_draw_shadow(_b);

    _b.surf = wood_surface(_b.surf, _w, _h, surface_rgba16float, true);
    surface_set_target(_b.surf);
    draw_clear_alpha(c_black, 1);

    matrix_set(matrix_view, wood_view(_b));
    matrix_set(matrix_projection, matrix_build_projection_perspective_fov(
        WOOD_FOV, _w / _h, WOOD_ZNEAR, WOOD_ZFAR));

    gpu_set_cullmode(cull_noculling);
    gpu_set_texfilter(true);
    gpu_set_tex_mip_enable(mip_markedonly);
    gpu_set_tex_mip_filter(tf_anisotropic);
    gpu_set_tex_max_aniso(8);
    gpu_set_texrepeat(true);
    gpu_set_blendenable(true);

    wood_draw_sky(_b);

    // The ground, then the trees far to near.
    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(true);
    gpu_set_blendmode(bm_normal);
    wood_shader(_b);
    var _u = wood_uniforms();
    wood_floor(1);
    wood_mat(WOOD_MAT_GROUND);
    wood_textures(spr_wood_floor_n, spr_wood_path, spr_wood_path_n);
    var _t0 = floor((_b.cam_z - WOOD_BEHIND) / WOOD_TILE_Z);
    var _t1 = floor((_b.cam_z + WOOD_FAR) / WOOD_TILE_Z);
    var _gt = sprite_get_texture(spr_wood_floor, 0);
    for (var _k = _t0; _k <= _t1; _k++) {
        matrix_set(matrix_world, matrix_build(0, 0, _k * WOOD_TILE_Z,
                                              0, 0, 0, 1, 1, 1));
        vertex_submit(_b.vb_ground, pr_trianglestrip, _gt);
    }
    wood_floor(0);

    wood_mat(WOOD_MAT_BARK);
    wood_textures(spr_wood_bark_n);
    var _bt = sprite_get_texture(spr_wood_bark, 0);
    for (var _i = 0; _i < _b.seen_n; _i++) {
        var _tr = _b.seen[_i];
        matrix_set(matrix_world, _tr.mat);
        var _vb = (_tr.d2 > WOOD_LOD_D2) ? _b.trees_far[_tr.mesh]
                                         : _b.trees[_tr.mesh];
        if (_vb != -1) vertex_submit(_vb, pr_trianglestrip, _bt);
    }

    wood_draw_charms(_b);
    wood_draw_wisps(_b);

    shader_reset();
    gpu_set_blendmode(bm_normal);
    gpu_set_ztestenable(_st_zt);
    gpu_set_zwriteenable(_st_zw);
    gpu_set_cullmode(_st_cull);
    gpu_set_texfilter(_st_filt);
    gpu_set_tex_mip_enable(_st_mip);
    gpu_set_tex_mip_filter(_st_mipf);
    gpu_set_tex_max_aniso(_st_aniso);
    gpu_set_texrepeat(_st_rep);
    gpu_set_blendenable(_st_blend);
    matrix_set(matrix_world, matrix_build_identity());
    matrix_set(matrix_view, _old_v);
    matrix_set(matrix_projection, _old_p);
    surface_reset_target();

    matrix_set(matrix_world, _old_w);
    wood_post(_b, _x0, _y0, _w, _h);
}

/// @desc The charms in view, each under its own swing, its glowing parts lit
///       with its light (`wood_charm_light`). They are placed whole, so the
///       shader doesn't stand them on the ground.
function wood_draw_charms(_b) {
    if (_b.charm_n <= 0) return;
    var _u = wood_uniforms();
    shader_set_uniform_f(_u.u_raise, 0);
    wood_mat(WOOD_MAT_CHARM);
    wood_textures(spr_wood_flat_n);
    var _tex = sprite_get_texture(spr_wood_charm, 0);
    for (var _i = 0; _i < _b.charm_n; _i++) {
        var _c = _b.charm_seen[_i];
        var _vb = _b.charms[_c.kind];
        if (_vb == -1) continue;
        var _rgb = wood_charm_light(_b, _c);
        shader_set_uniform_f(_u.u_glowcol, _rgb[0] * WOOD_CHARM_GLOW,
                             _rgb[1] * WOOD_CHARM_GLOW, _rgb[2] * WOOD_CHARM_GLOW);
        matrix_set(matrix_world, _c.mat);
        vertex_submit(_vb, pr_trianglelist, _tex);
    }
    shader_set_uniform_f(_u.u_glowcol, 1, 1, 1);
    shader_set_uniform_f(_u.u_raise, 1);
}

/// @desc The wisps' glows: a wide halo, a bright core, and a trail of fading
///       motes behind each, as cards facing the camera, added to the wood
///       (depth-tested against it, not written). Rebuilt every frame.
function wood_draw_wisps(_b) {
    var _vb = _b.vb_wisp;
    var _rx = dcos(_b.yaw), _rz = -dsin(_b.yaw);
    var _any = false;
    vertex_begin(_vb, wood_format());
    for (var _i = 0; _i < WOOD_WISPS; _i++) {
        var _w = _b.wisps[_i];
        if (_w[3] <= 0.01) continue;
        _any = true;
        var _bl = wood_blood_at(_b, _w[2] - _b.cam_z);
        var _col = merge_colour(WOOD_WISP_COL_N, WOOD_WISP_COL_B, _bl);
        var _sz = WOOD_WISP_SIZE;
        wood_glow_card(_vb, _w[0], _w[1], _w[2], _rx, _rz, _sz * 7, _col, 0.16 * _w[3]);
        wood_glow_card(_vb, _w[0], _w[1], _w[2], _rx, _rz, _sz * 2.2, _col, 0.55 * _w[3]);
        wood_glow_card(_vb, _w[0], _w[1], _w[2], _rx, _rz, _sz * 0.8, c_white, 0.9 * _w[3]);
        // The trail: where its wandering had it a moment ago.
        for (var _k = 1; _k <= 6; _k++) {
            var _tt = _b.t - _k * 5;
            var _ox = wood_wisp_wander(_tt, _i, 0) - wood_wisp_wander(_b.t, _i, 0);
            var _oy = wood_wisp_wander(_tt, _i, 1) - wood_wisp_wander(_b.t, _i, 1);
            var _oz = wood_wisp_wander(_tt, _i, 2) - wood_wisp_wander(_b.t, _i, 2);
            var _f = 1 - _k / 7;
            wood_glow_card(_vb, _w[0] + _ox, _w[1] + _oy, _w[2] + _oz, _rx, _rz,
                           _sz * (0.9 * _f + 0.3), _col, 0.35 * _f * _w[3]);
        }
    }
    vertex_end(_vb);
    if (!_any) return;

    shader_set(sh_wood_sky);
    shader_set_uniform_f(shader_get_uniform(sh_wood_sky, "u_mode"), 3);
    shader_set_uniform_f(shader_get_uniform(sh_wood_sky, "u_amount"), 1);
    gpu_set_blendmode(bm_add);
    gpu_set_zwriteenable(false);
    matrix_set(matrix_world, matrix_build_identity());
    vertex_submit(_vb, pr_trianglelist, sprite_get_texture(spr_wood_glow, 0));
    gpu_set_zwriteenable(true);
    gpu_set_blendmode(bm_normal);
    wood_shader(_b);
}

/// @desc One glow card facing the camera (whose right is `(_rx, 0, _rz)`;
///       it hardly pitches, so up is up), as six vertices.
function wood_glow_card(_vb, _x, _y, _z, _rx, _rz, _r, _col, _a) {
    var _c = [[-1, 1, 0, 0], [1, 1, 1, 0], [1, -1, 1, 1],
              [-1, 1, 0, 0], [1, -1, 1, 1], [-1, -1, 0, 1]];
    for (var _k = 0; _k < 6; _k++) {
        var _sx = _c[_k][0] * _r, _sy = _c[_k][1] * _r;
        wood_vertex(_vb, _x + _rx * _sx, _y + _sy, _z + _rz * _sx, 0, 0, -1,
                    _col, _a, _c[_k][2], _c[_k][3], 0, 0, 0, 0);
    }
}

/// @desc Draw the sky: the world matrix is the camera's position, and the
///       depth buffer is neither tested nor written (the sky is behind
///       everything, and the depth left at its clear value marks open sky
///       for the rays, `wood_post`).
function wood_draw_sky(_b) {
    gpu_set_ztestenable(false);
    gpu_set_zwriteenable(false);
    var _l = wood_light_state();
    var _sh = sh_wood_sky;
    shader_set(_sh);
    var _u = function(_n) { return shader_get_uniform(sh_wood_sky, _n); };
    shader_set_uniform_f(_u("u_time"), _b.t);
    shader_set_uniform_f(_u("u_bl"), _l.sb);
    shader_set_uniform_f(_u("u_light"), _l.light);
    wood_u3(_u("u_moon_vis"), _l.moon_vis);
    wood_u3(_u("u_hor_a"), WOOD_HOR_N);
    wood_u3(_u("u_hor_b"), WOOD_HOR_B);
    wood_u3(_u("u_zen_a"), WOOD_ZEN_N);
    wood_u3(_u("u_zen_b"), WOOD_ZEN_B);
    wood_u3(_u("u_haze_a"), WOOD_HAZE_N);
    wood_u3(_u("u_haze_b"), WOOD_HAZE_B);

    var _cam = matrix_build(_b.cam_x, _b.cam_y, _b.cam_z, 0, 0, 0, 1, 1, 1);
    matrix_set(matrix_world, _cam);
    gpu_set_blendmode(bm_normal);
    shader_set_uniform_f(_u("u_mode"), 0);
    vertex_submit(_b.vb_dome, pr_trianglelist, -1);

    // Stars, gone with the eclipse.
    var _stars = (1 - wood_eclipse(_b)) * (1 - _l.sb);
    if (_stars > 0.01) {
        gpu_set_blendmode(bm_add);
        shader_set_uniform_f(_u("u_mode"), 1);
        shader_set_uniform_f(_u("u_amount"), _stars);
        vertex_submit(_b.vb_stars, pr_trianglelist,
                      sprite_get_texture(spr_wood_star, 0));
    }

    // The corona, then the moon over it.
    var _mc = merge_colour(WOOD_MOON_FACE_N, WOOD_MOON_FACE_B, _l.sb);
    var _tot = wood_totality(_b);
    gpu_set_blendmode(bm_add);
    shader_set_uniform_f(_u("u_mode"), 3);
    shader_set_uniform_f(_u("u_amount"), (0.55 + 0.45 * _l.sb) * (1 - _tot * 0.85));
    vertex_submit(_b.vb_corona, pr_trianglelist,
                  sprite_get_texture(spr_wood_glow, 0));
    gpu_set_blendmode(bm_normal);
    shader_set_uniform_f(_u("u_mode"), 2);
    wood_u3(_u("u_moon_col"), wood_rgb(_mc, WOOD_MOON_BRIGHT));
    var _ecl = wood_eclipse(_b);
    var _on = (_ecl > 0 && _ecl < 1) ? 1 : 0;
    shader_set_uniform_f(_u("u_ecl"), (_ecl * 2 - 1) * 2.4, 0, 1.06, _on * 0.96);
    wood_u3(_u("u_umbra"), wood_rgb(WOOD_UMBRA_COL));
    vertex_submit(_b.vb_moon, pr_trianglelist,
                  sprite_get_texture(spr_wood_moon, 0));

    // At totality, a thin rim of red light round the shadow; then, as the
    // moon comes out red, a ring leaving it.
    gpu_set_blendmode(bm_add);
    shader_set_uniform_f(_u("u_mode"), 3);
    var _rim = wood_rgb(merge_colour(WOOD_MOON_FACE_N, WOOD_MOON_FACE_B, 0.8));
    if (_tot > 0.01) {
        matrix_set(matrix_world, _cam);
        shader_set_uniform_f(_u("u_amount"), _tot * 0.85);
        vertex_submit(_b.vb_rim, pr_trianglelist,
                      sprite_get_texture(spr_wood_ring, 0));
    }
    var _w = wood_wave_t(_b);
    if (_w > 0 && _w < 0.62) {
        var _p = _w / 0.62;
        var _sc = 1 + _p * 9;
        // Scaled about the moon's direction: the ring card sits on it.
        var _md = _l.moon_vis;
        var _dist = WOOD_SKY_R * 0.92;
        var _cx = _md[0] * _dist, _cy = _md[1] * _dist, _cz = _md[2] * _dist;
        matrix_set(matrix_world, matrix_multiply(matrix_multiply(
            matrix_build(-_cx, -_cy, -_cz, 0, 0, 0, 1, 1, 1),
            matrix_build(_cx, _cy, _cz, 0, 0, 0, _sc, _sc, 1)), _cam));
        shader_set_uniform_f(_u("u_amount"), (1 - _p) * 0.75);
        vertex_submit(_b.vb_rim, pr_trianglelist,
                      sprite_get_texture(spr_wood_ring, 0));
        matrix_set(matrix_world, _cam);
    }
    gpu_set_blendmode(bm_normal);

    // The clouds, turning slowly round the sky.
    shader_set_uniform_f(_u("u_mode"), 4);
    matrix_set(matrix_world, matrix_multiply(
        matrix_build(0, 0, 0, 0, (_b.t * WOOD_CLOUD_SPIN) mod 360, 0, 1, 1, 1),
        _cam));
    vertex_submit(_b.vb_cloud, pr_trianglelist,
                  sprite_get_texture(spr_wood_cloud, 0));
    gpu_set_blendmode(bm_normal);
}

/// @desc The moon's shadow map: the trees near enough to throw a shadow
///       into view, drawn from the moonlight's side into a float surface as
///       depth along it (`sh_wood_shadow`). The box follows the camera,
///       snapped to whole texels so the shadows don't crawl as it moves.
function wood_draw_shadow(_b) {
    var _l = wood_light_state();
    var _L = _l.moon;
    var _size = WOOD_SHADOW_SIZE;
    _b.shadow = wood_surface(_b.shadow, _size, _size, surface_r32float, true);

    // The box's centre: ahead of the camera, on the ground.
    var _fx = dsin(_b.yaw), _fz = dcos(_b.yaw);
    var _cx = _b.cam_x + _fx * WOOD_SHADOW_AHEAD;
    var _cz = _b.cam_z + _fz * WOOD_SHADOW_AHEAD;
    var _cy = 0;
    // The light's frame: right and up across it.
    var _rx = _L[2], _ry = 0, _rz = -_L[0];
    var _rl = max(0.0001, sqrt(_rx * _rx + _rz * _rz));
    _rx /= _rl; _rz /= _rl;
    var _ux = _L[1] * _rz - _L[2] * _ry;
    var _uy = _L[2] * _rx - _L[0] * _rz;
    var _uz = _L[0] * _ry - _L[1] * _rx;
    // Snap the centre to whole texels across the light.
    var _tx = WOOD_SHADOW_W / _size;
    var _a = _cx * _rx + _cy * _ry + _cz * _rz;
    var _c = _cx * _ux + _cy * _uy + _cz * _uz;
    var _sa = round(_a / _tx) * _tx - _a;
    var _sc = round(_c / _tx) * _tx - _c;
    _cx += _rx * _sa + _ux * _sc;
    _cy += _ry * _sa + _uy * _sc;
    _cz += _rz * _sa + _uz * _sc;

    var _back = WOOD_SHADOW_RANGE * 0.5;
    var _ex = _cx + _L[0] * _back;
    var _ey = _cy + _L[1] * _back;
    var _ez = _cz + _L[2] * _back;
    var _view = matrix_build_lookat(_ex, _ey, _ez, _cx, _cy, _cz,
                                    _ux, _uy, _uz);
    var _proj = matrix_build_projection_ortho(WOOD_SHADOW_W, WOOD_SHADOW_W,
                                              1, WOOD_SHADOW_RANGE);
    _b.shadow_vp = matrix_multiply(_view, _proj);
    _b.shadow_org = [_ex, _ey, _ez];
    _b.shadow_dir = [-_L[0], -_L[1], -_L[2]];

    surface_set_target(_b.shadow);
    draw_clear_alpha(c_white, 1);
    matrix_set(matrix_view, _view);
    matrix_set(matrix_projection, _proj);
    gpu_set_blendenable(false);
    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(true);
    gpu_set_cullmode(cull_noculling);
    shader_set(sh_wood_shadow);
    var _u = function(_n) { return shader_get_uniform(sh_wood_shadow, _n); };
    shader_set_uniform_f(_u("u_time"), _b.t mod 100000);
    var _wd = WOOD_WIND_DIR;
    shader_set_uniform_f(_u("u_wind"), WOOD_WIND, 1, _wd[0], _wd[1]);
    shader_set_uniform_f(_u("u_lorg"), _ex, _ey, _ez);
    shader_set_uniform_f(_u("u_ldir"), -_L[0], -_L[1], -_L[2]);
    shader_set_uniform_f(_u("u_lrange"), WOOD_SHADOW_RANGE);
    wood_lane(_u("u_lane"));

    // Every tree within reach casts, in view or not (a tree beside the
    // frame throws its shadow into it); the far mesh is enough for that.
    var _reach2 = sqr(WOOD_SHADOW_REACH + 600);
    var _rows = _b.rows;
    for (var _r = 0; _r < array_length(_rows); _r++) {
        var _row = _rows[_r];
        for (var _i = 0; _i < _row.n; _i++) {
            var _slot = _row.cache[_i];
            var _tr = _slot.trees;
            for (var _k = 0; _k < array_length(_tr); _k++) {
                var _t = _tr[_k];
                var _dz = _t.z - _b.cam_z;
                if (_dz < -WOOD_BEHIND || _dz > WOOD_SHADOW_REACH + 400) continue;
                if (sqr(_t.x - _b.cam_x) + sqr(_dz) > _reach2) continue;
                var _vb = _b.trees_far[_t.mesh];
                if (_vb == -1) continue;
                matrix_set(matrix_world, _t.mat);
                vertex_submit(_vb, pr_trianglestrip, -1);
            }
        }
    }
    shader_reset();
    gpu_set_blendenable(true);
    matrix_set(matrix_world, matrix_build_identity());
    surface_reset_target();
}

// ---------------------------------------------------------------------------
// The post-process (`sh_wood_post`)
// ---------------------------------------------------------------------------

/// @desc Finish the wood into the field: the bright pass and its bloom, the
///       moon's rays, then the wood put together with both.
function wood_post(_b, _x0, _y0, _w, _h) {
    var _qw = max(8, _w div 4);
    var _qh = max(8, _h div 4);
    _b.bloom_a = wood_surface(_b.bloom_a, _qw, _qh, surface_rgba16float);
    _b.bloom_b = wood_surface(_b.bloom_b, _qw, _qh, surface_rgba16float);
    _b.ray_a = wood_surface(_b.ray_a, _qw, _qh, surface_rgba16float);
    _b.ray_b = wood_surface(_b.ray_b, _qw, _qh, surface_rgba16float);

    var _wm = matrix_get(matrix_world);
    matrix_set(matrix_world, matrix_build_identity());
    var _st_filt = gpu_get_texfilter();
    gpu_set_texfilter(true);
    gpu_set_blendmode(bm_normal);
    gpu_set_blendenable(false);
    var _sh = sh_wood_post;
    shader_set(_sh);
    var _mode = shader_get_uniform(_sh, "u_mode");
    var _texel = shader_get_uniform(_sh, "u_texel");
    var _dir = shader_get_uniform(_sh, "u_dir");
    var _l = wood_light_state();

    // The bright pass, at a quarter size.
    surface_set_target(_b.bloom_a);
    shader_set_uniform_f(_mode, 0);
    shader_set_uniform_f(_texel, 1 / _w, 1 / _h);
    shader_set_uniform_f(shader_get_uniform(_sh, "u_thresh"), WOOD_BLOOM_THRESH);
    draw_surface_stretched(_b.surf, 0, 0, _qw, _qh);
    surface_reset_target();
    // Two blurs, each across then down, the second twice as wide.
    shader_set_uniform_f(_mode, 1);
    for (var _k = 1; _k <= 2; _k++) {
        surface_set_target(_b.bloom_b);
        shader_set_uniform_f(_dir, _k / _qw, 0);
        draw_surface(_b.bloom_a, 0, 0);
        surface_reset_target();
        surface_set_target(_b.bloom_a);
        shader_set_uniform_f(_dir, 0, _k / _qh);
        draw_surface(_b.bloom_b, 0, 0);
        surface_reset_target();
    }

    // The rays: the open sky's light, smeared out from the moon.
    var _sun = wood_moon_screen(_b, _w, _h);
    var _rayp = shader_get_uniform(_sh, "u_rayp");
    var _rk = WOOD_RAYS * (1 - wood_totality(_b)) * (0.6 + 0.4 * _l.light / WOOD_NIGHT_LIGHT);
    surface_set_target(_b.ray_a);
    shader_set_uniform_f(_mode, 4);
    shader_set_uniform_f(_texel, 1 / _w, 1 / _h);
    shader_set_uniform_f(_rayp, WOOD_RAY_LEN, WOOD_RAY_DECAY, _rk, WOOD_RAY_FLOOR);
    var _sd = shader_get_sampler_index(_sh, "u_depth");
    texture_set_stage(_sd, surface_get_texture_depth(_b.surf));
    draw_surface_stretched(_b.surf, 0, 0, _qw, _qh);
    surface_reset_target();
    shader_set_uniform_f(_mode, 2);
    shader_set_uniform_f(shader_get_uniform(_sh, "u_sun"), _sun[0], _sun[1]);
    surface_set_target(_b.ray_b);
    draw_surface(_b.ray_a, 0, 0);
    surface_reset_target();

    // The wood, put together.
    matrix_set(matrix_world, _wm);
    shader_set_uniform_f(_mode, 3);
    texture_set_stage(shader_get_sampler_index(_sh, "u_bloom"),
                      surface_get_texture(_b.bloom_a));
    texture_set_stage(shader_get_sampler_index(_sh, "u_rays"),
                      surface_get_texture(_b.ray_b));
    shader_set_uniform_f(shader_get_uniform(_sh, "u_bloom_k"), WOOD_BLOOM_A);
    var _rc = merge_colour(WOOD_RAY_COL_N, WOOD_RAY_COL_B, _l.sb);
    wood_u3(shader_get_uniform(_sh, "u_raycol"), wood_rgb(_rc));
    shader_set_uniform_f(_rayp, WOOD_RAY_LEN, WOOD_RAY_DECAY, _rk, WOOD_RAY_FLOOR);
    shader_set_uniform_f(shader_get_uniform(_sh, "u_vignette"), WOOD_VIGNETTE);
    wood_u3(shader_get_uniform(_sh, "u_lift"), WOOD_LIFT);
    wood_u3(shader_get_uniform(_sh, "u_gain"), [1, 1, 1]);
    // The red flash as the moon turns (the first moment of the ring).
    var _wt = wood_wave_t(_b) / 0.62;
    var _fl = (_wt > 0 && _wt < 0.14) ? (1 - _wt / 0.14) * 0.22 : 0;
    var _fc = wood_rgb(WOOD_MOON_FACE_B);
    shader_set_uniform_f(shader_get_uniform(_sh, "u_flash"), _fc[0], _fc[1], _fc[2], _fl);
    draw_surface(_b.surf, _x0, _y0);
    shader_reset();
    gpu_set_blendenable(true);
    gpu_set_texfilter(_st_filt);
}

/// @desc Where the moon is on screen, 0..1 across and down the view.
function wood_moon_screen(_b, _w, _h) {
    var _d = wood_moon_vis();
    // Into the camera's frame: yaw, then pitch.
    var _cy = dcos(_b.yaw), _sy = dsin(_b.yaw);
    var _x = _d[0] * _cy - _d[2] * _sy;
    var _z = _d[0] * _sy + _d[2] * _cy;
    var _cp = dcos(_b.pitch), _sp = dsin(_b.pitch);
    var _y = _d[1] * _cp - _z * _sp;
    _z = _d[1] * _sp + _z * _cp;
    var _f = 0.5 / dtan(WOOD_FOV * 0.5);
    _z = max(_z, 0.05);
    return [0.5 + _x / _z * _f * (_h / _w), 0.5 - _y / _z * _f];
}

/// @desc The pass drawn over the field. Nothing yet.
function wood_draw_front(_b, _spell, _fill) {
}
