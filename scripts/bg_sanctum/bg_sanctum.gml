/// @desc The Archives of Bequeathed Memories: a room, drawn in three
///       dimensions.
///
/// **Stage one is a floor, stage two is a corridor, and this is a room**, and
/// each of those is a different projection rather than a different set of art.
/// `bg_functions` slides three flat plates down the screen, which is right for
/// a pavement seen from above. `bg_corridor` divides by depth, which is right
/// for a wood the camera flies into: a tree is an upright card, and a card has
/// no inside.
///
/// A library has an inside. Its defining feature is that it *encloses* -- two
/// walls of shelving, a marble floor, a coffered ceiling, all receding to one
/// point -- and those are continuous surfaces rather than objects standing in
/// space. That is the first reason this file exists.
///
/// The second is the camera, and it is the one that forced the change. The
/// stage opens high above the floor looking almost straight *down*, so that
/// the hall is hidden and the marble is the whole picture, and then rises and
/// levels out and the room arrives all at once. **A corridor cannot do that.**
/// `corridor_horizon` adds its pitch to the horizon, which is a principal-
/// point shift -- a tilt-shift lens -- and a shift keeps the optical axis
/// pointing forward however far it travels. It crops a wider forward view; it
/// never looks down. Pointing a camera at the floor is a *rotation*, and a
/// rotation is what neither of the other two backgrounds can express.
///
/// So: a real camera, a real projection, and the GPU's own depth buffer.
/// Which turns out to cost less rather than more -- perspective-correct
/// texturing, depth sorting and near/far clipping all stop being this file's
/// problem, and with them go the affine subdivision, the mip cross-fade and
/// the k-way merge that `bg_grove` needed to fake them.
///
/// How it is put together
/// ----------------------
///
/// **One bay, submitted many times.** The hall is a single `HALL_BAY_Z` slice
/// of floor, ceiling and both walls, built once into a vertex buffer and drawn
/// again at each bay's own offset through the world matrix. Twelve bays is
/// twenty-four submissions of frozen geometry, which is nothing, and it means
/// the hall is endless without anything being recycled.
///
/// **Three bays, as three frames, chosen by a hash.** A wall that repeats
/// every tile is wallpaper however good the tile is. `spr_hall_wall` holds
/// shelves, shelves-with-a-ladder and an alcove, and which one a bay gets is
/// `hall_hash` of its index -- so the rhythm never locks and it is the *same*
/// rhythm on the second attempt, which is the argument `corridor_hash` makes
/// one file over.
///
/// **Texture coordinates are page coordinates.** A vertex buffer is the raw
/// path: unlike `draw_primitive_begin_texture`, nothing remaps a sprite's
/// space onto the page for you, so every UV in here goes through `hall_uv`.
/// That is also where the half-texel inset lives -- sampling exactly on a
/// packed sprite's edge blends in whatever is beside it on the page, which at
/// a tile seam is a hairline of somebody else's art.
///
/// **Light is a second pass, not a colour.** Every surface ships as a body
/// and an emissive (see `tools/make_sanctum.py`), and the emissive is drawn
/// additively over the body with depth *testing* but not depth *writing*. A
/// lamp is therefore brighter than white and blooms over its own surround,
/// rather than being a pale patch painted onto a wall -- and the hall's light
/// can change without a texture being redrawn.

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// @desc Mika's hall. One of these per stage that wants it.
function bg_sanctum() {
    // The three sprite slots on the base struct are the parallax stack's and
    // mean nothing here -- this background draws itself through `f_back`. They
    // are handed the hall's own materials rather than left pointing at the
    // flat bay tiles, which no longer exist: GameMaker compiles a reference to
    // a deleted asset as an ordinary variable read, so it built clean and then
    // threw on the first frame, which under the harness is a 120-second hang
    // rather than an error. `check_project` is what names it.
    var _b = bg_new(spr_hall_floor, spr_hall_stone, spr_hall_pale,
                    HALL_FOG, HALL_SPEED);
    _b.kind = BGKIND_SANCTUM;

    // **The three entry points, as function references on the struct.**
    // `bg_step` and its neighbours dispatched on `kind` with one `if` per
    // world, which was honest while there were two and becomes a switch
    // statement the day there are four. A background that says how to draw
    // itself is the same shape as a phase that carries its own `attack` and a
    // ring that carries its own `act`.
    _b.f_step = hall_step;
    _b.f_back = hall_draw_back;
    _b.f_front = hall_draw_front;

    _b.t = 0;
    _b.dist = 0;          // how far down the hall the camera has flown
    _b.spd = HALL_SPEED;
    _b.rush = HALL_SPEED;

    // **The reveal, and it is the stage's whole shape.** Zero is phase A --
    // high above the floor, aimed down at the marble, the hall hidden. One is
    // phase B -- down at flying height, level, the room open. It is driven off
    // `omen`, which already means "the stage turns" and is already a line in a
    // timeline, so the reveal costs no new plumbing at all.
    _b.reveal = 0;

    // **The arrival, which is the reveal's own movement run once at the
    // beginning and in the other direction.** Zero is a dark hall barely
    // moving; one is the stage under way. It is the grove's `intro` under the
    // same name, because it is the same thing -- and like the grove's it is
    // one number driving both the light and the speed, which is the whole of
    // why the two read as one event.
    _b.intro = 0;

    _b.cam_x = 0;
    _b.cam_y = HALL_CAM_HIGH;
    _b.pitch = HALL_PITCH_A;
    _b.lean = 0;
    _b.surf = -1;

    hall_build(_b);
    return _b;
}

/// @desc A stable pseudo-random number in 0..1 from two integers.
///
///       **A hash, never `random`.** A hall whose alcoves are somewhere else
///       on the second attempt is a hall nobody can build a memory of, which
///       is the argument `corridor_hash` and `hex_spray_dir` both make. And
///       `frac` keeps its sign in GML, so this folds into `[0, 1)` rather
///       than trusting it to.
function hall_hash(_a, _b) {
    var _v = sin(_a * 127.1 + _b * 311.7) * 43758.5453;
    _v = frac(_v);
    return (_v < 0) ? _v + 1 : _v;
}

/// @desc Which kind of bay this one is: shelves, shelves-with-a-ladder, or
///       an alcove.
///
///       **The alcove is on a stratum, not on the hash**, and that is the
///       same correction `grove_side` records one stage over. Asked for one
///       of three kinds per bay, `hall_hash` obliges and is *correlated along
///       consecutive integers* -- it is the one-line shader hash, built for
///       fractional coordinates -- so what it actually produced over the
///       fourteen bays the camera can see was one alcove right beside the
///       lens and two past the fog, and nine bays of plain shelving in
///       between. Measured, not guessed: the frame it produced had no alcove
///       in it anywhere.
///
///       A stratum cannot have that failure, because it never asks the hash
///       whether to place one -- only what the bays in between are. It is
///       also what a hall actually does: a run of cases, a niche, a run of
///       cases, at a fixed rhythm somebody laid out.
function hall_bay_kind(_i) {
    var _m = ((_i % HALL_ALCOVE_EVERY) + HALL_ALCOVE_EVERY) % HALL_ALCOVE_EVERY;
    if (_m == HALL_ALCOVE_AT) return 2;
    return (hall_hash(_i, 3) < 0.5) ? 0 : 1;
}

/// @desc A sprite frame's texture coordinates, in *page* space.
///
///       **The raw path does not remap.** `draw_primitive_begin_texture` is
///       handed a sprite's own 0-to-1 space in this runtime -- which
///       `test_band_strip` pins down every run, because it was got wrong once
///       and cost a stage its hedgerow. A vertex buffer is a level below
///       that: what reaches the sampler is whatever is in the buffer, so the
///       mapping has to be done here.
///
///       **Half a texel in from every edge**, for the reason the band strip
///       records: bilinear sampling exactly on the edge of a packed sprite
///       blends in its neighbour on the page, and at a tile seam that is a
///       one-pixel line of unrelated art running the height of the hall.
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

/// @desc A quad carrying its sprite **once**, subdivided into a grid.
///
///       **Subdivided even though the GPU does not need it to be.** The
///       perspective is the projection's problem now, so a wall could be two
///       triangles -- but then its light could only vary at four points, and
///       a lamp half way up a bay would light the whole bay evenly. The grid
///       is what lets the falloff be a falloff. It is vertex lighting, which
///       is the oldest trick there is and still the cheapest way to make a
///       flat surface look like it is standing in a room.
///
///       The one difference from `hall_tiles` is the texture: there every
///       cell takes the whole sprite, so the art repeats; here the sprite is
///       stretched across the whole quad and the grid buys nothing but light.
///       The runner wants that -- it is one piece of art a bay long, and a
///       cartouche repeated eight times down a bay is wallpaper.
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

/// @desc A colour scaled by a light value. Vertex colour multiplies the
///       texture, so this is the whole of the lighting model.
function hall_shade(_col, _l) {
    // **Not clamped at one.** A face factor above unity is how a lit edge is
    // said -- a gilt fillet catching the lamp is brighter than the same gilt
    // in shade -- and clamping here silently threw every one of those away.
    // The ceiling is the colour saturating, which is where it belongs.
    var _k = max(_l, 0);
    return make_colour_rgb(min(255, colour_get_red(_col) * _k),
                           min(255, colour_get_green(_col) * _k),
                           min(255, colour_get_blue(_col) * _k));
}

