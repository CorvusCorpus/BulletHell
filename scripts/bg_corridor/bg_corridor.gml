/// @desc The corridor projection and prop rings used by stage two's
///       background (`bg_grove` arranges the forest in it). A world the camera
///       flies into, rather than layers scrolling past.
///
/// The camera sits at the origin looking down +z, `CORRIDOR_CAM_H` above the
/// ground plane:
///
///     k  = focal / z              -- screen pixels per world unit at depth z
///     sx = centre + k * wx
///     sy = horizon + k * wy
///
/// with `wy` measured down from the camera, so the ground is at
/// `wy = CORRIDOR_CAM_H`. A prop's position, scale and haze all come from `k`
/// (`corridor_k`).
///
/// Props live in ring buffers so they can be drawn in depth order: `head` is
/// the nearest, and a prop that passes the camera is recycled to the back and
/// becomes the farthest. (Deriving positions from the clock, as the embers do,
/// wouldn't keep a stable depth order, and the corridor changes speed.) Slots
/// are evenly spaced in z, with each prop jittered within half a slot so the
/// order never changes.

// ---------------------------------------------------------------------------
// The camera
// ---------------------------------------------------------------------------

/// @desc Screen pixels per world unit at depth `_z`, clamped at the near plane
///       (so nothing can project to an enormous size).
function corridor_k(_z) {
    return CORRIDOR_FOCAL / max(_z, CORRIDOR_Z_MIN);
}

/// @desc The horizon's screen y (the vanishing point), including the camera's
///       pitch `oy`. Every position in the corridor is measured from it.
function corridor_horizon(_v) {
    return _v.y0 + _v.h * CORRIDOR_HORIZON + _v.oy;
}

/// @desc The depth of the ground at screen row `_sy` (the inverse of the
///       projection), clamped to `CORRIDOR_Z_FAR`. Without the clamp, rows at
///       the horizon report enormous or infinite depths, which drew a stray red
///       line from the grove's blood wavefront (parked beyond the far plane).
function corridor_depth_at(_v, _sy) {
    var _d = _sy - corridor_horizon(_v);
    if (_d <= 0.5) return CORRIDOR_Z_FAR;        // at or above the horizon
    return min(CORRIDOR_Z_FAR, CORRIDOR_FOCAL * CORRIDOR_CAM_H / _d);
}

