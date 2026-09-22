/// @desc Stage three's background, the Archives of Bequeathed Memories: a hall
///       drawn in real 3D (a camera, a perspective projection and the GPU's
///       depth buffer), open to a night sky with an orrery hanging in it.
///
/// Real 3D because the stage opens with the camera high above the floor
/// looking down, then rises and levels out (the reveal, driven by `omen`);
/// pointing the camera down is a rotation, which the corridor projection
/// can't do.
///
/// - One bay (floor and both walls, `HALL_BAY_Z` long) is built into frozen
///   vertex buffers and submitted at each bay's offset through the world
///   matrix, so the hall is endless with nothing recycled. There are three bay
///   kinds (shelves, shelves with a ladder, an alcove), chosen per bay index.
/// - Vertex buffers take UVs in texture-page space, so every UV goes through
///   `hall_uv`, which also insets half a texel.
/// - `vertex_submit` takes one texture, so each buffer only holds geometry
///   from one sprite frame (`check_hall_frame_textures`,
///   `check_hall_buffer_textures`).
/// - Lighting is baked into vertex colours. Light sources are a second,
///   additive pass (depth-tested, not depth-written).
/// - `sh_hall` does distance fog and fades far geometry out by alpha.
/// - Every GPU state changed here is restored afterwards.

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// @desc Build the hall background.
function bg_sanctum() {
    // The base struct's parallax sprite slots are unused here; they point at
    // existing hall sprites because a reference to a deleted asset compiles as
    // a variable read and throws at run time.
    var _b = bg_new(spr_hall_floor, spr_hall_stone, spr_hall_pale,
                    HALL_FOG, HALL_SPEED);
    _b.kind = BGKIND_SANCTUM;

    // This background draws through its own entry points.
    _b.f_step = hall_step;
    _b.f_back = hall_draw_back;
    _b.f_front = hall_draw_front;

    _b.t = 0;
    _b.dist = 0;          // how far down the hall the camera has flown
    _b.spd = HALL_SPEED;
    _b.rush = HALL_SPEED;

    // The reveal (eased from `omen`): 0 is phase A, high above the floor and
    // aimed down at it; 1 is phase B, at flying height and level.
    _b.reveal = 0;

    // The opening: 0 is a dark, nearly still hall; 1 is under way. Drives both
    // the lights coming up and the flight speed.
    _b.intro = 0;

    _b.cam_x = 0;
    _b.cam_y = HALL_CAM_HIGH;
    _b.pitch = HALL_PITCH_A;
    _b.lean = 0;
    _b.surf = -1;

    hall_build(_b);
    return _b;
}

/// @desc A stable pseudo-random number in [0, 1) from two integers (`frac`
///       keeps its sign in GML, hence the fold). Used instead of `random` so
///       the hall is the same on every attempt.
function hall_hash(_a, _b) {
    var _v = sin(_a * 127.1 + _b * 311.7) * 43758.5453;
    _v = frac(_v);
    return (_v < 0) ? _v + 1 : _v;
}

/// @desc Which kind of bay this is: 0 shelves, 1 shelves with a ladder, 2 an
///       alcove. The alcove is every `HALL_ALCOVE_EVERY` bays at a fixed
///       position (hashing it per bay clumped badly, since `hall_hash` is
///       correlated across consecutive integers); the hash only picks between
///       the two shelf kinds.
function hall_bay_kind(_i) {
    var _m = ((_i % HALL_ALCOVE_EVERY) + HALL_ALCOVE_EVERY) % HALL_ALCOVE_EVERY;
    if (_m == HALL_ALCOVE_AT) return 2;
    return (hall_hash(_i, 3) < 0.5) ? 0 : 1;
}

/// @desc A sprite frame's texture coordinates in page space, for vertex
///       buffers (which, unlike `draw_primitive_begin_texture`, get no remapping
///       from sprite space), inset half a texel from every edge so bilinear
///       sampling doesn't pick up neighbouring art on the page.
function hall_uv(_spr, _frame, _u, _v) {
    var _q = sprite_get_uvs(_spr, _frame);
    var _w = max(1, sprite_get_width(_spr));
    var _h = max(1, sprite_get_height(_spr));
    var _hu = 0.5 / _w * (_q[2] - _q[0]);
    var _hv = 0.5 / _h * (_q[3] - _q[1]);
    return [lerp(_q[0] + _hu, _q[2] - _hu, _u),
            lerp(_q[1] + _hv, _q[3] - _hv, _v)];
}

/// @desc The vertex format everything in the hall is built in.
function hall_format() {
    static _f = undefined;
    if (_f == undefined) {
        vertex_format_begin();
        vertex_format_add_position_3d();
        vertex_format_add_colour();
        vertex_format_add_texcoord();
        _f = vertex_format_end();
    }
    return _f;
}

/// @desc A quad with its sprite stretched across it once, subdivided into an
///       `_nx` by `_ny` grid so the per-vertex light can fall off across it.
///       (Compare `hall_tiles`, which repeats the sprite per cell.)
function hall_quad(_vb, _p0, _p1, _p2, _p3, _spr, _frame, _nx, _ny,
                   _face, _side, _kind, _col = c_white,
                   _lightfn = hall_wall_light) {
    var _order = [0, 1, 2, 0, 2, 3];
    for (var _i = 0; _i < _nx; _i++) {
        for (var _j = 0; _j < _ny; _j++) {
            var _u0 = _i / _nx, _u1 = (_i + 1) / _nx;
            var _v0 = _j / _ny, _v1 = (_j + 1) / _ny;
            var _uu = [[_u0, _v0], [_u1, _v0], [_u1, _v1], [_u0, _v1]];
            var _c = [];
            for (var _k = 0; _k < 4; _k++) {
                _c[_k] = hall_lerp4(_p0, _p1, _p2, _p3, _uu[_k][0],
                                    _uu[_k][1]);
            }
            for (var _k = 0; _k < 6; _k++) {
                var _m = _order[_k];
                var _pt = _c[_m];
                var _l = _face * _lightfn(_pt[0], _pt[1], _pt[2], _side,
                                          _kind);
                var _t = hall_uv(_spr, _frame, _uu[_m][0], _uu[_m][1]);
                vertex_position_3d(_vb, _pt[0], _pt[1], _pt[2]);
                vertex_colour(_vb, hall_shade(_col, _l), 1);
                vertex_texcoord(_vb, _t[0], _t[1]);
            }
        }
    }
}

/// @desc Bilinear interpolation between a quad's four corners.
function hall_lerp4(_p0, _p1, _p2, _p3, _u, _v) {
    var _ax = lerp(_p0[0], _p1[0], _u), _ay = lerp(_p0[1], _p1[1], _u),
        _az = lerp(_p0[2], _p1[2], _u);
    var _bx = lerp(_p3[0], _p2[0], _u), _by = lerp(_p3[1], _p2[1], _u),
        _bz = lerp(_p3[2], _p2[2], _u);
    return [lerp(_ax, _bx, _v), lerp(_ay, _by, _v), lerp(_az, _bz, _v)];
}

/// @desc A colour scaled by a light value (vertex colour multiplies the
///       texture, so this is the lighting model).
function hall_shade(_col, _l) {
    // Not clamped at 1: face factors above 1 are how lit edges are made
    // brighter. Each channel saturates at 255.
    var _k = max(_l, 0);
    return make_colour_rgb(min(255, colour_get_red(_col) * _k),
                           min(255, colour_get_green(_col) * _k),
                           min(255, colour_get_blue(_col) * _k));
}

/// @desc Build the hall's geometry, once, at construction.
function hall_build(_b) {
    // ---- the joinery and the pavement: one set of buffers per bay kind ----
    //
    // Per kind so each kind's floor is lit by its own lights (the alcove's
    // orb lights the floor in front of it). One buffer per texture.
    // The member is `joinery`, not `case`: `case` is a reserved word, which
    // Igor accepts as a struct member name but Feather rejects.
    _b.joinery = [];
    for (var _k = 0; _k < 3; _k++) {
        _b.joinery[_k] = hall_build_case(_k);
    }

    hall_build_props(_b);
    hall_build_instruments(_b);

    hall_build_sky(_b);
    hall_build_orrery(_b);
}

/// @desc Baked light at a point on the joinery, from the bay's sources: the
///       lamp position every bay has, and the orb in an alcove bay. A softened
///       inverse-square falloff over the ambient `HALL_WALL_AMB`.
function hall_wall_light(_x, _y, _z, _side, _kind) {
    var _l = HALL_WALL_AMB;

    var _lx = _side * HALL_LAMP_X;
    var _lz = HALL_BAY_Z * 0.42;
    var _d = point_distance_3d(_x, _y, _z, _lx, HALL_LAMP_Y, _lz);
    _l += HALL_LAMP_POWER / (1 + (_d / HALL_LIGHT_R) * (_d / HALL_LIGHT_R));

    if (_kind == 2) {
        var _od = point_distance_3d(_x, _y, _z, hall_orb_x(_side),
                                    HALL_ORB_Y, HALL_BAY_Z * 0.5);
        _l += HALL_ORB_POWER
              / (1 + (_od / HALL_ORB_LIGHT_R) * (_od / HALL_ORB_LIGHT_R));
    }
    return min(_l, 1.35);
}

/// @desc No falloff (always 1), for geometry built at the origin and placed
///       by a matrix, which has no world position at build time.
function hall_no_light(_x, _y, _z, _side, _kind) {
    return 1;
}

/// @desc The alcove orb's x on the given side. The single source for both
///       the orb's geometry and its light (`test_hall_orb`).
function hall_orb_x(_side) {
    return _side * (HALL_HALF_W + HALL_PIL_D + HALL_ORB_STAND);
}

/// @desc Baked light at a point on the floor, from the lamps and orbs on both
///       sides of the nave.
function hall_floor_light(_x, _y, _z, _side, _kind) {
    var _l = HALL_FLOOR_AMB;
    for (var _s = -1; _s <= 1; _s += 2) {
        var _d = point_distance_3d(_x, _y, _z, _s * HALL_LAMP_X, HALL_LAMP_Y,
                                   HALL_BAY_Z * 0.42);
        _l += HALL_LAMP_POWER * HALL_FLOOR_BOUNCE
              / (1 + (_d / HALL_LIGHT_R) * (_d / HALL_LIGHT_R));
        if (_kind == 2) {
            var _od = point_distance_3d(_x, _y, _z, hall_orb_x(_s),
                                        HALL_ORB_Y, HALL_BAY_Z * 0.5);
            _l += HALL_ORB_POWER * HALL_FLOOR_BOUNCE
                  / (1 + (_od / HALL_ORB_LIGHT_R)
                         * (_od / HALL_ORB_LIGHT_R));
        }
    }
    // Dim the centre of the nave relative to the edges (`HALL_FLOOR_DIM`);
    // the lamps alone light the floor almost evenly.
    var _e = clamp(abs(_x) / HALL_HALF_W, 0, 1);
    _l *= HALL_FLOOR_DIM + (1 - HALL_FLOOR_DIM) * power(_e, 1.6);
    return min(_l * HALL_FLOOR_LIGHT, 1.25);
}

/// @desc A surface tiled `_nu` by `_nv` times, lit per vertex. Each cell takes
///       the whole sprite (texture repeat isn't available on an atlas).
///       `_face` is an orientation factor on the light (e.g. a board's top vs
///       its underside); `_lightfn` is the light model (`hall_wall_light`, or
///       `hall_floor_light` for flat surfaces).
function hall_tiles(_vb, _p0, _p1, _p2, _p3, _spr, _frame, _nu, _nv,
                    _face, _side, _kind, _col = c_white,
                    _lightfn = hall_wall_light) {
    var _q0 = hall_uv(_spr, _frame, 0, 0);
    var _q1 = hall_uv(_spr, _frame, 1, 0);
    var _q2 = hall_uv(_spr, _frame, 1, 1);
    var _q3 = hall_uv(_spr, _frame, 0, 1);
    var _uv = [_q0, _q1, _q2, _q3];
    var _order = [0, 1, 2, 0, 2, 3];

    for (var _i = 0; _i < _nu; _i++) {
        for (var _j = 0; _j < _nv; _j++) {
            var _u0 = _i / _nu, _u1 = (_i + 1) / _nu;
            var _v0 = _j / _nv, _v1 = (_j + 1) / _nv;
            var _c = [hall_lerp4(_p0, _p1, _p2, _p3, _u0, _v0),
                      hall_lerp4(_p0, _p1, _p2, _p3, _u1, _v0),
                      hall_lerp4(_p0, _p1, _p2, _p3, _u1, _v1),
                      hall_lerp4(_p0, _p1, _p2, _p3, _u0, _v1)];
            for (var _k = 0; _k < 6; _k++) {
                var _m = _order[_k];
                var _pt = _c[_m];
                var _l = _face * _lightfn(_pt[0], _pt[1], _pt[2],
                                          _side, _kind);
                vertex_position_3d(_vb, _pt[0], _pt[1], _pt[2]);
                vertex_colour(_vb, hall_shade(_col, _l), 1);
                vertex_texcoord(_vb, _uv[_m][0], _uv[_m][1]);
            }
        }
    }
}

