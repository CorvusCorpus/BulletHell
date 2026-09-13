/// @desc A world the camera flies *into*, rather than one that scrolls past.
///
/// **Stage one is a floor and this is a corridor, and that is a difference in
/// the projection rather than in the art.** `bg_functions` draws three sprites
/// the size of the field sliding down the screen, which is exactly right for a
/// basalt pavement seen from above: everything in it is the same distance
/// away, so everything in it moves at one rate and depth is bought with
/// parallax between three flat plates.
///
/// A forest cannot be drawn that way. The player is flying *through* it at
/// head height, so a tree fifty metres off and a tree five metres off are not
/// two layers, they are one object at two depths -- and the whole of what
/// makes the shot read is that a tree grows, slides outward, and leaves past
/// the edge of the frame, accelerating the entire time. That is one divide per
/// prop and it cannot be got from a parallax rate.
///
/// So this file is the projection and the prop pool, and it knows nothing
/// about forests. `bg_grove` is what is arranged in it.
///
/// The camera
/// ----------
///
/// It sits at the origin looking down +z, `CORRIDOR_CAM_H` above a ground
/// plane, and the picture is
///
///     k  = focal / z              -- screen pixels per world unit at depth z
///     sx = centre + k * wx
///     sy = horizon + k * wy
///
/// with `wy` measured **down from the camera**, so the ground is at
/// `wy = CORRIDOR_CAM_H` and a tree's root is on it. Everything else here is
/// that identity and some bookkeeping.
///
/// **`k` is the only thing a caller ever needs.** A prop's screen position,
/// its scale, how fast it is travelling across the frame and how much haze is
/// in front of it are all functions of it, which is why `corridor_k` is the
/// one projection function and not four.
///
/// Why there is a ring buffer
/// --------------------------
///
/// `bg_draw_embers` derives its motes from the clock: a phase and a rate, and
/// where a mote is this frame is `frac` of the two. Nothing to step, nothing
/// to respawn, and a background that has been off screen for a minute is
/// already correct on the frame it comes back. That is the right shape and it
/// does not work here, for two reasons.
///
/// The first is speed: the corridor accelerates half way through the grove,
/// and a position derived from `t` would teleport every prop on the frame the
/// speed changed. That one is fixable -- derive from an accumulated distance
/// instead, which is what `dist` is.
///
/// The second is not. **These props overlap, so they have to be drawn in depth
/// order**, and a set of positions derived by `frac` is sorted only up to a
/// rotation that moves every frame. Finding where the rotation is each frame
/// costs more than keeping the order, so the order is kept: props live in a
/// ring, `head` is the nearest, and a prop that passes the camera is pushed to
/// the back of the queue and becomes the farthest. Drawing far to near is then
/// walking the ring backwards from `head`, which is exact and costs nothing.
///
/// **The slots are evenly spaced in z and jittered inside their own slot.**
/// Even spacing is what keeps the ring order true for ever; the jitter is what
/// stops a corridor of evenly spaced trees reading as a picket fence. The
/// jitter is bounded by half a slot precisely so it cannot reorder anything.

// ---------------------------------------------------------------------------
// The camera
// ---------------------------------------------------------------------------

/// @desc Screen pixels per world unit at depth `_z`.
///
///       **Clamped at the near plane rather than guarded at the call site.**
///       A prop at z of nearly zero projects to a scale of nearly infinity,
///       and one frame of that is a sprite drawn at ten thousand per cent
///       across the whole screen. Every prop is culled long before it gets
///       there -- see `corridor_prop_step` -- and the clamp is here anyway,
///       because the cost of being wrong about that is not a glitch, it is
///       the game stopping.
function corridor_k(_z) {
    return CORRIDOR_FOCAL / max(_z, CORRIDOR_Z_MIN);
}

/// @desc Where the eye is looking: the vanishing point of the corridor.
///
///       **`oy` is the camera's pitch, and it is added here rather than at
///       the call sites.** The horizon is what every other position in this
///       file is measured from -- a prop's footing, the ground's rows, the
///       moon, the far wood -- so putting the pitch in it once is what makes
///       the whole picture move as one body. Added anywhere else it would be
///       a list of layers that each had to remember, and the one that forgot
///       would be a layer sliding against the rest of the world.
function corridor_horizon(_v) {
    return _v.y0 + _v.h * CORRIDOR_HORIZON + _v.oy;
}