/// @desc The viewport a corridor is drawn into: the field, or with `_fill`
///       the whole screen (the rack).
///
///       `_ox` and `_oy` are the camera's yaw and pitch as screen-pixel offsets
///       (everything shifts equally, as under a rotation); they move `cx` and
///       the horizon. `_lat` is a sideways translation in world units: each
///       prop shifts by `corridor_k` of its own depth, which gives parallax
///       (the moon doesn't move, near trunks move a lot). Bands tiled from the
///       view's left edge apply `ox` themselves (`grove_rooted_x`).
function corridor_view(_fill, _ox = 0, _oy = 0, _lat = 0) {
    if (_fill) {
        // Screen-pixel offsets scale with the enlarged view.
        var _s = GAME_W / FIELD_W;
        return { x0: 0, y0: 0, w: GAME_W, h: GAME_H,
                 cx: GAME_W / 2 + _ox * _s, x1: GAME_W, y1: GAME_H,
                 ox: _ox * _s, oy: _oy * _s, lat: _lat };
    }
    return { x0: FIELD_X0, y0: FIELD_Y0, w: FIELD_W, h: FIELD_H,
             cx: FIELD_CX + _ox, x1: FIELD_X1, y1: FIELD_Y1,
             ox: _ox, oy: _oy, lat: _lat };
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

/// @desc A ring of `_n` props spread evenly from depth `_z0` to `_z1`.
///       `_make(prop, lap)` sets up a prop each time it is recycled; decide
///       its variety from the lap number (e.g. `corridor_hash`) rather than
///       `random`, so the forest is the same on every attempt.
function corridor_ring(_n, _z0, _z1, _make) {
    var _r = {
        n: _n,
        z0: _z0,
        z1: _z1,
        span: _z1 - _z0,
        slot: (_z1 - _z0) / _n,
        // How far in front of its far plane a prop fades in
        // (`corridor_prop_fade`).
        fade: (_z1 - _z0) * 0.30,
        head: 0,            // the index of the nearest prop
        lap: 0,
        props: [],
        // The draw order, allocated once and refilled in place.
        order: array_create(_n, 0),
        make: _make,
    };
    var _slot = _r.span / _n;
    _r.slot = _slot;
    for (var _i = 0; _i < _n; _i++) {
        // Index 0 is the nearest, so z counts up from the near plane.
        var _p = {
            z: _z0 + _slot * (_i + 0.5),
            slot: _slot,
            wx: 0, wy: 0,
            frame: 0, flip: 1, sway: 0,
            // Per-prop size and width multipliers, so the same few frames
            // don't all look identical.
            scale: 1, aspect: 1,
            // The prop's kind and its ring's far plane and fade band, carried
            // on the prop because the merged draw pass has no ring to ask.
            // `tag` and `hang` are for what a stage hangs off the prop (its
            // kind, and which branch tip).
            kind: 0,
            far: _z1,
            fadeband: (_z1 - _z0) * 0.38,
            tag: -1, hang: 0,
            // This prop's current jitter within its slot (removed before the
            // next one is applied; see `corridor_ring_step`).
            jit: 0,
            a: 1,
        };
        _make(_p, _i);
        array_push(_r.props, _p);
    }
    return _r;
}

/// @desc Move every prop `_dz` toward the camera and recycle those that pass
///       the near plane. Only the head (nearest) can pass, so this loops on
///       the head.
function corridor_ring_step(_r, _dz) {
    for (var _i = 0; _i < _r.n; _i++) _r.props[_i].z -= _dz;

    var _guard = 0;
    while (_guard++ < _r.n) {
        var _p = _r.props[_r.head];
        if (_p.z > _r.z0) break;
        _p.z += _r.span;
        _r.lap++;
        _r.make(_p, _r.lap);

        // Replace (not add to) the prop's jitter within its slot, bounded to
        // half a slot so the depth order never changes. Adding it every lap
        // made props drift out of their slots and order.
        var _j = (corridor_hash(_r.lap, 5) - 0.5) * _r.slot * 0.9;
        _p.z += _j - _p.jit;
        _p.jit = _j;

        _r.head = (_r.head + 1) mod _r.n;
    }
}

/// @desc The ring's props far to near, as indices (walking back from the
///       head). There is no depth buffer, so far-to-near is required.
function corridor_ring_order(_r) {
    for (var _j = 0; _j < _r.n; _j++) {
        _r.order[_j] = (_r.head + _r.n - 1 - _j) mod _r.n;
    }
    return _r.order;
}

/// @desc 0..1: how far a prop has faded in, measured from its own ring's far
///       plane (measuring against `CORRIDOR_Z_FAR` made short rings' props pop
///       in half-visible).
function corridor_prop_fade(_p) {
    return clamp((_p.far - _p.z) / max(1, _p.fadeband), 0, 1);
}

/// @desc Set up a merged, depth-sorted walk over several rings. Rings have
///       different depth ranges, but drawing them one ring at a time would
///       draw a nearer ring's props under a farther ring's; this k-way merges
///       the already-sorted rings into one far-to-near list.
function corridor_merge_new(_rings) {
    var _n = array_length(_rings);
    var _total = 0;
    for (var _i = 0; _i < _n; _i++) _total += _rings[_i].n;
    return {
        rings: _rings,
        n: _n,
        cur: array_create(_n, 0),
        out: array_create(_total, undefined),
        total: _total,
    };
}

/// @desc Refill `_m.out` with every prop in every ring, far to near.
function corridor_merge_step(_m) {
    for (var _i = 0; _i < _m.n; _i++) {
        corridor_ring_order(_m.rings[_i]);      // refreshes ring.order in place
        _m.cur[_i] = 0;
    }
    for (var _k = 0; _k < _m.total; _k++) {
        var _best = -1;
        var _bz = -1;
        for (var _i = 0; _i < _m.n; _i++) {
            var _r = _m.rings[_i];
            if (_m.cur[_i] >= _r.n) continue;
            var _z = _r.props[_r.order[_m.cur[_i]]].z;
            if (_z > _bz) {
                _bz = _z;
                _best = _i;
            }
        }
        var _rb = _m.rings[_best];
        _m.out[_k] = _rb.props[_rb.order[_m.cur[_best]]];
        _m.cur[_best]++;
    }
    return _m.total;
}

/// @desc A stable pseudo-random number in [0, 1) from two integers. (`frac`
///       keeps its sign in GML, hence the fold.)
function corridor_hash(_a, _b) {
    var _v = frac(sin(_a * 12.9898 + _b * 78.233) * 43758.5453);
    return (_v + 1) mod 1;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc 0..1: how much of a prop at depth `_z` shows through the haze (1 up
///       to `CORRIDOR_Z_CLEAR`, 0 at `CORRIDOR_Z_FAR`).
function corridor_haze(_z) {
    return 1 - clamp((_z - CORRIDOR_Z_CLEAR)
                     / (CORRIDOR_Z_FAR - CORRIDOR_Z_CLEAR), 0, 1);
}

/// @desc 0..1: the fade just before the near plane, so a prop that reaches
///       it doesn't blink out.
function corridor_near_fade(_z) {
    return clamp((_z - CORRIDOR_Z_MIN) / (CORRIDOR_Z_NEAR - CORRIDOR_Z_MIN),
                 0, 1);
}

/// @desc Draw one billboard. `_wh` is its height in world units (the sprite's
///       height converts it to a scale). `_rim` is a second sprite drawn
///       additively over it (the rim light; it may be lower resolution, the
///       scale is derived from the two heights). `_anchor` is how far below
///       the camera it is fixed (`CORRIDOR_CAM_H` stands on the ground;
///       negative hangs above), and `_yflip` -1 hangs the sprite downward
///       (boughs).
function corridor_draw_prop(_v, _spr, _rim, _frame, _z, _wx, _wh, _flip,
                            _col, _rim_col, _a, _rim_a, _aspect = 1,
                            _anchor = CORRIDOR_CAM_H, _yflip = 1) {
    var _k = corridor_k(_z);
    // The camera's sideways position is subtracted in world space (parallax).
    var _sx = _v.cx + _k * (_wx - _v.lat);
    var _sy = corridor_horizon(_v) + _k * _anchor;
    var _s = _k * _wh / sprite_get_height(_spr);

    draw_sprite_ext(_spr, _frame, _sx, _sy, _s * _flip * _aspect,
                    _s * _yflip, 0, _col, _a);

    if (_rim_a > 0.004) {
        var _rs = _s * sprite_get_height(_spr) / sprite_get_height(_rim);
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(_rim, _frame, _sx, _sy, _rs * _flip * _aspect,
                        _rs * _yflip, 0, _rim_col, _rim_a);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc Half the world width of a prop of height `_wh` (placement needs the
///       inner edge, not the centre; see `grove_make_trunk`).
function corridor_prop_half_w(_spr, _wh, _scale, _aspect) {
    return _wh * _scale * _aspect * 0.5
           * sprite_get_width(_spr) / sprite_get_height(_spr);
}

/// @desc Draw the ground as a triangle strip of rows, each coloured by
///       `_shade(bg, z, out, step)` for the depth under that row. `_shade`
///       writes into `out` (to avoid allocating per row). `step` is the depth
///       the row covers: patterns periodic in depth must fade out when their
///       period drops below a row, or they alias into crawling bands.
function corridor_draw_ground(_v, _b, _shade, _out, _rows = 90) {
    var _hy = corridor_horizon(_v);
    var _y0 = _hy + 2;
    if (_y0 >= _v.y1) return;

    var _row = (_v.y1 - _y0) / _rows;
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _rows; _i++) {
        // Stepped evenly in screen y (i.e. in 1/z), not in z.
        var _sy = _y0 + (_v.y1 - _y0) * (_i / _rows);
        var _z = corridor_depth_at(_v, _sy);
        // The depth this row covers.
        var _step = abs(corridor_depth_at(_v, _sy + _row) - _z);
        _shade(_b, _z, _out, _step);
        draw_vertex_colour(_v.x0, _sy, _out.col, _out.a);
        draw_vertex_colour(_v.x1, _sy, _out.col, _out.a);
    }
    draw_primitive_end();
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A horizontal band sprite tiled across the view at offset `_drift`
///       (folded into [0, w), since GML's `mod` keeps sign).
function corridor_draw_band(_v, _spr, _drift, _sy, _sc, _col, _a) {
    if (_a <= 0.004) return;
    var _w = sprite_get_width(_spr) * _sc;
    var _off = ((_drift mod _w) + _w) mod _w;
    var _x = _v.x0 - _off;
    while (_x < _v.x1) {
        draw_sprite_ext(_spr, 0, _x, _sy, _sc, _sc, 0, _col, _a);
        _x += _w;
    }
}

/// @desc How far down a wave band's baseline drops at `_u` (0..1 along its
///       tile). Only ever downward (raised cosines, so it is in `[0, _amp]`
///       by construction): the band's foot sits on the horizon, and lifting it
///       would show sky under it. Periodic in the tile (whole harmonics), so
///       there is no step at the tile seams (`test_corridor` checks).
function corridor_band_wave(_u, _amp, _seed) {
    return _amp * ((0.5 - 0.5 * dcos(_u * 360)) * 0.54
                   + (0.5 - 0.5 * dcos(_u * 720 + _seed)) * 0.30
                   + (0.5 - 0.5 * dcos(_u * 1440 + _seed * 2)) * 0.16);
}

/// @desc The band with its baseline undulating (`corridor_band_wave`), drawn
///       as one textured triangle strip per tile. A strip, not slices: slices
///       overlapped by a pixel to hide seams, which doubled up translucent
///       bands into visible vertical lines.
///
///       - Texture coordinates run 0..1 across the sprite, not across the
///         texture page: in this runtime a primitive textured with
///         `sprite_get_texture` reads the sprite's own UV space.
///         `sprite_get_uvs` is used only for the trim (the empty border
///         cropped at packing). `test_band_strip` checks this every run.
///       - UVs are inset half a texel so bilinear sampling doesn't pick up the
///         neighbouring art on the page at tile seams.
///       - `_dip` squashes the band toward its foot by up to that fraction of
///         its height around the view's centre line, over `_dip_w` px (where
///         the path runs into the hedge).
function corridor_draw_band_wave(_v, _spr, _drift, _sy, _sc, _col, _a,
                                 _amp, _seed, _dip = 0, _dip_w = 1) {
    if (_a <= 0.004) return;
    var _tw = sprite_get_width(_spr);
    var _th = sprite_get_height(_spr);
    var _uv = sprite_get_uvs(_spr, 0);
    var _tex = sprite_get_texture(_spr, 0);

    // The trimmed part of the sprite, in its own pixels (only `_uv[4..7]` is
    // used; `_uv[0..3]` are in page space).
    var _kx0 = _uv[4];
    var _kx1 = _uv[4] + _tw * _uv[6];
    var _ky0 = _uv[5];
    var _ky1 = _uv[5] + _th * _uv[7];
    var _hu = 0.5 / max(1, _kx1 - _kx0);
    var _hv = 0.5 / max(1, _ky1 - _ky0);
    var _u0 = _hu;
    var _u1 = 1 - _hu;
    var _v0 = _hv;
    var _v1 = 1 - _hv;

    var _w = _tw * _sc;
    var _off = ((_drift mod _w) + _w) mod _w;
    var _top0 = _sy + _ky0 * _sc;
    var _bot0 = _sy + _ky1 * _sc;
    var _n = CORRIDOR_BAND_COLS;
    var _x = _v.x0 - _off;
    while (_x < _v.x1) {
        draw_primitive_begin_texture(pr_trianglestrip, _tex);
        for (var _i = 0; _i <= _n; _i++) {
            var _f = _i / _n;
            var _src = lerp(_kx0, _kx1, _f);
            var _px = _x + _src * _sc;
            var _d = corridor_band_wave(_src / _tw, _amp, _seed);
            var _top = _top0 + _d;
            var _bot = _bot0 + _d;
            if (_dip > 0) {
                _top = lerp(_top, _bot, _dip * corridor_band_dip(_v, _px, _dip_w));
            }
            var _u = lerp(_u0, _u1, _f);
            draw_vertex_texture_colour(_px, _top, _u, _v0, _col, _a);
            draw_vertex_texture_colour(_px, _bot, _u, _v1, _col, _a);
        }
        draw_primitive_end();
        _x += _w;
    }
}

/// @desc 0..1: how much a band is squashed at screen x `_px`: 1 on the view's
///       centre line, 0 beyond `_w` either side, smoothstepped between.
function corridor_band_dip(_v, _px, _w) {
    var _g = clamp(1 - abs(_px - _v.cx) / max(1, _w), 0, 1);
    return _g * _g * (3 - 2 * _g);
}