/// @desc One bay of floor: a runner down the middle, sunk by
///       `HALL_FLOOR_STEP` with gilt step faces along its edges; a border
///       course either side; marble out to the walls; and a threshold band
///       across the raised floor at the bay joint (the runner passes under it
///       unbroken).
function hall_floor_bay(_o, _kind) {
    var _bz = HALL_BAY_Z;
    var _hw = HALL_HALF_W;
    var _r = HALL_RUNNER_HW;
    var _st = HALL_FLOOR_STEP;
    var _b0 = _r + HALL_BORDER_W;        // where the marble field begins
    var _tz = HALL_THRESH_W;             // the threshold's depth along the bay

    // --- the runner: one piece of art a bay long ---------------------------
    // Wound so the tile's top is the far edge (so its motifs are upright to
    // the camera flying up the hall).
    hall_quad(_o.runner,
              [-_r, -_st, _bz], [_r, -_st, _bz],
              [_r, -_st, 0], [-_r, -_st, 0],
              spr_hall_runner, 0, 8, 10, 1.0, 1, _kind, c_white,
              hall_floor_light);

    for (var _s = -1; _s <= 1; _s += 2) {
        // --- the step, faced in gilt (bright) -----------------------------
        hall_tiles(_o.gilt,
                   [_s * _r, 0, 0], [_s * _r, 0, _bz],
                   [_s * _r, -_st, _bz], [_s * _r, -_st, 0],
                   spr_hall_pale, 0, 6, 1, 1.30, _s, _kind, HALL_GILT,
                   hall_floor_light);

        // --- the border course, along the hall ----------------------------
        for (var _j = 0; _j < HALL_BORDER_NZ; _j++) {
            var _z0 = _tz + (_bz - _tz) * _j / HALL_BORDER_NZ;
            var _z1 = _tz + (_bz - _tz) * (_j + 1) / HALL_BORDER_NZ;
            hall_quad(_o.border,
                      [_s * _r, 0, _z1], [_s * _b0, 0, _z1],
                      [_s * _b0, 0, _z0], [_s * _r, 0, _z0],
                      spr_hall_border, 0, 1, 3, 1.0, _s, _kind, c_white,
                      hall_floor_light);
        }

        // --- the marble field, out where the furniture stands -------------
        for (var _i = 0; _i < HALL_AISLE_NX; _i++) {
            var _x0 = _b0 + (_hw - _b0) * _i / HALL_AISLE_NX;
            var _x1 = _b0 + (_hw - _b0) * (_i + 1) / HALL_AISLE_NX;
            for (var _j = 0; _j < HALL_AISLE_NZ; _j++) {
                var _z0 = _tz + (_bz - _tz) * _j / HALL_AISLE_NZ;
                var _z1 = _tz + (_bz - _tz) * (_j + 1) / HALL_AISLE_NZ;
                hall_quad(_o.marble,
                          [_s * _x0, 0, _z1], [_s * _x1, 0, _z1],
                          [_s * _x1, 0, _z0], [_s * _x0, 0, _z0],
                          spr_hall_floor, 0, 2, 2, 1.0, _s, _kind, c_white,
                          hall_floor_light);
            }
        }

        // --- the threshold, across the aisle at the bay's joint -----------
        // The border frieze turned through a right angle.
        for (var _i = 0; _i < HALL_THRESH_NX; _i++) {
            var _x0 = _r + (_hw - _r) * _i / HALL_THRESH_NX;
            var _x1 = _r + (_hw - _r) * (_i + 1) / HALL_THRESH_NX;
            hall_quad(_o.border,
                      [_s * _x0, 0, _tz], [_s * _x0, 0, 0],
                      [_s * _x1, 0, 0], [_s * _x1, 0, _tz],
                      spr_hall_border, 0, 1, 3, 1.06, _s, _kind, c_white,
                      hall_floor_light);
        }
    }
}

/// @desc One side of one bay, built as real geometry. Outward from the nave: a
///       pilaster, the case front behind it, the recess with books at the back
///       (or, in an alcove bay, a deep recess with the orb on a pedestal), a
///       cornice and plinth projecting past the pilaster, and on top a coping,
///       a parapet and an obelisk (or a brazier on alcove bays).
function hall_case_side(_o, _s, _kind) {
    var _bz = HALL_BAY_Z;
    var _pw = HALL_PIL_W * 0.5;
    var _x_pil = _s * HALL_HALF_W;
    var _x_case = _s * (HALL_HALF_W + HALL_PIL_D);
    var _deep = (_kind == 2) ? HALL_ALCOVE_D : HALL_CASE_D;
    var _x_back = _s * (HALL_HALF_W + HALL_PIL_D + _deep);
    var _x_corn = _s * (HALL_HALF_W - HALL_CORN_D);
    var _x_plin = _s * (HALL_HALF_W - HALL_PLINTH_D);

    var _z0 = _pw;                 // the case opening, between pilasters
    var _z1 = _bz - _pw;
    var _y0 = HALL_PLINTH_H;
    var _y1 = HALL_CASE_TOP;

    // --- the pilaster: a textured face and two stone returns -----------------
    hall_tiles(_o.pil, [_x_pil, HALL_CEIL_H, -_pw], [_x_pil, HALL_CEIL_H, _pw],
               [_x_pil, 0, _pw], [_x_pil, 0, -_pw],
               spr_hall_pil, 0, 1, 1, 1.00, _s, _kind);
    for (var _e = -1; _e <= 1; _e += 2) {
        var _zz = _e * _pw;
        hall_tiles(_o.stone,
                   [_x_pil, HALL_CEIL_H, _zz], [_x_case, HALL_CEIL_H, _zz],
                   [_x_case, 0, _zz], [_x_pil, 0, _zz],
                   spr_hall_stone, 0, 1, 6, 0.46, _s, _kind);
    }
    // Returns at both ends of the case opening.
    for (var _e = 0; _e <= 1; _e++) {
        var _zz = (_e == 0) ? _z0 : _z1;
        hall_tiles(_o.stone,
                   [_x_case, _y1, _zz], [_x_back, _y1, _zz],
                   [_x_back, _y0, _zz], [_x_case, _y0, _zz],
                   spr_hall_stone, 0, 1, 3, 0.40, _s, _kind);
    }

    if (_kind == 2) {
        // --- the alcove: a deep recess with a stone back wall ---------------
        hall_tiles(_o.stone, [_x_back, _y1, _z0], [_x_back, _y1, _z1],
                   [_x_back, _y0, _z1], [_x_back, _y0, _z0],
                   spr_hall_stone, 0, 3, 4, 0.62, _s, _kind);
        // the head and the sill of the recess
        hall_tiles(_o.stone, [_x_case, _y1, _z0], [_x_back, _y1, _z0],
                   [_x_back, _y1, _z1], [_x_case, _y1, _z1],
                   spr_hall_stone, 0, 2, 2, 0.28, _s, _kind);
        hall_tiles(_o.stone, [_x_case, _y0, _z1], [_x_back, _y0, _z1],
                   [_x_back, _y0, _z0], [_x_case, _y0, _z0],
                   spr_hall_stone, 0, 2, 2, 0.80, _s, _kind);
        // --- the pedestal, and the orb standing on it ---------------------
        //
        // A tapered shaft on the recess's sill, a moulding, a gilt cup, and
        // the orb resting in the cup. Each height is derived from the one
        // above, so the orb always sits in the cup.
        var _ox = hall_orb_x(_s);
        var _cup_y = HALL_ORB_Y - HALL_ORB_R;        // where the orb rests
        var _cap_y = _cup_y - HALL_ORB_CRADLE;       // the head of the shaft
        var _cz = _bz * 0.5;

        hall_taper(_o.stone, _ox, _cz, _y0, _cap_y - 12,
                   HALL_ORB_R * 0.74, HALL_ORB_R * 0.74,
                   HALL_ORB_R * 0.56, HALL_ORB_R * 0.56,
                   spr_hall_stone, 0, _s, _kind, c_white, 0.92);
        // the moulding at the head of the shaft
        hall_taper(_o.gilt, _ox, _cz, _cap_y - 12, _cap_y,
                   HALL_ORB_R * 0.60, HALL_ORB_R * 0.60,
                   HALL_ORB_R * 0.66, HALL_ORB_R * 0.66,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.22);
        // ...and the cup, opening upward to take the sphere
        hall_taper(_o.gilt, _ox, _cz, _cap_y, _cup_y + 4,
                   HALL_ORB_R * 0.40, HALL_ORB_R * 0.40,
                   HALL_ORB_R * 0.72, HALL_ORB_R * 0.72,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.34);

        // The orb: a sphere, with a meridian and an equator ring round it.
        hall_sphere(_o.orb, _ox, HALL_ORB_Y, _cz, HALL_ORB_R, 12, 8,
                    spr_hall_pale, 0, _s, _kind, HALL_ORB_BODY, 0.95);
        hall_ring(_o.gilt, _ox, HALL_ORB_Y, _cz, HALL_ORB_R + 3, 2.4,
                  0, 0, 20, spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.30);
        hall_ring(_o.gilt, _ox, HALL_ORB_Y, _cz, HALL_ORB_R + 3, 2.4,
                  90, 0, 20, spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.15);
        hall_sphere(_o.glow, _ox, HALL_ORB_Y, _cz, HALL_ORB_R * 1.35,
                    10, 7, spr_hall_pale, 0, _s, _kind, HALL_ORB_COL,
                    HALL_ORB_GLOW);
        // Its bloom: two crossed cards of `spr_fx_bloom`, so the air round it
        // glows from any angle.
        hall_cross(_o.bloom, spr_fx_bloom, 0, _ox, HALL_ORB_Y, _cz,
                   HALL_ORB_R * HALL_ORB_BLOOM, 1.0, HALL_ORB_COL,
                   HALL_LAMP_GLOW);
    } else {
        // --- the bookcase ------------------------------------------------
        var _n = HALL_SHELVES;
        var _gap = (_y1 - _y0) / _n;
        for (var _i = 0; _i < _n; _i++) {
            var _sy = _y0 + _i * _gap;
            var _ty = _sy + _gap;
            // the books, set back at the bottom of the recess
            var _fr = floor(hall_hash(_i * 7 + _kind, 5) * 3) % 3;
            var _xb = _x_case + _s * HALL_BOOK_INSET;
            hall_tiles(_o.books[_fr], [_xb, _ty - HALL_BOARD_T, _z0],
                       [_xb, _ty - HALL_BOARD_T, _z1],
                       [_xb, _sy, _z1], [_xb, _sy, _z0],
                       spr_hall_books, _fr, 2, 1, 1.06, _s, _kind);
            // the board: its top face, and its front edge (the moulding
            // that catches the light)
            hall_tiles(_o.stone, [_x_case, _sy, _z0], [_x_back, _sy, _z0],
                       [_x_back, _sy, _z1], [_x_case, _sy, _z1],
                       spr_hall_stone, 0, 1, 2, 0.96, _s, _kind);
            // Untinted, so the texture's own moulding profile shows.
            hall_tiles(_o.board,
                       [_x_case, _sy, _z0], [_x_case, _sy, _z1],
                       [_x_case, _sy - HALL_BOARD_T, _z1],
                       [_x_case, _sy - HALL_BOARD_T, _z0],
                       spr_hall_board, 0, 4, 1, 1.0, _s, _kind);
        }
        // the head of the case, and its own underside
        hall_tiles(_o.stone, [_x_case, _y1, _z1], [_x_back, _y1, _z1],
                   [_x_back, _y1, _z0], [_x_case, _y1, _z0],
                   spr_hall_stone, 0, 2, 2, 0.26, _s, _kind);
        var _xb2 = _x_case + _s * HALL_BOOK_INSET;
        hall_tiles(_o.books[0], [_xb2, _y1, _z0], [_xb2, _y1, _z1],
                   [_xb2, _y1 - HALL_BOARD_T * 2, _z1],
                   [_xb2, _y1 - HALL_BOARD_T * 2, _z0],
                   spr_hall_books, 0, 2, 1, 0.30, _s, _kind);
    }

    // --- cornice and plinth, projecting past the pilaster ------------------
    hall_tiles(_o.cornice, [_x_corn, HALL_CEIL_H, 0],
               [_x_corn, HALL_CEIL_H, _bz],
               [_x_corn, HALL_CASE_TOP, _bz], [_x_corn, HALL_CASE_TOP, 0],
               spr_hall_cornice, 0, 2, 1, 0.74, _s, _kind);
    hall_tiles(_o.stone, [_x_corn, HALL_CASE_TOP, 0], [_x_case, HALL_CASE_TOP, 0],
               [_x_case, HALL_CASE_TOP, _bz], [_x_corn, HALL_CASE_TOP, _bz],
               spr_hall_stone, 0, 1, 4, 0.20, _s, _kind);
    // The gilt fillets stand `HALL_FILLET_D` proud of the stone behind them:
    // coplanar surfaces z-fight and flicker.
    var _fx_c = _x_corn - _s * HALL_FILLET_D;
    hall_tiles(_o.gilt, [_fx_c, HALL_CASE_TOP + 10, 0],
               [_fx_c, HALL_CASE_TOP + 10, _bz],
               [_fx_c, HALL_CASE_TOP, _bz], [_fx_c, HALL_CASE_TOP, 0],
               spr_hall_pale, 0, 4, 1, 1.20, _s, _kind, HALL_GILT);

    hall_tiles(_o.dado, [_x_plin, HALL_PLINTH_H, 0],
               [_x_plin, HALL_PLINTH_H, _bz],
               [_x_plin, 0, _bz], [_x_plin, 0, 0],
               spr_hall_dado, 0, 2, 1, 0.92, _s, _kind);
    hall_tiles(_o.stone, [_x_plin, HALL_PLINTH_H, 0],
               [_x_case, HALL_PLINTH_H, 0], [_x_case, HALL_PLINTH_H, _bz],
               [_x_plin, HALL_PLINTH_H, _bz],
               spr_hall_stone, 0, 1, 4, 1.05, _s, _kind);
    var _fx_p = _x_plin - _s * HALL_FILLET_D;
    hall_tiles(_o.gilt, [_fx_p, HALL_PLINTH_H, 0],
               [_fx_p, HALL_PLINTH_H, _bz],
               [_fx_p, HALL_PLINTH_H - 9, _bz],
               [_fx_p, HALL_PLINTH_H - 9, 0],
               spr_hall_pale, 0, 4, 1, 1.25, _s, _kind, HALL_GILT);
    // --- the top of the wall: coping, parapet, and a post ------------------
    //
    // The parapet's height narrows the visible wedge of sky along the whole
    // hall (a horizontal edge at height H and half-width X projects to a ray
    // from the vanishing point with slope (H - camera) / X), and the orrery
    // has to fit in that wedge (`test_hall_sky`).
    var _x_cop_i = _s * (HALL_HALF_W - HALL_CORN_D - 14);
    var _x_cop_o = _s * (HALL_HALF_W + HALL_COPING_OUT);
    var _y_c0 = HALL_CEIL_H;
    var _y_c1 = HALL_CEIL_H + HALL_COPING_H;
    var _x_par = _s * HALL_PARAPET_X;
    var _y_p1 = _y_c1 + HALL_PARAPET_H;

    // the coping: a dark soffit, a moulded face, and a lit slab on top
    hall_tiles(_o.stone, [_x_cop_i, _y_c0, 0], [_x_cop_o, _y_c0, 0],
               [_x_cop_o, _y_c0, _bz], [_x_cop_i, _y_c0, _bz],
               spr_hall_stone, 0, 1, 4, 0.16, _s, _kind);
    hall_tiles(_o.cornice, [_x_cop_i, _y_c1, 0], [_x_cop_i, _y_c1, _bz],
               [_x_cop_i, _y_c0, _bz], [_x_cop_i, _y_c0, 0],
               spr_hall_cornice, 0, 2, 1, 0.90, _s, _kind);
    hall_tiles(_o.stone, [_x_cop_i, _y_c1, 0], [_x_cop_o, _y_c1, 0],
               [_x_cop_o, _y_c1, _bz], [_x_cop_i, _y_c1, _bz],
               spr_hall_stone, 0, 1, 4, 1.16, _s, _kind);

    // the parapet, panelled like the dado at the other end of the same wall
    hall_tiles(_o.dado, [_x_par, _y_p1, 0], [_x_par, _y_p1, _bz],
               [_x_par, _y_c1, _bz], [_x_par, _y_c1, 0],
               spr_hall_dado, 0, 2, 1, 0.70, _s, _kind);
    hall_tiles(_o.stone, [_x_par, _y_p1, 0], [_x_cop_o, _y_p1, 0],
               [_x_cop_o, _y_p1, _bz], [_x_par, _y_p1, _bz],
               spr_hall_stone, 0, 1, 4, 1.26, _s, _kind);
    var _fx_t = _x_par - _s * HALL_FILLET_D;
    hall_tiles(_o.gilt, [_fx_t, _y_p1, 0], [_fx_t, _y_p1, _bz],
               [_fx_t, _y_p1 - 11, _bz], [_fx_t, _y_p1 - 11, 0],
               spr_hall_pale, 0, 4, 1, 1.34, _s, _kind, HALL_GILT);

    // Posts rather than an upper storey, since a post narrows the sky only at
    // its own bay: an obelisk over the pilaster, or a brazier on alcove bays.
    if (_kind == 2) {
        // A brazier, with a glow and a bloom.
        var _bx = _s * HALL_HALF_W;
        hall_taper(_o.stone, _bx, 0, _y_p1, _y_p1 + HALL_BRAZIER_H * 0.60,
                   15, 15, HALL_BRAZIER_R * 0.58, HALL_BRAZIER_R * 0.58,
                   spr_hall_stone, 0, _s, _kind, c_white, 0.88);
        hall_taper(_o.gilt, _bx, 0, _y_p1 + HALL_BRAZIER_H * 0.60,
                   _y_p1 + HALL_BRAZIER_H, HALL_BRAZIER_R * 0.58,
                   HALL_BRAZIER_R * 0.58, HALL_BRAZIER_R, HALL_BRAZIER_R,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.30);
        hall_sphere(_o.glow, _bx, _y_p1 + HALL_BRAZIER_H, 0,
                    HALL_BRAZIER_R * 0.90, 9, 6, spr_hall_pale, 0, _s, _kind,
                    HALL_BRAZIER_COL, HALL_BRAZIER_GLOW);
        hall_cross(_o.bloom, spr_fx_bloom, 0, _bx, _y_p1 + HALL_BRAZIER_H, 0,
                   HALL_BRAZIER_R * 3.4, 1.0, HALL_BRAZIER_COL,
                   HALL_LAMP_GLOW * 0.8);
    } else {
        var _ox = _s * HALL_HALF_W;
        var _oy = _y_p1 + HALL_OBELISK_H;
        hall_taper(_o.stone, _ox, 0, _y_p1, _oy,
                   HALL_OBELISK_W, HALL_OBELISK_W,
                   HALL_OBELISK_W * 0.60, HALL_OBELISK_W * 0.60,
                   spr_hall_stone, 0, _s, _kind, c_white, 0.84);
        // the gilt pyramidion
        hall_taper(_o.gilt, _ox, 0, _oy, _oy + HALL_OBELISK_CAP,
                   HALL_OBELISK_W * 0.60, HALL_OBELISK_W * 0.60, 1.5, 1.5,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.45);
    }
}