/// @desc The depth of the ground under a given screen row. The inverse of the
///       projection, and what the ground plane is drawn from.
///
///       **Clamped at the far plane, and that is not tidiness.** The inverse
///       of a perspective divide has no far end: a row one pixel under the
///       horizon reports a quarter of a million units, and a row *on* it
///       reports infinity. Nothing in the corridor exists out there, so every
///       reader of this number has to cope with a depth no prop can ever have
///       -- and one of them did not.
///
///       What that drew was a thin dark red line across the field, a couple of
///       pixels under the horizon, in a stage that had not turned and would
///       not for another two minutes: the grove's blood wavefront is parked
///       *beyond* the far plane to mean "nothing has happened yet", and the
///       only thing in the world further away than the parked wavefront was
///       the ground under the horizon. It read as a rendering artefact,
///       because that is what it was, and no assertion was ever going to see
///       it -- every number involved was inside its own range.
///
///       So the corridor has a back wall, here, once. Beyond `CORRIDOR_Z_FAR`
///       there is fog and nothing else, which is already what `corridor_haze`
///       says.
function corridor_depth_at(_v, _sy) {
    var _d = _sy - corridor_horizon(_v);
    if (_d <= 0.5) return CORRIDOR_Z_FAR;        // at or above the horizon
    return min(CORRIDOR_Z_FAR, CORRIDOR_FOCAL * CORRIDOR_CAM_H / _d);
}