/// @desc Build the hall's geometry. Once, at construction.
function hall_build(_b) {
    // ---- the joinery and the pavement, one set of buffers per bay kind ----
    //
    // **The floor is built per kind now, and that is what makes the alcove's
    // orb light the stone in front of it.** It was one buffer shared by every
    // bay -- correct while a floor was four squares of marble lit by a
    // vignette, and the reason the one real light source in the hall threw
    // nothing onto the ground under it. Three copies of a bay's pavement is a
    // few hundred triangles; a lamp with no pool beneath it is a lamp nobody
    // believes.
    //
    // **One buffer per texture, and there is no way round it.** A vertex
    // buffer carries texture *coordinates* and `vertex_submit` carries the
    // texture, so a buffer holding two sprites' geometry can only ever be
    // drawn with one of them -- and what the other one's coordinates then
    // index is whatever happens to be packed at that spot on the page. The
    // floor and the ceiling were built into one buffer for exactly one
    // screenshot and the ceiling came back showing the floor's winged discs
    // and ankhs, because that is what those coordinates pointed at. It does
    // not fail loudly: every number involved is in range and the result is a
    // perfectly valid picture of the wrong thing.
    // **Not `_b.case`.** `case` is a reserved word, and a struct member of
    // that name is a parse error that Igor happens to let through and
    // Feather does not -- eleven of them, from three lines. It is the
    // `score` trap in a different costume: a name the language already owns,
    // used somewhere the compiler is feeling generous about.
    _b.joinery = [];
    for (var _k = 0; _k < 3; _k++) {
        _b.joinery[_k] = hall_build_case(_k);
    }

    hall_build_props(_b);


    hall_build_sky(_b);
    hall_build_orrery(_b);
}

/// @desc How lit a point on the joinery is, from the bay's own sources.
///
///       **Static lights baked into static geometry**, which is what a real
///       engine does with anything that cannot move and is the reason this
///       costs nothing at run time. Two sources: the standing lamp out in the
///       nave, which every bay has, and the orb in the alcove, which only the
///       third kind does. A surface far from both falls to `HALL_WALL_AMB`.
///
///       It is inverse-square-ish rather than inverse-square exactly -- a true
///       falloff is almost all darkness with a hot spot in it, and what is
///       wanted here is for the shelving *near* a lamp to be legible and the
///       shelving between lamps to be dim but not black.
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

/// @desc Where the alcove's orb stands along x, on the side given.
///
///       **One answer, read by the geometry and by the light.** It used to be
///       written out twice -- the sphere at the mouth of the recess and the
///       falloff a hundred and eighty units behind it, at the back wall the
///       orb had been moved forward from and nobody went back to. What that
///       draws is a lit patch of stone with nothing in it and, beside it, a
///       lamp casting nothing: two perfectly ordinary-looking halves of one
///       object disagreeing about where it is. It is the `HEX_COL_FAN` shape
///       of mistake -- every number legal, the build clean, and no assertion
///       anywhere with both of them in view. `test_hall_orb` has both now.
function hall_orb_x(_side) {
    return _side * (HALL_HALF_W + HALL_PIL_D + HALL_ORB_STAND);
}

/// @desc How lit a point on the pavement is.
///
///       **A floor is between two walls, and that is the whole reason it does
///       not use `hall_wall_light`.** A wall quad faces one way and answers
///       to the lamps on its own side; a floor quad in the middle of the nave
///       answers to both, and to the orb in either alcove. The old floor
///       ducked that by shading off `abs(u * 2 - 1)` *within each tile* --
///       which is not "brightest at the walls" at all but four bright seams
///       and four dark ones marching across the nave, one pair per tile.
///
///       It is a function of the world point for the same reason
///       `hall_wall_light` is: the light is a property of the room, not of
///       the piece of stone that happens to be catching it.
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
    // **...and the vignette, which is the rule rather than the physics.**
    // Both walls' lamps reach the whole nave, so the honest falloff on its own
    // is nearly flat -- the middle and the wall came out within one and a half
    // per cent, which is a floor with no shape in it and a bright one under
    // the player. What this buys is that the centre line, where the danmaku is
    // thickest, stays the darkest stone in the hall whatever is lighting it.
    var _e = clamp(abs(_x) / HALL_HALF_W, 0, 1);
    _l *= HALL_FLOOR_DIM + (1 - HALL_FLOOR_DIM) * power(_e, 1.6);
    return min(_l * HALL_FLOOR_LIGHT, 1.25);
}

/// @desc A surface, tiled `_nu` by `_nv` times, lit per vertex.
///
///       **Every cell takes the whole sprite**, which is how a texture
///       repeats here at all: the atlas rules out `gpu_set_texrepeat`, so a
///       shelf four hundred units long is eight quads each carrying one tile
///       rather than one quad carrying the tile stretched eight times. The
///       subdivision is wanted anyway -- it is what gives the light somewhere
///       to fall off across.
///
///       `_face` is the surface's own orientation term: a board's top catches
///       the lamp, its underside does not, and one number per quad is the
///       whole of the shading model on top of the distance falloff.
///
///       `_lightfn` is which of the hall's two light models this surface is
///       standing in -- the joinery's by default, the pavement's for anything
///       lying flat. It is an argument rather than a test on the surface,
///       because a surface has no way of knowing which it is and the caller
///       always does.
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