/// @desc Build both sides and the floor of one bay kind into frozen buffers,
///       one buffer per texture (a buffer is drawn with one texture).
function hall_build_case(_kind) {
    var _f = hall_format();
    var _o = {
        stone: vertex_create_buffer(),
        pil: vertex_create_buffer(),
        gilt: vertex_create_buffer(),
        orb: vertex_create_buffer(),
        glow: vertex_create_buffer(),
        bloom: vertex_create_buffer(),
        dado: vertex_create_buffer(),
        cornice: vertex_create_buffer(),
        board: vertex_create_buffer(),
        marble: vertex_create_buffer(),
        runner: vertex_create_buffer(),
        border: vertex_create_buffer(),
    };
    var _names = ["stone", "pil", "gilt", "orb", "glow", "bloom",
                  "dado", "cornice", "board", "marble", "runner", "border"];
    for (var _i = 0; _i < array_length(_names); _i++) {
        vertex_begin(_o[$ _names[_i]], _f);
    }
    // The books sprite has three frames, so three buffers (`hall_frames_begin`).
    _o.books = hall_frames_begin(spr_hall_books, _f);
    hall_case_side(_o, -1, _kind);
    hall_case_side(_o, 1, _kind);
    // The floor is part of the bay so each kind lights its own floor.
    hall_floor_bay(_o, _kind);

    // A slot a bay kind wrote nothing to becomes -1 (`hall_submit` skips it):
    // freezing an empty buffer is a Direct3D error (CreateBuffer,
    // E_INVALIDARG), which is a modal box and hangs the harnesses.
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _n = _names[_i];
        var _vb = _o[$ _n];
        vertex_end(_vb);
        if (vertex_get_number(_vb) <= 0) {
            vertex_delete_buffer(_vb);
            _o[$ _n] = -1;
            continue;
        }
        vertex_freeze(_vb);
    }
    _o.books = hall_frames_end(_o.books);
    return _o;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

/// @desc Advance the camera and the reveal.
function hall_step(_b) {
    _b.t++;

    // The reveal follows `omen` through a smootherstep, so the camera move
    // starts and ends gently.
    var _o = clamp(_b.omen, 0, 1);
    _b.reveal = _o * _o * _o * (_o * (_o * 6 - 15) + 10);

    // The opening: drives the veil and the flight speed.
    if (_b.intro < 1) _b.intro = min(1, _b.intro + 1 / HALL_INTRO_TIME);
    var _in = hall_ease(_b.intro);

    // Slower in phase A (high up, nothing nearby to read speed from).
    _b.spd = lerp(HALL_SPEED_A, HALL_SPEED, _b.reveal)
             * lerp(HALL_INTRO_SPD, 1, _in);
    // A slow swell on the speed.
    _b.rush = _b.spd * (1 + HALL_SWELL * dsin(_b.t * 360 / HALL_SWELL_P));
    _b.dist += _b.rush;

    _b.cam_y = lerp(HALL_CAM_HIGH, HALL_CAM_FLY, _b.reveal);
    _b.pitch = lerp(HALL_PITCH_A, HALL_PITCH_B, _b.reveal);

    // Lean toward the player's side, only once revealed; eased and capped
    // per frame as in the grove.
    var _want = HALL_LEAN * _b.aim * _b.reveal;
    _b.lean += clamp((_want - _b.lean) * HALL_LEAN_EASE,
                     -HALL_LEAN_SPD, HALL_LEAN_SPD);
    _b.cam_x = _b.lean;
}

// ---------------------------------------------------------------------------
// The draw
// ---------------------------------------------------------------------------

/// @desc Where the camera is, in world units.
function hall_cam_z(_b) {
    return _b.dist;
}

/// @desc Draw the hall into `_b.surf` with a 3D camera, then draw the surface
///       into the field (or the whole screen with `_fill`). The surface gives
///       the hall its own depth buffer and viewport; surfaces can be lost, so
///       it is recreated when missing or the wrong size.
function hall_draw_back(_b, _fill) {
    var _w = _fill ? GAME_W : FIELD_W;
    var _h = _fill ? GAME_H : FIELD_H;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;

    if (!surface_exists(_b.surf)) {
        _b.surf = surface_create(_w, _h);
    } else if (surface_get_width(_b.surf) != _w
               || surface_get_height(_b.surf) != _h) {
        surface_free(_b.surf);
        _b.surf = surface_create(_w, _h);
    }

    surface_set_target(_b.surf);
    draw_clear_alpha(HALL_FOG, 1);

    var _cx = _b.cam_x;
    var _cy = _b.cam_y;
    var _cz = hall_cam_z(_b);
    var _p = _b.pitch;

    // Look target: forward along z, tilted down by the pitch.
    var _tx = _cx;
    var _ty = _cy + dtan(_p) * 100;
    var _tz = _cz + 100;

    var _view = matrix_build_lookat(_cx, _cy, _cz, _tx, _ty, _tz, 0, 1, 0);
    // Positive FOV and aspect: this world is y-up. (The common GameMaker idiom
    // of negating both is for y-down worlds, and turns this hall upside down.)
    var _proj = matrix_build_projection_perspective_fov(
        HALL_FOV, _w / _h, HALL_ZNEAR, HALL_ZFAR);

    var _old_w = matrix_get(matrix_world);
    matrix_set(matrix_view, _view);
    matrix_set(matrix_projection, _proj);

    // Save every GPU state changed here and restore it at the end. This state
    // is global and survives the room: a leaked `cull_counterclockwise` once
    // stopped the boss's health bar rendering in every stage.
    var _st_cull = gpu_get_cullmode();
    var _st_filt = gpu_get_texfilter();
    var _st_zt = gpu_get_ztestenable();
    var _st_zw = gpu_get_zwriteenable();
    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(true);
    gpu_set_cullmode(cull_noculling);
    gpu_set_texfilter(true);

    // Sky, far chamber and orrery first: all are behind every bay, so the hall
    // simply draws over them.
    hall_draw_sky(_b);
    hall_draw_far(_b);
    hall_draw_orrery(_b);

    gpu_set_ztestenable(true);
    hall_pass_solid();

    // The bays from the camera's bay out to `HALL_BAYS` ahead.
    var _b0 = floor(_cz / HALL_BAY_Z);
    var _b1 = _b0 + HALL_BAYS;

    for (var _i = _b0; _i <= _b1; _i++) {
        var _z = _i * HALL_BAY_Z;
        matrix_set(matrix_world, matrix_build(0, 0, _z, 0, 0, 0, 1, 1, 1));
        var _k = hall_bay_kind(_i);
        var _c = _b.joinery[_k];
        hall_submit(_c.marble, sprite_get_texture(spr_hall_floor, 0));
        hall_submit(_c.runner, sprite_get_texture(spr_hall_runner, 0));
        hall_submit(_c.border, sprite_get_texture(spr_hall_border, 0));
        hall_submit(_c.stone, sprite_get_texture(spr_hall_stone, 0));
        hall_submit(_c.gilt, sprite_get_texture(spr_hall_pale, 0));
        hall_submit(_c.pil, sprite_get_texture(spr_hall_pil, 0));
        hall_submit_frames(_c.books, spr_hall_books);
        hall_submit(_c.board, sprite_get_texture(spr_hall_board, 0));
        hall_submit(_c.dado, sprite_get_texture(spr_hall_dado, 0));
        hall_submit(_c.cornice, sprite_get_texture(spr_hall_cornice, 0));
        hall_submit(_c.orb, sprite_get_texture(spr_hall_pale, 0));
    }

    // The emissive pass: additive, depth-tested (so walls occlude lights) but
    // not depth-written (so lights at the same depth all land). Every kind is
    // submitted; empty slots are -1 and skipped.
    hall_pass_light();
    for (var _i = _b0; _i <= _b1; _i++) {
        var _k = hall_bay_kind(_i);
        matrix_set(matrix_world,
                   matrix_build(0, 0, _i * HALL_BAY_Z, 0, 0, 0, 1, 1, 1));
        hall_submit(_b.joinery[_k].glow, sprite_get_texture(spr_hall_pale, 0));
        hall_submit(_b.joinery[_k].bloom, sprite_get_texture(spr_fx_bloom, 0));
    }
    hall_pass_solid();

    hall_draw_props(_b, _b0, _b1);

    // Restore the shader and all other state.
    shader_reset();
    gpu_set_fog(false, c_black, 0, 1);
    gpu_set_ztestenable(_st_zt);
    gpu_set_zwriteenable(_st_zw);
    gpu_set_cullmode(_st_cull);
    gpu_set_texfilter(_st_filt);
    matrix_set(matrix_world, matrix_build_identity());
    matrix_set(matrix_view, matrix_build_identity());
    matrix_set(matrix_projection, matrix_build_identity());
    surface_reset_target();

    matrix_set(matrix_world, _old_w);
    draw_surface_ext(_b.surf, _x0, _y0, 1, 1, 0, c_white, 1);
    hall_draw_veil(_b, _x0, _y0, _w, _h);
}