/// @desc The rectangle a corridor is drawn into.
///
///       **A viewport rather than a scale factor**, because the two places
///       that draw a background disagree about more than size: a run draws it
///       into the field, and the stage rack draws it across the whole screen
///       with no field at all. `bg_draw_back`'s `_fill` handles that for the
///       parallax stack by scaling a sprite; here there is no sprite to scale
///       -- every position is computed -- so what the arithmetic needs is the
///       box, and it needs it in one place rather than at forty call sites.
///       **`_ox` and `_oy` are where the camera is pointing, in screen
///       pixels, and they are a rotation rather than a translation.** That
///       distinction is the whole of why a moving camera reads as a camera:
///       under a small yaw *everything* on screen shifts by the same number
///       of pixels -- the moon at infinity, the far wall of wood, a tree ten
///       metres off and the ground under it -- because they have all turned
///       through the same angle. Sliding the camera sideways instead would
///       move the near trees and leave the moon where it was, which is not a
///       flyer looking somewhere else, it is a world on rails behind a pane
///       of glass.
///
///       So the offsets go into the two numbers every position in the
///       corridor is measured from, `cx` and the horizon, and nothing that
///       draws a prop has to know the camera exists. The exception is the
///       three bands -- the treeline, the canopy and the mist -- which are
///       tiled from the edge of the view rather than from its centre and so
///       take `-ox` off their own drift; `ox` is kept on the view for exactly
///       that.
///       **`_lat` is the third one and it is a *translation*, in world units
///       rather than screen pixels, which is the whole of where parallax
///       comes from.** A yaw moves the moon, the far wood and the nearest
///       trunk by the same number of pixels, because they have all turned
///       through the same angle -- so a camera with nothing but a yaw is a
///       camera the depth of the scene cannot be read from. A camera that
///       *slides* moves each thing by `corridor_k` of its own depth: the moon
///       at infinity does not move at all, the far wall of wood barely does,
///       and the canopy overhead sweeps. That is the illusion of flying
///       through a wood rather than of panning across a picture of one, and
///       it costs one subtraction in `corridor_draw_prop` because the
///       projection was already there.
///
///       It is not scaled by `_s` in fill mode, and `_ox` is, because they
///       are different kinds of number: `_ox` is screen pixels and `_lat` is
///       world units that meet the screen through `_k`, exactly as a prop's
///       own `_wx` does.
function corridor_view(_fill, _ox = 0, _oy = 0, _lat = 0) {
    if (_fill) {
        // The world is authored at the field's size, so a view that covers
        // the whole screen has to scale the camera's throw with everything
        // else or the bob is a third of what it is in play.
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

/// @desc A ring of `_n` props spread evenly through the corridor's depth.
///
///       `_make` is called with the prop and a lap number every time one is
///       recycled, and is where a stage decides what this one is. It is
///       handed the lap so that **what a prop becomes is a function of which
///       trip round it is on** -- the same argument `hex_spray_dir` makes for
///       hashing an index rather than calling `random`: noise that differs
///       every attempt is not a thing a player can learn, and a corridor
///       whose trees are in different places on the second run is a corridor
///       nobody can build a memory of.
function corridor_ring(_n, _z0, _z1, _make) {
    var _r = {
        n: _n,
        z0: _z0,
        z1: _z1,
        span: _z1 - _z0,
        slot: (_z1 - _z0) / _n,
        // **How far in front of its own far plane a prop fades up.** See
        // `corridor_ring_fade`: this is the number that stops a ring popping.
        fade: (_z1 - _z0) * 0.30,
        head: 0,            // the index of the nearest prop
        lap: 0,
        props: [],
        // The draw order, allocated once and refilled in place. A fresh array
        // a frame is the one allocation this file would otherwise make, and
        // the pools in this game are written the way they are precisely so
        // that a busy screen allocates nothing after its first second.
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
            // What a stage hangs off this prop, and where. `tag` is the kind
            // and `hang` is which of the sprite's own branch tips -- both are
            // meaningless to the projection and named rather than reused,
            // because a corridor whose props carry a `wy` that is sometimes a
            // height and sometimes an array index is a corridor nobody can
            // read.
            // **How big this one is, and how wide for its height.** A ring
            // of billboards is a handful of frames drawn hundreds of times,
            // and a frame always drawn at the same size is a frame the eye
            // learns in about four seconds -- it was reported as the same
            // tree pasted over and over, which is what it was. Two numbers
            // per prop turn eight silhouettes into eight hundred, and they
            // cost one multiply each at draw time.
            scale: 1, aspect: 1,
            // **What kind of thing this is, and where its own ring ends.**
            // Both are carried by the prop rather than looked up through the
            // ring, because once every ring's props are merged into one
            // depth-sorted pass there is no ring to hand to the draw.
            kind: 0,
            far: _z1,
            fadeband: (_z1 - _z0) * 0.38,
            tag: -1, hang: 0,
            // Where in its own slot this one is standing. **Kept, because it
            // has to be taken back off.** See `corridor_ring_step`.
            jit: 0,
            a: 1,
        };
        _make(_p, _i);
        array_push(_r.props, _p);
    }
    return _r;
}

/// @desc Advance every prop toward the camera by `_dz` and recycle what passes.
///
///       **The nearest one is the only one that can pass**, because they are
///       in depth order and they all move at the same rate -- so the recycle
///       is a `while` on the head rather than a scan, and the ring stays
///       sorted by construction rather than by being sorted.
function corridor_ring_step(_r, _dz) {
    for (var _i = 0; _i < _r.n; _i++) _r.props[_i].z -= _dz;

    var _guard = 0;
    while (_guard++ < _r.n) {
        var _p = _r.props[_r.head];
        if (_p.z > _r.z0) break;
        _p.z += _r.span;
        _r.lap++;
        _r.make(_p, _r.lap);

        // **The jitter is the ring's, and it is a replacement rather than an
        // addition.** Perfectly even slots keep the order true for ever and
        // read as a picket fence, so each prop stands a little off its own
        // slot -- but the offset has to be *taken back off* before the next
        // one is applied. It was applied inside `_make`, where every lap
        // added another one: over a couple of minutes the props wandered out
        // of their slots, then out of each other's order, and the depth
        // sorting the whole corridor rests on quietly stopped being true.
        //
        // Bounded by half a slot precisely so it cannot reorder anything.
        // Here rather than in the content for the same reason: an invariant
        // a stage could break by writing an ordinary-looking line is an
        // invariant nobody has.
        var _j = (corridor_hash(_r.lap, 5) - 0.5) * _r.slot * 0.9;
        _p.z += _j - _p.jit;
        _p.jit = _j;

        _r.head = (_r.head + 1) mod _r.n;
    }
}

/// @desc The props far to near, as an array of indices.
///
///       Walking the ring backwards from the head. **Far to near is the only
///       order that composites correctly** -- these are alpha-blended
///       silhouettes with no depth buffer behind them, so a near tree drawn
///       first is a near tree with a far one painted over it.
function corridor_ring_order(_r) {
    for (var _j = 0; _j < _r.n; _j++) {
        _r.order[_j] = (_r.head + _r.n - 1 - _j) mod _r.n;
    }
    return _r.order;
}

/// @desc How much of a prop at depth `_z` has arrived: 0 at its ring's own
///       far plane, 1 well inside it.
///
///       **A prop fades in at *its* far plane, not at the corridor's**, and
///       the difference between those two is a pop. `corridor_haze` is
///       measured against `CORRIDOR_Z_FAR`, which is the back of the whole
///       world -- so a ring that only reaches a third of the way out there was
///       recycling its props into a place where the haze was still two thirds
///       clear, and every fern and every trunk in this wood snapped into
///       existence at about seventy per cent opacity. It was reported as bad
///       pop-in on the grass, which is exactly what it was.
///
///       Every ring gets this whatever its span, so a ring added later cannot
///       be the one that forgot.
function corridor_prop_fade(_p) {
    return clamp((_p.far - _p.z) / max(1, _p.fadeband), 0, 1);
}

/// @desc One depth-sorted walk over several rings at once.
///
///       **Rings are separate because their depths are, and that is exactly
///       why they cannot be *drawn* separately.** A ring of trees runs out to
///       the far plane, a ring of trunks to half of it and a ring of ferns to
///       less; giving them one shared span would either crowd the near ground
///       with trees or spread the ferns over four times the depth they belong
///       in. So there are four rings -- and for three passes they were drawn
///       as four sequential loops, which means every trunk in the wood was
///       drawn over every tree in it whatever their depths.
///
///       What that looks like is what it was reported as: a big tree fading in
///       *in front of* a small tree that was already closer. Depth order is
///       not a property of a ring, it is a property of the frame.
///
///       Each ring is already sorted, so this is a k-way merge -- one linear
///       pass, no comparisons beyond the heads, and the output array is
///       allocated once and refilled in place.
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

/// @desc A stable pseudo-random number in 0..1 from two integers.
///
///       **`frac` keeps its sign in GML**, so a hash built on it comes back
///       in (-1, 1) and half of everything indexed by it lands on entry zero.
///       That is a real bug this project has already shipped once -- see
///       `hex_debris` -- and the `+ 1` fold is the whole fix.
function corridor_hash(_a, _b) {
    var _v = frac(sin(_a * 12.9898 + _b * 78.233) * 43758.5453);
    return (_v + 1) mod 1;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc How much of a prop at depth `_z` is left after the air in front of
///       it: 0 at the far plane, 1 close up.
///
///       **Depth is value.** It is the rule stage one's parallax stack is
///       built on and it is doing more work here, because in a corridor the
///       *same* object appears at every distance at once -- so a tree that
///       arrives at full contrast is a tree that pops into existence at the
///       far plane. The haze is what makes it fade up out of the fog instead.
function corridor_haze(_z) {
    return 1 - clamp((_z - CORRIDOR_Z_CLEAR)
                     / (CORRIDOR_Z_FAR - CORRIDOR_Z_CLEAR), 0, 1);
}

/// @desc ...and how much of it is left after the near fade.
///
///       A prop is culled at the near plane, and something has to happen in
///       the last stretch before it or a tree the size of the screen blinks
///       out. In practice the trees stand well off the path and leave sideways
///       long before this matters; it is here for the ones that do not.
function corridor_near_fade(_z) {
    return clamp((_z - CORRIDOR_Z_MIN) / (CORRIDOR_Z_NEAR - CORRIDOR_Z_MIN),
                 0, 1);
}

/// @desc Draw one billboard standing on the ground plane.
///
///       `_wh` is how tall the thing is in world units; the sprite's own
///       height is what turns that into a scale, so a taller sprite of the
///       same tree is the same tree and not a bigger one.
///
///       **The rim is a second sprite and it is derived, not configured.**
///       It ships at half the body's resolution -- there is nothing in a
///       blurred edge that half a pixel could lose -- and the factor is read
///       off the two sprites rather than written down anywhere, because a
///       number in two files is a number that gets edited in one.
///       `_anchor` is how far *below the camera* the thing is fixed, so
///       `CORRIDOR_CAM_H` is a thing standing on the ground and a negative
///       value is a thing hanging above one. `_yflip` of -1 turns a sprite
///       that grows up from its origin into one that hangs down from it,
///       which is the whole of what makes a bough out of a tree.
function corridor_draw_prop(_v, _spr, _rim, _frame, _z, _wx, _wh, _flip,
                            _col, _rim_col, _a, _rim_a, _aspect = 1,
                            _anchor = CORRIDOR_CAM_H, _yflip = 1) {
    var _k = corridor_k(_z);
    // The camera's own lateral position is subtracted in *world* space, so
    // the shift a prop gets is `_k` of it -- which is parallax, and is the
    // same arithmetic that already put the prop on the screen.
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

/// @desc How wide a prop of height `_wh` is in the world, at its own size.
///
///       **Placement has to know this**, because what matters about where a
///       trunk stands is where its *inner edge* is, not where its middle is --
///       and once a prop carries its own width the two stop being the same
///       question. See `grove_make_trunk`.
function corridor_prop_half_w(_spr, _wh, _scale, _aspect) {
    return _wh * _scale * _aspect * 0.5
           * sprite_get_width(_spr) / sprite_get_height(_spr);
}

/// @desc Draw the ground as bands of colour read off the projection.
///
///       **The floor of a corridor is free**, and that is worth spelling out
///       because it looks like the expensive part. Every screen row below the
///       horizon *is* a depth -- `corridor_depth_at` inverts the projection in
///       one divide -- so a stripe pattern in z, evaluated per row, comes out
///       on screen already perspective-correct: bunched to nothing at the
///       vanishing point, stretched under the camera, and rushing toward the
///       player at exactly the rate everything else in the scene is. It is one
///       triangle strip of about forty rows, and it is the single cheapest
///       thing in this stage.
///
///       `_shade` is called with `(bg, z, out, step)` and writes the colour
///       and the alpha of the ground at that depth into `out`. **It writes
///       rather than returning**, because a struct returned per row is one
///       allocation a row a frame for a number and a colour.
///
///       **`step` is how many world units this row covers**, and it is handed
///       over rather than being the shade's problem because only the drawer
///       knows it. Anything periodic in depth has to fade out once its period
///       is smaller than a row -- otherwise it is being point-sampled below
///       its own Nyquist rate, and what that draws is not a fine pattern, it
///       is a coarse one that crawls and flickers as the camera moves. It is
///       the oldest artefact in perspective rendering and the reason mip maps
///       exist; there is no texture here to mip, so the fade is done in the
///       function that makes the pattern.
function corridor_draw_ground(_v, _b, _shade, _out, _rows = 90) {
    var _hy = corridor_horizon(_v);
    var _y0 = _hy + 2;
    if (_y0 >= _v.y1) return;

    var _row = (_v.y1 - _y0) / _rows;
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _rows; _i++) {
        // **Stepped in screen y, not in z.** Uniform in z spends nearly every
        // row in the last few pixels above the horizon and leaves the whole
        // near floor as one flat band; uniform in screen y is uniform in 1/z,
        // which is where the picture actually lives.
        var _sy = _y0 + (_v.y1 - _y0) * (_i / _rows);
        var _z = corridor_depth_at(_v, _sy);
        // How deep this row is, in world units. The projection compresses
        // hard toward the horizon, so the top row of the strip can be a
        // thousand units deep where the bottom one is twenty.
        var _step = abs(corridor_depth_at(_v, _sy + _row) - _z);
        _shade(_b, _z, _out, _step);
        draw_vertex_colour(_v.x0, _sy, _out.col, _out.a);
        draw_vertex_colour(_v.x1, _sy, _out.col, _out.a);
    }
    draw_primitive_end();
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A band drawn across the view and wrapped horizontally.
///
///       The far treeline, the canopy and the mist are all one sprite the
///       width of the field drifting sideways for ever. Two draws, and the
///       offset is folded into `[0, w)` the way `bg_offset` folds the
///       parallax stack's -- **`mod` on a negative answers a negative in
///       GML**, and a negative offset here is a band of nothing down one side
///       of the screen.
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

/// @desc How far down a wave band's baseline has dropped, `_u` along its own
///       tile.
///
///       **Downward only, and periodic in the tile.** Both halves are
///       load-bearing and neither is obvious.
///
///       Downward, because the bands this displaces stand *on* the horizon:
///       the far wood's foot is drawn at the vanishing point and the ground
///       is painted over the top of it, so a slice lifted even slightly shows
///       a band of sky underneath the wood. Every term below is a raised
///       cosine, which is in `[0, 1]` by construction rather than by being
///       clamped -- a clamp would hide a sign error rather than make one
///       impossible.
///
///       Periodic, because the band it is displacing is tiled: a displacement
///       with any other period would put a step at every tile seam, which is
///       the defect `fbm_field`'s `wrap_y` exists to prevent one dimension
///       over. So the harmonics are whole multiples of the tile and nothing
///       else, and `test_corridor` checks the two ends agree.
function corridor_band_wave(_u, _amp, _seed) {
    return _amp * ((0.5 - 0.5 * dcos(_u * 360)) * 0.54
                   + (0.5 - 0.5 * dcos(_u * 720 + _seed)) * 0.30
                   + (0.5 - 0.5 * dcos(_u * 1440 + _seed * 2)) * 0.16);
}

/// @desc The same band, with its baseline undulating -- drawn as one textured
///       triangle strip per tile.
///
///       **A ruled horizontal line at the vanishing point is the single most
///       generated-looking thing a corridor can have**, and the far wood was
///       one: a band sprite drawn at one y is a wood standing on a spirit
///       level. It was reported exactly that way -- the horizon looking
///       unnaturally flat -- and the fix is not more raggedness in the art,
///       because the art is already ragged. It is that the *ground the wood
///       stands on* is not level either.
///
///       **It was drawn in slices first, and that shipped a row of glitchy
///       vertical lines across the moon.** Forty-eight `draw_sprite_part_ext`
///       calls a tile, each dropped by the wave and each drawn a pixel wider
///       than its share on the reasoning that a seam between two slices is a
///       hairline of whatever is behind it. That reasoning holds for an
///       opaque sprite and is exactly wrong for a translucent one: the extra
///       pixel is a column the band is *blended twice* in, so every slice
///       boundary of a layer at 17 per cent became a one-pixel line at 31.
///       The far wood's foot is ramped translucent and the mist bank is
///       translucent everywhere, and both lie across the bottom of the moon
///       -- the brightest thing in the picture, which is where a doubled
///       column shows most. Each slice also sat at its own height, so every
///       boundary was a step as well as a line.
///
///       **A strip has neither failure, by construction.** Neighbouring
///       columns share their vertices, so there is no overlap to blend twice
///       and no gap to show through, and the wave is interpolated between
///       columns rather than held flat across a slice, so there is no step.
///       It is the answer `laser_draw_curve` declined as more than a curved
///       laser needed, and it is the right one here because the thing being
///       bent is a picture rather than a glow.
///
///       Four details make it hold:
///
///       - **Its texture coordinates run 0 to 1 across the sprite, not
///         across the texture page -- and that was measured, because the
///         first version assumed the other.** `sprite_get_uvs` answers in
///         page space, and it is the obvious thing to feed a primitive; in
///         this runtime a primitive textured with `sprite_get_texture` reads
///         its coordinates in the *sprite's* space instead. Fed page
///         coordinates, the strip drew the top-left patch of each sprite
///         stretched across the whole band: the treeline became a few blocky
///         trunks and the hedgerow became half a dozen isolated tall bumps
///         with their feet cut off flat, which is why a hedge that was solid
///         in its own art could not be found on the screen. It was pinned
///         down by drawing one quad both ways beside `draw_sprite_ext`, and
///         `test_band_strip` now does that comparison on a surface every run,
///         because a runtime that changes its mind about this again would
///         otherwise say so only in a screenshot.
///       - **The trim still places it.** GameMaker crops a sprite's empty
///         border when it packs it and `sprite_get_uvs` says by how much, so
///         the strip is laid over the part that was kept rather than over
///         the rectangle that was drawn.
///       - **Half a texel in from every edge.** Bilinear sampling exactly on
///         the edge of a packed sprite blends in whatever is beside it on the
///         page, and at a tile seam that is a one-pixel line of somebody
///         else's art -- this bug again, one level down. Inset, the seam
///         samples the last column and then the first, which are neighbours
///         because the band tiles.
///       - **`_dip` squashes the band toward its own foot** either side of the
///         view's centre line, by up to that share of its height, eased over
///         `_dip_w` pixels. A band standing on the ground across the whole
///         width of a corridor is a wall at the end of it; one that dips
///         where the path runs into it is undergrowth with a track through
///         it. It follows the camera because `cx` does.
function corridor_draw_band_wave(_v, _spr, _drift, _sy, _sc, _col, _a,
                                 _amp, _seed, _dip = 0, _dip_w = 1) {
    if (_a <= 0.004) return;
    var _tw = sprite_get_width(_spr);
    var _th = sprite_get_height(_spr);
    var _uv = sprite_get_uvs(_spr, 0);
    var _tex = sprite_get_texture(_spr, 0);

    // The part of the sprite that survived packing, in its own pixels. Only
    // the trim is read off `_uv`; its first four entries are page space, and
    // the strip does not want page space. See above.
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

/// @desc How much a band is squashed at screen x `_px`: one on the view's
///       centre line, nothing beyond `_w` either side of it, and a smoothstep
///       between -- a linear ramp would put a visible corner in the crown of
///       the hedge at both ends of the dip.
function corridor_band_dip(_v, _px, _w) {
    var _g = clamp(1 - abs(_px - _v.cx) / max(1, _w), 0, 1);
    return _g * _g * (3 - 2 * _g);
}