/// @desc One bay of pavement: a sunken runner, a border course either side of
///       it, the marble field out at the walls, and a threshold across the
///       aisles at the bay's own joint.
///
///       **A floor of one tile repeated has no middle, and a hall with a
///       processional way down it is entirely about where its middle is.**
///       Four squares of marble across the nave was reported as exactly what
///       it was -- the same thing four times, left to right, for the length
///       of the hall -- and no amount of detail inside that tile would have
///       answered it, because what was missing was not detail but *structure*
///       across the nave.
///
///       **The runner is sunk rather than the aisles raised**, so everything
///       the walls stand on stays at zero and only the one new course had to
///       move. What the step buys is the two gilt lines running the length of
///       the hall where the courses meet: they converge on the vanishing
///       point, which is the strongest perspective cue in the frame and the
///       one thing a grid of squares can never have.
///
///       **The threshold stops at the step.** It is a feature of the raised
///       pavement, so the runner passes under it unbroken -- which is what a
///       real processional way does, and it keeps the rules down the runner's
///       own edges from being chopped into dashes once a bay.
function hall_floor_bay(_o, _kind) {
    var _bz = HALL_BAY_Z;
    var _hw = HALL_HALF_W;
    var _r = HALL_RUNNER_HW;
    var _st = HALL_FLOOR_STEP;
    var _b0 = _r + HALL_BORDER_W;        // where the marble field begins
    var _tz = HALL_THRESH_W;             // the threshold's depth along the bay

    // --- the runner, one piece of art a bay long -------------------------
    // **The far edge is the tile's top.** Wound the other way round the
    // pavement is laid face-down: every cartouche and every winged disc on it
    // faces back at the camera, which is upside down to anybody flying up the
    // hall and was reported that way about the marble. A floor seen from
    // above has no "up" of its own, so the only thing that can define one is
    // the direction of travel.
    hall_quad(_o.runner,
              [-_r, -_st, _bz], [_r, -_st, _bz],
              [_r, -_st, 0], [-_r, -_st, 0],
              spr_hall_runner, 0, 8, 10, 1.0, 1, _kind, c_white,
              hall_floor_light);

    for (var _s = -1; _s <= 1; _s += 2) {
        // --- the step, faced in gilt --------------------------------------
        // Bright, because it is the one edge in the pavement that faces the
        // light rather than lying flat under it -- and because two lit lines
        // converging is the whole reason the runner is sunk at all.
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
        // The same frieze the border course is, turned through a right angle,
        // which is what makes the pavement's two joints read as one moulding
        // rather than as two ideas.
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

/// @desc One side of one bay, as joinery rather than as a picture of it.
///
///       Reading outward from the nave: a **pilaster** standing proud of
///       everything, the **case front** set back behind it, the **recess**
///       set back again with the books at the bottom of it, and a
///       **cornice** and **plinth** projecting past the pilaster at top and
///       bottom. Every one of those is a real plane at a real depth, so the
///       pilasters occlude the shelving as the camera goes by, the boards
///       catch the lamp along their top edges, and the alcove is a hole with
///       something standing in it rather than a circle painted on a wall.
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

    // --- the pilaster ----------------------------------------------------
    // Its face takes the cartouche texture; its two returns are stone. The
    // returns are what actually sell it -- a face alone is a stripe, and a
    // face with two sides going back into the wall is a column.
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
    // ...and the same two returns again at the far pilaster of this bay, so
    // the case opening is closed at both ends.
    for (var _e = 0; _e <= 1; _e++) {
        var _zz = (_e == 0) ? _z0 : _z1;
        hall_tiles(_o.stone,
                   [_x_case, _y1, _zz], [_x_back, _y1, _zz],
                   [_x_back, _y0, _zz], [_x_case, _y0, _zz],
                   spr_hall_stone, 0, 1, 3, 0.40, _s, _kind);
    }

    if (_kind == 2) {
        // --- the alcove --------------------------------------------------
        // A deep recess, a plinth in the bottom of it, and the orb standing
        // on that. The back wall is the only large plane here that is *not*
        // books, which is what makes this bay read as a pause in the run of
        // shelving.
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
        // **It was a plate and the orb was floating above it.** The stand was
        // two flat quads at the orb's own x, so half of the sphere hung out
        // in front of its own face with nothing under it -- and its foot was
        // twenty-four units clear of the top besides. Neither reads as a
        // mistake on its own; together they are a ball hanging in a niche
        // beside a slab, which is what was reported.
        //
        // So it is a real tapered box on the alcove's sill, with a moulding
        // at its head, a gilt cup on that, and the orb sitting *in* the cup.
        // Every height here is derived from the one above it, so the stack
        // cannot come apart again: the cup's rim is where the sphere's
        // underside is, and the sphere's underside is `HALL_ORB_R` below its
        // centre.
        var _ox = hall_orb_x(_s);
        var _cup_y = HALL_ORB_Y - HALL_ORB_R;        // where the orb rests
        var _cap_y = _cup_y - HALL_ORB_CRADLE;       // the head of the shaft
        var _cz = _bz * 0.5;

        hall_taper(_o.stone, _ox, _cz, _y0, _cap_y - 12,
                   HALL_ORB_R * 0.74, HALL_ORB_R * 0.74,
                   HALL_ORB_R * 0.56, HALL_ORB_R * 0.56,
                   spr_hall_stone, 0, _s, _kind, c_white, 0.92);
        // the moulding at its head: a lit slab standing proud of the shaft,
        // which is the pair the whole hall's relief is drawn as
        hall_taper(_o.gilt, _ox, _cz, _cap_y - 12, _cap_y,
                   HALL_ORB_R * 0.60, HALL_ORB_R * 0.60,
                   HALL_ORB_R * 0.66, HALL_ORB_R * 0.66,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.22);
        // ...and the cup, opening upward to take the sphere
        hall_taper(_o.gilt, _ox, _cz, _cap_y, _cup_y + 4,
                   HALL_ORB_R * 0.40, HALL_ORB_R * 0.40,
                   HALL_ORB_R * 0.72, HALL_ORB_R * 0.72,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.34);

        // **A sphere and two rings, not crossed cards.** The orb was the
        // last thing in the hall still drawn as two quads at right angles,
        // and at this size the seam where they intersect is a hard edge that
        // the alpha test cuts differently frame to frame -- which is the
        // striping across it. It has the primitives now that everything else
        // does.
        hall_sphere(_o.orb, _ox, HALL_ORB_Y, _cz, HALL_ORB_R, 12, 8,
                    spr_hall_pale, 0, _s, _kind, HALL_ORB_BODY, 0.95);
        // the armillary round it: a meridian and an equator, so the sphere
        // reads as mounted rather than as resting loose in a bowl
        hall_ring(_o.gilt, _ox, HALL_ORB_Y, _cz, HALL_ORB_R + 3, 2.4,
                  0, 0, 20, spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.30);
        hall_ring(_o.gilt, _ox, HALL_ORB_Y, _cz, HALL_ORB_R + 3, 2.4,
                  90, 0, 20, spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.15);
        hall_sphere(_o.glow, _ox, HALL_ORB_Y, _cz, HALL_ORB_R * 1.35,
                    10, 7, spr_hall_pale, 0, _s, _kind, HALL_ORB_COL,
                    HALL_ORB_GLOW);
        // **And the light it throws, which is the half that was missing.**
        // A sphere drawn additively is a bright ball; what says *lamp* is the
        // air round it going bright too, and no amount of brightness on the
        // ball itself buys that. Two crossed cards of `spr_fx_bloom` -- the
        // game's own soft falloff, and the one texture in the project that is
        // a light rather than a surface -- so it blooms whether the camera is
        // abeam of the alcove or looking down the hall at it.
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
            // the board: its top face, and the front edge that catches the
            // light. The edge is the gilt line, and it is the single thing
            // that makes a stack of shelves read as joinery.
            hall_tiles(_o.stone, [_x_case, _sy, _z0], [_x_back, _sy, _z0],
                       [_x_back, _sy, _z1], [_x_case, _sy, _z1],
                       spr_hall_stone, 0, 1, 2, 0.96, _s, _kind);
            // **`c_white`, so the texture's own profile rules.** A tint here
            // flattens the moulding back into one value, which is the whole
            // thing this is drawn to avoid.
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

    // --- cornice and plinth ----------------------------------------------
    // Both project past the pilaster, so both cast the whole wall into
    // shadow above and below and both give the camera something with a
    // *lit top edge* to fly past.
    hall_tiles(_o.cornice, [_x_corn, HALL_CEIL_H, 0],
               [_x_corn, HALL_CEIL_H, _bz],
               [_x_corn, HALL_CASE_TOP, _bz], [_x_corn, HALL_CASE_TOP, 0],
               spr_hall_cornice, 0, 2, 1, 0.74, _s, _kind);
    hall_tiles(_o.stone, [_x_corn, HALL_CASE_TOP, 0], [_x_case, HALL_CASE_TOP, 0],
               [_x_case, HALL_CASE_TOP, _bz], [_x_corn, HALL_CASE_TOP, _bz],
               spr_hall_stone, 0, 1, 4, 0.20, _s, _kind);
    // **Proud of the face, not in it.** This and the plinth fillet below sat
    // at exactly `_x_corn` and `_x_plin` -- the same plane as the stone they
    // are supposed to stand out from. Two surfaces at one depth is a tie the
    // depth buffer has to break with whatever precision it has left at that
    // distance, and what that draws is a band that flickers between gold and
    // stone a row at a time as the camera moves. It was reported as the
    // bottom of the bookshelves jittering, and it was the top too.
    //
    // A moulding projects. Saying so in the geometry is both the fix and
    // what it should have been anyway.
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
    // --- the top of the wall, and what stands on it -----------------------
    //
    // **The wall ends against the sky now rather than against a ceiling, so
    // it needs a top.** A wall that simply stops is a cut edge -- the same
    // give-away `grove_draw_mound` exists to bury one stage over, where a
    // billboard's flat bottom read as cardboard standing on a floor. A
    // coping and a parapet is a building whose roof is missing, which is
    // what this one is.
    //
    // **And the parapet's height is the price of the sky.** A long
    // horizontal edge at height H and half-width X projects to a straight
    // ray out of the vanishing point with slope (H - camera) / X, so every
    // unit put on top of this wall narrows the visible sky for the whole
    // length of the hall -- and the orrery has to fit in what is left. See
    // the note in `constants` and the arithmetic in `test_hall_sky`.
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

    // **What stands on it is a post rather than a storey**, because a storey
    // would be a second wall and would close the sky along the whole hall,
    // where a post closes it only at its own bay. What the eye gets is a
    // rhythm of dark verticals marching away against the stars, which says
    // the building goes up a long way further than the frame does and spends
    // almost none of the sky saying it. Over the pilaster, which is what
    // carries it.
    if (_kind == 2) {
        // ...and a brazier on the alcove bays, so the rhythm is a rhythm
        // rather than a repeat and the upper level has a light of its own.
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
        // ...and its bloom, on the orb's terms: a fire against the stars with
        // no air lit round it is a bright bead, not a brazier.
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
        // the pyramidion, which is the part that is actually seen: a gilt
        // point catching what light there is, at the top of a dark shaft
        hall_taper(_o.gilt, _ox, 0, _oy, _oy + HALL_OBELISK_CAP,
                   HALL_OBELISK_W * 0.60, HALL_OBELISK_W * 0.60, 1.5, 1.5,
                   spr_hall_pale, 0, _s, _kind, HALL_GILT, 1.45);
    }
}


/// @desc Both sides of one bay of one kind, as a set of frozen buffers.
///
///       **One buffer per texture**, which is the rule this file learnt the
///       hard way when the ceiling drew the floor's winged discs: a vertex
///       buffer carries coordinates and `vertex_submit` carries the texture,
///       so geometry using two sprites cannot share one.
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
    // **The books are three frames and so they are three buffers.** See
    // `hall_frames_begin`: a buffer mixing frames is drawn against one page
    // and is right only while the packer keeps them together.
    _o.books = hall_frames_begin(spr_hall_books, _f);
    hall_case_side(_o, -1, _kind);
    hall_case_side(_o, 1, _kind);
    // **The pavement is part of the bay, not part of the hall**, which is
    // what lets the alcove's orb light the stone in front of it: a floor
    // built once and shared by every bay cannot know which kind it is under.
    hall_floor_bay(_o, _kind);

    // **An empty buffer is not a buffer, and freezing one is a hard crash.**
    // Not every kind fills every slot: a bookcase bay writes nothing to
    // `orb` or `glow`, and the alcove writes nothing to `books`. Handed a
    // zero-length buffer, `vertex_freeze` asks Direct3D to create a
    // zero-byte vertex buffer and gets E_INVALIDARG back --
    //
    //     HRESULT: 0x80070057 - The parameter is incorrect.
    //     Call: GR_D3D_Device->CreateBuffer
    //
    // -- which surfaces as a modal box, which under either harness is a
    // hang rather than a failure. Nothing above this line is wrong; the
    // geometry is correct and the buffer is simply empty, which is a
    // perfectly reasonable thing for it to be.
    //
    // So an empty slot is thrown away and becomes `-1`, and `hall_submit`
    // knows what that means. Deleting rather than keeping, because a buffer
    // nothing will ever draw is memory with no purpose.
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

/// @desc Fly the camera, and ease the reveal.
function hall_step(_b) {
    _b.t++;

    // **The reveal is the omen, eased hard at both ends.** Four and a half
    // seconds of camera movement is the most composed thing in the stage and
    // the one moment it is asking to be looked at, so it may not start or
    // stop abruptly: a smoothstep twice over is slow enough at the ends that
    // the beginning of the rise and the arrival at level both read as
    // decisions rather than as a cut.
    var _o = clamp(_b.omen, 0, 1);
    _b.reveal = _o * _o * _o * (_o * (_o * 6 - 15) + 10);

    // **The arrival.** One number, eased, and it drives the veil at the end
    // of the back pass and the speed of the flight -- the two together being
    // what makes the opening read as a hall coming alight rather than as a
    // curtain going up on one that was already running.
    if (_b.intro < 1) _b.intro = min(1, _b.intro + 1 / HALL_INTRO_TIME);
    var _in = hall_ease(_b.intro);

    // The flight gathers as the camera comes down: high above the floor there
    // is nothing near enough to read speed off, so phase A at flying speed
    // would look slower than phase B at the same number.
    _b.spd = lerp(HALL_SPEED_A, HALL_SPEED, _b.reveal)
             * lerp(HALL_INTRO_SPD, 1, _in);
    // ...and it breathes, for the reason the grove's swell exists: a constant
    // rate is arithmetically a flight and reads as a dolly on rails.
    _b.rush = _b.spd * (1 + HALL_SWELL * dsin(_b.t * 360 / HALL_SWELL_P));
    _b.dist += _b.rush;

    _b.cam_y = lerp(HALL_CAM_HIGH, HALL_CAM_FLY, _b.reveal);
    _b.pitch = lerp(HALL_PITCH_A, HALL_PITCH_B, _b.reveal);

    // **The flyer steers, and only once the hall is open.** Aimed at the
    // floor there is no vanishing point to swing and nothing at the sides to
    // read a yaw against, so a lean during phase A is a camera sliding for no
    // visible reason. Filtered the way the grove's is -- an ease to take the
    // dodging out and a cap to make it a guarantee rather than a tuning.
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

/// @desc Set up the 3D camera and draw the hall into `_b.surf`.
///
///       **A surface, and this is the one place in the game that owns one.**
///       Three things want it. The depth buffer has to belong to something,
///       and the application surface's is not ours to clear. The hall has to
///       land inside the field rather than across the screen, and a
///       perspective projection aimed at a rectangle that is not the render
///       target's centre is an off-axis frustum -- a matrix built by hand,
///       where a surface is a blit. And an additive pass wants somewhere to
///       accumulate before the result is laid down once.
///
///       The cost is the thing surfaces always cost: it can be lost, so it is
///       checked every frame.
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

    // Where the camera is looking: one unit forward, and `tan(pitch)` down.
    var _tx = _cx;
    var _ty = _cy + dtan(_p) * 100;
    var _tz = _cz + 100;

    var _view = matrix_build_lookat(_cx, _cy, _cz, _tx, _ty, _tz, 0, 1, 0);
    // **Both arguments positive, and that is worth a note because the idiom
    // says otherwise.** Most GameMaker 3D code passes a negative field of
    // view and a negative aspect, and it is right to -- for a world built
    // z-up, or y-*down* to match the 2D space. This one is y-up, so the
    // textbook projection is already the correct one.
    //
    // The negated pair shipped for exactly one screenshot and the hall came
    // back upside down: `-fov` makes the matrix's vertical scale negative,
    // which mirrors y, and `-aspect` then divides that negative through and
    // leaves x alone. The give-away was the props rather than the
    // architecture -- a coffered ceiling and a marble floor are both dark
    // panelled rectangles and look much alike inverted, where a Bastet
    // hanging by her ears does not.
    var _proj = matrix_build_projection_perspective_fov(
        HALL_FOV, _w / _h, HALL_ZNEAR, HALL_ZFAR);

    var _old_w = matrix_get(matrix_world);
    matrix_set(matrix_view, _view);
    matrix_set(matrix_projection, _proj);

    // **Every piece of GPU state this function touches is read first and put
    // back afterwards**, and that is not tidiness -- it is a bug this already
    // shipped. The teardown *asserted* the defaults instead of restoring
    // them, and set `cull_counterclockwise` on the way out; GameMaker's
    // default is `cull_noculling`, so from the first frame the hall was drawn
    // every triangle strip in the game was being back-face culled. What that
    // reached a player as was the boss's health bar not rendering -- in
    // *every* stage, because the state is global and survives the room -- and
    // nothing about a health bar suggests a background's business.
    //
    // A 2D game leaves this state alone, so nothing else in the project ever
    // had to think about it. That is exactly why this file has to.
    var _st_cull = gpu_get_cullmode();
    var _st_filt = gpu_get_texfilter();
    var _st_zt = gpu_get_ztestenable();
    var _st_zw = gpu_get_zwriteenable();
    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(true);
    gpu_set_cullmode(cull_noculling);
    gpu_set_texfilter(true);

    // **The sky first, then the thing hanging in it, then the room.** Both
    // of those are behind every bay the hall draws -- the dome because it
    // writes no depth at all, the orrery because it is a thousand units
    // further out than the last bay -- so the architecture simply paints
    // over whatever of them it is in front of, and the wedge of sky left
    // between the two parapets is the picture.
    hall_draw_sky(_b);
    hall_draw_far(_b);
    hall_draw_orrery(_b);

    gpu_set_ztestenable(true);
    hall_pass_solid();

    // **Which bays are in front of the camera.** The hall is endless because
    // nothing is recycled: a bay is a translation, and the range is whichever
    // ones the far plane can reach.
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

    // **The emissive pass: additive, depth-tested, depth-write off.** Tested,
    // so an orb behind a pilaster stays behind it. Not written, so two lights
    // at the same depth both land instead of the second being rejected by the
    // first.
    //
    // **Every kind, not just the alcove.** It was skipped for anything but
    // bay kind 2 on the grounds that the orb was the only light in the
    // joinery, which stopped being true the moment a brazier went up on the
    // parapet -- and the symptom of that would have been a bowl of fire
    // drawn as a cold grey bowl, with nothing anywhere saying why. A kind
    // with nothing to add has an empty `glow` slot, which is `-1`, which
    // `hall_submit` already knows to skip.
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

    // **And the shader goes back with everything else.** It is global state
    // and it survives the room, which is the whole reason the note above
    // exists: a hall that left its own shader set would draw the rest of the
    // game -- every stage, every menu -- fogged and faded by a distance
    // nothing outside this file has.
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

/// @desc The dark the hall comes up out of.
///
///       **The stage used to begin at full speed in a lit room on its first
///       frame**, which is the one moment in it nobody composed: the rack
///       cuts and everything is simply there, at once, going past. So the
///       lights come up instead -- and because `intro` is the same number the
///       flight's speed is scaled by, what the player sees is one event
///       rather than a fade happening over the top of a stage that had
///       already started.
///
///       **Opaque, and that is affordable because this is the back pass.**
///       Every bullet in the game is drawn over it, and in any case nothing
///       has been fired on the frames it is dense -- which is the exception
///       `grove_draw_veil` records, on the same terms.
///
///       Held near the top for the first fifth and then falling away, so the
///       opening is a room being lit rather than a linear dissolve.
function hall_draw_veil(_b, _x0, _y0, _w, _h) {
    if (_b.intro >= 1) return;
    draw_set_colour(c_black);
    draw_set_alpha(power(1 - _b.intro, 1.30));
    draw_rectangle(_x0, _y0, _x0 + _w, _y0 + _h, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The two passes
//
// **Distance has to take a surface's alpha away, and not only its colour.**
// The hall hid its far end with fog, which recolours a surface toward the air
// -- and that works only where what is *behind* it is the air too. At the end
// of this hall it is not: `hall_draw_far` hangs a lit rotunda at the vanishing
// point, and the last few bays of shelving, their statues and their tabards
// all project into the middle of it. So a prop arriving at the fog's own end
// arrived as a perfectly fog-coloured silhouette cut out of a bright building,
// which is exactly as visible as a black one.
//
// It was reported as things popping in at the far end, and the first answer
// here was to make the props' fog agree with the architecture's -- they had
// been fogging to black, inherited from the additive pass before them, which
// was a real bug and not this one. Fixing it changed nothing anybody could
// see, because the colour was never what was wrong.
//
// **Alpha is the only thing that hides a surface whatever is behind it**, and
// `vertex_submit` has no per-draw alpha: what reaches the default shader is
// the vertex buffer's own colour, and the buffers are frozen. So the fade is
// computed in `sh_hall` from the one quantity a frozen buffer cannot carry --
// how far the vertex is from the camera this frame -- and the fog is computed
// there too, off the same distance, so the two cannot disagree about where the
// end of the hall is.
// ---------------------------------------------------------------------------

/// @desc Set the hall's shader, and the state a solid surface wants.
///
///       `_ref` is the cut-out threshold. It is per pass rather than global
///       because the two things drawn here want opposite answers: a tabard is
///       a shape with transparent corners and has to punch them out of the
///       depth buffer, and a bloom is a soft falloff whose whole outer half
///       would become a hard disc if it were tested at all.
function hall_pass_solid(_ref = 0) {
    gpu_set_blendmode(bm_normal);
    gpu_set_zwriteenable(true);
    hall_shader(HALL_FOG, _ref);
}

/// @desc Begin the additive pass: light, rather than surface.
///
///       Depth writing off, because two lamps at one depth should both land,
///       and the fog toward **black**, because what distance does to a light
///       is take it away rather than wash it toward the colour of the air.
function hall_pass_light() {
    gpu_set_zwriteenable(false);
    gpu_set_blendmode(bm_add);
    hall_shader(c_black, 0);
}

/// @desc The shader, and everything the distance drives.
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

/// @desc Draw a buffer, unless it turned out to have nothing in it.
///
///       See `hall_build_case`: a slot no bay kind filled is `-1` rather than
///       an empty buffer, because an empty one cannot be frozen and cannot be
///       submitted -- Direct3D refuses a zero-length buffer outright.
function hall_submit(_vb, _tex) {
    if (_vb == -1) return;
    vertex_submit(_vb, pr_trianglelist, _tex);
}

// ---------------------------------------------------------------------------
// One buffer per frame
//
// **A buffer holding two frames of a sprite is a buffer that can only be
// right by luck.** `vertex_submit` takes one texture and `hall_uv` writes
// page coordinates, so geometry using frame 1 is drawn against whichever page
// `sprite_get_texture(spr, 0)` names -- which is correct exactly while the
// packer happens to have put the two frames on the same page, and the packer
// is under no obligation to. Adding two tiles to the hall's folder repacked
// the atlas, the banner's two frames came apart, and every other bay's tabard
// came back as a piece of masonry hanging off the cornice. It was reported by
// a person looking at the screen.
//
// **And it cannot be asserted against**, which is why the answer is
// construction rather than a guard. `sprite_get_texture` hands back a pointer
// to the frame's own entry rather than to the page it sits on -- measured:
// three single-frame sprites certainly packed together answer three different
// pointers -- so no suite can ask whether two frames share a page. What a
// suite *can* do is what `check_hall_frame_textures` does, which is refuse
// the construction that needs the question asking.
//
// So a sprite the hall draws more than one frame of gets one buffer per
// frame, each submitted with its own frame's texture. It costs a submit per
// frame and it is right whatever the packer does.
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

/// @desc ...and close them. A frame nothing was written for becomes `-1`, on
///       `hall_build_case`'s terms: an empty buffer cannot be frozen.
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

/// @desc One flat quad with a sprite's own corners on it.
///
///       The two things left that genuinely *are* flat: a tabard, which is
///       cloth, and a blade of light, which has no thickness to have. Solids
///       go through `hall_taper` and its neighbours instead.
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

/// @desc A light, as two square cards at right angles centred on a point.
///
///       **Crossed cards are wrong for an object and right for a glow**,
///       which is why every solid in this hall stopped using them and this
///       did not. The seam where two quads intersect is a silhouette defect,
///       and a bloom has no silhouette: it is additive, radially symmetric
///       and soft to its own edge, so the pair reads the same from any angle
///       the camera reaches and costs four triangles.
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
// Solids
//
// **The furniture is built out of these rather than out of crossed quads.**
// A cross of two cards is the cheapest thing that looks like an object from
// the front, and this stage is the worst possible place for it: the camera
// starts nine hundred units up looking down, where a pair of upright cards is
// a pair of upright cards. Seen from overhead they read as an X of cardboard,
// which is exactly what they are.
//
// So a plinth is a box, a lamp is a stem and a sphere, an armillary is three
// real rings. None of it is a lot of geometry -- a bay's worth of furniture is
// a couple of thousand triangles, built once and frozen -- and all of it is
// correct from every angle the camera ever reaches, which is the whole reason
// the stage went to three dimensions.
// ---------------------------------------------------------------------------

/// @desc A tapered box: four sides and a top, from `_y0` to `_y1`.
///
///       **No bottom face**, because everything here stands on something. A
///       face nobody can see is triangles nobody needs.
///
///       The taper is what stops it reading as a crate: a plinth is wider at
///       its foot than its head, and half a per cent of batter is the
///       difference between masonry and a cardboard box.
function hall_taper(_vb, _cx, _cz, _y0, _y1, _w0, _d0, _w1, _d1,
                    _spr, _frame, _side, _kind, _col = c_white, _face = 1) {
    var _c = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
    for (var _i = 0; _i < 4; _i++) {
        var _a = _c[_i];
        var _b = _c[(_i + 1) % 4];
        // sides facing along z are dimmer than those facing the nave, which
        // is the whole of the shading on a box and is enough
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

/// @desc A sphere, as a lattice of quads.
///
///       Coarse on purpose -- eight round and six up is enough for something
///       this size, and the facets read as a cut stone rather than as a
///       failure to be round.
function hall_sphere(_vb, _cx, _cy, _cz, _r, _nu, _nv,
                     _spr, _frame, _side, _kind, _col = c_white, _face = 1) {
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
                       _spr, _frame, 1, 1, _f, _side, _kind, _col);
        }
    }
}

/// @desc A flat ring, tilted. What an armillary is three of.
function hall_ring(_vb, _cx, _cy, _cz, _r, _w, _tilt, _yaw, _n,
                   _spr, _frame, _side, _kind, _col = c_white, _face = 1) {
    for (var _i = 0; _i < _n; _i++) {
        var _a0 = 360 * _i / _n, _a1 = 360 * (_i + 1) / _n;
        var _v = [];
        var _spec = [[_a0, _r + _w], [_a1, _r + _w], [_a1, _r - _w],
                     [_a0, _r - _w]];
        for (var _k = 0; _k < 4; _k++) {
            // tilt about x, then yaw about y -- `hall_orient`, because the
            // orrery's bodies have to ride in the same plane as their rings
            // and a second copy of this is a second copy to get wrong
            var _o = hall_orient(dcos(_spec[_k][0]) * _spec[_k][1],
                                 dsin(_spec[_k][0]) * _spec[_k][1], 0,
                                 _tilt, _yaw);
            _v[_k] = [_cx + _o[0], _cy + _o[1], _cz + _o[2]];
        }
        hall_tiles(_vb, _v[0], _v[1], _v[2], _v[3],
                   _spr, _frame, 1, 1, _face, _side, _kind, _col);
    }
}

/// @desc A seated Bastet: the drawn figure, on a built plinth.
///
///       **The plinth is geometry and the cat is not, and that division is
///       deliberate.** A plinth is a tapered box with a moulded cap -- a box
///       is genuinely what it is, and building it fixes the thing that looked
///       worst from overhead. A *cat* is not a box, and four passes of
///       stacked tapers proved it: the silhouette went from an obelisk to a
///       rounded monolith and never once to an animal, because the forms that
///       make a seated cat legible at this size are a haunch and a shoulder,
///       and a taper cannot do either.
///
///       So the figure is `spr_hall_bastet`, which is drawn, detailed, and
///       already right. It is a **fixed** quad, not a billboard: it faces
///       back down the hall and stays there, so it takes the perspective
///       exactly as the walls do and nothing silently re-aims as the camera
///       moves. What is given up is that from directly overhead, in phase A,
///       it is edge-on -- and what is seen there instead is the plinth's own
///       top, which is real.
function hall_bastet(_o, _s, _z, _kind) {
    var _x = _s * HALL_STATUE_X;
    var _pl = spr_hall_plinth;
    var _pa = spr_hall_pale;
    var _b = HALL_STATUE_BASE;

    hall_taper(_o.plinth, _x, _z, 0, _b - 16, 74, 68, 66, 60,
               _pl, 0, _s, _kind, c_white, 1.0);
    hall_taper(_o.plinth, _x, _z, _b - 16, _b, 78, 72, 74, 68,
               _pl, 0, _s, _kind, c_white, 1.15);
    hall_taper(_o.gilt, _x, _z, _b - 20, _b - 13, 80, 74, 80, 74,
               _pa, 0, _s, _kind, HALL_GILT, 1.40);
    hall_taper(_o.gilt, _x, _z, 8, 15, 78, 72, 78, 72,
               _pa, 0, _s, _kind, HALL_GILT, 1.10);

    hall_face_z(_o.statue, spr_hall_bastet, 0, _x, _b, _z,
                HALL_STATUE_H, HALL_PROP_LIGHT);
}

/// @desc A reading desk, with an hourglass or an armillary standing on it.
function hall_desk(_o, _s, _z, _kind, _which) {
    var _x = _s * HALL_DESK_X;
    var _pa = spr_hall_pale;
    var _st = _pa;
    var _t = HALL_DESK_TOP;

    hall_taper(_o.plinth, _x, _z, 0, _t - 12, 52, 74, 44, 64,
               spr_hall_deskface, 0, _s, _kind, c_white, 1.0);
    hall_taper(_o.stone, _x, _z, _t - 12, _t, 60, 82, 60, 82,
               _st, 0, _s, _kind, HALL_MASONRY, 1.1);
    hall_taper(_o.gilt, _x, _z, _t - 15, _t - 9, 62, 84, 62, 84,
               _pa, 0, _s, _kind, HALL_GILT, 1.30);

    if (_which == 0) {
        // an hourglass: two cones meeting at the waist, in a gilt frame
        var _g = 74;
        hall_taper(_o.gilt, _x, _z, _t, _t + _g * 0.5, 26, 26, 4, 4,
                   _pa, 0, _s, _kind, HALL_GLASS, 1.2);
        hall_taper(_o.gilt, _x, _z, _t + _g, _t + _g * 0.5, 26, 26, 4, 4,
                   _pa, 0, _s, _kind, HALL_GLASS, 1.0);
        for (var _c = 0; _c <= 1; _c++) {
            var _yy = _t + _c * _g;
            hall_taper(_o.gilt, _x, _z, _yy - 5, _yy + 5, 30, 30, 30, 30,
                       _pa, 0, _s, _kind, HALL_GILT, 1.30);
        }
        for (var _px = -1; _px <= 1; _px += 2) {
            for (var _pz = -1; _pz <= 1; _pz += 2) {
                hall_taper(_o.gilt, _x + _px * 26, _z + _pz * 26, _t, _t + _g,
                           4, 4, 4, 4, _pa, 0, _s, _kind, HALL_GILT, 1.15);
            }
        }
    } else {
        // an armillary: three real rings on a stem, and a cold heart
        var _cy = _t + 78;
        hall_taper(_o.gilt, _x, _z, _t, _t + 30, 6, 6, 5, 5,
                   _pa, 0, _s, _kind, HALL_GILT, 1.2);
        hall_ring(_o.gilt, _x, _cy, _z, 46, 3.5, 0, 0, 18, _pa, 0, _s, _kind,
                  HALL_GILT, 1.25);
        hall_ring(_o.gilt, _x, _cy, _z, 46, 3.5, 90, 0, 18, _pa, 0, _s, _kind,
                  HALL_GILT, 1.10);
        hall_ring(_o.gilt, _x, _cy, _z, 46, 3.0, 62, 54, 18, _pa, 0, _s, _kind,
                  HALL_GILT, 0.95);
        hall_sphere(_o.glow, _x, _cy, _z, 11, 8, 5, _pa, 0, _s, _kind,
                    HALL_ORB_COL, 0.85);
    }
}

// **The standing lamps are gone, and so are the shafts of light.** The lamps
// did the same job as the orb in the alcove -- a cold sphere on a gilt stem --
// without being the better-looking of the two, and a pair of them in every bay
// stood in the nave taking up the floor the camera flies over.
//
// The shafts went with the ceiling. They were four soft blades through a
// common upright, falling from the coffers; with no coffers to fall through
// they were two columns of haze arriving from nowhere, and what they actually
// did to the frame was grey the one part of it the roof was opened to show.
// What lights the hall now is the orbs set into the wall and the braziers on
// the parapet, both of which are objects that are *there*.
//
// `hall_lamp`, `hall_shaft` and `hall_pool` are deleted rather than commented
// out; the primitives they were built from are all still here.

/// @desc The things standing in the hall, as solids.
///
///       **Crossed quads are gone.** They were the compromise that replaced
///       billboards, and they carried the same defect one step further down:
///       from nine hundred units up, aimed at the floor, two upright cards at
///       right angles are two upright cards at right angles. What phase A
///       actually showed was an X of cardboard per prop.
///
///       So the furniture is built. See the solids above: a plinth is a
///       tapered box, a lamp is a stem and a sphere in a cage of real rings,
///       an armillary is three real rings. It is a couple of thousand
///       triangles a bay, built once and frozen, and it is correct from every
///       angle the camera reaches -- which is the entire reason this stage is
///       in three dimensions.
///
///       **And the tabards alternate with the statues.** Every bay used to
///       carry two statues, two tabards, two lamps and a desk, which is seven
///       things per bay and reads as clutter rather than as furnishing. A
///       tabard hangs on the even bays and a pair of statues stands on the
///       odd ones, so the hall has a rhythm and each thing gets seen.
function hall_build_props(_b) {
    _b.prop = [];
    for (var _v = 0; _v < 4; _v++) {
        _b.prop[_v] = hall_build_prop_set(_v);
    }
}

/// @desc Which arrangement a bay gets.
///
///       **Two arrangements alternating is a pattern the eye locks on to in
///       about three bays**, and it was reported as everything appearing in
///       the same order on every row -- which it did, because it was. Bit 0
///       is a stratum, so statues and tabards still alternate honestly; bit 1
///       is a hash, so which side the desk stands on and which instrument is
///       on it do not.
function hall_prop_variant(_i) {
    var _m = ((_i % 4) + 4) % 4;
    if (_m == 1 || _m == 3) return 1;           // a pair of statues
    if (_m == 0) return (hall_hash(_i, 21) < 0.5) ? 2 : 3;  // ...and a pedestal
    return 0;                                   // the alcove bay: tabard only
}

/// @desc One bay's furniture, for bays of the given parity.
function hall_build_prop_set(_v) {
    // **Four named arrangements, not two independent bits.** `_par = _v & 1`
    // and `_alt = _v >> 1` were read as though they chose separate things, so
    // variant 3 came out as a statue bay *and* a pedestal bay at once -- and
    // both stand on the same line at the same point in the bay. The cat's
    // plinth swallowed the pedestal's foot, which is why the statue sat on
    // top of the armillary and why the hourglass appeared to hover in mid
    // air with nothing under it. One cause, two symptoms, and neither is
    // anything a screenshot of the geometry would call wrong.
    var _statues = (_v == 1);
    var _pedestal = (_v >= 2);
    var _f = hall_format();
    var _o = {
        stone: vertex_create_buffer(),
        gilt: vertex_create_buffer(),
        glow: vertex_create_buffer(),
        plinth: vertex_create_buffer(),
        statue: vertex_create_buffer(),
    };
    var _names = ["stone", "gilt", "glow", "plinth", "statue"];
    for (var _i = 0; _i < array_length(_names); _i++) {
        vertex_begin(_o[$ _names[_i]], _f);
    }
    // The two tabards are two frames of one sprite, and one buffer each.
    _o.banner = hall_frames_begin(spr_hall_banner, _f);

    // **The pedestal falls midway between two statues, on the statue line.**
    // Statues stand on the odd bays at the bay's centre, so the centre of an
    // even bay is exactly half way between a pair of them -- which is where a
    // hall would put a stand, and which is also why it only appears on one
    // bay in four rather than wherever a hash happened to land it.
    // **`0` for the bay kind, not the variant.** Props are built per
    // arrangement and an arrangement does not know which wall it will stand
    // against, so the one thing it must not do is claim to be the alcove --
    // that would add the orb's light to a bay with no orb in it.
    if (_pedestal) {
        var _dside = (_v == 3) ? 1 : -1;
        hall_desk(_o, _dside, HALL_BAY_Z * 0.5, 0, (_v == 3) ? 1 : 0);
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

/// @desc Every prop in front of the camera, far to near.
///
///       **Depth writing is on and so is the alpha test**, and between them
///       they are the whole of why a tabard four bays away no longer draws in
///       front of one a bay away. The props used to be submitted with depth
///       writing *off* -- correct for the additive wall lights it had been
///       turned off for, and then inherited by everything drawn after them --
///       so nothing wrote a depth at all and the only thing deciding what
///       covered what was the order the loop happened to run in, which was
///       near to far.
///
///       The alpha test is the other half. A cut-out sprite on a quad has
///       transparent corners, and with depth writing on those corners write a
///       depth like anything else: a banner would punch a rectangular hole in
///       the hall behind it. Discarding the texels below the reference keeps
///       the depth buffer honest about the *shape* rather than about the quad.
///       **The cut-out is the shader's now.** `gpu_set_alphatestenable` is
///       a fixed-function state the *default* shader implements, so once the
///       hall had one of its own the test had to move into it -- and it is
///       better there, because `sh_hall` can test the texture's alpha rather
///       than the result's, which is what lets a prop fade out by distance
///       without the fade turning into a hard cut the moment it crosses the
///       reference.
function hall_draw_props(_b, _b0, _b1) {
    hall_pass_solid(HALL_ALPHA_REF);

    for (var _i = _b1; _i >= _b0; _i--) {
        var _p = _b.prop[hall_prop_variant(_i)];
        matrix_set(matrix_world,
                   matrix_build(0, 0, _i * HALL_BAY_Z, 0, 0, 0, 1, 1, 1));
        hall_submit(_p.stone, sprite_get_texture(spr_hall_stone, 0));
        hall_submit(_p.plinth, sprite_get_texture(spr_hall_plinth, 0));
        hall_submit(_p.gilt, sprite_get_texture(spr_hall_pale, 0));
        hall_submit(_p.statue, sprite_get_texture(spr_hall_bastet, 0));
        hall_submit_frames(_p.banner, spr_hall_banner);
    }

    // ...and their light. Additive and depth-tested but not written, because
    // a glow is not a surface: two lamps at the same depth should both land.
    hall_pass_light();
    for (var _i = _b1; _i >= _b0; _i--) {
        matrix_set(matrix_world,
                   matrix_build(0, 0, _i * HALL_BAY_Z, 0, 0, 0, 1, 1, 1));
        hall_submit(_b.prop[hall_prop_variant(_i)].glow,
                    sprite_get_texture(spr_hall_pale, 0));
    }
    hall_pass_solid();
}

// ---------------------------------------------------------------------------
// The sky
//
// **A skybox, and it is a dome centred on the camera rather than a backdrop
// behind it.** The difference is the one thing a flat backdrop can never be
// talked into: a dome turns correctly under the pitch and the lean, and it
// does not translate at all, which is what "infinitely far away" means. The
// reveal swings the camera through fifty-three degrees of pitch over four and
// a half seconds, and the whole of that movement has to read as the *camera*
// rising rather than as a picture sliding -- the defect `bg_grove` records
// about the canopy bands reading as acetate pulled across the frame.
//
// It is drawn first, with the depth test off, so everything else in the hall
// simply paints over it. That is also why the dome has to reach well below
// the horizon and has to *be the fog colour* down there: the far end of the
// hall dissolves into `HALL_FOG`, and anything past the last bay drawn is
// sky, so the two have to be the same colour or there is a line across the
// picture where one becomes the other.
//
// Nothing here is simulated and nothing is random. Every star, every patch of
// nebula and every constellation comes off `hall_hash`, so the sky is the
// same sky on the tenth attempt as on the first -- which is the argument
// `corridor_hash` and `hex_spray_dir` both make, and it matters more here
// than in either: this one is the backdrop of a stage somebody will play
// twenty times.
// ---------------------------------------------------------------------------

/// @desc Smoothstep. Written once because four things in this file want one.
function hall_ease(_t) {
    var _k = clamp(_t, 0, 1);
    return _k * _k * (3 - 2 * _k);
}

/// @desc A unit direction from an azimuth and an elevation, both in degrees.
function hall_dir(_az, _el) {
    var _c = dcos(_el);
    return [_c * dcos(_az), dsin(_el), _c * dsin(_az)];
}

/// @desc Where star `_i` sits on the dome.
///
///       **Two populations, not one.** A uniform sprinkle of points reads as
///       a screensaver however many of them there are; what makes a night sky
///       look like one is that most of its light is in a *band*, and the band
///       is at an angle to everything else in the frame. So a share of them
///       fall near one tilted great circle and the rest are spread over the
///       hemisphere by area -- `darcsin` of a uniform number, because taking
///       the elevation uniformly would crowd them all around the zenith.
function hall_star_dir(_i) {
    if (hall_hash(_i, 72) < HALL_STAR_BAND) {
        // on the band: a point on the equator, thickened, then the whole
        // sphere tipped over so the band crosses the hall at an angle
        var _u = hall_hash(_i, 73) * 360;
        var _v = (hall_hash(_i, 74) * 2 - 1) * HALL_STAR_BAND_W;
        var _d = hall_dir(_u, _v);
        var _t = HALL_STAR_BAND_TILT;
        return [_d[0], _d[1] * dcos(_t) - _d[2] * dsin(_t),
                _d[1] * dsin(_t) + _d[2] * dcos(_t)];
    }
    return hall_dir(hall_hash(_i, 71) * 360, darcsin(hall_hash(_i, 70)));
}

/// @desc How much of a star survives the haze it is seen through.
///
///       **The same haze the architecture is in.** The hall fades to
///       `HALL_FOG` between 1100 and 6400 units and the sky does not fade at
///       all, so without this the far bays would close into flat fog with a
///       perfectly crisp starfield sitting behind them -- and the join
///       between the two is precisely the line the fog exists to hide. A star
///       low down is seen through more air, so it goes out first.
///
///       **And the band it ramps over is the band that is seen.** The camera
///       never looks up: the top of the frame is twenty-seven degrees above
///       the horizon and the wall tops cut off everything under about ten, so
///       a ramp that finished at thirty put every star actually in frame at a
///       third of its brightness and the wedge came back empty.
function hall_star_extinction(_el) {
    return hall_ease((_el - HALL_STAR_EL0) / (HALL_STAR_EL1 - HALL_STAR_EL0));
}

/// @desc The sky's own colour at a given elevation.
///
///       **Three stops, not a scale of the fog.** Multiplying the fog colour
///       down is the obvious construction and it cannot work: a multiply
///       moves a colour's value and never its chroma, so a desaturated haze
///       makes a desaturated sky at every elevation it is asked for. What
///       came back was reported, exactly, as a grey void caught in fog.
///
///       The horizon stop *is* `HALL_FOG`, which is what keeps the far end of
///       the hall dissolving into the sky rather than meeting it at a line --
///       the finding `bg_grove` records about the ground at infinity being
///       the sky. Everything above it is blue, and blue at the same value
///       rather than at a higher one, because the danmaku's budget is
///       brightness and this spends none of it.
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

/// @desc One quad of the dome, coloured per corner off its own elevation.
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

/// @desc The dome itself: the one thing out here that is not a light.
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

/// @desc A flat card of the given half-size, tangent to the dome at `_d`.
///
///       **Built facing the centre rather than billboarded at draw time.**
///       The camera never rolls, so a card square to the radius is square to
///       the lens to within the half-degree the pitch costs it -- which means
///       the whole sky can be one frozen buffer rather than nine thousand
///       quads rebuilt every frame.
function hall_sky_card(_vb, _d, _r, _spr, _frame, _col, _a, _dist) {
    // a pair of axes across the line of sight. The pole is the one direction
    // the cross product cannot be taken against, and the sky has stars in it.
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

/// @desc What colour a star is. Mostly cold, a few warm, which is what the
///       sky actually does and what stops a starfield reading as one material
///       at several brightnesses.
function hall_star_col(_i) {
    var _h = hall_hash(_i, 76);
    if (_h > 0.94) return make_colour_rgb(255, 182, 132);
    if (_h > 0.84) return make_colour_rgb(255, 226, 180);
    if (_h > 0.46) return make_colour_rgb(244, 246, 255);
    return make_colour_rgb(198, 216, 255);
}

/// @desc Is star `_i` one of the bright ones? Asked in two places, so it is
///       written once: the constellations are drawn between these.
function hall_star_mag(_i) {
    if (hall_hash(_i, 72) < HALL_STAR_BAND) return 0;   // the band is faint
    var _m = hall_hash(_i, 75);
    if (_m > 0.962) return 2;
    if (_m > 0.800) return 1;
    return 0;
}

/// @desc Every star, as a card apiece, into its own magnitude's buffer.
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

/// @desc The deep sky: soft patches, added at a few per cent each.
///
///       **This is what gives the dark a shape.** Points on a flat black
///       ground have no depth to be at; the same points over cloud that has
///       edges and holes in it read as being *in front of* something, which
///       is the whole of why the sky looks far away.
function hall_fill_neb(_bufs) {
    // **Blue first, and the other three are what stop it being one colour.**
    // A nebula palette spread evenly across the wheel reads as stained glass;
    // what a sky does is one dominant hue with a little else in it, which is
    // the same rule the ivy keeps in the grove.
    var _cols = [make_colour_rgb(62, 104, 226), make_colour_rgb(48, 138, 196),
                 make_colour_rgb(62, 104, 226), make_colour_rgb(128, 78, 196),
                 make_colour_rgb(62, 104, 226), make_colour_rgb(46, 150, 158)];
    for (var _i = 0; _i < HALL_NEB_N; _i++) {
        // **Placed where the camera looks, not spread over the sphere.**
        // Measured: a uniform azimuth puts four patches in five behind the
        // player and a uniform elevation puts most of the rest above the top
        // of the frame, so what reached the screen out of ten of them was
        // one. The sky is a *backdrop* and is allowed to be composed for the
        // one direction this stage is ever flown -- the same call `bg_grove`
        // makes when it puts the moon on the horizon and centres it.
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

/// @desc One line of a constellation, as a ribbon across the line of sight.
function hall_const_line(_vb, _d0, _d1, _col, _a) {
    var _p0 = [_d0[0] * HALL_SKY_R * 0.95, _d0[1] * HALL_SKY_R * 0.95,
               _d0[2] * HALL_SKY_R * 0.95];
    var _p1 = [_d1[0] * HALL_SKY_R * 0.95, _d1[1] * HALL_SKY_R * 0.95,
               _d1[2] * HALL_SKY_R * 0.95];
    var _ax = _p1[0] - _p0[0], _ay = _p1[1] - _p0[1], _az = _p1[2] - _p0[2];
    // across the line of sight: the segment crossed with the way we are
    // looking, which for a dome centred on the camera is the radius
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

/// @desc The figures somebody drew between the bright stars.
///
///       **Joined to their neighbours, not to each other in index order.**
///       Bright stars are scattered all over the dome, so linking them as
///       they come out of the hash draws lines the length of the sky and what
///       that makes is a cat's cradle. A constellation is *local*: a seed
///       direction, and the four brightest things near it.
function hall_fill_const(_vb) {
    var _col = make_colour_rgb(150, 178, 255);

    // **The candidates are gathered once, before any figure is drawn.**
    // Asking "which four bright stars are nearest this seed" twenty-two times
    // over nine thousand of them is two hundred thousand `hall_star_dir`
    // calls -- the better part of a million sines, under the VM, on the frame
    // the stage opens, which is a hitch on the one transition this stage was
    // composed for.
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
        // Composed for the camera, as the nebulae are and for the same
        // measured reason: at a uniform azimuth exactly one short segment of
        // one figure fell inside the wedge, out of nine.
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

/// @desc Build the sky, and the chamber standing at the end of it.
function hall_build_sky(_b) {
    var _f = hall_format();
    _b.vb_dome = hall_prop_buffer(_f, hall_fill_dome);
    _b.vb_neb = hall_frames_buffer(spr_hall_neb, _f, hall_fill_neb);
    _b.vb_const = hall_prop_buffer(_f, hall_fill_const);
    _b.vb_stars = hall_frames_buffer(spr_hall_star, _f, hall_fill_stars);
    _b.vb_rot = hall_prop_buffer(_f, hall_fill_rotunda);
    _b.vb_rot_lit = hall_prop_buffer(_f, hall_fill_rotunda_lit);
}

/// @desc Lay the sky down, before anything that is actually in the hall.
///
///       **Centred on the camera and never depth-written.** The world matrix
///       is the camera's own position, which is the whole of what makes the
///       dome infinitely far away -- it translates with the viewer, so no
///       amount of flying ever reaches it, and it still rotates correctly
///       because the *view* matrix has not been touched.
function hall_draw_sky(_b) {
    gpu_set_ztestenable(false);
    gpu_set_zwriteenable(false);
    gpu_set_fog(false, c_black, 0, 1);
    matrix_set(matrix_world,
               matrix_build(_b.cam_x, _b.cam_y, hall_cam_z(_b),
                            0, 0, 0, 1, 1, 1));
    hall_submit(_b.vb_dome, sprite_get_texture(spr_hall_pale, 0));

    // ...and its lights, which are everything else out there.
    gpu_set_blendmode(bm_add);
    hall_submit_frames(_b.vb_neb, spr_hall_neb);
    hall_submit(_b.vb_const, sprite_get_texture(spr_hall_pale, 0));
    hall_submit_frames(_b.vb_stars, spr_hall_star);
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The chamber at the end of the hall
//
// **The sky needed a floor.** With the roof off, the hall's own perspective
// ran out at the vanishing point and everything past it was stars -- so the
// nave did not read as a room open to the night, it read as a corridor
// trailing off into space. What was missing is what every real view of a
// horizon has: something the ground *becomes*.
//
// It is one painted quad at a fixed depth, and painted is the point. A second
// room in three dimensions at the end of an endless hall is a room the flight
// would have to either reach or visibly never reach, and both of those are
// worse than a backdrop -- which is what `bg_grove`'s moon is and what this
// is. See `rotunda` in `tools/make_sanctum.py` for the projection it is drawn
// in, and for why only the far half of it exists.
//
// **It is a backdrop layer, not an object**, so it is drawn with the depth
// test off like the sky, immediately after it. That is what puts it in front
// of the stars -- a building occludes what is behind it -- and it is why
// nothing needs to depth-sort against it: the orrery and every bay of the
// hall are nearer and are drawn later.
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

/// @desc ...and the lamps burning in it, which is the half that says the room
///       is inhabited rather than ruined.
function hall_fill_rotunda_lit(_vb) {
    var _w = HALL_ROT_HW;
    var _h = HALL_ROT_HH;
    var _cy = HALL_ROT_Y0 + _h;
    hall_face(_vb, spr_hall_rot_lit, 0, 1,
              [-_w, _cy + _h, 0], [_w, _cy + _h, 0],
              [_w, _cy - _h, 0], [-_w, _cy - _h, 0],
              HALL_ROT_LIT, HALL_ROT_LIT_A);
}

/// @desc Lay the chamber down, over the stars and under everything else.
///
///       **Anchored to the camera's depth, exactly as the orrery is**, so the
///       flight never reaches it. At twelve and a half thousand units it is
///       past the last bay the hall draws and inside the far plane, which is
///       the only arithmetic it has to satisfy.
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
// The grand orrery
//
// **The thing at the end of the hall, and the reason the roof came off.** It
// is an armillary the size of a building, hanging above the nave far enough
// away that the flight never reaches it -- `bg_grove`'s moon, in a different
// sky. What it is *for* is that a corridor with nothing at the end of it is a
// corridor: the eye follows the perspective to the vanishing point, finds
// haze, and comes back.
//
// It is real geometry rather than a painted card, and that is not
// extravagance -- it is the only way it can *turn*. A ring seen face-on and
// the same ring seen edge-on are different shapes, and an armillary whose
// rings are continuously becoming one and then the other is the whole of what
// says "instrument" rather than "logo". Six rings at six rates is about two
// thousand triangles, built once and frozen, and the animation is six matrix
// multiplies a frame.
// ---------------------------------------------------------------------------

/// @desc A point turned by a tilt about x and then a yaw about y.
///
///       Factored out of `hall_ring`, which had it written inline, because
///       the orrery's bodies have to ride in the same plane as the rings they
///       belong to and a second copy of this is a second copy to get wrong.
function hall_orient(_x, _y, _z, _tilt, _yaw) {
    var _y2 = _y * dcos(_tilt) - _z * dsin(_tilt);
    var _z2 = _y * dsin(_tilt) + _z * dcos(_tilt);
    return [_x * dcos(_yaw) + _z2 * dsin(_yaw), _y2,
            -_x * dsin(_yaw) + _z2 * dcos(_yaw)];
}

/// @desc One quad with an explicit span of its sprite across it.
///
///       **The orrery's limbs are graduated, and a graduation has a pitch.**
///       `hall_face` puts the whole sprite on one quad, which for a ring of
///       forty segments is forty copies of the band -- which is not a scale,
///       it is grey. This is what lets the band repeat twice instead.
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

/// @desc A ring of square section, centred on the origin in its own plane.
///
///       **Four faces a segment, because an armillary's rings go edge-on.** A
///       flat annulus is invisible from its own plane, so a ring that spins
///       would vanish twice a turn and come back -- which reads as a bug
///       rather than as an instrument. With a section it narrows to a bright
///       line instead, which is what a band of metal actually does.
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

/// @desc A faceted ball, lit flat rather than by the hall's lamps.
///
///       `hall_sphere` goes through `hall_wall_light`, which measures the
///       distance to a bay's own lamp -- nine thousand units away that
///       answers the ambient and nothing else, so every one of these would be
///       the same flat dark grey. Out here the light is the object's own.
///
///       `_sy` squashes it down its own axis, which is the difference between
///       a bead and one of the lens-shaped bubbles the reference hangs off
///       its armature.
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

/// @desc A cone on the y axis: base of radius `_r` at `_y0`, apex at `_y1`.
///
///       **The pointed ends are what stop the armature reading as a rod.** A
///       shaft that simply stops is the same defect the grove's treeline had
///       -- a branch cut off in mid-air -- and the reference ends every one
///       of its members in a point.
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

/// @desc One of the orrery's rings, with whatever rides on it.
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

/// @desc A body riding on a ring of the same tilt and rate.
///
///       **It is in the ring's own frame**, so the orbit is the same matrix
///       the ring takes and cannot drift out of the ring it belongs to. It is
///       a *separate* buffer only because it needs a different texture, which
///       is the rule this file learnt when the ceiling drew the floor's ankhs.
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

/// @desc Build the instrument.
///
///       **Six rings, no two at the same rate and no two at the same tilt**,
///       which is the whole of why it never settles into a shape the eye can
///       learn. The outer limb does not turn at all: an armillary has a fixed
///       meridian that everything else is measured against, and something
///       stationary in the middle of all that movement is what makes the
///       movement legible.
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

/// @desc The heart of it, and the armature it all hangs from.
///
///       **The armature is the half of this that is not the rings.** Six
///       hoops sharing a middle are six hoops; a polar axis through them,
///       ending in a point at each end, with beads down it and a long
///       pointed pillar beneath, is an *instrument* somebody mounted. The
///       reference ends every member in a point and hangs lens-shaped
///       bubbles off the shaft, and both of those are silhouette rather than
///       detail -- which is what survives at three hundred pixels.
///
///       The pillar below is longer than the finial above, because the thing
///       is hanging: what is over it is a cap and what is under it is a
///       plumb.
function hall_fill_orrery_core(_vb) {
    var _R = HALL_ORRERY_R;
    var _g = HALL_ORRERY_GILT;
    var _l = HALL_ORRERY_DIM;
    var _pa = spr_hall_pale;

    // **Blue rather than white, and that is a fairness line rather than a
    // taste.** Driven at one and a half the core clipped every channel and
    // came back as a twenty-pixel white-hot blob -- which is what a bullet's
    // core is, in a sky bullets cross.
    hall_ball(_vb, 0, 0, 0, _R * 0.105, 14, 9, _pa, HALL_ORRERY_CORE,
              _l * 1.05);

    // the polar axis, as a pair of crossed blades so it reads from any angle
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

    // collars down the shaft, so it is turned rather than extruded
    var _beads = [0.40, 0.80, -0.40, -0.86, -1.22];
    for (var _i = 0; _i < array_length(_beads); _i++) {
        hall_ball(_vb, 0, _R * _beads[_i], 0, _R * 0.036, 10, 6, _pa, _g,
                  _l * 1.15, 0.62);
    }

    // and the bubbles: lens-shaped glass on the armature, which is the one
    // thing out here that is not metal
    var _bub = [[0.66, 0.115], [-0.60, 0.135], [-1.04, 0.100]];
    for (var _i = 0; _i < array_length(_bub); _i++) {
        // **Lit glass, not `HALL_GLASS`.** That colour is the hourglass on
        // a reading desk six hundred units from a lamp; out here it resolves
        // to a dull grey lozenge, which is what these came back as. A bubble
        // on this armature is the one thing in the instrument that is not
        // metal, and it has to say so by being *cool and bright* against the
        // gold rather than by being a different grey.
        hall_ball(_vb, 0, _R * _bub[_i][0], 0, _R * _bub[_i][1], 12, 7, _pa,
                  make_colour_rgb(176, 208, 244), _l * 1.2, 0.54);
    }
}

/// @desc ...and the light it throws, which is a second ball over the first
///       and a bloom on every bubble.
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

/// @desc The bloom behind it. One soft card, and it is what makes an object
///       nine thousand units off read as *luminous* rather than as pale.
function hall_fill_orrery_halo(_vb) {
    var _r = HALL_ORRERY_HALO_R;
    hall_face(_vb, spr_fx_bloom, 0, 1,
              [-_r, _r, 0], [_r, _r, 0], [_r, -_r, 0], [-_r, -_r, 0],
              HALL_ORRERY_CORE, HALL_ORRERY_HALO_A);
}

/// @desc Draw it, turning.
///
///       **Depth-tested and depth-written, unlike the sky.** A solid object
///       drawn with the depth test off shows its own far side through its
///       near one -- which on six nested rings is every ring at once, and
///       reads as a tangle of wire rather than as a sphere of them. It is
///       nearer than the far plane and further than every bay the hall draws,
///       so the depth buffer sorts it against itself and the hall then paints
///       over it exactly where the hall is in the way.
///
///       **The fog is off and the dimming is baked into the colours.** At
///       nine thousand units hardware fog is total -- `HALL_FOG_END` is 6400
///       -- so a fogged orrery is a rectangle of fog colour. What distance
///       does to something bright is take its contrast away, which is a
///       multiply.
///
///       It breathes by *scale* rather than by alpha, because a vertex
///       buffer's alpha is frozen into it and its size is one matrix.
function hall_draw_orrery(_b) {
    var _oz = hall_cam_z(_b) + HALL_ORRERY_Z;
    var _base = matrix_build(0, HALL_ORRERY_Y, _oz, 0, 0, 0, 1, 1, 1);
    var _pulse = 1 + 0.055 * dsin(_b.t * 360 / HALL_ORRERY_PULSE);

    gpu_set_ztestenable(true);
    gpu_set_zwriteenable(false);
    gpu_set_fog(false, c_black, 0, 1);

    // the bloom first, behind the metal, adding to the sky
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

    // and the core's own light over all of it
    gpu_set_zwriteenable(false);
    gpu_set_blendmode(bm_add);
    matrix_set(matrix_world,
               matrix_build(0, HALL_ORRERY_Y, _oz, 0, 0, 0,
                            _pulse, _pulse, _pulse));
    hall_submit(_b.vb_orrery_glow, sprite_get_texture(spr_hall_pale, 0));
    gpu_set_blendmode(bm_normal);
    gpu_set_zwriteenable(true);
}

/// @desc The one pass drawn over live danmaku.
///
///       **Additive without exception**, which is the rule `grove_draw_front`
///       keeps and for the same reason: a corridor cannot keep out of the
///       middle of the field the way stage one's near layer does, and light
///       can only ever brighten what is behind it -- so an additive
///       foreground cannot conceal a bullet at any alpha, at any size, in any
///       arrangement.
function hall_draw_front(_b, _spell, _fill) {
    // ...and the dust comes up with the room. It is drawn after the veil, so
    // without this the one thing visible during the arrival is the motes.
    var _a = (1 - 0.86 * clamp(_spell, 0, 1)) * hall_ease(_b.intro);
    if (_a <= 0.01) return;
    var _x0 = _fill ? 0 : FIELD_X0;
    var _y0 = _fill ? 0 : FIELD_Y0;
    var _w = _fill ? GAME_W : FIELD_W;
    var _h = _fill ? GAME_H : FIELD_H;

    // Dust. Derived from the clock rather than simulated, the way the
    // brimstone stage's embers are: a phase and a rate, and where a mote is
    // this frame is `frac` of the two.
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < HALL_DUST_N; _i++) {
        var _ph = hall_hash(_i, 11);
        var _rate = 0.00018 + hall_hash(_i, 12) * 0.0007;
        var _fy = frac(_ph + _b.t * _rate);
        var _px = _x0 + hall_hash(_i, 13) * _w
                  + dsin(_b.t * 0.5 + _i * 37) * 22;
        var _py = _y0 + (1 - _fy) * _h;
        var _sz = 1.4 + hall_hash(_i, 14) * 3.0;
        draw_sprite_ext(spr_fx_bloom, 0, _px, _py, _sz * 0.05, _sz * 0.05, 0,
                        HALL_DUST_COL, 0.24 * _a * (0.35 + 0.65 * _fy));
    }
    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}