/// @desc The opening: an opaque black veil over the hall that fades as
///       `intro` rises (stays dense at first, then thins). Fine in the back
///       pass, since bullets draw over it.
function hall_draw_veil(_b, _x0, _y0, _w, _h) {
    if (_b.intro >= 1) return;
    draw_set_colour(c_black);
    draw_set_alpha(power(1 - _b.intro, 1.30));
    draw_rectangle(_x0, _y0, _x0 + _w, _y0 + _h, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The two passes (solid and light), both through `sh_hall`.
//
// Far geometry has to fade out by alpha, not just fog toward `HALL_FOG`: the
// far chamber is drawn behind the last bays, and a fog-coloured silhouette in
// front of it is as visible as a black one. `vertex_submit` has no per-draw
// alpha and the buffers are frozen, so `sh_hall` computes both the fog and
// the fade from each vertex's distance to the camera.
// ---------------------------------------------------------------------------

/// @desc Begin a solid pass: normal blending, depth writing on. `_ref` is the
///       alpha-test threshold (cut-outs like the tabards need one; blooms
///       must not be tested).
function hall_pass_solid(_ref = 0) {
    gpu_set_blendmode(bm_normal);
    gpu_set_zwriteenable(true);
    hall_shader(HALL_FOG, _ref);
}

/// @desc Begin the light pass: additive, no depth writing (so lights at the
///       same depth both land), fog toward black (distance dims a light).
function hall_pass_light() {
    gpu_set_zwriteenable(false);
    gpu_set_blendmode(bm_add);
    hall_shader(c_black, 0);
}

/// @desc Set `sh_hall` and its uniforms (fog range, fade range, fog colour,
///       alpha-test threshold).
function hall_shader(_fogcol, _ref) {
    shader_set(sh_hall);
    shader_set_uniform_f(shader_get_uniform(sh_hall, "u_fog"),
                         HALL_FOG_START, HALL_FOG_END);
    shader_set_uniform_f(shader_get_uniform(sh_hall, "u_fade"),
                         HALL_FADE_START, HALL_FADE_END);
    shader_set_uniform_f(shader_get_uniform(sh_hall, "u_fogcol"),
                         colour_get_red(_fogcol) / 255,
                         colour_get_green(_fogcol) / 255,
                         colour_get_blue(_fogcol) / 255);
    shader_set_uniform_f(shader_get_uniform(sh_hall, "u_alpharef"),
                         _ref / 255);
}

/// @desc Submit a buffer, skipping -1 (a slot nothing was written to).
function hall_submit(_vb, _tex) {
    if (_vb == -1) return;
    vertex_submit(_vb, pr_trianglelist, _tex);
}

// ---------------------------------------------------------------------------
// One buffer per frame. Frames of one sprite may sit on different texture
// pages, and `vertex_submit` takes one texture, so a buffer holding two frames
// is only right while the packer keeps them together (a repack once turned the
// tabards into masonry). This can't be checked at run time
// (`sprite_get_texture` returns a per-frame pointer even for frames on one
// page), so every multi-frame sprite gets a buffer per frame;
// `check_hall_frame_textures` refuses the other shape.
// ---------------------------------------------------------------------------

/// @desc One buffer per frame of a sprite, begun and ready to be written.
function hall_frames_begin(_spr, _f) {
    var _a = [];
    for (var _i = 0; _i < sprite_get_number(_spr); _i++) {
        _a[_i] = vertex_create_buffer();
        vertex_begin(_a[_i], _f);
    }
    return _a;
}

/// @desc ...and end and freeze them; a frame with nothing written becomes -1.
function hall_frames_end(_a) {
    for (var _i = 0; _i < array_length(_a); _i++) {
        vertex_end(_a[_i]);
        if (vertex_get_number(_a[_i]) <= 0) {
            vertex_delete_buffer(_a[_i]);
            _a[_i] = -1;
            continue;
        }
        vertex_freeze(_a[_i]);
    }
    return _a;
}

/// @desc Build, fill and freeze one buffer per frame.
function hall_frames_buffer(_spr, _f, _fill) {
    var _a = hall_frames_begin(_spr, _f);
    _fill(_a);
    return hall_frames_end(_a);
}

/// @desc Draw every frame's buffer, each with its own frame's texture.
function hall_submit_frames(_a, _spr) {
    for (var _i = 0; _i < array_length(_a); _i++) {
        if (_a[_i] == -1) continue;
        vertex_submit(_a[_i], pr_trianglelist, sprite_get_texture(_spr, _i));
    }
}

/// @desc Build, fill, freeze. Answers `-1` if nothing was written.
function hall_prop_buffer(_f, _fill) {
    var _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    _fill(_vb);
    vertex_end(_vb);
    if (vertex_get_number(_vb) <= 0) {
        vertex_delete_buffer(_vb);
        return -1;
    }
    vertex_freeze(_vb);
    return _vb;
}

/// @desc One flat quad with the whole sprite on it (for tabards and glows;
///       solids use `hall_taper` and the like).
function hall_face(_vb, _spr, _frame, _l, _p0, _p1, _p2, _p3,
                   _col = c_white, _a = 1) {
    var _q = [hall_uv(_spr, _frame, 0, 0), hall_uv(_spr, _frame, 1, 0),
              hall_uv(_spr, _frame, 1, 1), hall_uv(_spr, _frame, 0, 1)];
    var _p = [_p0, _p1, _p2, _p3];
    var _c = hall_shade(_col, _l);
    var _order = [0, 1, 2, 0, 2, 3];
    for (var _i = 0; _i < 6; _i++) {
        var _j = _order[_i];
        vertex_position_3d(_vb, _p[_j][0], _p[_j][1], _p[_j][2]);
        vertex_colour(_vb, _c, _a);
        vertex_texcoord(_vb, _q[_j][0], _q[_j][1]);
    }
}

/// @desc One upright quad in the plane z = `_z`, facing back down the hall.
function hall_face_z(_vb, _spr, _frame, _x, _y, _z, _h, _l) {
    var _w = _h * sprite_get_width(_spr) / sprite_get_height(_spr);
    var _hw = _w * 0.5;
    hall_face(_vb, _spr, _frame, _l,
              [_x - _hw, _y + _h, _z], [_x + _hw, _y + _h, _z],
              [_x + _hw, _y, _z], [_x - _hw, _y, _z]);
}

/// @desc A glow: two square cards at right angles through a point. Crossed
///       cards suit a soft, symmetric additive glow (not a solid object).
function hall_cross(_vb, _spr, _frame, _x, _y, _z, _r, _l,
                    _col = c_white, _a = 1) {
    hall_face(_vb, _spr, _frame, _l,
              [_x - _r, _y + _r, _z], [_x + _r, _y + _r, _z],
              [_x + _r, _y - _r, _z], [_x - _r, _y - _r, _z], _col, _a);
    hall_face(_vb, _spr, _frame, _l,
              [_x, _y + _r, _z - _r], [_x, _y + _r, _z + _r],
              [_x, _y - _r, _z + _r], [_x, _y - _r, _z - _r], _col, _a);
}

// ---------------------------------------------------------------------------
// Solids. The furniture is real geometry (boxes, spheres, lathes, rings)
// rather than cards, because phase A looks down on it from above.
// ---------------------------------------------------------------------------

/// @desc A tapered box, `_y0` to `_y1`: four sides and a top (no bottom).
function hall_taper(_vb, _cx, _cz, _y0, _y1, _w0, _d0, _w1, _d1,
                    _spr, _frame, _side, _kind, _col = c_white, _face = 1) {
    var _c = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
    for (var _i = 0; _i < 4; _i++) {
        var _a = _c[_i];
        var _b = _c[(_i + 1) % 4];
        // Sides facing along z are dimmer than those facing the nave.
        var _f = _face * ((_a[0] == _b[0]) ? 1.0 : 0.58);
        hall_tiles(_vb,
                   [_cx + _a[0] * _w1, _y1, _cz + _a[1] * _d1],
                   [_cx + _b[0] * _w1, _y1, _cz + _b[1] * _d1],
                   [_cx + _b[0] * _w0, _y0, _cz + _b[1] * _d0],
                   [_cx + _a[0] * _w0, _y0, _cz + _a[1] * _d0],
                   _spr, _frame, 1, 1, _f, _side, _kind, _col);
    }
    hall_tiles(_vb,
               [_cx - _w1, _y1, _cz - _d1], [_cx + _w1, _y1, _cz - _d1],
               [_cx + _w1, _y1, _cz + _d1], [_cx - _w1, _y1, _cz + _d1],
               _spr, _frame, 1, 1, _face * 1.28, _side, _kind, _col);
}

/// @desc A coarse faceted sphere.
function hall_sphere(_vb, _cx, _cy, _cz, _r, _nu, _nv,
                     _spr, _frame, _side, _kind, _col = c_white, _face = 1,
                     _lightfn = hall_wall_light) {
    for (var _i = 0; _i < _nu; _i++) {
        for (var _j = 0; _j < _nv; _j++) {
            var _a0 = 360 * _i / _nu, _a1 = 360 * (_i + 1) / _nu;
            var _p0 = -90 + 180 * _j / _nv, _p1 = -90 + 180 * (_j + 1) / _nv;
            var _q = [[_a0, _p1], [_a1, _p1], [_a1, _p0], [_a0, _p0]];
            var _v = [];
            for (var _k = 0; _k < 4; _k++) {
                var _ca = dcos(_q[_k][1]);
                _v[_k] = [_cx + _r * _ca * dcos(_q[_k][0]),
                          _cy + _r * dsin(_q[_k][1]),
                          _cz + _r * _ca * dsin(_q[_k][0])];
            }
            // the top of a sphere catches the light, the underside does not
            var _f = _face * (0.52 + 0.62 * (0.5 + 0.5 * dsin(_p1)));
            hall_tiles(_vb, _v[0], _v[1], _v[2], _v[3],
                       _spr, _frame, 1, 1, _f, _side, _kind, _col, _lightfn);
        }
    }
}

/// @desc A surface of revolution about the y axis from a profile of
///       `[radius, y]` points, foot upward, `_nu` segments round. Shaded by
///       facing rather than by a light direction: segments edge-on to the
///       camera are brighter (`_rim` controls how much), which makes glass
///       read as transparent.
function hall_lathe(_vb, _cx, _cy, _cz, _prof, _nu, _spr, _frame, _side,
                    _kind, _col = c_white, _face = 1, _rim = 0.55,
                    _lightfn = hall_wall_light) {
    var _n = array_length(_prof) - 1;
    for (var _j = 0; _j < _n; _j++) {
        var _r0 = _prof[_j][0], _y0 = _prof[_j][1];
        var _r1 = _prof[_j + 1][0], _y1 = _prof[_j + 1][1];
        for (var _i = 0; _i < _nu; _i++) {
            var _a0 = 360 * _i / _nu, _a1 = 360 * (_i + 1) / _nu;
            var _v = [[_cx + _r1 * dcos(_a0), _cy + _y1, _cz + _r1 * dsin(_a0)],
                      [_cx + _r1 * dcos(_a1), _cy + _y1, _cz + _r1 * dsin(_a1)],
                      [_cx + _r0 * dcos(_a1), _cy + _y0, _cz + _r0 * dsin(_a1)],
                      [_cx + _r0 * dcos(_a0), _cy + _y0, _cz + _r0 * dsin(_a0)]];
            // the camera looks down -z, so a segment facing it is at
            // sin(a) = -1 and one edge-on to it is at cos(a) = +-1
            var _ca = dcos((_a0 + _a1) * 0.5);
            var _f = _face * (1 - _rim + _rim * 1.9 * _ca * _ca);
            hall_tiles(_vb, _v[0], _v[1], _v[2], _v[3],
                       _spr, _frame, 1, 1, _f, _side, _kind, _col, _lightfn);
        }
    }
}

/// @desc A flat ring, tilted about x then yawed about y.
function hall_ring(_vb, _cx, _cy, _cz, _r, _w, _tilt, _yaw, _n,
                   _spr, _frame, _side, _kind, _col = c_white, _face = 1,
                   _lightfn = hall_wall_light) {
    for (var _i = 0; _i < _n; _i++) {
        var _a0 = 360 * _i / _n, _a1 = 360 * (_i + 1) / _n;
        var _v = [];
        var _spec = [[_a0, _r + _w], [_a1, _r + _w], [_a1, _r - _w],
                     [_a0, _r - _w]];
        for (var _k = 0; _k < 4; _k++) {
            // `hall_orient`, shared with the orrery's bodies.
            var _o = hall_orient(dcos(_spec[_k][0]) * _spec[_k][1],
                                 dsin(_spec[_k][0]) * _spec[_k][1], 0,
                                 _tilt, _yaw);
            _v[_k] = [_cx + _o[0], _cy + _o[1], _cz + _o[2]];
        }
        hall_tiles(_vb, _v[0], _v[1], _v[2], _v[3],
                   _spr, _frame, 1, 1, _face, _side, _kind, _col, _lightfn);
    }
}

/// @desc One point on the swept Bastet statue, from its height down the card
///       `_v` and the angle `_a` round the cross-section there. Mirroring
///       (`_flip`) applies only to the world position; the cross-section and
///       texture stay in the sprite's own coordinates. (Flipping both cancels
///       out and wraps the picture onto the wrong ends of the form.)
function hall_bastet_point(_v, _a, _x, _y0, _h, _z, _w, _flip) {
    var _vc = clamp(_v, 0, 1);
    var _c = bastet_at(_vc);
    var _u = _c[0] + _c[1] * dcos(_a);
    var _wu = _flip ? 1 - _u : _u;
    return [_x + (_wu - 0.5) * _w, _y0 + (1 - _vc) * _h,
            _z + _c[2] * _w * dsin(_a), _u, _vc];
}

/// @desc One vertex of the sweep. The texture is projected along z, so the
///       view down the hall shows the sprite exactly. The cross-section spans
///       the whole silhouette at each height, and the alpha test
///       (`HALL_ALPHA_REF`) cuts out the transparent texels (e.g. between the
///       ears).
function hall_bastet_vertex(_vb, _v, _a, _x, _y0, _h, _z, _w, _flip, _spr,
                            _l) {
    var _p = hall_bastet_point(_v, _a, _x, _y0, _h, _z, _w, _flip);

    // The normal: cross product of the two tangents, by central differences.
    var _e = 0.008;
    var _pv0 = hall_bastet_point(_v - _e, _a, _x, _y0, _h, _z, _w, _flip);
    var _pv1 = hall_bastet_point(_v + _e, _a, _x, _y0, _h, _z, _w, _flip);
    var _pa0 = hall_bastet_point(_v, _a - 5, _x, _y0, _h, _z, _w, _flip);
    var _pa1 = hall_bastet_point(_v, _a + 5, _x, _y0, _h, _z, _w, _flip);
    var _tv = [_pv1[0] - _pv0[0], _pv1[1] - _pv0[1], _pv1[2] - _pv0[2]];
    var _ta = [_pa1[0] - _pa0[0], _pa1[1] - _pa0[1], _pa1[2] - _pa0[2]];
    var _nx = _ta[1] * _tv[2] - _ta[2] * _tv[1];
    var _ny = _ta[2] * _tv[0] - _ta[0] * _tv[2];
    var _nz = _ta[0] * _tv[1] - _ta[1] * _tv[0];
    var _len = sqrt(_nx * _nx + _ny * _ny + _nz * _nz);
    if (_len > 0.00001) {
        _nx /= _len; _ny /= _len; _nz /= _len;
    } else {
        _nx = 0; _ny = 0; _nz = -1;
    }
    // Forced to point away from the axis, whatever the winding.
    if (_nx * (_p[0] - _x) + _nz * (_p[2] - _z) < 0) {
        _nx = -_nx; _ny = -_ny; _nz = -_nz;
    }

    // A surface facing back down the hall (normal -z) gets exactly `_l`; the
    // extra terms light upward-facing surfaces, which phase A sees from above.
    var _f = _l * (1 + HALL_STATUE_TOP * max(0, _ny)
                   - HALL_STATUE_AWAY * max(0, _nz));

    vertex_position_3d(_vb, _p[0], _p[1], _p[2]);
    vertex_colour(_vb, hall_shade(c_white, _f), 1);
    var _q = hall_uv(_spr, 0, _p[3], _p[4]);
    vertex_texcoord(_vb, _q[0], _q[1]);
}

/// @desc The Bastet as a solid: her profile swept round. The cross-section per
///       height comes from `scripts/sanctum_table`, measured off the sprite's
///       alpha by `tools/make_sanctum.py`, so the solid's outline matches the
///       drawing.
function hall_bastet_sweep(_vb, _spr, _x, _y0, _h, _z, _flip, _l) {
    var _w = _h * sprite_get_width(_spr) / sprite_get_height(_spr);
    var _t = global.bastet_slice;
    var _n = array_length(_t);
    var _s = HALL_STATUE_STEPS;
    for (var _i = 0; _i < _n - 1; _i++) {
        var _v0 = _t[_i][0];
        var _v1 = _t[_i + 1][0];
        for (var _j = 0; _j < _s; _j++) {
            var _a0 = 360 * _j / _s;
            var _a1 = 360 * (_j + 1) / _s;
            var _c = [[_v0, _a0], [_v0, _a1], [_v1, _a1],
                      [_v0, _a0], [_v1, _a1], [_v1, _a0]];
            for (var _k = 0; _k < 6; _k++) {
                hall_bastet_vertex(_vb, _c[_k][0], _c[_k][1],
                                   _x, _y0, _h, _z, _w, _flip, _spr, _l);
            }
        }
    }
}

/// @desc A seated Bastet statue on a plinth (a tapered box with a moulded cap
///       and gilt fillets). The sprite is a profile and is mirrored on the far
///       wall, so the statues face each other across the nave. Her rim light
///       is a second sweep (`statue_rim`). The sprite contains the figure
///       only; `HALL_STATUE_BASE` is the plinth's height.
function hall_bastet(_o, _s, _z, _kind) {
    var _x = _s * HALL_STATUE_X;
    var _pl = spr_hall_plinth;
    var _pa = spr_hall_pale;
    var _b = HALL_STATUE_BASE;

    // A die, a moulded cap and a foot block, with gilt fillets between.
    hall_taper(_o.plinth, _x, _z, 14, _b - 22, 74, 68, 65, 59,
               _pl, 0, _s, _kind, c_white, 1.0);
    hall_taper(_o.plinth, _x, _z, _b - 22, _b, 79, 73, 75, 69,
               _pl, 0, _s, _kind, c_white, 1.15);
    hall_taper(_o.plinth, _x, _z, 0, 14, 82, 76, 79, 73,
               _pl, 0, _s, _kind, c_white, 0.92);
    hall_taper(_o.gilt, _x, _z, _b - 26, _b - 19, 81, 75, 81, 75,
               _pa, 0, _s, _kind, HALL_GILT, 1.40);
    hall_taper(_o.gilt, _x, _z, 14, 21, 80, 74, 80, 74,
               _pa, 0, _s, _kind, HALL_GILT, 1.10);

    var _mirror = (_s > 0);
    hall_bastet_sweep(_o.statue, spr_hall_bastet, _x, _b, HALL_STATUE_H, _z,
                      _mirror, HALL_PROP_LIGHT);
    hall_bastet_sweep(_o.statue_rim, spr_hall_bastet_rim, _x, _b,
                      HALL_STATUE_H, _z, _mirror, HALL_STATUE_RIM);
}

/// @desc The pedestal an instrument floats over (the instrument itself is
///       drawn separately; see `hall_build_instruments`). The shaft uses
///       `spr_hall_deskface` in its own buffer (`deskface`), and the cap
///       `spr_hall_pale` in `gilt`: each buffer must match the sprite it is
///       submitted with, or the result depends on the atlas packing
///       (`check_hall_buffer_textures`).
function hall_desk(_o, _s, _z, _kind) {
    var _x = _s * HALL_DESK_X;
    var _pa = spr_hall_pale;
    var _t = HALL_DESK_TOP;

    hall_taper(_o.deskface, _x, _z, 0, _t - 12, 52, 74, 44, 64,
               spr_hall_deskface, 0, _s, _kind, c_white, 1.0);
    hall_taper(_o.gilt, _x, _z, _t - 12, _t, 60, 82, 60, 82,
               _pa, 0, _s, _kind, HALL_MASONRY, 1.1);
    hall_taper(_o.gilt, _x, _z, _t - 15, _t - 9, 62, 84, 62, 84,
               _pa, 0, _s, _kind, HALL_GILT, 1.30);
}

/// @desc Build the four prop arrangements (`hall_prop_variant`).
function hall_build_props(_b) {
    _b.prop = [];
    for (var _v = 0; _v < 4; _v++) {
        _b.prop[_v] = hall_build_prop_set(_v);
    }
}

/// @desc Which prop arrangement bay `_i` gets, cycling every four bays:
///       0 tabards only (the alcove bay), 1 a pair of statues, 2 or 3 tabards
///       plus a pedestal on the left or right (hashed, so the order doesn't
///       repeat exactly).
function hall_prop_variant(_i) {
    var _m = ((_i % 4) + 4) % 4;
    if (_m == 1 || _m == 3) return 1;           // a pair of statues
    if (_m == 0) return (hall_hash(_i, 21) < 0.5) ? 2 : 3;  // ...and a pedestal
    return 0;                                   // the alcove bay: tabard only
}

/// @desc One bay's furniture, for bays of the given parity.
function hall_build_prop_set(_v) {
    // Statue bays and pedestal bays are exclusive (both stand on the same
    // line at the same point in the bay).
    var _statues = (_v == 1);
    var _pedestal = (_v >= 2);
    var _f = hall_format();
    var _o = {
        stone: vertex_create_buffer(),
        gilt: vertex_create_buffer(),
        glow: vertex_create_buffer(),
        plinth: vertex_create_buffer(),
        deskface: vertex_create_buffer(),
        statue: vertex_create_buffer(),
        statue_rim: vertex_create_buffer(),
    };
    // One buffer per sprite: `deskface` and `statue_rim` are separate slots
    // because they are separate sprites.
    var _names = ["stone", "gilt", "glow", "plinth", "deskface", "statue",
                  "statue_rim"];
    for (var _i = 0; _i < array_length(_names); _i++) {
        vertex_begin(_o[$ _names[_i]], _f);
    }
    // The two tabards are two frames of one sprite: one buffer each.
    _o.banner = hall_frames_begin(spr_hall_banner, _f);

    // The pedestal stands at the middle of its bay, halfway between the
    // statues of the neighbouring bays. Built with bay kind 0: an arrangement
    // doesn't know which bay it will stand in, and kind 2 would add the
    // alcove orb's light.
    if (_pedestal) {
        hall_desk(_o, hall_inst_side(_v), HALL_BAY_Z * 0.5, 0);
    }

    for (var _s = -1; _s <= 1; _s += 2) {
        if (_statues) {
            hall_bastet(_o, _s, HALL_BAY_Z * 0.50, 0);
        } else {
            var _bf = (_s > 0) ? 1 : 0;
            hall_face_z(_o.banner[_bf], spr_hall_banner,
                        _bf, _s * HALL_BANNER_X,
                        HALL_CEIL_H - HALL_BANNER_DROP - HALL_BANNER_H,
                        HALL_BAY_Z * 0.50, HALL_BANNER_H, HALL_PROP_LIGHT);
        }
    }

    for (var _i = 0; _i < array_length(_names); _i++) {
        var _vb = _o[$ _names[_i]];
        vertex_end(_vb);
        if (vertex_get_number(_vb) <= 0) {
            vertex_delete_buffer(_vb);
            _o[$ _names[_i]] = -1;
            continue;
        }
        vertex_freeze(_vb);
    }
    _o.banner = hall_frames_end(_o.banner);
    return _o;
}

// ---------------------------------------------------------------------------
// The instruments on the pedestals (an hourglass and an armillary). Unlike the
// frozen bay geometry, each is built at the origin and drawn under its own
// matrix every frame, so it can turn and bob; hence `hall_no_light`. Every
// piece uses `spr_hall_pale` with a tint, so each buffer is one submit.
// ---------------------------------------------------------------------------

/// @desc The hourglass's profile, foot to head, as `[radius, y]` about its
///       middle: a table for the lower bulb, mirrored for the upper.
function hall_glass_profile() {
    var _t = [[0.60, 0.000], [0.90, 0.052], [1.00, 0.132], [0.98, 0.222],
              [0.85, 0.312], [0.62, 0.398], [0.32, 0.458], [0.14, 0.488]];
    var _n = array_length(_t);
    var _h = HALL_GLASS_H;
    var _p = [];
    for (var _i = 0; _i < _n; _i++) {
        _p[_i] = [_t[_i][0] * HALL_GLASS_R, _t[_i][1] * _h - _h * 0.5];
    }
    _p[_n] = [HALL_GLASS_NECK, 0];
    for (var _i = 0; _i < _n; _i++) {
        var _s = _t[_n - 1 - _i];
        _p[_n + 1 + _i] = [_s[0] * HALL_GLASS_R, _h * 0.5 - _s[1] * _h];
    }
    return _p;
}

/// @desc The glass shell, drawn in the light pass (additive), so the sand
///       inside it shows through.
function hall_fill_glass(_vb) {
    hall_lathe(_vb, 0, 0, 0, hall_glass_profile(), HALL_GLASS_SEG,
               spr_hall_pale, 0, 1, 0, HALL_GLASS, HALL_PROP_LIGHT * 0.30,
               0.80, hall_no_light);
}

/// @desc The gilt frame: a plate at each end and three posts (three always
///       show at least two from any angle; four line up in pairs).
function hall_fill_glass_frame(_vb) {
    var _h = HALL_GLASS_H * 0.5;
    var _r = HALL_GLASS_R * 1.18;
    var _c = HALL_PROP_LIGHT * 1.30;
    for (var _e = -1; _e <= 1; _e += 2) {
        var _y0 = _e * _h;
        var _y1 = _e * (_h + 7);
        hall_lathe(_vb, 0, 0, 0,
                   [[0, _y0], [_r, _y0], [_r * 0.96, _y1], [0, _y1]],
                   HALL_GLASS_SEG, spr_hall_pale, 0, 1, 0, HALL_GILT, _c,
                   0.30, hall_no_light);
    }
    for (var _i = 0; _i < 3; _i++) {
        var _a = 90 + 120 * _i;
        hall_lathe(_vb, dcos(_a) * _r * 0.90, 0, dsin(_a) * _r * 0.90,
                   [[0, -_h - 5], [3.1, -_h - 2], [3.1, _h + 2], [0, _h + 5]],
                   7, spr_hall_pale, 0, 1, 0, HALL_GILT, _c * 1.05, 0.25,
                   hall_no_light);
    }
}

/// @desc The sand: a heap below, a body above with a dished surface, and the
///       thread between. The level never changes (no state to reset).
function hall_fill_sand(_vb) {
    var _p = hall_glass_profile();
    var _h = HALL_GLASS_H;
    var _c = HALL_PROP_LIGHT * 1.00;
    var _sy = -_h * 0.5 + _h * 0.5 * HALL_SAND_FILL;

    // The heap: the glass's contour up to the fill level, then a cone.
    var _heap = [];
    var _n = 0;
    for (var _i = 0; _i < array_length(_p); _i++) {
        if (_p[_i][1] > _sy) break;
        _heap[_n++] = [_p[_i][0] * 0.90, _p[_i][1] + 1.5];
    }
    var _hr = _heap[_n - 1][0];
    _heap[_n++] = [_hr * 0.66, _sy + _h * 0.055];
    _heap[_n++] = [0, _sy + _h * 0.105];
    hall_lathe(_vb, 0, 0, 0, _heap, HALL_GLASS_SEG, spr_hall_pale, 0, 1, 0,
               HALL_SAND, _c, 0.18, hall_no_light);

    // The body above, resting on the neck, its surface dished.
    var _uy = _h * HALL_SAND_HEAD;
    var _body = [[HALL_GLASS_NECK * 0.85, 1.0]];
    var _m = 1;
    for (var _i = 0; _i < array_length(_p); _i++) {
        if (_p[_i][1] <= 1.0 || _p[_i][1] > _uy) continue;
        _body[_m++] = [_p[_i][0] * 0.90, _p[_i][1]];
    }
    var _br = _body[_m - 1][0];
    _body[_m++] = [_br * 0.70, _uy - _h * 0.030];
    _body[_m++] = [0, _uy - _h * 0.060];
    hall_lathe(_vb, 0, 0, 0, _body, HALL_GLASS_SEG, spr_hall_pale, 0, 1, 0,
               HALL_SAND, _c * 0.92, 0.18, hall_no_light);

    // and the thread between them
    hall_lathe(_vb, 0, 0, 0, [[1.5, _sy + _h * 0.10], [1.1, 0]], 6,
               spr_hall_pale, 0, 1, 0, HALL_SAND, _c * 1.25, 0.10,
               hall_no_light);
}

/// @desc The armillary's spindle: a rod pointed at both ends with collars.
///       It doesn't turn.
function hall_fill_arm_axis(_vb) {
    var _h = HALL_ARM_R * 1.34;
    var _c = HALL_PROP_LIGHT * 1.25;
    hall_lathe(_vb, 0, 0, 0,
               [[0, -_h], [2.2, -_h * 0.86], [2.2, -_h * 0.60],
                [4.0, -_h * 0.54], [2.2, -_h * 0.48], [2.2, _h * 0.48],
                [4.0, _h * 0.54], [2.2, _h * 0.60], [2.2, _h * 0.86],
                [0, _h]],
               8, spr_hall_pale, 0, 1, 0, HALL_GILT, _c, 0.28, hall_no_light);
}

/// @desc One armillary ring, with its tilt and a fixed yaw baked in.
function hall_fill_arm_ring(_vb, _tilt, _yaw, _w, _face) {
    hall_ring(_vb, 0, 0, 0, HALL_ARM_R, _w, _tilt, _yaw, 20,
              spr_hall_pale, 0, 1, 0, HALL_GILT,
              HALL_PROP_LIGHT * _face, hall_no_light);
}

/// @desc Build both instruments, once.
function hall_build_instruments(_b) {
    var _f = hall_format();
    _b.inst = {
        glass: hall_prop_buffer(_f, hall_fill_glass),
        frame: hall_prop_buffer(_f, hall_fill_glass_frame),
        sand:  hall_prop_buffer(_f, hall_fill_sand),
        axis:  hall_prop_buffer(_f, hall_fill_arm_axis),
        // Kept dim: brighter, the additive sphere clipped to a white dot.
        core:  hall_prop_buffer(_f, function(_vb) {
                   hall_sphere(_vb, 0, 0, 0, HALL_ARM_CORE, 10, 6,
                               spr_hall_pale, 0, 1, 0, HALL_ORB_COL,
                               HALL_PROP_LIGHT * 0.38, hall_no_light);
               }),
        // Each ring has its own tilt and rate (the horizontal equator is
        // still), plus a fixed yaw offset so the rings don't all turn
        // edge-on at the same moment.
        ring: [
            { vb: hall_prop_buffer(_f, function(_vb) {
                      hall_fill_arm_ring(_vb, 90, 0, 3.6, 1.10); }),
              rate: 0 },
            { vb: hall_prop_buffer(_f, function(_vb) {
                      hall_fill_arm_ring(_vb, 28, 0, 3.6, 1.25); }),
              rate: 0.41 },
            { vb: hall_prop_buffer(_f, function(_vb) {
                      hall_fill_arm_ring(_vb, 64, 52, 3.0, 0.98); }),
              rate: -0.27 },
            { vb: hall_prop_buffer(_f, function(_vb) {
                      hall_fill_arm_ring(_vb, 46, 104, 2.6, 0.88); }),
              rate: 0.17 },
        ],
    };
}

/// @desc Which side a pedestal bay's instrument is on (-1 or 1). Used by the
///       pedestal at build time and the instrument at draw time.
function hall_inst_side(_v) {
    return (_v == 3) ? 1 : -1;
}

/// @desc The world matrix for bay `_i`'s instrument, with a bob phased per bay.
function hall_inst_matrix(_b, _i, _v, _spin) {
    var _ph = _b.t * 360 / HALL_INST_BOB_P + _i * 63;
    return matrix_build(hall_inst_side(_v) * HALL_DESK_X,
                        HALL_DESK_TOP + HALL_INST_Y
                            + HALL_INST_BOB * dsin(_ph),
                        _i * HALL_BAY_Z + HALL_BAY_Z * 0.5,
                        0, _spin, 0, 1, 1, 1);
}

/// @desc Draw the instruments in view. Called in the solid pass (metal, sand)
///       with `_lit` false, and in the light pass (glass, the armillary's
///       core) with `_lit` true.
function hall_draw_instruments(_b, _b0, _b1, _lit) {
    var _t = sprite_get_texture(spr_hall_pale, 0);
    for (var _i = _b1; _i >= _b0; _i--) {
        var _v = hall_prop_variant(_i);
        if (_v < 2) continue;

        if (_v == 2) {
            matrix_set(matrix_world,
                       hall_inst_matrix(_b, _i, _v, _b.t * HALL_INST_SPIN));
            if (_lit) {
                hall_submit(_b.inst.glass, _t);
            } else {
                hall_submit(_b.inst.sand, _t);
                hall_submit(_b.inst.frame, _t);
            }
            continue;
        }

        var _base = hall_inst_matrix(_b, _i, _v, 0);
        matrix_set(matrix_world, _base);
        if (_lit) {
            hall_submit(_b.inst.core, _t);
            continue;
        }
        hall_submit(_b.inst.axis, _t);
        var _n = array_length(_b.inst.ring);
        for (var _k = 0; _k < _n; _k++) {
            var _r = _b.inst.ring[_k];
            matrix_set(matrix_world,
                       matrix_multiply(matrix_build(0, 0, 0, 0,
                                                    _b.t * _r.rate, 0,
                                                    1, 1, 1), _base));
            hall_submit(_r.vb, _t);
        }
    }
}

/// @desc Draw the props in view, far to near, with depth writing and the alpha
///       test on (so cut-out corners don't write depth). The alpha test is
///       done in `sh_hall` on the texture's alpha, so a prop fading with
///       distance doesn't become a hard cut.
function hall_draw_props(_b, _b0, _b1) {
    hall_pass_solid(HALL_ALPHA_REF);

    for (var _i = _b1; _i >= _b0; _i--) {
        var _p = _b.prop[hall_prop_variant(_i)];
        matrix_set(matrix_world,
                   matrix_build(0, 0, _i * HALL_BAY_Z, 0, 0, 0, 1, 1, 1));
        hall_submit(_p.stone, sprite_get_texture(spr_hall_stone, 0));
        hall_submit(_p.plinth, sprite_get_texture(spr_hall_plinth, 0));
        hall_submit(_p.deskface, sprite_get_texture(spr_hall_deskface, 0));
        hall_submit(_p.gilt, sprite_get_texture(spr_hall_pale, 0));
        hall_submit(_p.statue, sprite_get_texture(spr_hall_bastet, 0));
        hall_submit_frames(_p.banner, spr_hall_banner);
    }

    // The instruments' solid parts.
    hall_draw_instruments(_b, _b0, _b1, false);

    // Then the glows and rims, additive (depth-tested, not written).
    hall_pass_light();
    for (var _i = _b1; _i >= _b0; _i--) {
        var _p = _b.prop[hall_prop_variant(_i)];
        matrix_set(matrix_world,
                   matrix_build(0, 0, _i * HALL_BAY_Z, 0, 0, 0, 1, 1, 1));
        hall_submit(_p.glow, sprite_get_texture(spr_hall_pale, 0));
        hall_submit(_p.statue_rim,
                    sprite_get_texture(spr_hall_bastet_rim, 0));
    }
    hall_draw_instruments(_b, _b0, _b1, true);
    hall_pass_solid();
}

// ---------------------------------------------------------------------------
// The sky: a dome centred on the camera (it turns with the view but never
// translates, so it reads as infinitely far), drawn first with depth testing
// off. Below the horizon it is `HALL_FOG`, so the far end of the hall fades
// into it without a line. Stars, nebulae and constellations all come from
// `hall_hash`, so the sky is the same every attempt.
// ---------------------------------------------------------------------------

/// @desc Smoothstep.
function hall_ease(_t) {
    var _k = clamp(_t, 0, 1);
    return _k * _k * (3 - 2 * _k);
}

/// @desc A unit direction from an azimuth and an elevation, both in degrees.
function hall_dir(_az, _el) {
    var _c = dcos(_el);
    return [_c * dcos(_az), dsin(_el), _c * dsin(_az)];
}

/// @desc Star `_i`'s direction: a share (`HALL_STAR_BAND`) lie near one tilted
///       great circle (a band, like the Milky Way), the rest spread evenly by
///       area over the hemisphere (`darcsin` of a uniform value).
function hall_star_dir(_i) {
    if (hall_hash(_i, 72) < HALL_STAR_BAND) {
        // On the band: a point near the equator, then tilted.
        var _u = hall_hash(_i, 73) * 360;
        var _v = (hall_hash(_i, 74) * 2 - 1) * HALL_STAR_BAND_W;
        var _d = hall_dir(_u, _v);
        var _t = HALL_STAR_BAND_TILT;
        return [_d[0], _d[1] * dcos(_t) - _d[2] * dsin(_t),
                _d[1] * dsin(_t) + _d[2] * dcos(_t)];
    }
    return hall_dir(hall_hash(_i, 71) * 360, darcsin(hall_hash(_i, 70)));
}

/// @desc 0..1: how visible a star is at elevation `_el`. Stars near the
///       horizon fade out (as the hall fogs out), ramping over the band of
///       elevations actually visible in frame.
function hall_star_extinction(_el) {
    return hall_ease((_el - HALL_STAR_EL0) / (HALL_STAR_EL1 - HALL_STAR_EL0));
}

/// @desc The sky colour at elevation `_el`: `HALL_FOG` at and below the
///       horizon, easing to `HALL_SKY_LOW` then `HALL_SKY_HIGH` (blues at a
///       similar value, not a darkened fog, which came out grey).
function hall_sky_col(_el) {
    if (_el <= 0) return HALL_FOG;
    if (_el < HALL_SKY_LOW_EL) {
        return merge_colour(HALL_FOG, HALL_SKY_LOW,
                            hall_ease(_el / HALL_SKY_LOW_EL));
    }
    return merge_colour(HALL_SKY_LOW, HALL_SKY_HIGH,
                        hall_ease((_el - HALL_SKY_LOW_EL)
                                  / (HALL_SKY_HIGH_EL - HALL_SKY_LOW_EL)));
}

/// @desc One quad of the dome, each corner coloured by its elevation.
function hall_dome_quad(_vb, _a0, _a1, _e0, _e1) {
    var _p = [hall_dir(_a0, _e1), hall_dir(_a1, _e1),
              hall_dir(_a1, _e0), hall_dir(_a0, _e0)];
    var _c = [hall_sky_col(_e1), hall_sky_col(_e1),
              hall_sky_col(_e0), hall_sky_col(_e0)];
    var _q = [hall_uv(spr_hall_pale, 0, 0, 0), hall_uv(spr_hall_pale, 0, 1, 0),
              hall_uv(spr_hall_pale, 0, 1, 1), hall_uv(spr_hall_pale, 0, 0, 1)];
    var _order = [0, 1, 2, 0, 2, 3];
    for (var _i = 0; _i < 6; _i++) {
        var _j = _order[_i];
        vertex_position_3d(_vb, _p[_j][0] * HALL_SKY_R,
                           _p[_j][1] * HALL_SKY_R, _p[_j][2] * HALL_SKY_R);
        vertex_colour(_vb, _c[_j], 1);
        vertex_texcoord(_vb, _q[_j][0], _q[_j][1]);
    }
}

/// @desc The dome.
function hall_fill_dome(_vb) {
    for (var _j = 0; _j < HALL_SKY_ROWS; _j++) {
        var _e0 = lerp(HALL_SKY_EL0, 90, _j / HALL_SKY_ROWS);
        var _e1 = lerp(HALL_SKY_EL0, 90, (_j + 1) / HALL_SKY_ROWS);
        for (var _i = 0; _i < HALL_SKY_COLS; _i++) {
            hall_dome_quad(_vb, 360 * _i / HALL_SKY_COLS,
                           360 * (_i + 1) / HALL_SKY_COLS, _e0, _e1);
        }
    }
}

/// @desc A flat card of half-size `_r` tangent to the dome at direction `_d`.
///       Built facing the centre (the camera never rolls), so the whole sky is
///       one frozen buffer.
function hall_sky_card(_vb, _d, _r, _spr, _frame, _col, _a, _dist) {
    // Two axes across the line of sight (a different up vector near the pole,
    // where the cross product degenerates).
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
    hall_face(_vb, _spr, _frame, 1,
              [_px - _rx * _r + _ux * _r, _py - _ry * _r + _uy * _r,
               _pz - _rz * _r + _uz * _r],
              [_px + _rx * _r + _ux * _r, _py + _ry * _r + _uy * _r,
               _pz + _rz * _r + _uz * _r],
              [_px + _rx * _r - _ux * _r, _py + _ry * _r - _uy * _r,
               _pz + _rz * _r - _uz * _r],
              [_px - _rx * _r - _ux * _r, _py - _ry * _r - _uy * _r,
               _pz - _rz * _r - _uz * _r],
              _col, _a);
}

/// @desc A star's colour: mostly cool white, a few warm.
function hall_star_col(_i) {
    var _h = hall_hash(_i, 76);
    if (_h > 0.94) return make_colour_rgb(255, 182, 132);
    if (_h > 0.84) return make_colour_rgb(255, 226, 180);
    if (_h > 0.46) return make_colour_rgb(244, 246, 255);
    return make_colour_rgb(198, 216, 255);
}

/// @desc Star `_i`'s magnitude class: 0 faint (including every band star),
///       1 or 2 bright. Constellations are drawn between bright stars.
function hall_star_mag(_i) {
    if (hall_hash(_i, 72) < HALL_STAR_BAND) return 0;   // the band is faint
    var _m = hall_hash(_i, 75);
    if (_m > 0.962) return 2;
    if (_m > 0.800) return 1;
    return 0;
}

/// @desc Every star as a card, into its magnitude's buffer (one per frame).
function hall_fill_stars(_bufs) {
    for (var _i = 0; _i < HALL_STARS; _i++) {
        var _d = hall_star_dir(_i);
        var _el = darcsin(clamp(_d[1], -1, 1));
        var _ex = hall_star_extinction(_el);
        if (_ex <= 0.002) continue;
        var _g = hall_star_mag(_i);
        var _sz = HALL_STAR_SIZE * (_g == 2 ? 2.05 : (_g == 1 ? 1.0 : 0.62));
        _sz *= 0.78 + hall_hash(_i, 77) * 0.5;
        var _a = (_g == 2 ? 0.88 : (_g == 1 ? 0.60 : 0.36))
                 * (0.7 + hall_hash(_i, 78) * 0.5) * _ex;
        hall_sky_card(_bufs[_g], _d, _sz, spr_hall_star, _g,
                      hall_star_col(_i), _a, HALL_SKY_R * 0.96);
    }
}

/// @desc The nebulae: soft additive patches at a few per cent.
function hall_fill_neb(_bufs) {
    // Mostly blue, with a little violet and teal.
    var _cols = [make_colour_rgb(62, 104, 226), make_colour_rgb(48, 138, 196),
                 make_colour_rgb(62, 104, 226), make_colour_rgb(128, 78, 196),
                 make_colour_rgb(62, 104, 226), make_colour_rgb(46, 150, 158)];
    for (var _i = 0; _i < HALL_NEB_N; _i++) {
        // Placed within `HALL_SKY_SPREAD` of straight ahead and low in the
        // sky, where the camera looks (spread over the whole sphere, almost
        // none were on screen).
        var _d = hall_dir(90 + (hall_hash(_i, 81) * 2 - 1) * HALL_SKY_SPREAD,
                          3 + hall_hash(_i, 82) * 34);
        var _ang = HALL_NEB_R0 - hall_hash(_i, 83) * HALL_NEB_R1;
        var _r = HALL_SKY_R * dtan(_ang * 0.5);
        var _c = _cols[floor(hall_hash(_i, 84) * 6) % 6];
        var _a = HALL_NEB_A * (0.45 + hall_hash(_i, 85) * 0.75)
                 * hall_star_extinction(darcsin(clamp(_d[1], -1, 1)));
        var _fr = floor(hall_hash(_i, 86) * 3) % 3;
        hall_sky_card(_bufs[_fr], _d, _r, spr_hall_neb, _fr, _c, _a,
                      HALL_SKY_R * 0.99);
    }
}

/// @desc One constellation line: a thin ribbon across the line of sight.
function hall_const_line(_vb, _d0, _d1, _col, _a) {
    var _p0 = [_d0[0] * HALL_SKY_R * 0.95, _d0[1] * HALL_SKY_R * 0.95,
               _d0[2] * HALL_SKY_R * 0.95];
    var _p1 = [_d1[0] * HALL_SKY_R * 0.95, _d1[1] * HALL_SKY_R * 0.95,
               _d1[2] * HALL_SKY_R * 0.95];
    var _ax = _p1[0] - _p0[0], _ay = _p1[1] - _p0[1], _az = _p1[2] - _p0[2];
    // Across the line of sight: the segment crossed with the radius.
    var _wx = _ay * _d0[2] - _az * _d0[1];
    var _wy = _az * _d0[0] - _ax * _d0[2];
    var _wz = _ax * _d0[1] - _ay * _d0[0];
    var _l = max(0.0001, sqrt(_wx * _wx + _wy * _wy + _wz * _wz));
    var _h = HALL_SKY_R * 0.0021;
    _wx = _wx / _l * _h; _wy = _wy / _l * _h; _wz = _wz / _l * _h;
    hall_face(_vb, spr_hall_pale, 0, 1,
              [_p0[0] + _wx, _p0[1] + _wy, _p0[2] + _wz],
              [_p1[0] + _wx, _p1[1] + _wy, _p1[2] + _wz],
              [_p1[0] - _wx, _p1[1] - _wy, _p1[2] - _wz],
              [_p0[0] - _wx, _p0[1] - _wy, _p0[2] - _wz],
              _col, _a);
}

/// @desc Constellations: for each seed direction (near straight ahead, like
///       the nebulae), lines joining the four bright stars nearest it.
function hall_fill_const(_vb) {
    var _col = make_colour_rgb(150, 178, 255);

    // Gather the visible bright stars once (checking every star for every
    // figure was slow enough to hitch the stage's first frame).
    var _dirs = [];
    var _n = 0;
    for (var _i = 0; _i < HALL_STARS; _i++) {
        if (hall_star_mag(_i) < 1) continue;
        var _d = hall_star_dir(_i);
        if (hall_star_extinction(darcsin(clamp(_d[1], -1, 1))) < 0.5) continue;
        _dirs[_n] = _d;
        _n++;
    }
    if (_n < 4) return;

    for (var _c = 0; _c < HALL_CONST_N; _c++) {
        var _sd = hall_dir(90 + (hall_hash(_c, 201) * 2 - 1) * HALL_SKY_SPREAD,
                           8 + hall_hash(_c, 202) * 26);
        var _pick = [-1, -1, -1, -1];
        var _dot = [-2, -2, -2, -2];
        for (var _i = 0; _i < _n; _i++) {
            var _d = _dirs[_i];
            var _v = _d[0] * _sd[0] + _d[1] * _sd[1] + _d[2] * _sd[2];
            for (var _k = 0; _k < 4; _k++) {
                if (_v > _dot[_k]) {
                    for (var _m = 3; _m > _k; _m--) {
                        _dot[_m] = _dot[_m - 1];
                        _pick[_m] = _pick[_m - 1];
                    }
                    _dot[_k] = _v;
                    _pick[_k] = _i;
                    break;
                }
            }
        }
        for (var _k = 0; _k < 3; _k++) {
            if (_pick[_k] < 0 || _pick[_k + 1] < 0) continue;
            hall_const_line(_vb, _dirs[_pick[_k]], _dirs[_pick[_k + 1]],
                            _col, HALL_CONST_A);
        }
    }
}

/// @desc Build the sky and the far chamber.
function hall_build_sky(_b) {
    var _f = hall_format();
    _b.vb_dome = hall_prop_buffer(_f, hall_fill_dome);
    _b.vb_neb = hall_frames_buffer(spr_hall_neb, _f, hall_fill_neb);
    _b.vb_const = hall_prop_buffer(_f, hall_fill_const);
    _b.vb_stars = hall_frames_buffer(spr_hall_star, _f, hall_fill_stars);
    _b.vb_rot = hall_prop_buffer(_f, hall_fill_rotunda);
    _b.vb_rot_lit = hall_prop_buffer(_f, hall_fill_rotunda_lit);
}

/// @desc Draw the sky: the world matrix is the camera's position, and depth
///       testing and writing are off.
function hall_draw_sky(_b) {
    gpu_set_ztestenable(false);
    gpu_set_zwriteenable(false);
    gpu_set_fog(false, c_black, 0, 1);
    matrix_set(matrix_world,
               matrix_build(_b.cam_x, _b.cam_y, hall_cam_z(_b),
                            0, 0, 0, 1, 1, 1));
    hall_submit(_b.vb_dome, sprite_get_texture(spr_hall_pale, 0));

    // Nebulae, constellations and stars, additive.
    gpu_set_blendmode(bm_add);
    hall_submit_frames(_b.vb_neb, spr_hall_neb);
    hall_submit(_b.vb_const, sprite_get_texture(spr_hall_pale, 0));
    hall_submit_frames(_b.vb_stars, spr_hall_star);
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The chamber at the end of the hall: one painted quad (`spr_hall_rot`) at a
// fixed distance ahead of the camera, so the flight never reaches it. Drawn
// right after the sky with depth testing off, so it covers the stars and
// everything nearer draws over it. See `rotunda` in `tools/make_sanctum.py`
// for the painting's projection.
// ---------------------------------------------------------------------------

/// @desc The far chamber, as a quad in the plane z = 0.
function hall_fill_rotunda(_vb) {
    var _w = HALL_ROT_HW;
    var _h = HALL_ROT_HH;
    var _cy = HALL_ROT_Y0 + _h;
    hall_face(_vb, spr_hall_rot, 0, 1,
              [-_w, _cy + _h, 0], [_w, _cy + _h, 0],
              [_w, _cy - _h, 0], [-_w, _cy - _h, 0], HALL_ROT_COL, HALL_ROT_A);
}

/// @desc ...and its lamps, drawn additively over it.
function hall_fill_rotunda_lit(_vb) {
    var _w = HALL_ROT_HW;
    var _h = HALL_ROT_HH;
    var _cy = HALL_ROT_Y0 + _h;
    hall_face(_vb, spr_hall_rot_lit, 0, 1,
              [-_w, _cy + _h, 0], [_w, _cy + _h, 0],
              [_w, _cy - _h, 0], [-_w, _cy - _h, 0],
              HALL_ROT_LIT, HALL_ROT_LIT_A);
}

/// @desc Draw the chamber `HALL_ROT_Z` ahead of the camera: past the last bay
///       drawn and inside the far plane.
function hall_draw_far(_b) {
    gpu_set_ztestenable(false);
    gpu_set_zwriteenable(false);
    gpu_set_fog(false, c_black, 0, 1);
    matrix_set(matrix_world,
               matrix_build(0, 0, hall_cam_z(_b) + HALL_ROT_Z,
                            0, 0, 0, 1, 1, 1));
    hall_submit(_b.vb_rot, sprite_get_texture(spr_hall_rot, 0));
    gpu_set_blendmode(bm_add);
    hall_submit(_b.vb_rot_lit, sprite_get_texture(spr_hall_rot_lit, 0));
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The grand orrery: an armillary hanging above the far end of the hall at a
// fixed distance from the camera (never reached). Real geometry so its rings
// can turn; each ring is a frozen buffer drawn under its own rotation.
// ---------------------------------------------------------------------------

/// @desc A point rotated by `_tilt` about x, then `_yaw` about y.
function hall_orient(_x, _y, _z, _tilt, _yaw) {
    var _y2 = _y * dcos(_tilt) - _z * dsin(_tilt);
    var _z2 = _y * dsin(_tilt) + _z * dcos(_tilt);
    return [_x * dcos(_yaw) + _z2 * dsin(_yaw), _y2,
            -_x * dsin(_yaw) + _z2 * dcos(_yaw)];
}

/// @desc One quad showing the span `_u0`..`_u1` of its sprite (so a graduated
///       band can repeat a set number of times round a ring).
function hall_face_u(_vb, _spr, _l, _p0, _p1, _p2, _p3, _u0, _u1, _col) {
    var _q = [hall_uv(_spr, 0, _u0, 0), hall_uv(_spr, 0, _u1, 0),
              hall_uv(_spr, 0, _u1, 1), hall_uv(_spr, 0, _u0, 1)];
    var _p = [_p0, _p1, _p2, _p3];
    var _c = hall_shade(_col, _l);
    var _order = [0, 1, 2, 0, 2, 3];
    for (var _i = 0; _i < 6; _i++) {
        var _j = _order[_i];
        vertex_position_3d(_vb, _p[_j][0], _p[_j][1], _p[_j][2]);
        vertex_colour(_vb, _c, 1);
        vertex_texcoord(_vb, _q[_j][0], _q[_j][1]);
    }
}

/// @desc A ring of square section in its own plane, centred on the origin.
///       Four faces per segment, so it narrows to a line edge-on instead of
///       vanishing. `_reps` is how many times the sprite repeats round it.
function hall_torus(_vb, _R, _w, _t, _tilt, _yaw, _n, _reps, _spr, _col, _l) {
    var _per = max(1, _n div _reps);
    for (var _i = 0; _i < _n; _i++) {
        var _a0 = 360 * _i / _n, _a1 = 360 * (_i + 1) / _n;
        var _p = array_create(8);
        var _k = 0;
        for (var _ai = 0; _ai < 2; _ai++) {
            var _a = (_ai == 0) ? _a0 : _a1;
            for (var _ri = 0; _ri < 2; _ri++) {
                var _rr = (_ri == 0) ? (_R + _w) : (_R - _w);
                for (var _zi = 0; _zi < 2; _zi++) {
                    _p[_k] = hall_orient(dcos(_a) * _rr, dsin(_a) * _rr,
                                         (_zi == 0) ? _t : -_t, _tilt, _yaw);
                    _k++;
                }
            }
        }
        var _s0 = (_i mod _per) / _per;
        var _s1 = ((_i mod _per) + 1) / _per;
        // the two faces, then the two rims
        hall_face_u(_vb, _spr, _l, _p[0], _p[4], _p[6], _p[2], _s0, _s1, _col);
        hall_face_u(_vb, _spr, _l * 0.54, _p[1], _p[5], _p[7], _p[3],
                    _s0, _s1, _col);
        hall_face_u(_vb, _spr, _l * 1.2, _p[0], _p[4], _p[5], _p[1],
                    _s0, _s1, _col);
        hall_face_u(_vb, _spr, _l * 0.44, _p[2], _p[6], _p[7], _p[3],
                    _s0, _s1, _col);
    }
}

/// @desc A faceted ball lit by a fixed factor rather than the hall's lamps
///       (which don't reach this far). `_sy` squashes it vertically.
function hall_ball(_vb, _cx, _cy, _cz, _r, _nu, _nv, _spr, _col, _l, _sy = 1) {
    for (var _i = 0; _i < _nu; _i++) {
        for (var _j = 0; _j < _nv; _j++) {
            var _a0 = 360 * _i / _nu, _a1 = 360 * (_i + 1) / _nu;
            var _q0 = -90 + 180 * _j / _nv, _q1 = -90 + 180 * (_j + 1) / _nv;
            var _sp = [[_a0, _q1], [_a1, _q1], [_a1, _q0], [_a0, _q0]];
            var _v = [];
            for (var _k = 0; _k < 4; _k++) {
                var _ca = dcos(_sp[_k][1]);
                _v[_k] = [_cx + _r * _ca * dcos(_sp[_k][0]),
                          _cy + _r * _sy * dsin(_sp[_k][1]),
                          _cz + _r * _ca * dsin(_sp[_k][0])];
            }
            hall_face(_vb, _spr, 0, _l * (0.58 + 0.58 * (0.5 + 0.5
                      * dsin(_q1))), _v[0], _v[1], _v[2], _v[3], _col, 1);
        }
    }
}

/// @desc A cone on the y axis: base radius `_r` at `_y0`, apex at `_y1`.
function hall_cone(_vb, _cx, _y0, _y1, _cz, _r, _n, _spr, _col, _l) {
    for (var _i = 0; _i < _n; _i++) {
        var _a0 = 360 * _i / _n, _a1 = 360 * (_i + 1) / _n;
        var _p0 = [_cx + dcos(_a0) * _r, _y0, _cz + dsin(_a0) * _r];
        var _p1 = [_cx + dcos(_a1) * _r, _y0, _cz + dsin(_a1) * _r];
        var _ap = [_cx, _y1, _cz];
        // one facet per segment, lit by which way it faces
        hall_face(_vb, _spr, 0, _l * (0.56 + 0.62 * (0.5 + 0.5 * dcos(_a0))),
                  _ap, _ap, _p1, _p0, _col, 1);
    }
}

/// @desc One orrery ring as a frozen buffer, with its rotation rate.
function hall_orrery_ring(_R, _w, _t, _tilt, _yaw, _n, _reps, _spr, _col,
                          _l, _rate) {
    var _f = hall_format();
    var _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    hall_torus(_vb, _R, _w, _t, _tilt, _yaw, _n, _reps, _spr, _col, _l);
    vertex_end(_vb);
    vertex_freeze(_vb);
    return { vb: _vb, spr: _spr, rate: _rate };
}

/// @desc A ball on a ring, built in the ring's frame and given the same rate
///       so it rides with it (a separate buffer because it uses a different
///       texture).
function hall_orrery_body(_R, _ang, _tilt, _yaw, _r, _col, _l, _rate) {
    var _f = hall_format();
    var _vb = vertex_create_buffer();
    vertex_begin(_vb, _f);
    var _p = hall_orient(dcos(_ang) * _R, dsin(_ang) * _R, 0, _tilt, _yaw);
    hall_ball(_vb, _p[0], _p[1], _p[2], _r, 10, 7, spr_hall_pale, _col, _l);
    vertex_end(_vb);
    vertex_freeze(_vb);
    return { vb: _vb, spr: spr_hall_pale, rate: _rate };
}

/// @desc Build the orrery: six rings with different tilts and rates (the outer
///       limb doesn't turn), three bodies, the core and armature, its glow and
///       a halo.
function hall_build_orrery(_b) {
    var _R = HALL_ORRERY_R;
    var _pa = spr_hall_pale;
    var _zo = spr_hall_zodiac;
    var _g = HALL_ORRERY_GILT;
    var _l = HALL_ORRERY_DIM;

    _b.orrery = [
        // the limb: face-on, graduated, and still
        hall_orrery_ring(_R, _R * 0.030, _R * 0.011, 0, 0, 40, 2, _zo, _g,
                         _l * 1.12, 0),
        // the ecliptic, at the angle the real one is off the equator
        hall_orrery_ring(_R * 0.90, _R * 0.024, _R * 0.010, 23.4, 0, 36, 2,
                         _zo, _g, _l * 1.0, 0.031),
        hall_orrery_ring(_R * 0.76, _R * 0.014, _R * 0.009, 74, 0, 32, 1, _pa,
                         _g, _l * 0.94, -0.052),
        hall_orrery_ring(_R * 0.60, _R * 0.012, _R * 0.008, -46, 18, 32, 1,
                         _pa, _g, _l * 0.88, 0.079),
        hall_orrery_ring(_R * 0.43, _R * 0.010, _R * 0.007, 86, 0, 28, 1, _pa,
                         _g, _l * 0.82, -0.116),
        hall_orrery_ring(_R * 0.27, _R * 0.009, _R * 0.006, 34, 62, 24, 1,
                         _pa, _g, _l * 0.76, 0.167),

        // ...and the bodies riding on three of them
        hall_orrery_body(_R * 0.76, 20, 74, 0, _R * 0.045,
                         make_colour_rgb(198, 206, 232), _l * 1.05, -0.052),
        hall_orrery_body(_R * 0.60, 210, -46, 18, _R * 0.058,
                         make_colour_rgb(226, 168, 98), _l * 1.05, 0.079),
        hall_orrery_body(_R * 0.43, 118, 86, 0, _R * 0.036,
                         make_colour_rgb(150, 205, 255), _l * 1.15, -0.116),
    ];

    var _f = hall_format();
    _b.vb_orrery_core = hall_prop_buffer(_f, hall_fill_orrery_core);
    _b.vb_orrery_glow = hall_prop_buffer(_f, hall_fill_orrery_glow);
    _b.vb_orrery_halo = hall_prop_buffer(_f, hall_fill_orrery_halo);
}

/// @desc The orrery's core and armature: a polar axis through the rings, a
///       pointed finial above and a longer plumb below, collars along the
///       shaft, and lens-shaped glass bubbles.
function hall_fill_orrery_core(_vb) {
    var _R = HALL_ORRERY_R;
    var _g = HALL_ORRERY_GILT;
    var _l = HALL_ORRERY_DIM;
    var _pa = spr_hall_pale;

    // The core is blue; driven brighter it clipped to a white blob.
    hall_ball(_vb, 0, 0, 0, _R * 0.105, 14, 9, _pa, HALL_ORRERY_CORE,
              _l * 1.05);

    // The polar axis, as two crossed blades so it reads from any angle.
    for (var _e = -1; _e <= 1; _e += 2) {
        var _y0 = _R * 0.07 * _e;
        var _y1 = _R * ((_e > 0) ? 1.10 : 1.46) * _e;
        var _w = _R * 0.011;
        hall_face(_vb, _pa, 0, _l * 1.1,
                  [-_w, _y1, 0], [_w, _y1, 0], [_w, _y0, 0], [-_w, _y0, 0],
                  _g, 1);
        hall_face(_vb, _pa, 0, _l * 0.7,
                  [0, _y1, -_w], [0, _y1, _w], [0, _y0, _w], [0, _y0, -_w],
                  _g, 1);
    }
    // the finial above and the plumb below, both pointed
    hall_cone(_vb, 0, _R * 1.10, _R * 1.30, 0, _R * 0.034, 8, _pa, _g,
              _l * 1.25);
    hall_cone(_vb, 0, -_R * 1.46, -_R * 1.82, 0, _R * 0.052, 8, _pa, _g,
              _l * 1.25);

    // Collars along the shaft.
    var _beads = [0.40, 0.80, -0.40, -0.86, -1.22];
    for (var _i = 0; _i < array_length(_beads); _i++) {
        hall_ball(_vb, 0, _R * _beads[_i], 0, _R * 0.036, 10, 6, _pa, _g,
                  _l * 1.15, 0.62);
    }

    // The glass bubbles, in a cool light blue so they read as glass against
    // the gold.
    var _bub = [[0.66, 0.115], [-0.60, 0.135], [-1.04, 0.100]];
    for (var _i = 0; _i < array_length(_bub); _i++) {
        hall_ball(_vb, 0, _R * _bub[_i][0], 0, _R * _bub[_i][1], 12, 7, _pa,
                  make_colour_rgb(176, 208, 244), _l * 1.2, 0.54);
    }
}

/// @desc The orrery's glow: a larger sphere over the core, and one on each
///       bubble.
function hall_fill_orrery_glow(_vb) {
    var _R = HALL_ORRERY_R;
    hall_ball(_vb, 0, 0, 0, _R * 0.17, 12, 8, spr_hall_pale,
              HALL_ORRERY_CORE, 0.30);
    var _bub = [[0.66, 0.115], [-0.60, 0.135], [-1.04, 0.100]];
    for (var _i = 0; _i < array_length(_bub); _i++) {
        hall_ball(_vb, 0, _R * _bub[_i][0], 0, _R * _bub[_i][1] * 1.25, 10, 6,
                  spr_hall_pale, HALL_ORRERY_CORE, 0.16, 0.54);
    }
}

/// @desc The halo behind the orrery: one bloom card.
function hall_fill_orrery_halo(_vb) {
    var _r = HALL_ORRERY_HALO_R;
    hall_face(_vb, spr_fx_bloom, 0, 1,
              [-_r, _r, 0], [_r, _r, 0], [_r, -_r, 0], [-_r, -_r, 0],
              HALL_ORRERY_CORE, HALL_ORRERY_HALO_A);
}

/// @desc Draw the orrery. Depth-tested and depth-written (so its rings sort
///       against each other), with fog off: at this distance hardware fog
///       would be total, so its dimming is baked into its colours. It pulses
///       by scale, since a frozen buffer's alpha is fixed.
function hall_draw_orrery(_b) {
    var _oz = hall_cam_z(_b) + HALL_ORRERY_Z;
    var _base = matrix_build(0, HALL_ORRERY_Y, _oz, 0, 0, 0, 1, 1, 1);
    var _pulse = 1 + 0.055 * dsin(_b.t * 360 / HALL_ORRERY_PULSE);

    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(false);
    gpu_set_fog(false, c_black, 0, 1);

    // The halo first, behind the metal.
    gpu_set_blendmode(bm_add);
    matrix_set(matrix_world,
               matrix_build(0, HALL_ORRERY_Y, _oz + HALL_ORRERY_R, 0, 0, 0,
                            _pulse, _pulse, 1));
    hall_submit(_b.vb_orrery_halo, sprite_get_texture(spr_fx_bloom, 0));
    gpu_set_blendmode(bm_normal);

    gpu_set_zwriteenable(true);
    matrix_set(matrix_world, _base);
    hall_submit(_b.vb_orrery_core, sprite_get_texture(spr_hall_pale, 0));

    var _n = array_length(_b.orrery);
    for (var _i = 0; _i < _n; _i++) {
        var _r = _b.orrery[_i];
        matrix_set(matrix_world,
                   matrix_multiply(matrix_build(0, 0, 0, 0, _b.t * _r.rate, 0,
                                                1, 1, 1), _base));
        hall_submit(_r.vb, sprite_get_texture(_r.spr, 0));
    }

    // Then the core's glow over everything.
    gpu_set_zwriteenable(false);
    gpu_set_blendmode(bm_add);
    matrix_set(matrix_world,
               matrix_build(0, HALL_ORRERY_Y, _oz, 0, 0, 0,
                            _pulse, _pulse, _pulse));
    hall_submit(_b.vb_orrery_glow, sprite_get_texture(spr_hall_pale, 0));
    gpu_set_blendmode(bm_normal);
    gpu_set_zwriteenable(true);
}

/// @desc `frac` folded into [0, 1) (GML's `frac` keeps the sign, which matters
///       when a value is decreasing, as the sand's depth is).
function hall_wrap01(_v) {
    var _f = frac(_v);
    return (_f < 0) ? _f + 1 : _f;
}

/// @desc The camera, packed for projecting points by hand (the hall's camera
///       never yaws: a translation and a pitch). `_back` moves the eye back
///       down the hall, for projecting a grain where it was a few frames ago.
function hall_eye(_b, _x0, _y0, _w, _h, _back) {
    return {
        x: _b.cam_x, y: _b.cam_y, z: _b.dist - _back,
        cp: dcos(_b.pitch), sp: dsin(_b.pitch),
        foc: (_h * 0.5) / dtan(HALL_FOV * 0.5),
        mx: _x0 + _w * 0.5, my: _y0 + _h * 0.5,
    };
}

/// @desc Project a world point to the screen as `[x, y, scale]`, or
///       `undefined` if it is behind the eye. The same projection the hall is
///       drawn with, done in GML for the sand, which is drawn in the 2D front
///       pass after the 3D state has been reset.
function hall_project(_e, _wx, _wy, _wz) {
    var _dy = _wy - _e.y;
    var _dz = _wz - _e.z;
    var _vz = _dy * _e.sp + _dz * _e.cp;
    if (_vz < HALL_SAND_ZNEAR) return undefined;
    var _k = _e.foc / _vz;
    return [_e.mx + (_wx - _e.x) * _k,
            _e.my - (_dy * _e.cp - _dz * _e.sp) * _k, _k];
}

/// @desc The front pass, over the field: drifting sand, additive only (so it
///       can't hide a bullet). Fades with the spell background and with the
///       opening.
function hall_draw_front(_b, _spell, _fill) {
    var _a = (1 - 0.86 * clamp(_spell, 0, 1)) * hall_ease(_b.intro);
    if (_a <= 0.01) return;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;
    var _w = _fill ? GAME_W : FIELD_W;
    var _h = _fill ? GAME_H : FIELD_H;

    // ---- the sand ----------------------------------------------------------
    //
    // Each grain has a world position and is projected through the camera,
    // so the sand parallaxes, moves with the camera, and streams past. It is
    // blown on one shared wind (`HALL_SAND_WIND`) and kept low over the floor
    // (`HALL_SAND_TOP`).
    var _eye = hall_eye(_b, _x0, _y0, _w, _h, 0);
    var _was = hall_eye(_b, _x0, _y0, _w, _h, _b.rush * HALL_SAND_TRAIL);

    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < HALL_SAND_N; _i++) {
        // One hash sets size, fall rate and wind response together, so heavy
        // grains are large, fall fast and travel straight, and fine ones hang.
        var _g = hall_hash(_i, 14);
        var _rate = HALL_SAND_FALL * (0.55 + 1.30 * _g);
        var _top = HALL_SAND_TOP * (0.10 + 0.90 * sqr(hall_hash(_i, 15)));
        var _sx = hall_hash(_i, 13) * 2 * HALL_SAND_SPREAD - HALL_SAND_SPREAD
                  - HALL_SAND_WIND * 0.5;
        var _wind = HALL_SAND_WIND * (0.72 + 0.56 * hall_hash(_i, 16));

        // Its fall cycle, and its depth measured against the camera's travel
        // (a fixed world z the camera flies past, wrapping to the far end
        // behind the fade).
        var _l = hall_wrap01(hall_hash(_i, 12) + _b.t * _rate);
        var _s = hall_wrap01(hall_hash(_i, 11)
                             - _b.dist / HALL_SAND_RANGE);
        var _wz = _b.dist + HALL_SAND_NEAR + _s * HALL_SAND_RANGE;

        var _p = hall_project(_eye, _sx + _wind * _l, _top * (1 - _l), _wz);
        if (is_undefined(_p)) continue;
        if (_p[0] < _x0 - 48 || _p[0] > _x0 + _w + 48
            || _p[1] < _y0 - 48 || _p[1] > _y0 + _h + 48) continue;

        // The streak: the same grain projected from where the camera and the
        // grain were a few frames ago.
        var _lb = max(0, _l - _rate * HALL_SAND_TRAIL);
        var _q = hall_project(_was, _sx + _wind * _lb, _top * (1 - _lb), _wz);
        var _len = 0;
        var _ang = 0;
        if (!is_undefined(_q)) {
            var _ex = _p[0] - _q[0];
            var _ey = _p[1] - _q[1];
            _len = min(sqrt(_ex * _ex + _ey * _ey), HALL_SAND_TRAIL_MAX);
            _ang = point_direction(_q[0], _q[1], _p[0], _p[1]);
        }

        // Fade at both ends of both cycles (so nothing is visible when it
        // wraps, and grains don't arrive at the lens as bright blobs).
        var _fade = min(1, _s * 5) * min(1, (1 - _s) * 3)
                    * min(1, _l * 8) * min(1, (1 - _l) * 8);
        if (_fade <= 0.01) continue;

        // Drawn with its head on the grain and its tail behind.
        var _r = (0.55 + 1.70 * _g) * HALL_SAND_R * _p[2];
        var _bw = sprite_get_width(spr_fx_bloom);
        draw_sprite_ext(spr_fx_bloom, 0,
                        _p[0] - dcos(_ang) * _len * 0.5,
                        _p[1] + dsin(_ang) * _len * 0.5,
                        (_r * 2 + _len) / _bw, _r * 2 / _bw, _ang,
                        HALL_SAND_COL, HALL_SAND_A * _a * _fade);
    }
    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}
